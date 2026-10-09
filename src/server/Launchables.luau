--!strict
-- Launchables (Tag "Launchable"), Server-Seite: Treffer pruefen und den Flug planen.
-- Der Client meldet den Treffer; der Server prueft (Abstand, nicht schon getroffen) und
-- entscheidet Flugbahn, Himmelsflug, Flugweite, Rekord und Bonus. Der Client spielt den
-- Flug nur ab. So kann niemand Flugweiten oder Muenzen "erfinden".
-- Leben zieht RaceManager ab (der ruft dieses Modul auf).
-- Gespawnte Launchables (Spawner oder Vorlage mit Tag "Launchable") gibt es nur beim Client;
-- dafuer meldet er Spawner + Objekt-Nummer, wir pruefen sie gegen den Zeitplan (SpawnedHit).
-- Debug (Config.Debug.Toolkit, nur Studio): erkannte / nicht erkannte Objekte und abgelehnte
-- Treffer stehen als Warnung "[Launchable]" im Output.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Attributes = require(Shared:WaitForChild("Attributes"))
local Config = require(Shared:WaitForChild("Config"))
local Vehicles = require(Shared:WaitForChild("Vehicles"))
local Combo = require(Shared:WaitForChild("Progression"):WaitForChild("Combo"))
local LaunchMath = require(Shared:WaitForChild("Progression"):WaitForChild("LaunchMath"))
local TagList = require(Shared:WaitForChild("TagList"))
local SpawnSchedule = require(Shared:WaitForChild("Toolkit"):WaitForChild("SpawnSchedule"))
local SpawnedHit = require(Shared:WaitForChild("Toolkit"):WaitForChild("SpawnedHit"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local Leaderboards = require(script.Parent:WaitForChild("Leaderboards"))
local PlayerEvents = require(script.Parent:WaitForChild("PlayerEvents"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))

local Launchables = {}

-- Was der Client zum Abspielen bekommt
export type LaunchInfo = {
	direction: Vector3, -- waagerechte Flugrichtung
	flight: LaunchMath.Flight,
	spin: number, -- Radiant/s
	name: string, -- Anzeigename ("Kuh")
	meters: number, -- Flugweite
	bonus: number, -- Muenzbonus (mit Kombo)
	isRecord: boolean, -- neuer persoenlicher Rekord fuer diesen Namen
	combo: number, -- Treffer in Folge (1 = keine Kombo)
	multiplier: number, -- Kombo-Multiplikator
	key: string?, -- gespawntes Objekt: Schluessel des Clients (sonst nil)
}

local hitThisRun: { [Player]: { [Instance]: boolean } } = {}
local spawnedHits: { [Player]: { [Instance]: { [number]: boolean } } } = {}
local spawnedTimes: { [Player]: { number } } = {} -- fuer die Ratenbegrenzung
local combos: { [Player]: Combo.State } = {}
local random = Random.new()
local nextId = 0

local function shape(instance: Instance): (Vector3?, number)
	if instance:IsA("BasePart") then
		local size = instance.Size
		return instance.Position, math.max(size.X, size.Y, size.Z) / 2
	elseif instance:IsA("Model") then
		local cframe, size = instance:GetBoundingBox()
		return cframe.Position, math.max(size.X, size.Y, size.Z) / 2
	end
	return nil, 0
end

local function debugWarn(message: string)
	if Config.Debug.Toolkit and RunService:IsStudio() then
		warn("[Launchable] " .. message)
	end
end

local function countParts(instance: Instance): number
	local count = if instance:IsA("BasePart") then 1 else 0
	for _, item in instance:GetDescendants() do
		if item:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

local function prepare(instance: Instance)
	-- Spawner mit Tag: Er selbst fliegt nicht, seine Kopien schon (siehe Client Spawners)
	if instance:HasTag("Spawner") then
		debugWarn(
			`erkannt: Spawner {instance:GetFullName()} hat den Tag - alle Objekte, die er spawnt, sind wegschleuderbar.`
		)
		return
	end
	if not (instance:IsA("BasePart") or instance:IsA("Model")) then
		debugWarn(
			`NICHT erkannt: {instance:GetFullName()} ist ein {instance.ClassName}. Der Tag muss an ein Model oder Part.`
		)
		return
	end
	local partCount = countParts(instance)
	if partCount == 0 then
		debugWarn(`NICHT erkannt: {instance:GetFullName()} enthaelt keine Parts (nichts zum Treffen).`)
		return
	end
	debugWarn(`erkannt: {instance:GetFullName()} ({instance.ClassName}, {partCount} Parts)`)
	if type(instance:GetAttribute("LaunchId")) ~= "string" then
		nextId += 1
		instance:SetAttribute("LaunchId", tostring(nextId))
	end
	local parts: { BasePart } = {}
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	for _, part in parts do
		part.Anchored = true
		part.CanCollide = false -- kein echter Aufprall: der Wagen faehrt hindurch, das Objekt fliegt
		part.CanQuery = true -- fuer die Beruehrungs-Abfrage des Clients
		part.CanTouch = false
	end
end

-- Anzeigename fuer Rekorde: Attribut "DisplayName", sonst der Name des Objekts
function Launchables.displayName(instance: Instance): string
	local name = instance:GetAttribute("DisplayName")
	if type(name) == "string" and name ~= "" then
		return name
	end
	return instance.Name
end

-- Wagen des Spielers, wenn er sitzt (sonst nil und Grund)
local function seatedBase(player: Player): (Model?, BasePart?, string?)
	if not CartManager.isSeated(player) then
		return nil, nil, "Spieler sitzt nicht im Wagen"
	end
	local cart = CartManager.getCart(player)
	local base = cart and cart:FindFirstChild("Base")
	if not cart or not base or not base:IsA("BasePart") then
		return nil, nil, "kein Wagen"
	end
	return cart, base, nil
end

-- Plausibilitaet: Der Wagen muss am Objekt sein (der Server sieht ihn etwas verspaetet)
local function nearEnough(cart: Model, base: BasePart, center: Vector3, radius: number): (boolean, string?)
	local L = Config.Launch
	local speed = math.min(base.AssemblyLinearVelocity.Magnitude, Config.Drive.TerminalSpeed)
	local cartLength = Vehicles.forCart(cart).Cart.Length
	local allowed = radius + cartLength / 2 + L.HitTolerance + speed * L.LatencyAllowance
	local distance = (base.Position - center).Magnitude
	if distance > allowed then
		return false, string.format("Wagen zu weit weg (%.0f Studs, erlaubt %.0f)", distance, allowed)
	end
	return true, nil
end

-- Attribut zuerst an `primary` (Objekt bzw. Vorlage), sonst an `fallback` (Spawner)
local function numberFrom(primary: Instance, fallback: Instance?, name: string, default: number): number
	if primary:GetAttribute(name) ~= nil or not fallback then
		return Attributes.number(primary, name, default)
	end
	return Attributes.number(fallback, name, default)
end

-- Flug planen, Rekord, Kombo, Bonus. `source`: Objekt bzw. Vorlage (Attribute, Name).
local function plan(
	player: Player,
	base: BasePart,
	source: Instance,
	fallback: Instance?,
	name: string
): LaunchInfo
	local L = Config.Launch
	local velocity = base.AssemblyLinearVelocity

	-- Flug planen
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	if flat.Magnitude < 1 then
		flat = Vector3.new(base.CFrame.LookVector.X, 0, base.CFrame.LookVector.Z)
	end
	local direction = if flat.Magnitude > 0.01 then flat.Unit else -Vector3.zAxis
	local power = numberFrom(source, fallback, "LaunchPower", L.Power)
	local skyChance = numberFrom(source, fallback, "SkyChance", L.SkyChance)
	local sky = LaunchMath.isSky(random:NextNumber(), skyChance)
	local flight = LaunchMath.plan(flat.Magnitude, power, sky, L)
	local meters = LaunchMath.meters(flight.distance, Config.UI.StudsToMeters)
	-- Kuh-Kombo: Treffer kurz hintereinander erhoehen den Multiplikator
	local comboState = combos[player]
	if not comboState then
		comboState = Combo.new()
		combos[player] = comboState
	end
	local comboCount = Combo.hit(comboState, os.clock(), Config.Combo)
	local bonus = Combo.bonus(LaunchMath.bonus(meters, L), comboCount, Config.Combo)

	-- Rekord und Bonus in den Spielstand
	local data = Profiles.get(player)
	local previous = data.launchRecords[name]
	local isRecord = previous == nil or meters > previous
	if isRecord then
		data.launchRecords[name] = meters
	end
	data.stats.objectsLaunched += 1
	Leaderboards.submitFlight(player, meters) -- Bestenliste "Weitester Kuh-Wurf"
	PlayerEvents.fire(
		player,
		{ type = "Launch", name = name, meters = meters, sky = sky, combo = comboCount }
	)
	if bonus > 0 then
		Profiles.addCoins(player, bonus) -- meldet die Aenderung
	else
		Profiles.markChanged(player)
	end

	return {
		direction = direction,
		flight = flight,
		spin = numberFrom(source, fallback, "SpinPower", L.SpinPower),
		name = name,
		meters = meters,
		bonus = bonus,
		isRecord = isRecord and previous ~= nil, -- der allererste Wurf ist noch kein "Rekord"
		combo = comboCount,
		multiplier = Combo.multiplier(comboCount, Config.Combo),
		key = nil,
	}
end

-- Treffer an einem Objekt in der Welt pruefen und Flug planen.
-- Gibt nil und den Grund zurueck, wenn der Treffer nicht zaehlt.
function Launchables.tryLaunch(player: Player, object: unknown): (LaunchInfo?, string?)
	if typeof(object) ~= "Instance" then
		return nil, "Objekt unbekannt (beim Server nicht vorhanden)"
	end
	local instance = object :: Instance
	if not instance:HasTag("Launchable") or not instance:IsDescendantOf(workspace) then
		return nil, "kein Launchable im Workspace"
	end
	if instance:HasTag("Spawner") then
		return nil, "ein Spawner fliegt nicht selbst"
	end
	local set = hitThisRun[player]
	if not set then
		set = {}
		hitThisRun[player] = set
	end
	if set[instance] then
		return nil, "in diesem Lauf schon getroffen"
	end
	local cart, base, why = seatedBase(player)
	local center, radius = shape(instance)
	if not cart or not base or not center then
		return nil, why or "Objekt ohne Form"
	end
	local ok, reason = nearEnough(cart, base, center, radius)
	if not ok then
		return nil, reason
	end
	set[instance] = true
	return plan(player, base, instance, nil, Launchables.displayName(instance)), nil
end

-- Treffer an einer Kopie aus einem Spawner pruefen (der Server sieht die Kopie nicht).
-- `spawn` vom Client: { index, template, position, key }.
function Launchables.tryLaunchSpawned(
	player: Player,
	spawner: unknown,
	spawn: unknown
): (LaunchInfo?, string?)
	if typeof(spawner) ~= "Instance" or type(spawn) ~= "table" then
		return nil, "Spawner unbekannt"
	end
	local part = spawner :: Instance
	if not part:IsA("BasePart") or not part:HasTag("Spawner") or not part:IsDescendantOf(workspace) then
		return nil, "kein Spawner im Workspace"
	end
	local data = spawn :: { [any]: any }
	local index, templateName, position, key = data.index, data.template, data.position, data.key
	if
		type(templateName) ~= "string"
		or typeof(position) ~= "Vector3"
		or type(key) ~= "string"
		or #key > 80
	then
		return nil, "Meldung unvollstaendig"
	end
	-- Die Vorlage muss zu diesem Spawner gehoeren
	local templateList = part:GetAttribute("Template")
	local names = SpawnSchedule.splitNames(
		if type(templateList) == "string" then templateList else Config.Spawner.Template
	)
	if not table.find(names, templateName) then
		return nil, `Vorlage "{templateName}" gehoert nicht zu diesem Spawner`
	end
	local folder = ReplicatedStorage:FindFirstChild(Config.Toolkit.TemplatesFolder)
	local template = folder and folder:FindFirstChild(templateName)
	if not SpawnedHit.isLaunchableSource(part) and not SpawnedHit.isLaunchableSource(template) then
		return nil, `weder Spawner noch Vorlage "{templateName}" hat den Tag Launchable`
	end
	-- Nummer passt zum Zeitplan? Schon getroffen? Rate?
	local S, L = Config.Spawner, Config.Launch
	local now = workspace:GetServerTimeNow()
	local ok, reason = SpawnedHit.checkIndex(index, now, {
		interval = math.max(Attributes.number(part, "Interval", S.Interval), 0.1), -- wie im Client
		intervalRandom = Attributes.number(part, "IntervalRandom", S.IntervalRandom),
		burst = Attributes.number(part, "Burst", S.Burst),
		lifetime = Attributes.number(part, "Lifetime", S.Lifetime),
		slack = L.SpawnedTimeSlack,
	})
	if not ok then
		return nil, reason
	end
	local perPlayer = spawnedHits[player]
	if not perPlayer then
		perPlayer = {}
		spawnedHits[player] = perPlayer
	end
	local perSpawner = perPlayer[part]
	if not perSpawner then
		perSpawner = {}
		perPlayer[part] = perSpawner
	end
	if perSpawner[index :: number] then
		return nil, "diese Kopie wurde schon getroffen"
	end
	-- Wagen am gemeldeten Ort?
	local cart, base, why = seatedBase(player)
	if not cart or not base then
		return nil, why
	end
	local templateRadius = S.PlaceholderSize / 2
	if template then
		local _, radius = shape(template)
		if radius > 0 then
			templateRadius = radius
		end
	end
	local scaleMax = S.ScaleMax
	local scaleAttr = part:GetAttribute("ScaleRandom")
	if typeof(scaleAttr) == "NumberRange" then
		scaleMax = scaleAttr.Max
	elseif type(scaleAttr) == "number" then
		scaleMax = 1 + math.abs(scaleAttr)
	end
	local near, nearReason = nearEnough(cart, base, position, templateRadius * math.max(scaleMax, 1))
	if not near then
		return nil, nearReason
	end
	local times = spawnedTimes[player]
	if not times then
		times = {}
		spawnedTimes[player] = times
	end
	if not SpawnedHit.allowRate(times, os.clock(), L.SpawnedMaxPerMinute) then
		return nil, "zu viele Treffer pro Minute"
	end
	perSpawner[index :: number] = true
	local source: Instance = template or part
	local name = if template then Launchables.displayName(template) else templateName
	local info = plan(player, base, source, part, name)
	info.key = key
	return info, nil
end

-- Debug: abgelehnten Treffer melden (Server-Seite)
function Launchables.debugRejected(player: Player, what: string, reason: string?)
	debugWarn(`Treffer von {player.Name} an {what} abgelehnt: {reason or "?"}`)
end

-- Kompletter Neustart (T): alle Objekte stehen wieder
function Launchables.resetRun(player: Player)
	hitThisRun[player] = {}
	spawnedHits[player] = {}
end

-- Debug: Vorlagen mit Tag (Kopien aus Spawnern werden wegschleuderbar)
local function reportTemplates()
	if not Config.Debug.Toolkit then
		return
	end
	local folder = ReplicatedStorage:FindFirstChild(Config.Toolkit.TemplatesFolder)
	if not folder then
		debugWarn(
			`kein Ordner ReplicatedStorage/{Config.Toolkit.TemplatesFolder} - Spawner nutzen Ersatz-Kugeln.`
		)
		return
	end
	local count = 0
	for _, template in folder:GetChildren() do
		if SpawnedHit.isLaunchableSource(template) then
			count += 1
			debugWarn(`erkannt: Vorlage {template:GetFullName()} - Kopien aus Spawnern sind wegschleuderbar.`)
		end
	end
	if count == 0 then
		debugWarn(
			`keine Vorlage in {folder:GetFullName()} hat den Tag "Launchable" (gespawnte Objekte sind nur `
				.. "wegschleuderbar, wenn Vorlage oder Spawner den Tag haben)."
		)
	end
end

function Launchables.init()
	TagList.watch("Launchable", prepare)
	reportTemplates()
	-- Debug-Schalter erst spaeter im F2-Panel eingeschaltet: alles nochmal melden
	if RunService:IsStudio() then
		task.spawn(function()
			local wasOn = Config.Debug.Toolkit
			while true do
				task.wait(1)
				local on = Config.Debug.Toolkit
				if on and not wasOn then
					for _, instance in TagList.get("Launchable") do
						prepare(instance)
					end
					reportTemplates()
				end
				wasOn = on
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		hitThisRun[player] = nil
		spawnedHits[player] = nil
		spawnedTimes[player] = nil
		combos[player] = nil
	end)
end

return Launchables
