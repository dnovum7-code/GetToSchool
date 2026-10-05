--!strict
-- Einfache Bildschirmanzeige, komplett per Skript erzeugt (keine fertigen GUI-Assets noetig).
-- Unity-Vergleich: ein Canvas (ScreenGui) mit Text-Elementen (TextLabel).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local RaceUI = {}

local gui: ScreenGui
local messageLabel: TextLabel
local subMessageLabel: TextLabel
local timerLabel: TextLabel
local bestLabel: TextLabel
local speedLabel: TextLabel
local speedometer: Frame
local kmhLabel: TextLabel
local speedBarFill: Frame
local messageToken = 0

local function makeLabel(props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	for key, value in props do
		(label :: any)[key] = value
	end
	label.Parent = gui
	return label
end

function RaceUI.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "RaceUI"
	gui.ResetOnSpawn = false -- bleibt bei Respawn bestehen
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Grosse Meldung in der Mitte (CRASH!, ZIEL!)
	messageLabel = makeLabel({
		Name = "Message",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromScale(0.6, 0.12),
		Text = "",
		Visible = false,
	})
	subMessageLabel = makeLabel({
		Name = "SubMessage",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.5, 0.05),
		Text = "",
		Visible = false,
	})

	-- Zeit oben in der Mitte, Bestzeit darunter
	timerLabel = makeLabel({
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 50),
		Size = UDim2.new(0, 220, 0, 48),
		Font = Enum.Font.Code,
		Text = RaceUI.formatTime(0),
	})
	bestLabel = makeLabel({
		Name = "Best",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.new(0, 220, 0, 22),
		Font = Enum.Font.Gotham,
		Text = "",
		TextColor3 = Color3.fromRGB(255, 220, 120),
	})

	-- Tempo unten rechts (hilft beim Tunen)
	speedLabel = makeLabel({
		Name = "Speed",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -40),
		Size = UDim2.new(0, 160, 0, 36),
		Font = Enum.Font.Code,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = Config.UI.ShowSpeed,
	})

	-- Tacho unten in der Mitte: Zahl in km/h und ein Balken
	speedometer = Instance.new("Frame")
	speedometer.Name = "Speedometer"
	speedometer.AnchorPoint = Vector2.new(0.5, 1)
	speedometer.Position = UDim2.new(0.5, 0, 1, -38)
	speedometer.Size = UDim2.new(0, 220, 0, 58)
	speedometer.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	speedometer.BackgroundTransparency = 0.4
	speedometer.Visible = false
	speedometer.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = speedometer

	kmhLabel = makeLabel({
		Name = "Kmh",
		Position = UDim2.new(0, 10, 0, 4),
		Size = UDim2.new(1, -20, 0, 34),
		Font = Enum.Font.Code,
		Text = "0 km/h",
	})
	kmhLabel.Parent = speedometer

	local barBackground = Instance.new("Frame")
	barBackground.Name = "Bar"
	barBackground.Position = UDim2.new(0, 10, 1, -14)
	barBackground.Size = UDim2.new(1, -20, 0, 8)
	barBackground.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	barBackground.BorderSizePixel = 0
	barBackground.Parent = speedometer
	speedBarFill = Instance.new("Frame")
	speedBarFill.Name = "Fill"
	speedBarFill.Size = UDim2.fromScale(0, 1)
	speedBarFill.BorderSizePixel = 0
	speedBarFill.Parent = barBackground

	-- Steuerungshilfe unten
	makeLabel({
		Name = "Help",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(0.6, 0, 0, 22),
		Font = Enum.Font.Gotham,
		Text = "W/S: Anschieben/Bremsen   A/D: Lenken   Shift: Drift   E: Aus-/Einsteigen   R: Neustart",
		TextTransparency = 0.2,
	})
end

-- Zeigt eine grosse Meldung fuer `duration` Sekunden (nil = bis zum naechsten Aufruf).
function RaceUI.showMessage(text: string, color: Color3, subText: string?, duration: number?)
	messageToken += 1
	local token = messageToken
	messageLabel.Text = text
	messageLabel.TextColor3 = color
	messageLabel.Visible = true
	subMessageLabel.Text = subText or ""
	subMessageLabel.Visible = subText ~= nil
	if duration then
		task.delay(duration, function()
			if messageToken == token then
				RaceUI.hideMessage()
			end
		end)
	end
end

function RaceUI.formatTime(seconds: number): string
	return string.format("%.2f s", seconds)
end

function RaceUI.setTimer(seconds: number)
	timerLabel.Text = RaceUI.formatTime(seconds)
end

-- Lauf ungueltig (z. B. ausgestiegen)
function RaceUI.setTimerInvalid()
	timerLabel.Text = "--.-- s"
end

function RaceUI.setBest(seconds: number?)
	bestLabel.Text = if seconds then "Bestzeit: " .. RaceUI.formatTime(seconds) else ""
end

-- Tempo in Studs pro Sekunde: Tacho (km/h) und kleine Studs-Anzeige aktualisieren
function RaceUI.setSpeed(speed: number)
	speedLabel.Text = string.format("%d studs/s", math.floor(speed + 0.5))
	local kmh = speed * Config.UI.StudsToMeters * 3.6
	kmhLabel.Text = string.format("%d km/h", math.floor(kmh + 0.5))
	local fill = math.clamp(kmh / Config.UI.SpeedometerMaxKmh, 0, 1)
	speedBarFill.Size = UDim2.fromScale(fill, 1)
	-- gruen -> gelb -> rot
	speedBarFill.BackgroundColor3 = Color3.fromHSV(0.33 * (1 - fill), 0.85, 0.95)
end

-- Tacho nur zeigen, solange man faehrt
function RaceUI.setSpeedometerVisible(visible: boolean)
	speedometer.Visible = visible
	speedLabel.Visible = visible and Config.UI.ShowSpeed
end

function RaceUI.hideMessage()
	messageToken += 1
	messageLabel.Visible = false
	subMessageLabel.Visible = false
end

return RaceUI
