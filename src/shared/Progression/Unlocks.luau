--!strict
-- Freischalt-Bedingungen fuer Strecken - reine Logik ohne Roblox-Dienste
-- (getestet in tests/UnlocksSpec.luau). Die Strecken stehen in Config.Tracks.
--
-- Eine Strecke ist frei, wenn
--   * sie keine Bedingung hat (oder gar nicht in Config.Tracks steht), oder
--   * sie schon einmal freigeschaltet wurde (steht dann im Spielstand), oder
--   * die Noten-Bedingung erfuellt ist: Note `grade` oder besser auf Strecke `track`.
-- Mit `price` kann man sie stattdessen fuer Muenzen freischalten.

local Unlocks = {}

export type UnlockRule = {
	track: string?, -- Strecke, auf der die Note erreicht werden muss ...
	grade: number?, -- ... mindestens diese Note (6 = beste)
	price: number?, -- oder fuer so viele Muenzen
}

export type TrackDef = {
	id: string,
	name: string,
	minTime: number?, -- fuer die Bestenliste (siehe RunValidation), hier nicht benutzt
	unlock: UnlockRule?,
}

export type UnlockData = {
	coins: number,
	unlockedTracks: { [string]: boolean },
	bestGrades: { [string]: number },
}

function Unlocks.find(defs: { TrackDef }, id: unknown): TrackDef?
	for _, def in defs do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- Noten-Bedingung erfuellt?
function Unlocks.gradeMet(rule: UnlockRule, data: UnlockData): boolean
	local track, grade = rule.track, rule.grade
	if not track or not grade then
		return false
	end
	return (data.bestGrades[track] or 0) >= grade
end

-- Darf der Spieler die Strecke fahren? `def` nil = Strecke nicht in der Config = frei.
function Unlocks.isUnlocked(def: TrackDef?, data: UnlockData): boolean
	if not def or not def.unlock then
		return true
	end
	if data.unlockedTracks[def.id] then
		return true
	end
	return Unlocks.gradeMet(def.unlock, data)
end

-- Strecken, deren Noten-Bedingung jetzt erfuellt ist, die aber noch nicht im Spielstand
-- als freigeschaltet stehen (der Aufrufer traegt sie ein und meldet es dem Spieler).
function Unlocks.newlyUnlocked(defs: { TrackDef }, data: UnlockData): { string }
	local result = {}
	for _, def in defs do
		local rule = def.unlock
		if rule and not data.unlockedTracks[def.id] and Unlocks.gradeMet(rule, data) then
			table.insert(result, def.id)
		end
	end
	return result
end

-- Fuer Muenzen freischalten. Veraendert `data` nur bei Erfolg.
-- Rueckgabe: Erfolg, Grund ("Ok", "AlreadyUnlocked", "NotForSale", "NotEnoughCoins"), Preis
function Unlocks.purchase(def: TrackDef, data: UnlockData): (boolean, string, number)
	if Unlocks.isUnlocked(def, data) then
		return false, "AlreadyUnlocked", 0
	end
	local rule = def.unlock
	local price = if rule and rule.price then math.max(0, math.floor(rule.price)) else nil
	if not price then
		return false, "NotForSale", 0
	end
	if data.coins < price then
		return false, "NotEnoughCoins", price
	end
	data.coins -= price
	data.unlockedTracks[def.id] = true
	return true, "Ok", price
end

-- Bedingung als Text fuer das Menue, z. B. "Note 4 auf Der Schulweg oder 250 Muenzen".
-- `nameOf(id)` liefert den Anzeigenamen einer Strecke.
function Unlocks.describe(def: TrackDef, nameOf: (string) -> string): string?
	local rule = def.unlock
	if not rule then
		return nil
	end
	local parts = {}
	if rule.track and rule.grade then
		table.insert(parts, `Note {rule.grade} auf {nameOf(rule.track)}`)
	end
	if rule.price then
		table.insert(parts, `{math.floor(rule.price)} Muenzen`)
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, " oder ")
end

return Unlocks
