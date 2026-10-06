--!strict
-- Kuh-Kombo - reine Logik ohne Roblox-Dienste (getestet in tests/ComboSpec.luau).
-- Mehrere Treffer (Launchables) kurz hintereinander erhoehen einen Multiplikator fuer die
-- Bonus-Muenzen. Werte in Config.Combo.

local Combo = {}

export type Config = {
	Window: number, -- so lange (s) nach einem Treffer zaehlt der naechste zur Kombo
	MaxMultiplier: number,
	StepBonus: number, -- Extra-Muenzen pro Kombo-Stufe (2x = 1 * StepBonus, 3x = 2 * ...)
}

export type State = { count: number, lastAt: number }

function Combo.new(): State
	return { count = 0, lastAt = -math.huge }
end

-- Treffer zum Zeitpunkt `now`: gibt die neue Kombo-Zahl zurueck (1 = kein Kombo)
function Combo.hit(state: State, now: number, cfg: Config): number
	if now - state.lastAt <= cfg.Window then
		state.count += 1
	else
		state.count = 1
	end
	state.lastAt = now
	return state.count
end

function Combo.multiplier(count: number, cfg: Config): number
	return math.clamp(count, 1, math.max(cfg.MaxMultiplier, 1))
end

-- Bonus-Muenzen mit Kombo: Grundbonus mal Multiplikator, plus Extra pro Stufe
function Combo.bonus(baseBonus: number, count: number, cfg: Config): number
	local multiplier = Combo.multiplier(count, cfg)
	return math.max(0, math.floor(baseBonus * multiplier + (multiplier - 1) * cfg.StepBonus))
end

-- Kombo vorbei? (fuer die Anzeige)
function Combo.isActive(state: State, now: number, cfg: Config): boolean
	return state.count >= 2 and now - state.lastAt <= cfg.Window
end

return Combo
