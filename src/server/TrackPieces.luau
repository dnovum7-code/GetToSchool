--!strict
-- Stellt getaggte Streckenbausteine richtig ein (Anchored, Kollision, Material ...),
-- damit du in Studio nur ein normales Part bauen und taggen musst.
-- Die Wirkung (Schub, Bremsen, Crash ...) rechnet der Client des Fahrers, weil er die
-- Physik seines Wagens rechnet. Siehe src/client/TrackSensors.luau.
--
-- Bausteine duerfen Parts oder Modelle sein (bei Modellen gilt es fuer alle Teile darin).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local TagList = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TagList"))

local TrackPieces = {}

-- Tags des erweiterten Baukastens (M2.5)
local TOOLKIT_TAGS =
	{ "TriggerZone", "Spawner", "PathMover", "Gate", "Collapse", "Prop", "ForceZone", "Chaser" }

local function forEachPart(instance: Instance, callback: (BasePart) -> ())
	if instance:IsA("BasePart") then
		callback(instance)
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			callback(descendant)
		end
	end
end

-- Nur Standard-Material ersetzen, damit eigene Gestaltung erhalten bleibt
local function defaultMaterial(part: BasePart, material: Enum.Material)
	if part.Material == Enum.Material.Plastic or part.Material == Enum.Material.SmoothPlastic then
		part.Material = material
	end
end

local function numberAttribute(instance: Instance, name: string, default: number): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else default
end

-- Boden-Bausteine: fest, befahrbar, fuer Raycasts sichtbar (CanQuery)
local function prepareFloor(material: Enum.Material?): (Instance) -> ()
	return function(instance)
		forEachPart(instance, function(part)
			part.Anchored = true
			part.CanCollide = true
			part.CanQuery = true
			if material then
				defaultMaterial(part, material)
			end
		end)
	end
end

function TrackPieces.init()
	TagList.watch("BoostPad", prepareFloor(Enum.Material.Neon))
	TagList.watch("JumpPad", prepareFloor(Enum.Material.Neon))
	TagList.watch("Mud", prepareFloor(Enum.Material.Mud))
	TagList.watch("Ice", function(instance)
		prepareFloor(Enum.Material.Ice)(instance)
		forEachPart(instance, function(part)
			-- glatt: kaum Reibung (wichtig, wenn der Wagen auf dem Korb rutscht)
			part.CustomPhysicalProperties = PhysicalProperties.new(0.9, 0.02, 0, 100, 1)
		end)
	end)

	-- Bouncy: hohe Elastizitaet; ElasticityWeight 100 = dieser Wert zaehlt beim Aufprall
	TagList.watch("Bouncy", function(instance)
		local bounciness =
			math.clamp(numberAttribute(instance, "Bounciness", Config.Track.BouncyElasticity), 0, 1)
		forEachPart(instance, function(part)
			part.Anchored = true
			part.CanCollide = true
			part.CanQuery = true
			part.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, bounciness, 1, 100)
		end)
	end)

	-- Bewegte Hindernisse: verankert, die Bewegung rechnet jeder Client selbst
	-- (siehe src/client/Obstacles.luau und src/client/Toolkit)
	for _, tag in { "Mover", "Spinner", "Pendulum", "PathMover", "Gate" } do
		TagList.watch(tag, function(instance)
			forEachPart(instance, function(part)
				part.Anchored = true
			end)
		end)
	end

	-- Erweiterter Baukasten (M2.5): Jeder Baustein bekommt eine feste Nummer ("PieceId"),
	-- aus der jeder Client denselben Zufall berechnet (gleiche Steine fuer alle Spieler).
	local nextPieceId = 0
	for _, tag in TOOLKIT_TAGS do
		TagList.watch(tag, function(instance)
			if type(instance:GetAttribute("PieceId")) ~= "string" then
				nextPieceId += 1
				instance:SetAttribute("PieceId", tag .. tostring(nextPieceId))
			end
		end)
	end

	-- Wegpunkte eines PathMovers: im Spiel unsichtbar und ohne Wirkung
	TagList.watch("PathMover", function(instance)
		local waypoints = instance:FindFirstChild("Waypoints")
		if waypoints then
			forEachPart(waypoints, function(part)
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.Transparency = 1
			end)
		end
	end)

	-- Unsichtbare Bereiche (TriggerZone, Spawner): nur Messbereich, im Spiel unsichtbar
	for _, tag in { "TriggerZone", "Spawner" } do
		TagList.watch(tag, function(instance)
			forEachPart(instance, function(part)
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.Transparency = 1
			end)
		end)
	end

	-- Hazard: standardmaessig nicht fest (Wasser, Grube), mit Attribut Solid = true fest
	TagList.watch("Hazard", function(instance)
		local solid = instance:GetAttribute("Solid") == true
		forEachPart(instance, function(part)
			part.Anchored = true
			part.CanCollide = solid
			part.CanQuery = true -- noetig fuer die Beruehrungs-Abfrage des Clients
			part.CanTouch = false
		end)
	end)
end

return TrackPieces
