--!strict
-- Einfache Bildschirmanzeige, komplett per Skript erzeugt (keine fertigen GUI-Assets noetig).
-- Unity-Vergleich: ein Canvas (ScreenGui) mit Text-Elementen (TextLabel).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local RaceTime = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RaceTime"))

local RaceUI = {}

local gui: ScreenGui
local helpLabel: TextLabel? = nil
local messageLabel: TextLabel
local subMessageLabel: TextLabel
local timerLabel: TextLabel
local bestLabel: TextLabel
local toastLabel: TextLabel
local toastToken = 0
local resultPanel: Frame
local resultTitle: TextLabel
local resultLines: TextLabel
local resultGrade: TextLabel
local resultToken = 0
local speedLabel: TextLabel
local speedometer: Frame
local kmhLabel: TextLabel
local speedBarFill: Frame
local messageToken = 0
local gameOverFrame: Frame
local gameOverTitle: TextLabel
local gameOverText: TextLabel
local gameOverInfo: TextLabel
local gameOverConnection: RBXScriptConnection? = nil

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

	-- Timer oben in der Mitte, Bestzeit darunter
	timerLabel = makeLabel({
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 50),
		Size = UDim2.new(0, 260, 0, 48),
		Font = Enum.Font.Code,
		Text = RaceTime.format(0),
	})
	bestLabel = makeLabel({
		Name = "Best",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.new(0, 260, 0, 22),
		Font = Enum.Font.Gotham,
		Text = "",
		TextColor3 = Color3.fromRGB(255, 220, 120),
	})
	-- Kurzer Hinweis unter dem Timer (z. B. "Checkpoint  -0.45")
	toastLabel = makeLabel({
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 128),
		Size = UDim2.new(0, 320, 0, 30),
		Text = "",
		TextColor3 = Color3.fromRGB(140, 230, 255),
		Visible = false,
	})

	-- Ergebnis-Screen in der Mitte
	resultPanel = Instance.new("Frame")
	resultPanel.Name = "Result"
	resultPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	resultPanel.Position = UDim2.fromScale(0.5, 0.42)
	resultPanel.Size = UDim2.new(0, 520, 0, 300)
	resultPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	resultPanel.BackgroundTransparency = 0.25
	resultPanel.Visible = false
	resultPanel.Parent = gui
	local resultCorner = Instance.new("UICorner")
	resultCorner.CornerRadius = UDim.new(0, 12)
	resultCorner.Parent = resultPanel
	resultTitle = makeLabel({
		Name = "Title",
		Position = UDim2.new(0, 16, 0, 12),
		Size = UDim2.new(1, -32, 0, 44),
		Text = "",
	})
	resultTitle.Parent = resultPanel
	resultLines = makeLabel({
		Name = "Lines",
		Position = UDim2.new(0, 20, 0, 66),
		Size = UDim2.new(1, -150, 0, 220),
		Font = Enum.Font.Gotham,
		TextScaled = false,
		TextSize = 18,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
	})
	resultLines.Parent = resultPanel
	resultGrade = makeLabel({
		Name = "Grade",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 70),
		Size = UDim2.new(0, 110, 0, 110),
		Text = "",
	})
	resultGrade.Parent = resultPanel

	-- Game-Over-Screen: dunkler Hintergrund, wackelnder Titel
	gameOverFrame = Instance.new("Frame")
	gameOverFrame.Name = "GameOver"
	gameOverFrame.Size = UDim2.fromScale(1, 1)
	gameOverFrame.BackgroundColor3 = Color3.fromRGB(30, 10, 40)
	gameOverFrame.BackgroundTransparency = 0.35
	gameOverFrame.Visible = false
	gameOverFrame.ZIndex = 5
	gameOverFrame.Parent = gui
	gameOverTitle = makeLabel({
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.33),
		Size = UDim2.fromScale(0.7, 0.16),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 220, 60),
		TextStrokeTransparency = 0,
		ZIndex = 6,
	})
	gameOverTitle.Parent = gameOverFrame
	gameOverText = makeLabel({
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.7, 0.06),
		Font = Enum.Font.GothamMedium,
		Text = "",
		ZIndex = 6,
	})
	gameOverText.Parent = gameOverFrame
	gameOverInfo = makeLabel({
		Name = "Info",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.54),
		Size = UDim2.fromScale(0.5, 0.16),
		Font = Enum.Font.Gotham,
		TextScaled = false,
		TextSize = 22,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
		ZIndex = 6,
	})
	gameOverInfo.Parent = gameOverFrame

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

	-- Steuerungshilfe unten (Text je nach Geraet, siehe RaceUI.setHelpText / ControlsInfo)
	helpLabel = makeLabel({
		Name = "Help",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(0.8, 0, 0, 22),
		Font = Enum.Font.Gotham,
		Text = "",
		TextTransparency = 0.2,
	})
