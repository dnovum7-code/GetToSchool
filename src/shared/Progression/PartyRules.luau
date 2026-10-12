--!strict
-- Party-Modi: Rangliste, Belohnung, Rundenende - reine Logik (getestet in
-- tests/PartySpec.luau). Den Ablauf (Anmeldung, Countdown, Arena) macht server/Party.

local PartyRules = {}

export type Entry = {
	id: number, -- UserId
	name: string,
	score: number, -- Kuh-Bowling: Summe der Flugweiten (m)
	lives: number, -- Letzter Wagen: verbleibende Leben
	alive: boolean, -- Letzter Wagen: noch dabei
	outAt: number, -- Letzter Wagen: Sekunden seit Rundenstart beim Ausscheiden (0 = noch dabei)
}

export type Ranked = { entry: Entry, place: number }

-- Platzierung mit Gleichstand: gleich gute teilen sich den Platz (1, 1, 3 ...)
local function placeAll(
	entries: { Entry },
	better: (Entry, Entry) -> boolean,
	same: (Entry, Entry) -> boolean
): { Ranked }
	local sorted = table.clone(entries)
	table.sort(sorted, function(a, b)
		if better(a, b) then
			return true
		elseif better(b, a) then
			return false
		end
		return a.name < b.name -- feste Reihenfolge bei Gleichstand
	end)
	local result: { Ranked } = {}
	for index, entry in sorted do
		local previous = result[index - 1]
		local place = if previous and same(previous.entry, entry) then previous.place else index
		table.insert(result, { entry = entry, place = place })
	end
	return result
end

-- Kuh-Bowling: mehr Meter = besser
function PartyRules.rankCowBowling(entries: { Entry }): { Ranked }
	return placeAll(entries, function(a, b)
		return a.score > b.score
	end, function(a, b)
		return a.score == b.score
	end)
end

-- Letzter Wagen: Wer noch faehrt, vor allen Ausgeschiedenen (mehr Leben = besser, gleich viele
-- Leben = Gleichstand). Ausgeschiedene: wer spaeter rausflog, ist besser.
function PartyRules.rankLastCart(entries: { Entry }): { Ranked }
	return placeAll(entries, function(a, b)
		if a.alive ~= b.alive then
			return a.alive
		end
		if a.alive then
			return a.lives > b.lives
		end
		return a.outAt > b.outAt
	end, function(a, b)
		if a.alive ~= b.alive then
			return false
		end
		return if a.alive then a.lives == b.lives else a.outAt == b.outAt
	end)
end

-- Muenzen fuer einen Platz: rewards[place], sonst die Teilnahme-Belohnung
function PartyRules.reward(place: number, rewards: { number }, participation: number): number
	return rewards[place] or participation
end

-- Genug Spieler fuer eine Runde?
function PartyRules.canStart(queued: number, minPlayers: number): boolean
	return queued >= math.max(minPlayers, 1)
end

-- Letzter Wagen vorbei? Nur noch einer (oder keiner) uebrig oder Zeit abgelaufen.
function PartyRules.lastCartOver(alive: number, total: number, elapsed: number, maxDuration: number): boolean
	if elapsed >= maxDuration then
		return true
	end
	if total >= 2 then
		return alive <= 1
	end
	return alive <= 0
end

-- Eskalation (Letzter Wagen): 0 vor `after` Sekunden, dann alle `interval` Sekunden +1
function PartyRules.dangerLevel(elapsed: number, after: number, interval: number): number
	if elapsed < after then
		return 0
	end
	return 1 + math.floor((elapsed - after) / math.max(interval, 1))
end

return PartyRules
