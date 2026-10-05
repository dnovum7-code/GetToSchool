--!strict
-- Regeln fuer Leben und Schild (Fahrradhelm) in einem Lauf - reine Logik ohne Roblox-Dienste
-- (getestet in tests/RunRulesSpec.luau).
--
-- Jeder Treffer (Launchable) und jeder Crash kostet ein Leben. Hat der Spieler noch eine
-- Helm-Ladung, faengt die den Lebensverlust ab. Der Helm laedt sich am naechsten Checkpoint
-- wieder auf. Bei 0 Leben ist Game Over.

local RunRules = {}

export type LifeState = {
	lives: number,
	maxLives: number,
	shield: number, -- aktuelle Helm-Ladungen
	maxShield: number,
}

export type HitOutcome = "Shielded" | "LifeLost" | "GameOver"

-- Neuer Lauf: volle Leben, voller Helm
function RunRules.newRun(lives: number, maxShield: number): LifeState
	local maxLives = math.max(1, math.floor(lives))
	local shield = math.max(0, math.floor(maxShield))
	return { lives = maxLives, maxLives = maxLives, shield = shield, maxShield = shield }
end

-- Treffer oder Crash. Veraendert `state` und sagt, was passiert ist.
function RunRules.applyHit(state: LifeState): HitOutcome
	if state.shield > 0 then
		state.shield -= 1
		return "Shielded"
	end
	state.lives = math.max(0, state.lives - 1)
	if state.lives <= 0 then
		return "GameOver"
	end
	return "LifeLost"
end

-- Checkpoint erreicht: Helm wieder voll. Gibt zurueck, ob sich etwas geaendert hat.
function RunRules.rechargeShield(state: LifeState): boolean
	if state.shield < state.maxShield then
		state.shield = state.maxShield
		return true
	end
	return false
end

-- Wert fuer eine Upgrade-Stufe aus der Config lesen: z. B. prefix "HelmetCharges" und
-- Stufe 2 -> section.HelmetCharges2. Stufe 0 oder fehlender Eintrag -> `default`.
function RunRules.levelValue(
	section: { [string]: any },
	prefix: string,
	level: number,
	default: number
): number
	if level <= 0 then
		return default
	end
	-- hoechste vorhandene Stufe bis `level` nehmen (falls eine Stufe in der Config fehlt)
	for current = math.floor(level), 1, -1 do
		local value = section[prefix .. tostring(current)]
		if type(value) == "number" then
			return value
		end
	end
	return default
end

return RunRules
