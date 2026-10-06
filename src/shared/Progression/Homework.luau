--!strict
-- Hausaufgaben (taegliche Aufgaben) - reine Logik ohne Roblox-Dienste
-- (getestet in tests/HomeworkSpec.luau). Aufgaben und Belohnungen stehen in Config.Homework.
--
-- Jeden Tag (Wechsel um Config.Homework.ResetHourUtc, UTC) bekommt jeder Spieler
-- TasksPerDay zufaellige Aufgaben aus dem Pool. Welche, haengt nur vom Tag und vom Spieler ab
-- (gleicher Tag = gleiche Aufgaben, auch nach einem Serverwechsel).
--
-- Aufgaben-Arten (Feld `type` im Pool):
--   "Launch"      Objekte wegschleudern (optional `name` = DisplayName, z. B. "Kuh")
--   "Flight"      ein Objekt mindestens `meters` weit schleudern
--   "Coins"       Muenzen einsammeln
--   "Drift"       insgesamt `goal` Sekunden driften
--   "Finish"      Laeufe beenden (optional `track`)
--   "FinishUnder" Strecke `track` unter `time` Sekunden beenden
--   "Flawless"    einen Lauf ohne Lebensverlust beenden
--   "Grade"       einen Lauf mit Note `grade` oder besser beenden

local Homework = {}

export type Def = {
	id: string,
	type: string,
	text: string, -- Platzhalter: {goal}, {time}, {track}, {meters}, {grade}
	goal: number?, -- Standard 1
	reward: number, -- Muenzen
	weight: number?, -- Wahrscheinlichkeit beim Auswuerfeln (Standard 1)
	name: string?,
	track: string?,
	time: number?,
	meters: number?,
	grade: number?,
}

export type Task = { id: string, progress: number, done: boolean }

export type State = { day: number, tasks: { Task }, bonusDone: boolean }

export type Event = {
	type: string, -- "Launch", "Coins", "Drift", "Finish"
	amount: number?, -- Coins/Drift: wie viel
	name: string?, -- Launch: DisplayName
	meters: number?, -- Launch: Flugweite
	trackId: string?, -- Finish
	time: number?, -- Finish: Fahrzeit
	grade: number?, -- Finish: Note
	livesLost: number?, -- Finish: verlorene Leben
}

local DAY = 86400

-- Tag (Tage seit 1970) zum Zeitpunkt `unixTime`, Wechsel um `resetHour` Uhr UTC
function Homework.dayIndex(unixTime: number, resetHour: number): number
	return math.floor((unixTime - resetHour * 3600) / DAY)
end

-- Wann der naechste Tag beginnt (Unix-Zeit)
function Homework.nextReset(unixTime: number, resetHour: number): number
	return (Homework.dayIndex(unixTime, resetHour) + 1) * DAY + resetHour * 3600
end

function Homework.goalOf(def: Def): number
	return math.max(1, def.goal or 1)
end

function Homework.find(pool: { Def }, id: string): Def?
	for _, def in pool do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- Einfacher, fester Zufall (gleiche Zahlen fuer gleichen Tag und Spieler)
local function makeRandom(seed: number): () -> number
	local state = math.floor(math.abs(seed)) % 2147483647
	if state == 0 then
		state = 1234567
	end
	return function(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end

-- Aufgaben fuer `day` auswuerfeln. `available(def)`: darf diese Aufgabe vorkommen (z. B. ist
-- die Strecke frei)?
function Homework.pick(
	pool: { Def },
	count: number,
	day: number,
	seed: number,
	available: ((Def) -> boolean)?
): { Task }
	local random = makeRandom(day * 7919 + seed * 104729 + 17)
	for _ = 1, 3 do
		random() -- erste Zahlen sind sich bei aehnlichen Startwerten noch aehnlich
	end
	local candidates: { Def } = {}
	for _, def in pool do
		if (def.weight or 1) > 0 and (not available or available(def)) then
			table.insert(candidates, def)
		end
	end
	local result: { Task } = {}
	while #result < count and #candidates > 0 do
		local total = 0
		for _, def in candidates do
			total += def.weight or 1
		end
		local roll = random() * total
		local chosen = #candidates
		for index, def in candidates do
			roll -= def.weight or 1
			if roll <= 0 then
				chosen = index
				break
			end
		end
		local def = table.remove(candidates, chosen) :: Def
		table.insert(result, { id = def.id, progress = 0, done = false })
	end
	return result
end

-- Neuer Tag? Dann neue Aufgaben. Gibt zurueck, ob sich etwas geaendert hat.
function Homework.ensureDay(
	state: State,
	day: number,
	pool: { Def },
	count: number,
	seed: number,
	available: ((Def) -> boolean)?
): boolean
	if state.day == day then
		return false
	end
	state.day = day
	state.tasks = Homework.pick(pool, count, day, seed, available)
	state.bonusDone = false
	return true
end

-- Wie viel bringt dieses Ereignis fuer diese Aufgabe? (0 = nichts)
local function gain(def: Def, event: Event): number
	local kind = def.type
	if kind == "Launch" then
		if event.type == "Launch" and (def.name == nil or def.name == event.name) then
			return 1
		end
	elseif kind == "Flight" then
		if event.type == "Launch" and (event.meters or 0) >= (def.meters or 0) then
			return math.huge
		end
	elseif kind == "Coins" or kind == "Drift" then
		if event.type == kind then
			return math.max(0, event.amount or 0)
		end
	elseif event.type == "Finish" then
		if def.track and def.track ~= event.trackId then
			return 0
		end
		if kind == "Finish" then
			return 1
		elseif kind == "FinishUnder" then
			return if event.time and event.time < (def.time or 0) then math.huge else 0
		elseif kind == "Flawless" then
			return if (event.livesLost or 0) == 0 then 1 else 0
		elseif kind == "Grade" then
			return if (event.grade or 0) >= (def.grade or 6) then 1 else 0
		end
	end
	return 0
end

-- Ereignis verbuchen. Gibt die Aufgaben zurueck, die dadurch gerade fertig geworden sind.
function Homework.report(state: State, pool: { Def }, event: Event): { Def }
	local finished: { Def } = {}
	for _, task in state.tasks do
		local def = Homework.find(pool, task.id)
		if not def or task.done then
			continue
		end
		local amount = gain(def, event)
		if amount > 0 then
			local goal = Homework.goalOf(def)
			task.progress = math.min(goal, task.progress + amount)
			if task.progress >= goal then
				task.done = true
				table.insert(finished, def)
			end
		end
	end
	return finished
end

-- Alle Aufgaben erledigt und Bonus noch nicht vergeben? Dann true (und als vergeben merken).
function Homework.takeBonus(state: State): boolean
	if state.bonusDone or #state.tasks == 0 then
		return false
	end
	for _, task in state.tasks do
		if not task.done then
			return false
		end
	end
	state.bonusDone = true
	return true
end

local function formatTime(seconds: number): string
	local whole = math.floor(seconds)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

-- Text zum Anzeigen. `trackName(id)` liefert den Namen einer Strecke.
function Homework.describe(def: Def, trackName: ((string) -> string)?): string
	local track = def.track
	local text = def.text
	text = text:gsub("{goal}", tostring(Homework.goalOf(def)))
	text = text:gsub("{time}", formatTime(def.time or 0))
	text = text:gsub("{meters}", tostring(def.meters or 0))
	text = text:gsub("{grade}", tostring(def.grade or 0))
	text = text:gsub(
		"{track}",
		if track then (if trackName then trackName(track) else track) else "einer Strecke"
	)
	return text
end

return Homework
