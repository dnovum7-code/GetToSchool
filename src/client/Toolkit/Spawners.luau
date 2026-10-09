--!strict
-- Spawner (Tag "Spawner", Part): erzeugt Objekte aus Vorlagen (ReplicatedStorage/Templates)
-- an zufaelligen Stellen innerhalb des Parts, mit Schwung Richtung Vorderseite (LookVector).
--   Dauerbetrieb:     alle Interval (+ IntervalRandom) Sekunden, nur wenn dein Wagen
--                     naeher als ActiveRadius ist. Zeitplan und Zufall sind fuer alle
--                     Spieler gleich (Serveruhr + reproduzierbarer Zufall).
--   Mit ListenSignal: pro Signal ein Burst (z. B. Steinschlag durch eine TriggerZone).
-- Objekte werden wiederverwendet (Pooling) statt immer neu erzeugt und zerstoert.
-- Kinematic = true: Objekte fahren stur geradeaus (kein Fallen, kein Bremsen), z. B. Autos.
-- Tag "Launchable" am Spawner oder an der Vorlage: Die Kopien sind wegschleuderbar (wie eine
-- Kuh in der Welt; der Server prueft den Treffer ueber Spawner + Objekt-Nummer).
-- Tags LowGravity / NoFriction / KeepUpright an Spawner oder Vorlage: siehe shared/ObjectPhysics.
-- Unity-Vergleich: Object Pool + Instantiate mit Rigidbody.velocity.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ObjectPhysics = require(Shared:WaitForChild("ObjectPhysics"))
local TagList = require(Shared:WaitForChild("TagList"))
local Rng = require(Shared:WaitForChild("Toolkit"):WaitForChild("Rng"))
local SpawnSchedule = require(Shared:WaitForChild("Toolkit"):WaitForChild("SpawnSchedule"))
local SpawnedHit = require(Shared:WaitForChild("Toolkit"):WaitForChild("SpawnedHit"))
local Kinematic = require(script.Parent.Parent:WaitForChild("Kinematic"))
local LocalClone = require(script.Parent.Parent:WaitForChild("LocalClone"))
local LocalHide = require(script.Parent.Parent:WaitForChild("LocalHide"))
local SpawnedLaunchables = require(script.Parent.Parent:WaitForChild("SpawnedLaunchables"))
local Pieces = require(script.Parent:WaitForChild("Pieces"))
local Signals = require(script.Parent:WaitForChild("Signals"))
local ToolkitTypes = require(script.Parent:WaitForChild("ToolkitTypes"))

type Active = {
	object: PVInstance,
	template: string,
	bornAt: number, -- Serverzeit
	-- Kinematic: Startlage und Tempo (Position = Start + Richtung * Tempo * Zeit)
	start: CFrame?,
	velocity: Vector3?,
	last: CFrame?,
}

type Spawner = {
	part: BasePart,
	seed: number,
	lastK: number?, -- nil = Dauerbetrieb gerade aus
	active: { Active },
	pool: { [string]: { PVInstance } },
	signalCount: number, -- Ausloesungen per Signal in diesem Lauf
	disconnect: (() -> ())?,
}

local spawners: { [Instance]: Spawner } = {}
local warnedTemplate: { [string]: boolean } = {}
local reported: { [string]: boolean } = {} -- Debug: pro Spawner und Vorlage einmal melden

local function templatesFolder(): Instance?
	return ReplicatedStorage:FindFirstChild(Config.Toolkit.TemplatesFolder)
end

-- Neue Kopie einer Vorlage (oder eine Ersatz-Kugel, wenn es die Vorlage nicht gibt)
local function createCopy(name: string): PVInstance
	local folder = templatesFolder()
	local template = folder and folder:FindFirstChild(name)
	local copy = if template then LocalClone.copy(template) else nil
	if copy then
		LocalClone.weldTogether(copy) -- lose Kopie darf nicht zerfallen
		return copy
	end
	if not warnedTemplate[name] then
		warnedTemplate[name] = true
		warn(
			`[Baukasten] Vorlage "{name}" nicht gefunden (ReplicatedStorage/{Config.Toolkit.TemplatesFolder}). `
				.. "Ersatz-Kugel wird benutzt."
		)
	end
	local ball = Instance.new("Part")
	ball.Name = "Placeholder_" .. name
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * Config.Spawner.PlaceholderSize
	ball.Material = Enum.Material.Slate
	ball.Color = Color3.fromRGB(120, 115, 110)
	return ball
