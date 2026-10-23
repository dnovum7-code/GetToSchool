--!strict
-- Tomaten, Client-Seite.
--   * Duo-Schuetze (hinten im Duo-Wagen): Fadenkreuz, zielt mit der Maus (Gamepad: Kamera mit
--     dem rechten Stick drehen, gezielt wird zur Bildmitte), Linksklick / RT / Touch "Tomate".
--   * Chaos: wer "Items" hat, wirft nach vorne (CrewClient.throwItem bzw. Server direkt).
--   * Flug-Optik fuer alle ("Fly"), Matsch auf dem Bildschirm und Schubs fuer Getroffene
--     ("Splat"), Munitionsanzeige, ItemBox dreht sich und ist nach dem Einsammeln kurz blass.
-- Server: server/Tomato.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TagList = require(Shared:WaitForChild("TagList"))
local CrewClient = require(script.Parent:WaitForChild("CrewClient"))
local RaceUI = require(script.Parent:WaitForChild("RaceUI"))
local SoundSystem = require(script.Parent:WaitForChild("SoundSystem"))

local tomatoRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Tomato") :: RemoteEvent
local player = Players.LocalPlayer

local TomatoClient = {}

local THROW_ACTION = "GetToSchoolTomato"
local TOMATO_RED = Color3.fromRGB(220, 40, 30)

local gui: ScreenGui
local crosshair: TextLabel
local ammoLabel: TextLabel
local splatFrame: Frame
local ammo = Config.Tomato.MaxAmmo
local aiming = false
local pushHandler: ((Vector3) -> ())? = nil
local boxFadeUntil: { [Instance]: number } = {}

-- CartClient wendet den Schubs an (meldet ihn der Crash-Erkennung)
function TomatoClient.setPushHandler(handler: (Vector3) -> ())
	pushHandler = handler
end

local function seatName(): string?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	return seat and seat.Name
end

-- Bin ich gerade der Duo-Schuetze?
local function isDuoShooter(): boolean
	local state = CrewClient.getState()
	return state ~= nil
		and state.kind == "Duo"
		and state.hostId ~= player.UserId
		and seatName() == "CrewSeat2"
end

local function canThrowNow(): boolean
	local state = CrewClient.getState()
	if not state then
		return false
	end
	if state.kind == "Duo" then
		return isDuoShooter()
	end
	return state.assignment.Items == player.UserId and #state.seats > 0
end

-- Zielrichtung: Strahl von der Kamera durch Maus (bzw. Bildmitte) bis zum Treffpunkt
local function aimDirection(): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local position = if UserInputService.MouseEnabled and not UserInputService.GamepadEnabled
		then UserInputService:GetMouseLocation()
		else camera.ViewportSize / 2
	local ray = camera:ViewportPointToRay(position.X, position.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seatPart = humanoid and humanoid.SeatPart
	local cart = seatPart and seatPart.Parent
	if cart then
		table.insert(ignore, cart)
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 400, params)
	local point = if hit then hit.Position else ray.Origin + ray.Direction * 400
	local base = cart and cart:FindFirstChild("Base")
	local from = if base and base:IsA("BasePart") then base.Position + Vector3.new(0, 3, 0) else ray.Origin
	local direction = point - from
	return if direction.Magnitude > 0.1 then direction.Unit else ray.Direction
end

local function throwAimed()
	tomatoRemote:FireServer("Throw", aimDirection())
end

local function setAiming(on: boolean)
	if on == aiming then
		return
	end
	aiming = on
	crosshair.Visible = on
	if on then
		ContextActionService:BindActionAtPriority(
			THROW_ACTION,
			function(_, inputState)
				if inputState == Enum.UserInputState.Begin then
					throwAimed()
				end
				return Enum.ContextActionResult.Sink
			end,
			true,
			Enum.ContextActionPriority.High.Value + 10,
			Enum.UserInputType.MouseButton1,
			Enum.KeyCode.ButtonR2
		)
		ContextActionService:SetTitle(THROW_ACTION, "Tomate")
		tomatoRemote:FireServer("Ammo")
	else
		ContextActionService:UnbindAction(THROW_ACTION)
	end
end

-- Flug-Optik --------------------------------------------------------------------------

local function splash(position: Vector3)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = position
	part.Parent = workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Color = ColorSequence.new(TOMATO_RED)
	emitter.Lifetime = NumberRange.new(0.3, 0.7)
	emitter.Speed = NumberRange.new(8, 20)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -50, 0)
	emitter.Size = NumberSequence.new(0.6, 0.1)
	emitter.Parent = part
	emitter:Emit(30)
	local sound = Instance.new("Sound")
	sound.SoundId = Config.Sounds.TomatoSplat.Id
	sound.Volume = Config.Sounds.TomatoSplat.Volume
	sound.Parent = part
	if sound.SoundId ~= "" then
		sound:Play()
	end
	task.delay(1.5, function()
		part:Destroy()
	end)
end

local function fly(origin: Vector3, velocity: Vector3, gravity: number, duration: number)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * 1.2
	ball.Color = TOMATO_RED
	ball.Material = Enum.Material.SmoothPlastic
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Position = origin
	ball.Parent = workspace
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.min(os.clock() - started, duration)
		ball.Position = origin + velocity * t - Vector3.new(0, 0.5 * gravity * t * t, 0)
		if t >= duration then
			connection:Disconnect()
			splash(ball.Position)
			ball:Destroy()
		end
	end)
end

-- Matsch auf dem Bildschirm -------------------------------------------------------------

