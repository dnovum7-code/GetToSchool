--!strict
-- Bestzeiten pro Spieler und Track. Gespeichert werden sie im Spielstand (siehe Profiles):
-- pro Track die Bestzeit und die Zwischenzeiten an jedem Checkpoint (fuer die Live-Anzeige
-- "schneller/langsamer als Bestzeit").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SaveData =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"):WaitForChild("SaveData"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))

local BestTimes = {}

export type Record = SaveData.BestTime

function BestTimes.get(player: Player, trackId: string): Record?
	return Profiles.get(player).bestTimes[trackId]
end

-- Neue Zeit melden. Gibt zurueck, ob es eine neue Bestzeit ist, und die alte Bestzeit.
function BestTimes.submit(
	player: Player,
	trackId: string,
	time: number,
	splits: { [string]: number }
): (boolean, number?)
	local data = Profiles.get(player)
	local previous = data.bestTimes[trackId]
	if previous and previous.time <= time then
		return false, previous.time
	end
	data.bestTimes[trackId] = { time = time, splits = table.clone(splits) }
	Profiles.markChanged(player)
	return true, if previous then previous.time else nil
end

return BestTimes
