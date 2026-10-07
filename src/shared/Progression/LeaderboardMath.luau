--!strict
-- Rechnen fuer die Bestenlisten - reine Logik ohne Roblox-Dienste
-- (getestet in tests/LeaderboardSpec.luau).
--
-- Zwei Arten von Listen:
--   "Time"     Fahrzeit einer Strecke, kleiner ist besser (gespeichert in Millisekunden)
--   "Distance" weitester Wurf, groesser ist besser (gespeichert in Zehntel-Metern)
--   "Meters"   insgesamt gefahrene Meter, groesser ist besser (gespeichert in ganzen Metern)
-- OrderedDataStores speichern nur ganze Zahlen, daher encode/decode.

local LeaderboardMath = {}

export type Kind = "Time" | "Distance" | "Meters"

export type Entry = {
	userId: number,
	value: number, -- gespeicherte ganze Zahl (encode)
	rank: number?,
	name: string?,
}

function LeaderboardMath.encode(kind: Kind, value: number): number
	if kind == "Time" then
		return math.floor(value * 1000 + 0.5)
	elseif kind == "Meters" then
		return math.floor(value)
	end
	return math.floor(value * 10 + 0.5)
end

function LeaderboardMath.decode(kind: Kind, stored: number): number
	if kind == "Time" then
		return stored / 1000
	elseif kind == "Meters" then
		return stored
	end
	return stored / 10
end

function LeaderboardMath.ascending(kind: Kind): boolean
	return kind == "Time"
end

-- Ist der (gespeicherte) Wert a besser als b? b = nil: immer besser.
function LeaderboardMath.isBetter(kind: Kind, a: number, b: number?): boolean
	if b == nil then
		return true
	end
	return if kind == "Time" then a < b else a > b
end

-- Liste sortieren und Plaetze vergeben (gleicher Wert = gleicher Platz).
-- Bei gleichem Wert entscheidet die kleinere UserId, damit die Reihenfolge fest ist.
function LeaderboardMath.rank(kind: Kind, entries: { Entry }): { Entry }
	local list = table.clone(entries)
	table.sort(list, function(a, b)
		if a.value ~= b.value then
			return LeaderboardMath.isBetter(kind, a.value, b.value)
		end
		return a.userId < b.userId
	end)
	local result = {}
	for index, entry in list do
		local previous = result[index - 1]
		local rank = if previous and previous.value == entry.value then previous.rank else index
		table.insert(result, { userId = entry.userId, value = entry.value, rank = rank, name = entry.name })
	end
	return result
end

-- Platz eines Spielers in einer sortierten Liste (nil = nicht drin)
function LeaderboardMath.find(entries: { Entry }, userId: number): Entry?
	for _, entry in entries do
		if entry.userId == userId then
			return entry
		end
	end
	return nil
end

-- Die ersten `count` Eintraege
function LeaderboardMath.top(entries: { Entry }, count: number): { Entry }
	local result = {}
	for i = 1, math.min(count, #entries) do
		table.insert(result, entries[i])
	end
	return result
end

return LeaderboardMath
