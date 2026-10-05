--!strict
-- Alles rund um die Strecke: Start- und Zielzone finden, Startposition berechnen,
-- pruefen, ob der Wagen in einer Zone ist.
--
-- Zonen baust du in Studio als normale Parts (Quader). Gefunden werden sie ueber
-- einen Tag ("StartZone" / "FinishZone", siehe Config.Race) oder, falls kein Tag
-- gesetzt ist, ueber den gleichen Namen irgendwo im Workspace.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CartBuilder = require(script.Parent:WaitForChild("CartBuilder"))

local Track = {}

local cartsFolder: Instance? = nil

function Track.init(folder: Instance)
	cartsFolder = folder
end

-- Sucht unterhalb von `origin` den Boden und gibt die passende Position fuer die
-- Mitte des Korbbodens zurueck. Blickrichtung = LookVector von `origin` (waagerecht).
function Track.placeOnGround(origin: CFrame, ignore: { Instance }): CFrame
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = table.clone(ignore)
	if cartsFolder then
		table.insert(exclude, cartsFolder)
	end
	for _, player in game:GetService("Players"):GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude

	local start = origin.Position + Vector3.new(0, 3, 0)
	local hit = workspace:Raycast(start, Vector3.new(0, -200, 0), params)
	local groundPos = if hit then hit.Position else origin.Position
	local up = if hit then hit.Normal else Vector3.yAxis

	local look = Vector3.new(origin.LookVector.X, 0, origin.LookVector.Z)
	if look.Magnitude < 0.01 then
		look = -Vector3.zAxis
	end
	-- Blickrichtung an den Hang anpassen (rechtwinklig zur Bodennormalen)
	local right = look.Unit:Cross(up).Unit
	local position = groundPos + up * (CartBuilder.getRideHeight() + 0.3)
	return CFrame.fromMatrix(position, right, up)
end

local zoneCache: { [string]: BasePart } = {}
local lastSearch: { [string]: number } = {}
local warned: { [string]: boolean } = {}
local SEARCH_INTERVAL = 2 -- Sekunden; so oft wird nach einer fehlenden Zone gesucht

-- Zonen sind nur Messbereiche: nicht kollidieren, keine Touch-Events, und Raycasts
-- (Boden-Erkennung, Kamera) gehen hindurch.
local function prepareZone(zone: BasePart)
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanTouch = false
	zone.CanQuery = false
end

-- Sucht die Zone mit diesem Tag (oder Namen). nil, wenn es keine gibt.
function Track.findZone(tag: string): BasePart?
	local cached = zoneCache[tag]
	if cached and cached:IsDescendantOf(workspace) then
		return cached
	end
	-- Fehlt die Zone, nicht jeden Frame den ganzen Workspace durchsuchen
	local last = lastSearch[tag]
	if last and os.clock() - last < SEARCH_INTERVAL then
		return nil
	end
	lastSearch[tag] = os.clock()
	local found: BasePart? = nil
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			found = instance
			break
		end
	end
	if not found then
		local byName = workspace:FindFirstChild(tag, true)
		if byName and byName:IsA("BasePart") then
			found = byName
		end
	end
	if found then
		prepareZone(found)
		zoneCache[tag] = found
	elseif not warned[tag] then
		warned[tag] = true
		warn(`[Track] Keine Zone "{tag}" gefunden (Part mit Tag oder Name "{tag}").`)
	end
	return found
end

-- Liegt `position` in der Zone? Die Zone darf gedreht sein. Nach oben gibt es etwas
-- Spielraum, damit auch flache Zonen auf dem Boden funktionieren.
function Track.isInZone(zone: BasePart, position: Vector3): boolean
	local localPos = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Z) <= half.Z
		and localPos.Y >= -half.Y - 2
		and localPos.Y <= half.Y + 8
end

-- Startposition: Mitte der Startzone, auf dem Boden, Blick in Richtung der
-- Vorderseite (Front) der Zone. Ohne Startzone: vor dem SpawnLocation.
function Track.getSpawn(): CFrame
	local startZone = Track.findZone(Config.Race.StartZoneTag)
	if startZone then
		-- von der Oberseite der Zone aus nach unten den Boden suchen
		local top = startZone.CFrame * CFrame.new(0, startZone.Size.Y / 2, 0)
		return Track.placeOnGround(top, { startZone })
	end
	return Track.getFallbackSpawn()
end

-- Ersatz-Start, solange es keine Startzone gibt: vor dem ersten SpawnLocation.
function Track.getFallbackSpawn(): CFrame
	local spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnLocation then
		local origin = (spawnLocation :: BasePart).CFrame * CFrame.new(0, 0, -10)
		return Track.placeOnGround(origin, { spawnLocation })
	end
	return Track.placeOnGround(CFrame.new(0, 10, 0), {})
end

return Track
