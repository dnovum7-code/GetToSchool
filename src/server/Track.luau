--!strict
-- Alles rund um die Strecken: Strecken finden, Start- und Zielzone pro Strecke,
-- Startposition berechnen, pruefen, ob der Wagen in einer Zone ist.
--
-- Zonen baust du in Studio als normale Parts (Quader). Gefunden werden sie ueber
-- einen Tag ("StartZone" / "FinishZone", siehe Config.Race) oder, falls kein Tag
-- gesetzt ist, ueber den gleichen Namen. Mehrere Strecken: siehe "Strecken" unten.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local TagList = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TagList"))
local CartBuilder = require(script.Parent:WaitForChild("CartBuilder"))

local Track = {}

local cartsFolder: Instance? = nil

function Track.init(folder: Instance)
	cartsFolder = folder
end

-- Mittlere Bodenneigung rund um `center` (mehrere Strahlen, damit kleine Huckel
-- die Richtung nicht verfaelschen).
local function averageGroundNormal(center: Vector3, params: RaycastParams): Vector3?
	local sum = Vector3.zero
	local count = 0
	for _, offset in { Vector3.zero, Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
		local hit = workspace:Raycast(center + offset * 3, Vector3.new(0, -200, 0), params)
		if hit then
			sum += hit.Normal
			count += 1
		end
	end
	if count == 0 or sum.Magnitude < 0.01 then
		return nil
	end
	return sum.Unit
end

-- Sucht unterhalb von `origin` den Boden und gibt die passende Position fuer die
-- Mitte des Korbbodens zurueck. Blickrichtung: der LookVector von `origin` (waagerecht),
-- mit `allowDownhill` und Config.Race.StartFacing = "Downhill" stattdessen bergab.
function Track.placeOnGround(origin: CFrame, ignore: { Instance }, allowDownhill: boolean?): CFrame
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
	if allowDownhill and Config.Race.StartFacing == "Downhill" then
		-- Die Bodennormale kippt in Richtung bergab; ihr waagerechter Anteil zeigt dorthin.
		local normal = averageGroundNormal(start, params)
		local minSlope = math.sin(math.rad(Config.Race.DownhillMinSlope))
		if normal and Vector3.new(normal.X, 0, normal.Z).Magnitude >= minSlope then
			look = Vector3.new(normal.X, 0, normal.Z)
		end
	end
	-- Blickrichtung an den Hang anpassen (rechtwinklig zur Bodennormalen)
	local right = look.Unit:Cross(up).Unit
	local position = groundPos + up * (CartBuilder.getRideHeight() + 0.3)
	return CFrame.fromMatrix(position, right, up)
end

-- Strecken ------------------------------------------------------------------------------
-- Jede Strecke ist ein Model mit Attribut "TrackId" (Text); StartZone, FinishZone und
-- Checkpoints liegen darin. Zonen, die in keinem solchen Model liegen, bilden die
-- "lose" Strecke (so wie vor M3): ihre Id ist das Attribut "TrackId" der StartZone oder
-- Config.Race.DefaultTrackId.

local trackModels: { [string]: Model } = {}
local warnedDuplicate: { [string]: boolean } = {}

local function readTrackId(instance: Instance): string?
	if not instance:IsA("Model") then
		return nil
	end
	local id = instance:GetAttribute("TrackId")
	return if type(id) == "string" and id ~= "" then id else nil
end

local function addTrackModel(instance: Instance)
	local id = readTrackId(instance)
	if not id then
		return
	end
	local existing = trackModels[id]
	if existing and existing ~= instance and existing:IsDescendantOf(workspace) then
		if not warnedDuplicate[id] then
			warnedDuplicate[id] = true
			warn(`[Track] Zwei Strecken mit TrackId "{id}" - nur eine wird benutzt.`)
		end
		return
	end
	trackModels[id] = instance :: Model
end

for _, descendant in workspace:GetDescendants() do
	addTrackModel(descendant)
end
workspace.DescendantAdded:Connect(addTrackModel)
workspace.DescendantRemoving:Connect(function(instance)
	local id = readTrackId(instance)
	if id and trackModels[id] == instance then
		trackModels[id] = nil
	end
end)

-- Zu welcher Strecke (Model) gehoert dieses Objekt? nil = lose (in keinem Track-Model)
local function ownerModel(instance: Instance): Model?
	local current = instance.Parent
	while current and current ~= workspace do
		if readTrackId(current) then
			return current :: Model
		end
		current = current.Parent
	end
	return nil
end

-- Gehoert `instance` zur Strecke `trackId`?
local function belongsTo(instance: Instance, trackId: string): boolean
	local owner = ownerModel(instance)
	if owner then
		local model: Model? = trackModels[trackId]
		if not model then
			return false
		end
		return rawequal(owner, model)
	end
	-- lose Objekte gehoeren zur losen Strecke (wenn kein Model diese Id hat)
	local model: Model? = trackModels[trackId]
	return not model
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

-- Sucht ohne Cache: erst per Tag, dann per Name (im Track-Model bzw. lose im Workspace)
local function searchZone(trackId: string, tag: string): BasePart?
	for _, instance in CollectionService:GetTagged(tag) do
		if
			instance:IsA("BasePart")
			and instance:IsDescendantOf(workspace)
			and belongsTo(instance, trackId)
		then
			return instance
		end
	end
	local model = trackModels[trackId]
	local root: Instance = model or workspace
	for _, instance in root:GetDescendants() do
		if instance.Name == tag and instance:IsA("BasePart") and belongsTo(instance, trackId) then
			return instance
		end
	end
	return nil
end

-- Id der losen Strecke (Zonen ausserhalb von Track-Models), nil wenn es keine gibt
local function looseTrackId(): string?
	for _, instance in CollectionService:GetTagged(Config.Race.StartZoneTag) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) and not ownerModel(instance) then
			local id = instance:GetAttribute("TrackId")
			return if type(id) == "string" and id ~= "" then id else Config.Race.DefaultTrackId
		end
	end
	local byName = workspace:FindFirstChild(Config.Race.StartZoneTag, true)
	if byName and byName:IsA("BasePart") and not ownerModel(byName) then
		local id = byName:GetAttribute("TrackId")
		return if type(id) == "string" and id ~= "" then id else Config.Race.DefaultTrackId
	end
	return nil
