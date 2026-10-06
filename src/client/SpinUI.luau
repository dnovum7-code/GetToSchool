--!strict
-- Reiter "Gluecksrad" im Menue (B): einmal am Tag gratis drehen. Der Server wuerfelt
-- (server/DailySpin) und schickt das Feld ("SpinResult"); hier dreht sich das Rad dorthin.
-- Darunter: deine Powerups (wirken automatisch beim naechsten Lauf).
--
-- Das Menue zeichnet sich bei jeder Aenderung neu. Damit die Drehung dabei nicht abbricht,
-- rechnet die Animation den Winkel aus der Zeit und setzt ihn am jeweils aktuellen Rad.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ProgressClient = require(script.Parent:WaitForChild("ProgressClient"))
local RaceUI = require(script.Parent:WaitForChild("RaceUI"))
local ShopUI = require(script.Parent:WaitForChild("ShopUI"))
local SoundSystem = require(script.Parent:WaitForChild("SoundSystem"))

local shopRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ShopRequest") :: RemoteEvent
local progressRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Progress") :: RemoteEvent

local SpinUI = {}

type Info = { canSpin: boolean, nextReset: number, items: { [string]: number } }

local WHEEL_SIZE = 260
local wheel: Frame? = nil -- aktuelles Rad (wechselt beim Neuzeichnen)
local rotation = 0 -- aktueller Winkel des Rads (Grad)
local animation: { from: number, to: number, startedAt: number, text: string }? = nil
local lastTick = 0

local function segmentAngle(index: number, count: number): number
	return (index - 1) * 360 / count
end

local function timeLeft(nextReset: number): string
	local seconds = math.max(0, nextReset - workspace:GetServerTimeNow())
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	return if hours > 0 then `{hours} Std {minutes} Min` else `{math.max(minutes, 1)} Min`
end

