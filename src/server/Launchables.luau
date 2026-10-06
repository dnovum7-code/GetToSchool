--!strict
-- Launchables (Tag "Launchable"), Server-Seite: Treffer pruefen und den Flug planen.
-- Der Client meldet den Treffer; der Server prueft (Abstand, nicht schon getroffen) und
-- entscheidet Flugbahn, Himmelsflug, Flugweite, Rekord und Bonus. Der Client spielt den
-- Flug nur ab. So kann niemand Flugweiten oder Muenzen "erfinden".
-- Leben zieht RaceManager ab (der ruft dieses Modul auf).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Attributes = require(Shared:WaitForChild("Attributes"))
local Config = require(Shared:WaitForChild("Config"))
local LaunchMath = require(Shared:WaitForChild("Progression"):WaitForChild("LaunchMath"))
local TagList = require(Shared:WaitForChild("TagList"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local Homework = require(script.Parent:WaitForChild("Homework"))
local Leaderboards = require(script.Parent:WaitForChild("Leaderboards"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))

local Launchables = {}

-- Was der Client zum Abspielen bekommt
export type LaunchInfo = {
	direction: Vector3, -- waagerechte Flugrichtung
	flight: LaunchMath.Flight,
	spin: number, -- Radiant/s
	name: string, -- Anzeigename ("Kuh")
	meters: number, -- Flugweite
	bonus: number, -- Muenzbonus
	isRecord: boolean, -- neuer persoenlicher Rekord fuer diesen Namen
}

local hitThisRun: { [Player]: { [Instance]: boolean } } = {}
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

local function prepare(instance: Instance)
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

-- Treffer pruefen und Flug planen. Gibt nil zurueck, wenn der Treffer nicht zaehlt.
function Launchables.tryLaunch(player: Player, object: unknown): LaunchInfo?
	if typeof(object) ~= "Instance" then
		return nil
	end
	local instance = object :: Instance
	if not instance:HasTag("Launchable") or not instance:IsDescendantOf(workspace) then
		return nil
	end
	local set = hitThisRun[player]
	if not set then
		set = {}
		hitThisRun[player] = set
	end
	if set[instance] or not CartManager.isSeated(player) then
		return nil
	end
	local cart = CartManager.getCart(player)
	local base = cart and cart:FindFirstChild("Base")
	local center, radius = shape(instance)
	if not base or not base:IsA("BasePart") or not center then
		return nil
	end
	-- Plausibilitaet: Der Wagen muss am Objekt sein (der Server sieht ihn etwas verspaetet)
	local L = Config.Launch
	local velocity = base.AssemblyLinearVelocity
	local speed = math.min(velocity.Magnitude, Config.Drive.TerminalSpeed)
	local allowed = radius + Config.Cart.Length / 2 + L.HitTolerance + speed * L.LatencyAllowance
	if (base.Position - center).Magnitude > allowed then
		return nil
	end
	set[instance] = true

	-- Flug planen
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	if flat.Magnitude < 1 then
		flat = Vector3.new(base.CFrame.LookVector.X, 0, base.CFrame.LookVector.Z)
	end
	local direction = if flat.Magnitude > 0.01 then flat.Unit else -Vector3.zAxis
	local power = Attributes.number(instance, "LaunchPower", L.Power)
	local skyChance = Attributes.number(instance, "SkyChance", L.SkyChance)
	local sky = LaunchMath.isSky(random:NextNumber(), skyChance)
	local flight = LaunchMath.plan(flat.Magnitude, power, sky, L)
	local meters = LaunchMath.meters(flight.distance, Config.UI.StudsToMeters)
	local bonus = LaunchMath.bonus(meters, L)
	local name = Launchables.displayName(instance)

	-- Rekord und Bonus in den Spielstand
	local data = Profiles.get(player)
	local previous = data.launchRecords[name]
	local isRecord = previous == nil or meters > previous
	if isRecord then
		data.launchRecords[name] = meters
	end
	data.stats.objectsLaunched += 1
	Leaderboards.submitFlight(player, meters) -- Bestenliste "Weitester Kuh-Wurf"
	Homework.report(player, { type = "Launch", name = name, meters = meters })
	if bonus > 0 then
		Profiles.addCoins(player, bonus) -- meldet die Aenderung
	else
		Profiles.markChanged(player)
	end

	return {
		direction = direction,
		flight = flight,
		spin = Attributes.number(instance, "SpinPower", L.SpinPower),
		name = name,
		meters = meters,
		bonus = bonus,
		isRecord = isRecord and previous ~= nil, -- der allererste Wurf ist noch kein "Rekord"
	}
end

-- Kompletter Neustart (T): alle Objekte stehen wieder
function Launchables.resetRun(player: Player)
	hitThisRun[player] = {}
end

function Launchables.init()
	TagList.watch("Launchable", prepare)
	Players.PlayerRemoving:Connect(function(player)
		hitThisRun[player] = nil
	end)
end

return Launchables
