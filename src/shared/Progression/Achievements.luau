--!strict
-- Erfolge - reine Logik ohne Roblox-Dienste (getestet in tests/AchievementsSpec.luau).
-- Die Liste steht in Config.Achievements.List.
--
-- Arten (Feld `type`):
--   Ereignis-Erfolge (gelten im Moment des Ereignisses):
--     "SkyLaunch"   etwas ins All schleudern
--     "Flight"      etwas mindestens `meters` weit schleudern
--     "AllCoins"    alle Muenzen der Strecke `track` eingesammelt und im Ziel
--     "Flawless"    Lauf ohne Lebensverlust beendet
--     "BeatGhost"   eigene Bestzeit geschlagen (es gab schon eine)
--     "HomeworkDay" alle Hausaufgaben eines Tages erledigt
--     "Combo"       Kuh-Kombo mit mindestens `goal` Treffern in Folge
--     "Trick"       Lufttrick mit mindestens `goal` halben Drehungen sauber gelandet
--   Zaehler/Zustand (werden immer geprueft, mit Fortschritt im Menue):
--     "Finishes"    `goal` Laeufe beendet
--     "Launches"    `goal` Objekte weggeschleudert
--     "DriftTotal"  insgesamt `goal` Sekunden gedriftet
--     "AllGrades"   Note `grade` (Standard 6) auf allen Strecken
--     "AllVehicles" alle Fahrzeuge besitzen

local Achievements = {}

export type Def = {
	id: string,
	name: string,
	description: string,
	type: string,
	goal: number?,
	meters: number?,
	track: string?,
	grade: number?,
	badge: number?, -- Roblox-Badge-Id (0 / nil = keins)
}

export type Event = {
	type: string, -- "Launch", "Finish", "HomeworkDone", "Trick"
	amount: number?, -- Trick: halbe Drehungen
	combo: number?, -- Launch: Treffer in Folge
	sky: boolean?,
	meters: number?,
	trackId: string?,
	livesLost: number?,
	allCoins: boolean?,
	isNewBest: boolean?,
	hadPrevious: boolean?,
}

export type Facts = {
	event: Event?,
	finishedRuns: number,
	objectsLaunched: number,
	driftSeconds: number,
	bestGrades: { [string]: number },
	trackIds: { string }, -- alle Strecken, die zaehlen
	vehiclesOwned: number,
	vehiclesTotal: number,
}

-- Fortschritt fuer Zaehler-Erfolge: aktueller Wert und Ziel (Ereignis-Erfolge: 0 / 1)
function Achievements.progress(def: Def, facts: Facts): (number, number)
	local kind = def.type
	if kind == "Finishes" then
		return facts.finishedRuns, def.goal or 1
	elseif kind == "Launches" then
		return facts.objectsLaunched, def.goal or 1
	elseif kind == "DriftTotal" then
		return math.floor(facts.driftSeconds), def.goal or 1
	elseif kind == "AllGrades" then
		local grade = def.grade or 6
		local count = 0
		for _, id in facts.trackIds do
			if (facts.bestGrades[id] or 0) >= grade then
				count += 1
			end
		end
		return count, math.max(#facts.trackIds, 1)
	elseif kind == "AllVehicles" then
		return facts.vehiclesOwned, math.max(facts.vehiclesTotal, 1)
	end
	return 0, 1
end

-- Ist der Erfolg jetzt erreicht?
function Achievements.isMet(def: Def, facts: Facts): boolean
	local kind = def.type
	local event = facts.event
	if kind == "SkyLaunch" then
		return event ~= nil and event.type == "Launch" and event.sky == true
	elseif kind == "Flight" then
		return event ~= nil and event.type == "Launch" and (event.meters or 0) >= (def.meters or 0)
	elseif kind == "AllCoins" then
		return event ~= nil
			and event.type == "Finish"
			and event.allCoins == true
			and (def.track == nil or def.track == event.trackId)
	elseif kind == "Flawless" then
		return event ~= nil and event.type == "Finish" and (event.livesLost or 0) == 0
	elseif kind == "BeatGhost" then
		return event ~= nil
			and event.type == "Finish"
			and event.isNewBest == true
			and event.hadPrevious == true
	elseif kind == "HomeworkDay" then
		return event ~= nil and event.type == "HomeworkDone"
	elseif kind == "Combo" then
		return event ~= nil and event.type == "Launch" and (event.combo or 0) >= (def.goal or 2)
	elseif kind == "Trick" then
		return event ~= nil and event.type == "Trick" and (event.amount or 0) >= (def.goal or 1)
	elseif kind == "AllGrades" and #facts.trackIds == 0 then
		return false
	end
	local current, goal = Achievements.progress(def, facts)
	if
		kind == "Finishes"
		or kind == "Launches"
		or kind == "DriftTotal"
		or kind == "AllGrades"
		or kind == "AllVehicles"
	then
		return current >= goal
	end
	return false
end

-- Alle pruefen: neu erreichte werden in `unlocked` eingetragen und zurueckgegeben
function Achievements.check(defs: { Def }, unlocked: { [string]: boolean }, facts: Facts): { Def }
	local newly = {}
	for _, def in defs do
		if not unlocked[def.id] and Achievements.isMet(def, facts) then
			unlocked[def.id] = true
			table.insert(newly, def)
		end
	end
	return newly
end

-- Text mit Platzhaltern {goal} {meters} {track} {grade}
function Achievements.describe(def: Def, trackName: ((string) -> string)?): string
	local text = def.description
	local track = def.track
	text = text:gsub("{goal}", tostring(def.goal or 1))
	text = text:gsub("{meters}", tostring(def.meters or 0))
	text = text:gsub("{grade}", tostring(def.grade or 6))
	text = text:gsub(
		"{track}",
		if track then (if trackName then trackName(track) else track) else "einer Strecke"
	)
	return text
end

return Achievements
