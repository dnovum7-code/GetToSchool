--!strict
-- Meterzaehler waehrend der Fahrt (oben links) und Anzeige "x2 METER", solange der x2-Boost
-- in diesem Lauf aktiv ist. Die Meter zaehlt der Server (RaceManager), hier nur Anzeige.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local runState = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RunState") :: RemoteEvent

local MeterUI = {}

local label: TextLabel
local boostLabel: TextLabel
local boostScale: UIScale
local wasBoost = false

local function show(meters: number, boost: boolean)
	label.Text = `{math.floor(meters)} m`
	boostLabel.Visible = boost
	if boost and not wasBoost then
		boostScale.Scale = 1.6
		TweenService:Create(
			boostScale,
			TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end
	wasBoost = boost
end

function MeterUI.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Meters"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(16, 64)
	label.Size = UDim2.fromOffset(170, 36)
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	label.BackgroundTransparency = 0.35
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 24
	label.Text = "0 m"
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	boostLabel = Instance.new("TextLabel")
	boostLabel.Position = UDim2.fromOffset(16, 104)
	boostLabel.Size = UDim2.fromOffset(170, 28)
	boostLabel.BackgroundColor3 = Color3.fromRGB(255, 140, 30)
	boostLabel.TextColor3 = Color3.fromRGB(40, 20, 0)
	boostLabel.Font = Enum.Font.LuckiestGuy
	boostLabel.TextSize = 22
	boostLabel.Text = `x{Config.Meters.BoostMultiplier} METER!`
	boostLabel.Visible = false
	boostLabel.Parent = gui
	local boostCorner = Instance.new("UICorner")
	boostCorner.CornerRadius = UDim.new(0, 10)
	boostCorner.Parent = boostLabel
	boostScale = Instance.new("UIScale")
	boostScale.Parent = boostLabel
	runState.OnClientEvent:Connect(function(kind: string, meters: unknown, boost: unknown)
		if kind == "Meters" and type(meters) == "number" then
			show(meters, boost == true)
		end
	end)
end

return MeterUI
