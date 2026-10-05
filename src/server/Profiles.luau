--!strict
-- Spielstaende der Spieler laden und speichern (DataStore). Der Server ist der Einzige,
-- der Spielstaende aendert (Muenzen, Upgrades, Bestzeiten ...).
--
-- Ablauf:
--   * Beim Beitreten wird geladen (im Hintergrund, mit Wiederholungen bei Fehlern).
--     Bis dahin sammelt der Spieler in einem vorlaeufigen Spielstand; der wird nach dem
--     Laden mit dem gespeicherten zusammengefuehrt (siehe SaveData.merge).
--   * Gespeichert wird regelmaessig (Config.Save.AutosaveInterval), beim Verlassen und
--     beim Herunterfahren des Servers.
--   * Klappt das Laden gar nicht, wird fuer diesen Spieler NICHT gespeichert. Sonst
--     koennte ein leerer Spielstand den echten ueberschreiben (Datenverlust).
--   * Sitzungs-Sperre: Der Datensatz merkt sich, welcher Server ihn benutzt. Wechselt ein
--     Spieler schnell den Server, wartet der neue, bis der alte fertig gespeichert hat
--     (hoechstens Config.Save.LockAttempts Versuche, dann uebernimmt er). Ein Server, dessen
--     Sperre uebernommen wurde, speichert nicht mehr - so ueberschreibt nie ein alter Stand
--     einen neueren.
--   * Sind DataStores in Studio nicht erreichbar (kein API-Zugriff), wird automatisch ein
--     Speicher im Arbeitsspeicher benutzt (nur fuer diese Sitzung), mit Warnung im Output.
--
-- Unity-Vergleich: wie PlayerPrefs bzw. eine Cloud-Save-Datei, nur auf dem Server.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SaveData = require(Shared:WaitForChild("Progression"):WaitForChild("SaveData"))

local Profiles = {}

export type State = "Loading" | "Ready" | "Failed"

type Profile = {
	data: SaveData.Data,
	state: State,
	dirty: boolean,
	saving: boolean,
	lastSave: number, -- os.clock() des letzten Speicherns (haelt die Sperre frisch)
}

-- Ein Speicherort: echter DataStore oder Ersatz im Arbeitsspeicher
type Backend = {
	name: string,
	get: (key: string) -> any,
	update: (key: string, transform: (old: any) -> any) -> (),
}

local profiles: { [Player]: Profile } = {}
local loadedCallbacks: { (Player) -> () } = {}
local changedCallbacks: { (Player) -> () } = {}

local backend: Backend? = nil
local legacyBackend: Backend? = nil
local memory: { [string]: any } = {}
-- Kennung dieses Servers fuer die Sitzungs-Sperre (game.JobId ist in Studio leer)
local sessionId = HttpService:GenerateGUID(false)

local function memoryBackend(): Backend
	return {
		name = "Memory",
		get = function(key)
			return memory[key]
		end,
		update = function(key, transform)
			local new = transform(memory[key])
			if new ~= nil then
				memory[key] = new
			end
		end,
	}
end

local function dataStoreBackend(storeName: string): Backend
	-- GetDataStore kann in Studio ohne API-Zugriff einen Fehler werfen (pcall beim Aufrufer)
	local store = DataStoreService:GetDataStore(storeName)
	return {
		name = "DataStore",
		get = function(key)
			return store:GetAsync(key)
		end,
		update = function(key, transform)
			store:UpdateAsync(key, transform)
		end,
	}
end

local function useMemory(reason: string)
	if backend and backend.name == "Memory" then
		return
	end
	backend = memoryBackend()
	legacyBackend = nil
	warn(
		"[Profiles] DataStores nicht verfuegbar - Spielstaende werden nur im Arbeitsspeicher "
			.. "gehalten (gehen beim Beenden verloren). In Studio: Game Settings -> Security -> "
			.. "'Enable Studio Access to API Services' einschalten. Grund: "
			.. reason
	)
end

local function getBackend(): Backend
	local current = backend
	if current then
		return current
	end
	if not Config.Save.Enabled then
		warn("[Profiles] Config.Save.Enabled = false: Spielstaende nur im Arbeitsspeicher.")
		backend = memoryBackend()
		return backend :: Backend
	end
	local ok, result = pcall(dataStoreBackend, Config.Save.StoreName)
	if ok then
		backend = result
		local legacyOk, legacy = pcall(dataStoreBackend, Config.Save.LegacyBestTimesStore)
		legacyBackend = if legacyOk then legacy else nil
	else
		useMemory(tostring(result))
	end
	return backend :: Backend
end

local function keyFor(player: Player): string
	return "u_" .. tostring(player.UserId)
end