local function buildWheel(parent: Instance): Frame
	local segments = Config.DailySpin.Segments
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 28)
	holder.Size = UDim2.fromOffset(WHEEL_SIZE, WHEEL_SIZE)
	holder.BackgroundColor3 = Color3.fromRGB(45, 40, 60)
	holder.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = holder
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = ShopUI.COLORS.ACCENT
	stroke.Parent = holder
	-- Felder: farbige Schilder im Kreis, dazwischen Trennlinien
	for index, segment in segments do
		local angle = segmentAngle(index, #segments)
		local arm = Instance.new("Frame")
		arm.AnchorPoint = Vector2.new(0.5, 0.5)
		arm.Position = UDim2.fromScale(0.5, 0.5)
		arm.Size = UDim2.fromOffset(WHEEL_SIZE, WHEEL_SIZE)
		arm.BackgroundTransparency = 1
		arm.Rotation = angle
		arm.Parent = holder
		local tag = Instance.new("TextLabel")
		tag.AnchorPoint = Vector2.new(0.5, 0)
		tag.Position = UDim2.new(0.5, 0, 0, 8)
		tag.Size = UDim2.fromOffset(76, 44)
		tag.BackgroundColor3 = segment.color
		tag.TextColor3 = Color3.fromRGB(30, 20, 10)
		tag.Font = Enum.Font.GothamBold
		tag.TextScaled = true
		tag.TextWrapped = true
		tag.Text = segment.text
		tag.Parent = arm
		local tagCorner = Instance.new("UICorner")
		tagCorner.CornerRadius = UDim.new(0, 8)
		tagCorner.Parent = tag
		local divider = Instance.new("Frame")
		divider.AnchorPoint = Vector2.new(0.5, 1)
		divider.Position = UDim2.fromScale(0.5, 0.5)
		divider.Size = UDim2.new(0, 2, 0.5, -4)
		divider.BackgroundColor3 = Color3.fromRGB(90, 85, 110)
		divider.BorderSizePixel = 0
		divider.Rotation = 0
		divider.Parent = arm
		-- Trennlinie halb zwischen zwei Feldern
		local dividerArm = Instance.new("Frame")
		dividerArm.AnchorPoint = Vector2.new(0.5, 0.5)
		dividerArm.Position = UDim2.fromScale(0.5, 0.5)
		dividerArm.Size = UDim2.fromScale(1, 1)
		dividerArm.BackgroundTransparency = 1
		dividerArm.Rotation = 180 / #segments
		dividerArm.Parent = arm
		divider.Parent = dividerArm
	end
	local hub = Instance.new("Frame")
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(46, 46)
	hub.BackgroundColor3 = ShopUI.COLORS.ACCENT
	hub.Parent = holder
	local hubCorner = Instance.new("UICorner")
	hubCorner.CornerRadius = UDim.new(1, 0)
	hubCorner.Parent = hub
	holder.Rotation = rotation
	return holder
end

local function render(snapshot: ProgressClient.Snapshot)
	local C = ShopUI.COLORS
	local info = snapshot.spin :: Info?
	local area = ShopUI.card(WHEEL_SIZE + 110, 1)
	area.BackgroundTransparency = 1
	-- Zeiger oben
	ShopUI.label(area, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(40, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.ACCENT,
		TextSize = 30,
		Font = Enum.Font.GothamBold,
		Text = "▼",
		ZIndex = 3,
	})
	wheel = buildWheel(area)
	local canSpin = info ~= nil and info.canSpin and animation == nil
	local button = ShopUI.button(area, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.fromOffset(300, 46),
		BackgroundColor3 = if canSpin then C.ACCENT else C.GREY,
		TextColor3 = if canSpin then C.DARK else Color3.new(1, 1, 1),
		AutoButtonColor = canSpin,
		Text = if animation
			then "Dreht ..."
			elseif canSpin then "Drehen! (gratis)"
			elseif info then `Naechstes Drehen in {timeLeft(info.nextReset)}`
			else "Wird geladen ...",
	})
	if canSpin then
		button.Activated:Connect(function()
			shopRemote:FireServer("Spin", "")
		end)
	end

	-- Powerups
	local items = if info then info.items else {}
	local lines = {}
	for _, id in Config.DailySpin.ItemOrder do
		local count = items[id] or 0
		local def = (Config.DailySpin.Items :: any)[id]
		if count > 0 and def then
			table.insert(lines, `{def.icon} {def.name} x{count} ({def.description})`)
		end
	end
	local list = ShopUI.card(28 + math.max(#lines, 1) * 22, 2)
	ShopUI.label(list, {
		Position = UDim2.fromOffset(14, 4),
		Size = UDim2.new(1, -28, 1, -8),
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		TextSize = 15,
		Text = if #lines > 0
			then "Deine Powerups (wirken automatisch beim naechsten Lauf):\n" .. table.concat(lines, "\n")
			else "Noch keine Powerups. Dreh am Rad!",
	})
end

function SpinUI.init()
	ShopUI.addTab("Spin", "Gluecksrad", render)
	progressRemote.OnClientEvent:Connect(function(kind: string, index: unknown, text: unknown)
		if kind ~= "SpinResult" or type(index) ~= "number" then
			return
		end
		local count = #Config.DailySpin.Segments
		-- Ziel: Feld `index` oben; mindestens 4 volle Umdrehungen
		local target = -segmentAngle(index, count)
		local from = rotation
		local to = target - 360 * 5
		while to > from - 360 * 4 do
			to -= 360
		end
		-- kleine Zufallsabweichung innerhalb des Felds (wirkt echter)
		to += (math.random() - 0.5) * (300 / count) * 0.6
		animation = {
			from = from,
			to = to,
			startedAt = os.clock(),
			text = if type(text) == "string" then text else "",
		}
		ShopUI.refresh()
	end)
	RunService.RenderStepped:Connect(function()
		local current = animation
		if not current then
			return
		end
		local t =
			math.clamp((os.clock() - current.startedAt) / math.max(Config.DailySpin.SpinTime, 0.5), 0, 1)
		local eased = 1 - (1 - t) ^ 4 -- schnell los, langsam aus (wie ein echtes Rad)
		local newRotation = current.from + (current.to - current.from) * eased
		-- Klick-Geraeusch bei jedem Feld
		local step = 360 / #Config.DailySpin.Segments
		if math.floor(newRotation / step) ~= math.floor(rotation / step) and os.clock() - lastTick > 0.05 then
			lastTick = os.clock()
			SoundSystem.play("SpinTick")
		end
		rotation = newRotation
		local w = wheel
		if w and w.Parent then
			w.Rotation = rotation
		end
		if t >= 1 then
			animation = nil
			rotation = rotation % 360
			SoundSystem.play("SpinWin")
			RaceUI.showToast(`Gewonnen: {current.text}!`, 3, Color3.fromRGB(255, 215, 80))
			ShopUI.refresh()
		end
	end)
end

return SpinUI
