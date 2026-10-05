--!strict
local TestLib = require("./TestLib")
local RunRules = require("../src/shared/Progression/RunRules")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

describe("RunRules: Leben und Helm", function()
	it("neuer Lauf hat volle Leben und vollen Helm", function()
		local state = RunRules.newRun(5, 2)
		expect(state.lives).toBe(5)
		expect(state.maxLives).toBe(5)
		expect(state.shield).toBe(2)
	end)

	it("Treffer ohne Helm kostet ein Leben, bei 0 ist Game Over", function()
		local state = RunRules.newRun(2, 0)
		expect(RunRules.applyHit(state)).toBe("LifeLost")
		expect(state.lives).toBe(1)
		expect(RunRules.applyHit(state)).toBe("GameOver")
		expect(state.lives).toBe(0)
		expect(RunRules.applyHit(state)).toBe("GameOver")
		expect(state.lives).toBe(0)
	end)

	it("Helm faengt Treffer ab, bis er leer ist", function()
		local state = RunRules.newRun(5, 2)
		expect(RunRules.applyHit(state)).toBe("Shielded")
		expect(RunRules.applyHit(state)).toBe("Shielded")
		expect(state.lives).toBe(5)
		expect(RunRules.applyHit(state)).toBe("LifeLost")
		expect(state.lives).toBe(4)
	end)

	it("Checkpoint laedt den Helm wieder auf", function()
		local state = RunRules.newRun(5, 1)
		RunRules.applyHit(state)
		expect(state.shield).toBe(0)
		expect(RunRules.rechargeShield(state)).toBe(true)
		expect(state.shield).toBe(1)
		expect(RunRules.rechargeShield(state)).toBe(false)
	end)

	it("Leben werden nie kleiner als 1 beim Start", function()
		expect(RunRules.newRun(0, 0).lives).toBe(1)
	end)
end)

describe("RunRules.levelValue", function()
	local section = { HelmetCharges1 = 1, HelmetCharges2 = 2, HelmetCharges3 = 3 }
	it("liest den Wert der Stufe", function()
		expect(RunRules.levelValue(section, "HelmetCharges", 2, 0)).toBe(2)
	end)
	it("Stufe 0 gibt den Standardwert", function()
		expect(RunRules.levelValue(section, "HelmetCharges", 0, 0)).toBe(0)
	end)
	it("zu hohe Stufe nimmt die hoechste vorhandene", function()
		expect(RunRules.levelValue(section, "HelmetCharges", 7, 0)).toBe(3)
	end)
end)

return nil
