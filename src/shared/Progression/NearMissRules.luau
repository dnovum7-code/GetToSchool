--!strict
-- Near-Miss ("KNAPP!"): reine Logik, getestet in tests/NearMissSpec.luau.
-- Client: Ein Objekt war knapp neben dem Wagen (im "nah"-Bereich) und ist wieder weg, ohne
-- dass es den Wagen beruehrt hat -> Bonus (bei genug Tempo, pro Objekt mit Abklingzeit).
-- Server: hoechstens alle MinInterval Sekunden und MaxPerRun Mal pro Lauf.

local NearMissRules = {}

export type Tracker = {
	inside: { [any]: boolean }, -- gerade knapp daneben
	touched: { [any]: boolean }, -- hat waehrenddessen beruehrt
	lastAward: { [any]: number },
}

function NearMissRules.newTracker(): Tracker
	return { inside = {}, touched = {}, lastAward = {} }
end

-- Ein Schritt: `near` = Objekte im knappen Bereich, `touching` = Objekte, die den Wagen
-- (fast) beruehren. Rueckgabe: Objekte, fuer die es jetzt einen Bonus gibt.
function NearMissRules.step(
	tracker: Tracker,
	near: { [any]: boolean },
	touching: { [any]: boolean },
	now: number,
	speed: number,
	minSpeed: number,
	cooldown: number
): { any }
	for key in touching do
		tracker.touched[key] = true
	end
	for key in near do
		tracker.inside[key] = true
	end
	local awarded = {}
	for key in tracker.inside do
		if not near[key] and not touching[key] then
			-- vorbei: Bonus nur ohne Beruehrung, mit Tempo und nicht zu oft
			local last = tracker.lastAward[key]
			if not tracker.touched[key] and speed >= minSpeed and (last == nil or now - last >= cooldown) then
				tracker.lastAward[key] = now
				table.insert(awarded, key)
			end
			tracker.inside[key] = nil
			tracker.touched[key] = nil
		end
	end
	return awarded
end

export type Budget = { runId: number, count: number, last: number }

-- Server: Bonus erlaubt? (zaehlt mit, wenn ja). Neuer Lauf = neues Budget.
function NearMissRules.allow(
	budget: Budget,
	runId: number,
	now: number,
	minInterval: number,
	maxPerRun: number
): boolean
	if budget.runId ~= runId then
		budget.runId = runId
		budget.count = 0
		budget.last = -math.huge
	end
	if now - budget.last < minInterval or budget.count >= maxPerRun then
		return false
	end
	budget.count += 1
	budget.last = now
	return true
end

return NearMissRules