local function splat()
	for _, child in splatFrame:GetChildren() do
		child:Destroy()
	end
	local strength = Config.Tomato.SplatStrength
	local rng = Random.new()
	for _ = 1, 7 do
		local blob = Instance.new("Frame")
		local size = rng:NextInteger(140, 320)
		blob.AnchorPoint = Vector2.new(0.5, 0.5)
		blob.Position = UDim2.fromScale(rng:NextNumber(0.15, 0.85), rng:NextNumber(0.15, 0.85))
		blob.Size = UDim2.fromOffset(size, size * rng:NextNumber(0.7, 1.1))
		blob.BackgroundColor3 = TOMATO_RED:Lerp(Color3.fromRGB(150, 20, 10), rng:NextNumber())
		blob.BackgroundTransparency = 1 - strength
		blob.Rotation = rng:NextNumber(0, 360)
		blob.Parent = splatFrame
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = blob
		local tween = TweenService:Create(
			blob,
			TweenInfo.new(Config.Tomato.SplatTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1, Position = blob.Position + UDim2.fromOffset(0, 60) }
		)
		tween:Play()
		tween.Completed:Connect(function()
			blob:Destroy()
		end)
	end
end

local function onSplat(byName: unknown, push: unknown)
	splat()
	SoundSystem.play("TomatoSplat")
	RaceUI.showToast(`Tomate von {tostring(byName)}!`, 2, TOMATO_RED)
	if typeof(push) == "Vector3" then
		local handler = pushHandler
		if handler then
			handler(push :: Vector3)
		end
	end
end

-- UI ----------------------------------------------------------------------------------

local function buildUi()
	gui = Instance.new("ScreenGui")
	gui.Name = "TomatoUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")
	splatFrame = Instance.new("Frame")
	splatFrame.Size = UDim2.fromScale(1, 1)
	splatFrame.BackgroundTransparency = 1
	splatFrame.Parent = gui
	crosshair = Instance.new("TextLabel")
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Size = UDim2.fromOffset(40, 40)
	crosshair.BackgroundTransparency = 1
	crosshair.Font = Enum.Font.GothamBlack
	crosshair.TextSize = 36
	crosshair.TextColor3 = TOMATO_RED
	crosshair.TextStrokeTransparency = 0.3
	crosshair.Text = "+"
	crosshair.Visible = false
	crosshair.Parent = gui
	ammoLabel = Instance.new("TextLabel")
	ammoLabel.AnchorPoint = Vector2.new(1, 1)
	ammoLabel.Position = UDim2.new(1, -20, 1, -250)
	ammoLabel.Size = UDim2.fromOffset(200, 34)
	ammoLabel.BackgroundColor3 = Color3.fromRGB(40, 20, 20)
	ammoLabel.BackgroundTransparency = 0.3
	ammoLabel.Font = Enum.Font.GothamBold
	ammoLabel.TextSize = 20
	ammoLabel.TextColor3 = Color3.new(1, 1, 1)
	ammoLabel.Visible = false
	ammoLabel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = ammoLabel
end

local function updateBoxes(dt: number)
	local now = os.clock()
	for _, box in TagList.get("ItemBox") do
		if box:IsA("BasePart") then
			box.CFrame = box.CFrame * CFrame.Angles(0, dt * 1.5, 0)
			box.LocalTransparencyModifier = if (boxFadeUntil[box] or 0) > now then 0.75 else 0
		end
	end
end

function TomatoClient.init()
	buildUi()
	CrewClient.setItemsHandler(function()
		tomatoRemote:FireServer("Throw", nil) -- Chaos-Gastgeber hat "Items": nach vorne
	end)
	tomatoRemote.OnClientEvent:Connect(function(kind: string, ...)
		if kind == "Fly" then
			local origin, velocity, gravity, duration, byId = ...
			fly(origin, velocity, gravity, duration)
			if byId == player.UserId then
				SoundSystem.play("TomatoThrow")
			end
		elseif kind == "Splat" then
			onSplat(...)
		elseif kind == "Ammo" then
			local current = ...
			ammo = if type(current) == "number" then current else ammo
		elseif kind == "Empty" then
			RaceUI.showToast("Keine Tomaten mehr - warten oder durch eine ItemBox fahren", 2)
		elseif kind == "Hit" then
			local name = ...
			RaceUI.showToast(`Treffer: {tostring(name)}!`, 1.5, Color3.fromRGB(110, 255, 120))
		elseif kind == "ItemBox" then
			local box, cooldown = ...
			if typeof(box) == "Instance" and type(cooldown) == "number" then
				boxFadeUntil[box] = os.clock() + cooldown
			end
			SoundSystem.play("ItemBox")
			RaceUI.showToast("Tomaten aufgefuellt!", 1.5)
		end
	end)
	local lastAmmoAsk = 0
	RunService.RenderStepped:Connect(function(dt)
		setAiming(isDuoShooter())
		if aiming then
			local position = if UserInputService.MouseEnabled and not UserInputService.GamepadEnabled
				then UserInputService:GetMouseLocation()
				else (workspace.CurrentCamera :: Camera).ViewportSize / 2
			crosshair.Position = UDim2.fromOffset(position.X, position.Y)
		end
		local show = canThrowNow()
		ammoLabel.Visible = show
		if show and os.clock() - lastAmmoAsk > 2 then
			lastAmmoAsk = os.clock() -- Nachladen passiert auf dem Server: ab und zu nachfragen
			tomatoRemote:FireServer("Ammo")
		end
		if show then
			ammoLabel.Text = `Tomaten: {ammo} / {Config.Tomato.MaxAmmo}`
		end
		updateBoxes(dt)
	end)
end

return TomatoClient
