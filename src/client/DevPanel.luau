--!strict
-- Tuning-Panel fuer die Entwicklung: nur in Studio, mit F2 ein-/ausblenden.
-- Inhalt: Config.TuningPanel - Abschnitte mit Titel (Klick auf den Titel klappt ein/aus).
--
-- Regler: starten in der MITTE; die Mitte ist der Wert beim Spielstart (aus Config.luau).
-- Bereich: 0 bis doppelter Startwert (oder Startwert +/- span). Pro Regler: Wert als Zahl,
-- Eingabefeld fuer einen genauen Wert (auch ausserhalb des Bereichs), Knopf "R" = zurueck.
-- Schalter: An/Aus-Knopf fuer true/false-Werte (z. B. God Mode, Crash aus).
-- "Werte kopieren" schreibt nur die geaenderten Regler-Werte ins Output-Fenster, z. B.
--   Drift.LateralGrip: 3.5 -> 4.2
--
-- Aenderungen gelten auf diesem Client sofort (das Fahrskript liest die Config jeden Frame).
-- Eintraege mit server = true gehen zusaetzlich an den Server (server/DevTuning).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local DevPanel = {}

local PANEL_WIDTH = 360
local SLIDER_HEIGHT = 50
local SWITCH_HEIGHT = 32

type Item = Config.TuningItem

type Slider = {
	item: Item,
	holder: any, -- Tabelle in der Config, die den Wert enthaelt
	key: string,
	base: number, -- Wert beim Spielstart = Mitte des Reglers
	low: number,
	high: number,
	decimals: number,
	bar: Frame,
	fill: Frame,
	valueLabel: TextLabel,
}

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

local CHANGED_COLOR = Color3.fromRGB(255, 220, 110)
local NORMAL_COLOR = Color3.new(1, 1, 1)

local function refreshSlider(slider: Slider)
	local value = slider.holder[slider.key] :: number
	slider.valueLabel.Text = formatNumber(value, slider.decimals)
	-- geaenderte Werte gelb, damit man sieht, was vom Config-Wert abweicht
	slider.valueLabel.TextColor3 = if value ~= slider.base then CHANGED_COLOR else NORMAL_COLOR
	local alpha = if slider.high > slider.low then (value - slider.low) / (slider.high - slider.low) else 0.5
	slider.fill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
end

-- Nur geaenderte Werte ausgeben: "Abschnitt.Name: alt -> neu"
local function printChanges(sliders: { Slider })
	local lines = { "", "-- Geaenderte Tuning-Werte (in src/shared/Config.luau uebernehmen):" }
	for _, slider in sliders do
		local value = slider.holder[slider.key] :: number
		if value ~= slider.base then
			table.insert(
				lines,
				`{slider.item.path}: {formatNumber(slider.base, 6)} -> {formatNumber(
					value,
					slider.decimals + 1
				)}`
			)
		end
	end
	if #lines == 2 then
		table.insert(lines, "Keine Aenderungen.")
	end
	print(table.concat(lines, "\n"))
end

