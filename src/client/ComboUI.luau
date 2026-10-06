--!strict
-- Kuh-Kombo-Anzeige: grosses "3x KOMBO!" mit Zeitbalken, solange die Kombo laeuft.
-- Die Kombo zaehlt der Server (server/Launchables, Progression/Combo); hier nur die Show.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ChaseCamera = require(script.Parent:WaitForChild("ChaseCamera"))
local SoundSystem = require(script.Parent:WaitForChild("SoundSystem"))

local ComboUI = {}

-- Farbe je Stufe: 2x gelb ... 5x pink
local COLORS = {
	Color3.fromRGB(255, 230, 70),
	Color3.fromRGB(255, 160, 40),
	Color3.fromRGB(255, 80, 60),
	Color3.fromRGB(255, 70, 200),
}

local label: TextLabel
local scale: UIScale
local barBack: Frame
local bar: Frame
local shownAt = 0
local active = false

function ComboUI.show(count: number, multiplier: number, bonus: number)
	if count < 2 then
		return
	end
	local color = COLORS[math.clamp(multiplier - 1, 1, #COLORS)]
	label.Text = `{multiplier}x KOMBO!` .. (if bonus > 0 then `  +{bonus}` else "")
	label.TextColor3 = color
	label.Rotation = math.random(-8, 8)
	label.Visible = true
	barBack.Visible = true
	bar.BackgroundColor3 = color
	scale.Scale = 1.8
	TweenService
		:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	shownAt = os.clock()
	active = true
	SoundSystem.play("Combo")
	ChaseCamera.addShake(0.4 * multiplier)
end

function ComboUI.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Combo"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 7
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.2)
	label.Size = UDim2.fromOffset(520, 90)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(60, 0, 30)
	label.Visible = false
	label.Parent = gui
	scale = Instance.new("UIScale")
	scale.Parent = label
	barBack = Instance.new("Frame")
	barBack.AnchorPoint = Vector2.new(0.5, 0)
	barBack.Position = UDim2.new(0.5, 0, 0.2, 50)
	barBack.Size = UDim2.fromOffset(240, 8)
	barBack.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	barBack.BackgroundTransparency = 0.3
	barBack.BorderSizePixel = 0
	barBack.Visible = false
	barBack.Parent = gui
	bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 1)
	bar.BorderSizePixel = 0
	bar.Parent = barBack
	-- Zeitbalken laeuft ab; danach Anzeige weg
	RunService.RenderStepped:Connect(function()
		if not active then
			return
		end
		local left = 1 - (os.clock() - shownAt) / math.max(Config.Combo.Window, 0.1)
		if left <= 0 then
			active = false
			label.Visible = false
			barBack.Visible = false
			return
		end
		bar.Size = UDim2.fromScale(left, 1)
	end)
end

return ComboUI
