--!strict
-- Zufallsereignisse (Tag "RandomEvent"): Der Server wuerfelt beim Start jedes Laufs, welche
-- aktiv sind, und schickt die Auswahl dem Spieler. Dessen Client blendet die inaktiven
-- Objekte bei sich aus (siehe src/client/RandomEventsClient.luau).
--
-- Warum pro Spieler und nicht fuer alle gleich? Jeder Spieler startet seine Laeufe zu
-- anderen Zeiten. Wuerde der Server die gemeinsame Welt umbauen, aenderte sich die Strecke
-- mitten im Lauf eines anderen Spielers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local TagList = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TagList"))

local RandomEvents = {}

export type Selection = { [string]: boolean } -- EventId -> aktiv?

local nextId = 0
local random = Random.new()

function RandomEvents.init()
	-- Jedes Ereignis bekommt eine feste Nummer (Attribut "EventId"), ueber die Server und
	-- Client dasselbe Objekt meinen. Attribute werden automatisch zum Client uebertragen.
	TagList.watch("RandomEvent", function(instance)
		if type(instance:GetAttribute("EventId")) ~= "string" then
			nextId += 1
			instance:SetAttribute("EventId", tostring(nextId))
		end
	end)
end

local function numberAttribute(instance: Instance, name: string, default: number): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else default
end

-- Neue Auswahl wuerfeln.
function RandomEvents.roll(): Selection
	local selection: Selection = {}
	local groups: { [string]: { Instance } } = {}
	for _, instance in TagList.get("RandomEvent") do
		local id = instance:GetAttribute("EventId")
		if type(id) ~= "string" then
			continue
		end
		local group = instance:GetAttribute("Group")
		if type(group) == "string" or type(group) == "number" then
			local key = tostring(group)
			groups[key] = groups[key] or {}
			table.insert(groups[key], instance)
		else
			local chance = math.clamp(numberAttribute(instance, "Chance", Config.Events.DefaultChance), 0, 1)
			selection[id] = random:NextNumber() < chance
		end
	end
	-- Pro Gruppe genau eins, gewichtet mit "Chance"
	for _, members in groups do
		local total = 0
		for _, member in members do
			total += math.max(numberAttribute(member, "Chance", Config.Events.DefaultGroupWeight), 0)
		end
		local pick = random:NextNumber() * total
		local chosen: Instance = members[#members]
		for _, member in members do
			pick -= math.max(numberAttribute(member, "Chance", Config.Events.DefaultGroupWeight), 0)
			if pick < 0 then
				chosen = member
				break
			end
		end
		if total <= 0 then
			chosen = members[random:NextInteger(1, #members)]
		end
		for _, member in members do
			selection[member:GetAttribute("EventId") :: string] = member == chosen
		end
	end
	return selection
end

return RandomEvents
