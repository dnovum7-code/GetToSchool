--!strict
local TestLib = require("./TestLib")
local NearMissRules = require("../src/shared/Progression/NearMissRules")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

describe("NearMissRules (KNAPP!)", function()
	it("knapp vorbei ohne Beruehrung = Bonus", function()
		local tracker = NearMissRules.newTracker()
		expect(#NearMissRules.step(tracker, { auto = true }, {}, 0, 60, 30, 1.5)).toBe(0)
		local awarded = NearMissRules.step(tracker, {}, {}, 0.2, 60, 30, 1.5)
		expect(awarded).toEqual({ "auto" })
	end)

	it("beruehrt = kein Bonus", function()
		local tracker = NearMissRules.newTracker()
		NearMissRules.step(tracker, { kuh = true }, {}, 0, 60, 30, 1.5)
		NearMissRules.step(tracker, { kuh = true }, { kuh = true }, 0.1, 60, 30, 1.5)
		expect(#NearMissRules.step(tracker, {}, {}, 0.2, 60, 30, 1.5)).toBe(0)
	end)

	it("zu langsam = kein Bonus", function()
		local tracker = NearMissRules.newTracker()
		NearMissRules.step(tracker, { stein = true }, {}, 0, 10, 30, 1.5)
		expect(#NearMissRules.step(tracker, {}, {}, 0.2, 10, 30, 1.5)).toBe(0)
	end)

	it("dasselbe Objekt nur nach der Abklingzeit wieder", function()
		local tracker = NearMissRules.newTracker()
		NearMissRules.step(tracker, { tor = true }, {}, 0, 60, 30, 1.5)
		expect(#NearMissRules.step(tracker, {}, {}, 0.1, 60, 30, 1.5)).toBe(1)
		NearMissRules.step(tracker, { tor = true }, {}, 0.5, 60, 30, 1.5)
		expect(#NearMissRules.step(tracker, {}, {}, 0.6, 60, 30, 1.5)).toBe(0)
		NearMissRules.step(tracker, { tor = true }, {}, 2, 60, 30, 1.5)
		expect(#NearMissRules.step(tracker, {}, {}, 2.1, 60, 30, 1.5)).toBe(1)
	end)

	it("Server: Abstand, Hoechstzahl pro Lauf, neuer Lauf", function()
		local budget: NearMissRules.Budget = { runId = 0, count = 0, last = -math.huge }
		expect(NearMissRules.allow(budget, 1, 0, 0.5, 2)).toBe(true)
		expect(NearMissRules.allow(budget, 1, 0.2, 0.5, 2)).toBe(false)
		expect(NearMissRules.allow(budget, 1, 1, 0.5, 2)).toBe(true)
		expect(NearMissRules.allow(budget, 1, 2, 0.5, 2)).toBe(false) -- 2 pro Lauf
		expect(NearMissRules.allow(budget, 2, 2.1, 0.5, 2)).toBe(true) -- neuer Lauf
	end)
end)

return nil