end

-- Gehoert `instance` (z. B. eine Muenze) zur Strecke `trackId`? Objekte in einem Track-Model
-- gehoeren zu diesem, lose Objekte zur losen Strecke.
function Track.belongsTo(instance: Instance, trackId: string): boolean
	return belongsTo(instance, trackId)
end

-- Alle Strecken, die es in der Welt gibt (Ids)
function Track.list(): { string }
	local ids = {}
	for id, model in trackModels do
		if model:IsDescendantOf(workspace) then
			table.insert(ids, id)
		end
	end
	local loose = looseTrackId()
	if loose and not trackModels[loose] then
		table.insert(ids, loose)
	end
	table.sort(ids)
	return ids
end

function Track.exists(trackId: string): boolean
	return table.find(Track.list(), trackId) ~= nil
end

-- Name zum Anzeigen: aus Config.Tracks, sonst Attribut "TrackName" am Model, sonst die Id
function Track.displayName(trackId: string): string
	for _, def in Config.Tracks do
		if def.id == trackId then
			return def.name
		end
	end
	local model = trackModels[trackId]
	local name = model and model:GetAttribute("TrackName")
	return if type(name) == "string" and name ~= "" then name else trackId
end

-- Strecke fuer neue Spieler: die erste aus Config.Tracks, die es gibt und die frei ist
-- (ohne Bedingung), sonst die erste vorhandene, sonst Config.Race.DefaultTrackId.
function Track.defaultTrackId(): string
	local existing = Track.list()
	for _, def in Config.Tracks do
		if def.unlock == nil and table.find(existing, def.id) then
			return def.id
		end
	end
	return existing[1] or Config.Race.DefaultTrackId
end

