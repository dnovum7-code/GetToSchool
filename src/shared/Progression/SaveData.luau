--!strict
-- Datenformat des Spielstands (pro Spieler) - reine Logik ohne Roblox-Dienste, damit die
-- automatischen Tests (tests/, mit Lune) sie auch ausserhalb von Studio pruefen koennen.
--
-- Gespeichert werden: Muenzen, gekaufte Upgrades mit Stufe, Bestzeiten und beste Noten pro
-- Track, freigeschaltete Tracks und Fahrzeuge, Flug-Rekorde (Launchables) und ein paar Zahlen.
--
-- Version: Jeder Spielstand hat eine Versionsnummer. Aendert sich das Format, wird VERSION
-- erhoeht und in MIGRATIONS ein Schritt "alte Version -> neue Version" ergaenzt. Alte
-- Spielstaende werden beim Laden Schritt fuer Schritt hochgestuft.
--   Version 0: altes Format (nur Bestzeiten, DataStore "BestTimes_v1")
--   Version 1: dieses Format

local SaveData = {}

SaveData.VERSION = 1

export type BestTime = {
	time: number, -- Sekunden
	splits: { [string]: number }, -- Checkpoint -> Zeit seit Start
}

export type Stats = {
	finishedRuns: number,
	coinsCollected: number, -- eingesammelte Muenzen (ohne Belohnungen)
	objectsLaunched: number,
}

export type Data = {
	version: number,
	coins: number,
	upgrades: { [string]: number }, -- Upgrade-Id -> Stufe (0 = nicht gekauft)
	bestTimes: { [string]: BestTime }, -- TrackId -> Bestzeit
	bestGrades: { [string]: number }, -- TrackId -> beste Note (6 = beste)
	unlockedTracks: { [string]: boolean },
	vehicles: { [string]: boolean },
	launchRecords: { [string]: number }, -- Objektname (z. B. "Kuh") -> weitester Flug in Metern
	stats: Stats,
}

local DEFAULT_VEHICLE = "ShoppingCart"

function SaveData.new(): Data
	return {
		version = SaveData.VERSION,
		coins = 0,
		upgrades = {},
		bestTimes = {},
		bestGrades = {},
		unlockedTracks = {},
		vehicles = { [DEFAULT_VEHICLE] = true },
		launchRecords = {},
		stats = { finishedRuns = 0, coinsCollected = 0, objectsLaunched = 0 },
	}
end

local function isNumber(value: unknown): boolean
	-- value == value: kein NaN; ausserdem keine Unendlichkeit
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function wholeNumber(value: unknown, min: number): number?
	if not isNumber(value) then
		return nil
	end
	return math.max(math.floor(value :: number), min)
end

local function sanitizeBestTimes(raw: unknown): { [string]: BestTime }
	local result: { [string]: BestTime } = {}
	if type(raw) ~= "table" then
		return result
	end
	for trackId, record in raw :: { [any]: any } do
		if
			type(trackId) == "string"
			and type(record) == "table"
			and isNumber(record.time)
			and record.time > 0
		then
			local splits: { [string]: number } = {}
			if type(record.splits) == "table" then
				for key, value in record.splits do
					if type(key) == "string" and isNumber(value) then
						splits[key] = value
					end
				end
			end
			result[trackId] = { time = record.time, splits = splits }
		end
	end
	return result
end

-- Tabelle "Text -> Zahl" pruefen; `min`/`max` begrenzen, `whole` = nur ganze Zahlen
local function sanitizeNumberMap(raw: unknown, min: number, max: number, whole: boolean): { [string]: number }
	local result: { [string]: number } = {}
	if type(raw) ~= "table" then
		return result
	end
	for key, value in raw :: { [any]: any } do
		if type(key) == "string" and isNumber(value) then
			local number = math.clamp(value, min, max)
			result[key] = if whole then math.floor(number) else number
		end
	end
	return result
end

