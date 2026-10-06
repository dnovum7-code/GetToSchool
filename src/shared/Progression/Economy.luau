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

-- Upgrades (Shop) ---------------------------------------------------------------------

export type UpgradeLevel = {
	price: number,
	description: string,
}

export type UpgradeDef = {
	id: string,
	name: string,
	levels: { UpgradeLevel },
}

function Economy.findUpgrade(defs: { UpgradeDef }, id: unknown): UpgradeDef?
	for _, def in defs do
		if def.id == id then
			return def
		end
	end
	return nil
end

function Economy.maxLevel(def: UpgradeDef): number
	return #def.levels
end

-- Stufe, mit der gespielt wird. `allMax`: alles auf hoechster Stufe (Test-Schalter in Studio)
function Economy.effectiveLevel(upgrades: { [string]: number }, def: UpgradeDef, allMax: boolean?): number
	if allMax then
		return #def.levels
	end
	return math.clamp(math.floor(upgrades[def.id] or 0), 0, #def.levels)
end

-- Hat der Spieler das Upgrade `id` mindestens auf Stufe `level`? (z. B. Abkuerzungs-Tuer)
-- Rueckgabe: erfuellt?, das Upgrade (fuer den Namen; nil = unbekannte Id)
function Economy.meetsRequirement(
	upgrades: { [string]: number },
	defs: { UpgradeDef },
	id: string,
	level: number,
	allMax: boolean?
): (boolean, UpgradeDef?)
	local def = Economy.findUpgrade(defs, id)
	if not def then
		return false, nil
	end
	return Economy.effectiveLevel(upgrades, def, allMax) >= math.max(1, math.floor(level)), def
end

-- Preis der naechsten Stufe, nil = schon hoechste Stufe
function Economy.nextPrice(def: UpgradeDef, currentLevel: number): number?
	local nextLevel = def.levels[currentLevel + 1]
	return if nextLevel then math.max(0, math.floor(nextLevel.price)) else nil
end

-- Naechste Stufe kaufen. Veraendert `data` nur bei Erfolg.
-- Rueckgabe: Erfolg, Grund ("Ok", "MaxLevel", "NotEnoughCoins"), neue Stufe, Preis
function Economy.purchase(
	data: { coins: number, upgrades: { [string]: number } },
	def: UpgradeDef
): (boolean, string, number, number)
	local level = math.clamp(math.floor(data.upgrades[def.id] or 0), 0, #def.levels)
	local price = Economy.nextPrice(def, level)
	if not price then
		return false, "MaxLevel", level, 0
	end
	if data.coins < price then
		return false, "NotEnoughCoins", level, price
	end
	data.coins -= price
	data.upgrades[def.id] = level + 1
	return true, "Ok", level + 1, price
end

local function formatValue(value: unknown): string
	if type(value) == "number" then
		if value == math.floor(value) then
			return tostring(math.floor(value))
		end
		local text = string.format("%.2f", value)
		text = string.gsub(text, "0+$", "")
		return text
	end
	return tostring(value)
end

-- Platzhalter wie "{Abilities.TurboCooldown2}" durch den Wert aus der Config ersetzen, damit
-- Beschreibungen nach dem Tunen stimmen.
function Economy.describe(text: string, config: { [string]: any }): string
	-- (als `any`, weil die Typpruefung Ersetz-Funktionen mit zwei Teilen nicht kennt)
	local replace: any = function(section: string, key: string): string
		local sectionTable = config[section]
		local value = if type(sectionTable) == "table" then sectionTable[key] else nil
		if value == nil then
			return "{" .. section .. "." .. key .. "}"
		end
		return formatValue(value)
	end
	local result = string.gsub(text, "{(%w+)%.(%w+)}", replace)
	return result
end

-- Etwas Einmaliges kaufen (Fahrzeug, Kosmetik ...): `owned` ist die Tabelle "Id -> true" im
-- Spielstand. Rueckgabe: Erfolg und Grund ("Owned", "NotEnough", "Bought").
function Economy.buyOnce(
	data: { coins: number },
	owned: { [string]: boolean },
	id: string,
	price: number
): (boolean, string)
	if owned[id] then
		return false, "Owned"
	end
	local cost = math.max(0, math.floor(price))
	if data.coins < cost then
		return false, "NotEnough"
	end
	data.coins -= cost
	owned[id] = true
	return true, "Bought"
end

return Economy
