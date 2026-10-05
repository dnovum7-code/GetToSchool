--!strict
local TestLib = require("./TestLib")
local Rng = require("../src/shared/Toolkit/Rng")
local TriggerRules = require("../src/shared/Toolkit/TriggerRules")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

describe("Rng (reproduzierbarer Zufall)", function()
	it("gleiche Eingabe gibt gleiche Zahl", function()
		expect(Rng.at(42, 7, 1)).toBe(Rng.at(42, 7, 1))
	end)
	it("andere Eingabe gibt andere Zahl", function()
		expect(Rng.at(42, 7, 1) ~= Rng.at(42, 8, 1)).toBe(true)
		expect(Rng.at(42, 7, 1) ~= Rng.at(42, 7, 2)).toBe(true)
		expect(Rng.at(42, 7, 1) ~= Rng.at(43, 7, 1)).toBe(true)
	end)
	it("Werte liegen zwischen 0 und 1 und sind gut verteilt", function()
		local sum, low, high = 0, 0, 0
		for i = 1, 2000 do
			local r = Rng.at(1234, i, 3)
			assert(r >= 0 and r < 1, "ausserhalb 0..1")
			sum += r
			if r < 0.5 then
				low += 1
			else
				high += 1
			end
		end
		expect(sum / 2000).toBeNear(0.5, 0.05)
		expect(math.abs(low - high)).toBeLessThan(200)
	end)
	it("grosse Indizes (Serverzeit) funktionieren", function()
		local r = Rng.at(5, 900000000, 1)
		expect(r >= 0 and r < 1).toBe(true)
	end)
	it("range und seedFromString", function()
		local v = Rng.range(1, 2, 3, 10, 20)
		expect(v >= 10 and v < 20).toBe(true)
		expect(Rng.seedFromString("Spawner1")).toBe(Rng.seedFromString("Spawner1"))
		expect(Rng.seedFromString("Spawner1") ~= Rng.seedFromString("Spawner2")).toBe(true)
	end)
end)

describe("TriggerRules", function()
	it("loest nur beim Hineinfahren aus, nicht solange man drin ist", function()
		local state = TriggerRules.new()
		expect(TriggerRules.update(state, false, 0, false, 0)).toBe(false)
		expect(TriggerRules.update(state, true, 1, false, 0)).toBe(true)
		expect(TriggerRules.update(state, true, 2, false, 0)).toBe(false)
		expect(TriggerRules.update(state, false, 3, false, 0)).toBe(false)
		expect(TriggerRules.update(state, true, 4, false, 0)).toBe(true)
	end)
	it("Once: nur einmal pro Lauf, nach rearm wieder", function()
		local state = TriggerRules.new()
		expect(TriggerRules.update(state, true, 1, true, 0)).toBe(true)
		TriggerRules.update(state, false, 2, true, 0)
		expect(TriggerRules.update(state, true, 3, true, 0)).toBe(false)
		TriggerRules.rearm(state)
		expect(TriggerRules.update(state, true, 4, true, 0)).toBe(true)
	end)
	it("Cooldown: zu schnelles Wiederholen zaehlt nicht", function()
		local state = TriggerRules.new()
		expect(TriggerRules.update(state, true, 10, false, 2)).toBe(true)
		TriggerRules.update(state, false, 10.5, false, 2)
		expect(TriggerRules.update(state, true, 11, false, 2)).toBe(false)
		TriggerRules.update(state, false, 11.5, false, 2)
		expect(TriggerRules.update(state, true, 12.5, false, 2)).toBe(true)
	end)
	it("rearm: Wagen steht nach dem Neustart draussen", function()
		local state = TriggerRules.new()
		TriggerRules.update(state, true, 1, false, 0)
		TriggerRules.rearm(state)
		expect(state.inside).toBe(false)
	end)
end)

return nil