local function retry(fn: () -> any): (boolean, any)
	local S = Config.Save
	local ok, result = SaveData.withRetry(fn, S.Retries, S.RetryDelay, task.wait, SaveData.isAccessError)
	return ok, result
end

local function fire(callbacks: { (Player) -> () }, player: Player)
	for _, callback in callbacks do
		task.spawn(callback, player)
	end
end

-- Spielstand lesen und gleichzeitig die Sitzungs-Sperre setzen (ein UpdateAsync).
-- Benutzt gerade ein anderer Server den Spielstand, wird gewartet und erneut versucht;
-- beim letzten Versuch uebernehmen wir die Sperre.
-- Rueckgabe: Erfolg, gelesener Datensatz (oder Fehlermeldung), Zustand der Sperre
local function readAndLock(store: Backend, key: string): (boolean, any, string)
	local S = Config.Save
	local attempts = math.max(1, math.floor(S.LockAttempts))
	for attempt = 1, attempts do
		local force = attempt == attempts
		local raw: any = nil
		local status = "Free"
		local ok, err = retry(function()
			store.update(key, function(old)
				raw = old
				status = SaveData.lockState(old, sessionId, os.time(), S.LockTimeout)
				if status == "Newer" or (status == "Locked" and not force) then
					return nil -- nichts schreiben
				end
				local record = if type(old) == "table" then old else { version = SaveData.VERSION }
				return SaveData.withSession(record, sessionId, os.time())
			end)
			return true
		end)
		if not ok then
			return false, err, "Error"
		end
		if status ~= "Locked" or force then
			return true, raw, status
		end
		task.wait(S.LockRetryDelay) -- der andere Server speichert gerade noch
	end
	return false, "Sperre", "Locked"
end

local function load(player: Player, profile: Profile)
	local key = keyFor(player)
	local store = getBackend()
	local ok, raw, lock = readAndLock(store, key)
	if not ok and RunService:IsStudio() and SaveData.isAccessError(tostring(raw)) then
		-- kein Zugriff in Studio: ab jetzt Arbeitsspeicher (im echten Spiel nie, sonst
		-- wuerden alle Spieler dieses Servers ihre Speicherstaende verlieren)
		useMemory(tostring(raw))
		store = getBackend()
		ok, raw, lock = readAndLock(store, key)
	end
	-- Noch kein Spielstand im neuen Format: einmalig die alten Bestzeiten uebernehmen
	local legacy = legacyBackend
	if ok and raw == nil and store.name == "DataStore" and legacy then
		ok, raw = retry(function()
			return legacy.get(key)
		end)
	end
	if not player.Parent then
		-- Spieler ist waehrend des Ladens gegangen: Sperre gleich wieder freigeben
		if ok then
			retry(function()
				store.update(key, function(old)
					if SaveData.lockState(old, sessionId, os.time(), Config.Save.LockTimeout) == "Ours" then
						return SaveData.withSession(old, nil, os.time())
					end
					return nil
				end)
				return true
			end)
		end
		return
	end

	if not ok then
		profile.state = "Failed"
		warn(
			`[Profiles] Spielstand von {player.Name} konnte nicht geladen werden ({raw}). `
				.. "Fortschritt dieser Sitzung wird NICHT gespeichert, damit nichts ueberschrieben wird."
		)
		fire(loadedCallbacks, player)
		return
	end
	local data, note = SaveData.migrate(raw)
	if not data or lock == "Newer" then
		profile.state = "Failed"
		warn(
			`[Profiles] Spielstand von {player.Name} stammt von einer neueren Spielversion. `
				.. "Er wird nicht veraendert; Fortschritt dieser Sitzung wird nicht gespeichert."
		)
		fire(loadedCallbacks, player)
		return
	end
	if lock == "Locked" then
		warn(
			`[Profiles] Spielstand von {player.Name} war noch von einem anderen Server gesperrt - uebernommen.`
		)
	end
	-- Was der Spieler waehrend des Ladens gesammelt hat, geht nicht verloren
	profile.data = SaveData.merge(data, profile.data)
	profile.state = "Ready"
	profile.lastSave = os.clock()
	if note == "migrated" then
		print(`[Profiles] Spielstand von {player.Name} auf Version {SaveData.VERSION} umgestellt.`)
		profile.dirty = true
	end
	fire(loadedCallbacks, player)
	fire(changedCallbacks, player)
end

