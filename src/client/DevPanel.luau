--!strict
-- Tuning-Panel fuer die Entwicklung: nur in Studio, mit F2 ein-/ausblenden.
-- Welche Werte erscheinen, steht in Config.TuningPanel.
--
-- Jeder Regler startet in der MITTE; die Mitte ist der Wert beim Spielstart (aus Config.luau).
-- Bereich: 0 bis doppelter Startwert (oder Startwert +/- span, siehe Config.TuningPanel).
-- Pro Regler: aktueller Wert als Zahl, Eingabefeld fuer einen genauen Wert (auch ausserhalb
-- des Reglerbereichs) und ein Knopf zum Zuruecksetzen auf den Startwert.
-- "Werte kopieren" schreibt nur die geaenderten Werte ins Output-Fenster, z. B.
--   Drift.LateralGrip: 3.5 -> 4.2
--
-- Die Regler aendern die Config-Werte dieses Clients sofort (das Fahrskript liest sie jeden
-- Frame). Werte mit server = true gehen zusaetzlich an den Server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local DevPanel = {}

local ROW_HEIGHT = 50
local PANEL_WIDTH = 340

type Entry = {
	label: string,
	path: string, -- "Abschnitt.Name" (auch tiefer: "Vehicles.OfficeChair.scale.Drive.SteerRate")
	span: number?,
	min: number?,
	server: boolean?,
}

type Row = {
	entry: Entry,
	holder: any, -- Tabelle in der Config, die den Wert enthaelt
	key: string,
	base: number, -- Wert beim Spielstart = Mitte des Reglers
	low: number,
	high: number,
	decimals: number,
	bar: Frame,
	fill: Frame,
	valueLabel: TextLabel,
	input: TextBox,
}

local function getValue(row: Row): number
	return row.holder[row.key] :: number
end

local function setConfigValue(row: Row, value: number)
	row.holder[row.key] = value
end

