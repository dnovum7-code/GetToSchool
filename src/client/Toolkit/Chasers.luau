--!strict
-- Chaser (Tag "Chaser", Modell oder Part, z. B. ein Hund): rennt dem eigenen Wagen am Boden
-- nach, sobald er naeher als Radius kommt (oder bei ListenSignal), gibt nach GiveUpTime auf
-- und laeuft nach Hause. Jeder Spieler hat seinen eigenen Hund (nur bei dir bewegt).
-- Bewegt wird kinematisch (verankert + passende Geschwindigkeit), damit er den Wagen
-- schubst. Hazard = true: Beruehrung ist ein Crash. Bei R und T sofort wieder zu Hause.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TagList = require(Shared:WaitForChild("TagList"))
local ChaserLogic = require(Shared:WaitForChild("Toolkit"):WaitForChild("ChaserLogic"))
local Kinematic = require(script.Parent.Parent:WaitForChild("Kinematic"))
local Pieces = require(script.Parent:WaitForChild("Pieces"))
local Signals = require(script.Parent:WaitForChild("Signals"))
local ToolkitTypes = require(script.Parent:WaitForChild("ToolkitTypes"))

type Chaser = {
	instance: PVInstance,
	home: CFrame,
	groundOffset: number?, -- Hoehe des Pivots ueber dem Boden (nil = kein Boden gefunden)
	last: CFrame,
	state: ChaserLogic.State,
	signaled: boolean,
	disconnect: (() -> ())?,
}

local chasers: { [Instance]: Chaser } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- Boden unter `position` (ohne Wagen, Spieler und den Hund selbst)
local function groundY(chaser: Chaser, position: Vector3): number?
	local exclude: { Instance } = { chaser.instance }
	local carts = workspace:FindFirstChild("Carts")
	if carts then
		table.insert(exclude, carts)
	end
	for _, folderName in { "LocalToolkit", "LocalProps", "LocalLaunchEffects", "LocalCoinEffects" } do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			table.insert(exclude, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	rayParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), rayParams)
	return if hit then hit.Position.Y else nil
end

local function settingsFor(instance: Instance): ChaserLogic.Settings
	local C = Config.Chaser
	return {
		radius = Pieces.number(instance, "Radius", C.Radius),
		maxSpeed = Pieces.number(instance, "MaxSpeed", C.MaxSpeed),
		acceleration = Pieces.number(instance, "Acceleration", C.Acceleration),
		giveUpTime = Pieces.number(instance, "GiveUpTime", C.GiveUpTime),
		returnSpeed = Pieces.number(instance, "ReturnSpeed", C.ReturnSpeed),
		cooldown = Pieces.number(instance, "Cooldown", C.Cooldown),
	}
end

local function register(instance: Instance)
	if chasers[instance] or not (instance:IsA("Model") or instance:IsA("BasePart")) then
		return
	end
	local pv = instance :: PVInstance
	local home = pv:GetPivot()
	local chaser: Chaser = {
		instance = pv,
		home = home,
		groundOffset = nil,
		last = home,
		state = ChaserLogic.new(),
		signaled = false,
		disconnect = nil,
	}
	local ground = groundY(chaser, home.Position)
	chaser.groundOffset = if ground then home.Position.Y - ground else nil
	-- Beruehrung: Crash (Hazard) oder nur Schubs (zaehlt nicht als harter Aufprall)
	if Pieces.bool(instance, "Hazard", Config.Chaser.Hazard) then
		CollectionService:AddTag(instance, "Hazard")
		if instance:GetAttribute("Message") == nil then
			instance:SetAttribute("Message", Config.Chaser.HazardMessage)
		end
	else
		CollectionService:AddTag(instance, "SoftHit")
	end
	local listen = Pieces.string(instance, "ListenSignal", nil)
	if listen then
		chaser.disconnect = Signals.on(listen, function()
			chaser.signaled = true
		end)
	end
	chasers[instance] = chaser
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function update(chaser: Chaser, ctx: ToolkitTypes.Context)
	local current = chaser.last
	local position = current.Position
	local base = ctx.base
	local targetDistance = if base then flat(base.Position - position).Magnitude else nil
	local homeDistance = flat(chaser.home.Position - position).Magnitude
	local speed = ChaserLogic.step(
		chaser.state,
		ctx.dt,
		targetDistance,
		homeDistance,
		chaser.signaled,
		settingsFor(chaser.instance)
	)
	chaser.signaled = false

	local mode = chaser.state.mode
	if mode == "Idle" then
		if current ~= chaser.home then
			Kinematic.move(chaser.instance, current, chaser.home, ctx.dt, true)
			chaser.last = chaser.home
		else
			Kinematic.stop(chaser.instance)
		end
		return
	end
	-- Ziel: Wagen (Jagd) oder Zuhause (Rueckweg), nur waagerecht laufen
	local goal = if mode == "Chase" and base then base.Position else chaser.home.Position
	local toGoal = flat(goal - position)
	local distance = toGoal.Magnitude
	local stopDistance = if mode == "Chase" then 1.5 else 0
	local stepLength = math.min(speed * ctx.dt, math.max(distance - stopDistance, 0))
	local direction = if distance > 0.01 then toGoal.Unit else flat(current.LookVector)
	local newPosition = position + direction * stepLength
	-- auf dem Boden bleiben
	local offset = chaser.groundOffset
	if offset then
		local ground = groundY(chaser, newPosition)
		if ground then
			newPosition = Vector3.new(newPosition.X, ground + offset, newPosition.Z)
		end
	end
	-- in Laufrichtung drehen (nur um die Hochachse)
	local rotation = current.Rotation
	if direction.Magnitude > 0.01 then
		local wanted = CFrame.lookAt(Vector3.zero, direction).Rotation
		rotation = rotation:Lerp(wanted, 1 - math.exp(-Config.Chaser.TurnSpeed * ctx.dt))
	end
	local target = CFrame.new(newPosition) * rotation
	if mode == "Return" and homeDistance <= 1 then
		target = chaser.home
	end
	Kinematic.move(chaser.instance, current, target, ctx.dt, true)
	chaser.last = target
end

local Chasers: ToolkitTypes.Piece = {
	init = function()
		TagList.watch("Chaser", register)
	end,

	step = function(ctx)
		for instance, chaser in chasers do
			if not instance:IsDescendantOf(workspace) then
				if chaser.disconnect then
					chaser.disconnect()
				end
				chasers[instance] = nil
				continue
			end
			update(chaser, ctx)
		end
	end,

	-- R und T: sofort wieder zu Hause
	reset = function()
		for _, chaser in chasers do
			ChaserLogic.reset(chaser.state)
			chaser.signaled = false
			chaser.instance:PivotTo(chaser.home)
			Kinematic.stop(chaser.instance)
			chaser.last = chaser.home
		end
	end,
}

return Chasers