local function sanitizeFlags(raw: unknown): { [string]: boolean }
	local result: { [string]: boolean } = {}
	if type(raw) ~= "table" then
		return result
	end
	for key, value in raw :: { [any]: any } do
		if type(key) == "string" and value == true then
			result[key] = true
		end
	end
	return result
end

-- Spielstand der aktuellen Version pruefen: unbekannte oder kaputte Eintraege fallen weg,
-- fehlende bekommen Standardwerte.
function SaveData.sanitize(raw: { [any]: any }): Data
	local data = SaveData.new()
	data.coins = wholeNumber(raw.coins, 0) or 0
	data.upgrades = sanitizeNumberMap(raw.upgrades, 0, 100, true)
	data.bestTimes = sanitizeBestTimes(raw.bestTimes)
	data.bestGrades = sanitizeNumberMap(raw.bestGrades, 1, 6, true)
	data.unlockedTracks = sanitizeFlags(raw.unlockedTracks)
	data.vehicles = sanitizeFlags(raw.vehicles)
	data.vehicles[DEFAULT_VEHICLE] = true
	data.launchRecords = sanitizeNumberMap(raw.launchRecords, 0, 1e7, false)
	local stats = if type(raw.stats) == "table" then raw.stats else {}
	data.stats = {
		finishedRuns = wholeNumber(stats.finishedRuns, 0) or 0,
		coinsCollected = wholeNumber(stats.coinsCollected, 0) or 0,
		objectsLaunched = wholeNumber(stats.objectsLaunched, 0) or 0,
	}
	return data
end

-- Schritte zum Hochstufen: MIGRATIONS[v] macht aus Version v die Version v + 1.
local MIGRATIONS: { [number]: (raw: { [any]: any }) -> { [any]: any } } = {
	-- 0 -> 1: Das alte Format war nur "TrackId -> Bestzeit"
	[0] = function(raw)
		return { version = 1, bestTimes = raw }
	end,
}

-- Gespeicherte Daten (egal welche Version) in das aktuelle Format bringen.
-- Rueckgabe: Daten und ein Hinweis ("new", "ok", "migrated", "invalid"), oder nil und
-- "newer", wenn der Spielstand von einer neueren Spielversion stammt. Den darf diese
-- Version nicht ueberschreiben (sonst gingen Daten verloren).
function SaveData.migrate(raw: unknown): (Data?, string)
	if raw == nil then
		return SaveData.new(), "new"
	end
	if type(raw) ~= "table" then
		return SaveData.new(), "invalid"
	end
	local current: { [any]: any } = raw :: any
	local version = if isNumber(current.version) then math.floor(current.version) else 0
	if version > SaveData.VERSION then
		return nil, "newer"
	end
	local note = "ok"
	while version < SaveData.VERSION do
		local step = MIGRATIONS[version]
		if not step then
			return SaveData.new(), "invalid"
		end
		current = step(current)
		version += 1
		note = "migrated"
	end
	return SaveData.sanitize(current), note
end

-- Waehrend des Ladens gesammelter Fortschritt (`session`, startete mit SaveData.new())
-- wird mit dem geladenen Spielstand (`stored`) zusammengefuehrt. Nichts geht verloren:
-- Muenzen werden addiert, bei Zeiten zaehlt die bessere, bei Stufen die hoehere.
function SaveData.merge(stored: Data, session: Data): Data
	local result = SaveData.sanitize(stored :: any)
	result.coins += session.coins
	for id, level in session.upgrades do
		result.upgrades[id] = math.max(result.upgrades[id] or 0, level)
	end
	for trackId, record in session.bestTimes do
		local existing = result.bestTimes[trackId]
		if not existing or record.time < existing.time then
			result.bestTimes[trackId] = { time = record.time, splits = table.clone(record.splits) }
		end
	end
	for trackId, grade in session.bestGrades do
		result.bestGrades[trackId] = math.max(result.bestGrades[trackId] or 0, grade)
	end
	for id in session.unlockedTracks do
		result.unlockedTracks[id] = true
	end
	for id in session.vehicles do
		result.vehicles[id] = true
	end
	for name, meters in session.launchRecords do
		result.launchRecords[name] = math.max(result.launchRecords[name] or 0, meters)
	end
	result.stats.finishedRuns += session.stats.finishedRuns
	result.stats.coinsCollected += session.stats.coinsCollected
	result.stats.objectsLaunched += session.stats.objectsLaunched
	return result
