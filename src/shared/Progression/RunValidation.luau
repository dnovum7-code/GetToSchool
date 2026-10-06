--!strict
-- Plausibilitaetspruefung fuer die globale Bestenliste - reine Logik ohne Roblox-Dienste
-- (getestet in tests/LeaderboardSpec.luau).
--
-- Hindernisse laufen auf dem Client, der Wagen wird vom Client gesteuert. Bevor eine Zeit in
-- die globale Bestenliste kommt, prueft der Server deshalb:
--   1. Mindestzeit fuer die Strecke
--   2. alle Checkpoints durchfahren (alternative Wege: gleiche Order = einer davon reicht)
--   3. Checkpoints mit Order in der richtigen Reihenfolge
--   4. Mindestzeit zwischen zwei Checkpoints
--   5. kein Abschnitt schneller als moeglich (Luftlinie / Zeit, auch Start -> 1. Checkpoint
--      und letzter Checkpoint -> Ziel; faengt "Teleportieren" ab)
-- Unplausible Zeiten zaehlen nur persoenlich.

local RunValidation = {}

export type Point = { number } -- { x, y, z }

-- Ein Checkpoint der Strecke
export type TrackCheckpoint = {
	key: string, -- eindeutiger Name (z. B. GetFullName)
	order: number?, -- Attribut Order (gleiche Zahl = alternative Wege)
	optional: boolean?, -- Attribut Optional = true: muss nicht durchfahren werden
}

-- Erstes Durchfahren eines Checkpoints in diesem Lauf
export type Visit = {
	key: string,
	order: number?,
	at: number, -- Sekunden seit dem Start
	position: Point,
}

export type Run = {
	time: number, -- Fahrzeit
	startPosition: Point, -- wo der Wagen die Startzone verlassen hat
	finishPosition: Point, -- wo er ins Ziel gefahren ist
	visits: { Visit },
}

export type Rules = {
	minTime: number, -- Mindestzeit fuer die ganze Strecke (s)
	minGap: number, -- Mindestzeit zwischen zwei Checkpoints (s)
	maxSpeed: number, -- hoechstens so schnell (Studs/s, Luftlinie) in jedem Abschnitt
}

-- Gruende (fuer die Anzeige beim Spieler)
RunValidation.REASONS = {
	TooFast = "Zu schnell fuer diese Strecke",
	Missed = "Checkpoint ausgelassen",
	Order = "Checkpoints in falscher Reihenfolge",
	Gap = "Zu schnell zwischen zwei Checkpoints",
	Speed = "Unmoeglich schneller Abschnitt",
}

local function groupOf(key: string, order: number?): string
	return if order then `#{order}` else key
end

local function distance(a: Point, b: Point): number
	local dx, dy, dz = a[1] - b[1], a[2] - b[2], a[3] - b[3]
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Gibt zurueck: gueltig?, Grund (Schluessel aus REASONS) wenn nicht
function RunValidation.check(run: Run, checkpoints: { TrackCheckpoint }, rules: Rules): (boolean, string?)
	if run.time < rules.minTime then
		return false, "TooFast"
	end

	-- Pflicht-Gruppen der Strecke
	local required: { [string]: number? | false } = {} -- Gruppe -> Order (false = ohne Order)
	for _, checkpoint in checkpoints do
		if not checkpoint.optional then
			required[groupOf(checkpoint.key, checkpoint.order)] = checkpoint.order or false
		end
	end

	-- erstes Durchfahren pro Gruppe (Besuche sind nach Zeit sortiert)
	local visits = table.clone(run.visits)
	table.sort(visits, function(a, b)
		return a.at < b.at
	end)
	local firstVisit: { [string]: Visit } = {}
	local counted: { Visit } = {}
	for _, visit in visits do
		local group = groupOf(visit.key, visit.order)
		if required[group] ~= nil and not firstVisit[group] then
			firstVisit[group] = visit
			table.insert(counted, visit)
		end
	end
	for group in required do
		if not firstVisit[group] then
			return false, "Missed"
		end
	end

	-- Reihenfolge: Checkpoints mit Order muessen in aufsteigender Zahl durchfahren werden
	local lastOrder = -math.huge
	for _, visit in counted do
		local order = visit.order
		if order then
			if order < lastOrder then
				return false, "Order"
			end
			lastOrder = order
		end
	end

	-- Mindestzeit zwischen zwei Checkpoints
	for i = 2, #counted do
		if counted[i].at - counted[i - 1].at < rules.minGap then
			return false, "Gap"
		end
	end

	-- Tempo pro Abschnitt (Luftlinie ist nie laenger als der echte Weg)
	local previousPoint, previousTime = run.startPosition, 0
	local function segmentOk(point: Point, at: number): boolean
		local dt = math.max(at - previousTime, 1e-3)
		local ok = distance(previousPoint, point) / dt <= rules.maxSpeed
		previousPoint, previousTime = point, at
		return ok
	end
	for _, visit in counted do
		if not segmentOk(visit.position, visit.at) then
			return false, "Speed"
		end
	end
	if not segmentOk(run.finishPosition, run.time) then
		return false, "Speed"
	end
	return true, nil
end

return RunValidation
