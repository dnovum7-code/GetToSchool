--!strict
local TestLib = require("./TestLib")
local MeterMath = require("../src/shared/Progression/MeterMath")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local CFG: MeterMath.Config = { StudsPerMeter = 3.57, MaxSpeed = 320, Slack = 4, MetersPerCoin = 30 }

describe("MeterMath (gefahrene Meter)", function()
	it("normales Stueck zaehlt", function()
		expect(MeterMath.segment({ 0, 0, 0 }, { 3, 0, 4 }, 0.1, CFG)).toBe(5)
	end)

	it("Teleport zaehlt nicht", function()
		expect(MeterMath.segment({ 0, 0, 0 }, { 500, 0, 0 }, 1 / 60, CFG)).toBe(0)
	end)

	it("Grenze: MaxSpeed * dt + Puffer", function()
		expect(MeterMath.segment({ 0, 0, 0 }, { 36, 0, 0 }, 0.1, CFG)).toBe(36) -- 32 + 4
		expect(MeterMath.segment({ 0, 0, 0 }, { 36.1, 0, 0 }, 0.1, CFG)).toBe(0)
		expect(MeterMath.segment({ 0, 0, 0 }, { 1, 0, 0 }, 0, CFG)).toBe(0)
	end)

	it("Studs in Meter", function()
		expect(MeterMath.toMeters(357, CFG)).toBeNear(100, 0.001)
	end)

	it("Muenzen pro 30 m, nur neue", function()
		expect(MeterMath.coinsDue(29, 0, CFG)).toBe(0)
		expect(MeterMath.coinsDue(30, 0, CFG)).toBe(1)
		expect(MeterMath.coinsDue(95, 1, CFG)).toBe(2)
		expect(MeterMath.coinsDue(95, 5, CFG)).toBe(0)
	end)
end)
