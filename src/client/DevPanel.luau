--!strict
-- Tuning-Panel fuer die Entwicklung: nur in Studio, mit F2 ein-/ausblenden.
-- Die Schieberegler aendern die Config-Werte dieses Clients sofort (das Fahrskript liest
-- sie jeden Frame). Werte, die der Server braucht (Ballast), gehen zusaetzlich an den Server.
-- "Werte kopieren" schreibt die aktuellen Werte als Config-Code ins Output-Fenster.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local TuningSliders = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TuningSliders"))

local DevPanel = {}

local ROW_HEIGHT = 40 -- kompakt, damit alle Regler auf den Bildschirm passen
local PANEL_WIDTH = 300

type Row = {
	slider: TuningSliders.Slider,
	bar: Frame,
	fill: Frame,
	valueLabel: TextLabel,
}

local function getValue(slider: TuningSliders.Slider): number
	return ((Config :: any)[slider.section] :: any)[slider.key] :: number
end

local function setValue(slider: TuningSliders.Slider, value: number)
	local sectionTable: any = (Config :: any)[slider.section]
	sectionTable[slider.key] = value
end

-- Anzahl Nachkommastellen passend zur Schrittweite (0.05 -> 2, 0.0005 -> 4)
local function decimalsFor(step: number): number
	if step >= 1 then
		return 0
	end
	return math.ceil(-math.log10(step) - 1e-9)
end

local function formatValue(slider: TuningSliders.Slider, value: number): string
	return string.format("%." .. decimalsFor(slider.step) .. "f", value)
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

local function refreshRow(row: Row)
	local slider = row.slider
	local value = getValue(slider)
	row.valueLabel.Text = formatValue(slider, value)
	row.fill.Size = UDim2.fromScale(math.clamp((value - slider.min) / (slider.max - slider.min), 0, 1), 1)
end

-- Gibt alle Werte als Code aus, den man in Config.luau uebernehmen kann.
local function printValues()
	local lines = { "", "-- Tuning-Werte aus dem Panel (in src/shared/Config.luau uebernehmen):" }
	local sections: { string } = {}
	local bySection: { [string]: { TuningSliders.Slider } } = {}
	for _, slider in TuningSliders do
		if not bySection[slider.section] then
			bySection[slider.section] = {}
			table.insert(sections, slider.section)
		end
		table.insert(bySection[slider.section], slider)
	end
	for _, section in sections do
		table.insert(lines, `-- in Config.{section} = {"{"} ... {"}"}:`)
		for _, slider in bySection[section] do
			table.insert(lines, `\t{slider.key} = {formatValue(slider, getValue(slider))},`)
		end
	end
	print(table.concat(lines, "\n"))
end

function DevPanel.init()
	if not RunService:IsStudio() then
		return
	end
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DevTuning") :: RemoteEvent

	local gui = Instance.new("ScreenGui")
	gui.Name = "DevTuningPanel"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = 10

	-- Scrollbar, damit auch viele Regler auf kleine Bildschirme passen
	local contentHeight = 44 + ROW_HEIGHT * #TuningSliders + 48
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
		Size = UDim2.new(1, -24, 0, 24),
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		Text = "Tuning (F2)",
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local rows: { Row } = {}
	for index, slider in TuningSliders do
		local y = 44 + (index - 1) * ROW_HEIGHT
		makeText(panel, {
			Position = UDim2.new(0, 12, 0, y),
			Size = UDim2.new(0.65, -12, 0, 18),
			Text = slider.label,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local valueLabel = makeText(panel, {
			Position = UDim2.new(0.65, 0, 0, y),
			Size = UDim2.new(0.35, -12, 0, 18),
			Font = Enum.Font.Code,
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local bar = Instance.new("Frame")
		bar.Position = UDim2.new(0, 12, 0, y + 21)
		bar.Size = UDim2.new(1, -24, 0, 10)
		bar.BackgroundColor3 = Color3.fromRGB(70, 70, 85)
		bar.BorderSizePixel = 0
		bar.Active = true
		bar.Parent = panel
		local fill = Instance.new("Frame")
		fill.BackgroundColor3 = Color3.fromRGB(90, 170, 255)
		fill.BorderSizePixel = 0
		fill.Parent = bar

		local row: Row = { slider = slider, bar = bar, fill = fill, valueLabel = valueLabel }
		table.insert(rows, row)
		refreshRow(row)
	end

	local copyButton = Instance.new("TextButton")
	copyButton.Name = "CopyValues"
	copyButton.Position = UDim2.new(0, 12, 0, contentHeight - 40)
	copyButton.Size = UDim2.new(0, PANEL_WIDTH - 24, 0, 30)
	copyButton.BackgroundColor3 = Color3.fromRGB(60, 130, 80)
	copyButton.TextColor3 = Color3.new(1, 1, 1)
	copyButton.Font = Enum.Font.GothamBold
	copyButton.TextSize = 14
	copyButton.Text = "Werte kopieren (ins Output-Fenster)"
	copyButton.Parent = panel
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 6)
	buttonCorner.Parent = copyButton
	copyButton.Activated:Connect(printValues)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Ziehen: Klick auf einen Balken startet, Mausbewegung aendert den Wert
	local dragging: Row? = nil

	local function setFromScreenX(row: Row, x: number)
		local slider = row.slider
		local alpha = math.clamp((x - row.bar.AbsolutePosition.X) / row.bar.AbsoluteSize.X, 0, 1)
		local value = slider.min + alpha * (slider.max - slider.min)
		value = math.clamp(math.round(value / slider.step) * slider.step, slider.min, slider.max)
		if value == getValue(slider) then
			return
		end
		setValue(slider, value)
		refreshRow(row)
		if slider.server then
			remote:FireServer(slider.section, slider.key, value)
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
