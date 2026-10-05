--!strict
-- Haelt pro Tag (CollectionService) eine aktuelle Liste aller getaggten Objekte im Workspace.
-- Statt jeden Frame neu zu suchen, hoeren wir auf "hinzugefuegt"/"entfernt" (das passiert
-- auch, wenn Teile durch Streaming geladen oder entladen werden).
--
-- Unity-Vergleich: wie eine statische Liste, in die sich Komponenten in OnEnable eintragen.

local CollectionService = game:GetService("CollectionService")

local TagList = {}

type Entry = {
	items: { Instance },
	callbacks: { (Instance) -> () },
}

local entries: { [string]: Entry } = {}

local function getEntry(tag: string): Entry
	local entry = entries[tag]
	if entry then
		return entry
	end
	local newEntry: Entry = { items = {}, callbacks = {} }
	entries[tag] = newEntry

	local function add(instance: Instance)
		-- Nur Objekte in der Welt (nicht z. B. Vorlagen in ReplicatedStorage)
		if not instance:IsDescendantOf(workspace) or table.find(newEntry.items, instance) then
			return
		end
		table.insert(newEntry.items, instance)
		for _, callback in newEntry.callbacks do
			task.spawn(callback, instance)
		end
	end
	local function remove(instance: Instance)
		local index = table.find(newEntry.items, instance)
		if index then
			table.remove(newEntry.items, index)
		end
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(remove)
	for _, instance in CollectionService:GetTagged(tag) do
		add(instance)
	end
	return newEntry
end

-- Alle Objekte mit diesem Tag (nicht veraendern, nur lesen).
function TagList.get(tag: string): { Instance }
	return getEntry(tag).items
end

-- `callback` fuer jedes vorhandene und jedes kuenftige Objekt mit diesem Tag aufrufen.
function TagList.watch(tag: string, callback: (Instance) -> ())
	local entry = getEntry(tag)
	table.insert(entry.callbacks, callback)
	for _, instance in entry.items do
		task.spawn(callback, instance)
	end
end

return TagList
