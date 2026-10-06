--!strict
local TestLib = require("./TestLib")
local Combo = require("../src/shared/Progression/Combo")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local CFG: Combo.Config = { Window = 2.5, MaxMultiplier = 5, StepBonus = 4 }

describe("Combo (Kuh-Kombo)", function()
	it("Treffer kurz hintereinander zaehlen hoch", function()
		local state = Combo.new()
		expect(Combo.hit(state, 10, CFG)).toBe(1)
		expect(Combo.hit(state, 11, CFG)).toBe(2)
		expect(Combo.hit(state, 13.4, CFG)).toBe(3)
		expect(Combo.isActive(state, 14, CFG)).toBe(true)
	end)

	it("Pause beendet die Kombo", function()
		local state = Combo.new()
		Combo.hit(state, 0, CFG)
		Combo.hit(state, 1, CFG)
		expect(Combo.hit(state, 4, CFG)).toBe(1)
		expect(Combo.isActive(state, 4, CFG)).toBe(false)
	end)

	it("Multiplikator begrenzt", function()
		expect(Combo.multiplier(1, CFG)).toBe(1)
		expect(Combo.multiplier(3, CFG)).toBe(3)
		expect(Combo.multiplier(9, CFG)).toBe(5)
		expect(Combo.multiplier(0, CFG)).toBe(1)
	end)

	it("Bonus: Grundbonus mal Multiplikator plus Stufen-Extra", function()
		expect(Combo.bonus(2, 1, CFG)).toBe(2)
		expect(Combo.bonus(2, 2, CFG)).toBe(8) -- 2*2 + 1*4
		expect(Combo.bonus(3, 3, CFG)).toBe(17) -- 3*3 + 2*4
		expect(Combo.bonus(0, 4, CFG)).toBe(12) -- auch ohne Flugbonus gibt es das Extra
		expect(Combo.bonus(10, 20, CFG)).toBe(66) -- 10*5 + 4*4
	end)
end)
