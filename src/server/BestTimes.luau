--!strict
-- Bestzeiten pro Spieler und Track, dauerhaft gespeichert (DataStore).
-- Gespeichert wird pro Track die Bestzeit und die Zwischenzeiten an jedem Checkpoint
-- (fuer die Live-Anzeige "schneller/langsamer als Bestzeit").
--
-- Unity-Vergleich: wie PlayerPrefs, nur auf dem Server und ueber Roblox gespeichert.
-- In Studio funktioniert das nur mit: Game Settings -> Security ->
-- "Enable Studio Access to API Services". Sonst gelten Bestzeiten nur fuer die Sitzung.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local BestTimes = {}

export type Record = {
	time: number,
	splits: { [string]: number }, -- Checkpoint-Schluessel -> Zeit seit Start
}

type PlayerData = { [string]: Record } -- TrackId -> Bestzeit

local cache: { [Player]: PlayerData } = {}
local store: DataStore? = nil
local warnedUnavailable = false

local function warnUnavailable(reason: any)
	if warnedUnavailable then
		return
	end
	warnedUnavailable = true
	warn(
		"[BestTimes] Bestzeiten werden nur fuer diese Sitzung gespeichert. In Studio: Game Settings -> "
			.. "Security -> 'Enable Studio Access to API Services' einschalten. ("
			.. tostring(reason)
			.. ")"
	)
end

local function getStore(): DataStore?
	if not Config.Race.SaveBestTimes then
		return nil
	end
	if not store then
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(Config.Race.BestTimesStore)
		end)
		if ok then
			store = result
		else
			warnUnavailable(result)
		end
	end
	return store
end

local function keyFor(player: Player): string
	return "u_" .. tostring(player.UserId)
end

-- Gespeicherte Daten pruefen (nur gueltige Eintraege uebernehmen)
local function sanitize(raw: any): PlayerData
	local data: PlayerData = {}
	if type(raw) ~= "table" then
		return data
	end
	for trackId, record in raw do
		if type(trackId) == "string" and type(record) == "table" and type(record.time) == "number" then
			local splits = {}
			if type(record.splits) == "table" then
				for key, value in record.splits do
					if type(key) == "string" and type(value) == "number" then
						splits[key] = value
					end
				end
			end
			data[trackId] = { time = record.time, splits = splits }
		end
	end
	return data
end

-- Beim Beitreten laden (im Hintergrund; bis dahin gilt "noch keine Bestzeit").
-- `onLoaded` wird aufgerufen, sobald die gespeicherten Zeiten da sind.
function BestTimes.load(player: Player, onLoaded: (() -> ())?)
	cache[player] = cache[player] or {}
	local dataStore = getStore()
	if not dataStore then
		return
	end
	task.spawn(function()
		local ok, result = pcall(function()
			return (dataStore :: DataStore):GetAsync(keyFor(player))
		end)
		if not ok then
			warnUnavailable(result)
			return
		end
		if player.Parent then
			-- schon in dieser Sitzung gefahrene, bessere Zeiten behalten
			local loaded = sanitize(result)
			local current: PlayerData = cache[player] or {}
			for trackId, record in current do
				local stored = loaded[trackId]
				if not stored or record.time < stored.time then
					loaded[trackId] = record
				end
			end
			cache[player] = loaded
			if onLoaded then
				onLoaded()
			end
		end
	end)
end

function BestTimes.get(player: Player, trackId: string): Record?
	local data = cache[player]
	return if data then data[trackId] else nil
end

-- Neue Zeit melden. Gibt zurueck, ob es eine neue Bestzeit ist, und die alte Bestzeit.
function BestTimes.submit(
	player: Player,
	trackId: string,
	time: number,
	splits: { [string]: number }
): (boolean, number?)
	local data = cache[player] or {}
	cache[player] = data
	local previous = data[trackId]
	if previous and previous.time <= time then
		return false, previous.time
	end
	local record: Record = { time = time, splits = table.clone(splits) }
	data[trackId] = record

	local dataStore = getStore()
	if dataStore then
		task.spawn(function()
			local ok, err = pcall(function()
				(dataStore :: DataStore):UpdateAsync(keyFor(player), function(old: any)
					local stored = sanitize(old)
					local current = stored[trackId]
					if not current or record.time < current.time then
						stored[trackId] = record
					end
					return stored
				end)
			end)
			if not ok then
				warnUnavailable(err)
			end
		end)
	end
	return true, if previous then previous.time else nil
end

Players.PlayerRemoving:Connect(function(player)
	cache[player] = nil
end)

return BestTimes
