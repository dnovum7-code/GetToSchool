--!strict
-- Client-Seite der Zufallsereignisse: blendet Objekte mit Tag "RandomEvent", die der Server
-- fuer diesen Lauf nicht ausgewaehlt hat, nur bei diesem Spieler aus (siehe LocalHide).
-- Damit wirken auch Bausteine darin (z. B. ein Hazard) nicht mehr.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TagList = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TagList"))
local LocalHide = require(script.Parent:WaitForChild("LocalHide"))

local RandomEventsClient = {}

local selection: { [string]: boolean } = {}

local function apply(instance: Instance)
	local id = instance:GetAttribute("EventId")
	-- Unbekannt (noch keine Auswahl): sichtbar lassen
	local active = if type(id) == "string" and selection[id] ~= nil then selection[id] else true
	LocalHide.set(instance, "RandomEvent", not active)
end

function RandomEventsClient.init()
	-- auch fuer Objekte, die erst spaeter (Streaming) geladen werden
	TagList.watch("RandomEvent", apply)
end

-- Neue Auswahl vom Server anwenden
function RandomEventsClient.setSelection(newSelection: { [string]: boolean })
	selection = newSelection
	for _, instance in TagList.get("RandomEvent") do
		apply(instance)
	end
end

return RandomEventsClient