end

-- Kopie zum Speichern (DataStores speichern JSON: nur Text-Schluessel, keine Funktionen)
function SaveData.serialize(data: Data): { [string]: any }
	local copy = SaveData.sanitize(data :: any)
	return copy :: any
end

-- Sitzungs-Sperre ------------------------------------------------------------------------
-- Wechselt ein Spieler schnell den Server, koennte der neue Server den Spielstand laden,
-- bevor der alte fertig gespeichert hat - und spaeter mit veralteten Daten ueberschreiben.
-- Deshalb steht im gespeicherten Datensatz, welcher Server ihn gerade benutzt
-- (`session = { id, time }`). Ein anderer Server wartet, bis die Sperre frei ist, und
-- ein Server, dessen Sperre uebernommen wurde, speichert nicht mehr.

-- Zustand der Sperre im gespeicherten Datensatz `old` aus Sicht von `sessionId`:
--   "Free"   kein Datensatz, keine Sperre, oder Sperre abgelaufen (Server abgestuerzt)
--   "Ours"   wir haben die Sperre
--   "Locked" ein anderer Server benutzt den Spielstand gerade
--   "Newer"  Datensatz einer neueren Spielversion (nicht anfassen)
function SaveData.lockState(old: unknown, sessionId: string, now: number, timeout: number): string
	if type(old) ~= "table" then
		return "Free"
	end
	local record = old :: { [any]: any }
	if isNumber(record.version) and record.version > SaveData.VERSION then
		return "Newer"
	end
	local session = record.session
	if type(session) ~= "table" or type(session.id) ~= "string" then
		return "Free"
	end
	if session.id == sessionId then
		return "Ours"
	end
	if not isNumber(session.time) or now - session.time >= timeout then
		return "Free"
	end
	return "Locked"
end

-- Kopie des Datensatzes mit gesetzter (sessionId) oder freigegebener (nil) Sperre
function SaveData.withSession(record: { [any]: any }, sessionId: string?, now: number): { [any]: any }
	local copy = table.clone(record)
	copy.session = if sessionId then { id = sessionId, time = now } else nil
	return copy
end

-- Fuehrt `fn` aus und wiederholt es bei Fehlern (bis zu `attempts` Mal, Wartezeit
-- verdoppelt sich: baseDelay, 2 * baseDelay, ...). `wait` wartet (in Roblox task.wait).
-- `isFatal(err)`: bei diesen Fehlern sofort aufgeben (z. B. kein Zugriff in Studio).
-- Rueckgabe: Erfolg, Ergebnis bzw. letzte Fehlermeldung, Anzahl Versuche.
function SaveData.withRetry(
	fn: () -> any,
	attempts: number,
	baseDelay: number,
	wait: (number) -> (),
	isFatal: ((string) -> boolean)?
): (boolean, any, number)
	local lastError: any = nil
	local tries = math.max(1, math.floor(attempts))
	for attempt = 1, tries do
		local ok, result = pcall(fn)
		if ok then
			return true, result, attempt
		end
		lastError = result
		if isFatal and isFatal(tostring(result)) then
			return false, result, attempt
		end
		if attempt < tries then
			wait(baseDelay * 2 ^ (attempt - 1))
		end
	end
	return false, lastError, tries
end

-- Fehlermeldung "kein Zugriff auf DataStores" (Studio ohne API-Zugriff, unveroeffentlicht)?
function SaveData.isAccessError(message: string): boolean
	local lower = string.lower(message)
	return string.find(lower, "403", 1, true) ~= nil
		or string.find(lower, "studioaccess", 1, true) ~= nil
		or string.find(lower, "not allowed", 1, true) ~= nil
		or string.find(lower, "publish", 1, true) ~= nil
end

return SaveData
