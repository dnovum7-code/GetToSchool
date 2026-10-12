--!strict
-- Gespawnte Launchables: Kopien aus einem Spawner, deren Spawner oder Vorlage den Tag
-- "Launchable" hat. Es gibt sie nur auf diesem Client (Tag "LocalLaunchable"), deshalb
-- merken wir uns, woher sie kommen: Der Server prueft den Treffer ueber Spawner + Nummer
-- (siehe server/Launchables, shared/Toolkit/SpawnedHit).

local SpawnedLaunchables = {}

SpawnedLaunchables.TAG = "LocalLaunchable"

export type Info = {
	spawner: BasePart, -- der Spawner in der Welt (kennt auch der Server)
	index: number, -- Objekt-Nummer im Zeitplan
	template: string, -- Name der Vorlage
	key: string, -- eindeutig pro Objekt (Treffer nur einmal)
}

local byObject: { [Instance]: Info } = setmetatable({}, { __mode = "k" }) :: any

function SpawnedLaunchables.set(object: Instance, info: Info?)
	byObject[object] = info :: any -- nil = nicht (mehr) wegschleuderbar
end

function SpawnedLaunchables.get(object: Instance): Info?
	return byObject[object]
end

-- Kopie mit diesem Schluessel (z. B. Kuh, die ein anderer Spieler getroffen hat). Alle
-- Clients haben dieselben Kopien (gleicher Zeitplan und Zufall), also auch denselben Schluessel.
function SpawnedLaunchables.findByKey(key: string): Instance?
	for object, info in byObject do
		if info.key == key and object.Parent ~= nil then
			return object
		end
	end
	return nil
end

return SpawnedLaunchables
