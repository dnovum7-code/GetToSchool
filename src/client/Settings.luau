--!strict
-- Einstellungen des Spielers (Client): Geist an/aus, Kamera-Wackeln, Lautstaerken.
-- Andere Module fragen hier nach (Settings.get) und melden sich fuer Aenderungen an.
-- Gespeichert werden sie im Spielstand: Settings.change schickt die Aenderung an den Server
-- (server/PlayerSettings), beim Laden kommen sie mit dem Snapshot zurueck (Settings.load).
-- Erlaubte Namen und Standardwerte: SaveData.SETTINGS_DEFAULTS.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SaveData =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"):WaitForChild("SaveData"))

local settingsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Settings") :: RemoteEvent

local Settings = {}

export type Values = SaveData.Settings

local values: Values = table.clone(SaveData.SETTINGS_DEFAULTS)
local loaded = false
local listeners: { (key: string, value: any) -> () } = {}

function Settings.get(key: string): any
	return (values :: any)[key]
end

function Settings.getAll(): Values
	return table.clone(values)
end

-- Wert lokal setzen (ohne Speichern)
function Settings.set(key: string, value: any)
	local ok, clean = SaveData.validateSetting(key, value)
	if not ok or (values :: any)[key] == clean then
		return
	end
	(values :: any)[key] = clean
	for _, callback in listeners do
		task.spawn(callback, key, clean)
	end
end

-- Vom Spieler geaendert (Menue): setzen und speichern lassen
function Settings.change(key: string, value: any)
	Settings.set(key, value)
	settingsRemote:FireServer("Set", key, (values :: any)[key])
end

-- Gespeicherte Einstellungen aus dem Snapshot uebernehmen (einmal, wenn geladen)
function Settings.load(snapshot: { [string]: any })
	if loaded or snapshot.state ~= "Ready" or type(snapshot.settings) ~= "table" then
		return
	end
	loaded = true
	for key, value in snapshot.settings do
		Settings.set(key, value)
	end
end

function Settings.onChanged(callback: (key: string, value: any) -> ())
	table.insert(listeners, callback)
end

return Settings