end

local function setScale(object: PVInstance, scale: number)
	if object:IsA("Model") then
		object:ScaleTo(math.max(scale, 0.05))
	elseif object:IsA("BasePart") then
		local original = object:GetAttribute("OriginalSize")
		if typeof(original) ~= "Vector3" then
			original = object.Size
			object:SetAttribute("OriginalSize", original)
		end
		object.Size = (original :: Vector3) * math.max(scale, 0.05)
	end
end

-- Objekt zurueck in den Pool (unsichtbar, ohne Physik)
local function recycle(spawner: Spawner, entry: Active)
	local list = spawner.pool[entry.template]
	if not list then
		list = {}
		spawner.pool[entry.template] = list
	end
	-- Ist das Objekt schon zerstoert (z. B. ins Bodenlose gefallen), nicht wiederverwenden
	local object = entry.object
	local ok = pcall(function()
		object.Parent = nil
	end)
	if ok then
		table.insert(list, object)
	end
end

local function clearActive(spawner: Spawner)
	for _, entry in spawner.active do
		recycle(spawner, entry)
	end
	table.clear(spawner.active)
end

-- Debug (Config.Debug.Toolkit, nur Studio): einmal pro Spawner und Vorlage melden, ob die
-- Kopien wegschleuderbar sind und welche Physik-Tags gelten
local function report(
	part: BasePart,
	name: string,
	template: Instance?,
	launchable: boolean,
	flags: ObjectPhysics.Flags
)
	local key = part:GetFullName() .. "|" .. name
	if reported[key] or not Config.Debug.Toolkit then
		return
	end
	reported[key] = true
	local physics = `Physik-Tags: {ObjectPhysics.describe(flags)}`
	if not template then
		physics ..= " (Vorlage fehlt, Ersatz-Kugel)"
	end
	if launchable then
		ObjectPhysics.debugWarn(
			`[Launchable] erkannt: Spawner {part:GetFullName()} -> Kopien von "{name}" sind wegschleuderbar. {physics}`
		)
	else
		ObjectPhysics.debugWarn(
			`[Launchable] NICHT erkannt: Spawner {part:GetFullName()} -> Kopien von "{name}" sind nicht wegschleuderbar `
				.. `(kein Tag "Launchable" am Spawner oder an ReplicatedStorage/{Config.Toolkit.TemplatesFolder}/{name}). {physics}`
		)
	end
end

