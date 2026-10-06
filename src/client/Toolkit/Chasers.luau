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
local LocalClone = require(script.Parent.Parent:WaitForChild("LocalClone"))
local LocalHide = require(script.Parent.Parent:WaitForChild("LocalHide"))
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
	parts: { BasePart }, -- zwischengespeichert
	halfLength: number, -- halbe Groesse (waagerecht), fuer den Abstand zum Wagen
	moving: boolean,
}

local chasers: { [Instance]: Chaser } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local excludeBuiltAt = -math.huge

-- Liste der Dinge, die kein Boden sind (Wagen, Spieler, Hunde, lokale Objekte).
-- Nur einmal pro Sekunde neu bauen, nicht bei jedem Strahl.
local function refreshExclude()
	if os.clock() - excludeBuiltAt < 1 then
		return
	end
	excludeBuiltAt = os.clock()
	local exclude: { Instance } = {}
	for instance in chasers do
		table.insert(exclude, instance)
	end
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
end

-- Boden unter `position`
local function groundY(position: Vector3): number?
	refreshExclude()
	local hit = workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), rayParams)
	return if hit then hit.Position.Y else nil
end

local function settingsFor(instance: Instance): ChaserLogic.Settings
	local C = Config.Chaser
	return {
		waitsForSignal = Pieces.string(instance, "ListenSignal", nil) ~= nil,
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
	local size = if pv:IsA("Model") then pv:GetExtentsSize() else (pv :: BasePart).Size
	local chaser: Chaser = {
		instance = pv,
		home = home,
		groundOffset = nil, -- wird beim ersten Laufen bestimmt (Boden evtl. noch nicht geladen)
		last = home,
		state = ChaserLogic.new(),
		signaled = false,
		disconnect = nil,
		parts = LocalClone.allParts(instance),
		halfLength = math.max(size.X, size.Z) / 2,
		moving = false,
	}
	excludeBuiltAt = -math.huge -- neuer Hund: Ausschluss-Liste neu bauen
	-- Beruehrung: Crash (Hazard) oder nur Schubs (zaehlt nicht als harter Aufprall)
	if Pieces.bool(instance, "Hazard", Config.Chaser.Hazard) then
		CollectionService:AddTag(instance, "Hazard")
		instance:SetAttribute("HazardHit", true) -- Treffer, kein Wasser/Abgrund (Helm: weiterfahren)
		if instance:GetAttribute("Message") == nil then
			instance:SetAttribute("Message", Config.Chaser.HazardMessage)
		end
	else
		CollectionService:AddTag(instance, "SoftHit")
	end
	local listen = Pieces.string(instance, "ListenSignal", nil)
	if listen then
		chaser.disconnect = Signals.on(listen, function()
			if not LocalHide.isHidden(instance) then
				chaser.signaled = true
			end
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
	-- ausgeblendetes Zufallsereignis: kein Ziel (Hund bleibt bzw. geht nach Hause)
	local base = if LocalHide.isHidden(chaser.instance) then nil else ctx.base
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
			Kinematic.move(chaser.instance, current, chaser.home, ctx.dt, true, chaser.parts)
			chaser.last = chaser.home
			chaser.moving = true
		elseif chaser.moving then
			Kinematic.stop(chaser.instance, chaser.parts) -- nur beim Anhalten, nicht jeden Frame
			chaser.moving = false
		end
		return
	end
	chaser.moving = true
	-- Ziel: Wagen (Jagd) oder Zuhause (Rueckweg), nur waagerecht laufen
	local goal = if mode == "Chase" and base then base.Position else chaser.home.Position
	local toGoal = flat(goal - position)
	local distance = toGoal.Magnitude
	-- Abstand halten: halbe Wagenlaenge + halbe Hundegroesse + etwas Luft (nicht in den Wagen)
	local stopDistance = if mode == "Chase"
		then Config.Cart.Length / 2 + chaser.halfLength + Config.Chaser.StopGap
		else 0
	local stepLength = math.min(speed * ctx.dt, math.max(distance - stopDistance, 0))
	local direction = if distance > 0.01 then toGoal.Unit else flat(current.LookVector)
	local newPosition = position + direction * stepLength
	-- auf dem Boden bleiben (Abstand zum Boden beim ersten Mal bestimmen)
	if chaser.groundOffset == nil then
		local homeGround = groundY(chaser.home.Position)
		chaser.groundOffset = if homeGround then chaser.home.Position.Y - homeGround else nil
	end
	local offset = chaser.groundOffset
	if offset then
		local ground = groundY(newPosition)
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
	Kinematic.move(chaser.instance, current, target, ctx.dt, true, chaser.parts)
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
			Kinematic.stop(chaser.instance, chaser.parts)
			chaser.last = chaser.home
			chaser.moving = false
		end
	end,
}

return Chasers
