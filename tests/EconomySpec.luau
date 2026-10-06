--!strict
local TestLib = require("./TestLib")
local Economy = require("../src/shared/Progression/Economy")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local coinConfig = {
	DefaultValue = 1,
	MaxValue = 100,
	MaxPickupDistance = 12,
	LatencyAllowance = 0.3,
	FinishBase = 10,
	GradeBonus = { [6] = 20, [5] = 12, [4] = 7, [3] = 4, [2] = 2, [1] = 0 },
}

describe("Economy: Muenzen", function()
	it("Zielbelohnung = Grundbetrag + Notenbonus", function()
		local total, base, bonus = Economy.finishReward(6, coinConfig)
		expect(total).toBe(30)
		expect(base).toBe(10)
		expect(bonus).toBe(20)
		expect((Economy.finishReward(1, coinConfig))).toBe(10)
	end)

	it("unbekannte Note gibt nur den Grundbetrag", function()
		expect((Economy.finishReward(9, coinConfig))).toBe(10)
	end)

	it("Muenzwert: Standard, Attribut, Grenzen", function()
		expect(Economy.coinValue(nil, coinConfig)).toBe(1)
		expect(Economy.coinValue("5", coinConfig)).toBe(1)
		expect(Economy.coinValue(5, coinConfig)).toBe(5)
		expect(Economy.coinValue(2.9, coinConfig)).toBe(2)
		expect(Economy.coinValue(-3, coinConfig)).toBe(0)
		expect(Economy.coinValue(1e9, coinConfig)).toBe(100)
		expect(Economy.coinValue(0 / 0, coinConfig)).toBe(1)
	end)

	it("Einsammeln: nah genug ok, zu weit weg abgelehnt", function()
		expect(Economy.pickupInRange(5, 0, 1, coinConfig)).toBe(true)
		expect(Economy.pickupInRange(14, 0, 1, coinConfig)).toBe(false)
	end)

	it("Einsammeln: hohes Tempo erlaubt mehr Abstand (Netz-Verzoegerung)", function()
		-- 12 + 1 + 100 * 0.3 = 43
		expect(Economy.pickupInRange(40, 100, 1, coinConfig)).toBe(true)
		expect(Economy.pickupInRange(50, 100, 1, coinConfig)).toBe(false)
	end)
end)

local turbo = {
	id = "Turbo",
	name = "Turbo-Pausenbrot",
	levels = {
		{ price = 80, description = "Abklingzeit {Abilities.TurboCooldown1} s" },
		{ price = 200, description = "Abklingzeit {Abilities.TurboCooldown2} s" },
	},
}

describe("Economy: Upgrades", function()
	it("findet Upgrades ueber die Id", function()
		expect(Economy.findUpgrade({ turbo }, "Turbo")).toBe(turbo)
		expect(Economy.findUpgrade({ turbo }, "Gibtsnicht")).toBeNil()
		expect(Economy.findUpgrade({ turbo }, 5)).toBeNil()
	end)

	it("Preis steigt pro Stufe, nach der letzten Stufe gibt es keinen Preis", function()
		expect(Economy.nextPrice(turbo, 0)).toBe(80)
		expect(Economy.nextPrice(turbo, 1)).toBe(200)
		expect(Economy.nextPrice(turbo, 2)).toBeNil()
	end)

	it("Kauf zieht Muenzen ab und erhoeht die Stufe", function()
		local data = { coins = 300, upgrades = {} }
		local ok, reason, level, price = Economy.purchase(data, turbo)
		expect(ok).toBe(true)
		expect(reason).toBe("Ok")
		expect(level).toBe(1)
		expect(price).toBe(80)
		expect(data.coins).toBe(220)
		expect(data.upgrades.Turbo).toBe(1)
	end)

	it("zu wenig Muenzen: nichts aendert sich", function()
		local data = { coins = 100, upgrades = { Turbo = 1 } }
		local ok, reason, level = Economy.purchase(data, turbo)
		expect(ok).toBe(false)
		expect(reason).toBe("NotEnoughCoins")
		expect(level).toBe(1)
		expect(data.coins).toBe(100)
		expect(data.upgrades.Turbo).toBe(1)
	end)

	it("hoechste Stufe kann nicht weiter gekauft werden", function()
		local data = { coins = 9999, upgrades = { Turbo = 2 } }
		local ok, reason = Economy.purchase(data, turbo)
		expect(ok).toBe(false)
		expect(reason).toBe("MaxLevel")
		expect(data.coins).toBe(9999)
	end)

	it("Stufe zum Spielen: begrenzt, Test-Schalter = alles maximal", function()
		expect(Economy.effectiveLevel({}, turbo)).toBe(0)
		expect(Economy.effectiveLevel({ Turbo = 7 }, turbo)).toBe(2)
		expect(Economy.effectiveLevel({}, turbo, true)).toBe(2)
	end)

	it("Abkuerzungs-Tuer: Upgrade-Stufe erfuellt?", function()
		local ok, def = Economy.meetsRequirement({ Turbo = 1 }, { turbo }, "Turbo", 1)
		expect(ok).toBe(true)
		expect(def and def.name).toBe("Turbo-Pausenbrot")
		expect((Economy.meetsRequirement({ Turbo = 1 }, { turbo }, "Turbo", 2))).toBe(false)
		expect((Economy.meetsRequirement({}, { turbo }, "Turbo", 1))).toBe(false)
		expect((Economy.meetsRequirement({}, { turbo }, "Turbo", 2, true))).toBe(true)
		local unknown, noDef = Economy.meetsRequirement({}, { turbo }, "Gibtsnicht", 1)
		expect(unknown).toBe(false)
		expect(noDef).toBeNil()
		-- Stufe 0 oder weniger zaehlt als Stufe 1
		expect((Economy.meetsRequirement({}, { turbo }, "Turbo", 0))).toBe(false)
	end)

	it("Beschreibung setzt Config-Werte ein", function()
		local config = { Abilities = { TurboCooldown1 = 12, TurboCooldown2 = 7.5 } }
		expect(Economy.describe(turbo.levels[1].description, config)).toBe("Abklingzeit 12 s")
		expect(Economy.describe(turbo.levels[2].description, config)).toBe("Abklingzeit 7.5 s")
		expect(Economy.describe("{Abilities.Fehlt} x", config)).toBe("{Abilities.Fehlt} x")
	end)
end)

return nil
