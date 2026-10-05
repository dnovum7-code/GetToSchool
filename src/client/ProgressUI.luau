--!strict
-- Anzeige fuer den Fortschritt: Muenzzaehler oben rechts (mit kleiner Animation beim
-- Einsammeln). Komplett per Skript gebaut, keine GUI-Assets noetig.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ProgressUI = {}

local gui: ScreenGui
local coinFrame: Frame
local coinLabel: TextLabel
local coinScale: UIScale

local shownCoins = 0 -- angezeigte Zahl (zaehlt weich zum echten Wert hoch)
local targetCoins = 0
local initialized = false

local GOLD = Color3.fromRGB(255, 200, 40)

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

-- Rundes Muenz-Symbol (zwei Kreise)
function ProgressUI.makeCoinIcon(parent: Instance, size: number): Frame
	local icon = Instance.new("Frame")
	icon.Name = "CoinIcon"
	icon.Size = UDim2.fromOffset(size, size)
	icon.BackgroundColor3 = GOLD
	icon.BorderSizePixel = 0
	corner(icon, UDim.new(1, 0))
	local inner = Instance.new("Frame")
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromScale(0.62, 0.62)
	inner.BackgroundColor3 = Color3.fromRGB(230, 160, 20)
	inner.BorderSizePixel = 0
	inner.Parent = icon
	corner(inner, UDim.new(1, 0))
	icon.Parent = parent
	return icon
end

function ProgressUI.init()
	if initialized then
		return
	end
	initialized = true
	gui = Instance.new("ScreenGui")
	gui.Name = "ProgressUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	coinFrame = Instance.new("Frame")
	coinFrame.Name = "Coins"
	coinFrame.AnchorPoint = Vector2.new(1, 0)
	coinFrame.Position = UDim2.new(1, -20, 0, 50)
	coinFrame.Size = UDim2.fromOffset(170, 44)
	coinFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	coinFrame.BackgroundTransparency = 0.35
	coinFrame.Parent = gui
	corner(coinFrame, UDim.new(0, 10))
	coinScale = Instance.new("UIScale")
	coinScale.Parent = coinFrame

	local icon = ProgressUI.makeCoinIcon(coinFrame, 28)
	icon.Position = UDim2.fromOffset(10, 8)

	coinLabel = Instance.new("TextLabel")
	coinLabel.BackgroundTransparency = 1
	coinLabel.Position = UDim2.fromOffset(46, 4)
	coinLabel.Size = UDim2.new(1, -56, 1, -8)
	coinLabel.Font = Enum.Font.GothamBold
	coinLabel.TextScaled = true
	coinLabel.TextXAlignment = Enum.TextXAlignment.Right
	coinLabel.TextColor3 = Color3.new(1, 1, 1)
	coinLabel.TextStrokeTransparency = 0.5
	coinLabel.Text = "0"
	coinLabel.Parent = coinFrame

	-- Zahl weich hochzaehlen (z. B. +30 im Ziel)
	RunService.RenderStepped:Connect(function(dt: number)
		if shownCoins ~= targetCoins then
			local step = math.max(1, math.abs(targetCoins - shownCoins) * math.min(dt * 6, 1))
			if shownCoins < targetCoins then
				shownCoins = math.min(targetCoins, shownCoins + step)
			else
				shownCoins = math.max(targetCoins, shownCoins - step)
			end
			coinLabel.Text = tostring(math.floor(shownCoins + 0.5))
		end
	end)
end

local function pop()
	coinScale.Scale = 1.25
	TweenService:Create(coinScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

-- Muenzstand vom Server. `instant`: ohne Hochzaehlen (z. B. beim ersten Laden)
function ProgressUI.setCoins(total: number, instant: boolean?)
	if instant then
		shownCoins = total
		coinLabel.Text = tostring(total)
	elseif total > targetCoins then
		pop()
	end
	targetCoins = total
end

-- Gerade eingesammelt: "+1" steigt am Zaehler auf und verblasst
function ProgressUI.coinPickup(value: number)
	pop()
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(1, 0)
	label.Position = UDim2.new(1, -24, 0, 96)
	label.Size = UDim2.fromOffset(80, 28)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextColor3 = GOLD
	label.TextStrokeTransparency = 0.3
	label.Text = "+" .. tostring(value)
	label.Parent = gui
	local tween =
		TweenService:Create(label, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(1, -24, 0, 70),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
	tween.Completed:Once(function()
		label:Destroy()
	end)
	tween:Play()
end

function ProgressUI.getGui(): ScreenGui
	return gui
end

return ProgressUI