end

-- Steuerungshilfe unten setzen ("" = ausblenden, z. B. auf dem Handy)
function RaceUI.setHelpText(text: string)
	if helpLabel then
		helpLabel.Text = text
		helpLabel.Visible = text ~= ""
	end
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

local WHITE = Color3.new(1, 1, 1)

-- Laufende Zeit (Sekunden) anzeigen, z. B. "1:23.45"
function RaceUI.setTimer(seconds: number)
	timerLabel.Text = RaceTime.format(seconds)
end

-- Lauf ungueltig (z. B. ausgestiegen)
function RaceUI.setTimerInvalid()
	timerLabel.Text = "-:--.--"
end

function RaceUI.setBest(seconds: number?)
	bestLabel.Text = if seconds then "Bestzeit: " .. RaceTime.format(seconds) else ""
end

-- Kurzer Hinweis unter dem Timer (Farbe optional, Standard hellblau)
function RaceUI.showToast(text: string, duration: number?, color: Color3?)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.TextColor3 = color or Color3.fromRGB(140, 230, 255)
	toastLabel.Visible = true
	task.delay(duration or 1.5, function()
		if toastToken == token then
			toastLabel.Visible = false
		end
	end)
end

local GRADE_COLORS = {
	[6] = Color3.fromRGB(90, 230, 110),
	[5] = Color3.fromRGB(160, 230, 90),
	[4] = Color3.fromRGB(240, 220, 80),
	[3] = Color3.fromRGB(255, 160, 60),
	[2] = Color3.fromRGB(255, 100, 60),
	[1] = Color3.fromRGB(255, 60, 60),
}

-- Ergebnis-Screen: Titel, Textzeilen und Schulnote
function RaceUI.showResult(
	title: string,
	titleColor: Color3,
	lines: { string },
	grade: number,
	duration: number
)
	resultToken += 1
	local token = resultToken
	resultTitle.Text = title
	resultTitle.TextColor3 = titleColor
	resultLines.Text = table.concat(lines, "\n")
	resultGrade.Text = tostring(grade)
	resultGrade.TextColor3 = GRADE_COLORS[grade] or WHITE
	resultPanel.Visible = true
	task.delay(duration, function()
		if resultToken == token then
			resultPanel.Visible = false
		end
	end)
end

-- Game Over: grosser Titel (wackelt wie ein Gummiball), lustiger Text, ein paar Zahlen
function RaceUI.showGameOver(title: string, text: string, lines: { string })
	gameOverTitle.Text = title
	gameOverText.Text = text
	gameOverInfo.Text = table.concat(lines, "\n")
	gameOverFrame.Visible = true
	if gameOverConnection then
		gameOverConnection:Disconnect()
	end
	local started = os.clock()
	gameOverConnection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		-- erst reinploppen, dann schaukeln
		local grow = math.min(t / 0.35, 1)
		local bounce = 1 + 0.25 * math.sin(grow * math.pi) + 0.04 * math.sin(t * 5)
		gameOverTitle.Size = UDim2.fromScale(0.7 * grow * bounce, 0.16 * grow * bounce)
		gameOverTitle.Rotation = math.sin(t * 3) * 6
	end)
end

function RaceUI.hideGameOver()
	gameOverFrame.Visible = false
	if gameOverConnection then
		gameOverConnection:Disconnect()
		gameOverConnection = nil
	end
end

function RaceUI.hideResult()
	resultToken += 1
	resultPanel.Visible = false
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
