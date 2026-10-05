--!strict
-- Zeitplan fuer Spawner im Dauerbetrieb (reine Logik, getestet in tests/ToolkitSpec.luau).
-- Ereignis Nummer k findet statt bei  k * Interval + Zufallsversatz  (Serverzeit).
-- Der Versatz kommt aus reproduzierbarem Zufall (`random(k)` liefert 0..1), deshalb
-- spawnen alle Clients zur selben Zeit dasselbe - ohne dass der Server etwas schickt.

local SpawnSchedule = {}

-- Zeitpunkt von Ereignis k. Versatz hoechstens 95 % des Intervalls (Reihenfolge bleibt).
function SpawnSchedule.timeOf(
	k: number,
	interval: number,
	intervalRandom: number,
	random: (k: number) -> number
): number
	local jitter = math.clamp(intervalRandom, 0, interval * 0.95)
	return k * interval + random(k) * jitter
end

-- Startwert fuer `lastK`, wenn ein Spawner (wieder) aktiv wird: nichts nachholen, aber das
-- Ereignis im aktuellen Intervall darf noch kommen.
function SpawnSchedule.startIndex(now: number, interval: number): number
	return math.floor(now / interval) - 1
end

-- Alle Ereignisse nach `lastK`, die bis `now` faellig sind. Rueckgabe: Liste der Nummern
-- und das neue `lastK`. `maxCount` begrenzt die Anzahl (z. B. nach einem Ruckler).
function SpawnSchedule.due(
	lastK: number,
	now: number,
	interval: number,
	intervalRandom: number,
	random: (k: number) -> number,
	maxCount: number?
): ({ number }, number)
	local result = {}
	local safeInterval = math.max(interval, 0.05)
	local maxK = math.floor(now / safeInterval)
	local k = lastK + 1
	-- Riesiger Rueckstand (z. B. erster Aufruf): nur die letzten Intervalle ansehen
	if maxK - k > 50 then
		k = maxK - 50
	end
	local limit = maxCount or math.huge
	while k <= maxK and #result < limit do
		if SpawnSchedule.timeOf(k, safeInterval, intervalRandom, random) <= now then
			table.insert(result, k)
			lastK = k
		else
			break
		end
		k += 1
	end
	return result, lastK
end

-- "Stein1, Stein2 ,Auto" -> { "Stein1", "Stein2", "Auto" }
function SpawnSchedule.splitNames(text: string): { string }
	local names = {}
	for part in string.gmatch(text, "[^,]+") do
		local trimmed = string.match(part, "^%s*(.-)%s*$")
		if trimmed and trimmed ~= "" then
			table.insert(names, trimmed)
		end
	end
	return names
end

-- Eintrag aus einer Liste mit Zufallszahl r (0..1)
function SpawnSchedule.pick<T>(list: { T }, r: number): T?
	if #list == 0 then
		return nil
	end
	return list[math.clamp(math.floor(r * #list) + 1, 1, #list)]
end

return SpawnSchedule
