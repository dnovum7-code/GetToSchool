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

local livesFrame: Frame
local lifeIcons: { Frame } = {}
local shieldIcons: { Frame } = {}
local shownLives = -1

local shownCoins = 0 -- angezeigte Zahl (zaehlt weich zum echten Wert hoch)
local targetCoins = 0
local initialized = false

local GOLD = Color3.fromRGB(255, 200, 40)

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function box(parent: Instance, props: { [string]: any }): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	for key, value in props do
		(frame :: any)[key] = value
	end
	frame.Parent = parent
	return frame
end

-- Ein Leben = ein kleiner Schulranzen (aus Rechtecken gebaut, keine Bilder noetig)
local function makeBackpack(parent: Instance): Frame
	local holder = box(parent, { Size = UDim2.fromOffset(26, 32), BackgroundTransparency = 1 })
	-- Tragegriff oben
	local handle = box(holder, {
		Name = "Handle",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(12, 6),
		BackgroundColor3 = Color3.fromRGB(60, 40, 30),
	})
	corner(handle, UDim.new(0, 3))
	local body = box(holder, {
		Name = "Body",
		Position = UDim2.fromOffset(1, 4),
		Size = UDim2.fromOffset(24, 27),
		BackgroundColor3 = Color3.fromRGB(220, 60, 60),
	})
	corner(body, UDim.new(0, 6))
	local flap = box(body, {
		Name = "Flap",
		Size = UDim2.new(1, 0, 0, 13),
		BackgroundColor3 = Color3.fromRGB(170, 40, 45),
	})
	corner(flap, UDim.new(0, 6))
	box(flap, {
		Name = "Buckle",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(7, 6),
		BackgroundColor3 = Color3.fromRGB(255, 210, 60),
	})
	-- Reflektor-Streifen
	box(body, {
		Name = "Reflector",
		Position = UDim2.new(0, 4, 1, -7),
		Size = UDim2.new(1, -8, 0, 3),
		BackgroundColor3 = Color3.fromRGB(250, 240, 120),
	})
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	return holder
end

-- Eine Helm-Ladung = kleiner Fahrradhelm (Halbkreis mit Streifen)
local function makeHelmet(parent: Instance): Frame
	local holder = box(parent, { Size = UDim2.fromOffset(28, 32), BackgroundTransparency = 1 })
	local dome = box(holder, {
		Name = "Dome",
		Position = UDim2.fromOffset(1, 8),
		Size = UDim2.fromOffset(26, 22),
		BackgroundColor3 = Color3.fromRGB(70, 160, 255),
		ClipsDescendants = true,
	})
	corner(dome, UDim.new(0.5, 0))
	box(dome, {
		Name = "Stripe",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0, 6, 1, 0),
		BackgroundColor3 = Color3.fromRGB(240, 250, 255),
	})
	box(holder, {
		Name = "Rim",
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.fromOffset(28, 5),
		BackgroundColor3 = Color3.fromRGB(40, 90, 170),
	})
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	return holder
end

-- Ranzen/Helm grau oder farbig darstellen
local function setIconActive(icon: Frame, active: boolean)
	for _, item in { icon :: Instance, table.unpack(icon:GetDescendants()) } do
		if item:IsA("Frame") and item ~= icon then
			item.BackgroundTransparency = if active then 0 else 0.75
		end
	end
end

-- Kurzes Wackeln + Aufblaehen (verlorenes Leben, verbrauchter Helm)
local function shake(icon: Frame)
	local scale = icon:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 1.6
		TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end
	icon.Rotation = 25
	TweenService:Create(icon, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
		Rotation = 0,
	}):Play()
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

	-- Leben (Schulranzen) und Helm-Ladungen unter dem Muenzzaehler
	livesFrame = box(gui, {
		Name = "Lives",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 102),
		Size = UDim2.fromOffset(300, 34),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = livesFrame

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

-- Leben und Helm-Ladungen anzeigen. Verlorene Leben werden grau und wackeln kurz.
function ProgressUI.setLives(lives: number, maxLives: number, shield: number, maxShield: number)
	if #lifeIcons ~= maxLives then
		for _, icon in lifeIcons do
			icon:Destroy()
		end
		table.clear(lifeIcons)
		for index = 1, maxLives do
			local icon = makeBackpack(livesFrame)
			icon.LayoutOrder = 100 + index
			table.insert(lifeIcons, icon)
		end
		shownLives = -1
	end
	if #shieldIcons ~= maxShield then
		for _, icon in shieldIcons do
			icon:Destroy()
		end
		table.clear(shieldIcons)
		for index = 1, maxShield do
			local icon = makeHelmet(livesFrame)
			icon.LayoutOrder = index
			table.insert(shieldIcons, icon)
		end
	end
	for index, icon in lifeIcons do
		local active = index <= lives
		-- gerade verloren: wackeln
		if not active and shownLives >= index then
			shake(icon)
		end
		setIconActive(icon, active)
	end
	for index, icon in shieldIcons do
		local active = index <= shield
		local wasActive = icon:GetAttribute("Active")
		if wasActive == true and not active then
			shake(icon)
		end
		icon:SetAttribute("Active", active)
		setIconActive(icon, active)
	end
	shownLives = lives
end

function ProgressUI.getGui(): ScreenGui
	return gui
end

return ProgressUI