-- "A.B.C" -> Tabelle Config.A.B und Schluessel "C" (nil, wenn es den Weg nicht gibt)
local function resolvePath(path: string): (any, string?)
	local parts = string.split(path, ".")
	if #parts < 2 then
		return nil, nil
	end
	local holder: any = Config
	for i = 1, #parts - 1 do
		holder = if type(holder) == "table" then holder[parts[i]] else nil
	end
	if type(holder) ~= "table" then
		return nil, nil
	end
	return holder, parts[#parts]
end

-- Sinnvolle Nachkommastellen fuer einen Bereich: 45 -> 1, 2 -> 2, 0.003 -> 5
local function decimalsFor(span: number): number
	if span <= 0 then
		return 2
	end
	return math.clamp(2 - math.floor(math.log10(span)), 0, 6)
end

local function round(value: number, decimals: number): number
	local factor = 10 ^ decimals
	return math.round(value * factor) / factor
end

-- Zahl ohne ueberfluessige Nullen: 3.50 -> "3.5", 4.00 -> "4"
local function formatNumber(value: number, decimals: number): string
	local text = string.format("%." .. decimals .. "f", value)
	if string.find(text, "%.") then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

local function makeText(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Gotham
	label.TextSize = 14
	for key, value in props do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

local CHANGED_COLOR = Color3.fromRGB(255, 220, 110)
local NORMAL_COLOR = Color3.new(1, 1, 1)

local function refreshRow(row: Row)
	local value = getValue(row)
	row.valueLabel.Text = formatNumber(value, row.decimals)
	-- geaenderte Werte gelb, damit man sieht, was vom Config-Wert abweicht
	row.valueLabel.TextColor3 = if value ~= row.base then CHANGED_COLOR else NORMAL_COLOR
	local alpha = if row.high > row.low then (value - row.low) / (row.high - row.low) else 0.5
	row.fill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
end

-- Nur geaenderte Werte ausgeben: "Abschnitt.Name: alt -> neu"
local function printChanges(rows: { Row })
	local lines = { "", "-- Geaenderte Tuning-Werte (in src/shared/Config.luau uebernehmen):" }
	for _, row in rows do
		local value = getValue(row)
		if value ~= row.base then
			table.insert(
				lines,
				`{row.entry.path}: {formatNumber(row.base, 6)} -> {formatNumber(value, row.decimals + 1)}`
			)
		end
	end
	if #lines == 2 then
		table.insert(lines, "Keine Aenderungen.")
	end
	print(table.concat(lines, "\n"))
end

local function makeButton(parent: Instance, props: { [string]: any }): TextButton
	local button = Instance.new("TextButton")
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.AutoButtonColor = true
	for key, value in props do
		(button :: any)[key] = value
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = button
	button.Parent = parent
	return button
end

function DevPanel.init()
	if not RunService:IsStudio() then
		return
	end
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DevTuning") :: RemoteEvent
	local entries = (Config :: any).TuningPanel :: { Entry }

	local gui = Instance.new("ScreenGui")
	gui.Name = "DevTuningPanel"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = 10

	-- Scrollbar, damit auch viele Regler auf kleine Bildschirme passen
	local contentHeight = 44 + ROW_HEIGHT * #entries + 48
	local panel = Instance.new("ScrollingFrame")
	panel.Name = "Panel"
	panel.Position = UDim2.new(0, 16, 0, 100)
	panel.Size = UDim2.new(0, PANEL_WIDTH + 8, 1, -120)
	panel.CanvasSize = UDim2.new(1, 0, 0, contentHeight)
	panel.ScrollingDirection = Enum.ScrollingDirection.Y
	panel.ScrollBarThickness = 6
	panel.BorderSizePixel = 0
	panel.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	panel.BackgroundTransparency = 0.15
	panel.Active = true -- Klicks gehen nicht durch das Panel in die Welt
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel

	makeText(panel, {
		Position = UDim2.new(0, 12, 0, 8),
		Size = UDim2.new(0, PANEL_WIDTH - 24, 0, 24),
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		Text = "Tuning (F2)  -  Mitte = Config-Wert",
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local rows: { Row } = {}

	local function applyValue(row: Row, value: number)
		setConfigValue(row, value)
		refreshRow(row)
		if row.entry.server then
			remote:FireServer(row.entry.path, value)
		end
	end

	for index, entry in entries do
		local holder, key = resolvePath(entry.path)
		if not holder or not key or type(holder[key]) ~= "number" then
			warn(`[DevPanel] Unbekannter Config-Wert "{entry.path}" in Config.TuningPanel`)
			continue
		end
		local base = holder[key] :: number
		-- Bereich: Mitte = Startwert; Standard 0 .. doppelter Wert. Eine untere Grenze (min)
		-- verkleinert den Bereich symmetrisch, damit der Startwert in der Mitte bleibt.
		local minBound = entry.min or 0
		local span = entry.span or math.abs(base)
		span = math.min(span, base - minBound)
		local low, high
		if span > 0 then
			low, high = base - span, base + span
		else
			-- Startwert 0 (bzw. = min): Mitte geht nicht, Bereich min .. min + span (Standard 1)
			span = entry.span or 1
			low, high = minBound, minBound + span
		end

		local y = 44 + (index - 1) * ROW_HEIGHT
		makeText(panel, {
			Position = UDim2.new(0, 12, 0, y),
			Size = UDim2.new(0, PANEL_WIDTH - 110, 0, 18),
			Text = entry.label,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local valueLabel = makeText(panel, {
			Position = UDim2.new(0, PANEL_WIDTH - 100, 0, y),
			Size = UDim2.new(0, 88, 0, 18),
			Font = Enum.Font.Code,
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Right,
		})

		local bar = Instance.new("Frame")
		bar.Position = UDim2.new(0, 12, 0, y + 26)
		bar.Size = UDim2.new(0, PANEL_WIDTH - 130, 0, 10)
		bar.BackgroundColor3 = Color3.fromRGB(70, 70, 85)
		bar.BorderSizePixel = 0
		bar.Active = true
		bar.Parent = panel
		local fill = Instance.new("Frame")
		fill.BackgroundColor3 = Color3.fromRGB(90, 170, 255)
		fill.BorderSizePixel = 0
		fill.Parent = bar
		-- Markierung in der Mitte (= Config-Wert)
		local middle = Instance.new("Frame")
		middle.AnchorPoint = Vector2.new(0.5, 0)
		middle.Position = UDim2.new(0.5, 0, 0, -3)
		middle.Size = UDim2.new(0, 2, 1, 6)
		middle.BackgroundColor3 = Color3.new(1, 1, 1)
		middle.BorderSizePixel = 0
		middle.ZIndex = 2
		middle.Parent = bar

		-- Eingabefeld fuer einen genauen Wert
		local input = Instance.new("TextBox")
		input.Position = UDim2.new(0, PANEL_WIDTH - 110, 0, y + 20)
		input.Size = UDim2.new(0, 64, 0, 22)
		input.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
		input.TextColor3 = Color3.new(1, 1, 1)
		input.PlaceholderText = "Wert"
		input.PlaceholderColor3 = Color3.fromRGB(150, 150, 165)
		input.Font = Enum.Font.Code
		input.TextSize = 14
		input.Text = ""
		input.ClearTextOnFocus = true
		input.Parent = panel

		-- Zuruecksetzen auf den Config-Wert
		local reset = makeButton(panel, {
			Position = UDim2.new(0, PANEL_WIDTH - 38, 0, y + 20),
			Size = UDim2.new(0, 26, 0, 22),
			BackgroundColor3 = Color3.fromRGB(90, 70, 70),
			Text = "R",
		})

		local row: Row = {
			entry = entry,
			holder = holder,
			key = key,
			base = base,
			low = low,
			high = high,
			decimals = decimalsFor(span),
			bar = bar,
			fill = fill,
			valueLabel = valueLabel,
			input = input,
		}
		table.insert(rows, row)
		refreshRow(row)

		input.FocusLost:Connect(function()
			-- Komma oder Punkt als Dezimaltrenner erlauben
			local value = tonumber((string.gsub(input.Text, ",", ".")))
			input.Text = ""
			if value and value == value and math.abs(value) < 1e6 then
				applyValue(row, value)
			end
		end)
		reset.Activated:Connect(function()
			applyValue(row, row.base)
		end)
	end

	local copyButton = makeButton(panel, {
		Name = "CopyValues",
		Position = UDim2.new(0, 12, 0, contentHeight - 40),
		Size = UDim2.new(0, PANEL_WIDTH - 24, 0, 30),
		BackgroundColor3 = Color3.fromRGB(60, 130, 80),
		Text = "Werte kopieren (nur Aenderungen, ins Output)",
	})
	copyButton.Activated:Connect(function()
		printChanges(rows)
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Ziehen: Klick auf einen Balken startet, Mausbewegung aendert den Wert
	local dragging: Row? = nil

	local function setFromScreenX(row: Row, x: number)
		local alpha = math.clamp((x - row.bar.AbsolutePosition.X) / row.bar.AbsoluteSize.X, 0, 1)
		local value = round(row.low + alpha * (row.high - row.low), row.decimals)
		if value ~= getValue(row) then
			applyValue(row, value)
		end
	end

	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end

	for _, row in rows do
		row.bar.InputBegan:Connect(function(input)
			if isPress(input) then
				dragging = row
				setFromScreenX(row, input.Position.X)
			end
		end)
	end

	UserInputService.InputChanged:Connect(function(input)
		local row = dragging
		if
			row
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			setFromScreenX(row, input.Position.X)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if isPress(input) then
			dragging = nil
		end
	end)

	-- F2: ein-/ausblenden (Werte beim Oeffnen auffrischen)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or input.KeyCode ~= Enum.KeyCode.F2 then
			return
		end
		gui.Enabled = not gui.Enabled
		if gui.Enabled then
			for _, row in rows do
				refreshRow(row)
			end
		end
	end)
end

return DevPanel