function DevPanel.init()
	if not RunService:IsStudio() then
		return
	end
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DevTuning") :: RemoteEvent
	local sections = (Config :: any).TuningPanel :: { Config.TuningSection }

	local gui = Instance.new("ScreenGui")
	gui.Name = "DevTuningPanel"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = 10

	local panel = Instance.new("ScrollingFrame")
	panel.Name = "Panel"
	panel.Position = UDim2.new(0, 16, 0, 100)
	panel.Size = UDim2.new(0, PANEL_WIDTH + 12, 1, -120)
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panel.CanvasSize = UDim2.new()
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
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = panel

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	makeText(panel, {
		LayoutOrder = nextOrder(),
		Size = UDim2.new(0, PANEL_WIDTH, 0, 24),
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		Text = "Tuning (F2)  -  Mitte = Config-Wert",
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local sliders: { Slider } = {}

	local function applyValue(slider: Slider, value: number)
		slider.holder[slider.key] = value
		refreshSlider(slider)
		if slider.item.server then
			remote:FireServer(slider.item.path, value)
		end
	end

	local function addSwitch(parent: Instance, item: Item, holder: any, key: string)
		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.new(0, PANEL_WIDTH, 0, SWITCH_HEIGHT)
		frame.LayoutOrder = nextOrder()
		frame.Parent = parent
		makeText(frame, {
			Position = UDim2.new(0, 4, 0, 4),
			Size = UDim2.new(0, PANEL_WIDTH - 90, 0, 22),
			Text = item.label,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local toggle = makeButton(frame, {
			Position = UDim2.new(0, PANEL_WIDTH - 80, 0, 3),
			Size = UDim2.new(0, 70, 0, 26),
		})
		local function show()
			local value = holder[key] == true
			local on = if item.invert then not value else value
			toggle.Text = if on then "An" else "Aus"
			toggle.BackgroundColor3 = if on then Color3.fromRGB(60, 150, 80) else Color3.fromRGB(150, 60, 60)
		end
		show()
		toggle.Activated:Connect(function()
			holder[key] = not holder[key]
			show()
			if item.server then
				remote:FireServer(item.path, holder[key])
			end
		end)
	end

	local function addSlider(parent: Instance, item: Item, holder: any, key: string)
		local base = holder[key] :: number
		-- Bereich: Mitte = Startwert; Standard 0 .. doppelter Wert. Eine untere Grenze (min)
		-- verkleinert den Bereich symmetrisch, damit der Startwert in der Mitte bleibt.
		local minBound = item.min or 0
		local span = item.span or math.abs(base)
		span = math.min(span, base - minBound)
		local low, high
		if span > 0 then
			low, high = base - span, base + span
		else
			-- Startwert 0 (bzw. = min): Mitte geht nicht, Bereich min .. min + span (Standard 1)
			span = item.span or 1
			low, high = minBound, minBound + span
		end

		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.new(0, PANEL_WIDTH, 0, SLIDER_HEIGHT)
		frame.LayoutOrder = nextOrder()
		frame.Parent = parent
		makeText(frame, {
			Position = UDim2.new(0, 4, 0, 2),
			Size = UDim2.new(0, PANEL_WIDTH - 110, 0, 18),
			Text = item.label,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local valueLabel = makeText(frame, {
			Position = UDim2.new(0, PANEL_WIDTH - 100, 0, 2),
			Size = UDim2.new(0, 88, 0, 18),
			Font = Enum.Font.Code,
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local bar = Instance.new("Frame")
		bar.Position = UDim2.new(0, 4, 0, 28)
		bar.Size = UDim2.new(0, PANEL_WIDTH - 124, 0, 10)
		bar.BackgroundColor3 = Color3.fromRGB(70, 70, 85)
		bar.BorderSizePixel = 0
		bar.Active = true
		bar.Parent = frame
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
		input.Position = UDim2.new(0, PANEL_WIDTH - 110, 0, 22)
		input.Size = UDim2.new(0, 64, 0, 22)
		input.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
		input.TextColor3 = Color3.new(1, 1, 1)
		input.PlaceholderText = "Wert"
		input.PlaceholderColor3 = Color3.fromRGB(150, 150, 165)
		input.Font = Enum.Font.Code
		input.TextSize = 14
		input.Text = ""
		input.ClearTextOnFocus = true
		input.Parent = frame
		local reset = makeButton(frame, {
			Position = UDim2.new(0, PANEL_WIDTH - 40, 0, 22),
			Size = UDim2.new(0, 26, 0, 22),
			BackgroundColor3 = Color3.fromRGB(90, 70, 70),
			Text = "R",
		})
		local slider: Slider = {
			item = item,
			holder = holder,
			key = key,
			base = base,
			low = low,
			high = high,
			decimals = decimalsFor(span),
			bar = bar,
			fill = fill,
			valueLabel = valueLabel,
		}
		table.insert(sliders, slider)
		refreshSlider(slider)
		input.FocusLost:Connect(function()
			-- Komma oder Punkt als Dezimaltrenner erlauben
			local value = tonumber((string.gsub(input.Text, ",", ".")))
			input.Text = ""
			if value and value == value and math.abs(value) < 1e6 then
				applyValue(slider, value)
			end
		end)
		reset.Activated:Connect(function()
			applyValue(slider, slider.base)
		end)
	end

	-- Abschnitte: Titelzeile (Klick = ein-/ausklappen) und Inhalt
	for _, section in sections do
		local header = makeButton(panel, {
			LayoutOrder = nextOrder(),
			Size = UDim2.new(0, PANEL_WIDTH, 0, 28),
			BackgroundColor3 = Color3.fromRGB(55, 60, 80),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 15,
		})
		local body = Instance.new("Frame")
		body.BackgroundTransparency = 1
		body.Size = UDim2.new(0, PANEL_WIDTH, 0, 0)
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.LayoutOrder = nextOrder()
		body.Visible = section.open == true
		body.Parent = panel
		local bodyLayout = Instance.new("UIListLayout")
		bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
		bodyLayout.Padding = UDim.new(0, 2)
		bodyLayout.Parent = body
		local function showHeader()
			header.Text = `  {if body.Visible then "▼" else "▶"}  {section.title}  ({#section.items})`
		end
		showHeader()
		header.Activated:Connect(function()
			body.Visible = not body.Visible
			showHeader()
		end)
		for _, item in section.items do
			local holder, key = resolvePath(item.path)
			if not holder or not key then
				warn(`[DevPanel] Unbekannter Config-Wert "{item.path}" in Config.TuningPanel`)
				continue
			end
			if item.switch then
				if type(holder[key]) ~= "boolean" then
					warn(`[DevPanel] "{item.path}" ist kein true/false-Wert`)
					continue
				end
				addSwitch(body, item, holder, key)
			else
				if type(holder[key]) ~= "number" then
					warn(`[DevPanel] "{item.path}" ist keine Zahl`)
					continue
				end
				addSlider(body, item, holder, key)
			end
		end
	end

	local copyButton = makeButton(panel, {
		Name = "CopyValues",
		LayoutOrder = nextOrder(),
		Size = UDim2.new(0, PANEL_WIDTH, 0, 30),
		BackgroundColor3 = Color3.fromRGB(60, 130, 80),
		Text = "Werte kopieren (nur Aenderungen, ins Output)",
	})
	copyButton.Activated:Connect(function()
		printChanges(sliders)
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Ziehen: Klick auf einen Balken startet, Mausbewegung aendert den Wert
	local dragging: Slider? = nil

	local function setFromScreenX(slider: Slider, x: number)
		local alpha = math.clamp((x - slider.bar.AbsolutePosition.X) / slider.bar.AbsoluteSize.X, 0, 1)
		local value = round(slider.low + alpha * (slider.high - slider.low), slider.decimals)
		if value ~= slider.holder[slider.key] then
			applyValue(slider, value)
		end
	end

	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end

	for _, slider in sliders do
		slider.bar.InputBegan:Connect(function(input)
			if isPress(input) then
				dragging = slider
				setFromScreenX(slider, input.Position.X)
			end
		end)
	end

	UserInputService.InputChanged:Connect(function(input)
		local slider = dragging
		if
			slider
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			setFromScreenX(slider, input.Position.X)
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
			for _, slider in sliders do
				refreshSlider(slider)
			end
		end
	end)
end

return DevPanel