-- Sucht die Zone mit diesem Tag (oder Namen) auf der Strecke. nil, wenn es keine gibt.
function Track.findZone(trackId: string, tag: string): BasePart?
	local cacheKey = trackId .. "|" .. tag
	local cached = zoneCache[cacheKey]
	if cached and cached:IsDescendantOf(workspace) and belongsTo(cached, trackId) then
		return cached
	end
	-- Fehlt die Zone, nicht jeden Frame die ganze Welt durchsuchen
	local last = lastSearch[cacheKey]
	if last and os.clock() - last < SEARCH_INTERVAL then
		return nil
	end
	lastSearch[cacheKey] = os.clock()
	local found = searchZone(trackId, tag)
	if found then
		prepareZone(found)
		zoneCache[cacheKey] = found
	elseif not warned[cacheKey] then
		warned[cacheKey] = true
		warn(`[Track] Strecke "{trackId}": keine Zone "{tag}" gefunden (Part mit Tag oder Name "{tag}").`)
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
function Track.getSpawn(trackId: string): CFrame
	local testSpawn = Track.getTerrainTestSpawn()
	if testSpawn then
		return testSpawn
	end
	local startZone = Track.findZone(trackId, Config.Race.StartZoneTag)
	if startZone then
		-- von der Oberseite der Zone aus nach unten den Boden suchen
		local top = startZone.CFrame * CFrame.new(0, startZone.Size.Y / 2, 0)
		return Track.placeOnGround(top, { startZone }, true)
	end
	return Track.getFallbackSpawn()
end

-- Terrain-Vergleich (Plugin "Terrain-Import", nur Studio mit Config.Debug.TerrainTestSpawn):
-- Start an der aktiven Varianten-SpawnLocation (Ordner "TerrainVergleich"), ein Stueck bergab
-- davor, damit der Wagen nicht auf der SpawnLocation steht. nil = kein Terrain-Vergleich.
function Track.getTerrainTestSpawn(): CFrame?
	if not Config.Debug.TerrainTestSpawn then
		return nil
	end
	local folder = workspace:FindFirstChild("TerrainVergleich")
	if not folder then
		return nil
	end
	for _, instance in folder:GetDescendants() do
		if
			instance:IsA("SpawnLocation")
			and instance.Enabled
			and instance:GetAttribute("TerrainTest") == true
		then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = if cartsFolder then { folder, cartsFolder } else { folder }
			local position = instance.Position
			local normal = averageGroundNormal(position + Vector3.new(0, 3, 0), params)
			local downhill = if normal then Vector3.new(normal.X, 0, normal.Z) else Vector3.zero
			if downhill.Magnitude < 0.05 then
				downhill = -Vector3.zAxis
			end
			local origin = position + downhill.Unit * 10
			return Track.placeOnGround(CFrame.lookAt(origin, origin + downhill.Unit), { folder }, true)
		end
	end
	return nil
end

-- Ersatz-Start, solange es keine Startzone gibt: vor dem ersten SpawnLocation.
function Track.getFallbackSpawn(): CFrame
	local spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnLocation then
		local origin = (spawnLocation :: BasePart).CFrame * CFrame.new(0, 0, -10)
		return Track.placeOnGround(origin, { spawnLocation }, true)
	end
	return Track.placeOnGround(CFrame.new(0, 10, 0), {}, true)
end

-- Checkpoints: Parts mit Tag "Checkpoint". Wie Zonen nur Messbereiche ohne Kollision.
TagList.watch("Checkpoint", function(instance)
	if instance:IsA("BasePart") then
		prepareZone(instance)
	end
end)

-- Checkpoints dieser Strecke
-- Eindeutiger, stabiler Schluessel eines Checkpoints (Zwischenzeiten, Plausibilitaet).
-- Kopien mit Strg+D heissen gleich - deshalb kommt die (gerundete) Position dazu.
function Track.checkpointKey(instance: Instance): string
	local name = instance:GetFullName()
	if instance:IsA("BasePart") then
		local p = instance.Position
		return `{name}@{math.floor(p.X + 0.5)},{math.floor(p.Y + 0.5)},{math.floor(p.Z + 0.5)}`
	end
	return name
end

function Track.getCheckpoints(trackId: string): { Instance }
	local result = {}
	for _, instance in TagList.get("Checkpoint") do
		if belongsTo(instance, trackId) then
			table.insert(result, instance)
		end
	end
	return result
end

return Track
