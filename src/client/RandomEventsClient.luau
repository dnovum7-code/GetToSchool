--!strict
-- Client-Seite der Zufallsereignisse: blendet Objekte mit Tag "RandomEvent", die der Server
-- fuer diesen Lauf nicht ausgewaehlt hat, nur bei diesem Spieler aus.
-- "Ausblenden" heisst: unsichtbar, keine Kollision, fuer Raycasts und Beruehrungs-Abfragen
-- unsichtbar (CanQuery). Damit wirken auch Bausteine darin (z. B. ein Hazard) nicht mehr.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TagList = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TagList"))

local RandomEventsClient = {}

local selection: { [string]: boolean } = {}
-- Originalwerte, damit wir sie beim Wieder-Einblenden zuruecksetzen koennen
local originals: { [Instance]: { [string]: any } } = {}

-- Eigenschaften, die beim Ausblenden geaendert werden (pro Klasse)
local function hiddenValues(item: Instance): { [string]: any }?
	if item:IsA("BasePart") then
		return { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }
	elseif item:IsA("Decal") then -- Decal und Texture
		return { Transparency = 1 }
	elseif item:IsA("ParticleEmitter") or item:IsA("Light") or item:IsA("Beam") or item:IsA("Trail") then
		return { Enabled = false }
	elseif item:IsA("SurfaceGui") or item:IsA("BillboardGui") then
		return { Enabled = false }
	end
	return nil
end

local function setItemActive(item: Instance, active: boolean)
	local hidden = hiddenValues(item)
	if not hidden then
		return
	end
	if active then
		local saved = originals[item]
		if saved then
			for property, value in saved do
				(item :: any)[property] = value
			end
			originals[item] = nil
		end
	else
		if not originals[item] then
			local saved = {}
			for property in hidden do
				saved[property] = (item :: any)[property]
			end
			originals[item] = saved
		end
		for property, value in hidden do
			(item :: any)[property] = value
		end
	end
end

local function apply(instance: Instance)
	local id = instance:GetAttribute("EventId")
	-- Unbekannt (noch keine Auswahl): sichtbar lassen
	local active = if type(id) == "string" and selection[id] ~= nil then selection[id] else true
	setItemActive(instance, active)
	for _, descendant in instance:GetDescendants() do
		setItemActive(descendant, active)
	end
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