-- Ein Objekt erzeugen. `index` bestimmt den (reproduzierbaren) Zufall und ist zugleich die
-- Objekt-Nummer fuer die Server-Pruefung (SpawnedHit).
local function spawnOne(spawner: Spawner, index: number, now: number)
	local part = spawner.part
	local S = Config.Spawner
	local seed = spawner.seed
	local function r(salt: number): number
		return Rng.at(seed, index, salt)
	end

	local names = SpawnSchedule.splitNames(Pieces.string(part, "Template", S.Template) or "")
	local name = SpawnSchedule.pick(names, r(1)) or "Stein"

	local kinematic = Pieces.bool(part, "Kinematic", S.Kinematic)
	-- Position innerhalb des Parts (Kinematic: auf mittlerer Hoehe, sie fallen ja nicht),
	-- Richtung mit Streuung, Tempo
	local size = part.Size
	local height = if kinematic then 0 else (r(3) - 0.5) * size.Y
	local position =
		part.CFrame:PointToWorldSpace(Vector3.new((r(2) - 0.5) * size.X, height, (r(4) - 0.5) * size.Z))
	local spread = math.rad(Pieces.number(part, "SpreadAngle", S.SpreadAngle))
	local direction = (part.CFrame.Rotation * CFrame.Angles(
		(r(5) * 2 - 1) * spread,
		(r(6) * 2 - 1) * spread,
		0
	)).LookVector
	local speed = Pieces.number(part, "Speed", S.Speed)
		+ (r(7) * 2 - 1) * Pieces.number(part, "SpeedRandom", S.SpeedRandom)
	local spin = Pieces.number(part, "Spin", S.Spin)
	local scaleMin, scaleMax = Pieces.range(part, "ScaleRandom", S.ScaleMin, S.ScaleMax)
	local scale = scaleMin + (scaleMax - scaleMin) * r(8)
	local hazard = Pieces.bool(part, "Hazard", S.Hazard)

	-- Wegschleuderbar? Physik-Tags? (Spawner oder Vorlage)
	local folder = templatesFolder()
	local template = folder and folder:FindFirstChild(name)
	local launchable = SpawnedHit.isLaunchableSource(part) or SpawnedHit.isLaunchableSource(template)
	local flags = ObjectPhysics.flags(if template then { part, template } else { part })
	report(part, name, template, launchable, flags)

	-- Kopie aus dem Pool oder neu
	local list = spawner.pool[name]
	local object = if list and #list > 0 then table.remove(list) :: PVInstance else createCopy(name)
	setScale(object, scale)
	local rotation = if spin > 0
		then CFrame.Angles(r(9) * math.pi * 2, r(10) * math.pi * 2, r(11) * math.pi * 2)
		else CFrame.lookAt(Vector3.zero, direction).Rotation
	local cframe = CFrame.new(position) * rotation
	Pieces.setCFrame(object, cframe)

	for _, item in LocalClone.allParts(object) do
		item.Anchored = kinematic
		item.CanCollide = true
		item.CanQuery = true -- fuer die Beruehrungs-Abfrage (Hazard / Schubs)
		item.CanTouch = false
	end
	-- Hazard = Crash bei Beruehrung, sonst nur Schubs (zaehlt nicht als harter Aufprall).
	-- Launchable: Treffer = Objekt fliegt (kostet ein Leben wie die Kuh), kein Hazard.
	if launchable then
		CollectionService:AddTag(object, SpawnedLaunchables.TAG)
		SpawnedLaunchables.set(object, {
			spawner = part,
			index = index,
			template = name,
			key = `S{seed}:{index}`,
		})
	else
		CollectionService:RemoveTag(object, SpawnedLaunchables.TAG)
		SpawnedLaunchables.set(object, nil)
	end
	if hazard and not launchable then
		CollectionService:AddTag(object, "Hazard")
		CollectionService:RemoveTag(object, "SoftHit")
		object:SetAttribute("Message", Pieces.string(part, "Message", S.HazardMessage))
		object:SetAttribute("HazardHit", true) -- Treffer, kein Wasser/Abgrund (Helm: weiterfahren)
	else
		CollectionService:AddTag(object, "SoftHit")
		CollectionService:RemoveTag(object, "Hazard")
	end
	object.Parent = LocalClone.folder("LocalToolkit")

	local velocity = direction * speed
	if not kinematic then
		local angular = if spin > 0
			then Vector3.new(r(12) - 0.5, r(13) - 0.5, r(14) - 0.5).Unit * spin
			else Vector3.zero
		for _, item in LocalClone.allParts(object) do
			item.AssemblyLinearVelocity = velocity
			item.AssemblyAngularVelocity = angular
		end
		ObjectPhysics.apply(object, flags) -- LowGravity, NoFriction, KeepUpright
	end
	table.insert(spawner.active, {
		object = object,
		template = name,
		bornAt = now,
		start = if kinematic then cframe else nil,
		velocity = if kinematic then velocity else nil,
		last = if kinematic then cframe else nil,
	})
end

-- Eine Ausloesung: Burst Objekte (solange MaxActive nicht erreicht ist)
local function burst(spawner: Spawner, eventIndex: number, now: number)
	local part = spawner.part
	local count = math.max(1, math.floor(Pieces.number(part, "Burst", Config.Spawner.Burst)))
	local maxActive = math.max(1, math.floor(Pieces.number(part, "MaxActive", Config.Spawner.MaxActive)))
	for i = 1, count do
		if #spawner.active >= maxActive then
			break
		end
		spawnOne(spawner, SpawnedHit.index(eventIndex, i), now)
	end
end

