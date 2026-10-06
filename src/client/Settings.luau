--!strict
-- Einstellungen des Spielers (nur Client): Geist an/aus, Kamera-Wackeln, Lautstaerken ...
-- Andere Module fragen hier nach und melden sich fuer Aenderungen an.
-- Gespeichert werden sie im Spielstand (siehe Einstellungsmenue).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Settings = {}

export type Values = {
	Ghost: boolean,
	CameraShake: boolean,
	MusicVolume: number,
	EffectsVolume: number,
}

local values: Values = {
	Ghost = Config.Ghost.Enabled,
	CameraShake = true,
	MusicVolume = 0.5,
	EffectsVolume = 1,
}

local listeners: { (key: string, value: any) -> () } = {}

function Settings.get(key: string): any
	return (values :: any)[key]
end

function Settings.getAll(): Values
	return table.clone(values)
end

function Settings.set(key: string, value: any)
	local current = (values :: any)[key]
	if current == nil or type(current) ~= type(value) or current == value then
		return
	end
	(values :: any)[key] = value
	for _, callback in listeners do
		task.spawn(callback, key, value)
	end
end

-- Mehrere Werte auf einmal (z. B. gespeicherte Einstellungen vom Server)
function Settings.apply(newValues: { [string]: any })
	for key, value in newValues do
		Settings.set(key, value)
	end
end

function Settings.onChanged(callback: (key: string, value: any) -> ())
	table.insert(listeners, callback)
end

return Settings
