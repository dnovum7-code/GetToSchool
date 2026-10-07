--!strict
-- Taegliche Login-Belohnung: Popup mit Kalender Tag 1 bis 7, aktueller Tag hervorgehoben,
-- Abholen per Knopf. Erscheint, wenn der Server sagt, dass heute noch nicht abgeholt wurde
-- (Snapshot "login"). Der Server prueft und schreibt gut (server/LoginRewards).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local LoginStreak =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"):WaitForChild("LoginStreak"))
local ProgressClient = require(script.Parent:WaitForChild("ProgressClient"))
local SoundSystem = require(script.Parent:WaitForChild("SoundSystem"))
local VisualFX = require(script.Parent:WaitForChild("VisualFX"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local settingsRemote = remotes:WaitForChild("Settings") :: RemoteEvent
local progressRemote = remotes:WaitForChild("Progress") :: RemoteEvent

local LoginRewardUI = {}

type Info = { canClaim: boolean, day: number, today: number, skinOwned: boolean }

local GOLD = Color3.fromRGB(255, 205, 60)
local gui: ScreenGui
local panel: Frame? = nil
local promptedDay: number? = nil -- an diesem Tag schon gezeigt (nicht nervig wiederholen)
local claimButton: TextButton? = nil

local ICONS = { Coins = "💰", MeterBoost = "⚡", Skin = "✨" }

local function close()
	local current = panel
	panel = nil
	claimButton = nil
	if current then
		current:Destroy()
	end
end

local function skinName(id: string?): string
	for _, item in Config.Cosmetics.Colors do
		if item.id == id then
			return item.name
		end
	end
	return "Wagen-Skin"
end

local function open(info: Info)
	close()
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(660, 320)
	frame.BackgroundColor3 = Color3.fromRGB(24, 24, 34)
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = GOLD
	stroke.Parent = frame
	local scale = Instance.new("UIScale")
	local camera = workspace.CurrentCamera
	local fit = if camera
		then math.clamp(
			math.min((camera.ViewportSize.X - 20) / 660, (camera.ViewportSize.Y - 20) / 320),
			0.4,
			1
		)
		else 1
	scale.Scale = fit * 0.8
	scale.Parent = frame
	TweenService
		:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit })
		:Play()

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(20, 10)
	title.Size = UDim2.new(1, -80, 0, 40)
	title.Font = Enum.Font.LuckiestGuy
	title.TextSize = 32
	title.TextColor3 = GOLD
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Taegliche Belohnung"
	title.Parent = frame
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(20, 48)
	sub.Size = UDim2.new(1, -40, 0, 22)
	sub.Font = Enum.Font.Gotham
	sub.TextSize = 15
	sub.TextColor3 = Color3.fromRGB(210, 210, 220)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Text = `Tag {info.day} von 7 - komm jeden Tag wieder, sonst beginnt die Serie bei Tag 1!`
	sub.Parent = frame

	local closeButton = Instance.new("TextButton")
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -12, 0, 12)
	closeButton.Size = UDim2.fromOffset(40, 36)
	closeButton.BackgroundColor3 = Color3.fromRGB(170, 60, 60)
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 18
	closeButton.Text = "X"
	closeButton.Parent = frame
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeButton
	closeButton.Activated:Connect(close)

	-- Kalender
	for n = 1, LoginStreak.LENGTH do
		local reward = Config.LoginRewards.Days[n]
		local tile = Instance.new("Frame")
		tile.Position = UDim2.fromOffset(20 + (n - 1) * 90, 82)
		tile.Size = UDim2.fromOffset(82, 140)
		local past = n < info.day or (n == info.day and not info.canClaim)
		local current = n == info.day
		tile.BackgroundColor3 = if current
			then Color3.fromRGB(90, 70, 20)
			elseif past then Color3.fromRGB(40, 80, 50)
			else Color3.fromRGB(45, 45, 60)
		tile.Parent = frame
		local tileCorner = Instance.new("UICorner")
		tileCorner.CornerRadius = UDim.new(0, 10)
		tileCorner.Parent = tile
		if current then
			local tileStroke = Instance.new("UIStroke")
			tileStroke.Thickness = 3
			tileStroke.Color = GOLD
			tileStroke.Parent = tile
		end
		local dayLabel = Instance.new("TextLabel")
		dayLabel.BackgroundTransparency = 1
		dayLabel.Size = UDim2.new(1, 0, 0, 26)
		dayLabel.Font = Enum.Font.GothamBold
		dayLabel.TextSize = 16
		dayLabel.TextColor3 = if current then GOLD else Color3.new(1, 1, 1)
		dayLabel.Text = `Tag {n}`
		dayLabel.Parent = tile
		local icon = Instance.new("TextLabel")
		icon.BackgroundTransparency = 1
		icon.Position = UDim2.fromOffset(0, 26)
		icon.Size = UDim2.new(1, 0, 0, 44)
		icon.TextScaled = true
		icon.Text = if past then "✔" else (if reward then (ICONS :: any)[reward.kind] or "🎁" else "🎁")
		icon.TextColor3 = Color3.fromRGB(120, 255, 140)
		icon.Parent = tile
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Position = UDim2.fromOffset(4, 72)
		text.Size = UDim2.new(1, -8, 0, 62)
		text.Font = Enum.Font.Gotham
		text.TextSize = 13
		text.TextWrapped = true
		text.TextColor3 = Color3.fromRGB(230, 230, 235)
		local description = if reward then LoginStreak.describe(reward :: any, skinName(reward.skin)) else ""
		if reward and reward.kind == "Skin" and info.skinOwned then
			description = `{reward.fallbackCoins or 0} Muenzen (Skin hast du)`
		end
		text.Text = description
		text.Parent = tile
	end

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -16)
	button.Size = UDim2.fromOffset(280, 52)
	button.BackgroundColor3 = if info.canClaim then GOLD else Color3.fromRGB(80, 80, 92)
	button.TextColor3 = if info.canClaim then Color3.fromRGB(30, 20, 0) else Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 22
	button.Text = if info.canClaim then "Abholen!" else "Heute schon abgeholt"
	button.Parent = frame
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 10)
	buttonCorner.Parent = button
	if info.canClaim then
		button.Activated:Connect(function()
			button.Text = "..."
			settingsRemote:FireServer("ClaimLogin")
		end)
	end
	claimButton = button
	panel = frame
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = button
	end
end

function LoginRewardUI.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "LoginReward"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 15
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	ProgressClient.onChanged(function(snapshot)
		local info = snapshot.login :: Info?
		if snapshot.state ~= "Ready" or not info or not info.canClaim then
			return
		end
		if promptedDay == info.today then
			return -- heute schon gezeigt (geschlossen ohne Abholen: nicht nochmal nerven)
		end
		promptedDay = info.today
		open(info)
	end)
	progressRemote.OnClientEvent:Connect(function(kind: string, day: unknown, text: unknown)
		if kind ~= "LoginClaimed" then
			return
		end
		local button = claimButton
		if button then
			button.Text = `Tag {day}: {text}`
			button.TextSize = 16
			button.AutoButtonColor = false
		end
		SoundSystem.play("SpinWin")
		VisualFX.confetti(day == LoginStreak.LENGTH)
		task.delay(2.5, close)
	end)
end

return LoginRewardUI
