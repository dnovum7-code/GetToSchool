--!strict
-- Erfolge, Client-Seite:
--   * Popup oben in der Mitte, wenn der Server einen neuen Erfolg meldet ("Achievement")
--   * Reiter "Erfolge" im Menue (B): alle Erfolge, erreichte golden, sonst Fortschritt

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ProgressClient = require(script.Parent:WaitForChild("ProgressClient"))
local ShopUI = require(script.Parent:WaitForChild("ShopUI"))
local SoundSystem = require(script.Parent:WaitForChild("SoundSystem"))

local progressRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Progress") :: RemoteEvent

local AchievementUI = {}

type Entry = {
	id: string,
	name: string,
	description: string,
	unlocked: boolean,
	progress: number,
	goal: number,
	counter: boolean,
}

local GOLD = Color3.fromRGB(255, 205, 60)
local popupGui: ScreenGui
local queue: { { name: string, description: string } } = {}
local showing = false

local function showNext()
	if showing or #queue == 0 then
		return
	end
	showing = true
	local item = table.remove(queue, 1) :: { name: string, description: string }

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, -120)
	frame.Size = UDim2.fromOffset(440, 96)
	frame.BackgroundColor3 = Color3.fromRGB(35, 30, 15)
	frame.BackgroundTransparency = 0.05
	frame.Parent = popupGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = GOLD
	stroke.Parent = frame

	local trophy = Instance.new("TextLabel")
	trophy.BackgroundTransparency = 1
	trophy.Position = UDim2.fromOffset(12, 0)
	trophy.Size = UDim2.fromOffset(70, 96)
	trophy.Font = Enum.Font.GothamBold
	trophy.TextScaled = true
	trophy.Text = "🏆"
	trophy.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(90, 8)
	title.Size = UDim2.new(1, -100, 0, 22)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = GOLD
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Erfolg freigeschaltet!"
	title.Parent = frame

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(90, 28)
	name.Size = UDim2.new(1, -100, 0, 32)
	name.Font = Enum.Font.LuckiestGuy
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = item.name
	name.Parent = frame

	local description = Instance.new("TextLabel")
	description.BackgroundTransparency = 1
	description.Position = UDim2.fromOffset(90, 62)
	description.Size = UDim2.new(1, -100, 0, 24)
	description.Font = Enum.Font.Gotham
	description.TextSize = 14
	description.TextWrapped = true
	description.TextColor3 = Color3.fromRGB(220, 220, 220)
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.Text = item.description
	description.Parent = frame

	SoundSystem.play("Achievement")
	TweenService:Create(frame, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 70),
	}):Play()
	task.delay(Config.Achievements.PopupTime, function()
		local out =
			TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(0.5, 0, 0, -120),
			})
		out:Play()
		out.Completed:Wait()
		frame:Destroy()
		showing = false
		showNext()
	end)
end

function AchievementUI.show(name: string, description: string)
	table.insert(queue, { name = name, description = description })
	showNext()
end

local function render(snapshot: ProgressClient.Snapshot)
	local C = ShopUI.COLORS
	local list = snapshot.achievements :: { Entry }?
	if not list then
		ShopUI.label(ShopUI.card(60, 1), {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 1, 0),
			Text = "Wird geladen ...",
		})
		return
	end
	local done = 0
	for _, entry in list do
		if entry.unlocked then
			done += 1
		end
	end
	ShopUI.label(ShopUI.card(30, 0), {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -28, 1, 0),
		Font = Enum.Font.GothamBold,
		TextColor3 = GOLD,
		Text = `{done} von {#list} Erfolgen`,
	})
	for index, entry in list do
		local frame = ShopUI.card(60, index)
		if entry.unlocked then
			frame.BackgroundColor3 = Color3.fromRGB(70, 60, 25)
		end
		ShopUI.label(frame, {
			Position = UDim2.fromOffset(14, 6),
			Size = UDim2.new(1, -150, 0, 24),
			Font = Enum.Font.GothamBold,
			TextColor3 = if entry.unlocked then GOLD else Color3.fromRGB(200, 200, 210),
			Text = (if entry.unlocked then "🏆 " else "🔒 ") .. entry.name,
		})
		ShopUI.label(frame, {
			Position = UDim2.fromOffset(14, 30),
			Size = UDim2.new(1, -150, 0, 22),
			TextSize = 14,
			TextColor3 = Color3.fromRGB(190, 190, 205),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = entry.description,
		})
		ShopUI.label(frame, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(120, 24),
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Enum.Font.GothamBold,
			TextColor3 = if entry.unlocked then GOLD else C.ACCENT,
			Text = if entry.unlocked
				then "Geschafft!"
				elseif entry.counter then `{math.min(entry.progress, entry.goal)} / {entry.goal}`
				else "",
		})
	end
end

function AchievementUI.init()
	popupGui = Instance.new("ScreenGui")
	popupGui.Name = "AchievementPopup"
	popupGui.ResetOnSpawn = false
	popupGui.DisplayOrder = 20
	popupGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	progressRemote.OnClientEvent:Connect(function(kind: string, name: unknown, description: unknown)
		if kind == "Achievement" and type(name) == "string" then
			AchievementUI.show(name, if type(description) == "string" then description else "")
		end
	end)
	ShopUI.addTab("Achievements", "Erfolge", render)
end

return AchievementUI
