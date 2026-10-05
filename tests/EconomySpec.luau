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

return nil
