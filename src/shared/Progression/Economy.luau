--!strict
-- Rechenregeln fuer Muenzen, Belohnungen und Preise - reine Logik ohne Roblox-Dienste
-- (getestet in tests/EconomySpec.luau). Die Zahlen kommen aus der Config und werden
-- als Parameter uebergeben.

local Economy = {}

export type CoinConfig = {
	DefaultValue: number,
	MaxValue: number,
	MaxPickupDistance: number,
	LatencyAllowance: number,
	FinishBase: number,
	GradeBonus: { [number]: number },
}

local function isNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

-- Belohnung im Ziel: Grundbetrag plus Bonus je nach Note (6 = beste).
-- Rueckgabe: gesamt, Grundbetrag, Notenbonus
function Economy.finishReward(grade: number, cfg: CoinConfig): (number, number, number)
	local base = math.max(0, math.floor(cfg.FinishBase))
	local bonus = math.max(0, math.floor(cfg.GradeBonus[grade] or 0))
	return base + bonus, base, bonus
end

-- Wert einer Muenze aus ihrem Attribut "Value" (fehlt/falsch: Standardwert)
function Economy.coinValue(raw: unknown, cfg: CoinConfig): number
	if not isNumber(raw) then
		return math.floor(cfg.DefaultValue)
	end
	return math.clamp(math.floor(raw :: number), 0, math.floor(cfg.MaxValue))
end

-- Plausibilitaetspruefung beim Einsammeln: War der Wagen nah genug an der Muenze?
-- `distance`: Abstand Wagenmitte - Muenzmitte (so wie der Server ihn sieht), `speed`: Tempo
-- des Wagens (der Server sieht die Position etwas verspaetet), `coinRadius`: halbe Groesse.
function Economy.pickupInRange(distance: number, speed: number, coinRadius: number, cfg: CoinConfig): boolean
	local allowed = cfg.MaxPickupDistance
		+ math.max(coinRadius, 0)
		+ math.max(speed, 0) * cfg.LatencyAllowance
	return distance <= allowed
end

return Economy
