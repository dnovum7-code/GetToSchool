--!strict
-- Signale des Baukastens (nur auf diesem Client): Eine TriggerZone loest ein Signal aus,
-- Bausteine mit passendem Attribut "ListenSignal" reagieren (Steinschlag, Tor oeffnet ...).
-- Unity-Vergleich: ein einfacher Event-Bus (wie UnityEvent mit Namen).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Signals = {}

local listeners: { [string]: { [number]: (name: string) -> () } } = {}
local nextKey = 0

function Signals.debugLog(message: string)
	if Config.Debug.Toolkit and RunService:IsStudio() then
		print("[Baukasten] " .. message)
	end
end

-- `callback` bei Signal `name` aufrufen. Gibt eine Funktion zum Abmelden zurueck.
function Signals.on(name: string, callback: (name: string) -> ()): () -> ()
	local list = listeners[name]
	if not list then
		list = {}
		listeners[name] = list
	end
	nextKey += 1
	local key = nextKey
	list[key] = callback
	return function()
		local current = listeners[name]
		if current then
			current[key] = nil
		end
	end
end

function Signals.fire(name: string, source: string?)
	local list = listeners[name]
	local count = 0
	if list then
		for _, callback in list do
			count += 1
			task.spawn(callback, name)
		end
	end
	Signals.debugLog(
		`Signal "{name}" ausgeloest{if source then " von " .. source else ""}: {count} Baustein(e) reagieren`
	)
end

return Signals
