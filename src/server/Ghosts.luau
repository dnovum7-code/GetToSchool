--!strict
-- Geist vom besten Lauf, Server-Seite:
--   * zeichnet waehrend jedes Laufs die Lage des Wagens auf (so wie der Server ihn sieht)
--   * ist der Lauf eine neue Bestzeit, wird die Aufnahme gespeichert (eigener DataStore,
--     Schluessel pro Spieler und Strecke) und dem Client geschickt
--   * beim Start eines Laufs bekommt der Client den Geist seiner Strecke (einmal pro Sitzung)
-- Der Server zeichnet selbst auf: Kein Client kann einen falschen Geist hochladen.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GhostCodec = require(Shared:WaitForChild("Progression"):WaitForChild("GhostCodec"))
local SaveData = require(Shared:WaitForChild("Progression"):WaitForChild("SaveData"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))

local ghostRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Ghost") :: RemoteEvent

local Ghosts = {}

type Recording = {
	trackId: string,
	samples: { GhostCodec.Sample },
	nextAt: number,
}

local recordings: { [Player]: Recording } = {}
local loaded: { [Player]: { [string]: any } } = {} -- trackId -> Geist (Tabelle) oder false
local memory: { [string]: any } = {} -- Ersatz, wenn DataStores nicht gehen (Studio)
local store: DataStore? = nil

local function maxSamples(): number
	return math.floor(Config.Ghost.MaxDuration / math.max(Config.Ghost.SampleInterval, 0.02)) + 2
end

local function keyFor(player: Player, trackId: string): string
	return `g_{player.UserId}_{trackId}`
end

local function useMemory(): boolean
	return Profiles.getBackendName() == "Memory"
end

local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Ghost.StoreName)
	end)
	if ok then
		store = result
	end
	return store
end

local function retry(fn: () -> any): (boolean, any)
	local S = Config.Save
	local ok, result = SaveData.withRetry(fn, S.Retries, S.RetryDelay, task.wait, SaveData.isAccessError)
	return ok, result
end

local function load(player: Player, trackId: string): any
	local key = keyFor(player, trackId)
	if useMemory() then
		return memory[key]
	end
	local dataStore = getStore()
	if not dataStore then
		return nil
	end
	local ok, result = retry(function()
		return dataStore:GetAsync(key)
	end)
	return if ok then result else nil
end

local function save(player: Player, trackId: string, ghost: GhostCodec.Ghost)
	local key = keyFor(player, trackId)
	if useMemory() then
		memory[key] = ghost
		return
	end
	local dataStore = getStore()
	if not dataStore then
		return
	end
	local ok, err = retry(function()
		dataStore:SetAsync(key, ghost)
		return true
	end)
	if not ok then
		warn(`[Ghosts] Geist fuer {player.Name} ({trackId}) nicht gespeichert: {err}`)
	end
end

-- Lauf beginnt (Startzone verlassen): Aufnahme starten
function Ghosts.start(player: Player, trackId: string)
	recordings[player] = { trackId = trackId, samples = {}, nextAt = 0 }
end

-- Jeden Frame waehrend des Laufs: Lage des Wagens aufnehmen (alle SampleInterval Sekunden)
function Ghosts.record(player: Player, cframe: CFrame, elapsed: number)
	local recording = recordings[player]
	if not recording or elapsed < recording.nextAt then
		return
	end
	if #recording.samples >= maxSamples() then
		return -- zu lang, wird nicht gespeichert
	end
	-- Aufnahmen in festem Abstand: fehlende (z. B. nach einem Ruckler) mit der aktuellen Lage auffuellen
	local rx, ry, rz = cframe:ToEulerAnglesXYZ()
	local position = cframe.Position
	local sample = { position.X, position.Y, position.Z, math.deg(rx), math.deg(ry), math.deg(rz) }
	while elapsed >= recording.nextAt and #recording.samples < maxSamples() do
		table.insert(recording.samples, sample)
		recording.nextAt += Config.Ghost.SampleInterval
	end
end

-- Lauf abgebrochen (Neustart, Aussteigen, Game Over): Aufnahme verwerfen
function Ghosts.cancel(player: Player)
	recordings[player] = nil
end

-- Ziel erreicht. Bei neuer Bestzeit wird der Geist gespeichert und dem Client geschickt.
function Ghosts.finish(player: Player, trackId: string, isNewBest: boolean, time: number)
	local recording = recordings[player]
	recordings[player] = nil
	if not isNewBest or not recording or recording.trackId ~= trackId or #recording.samples < 2 then
		return
	end
	if time > Config.Ghost.MaxDuration then
		return
	end
	local ghost = GhostCodec.encode(recording.samples, Config.Ghost.SampleInterval, time)
	local perPlayer = loaded[player]
	if not perPlayer then
		perPlayer = {}
		loaded[player] = perPlayer
	end
	perPlayer[trackId] = ghost
	ghostRemote:FireClient(player, "Data", trackId, ghost)
	task.spawn(save, player, trackId, ghost)
end

-- Neuer Lauf auf `trackId`: Client sagen, welche Strecke, und den Geist schicken
-- (aus dem DataStore geladen, einmal pro Sitzung und Strecke).
function Ghosts.announce(player: Player, trackId: string)
	ghostRemote:FireClient(player, "Current", trackId)
	local perPlayer = loaded[player]
	if not perPlayer then
		perPlayer = {}
		loaded[player] = perPlayer
	end
	if perPlayer[trackId] ~= nil then
		return -- schon geschickt
	end
	perPlayer[trackId] = false -- laedt gerade / keiner
	task.spawn(function()
		local raw = load(player, trackId)
		if not player.Parent then
			return
		end
		local samples = GhostCodec.decode(raw, maxSamples())
		-- inzwischen schon eine neue Bestzeit gefahren? Dann nicht mit dem alten Geist ueberschreiben
		if samples and loaded[player] == perPlayer and perPlayer[trackId] == false then
			perPlayer[trackId] = raw
			ghostRemote:FireClient(player, "Data", trackId, raw)
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	recordings[player] = nil
	loaded[player] = nil
end)

return Ghosts