-- Speichern. `release`: Sitzungs-Sperre freigeben (Spieler verlaesst den Server).
-- `force`: auch ohne Aenderungen speichern (haelt die Sperre frisch bzw. gibt sie frei).
local function save(player: Player, profile: Profile, release: boolean?, force: boolean?): boolean
	if profile.state ~= "Ready" or profile.saving or not (profile.dirty or force) then
		return false
	end
	profile.saving = true
	profile.dirty = false -- Aenderungen waehrend des Speicherns setzen es wieder
	local snapshot = SaveData.serialize(profile.data)
	local store = getBackend()
	local key = keyFor(player)
	local lost: string? = nil
	local ok, err = retry(function()
		lost = nil
		store.update(key, function(old)
			local status = SaveData.lockState(old, sessionId, os.time(), Config.Save.LockTimeout)
			if status == "Newer" or status == "Locked" then
				-- Neuere Spielversion oder ein anderer Server hat uebernommen: nicht ueberschreiben
				lost = status
				return nil
			end
			return SaveData.withSession(snapshot, if release then nil else sessionId, os.time())
		end)
		return true
	end)
	profile.saving = false
	profile.lastSave = os.clock()
	if not ok then
		profile.dirty = true -- beim naechsten Mal erneut versuchen
		warn(`[Profiles] Speichern fuer {player.Name} fehlgeschlagen: {err}`)
		return false
	end
	if lost then
		profile.state = "Failed"
		warn(
			`[Profiles] Spielstand von {player.Name} wird inzwischen von einem anderen Server `
				.. `benutzt ({lost}) - dieser Server speichert ihn nicht mehr.`
		)
		return false
	end
	return true
end

local function getProfile(player: Player): Profile
	local profile = profiles[player]
	if not profile then
		profile =
			{ data = SaveData.new(), state = "Loading", dirty = false, saving = false, lastSave = os.clock() }
		profiles[player] = profile
	end
	return profile
end

function Profiles.init()
	local function onPlayerAdded(player: Player)
		local profile = getProfile(player)
		task.spawn(load, player, profile)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if profile then
			-- Wartet ein Speichern noch, kurz abwarten und dann sicher speichern
			while profile.saving do
				task.wait(0.1)
			end
			save(player, profile, true, true) -- letzter Stand, Sperre freigeben
			profiles[player] = nil
		end
	end)

	-- Server faehrt herunter: alle noch einmal speichern (Roblox wartet bis zu 30 s)
	game:BindToClose(function()
		local pending = 0
		for player, profile in profiles do
			pending += 1
			task.spawn(function()
				while profile.saving do
					task.wait(0.1)
				end
				save(player, profile, true, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	-- Regelmaessig speichern, was sich geaendert hat. Ohne Aenderungen trotzdem ab und zu,
	-- damit die Sitzungs-Sperre frisch bleibt (sonst koennte ein anderer Server sie nehmen).
	task.spawn(function()
		while true do
			task.wait(math.max(Config.Save.AutosaveInterval, 10))
			for player, profile in profiles do
				local stale = os.clock() - profile.lastSave > Config.Save.LockTimeout / 2
				if profile.dirty or stale then
					task.spawn(save, player, profile, false, stale)
				end
			end
		end
	end)
end

-- Spielstand des Spielers (waehrend des Ladens: der vorlaeufige). Nach Aenderungen
-- Profiles.markChanged aufrufen!
function Profiles.get(player: Player): SaveData.Data
	return getProfile(player).data
end

-- "Loading", "Ready" oder "Failed" (Laden fehlgeschlagen: es wird nicht gespeichert)
function Profiles.getState(player: Player): State
	return getProfile(player).state
end

-- Name des Speicherorts ("DataStore" oder "Memory")
function Profiles.getBackendName(): string
	return getBackend().name
end

-- Nach jeder Aenderung am Spielstand aufrufen: wird gespeichert und an den Client gemeldet.
function Profiles.markChanged(player: Player)
	local profile = profiles[player]
	if profile then
		profile.dirty = true
		fire(changedCallbacks, player)
	end
end

-- Muenzen gutschreiben (auch negativ, nie unter 0). Gibt den neuen Stand zurueck.
function Profiles.addCoins(player: Player, amount: number): number
	local data = Profiles.get(player)
	data.coins = math.max(0, data.coins + math.floor(amount))
	Profiles.markChanged(player)
	return data.coins
end

-- `callback(player)`, sobald der Spielstand geladen ist (oder das Laden aufgegeben wurde)
function Profiles.onLoaded(callback: (Player) -> ())
	table.insert(loadedCallbacks, callback)
end

-- `callback(player)` nach jeder Aenderung am Spielstand
function Profiles.onChanged(callback: (Player) -> ())
	table.insert(changedCallbacks, callback)
end

-- Sofort speichern (z. B. nach einem Kauf). Laeuft im Hintergrund.
function Profiles.saveSoon(player: Player)
	local profile = profiles[player]
	if profile then
		task.spawn(save, player, profile)
	end
end

return Profiles