local function register(instance: Instance)
	if spawners[instance] or not instance:IsA("BasePart") then
		return
	end
	if SpawnedHit.isLaunchableSource(instance) then
		ObjectPhysics.debugWarn(
			`[Launchable] Spawner {instance:GetFullName()} hat den Tag "Launchable": Er selbst fliegt nicht, `
				.. "aber alle Objekte, die er spawnt, sind wegschleuderbar."
		)
	end
	local spawner: Spawner = {
		part = instance,
		seed = Pieces.seed(instance),
		lastK = nil,
		active = {},
		pool = {},
		signalCount = 0,
		disconnect = nil,
	}
	local listen = Pieces.string(instance, "ListenSignal", nil)
	if listen then
		spawner.disconnect = Signals.on(listen, function()
			if LocalHide.isHidden(instance) then
				return -- ausgeblendetes Zufallsereignis: keine Wirkung
			end
			spawner.signalCount += 1
			-- eigener Zahlenbereich fuer Signal-Ausloesungen (anderer Zufall als der Dauerbetrieb)
			burst(spawner, SpawnedHit.SIGNAL_BASE + spawner.signalCount, workspace:GetServerTimeNow())
		end)
	end
	spawners[instance] = spawner
end

local function updateActive(spawner: Spawner, now: number, dt: number)
	local part = spawner.part
	local lifetime = Pieces.number(part, "Lifetime", Config.Spawner.Lifetime)
	local despawnY = Pieces.number(part, "DespawnY", Config.Spawner.DespawnY)
	for index = #spawner.active, 1, -1 do
		local entry = spawner.active[index]
		if entry.object.Parent == nil then
			-- weggeschleudert (LaunchablesClient hat es herausgenommen): zurueck in den Pool
			recycle(spawner, entry)
			table.remove(spawner.active, index)
			continue
		end
		local start, velocity, last = entry.start, entry.velocity, entry.last
		if start and velocity and last then
			-- stur geradeaus: Lage aus der Serverzeit (fuer alle Spieler gleich)
			local target = start + velocity * (now - entry.bornAt)
			Kinematic.move(entry.object, last, target, dt)
			entry.last = target
		end
		local position = Pieces.getCFrame(entry.object).Position
		if now - entry.bornAt > lifetime or position.Y < despawnY then
			recycle(spawner, entry)
			table.remove(spawner.active, index)
		end
	end
end

local Spawners: ToolkitTypes.Piece = {
	init = function()
		TagList.watch("Spawner", register)
	end,

	step = function(ctx)
		local now = workspace:GetServerTimeNow()
		local S = Config.Spawner
		for instance, spawner in spawners do
			if not instance:IsDescendantOf(workspace) then
				-- entfernt oder entladen (Streaming): aufraeumen
				clearActive(spawner)
				if spawner.disconnect then
					spawner.disconnect()
				end
				spawners[instance] = nil
				continue
			end
			updateActive(spawner, now, ctx.dt)
			if spawner.disconnect then
				continue -- wartet auf Signal, kein Dauerbetrieb
			end
			if LocalHide.isHidden(instance) then
				spawner.lastK = nil -- ausgeblendetes Zufallsereignis: kein Dauerbetrieb
				continue
			end
			-- Dauerbetrieb nur, wenn der eigene Wagen in der Naehe ist
			local base = ctx.base
			local radius = Pieces.number(instance, "ActiveRadius", S.ActiveRadius)
			local near = base ~= nil and (base.Position - spawner.part.Position).Magnitude <= radius
			if not near then
				spawner.lastK = nil
				continue
			end
			local interval = math.max(Pieces.number(instance, "Interval", S.Interval), 0.1)
			local intervalRandom = Pieces.number(instance, "IntervalRandom", S.IntervalRandom)
			local lastK = spawner.lastK or SpawnSchedule.startIndex(now, interval)
			local seed = spawner.seed
			local due, newLastK = SpawnSchedule.due(lastK, now, interval, intervalRandom, function(k)
				return Rng.at(seed, k, 0)
			end, 5)
			spawner.lastK = newLastK
			for _, k in due do
				burst(spawner, k, now)
			end
		end
	end,

	-- R und T: alle gespawnten Objekte weg, Zaehler zurueck
	reset = function()
		for _, spawner in spawners do
			clearActive(spawner)
			spawner.lastK = nil
			spawner.signalCount = 0
		end
	end,
}

return Spawners
