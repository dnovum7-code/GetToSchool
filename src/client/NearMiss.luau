--!strict
-- Near-Miss ("KNAPP!"): Faehrst du knapp an einem Hindernis, Auto oder einer Kuh vorbei, ohne
-- es zu beruehren, gibt es einen Comic-Text und ein paar Muenzen (der Server zahlt, mit
-- Grenzen). Zaehlen: Bausteine aus Config.NearMiss.Tags (Kuehe, Mover, Tore, Hund,
-- Verfolger ...) und bewegte Hazard/Schubs-Objekte (Autos, Steine aus Spawnern).
-- Abstand: Config.NearMiss.Distance (zwischen den Umrissen). Logik: Progression/NearMissRules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local NearMissRules = require(Shared:WaitForChild("Progression"):WaitForChild("NearMissRules"))
local TagList = require(Shared:WaitForChild("TagList"))
local ComicText = require(script.Parent:WaitForChild("ComicText"))
local SoundSystem = require(script.Parent:WaitForChild("SoundSystem"))

local reportRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ReportStat") :: RemoteEvent

local NearMiss = {}

local tracker = NearMissRules.newTracker()
local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Include
local MOVING_TAGS = { "Hazard", "SoftHit" }

local function tagOf(part: Instance): (Instance?, boolean)
	local current: Instance? = part
	while current and current ~= workspace do
		for _, tag in Config.NearMiss.Tags do
			if current:HasTag(tag) then
				return current, true
			end
		end
		for _, tag in MOVING_TAGS do
			if current:HasTag(tag) then
				return current, false
			end
		end
		current = current.Parent
	end
	return nil, false
end

-- Objekte im Kasten um den Wagen (vergroessert um `padding`)
local function collect(cframe: CFrame, size: Vector3, padding: number): { [Instance]: boolean }
	local found: { [Instance]: boolean } = {}
	for _, part in workspace:GetPartBoundsInBox(cframe, size + Vector3.one * padding * 2, params) do
		local object, always = tagOf(part)
		if object and not found[object] then
			-- Hazard/Schubs-Objekte nur, wenn sie sich bewegen (Autos, Steine), nicht z. B. Wasser
			if always or part.AssemblyLinearVelocity.Magnitude >= Config.NearMiss.MinObjectSpeed then
				found[object] = true
			end
		end
	end
	return found
end

-- Jeden Frame waehrend eines Laufs (CartClient)
function NearMiss.update(cart: Model, base: BasePart, running: boolean)
	local N = Config.NearMiss
	local include = {}
	for _, tag in N.Tags do
		for _, item in TagList.get(tag) do
			table.insert(include, item)
		end
	end
	for _, tag in MOVING_TAGS do
		for _, item in TagList.get(tag) do
			table.insert(include, item)
		end
	end
	if #include == 0 then
		return
	end
	params.FilterDescendantsInstances = include
	local cframe, size = cart:GetBoundingBox()
	local near = collect(cframe, size, N.Distance)
	local touching = collect(cframe, size, N.TouchPadding)
	local speed = base.AssemblyLinearVelocity.Magnitude
	local awarded = NearMissRules.step(tracker, near, touching, os.clock(), speed, N.MinSpeed, N.Cooldown)
	if #awarded > 0 and running then
		local text = N.Texts[math.random(1, #N.Texts)]
		ComicText.show(
			base.Position + Vector3.new(0, 5, 0),
			if N.Coins > 0 then `{text} +{N.Coins}` else text
		)
		SoundSystem.play("NearMiss")
		reportRemote:FireServer("NearMiss")
	end
end

-- Neustart: nichts mehr "knapp daneben"
function NearMiss.reset()
	tracker = NearMissRules.newTracker()
end

return NearMiss
