--!strict
-- Lokale Kopie eines Objekts (nur auf diesem Client): ohne Tags (sonst waere die Kopie
-- selbst wieder ein Baustein) und ohne Skripte. Fuer fliegende Kuehe, gespawnte Steine,
-- einstuerzende Bruecken, Props ...

local CollectionService = game:GetService("CollectionService")

local LocalClone = {}

function LocalClone.allParts(instance: Instance): { BasePart }
	local parts: { BasePart } = {}
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end
	for _, item in instance:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(parts, item)
		end
	end
	return parts
end

-- Kopie erzeugen (noch ohne Parent). nil, wenn es kein Part/Modell ist.
function LocalClone.copy(object: Instance): PVInstance?
	local instance: Instance = object
	if not (object:IsA("BasePart") or object:IsA("Model")) then
		return nil
	end
	local wasArchivable = instance.Archivable
	instance.Archivable = true -- nur Archivable-Objekte lassen sich kopieren
	local copy = instance:Clone() :: PVInstance
	instance.Archivable = wasArchivable
	for _, item in { copy :: Instance, table.unpack(copy:GetDescendants()) } do
		for _, tag in item:GetTags() do
			CollectionService:RemoveTag(item, tag)
		end
		if item:IsA("BaseScript") then
			item:Destroy()
		end
	end
	return copy
end

-- Ordner im Workspace fuer lokale Objekte (existiert nur auf diesem Client)
local folders: { [string]: Folder } = {}
function LocalClone.folder(name: string): Folder
	local folder = folders[name]
	if folder and folder.Parent then
		return folder
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = name
	newFolder.Parent = workspace
	folders[name] = newFolder
	return newFolder
end

return LocalClone
