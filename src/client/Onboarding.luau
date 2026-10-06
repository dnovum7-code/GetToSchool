--!strict
-- Einstieg: einmalige Hinweise beim ersten Lauf (Fahren, Drift, Neustart). Welche schon
-- gezeigt wurden, steht im Spielstand (hintsSeen, server/PlayerSettings). Texte passend zum
-- Geraet (ControlsInfo). Zeiten in Config.Onboarding.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ControlsInfo = require(script.Parent:WaitForChild("ControlsInfo"))

local settingsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Settings") :: RemoteEvent

local Onboarding = {}

local seen: { [string]: boolean } = {}
local loaded = false
local runToken = 0
local queue: { string } = {}
local showing = false
local gui: ScreenGui

local function enabled(): boolean
	return Config.Onboarding.Enabled and loaded
end

local function alwaysShow(): boolean
	return Config.Debug.ShowHintsAlways and RunService:IsStudio()
end

local function showNext()
	if showing or #queue == 0 then
		return
	end
	showing = true
	local id = table.remove(queue, 1) :: string
	local title, text = ControlsInfo.hint(id, ControlsInfo.device())

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -150)
	frame.Size = UDim2.new(0.9, 0, 0, 84) -- schmale Bildschirme: 90 % der Breite, sonst 520 px
	frame.BackgroundColor3 = Color3.fromRGB(20, 40, 70)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(520, 120)
	constraint.Parent = frame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromOffset(16, 6)
	titleLabel.Size = UDim2.new(1, -32, 0, 26)
	titleLabel.Font = Enum.Font.LuckiestGuy
	titleLabel.TextSize = 24
	titleLabel.TextColor3 = Color3.fromRGB(255, 215, 80)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTransparency = 1
	titleLabel.Text = "💡 " .. title
	titleLabel.Parent = frame

	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.Position = UDim2.fromOffset(16, 34)
	textLabel.Size = UDim2.new(1, -32, 0, 44)
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextSize = 17
	textLabel.TextWrapped = true
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextYAlignment = Enum.TextYAlignment.Top
	textLabel.TextTransparency = 1
	textLabel.Text = text
	textLabel.Parent = frame

	local fadeIn = TweenInfo.new(0.3)
	TweenService:Create(frame, fadeIn, { BackgroundTransparency = 0.15 }):Play()
	TweenService:Create(titleLabel, fadeIn, { TextTransparency = 0 }):Play()
	TweenService:Create(textLabel, fadeIn, { TextTransparency = 0 }):Play()
	task.delay(Config.Onboarding.HintTime, function()
		local fadeOut = TweenInfo.new(0.4)
		TweenService:Create(frame, fadeOut, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(titleLabel, fadeOut, { TextTransparency = 1 }):Play()
		local last = TweenService:Create(textLabel, fadeOut, { TextTransparency = 1 })
		last:Play()
		last.Completed:Wait()
		frame:Destroy()
		showing = false
		showNext()
	end)
end

-- Hinweis zeigen, wenn noch nicht gesehen
function Onboarding.show(id: string)
	if not enabled() or (seen[id] and not alwaysShow()) or table.find(queue, id) then
		return
	end
	seen[id] = true
	settingsRemote:FireServer("HintSeen", id)
	table.insert(queue, id)
	showNext()
end

-- Gesehene Hinweise aus dem Snapshot (einmal, wenn geladen)
function Onboarding.load(snapshot: { [string]: any })
	if loaded or snapshot.state ~= "Ready" then
		return
	end
	loaded = true
	if type(snapshot.hintsSeen) == "table" then
		for id, value in snapshot.hintsSeen do
			if value == true then
				seen[id] = true
			end
		end
	end
end

-- Alle Hinweise nochmal zeigen (Einstellungen)
function Onboarding.reset()
	table.clear(seen)
	settingsRemote:FireServer("ResetHints")
end

-- Lauf startet: Fahr-Hinweis sofort, Drift- und Neustart-Hinweis etwas spaeter
function Onboarding.onRunStarted()
	runToken += 1
	local token = runToken
	Onboarding.show("Drive")
	task.delay(Config.Onboarding.DriftHintDelay, function()
		if token == runToken then
			Onboarding.show("Drift")
		end
	end)
	task.delay(Config.Onboarding.RestartHintDelay, function()
		if token == runToken then
			Onboarding.show("Restart")
		end
	end)
end

-- Lauf vorbei (Ziel, Abbruch, Neustart): spaete Hinweise nicht mehr zeigen
function Onboarding.onRunEnded()
	runToken += 1
end

-- Erster Crash: Neustart-Hinweis
function Onboarding.onCrash()
	Onboarding.show("Restart")
end

function Onboarding.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "Onboarding"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return Onboarding
