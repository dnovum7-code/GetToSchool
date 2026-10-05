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
--   * Sind DataStores nicht erreichbar (Studio ohne API-Zugriff), wird automatisch ein
--     Speicher im Arbeitsspeicher benutzt (nur fuer diese Sitzung), mit Warnung im Output.
--
-- Unity-Vergleich: wie PlayerPrefs bzw. eine Cloud-Save-Datei, nur auf dem Server.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local function load(player: Player, profile: Profile)
	local key = keyFor(player)
	local store = getBackend()
	local ok, raw = retry(function()
		return store.get(key)
	end)
	if not ok and SaveData.isAccessError(tostring(raw)) then
		-- kein Zugriff (Studio): ab jetzt Arbeitsspeicher
		useMemory(tostring(raw))
		store = getBackend()
		ok, raw = retry(function()
			return store.get(key)
		end)
	end
	-- Noch kein Spielstand im neuen Format: einmalig die alten Bestzeiten uebernehmen
	local legacy = legacyBackend
	if ok and raw == nil and store.name == "DataStore" and legacy then
		ok, raw = retry(function()
			return legacy.get(key)
		end)
	end
	if not player.Parent then
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
	if not data then
		profile.state = "Failed"
		warn(
			`[Profiles] Spielstand von {player.Name} stammt von einer neueren Spielversion. `
				.. "Er wird nicht veraendert; Fortschritt dieser Sitzung wird nicht gespeichert."
		)
		fire(loadedCallbacks, player)
		return
	end
	-- Was der Spieler waehrend des Ladens gesammelt hat, geht nicht verloren
	profile.data = SaveData.merge(data, profile.data)
	profile.state = "Ready"
	if note == "migrated" then
		print(`[Profiles] Spielstand von {player.Name} auf Version {SaveData.VERSION} umgestellt.`)
		profile.dirty = true
	end
	fire(loadedCallbacks, player)
	fire(changedCallbacks, player)
end

local function save(player: Player, profile: Profile): boolean
	if profile.state ~= "Ready" or profile.saving or not profile.dirty then
		return false
	end
	profile.saving = true
	profile.dirty = false -- Aenderungen waehrend des Speicherns setzen es wieder
	local snapshot = SaveData.serialize(profile.data)
	local store = getBackend()
	local key = keyFor(player)
	local ok, err = retry(function()
		store.update(key, function(old)
			-- Hat inzwischen eine neuere Spielversion gespeichert? Dann nicht ueberschreiben.
			if type(old) == "table" and type(old.version) == "number" and old.version > SaveData.VERSION then
				return nil
			end
			return snapshot
		end)
		return true
	end)
	profile.saving = false
	if not ok then
		profile.dirty = true -- beim naechsten Mal erneut versuchen
		warn(`[Profiles] Speichern fuer {player.Name} fehlgeschlagen: {err}`)
	end
	return ok
end

local function getProfile(player: Player): Profile
	local profile = profiles[player]
	if not profile then
		profile = { data = SaveData.new(), state = "Loading", dirty = false, saving = false }
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
			save(player, profile)
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
				save(player, profile)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	-- Regelmaessig speichern, was sich geaendert hat
	task.spawn(function()
		while true do
			task.wait(math.max(Config.Save.AutosaveInterval, 10))
			for player, profile in profiles do
				if profile.dirty then
					task.spawn(save, player, profile)
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
