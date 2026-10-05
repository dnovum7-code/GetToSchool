--!strict
local TestLib = require("./TestLib")
local LaunchMath = require("../src/shared/Progression/LaunchMath")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local cfg = {
	SpeedCarry = 1,
	UpRatio = 0.8,
	Gravity = 50,
	SkyUpRatio = 1.5,
	SkyAcceleration = 300,
	SkyTime = 2.5,
	MaxFlightTime = 10,
	BonusPerMeter = 0.02,
	MaxBonus = 10,
}

describe("LaunchMath", function()
	it("normaler Flug: Wurfparabel landet wieder auf Abwurfhoehe", function()
		local flight = LaunchMath.plan(80, 140, false, cfg)
		expect(flight.horizontalSpeed).toBe(220)
		expect(flight.verticalSpeed).toBeNear(112)
		expect(flight.duration).toBeNear(2 * 112 / 50)
		expect(flight.distance).toBeNear(220 * flight.duration)
		local along, up = LaunchMath.offset(flight, flight.duration)
		expect(along).toBeNear(flight.distance)
		expect(up).toBeNear(0, 1e-6)
		local _, top = LaunchMath.offset(flight, flight.duration / 2)
		expect(top).toBeGreaterThan(100)
	end)

	it("Flugdauer ist begrenzt", function()
		local flight = LaunchMath.plan(0, 10000, false, cfg)
		expect(flight.duration).toBe(10)
	end)

	it("Himmelsflug steigt immer weiter und ist weiter als ein normaler Flug", function()
		local sky = LaunchMath.plan(80, 140, true, cfg)
		local normal = LaunchMath.plan(80, 140, false, cfg)
		expect(sky.sky).toBe(true)
		expect(sky.duration).toBe(2.5)
		local _, upHalf = LaunchMath.offset(sky, 1.25)
		local _, upEnd = LaunchMath.offset(sky, 2.5)
		expect(upEnd).toBeGreaterThan(upHalf)
		expect(sky.distance).toBeGreaterThan(normal.distance)
		expect(LaunchMath.distanceAt(sky, sky.duration)).toBeNear(sky.distance, 1e-3)
	end)

	it("Anzeige zaehlt von 0 bis zur Flugweite hoch", function()
		local flight = LaunchMath.plan(50, 100, false, cfg)
		expect(LaunchMath.distanceAt(flight, 0)).toBe(0)
		expect(LaunchMath.distanceAt(flight, flight.duration * 2)).toBeNear(flight.distance)
	end)

	it("Meter und Bonus", function()
		expect(LaunchMath.meters(1000, 0.28)).toBe(280)
		expect(LaunchMath.bonus(280, cfg)).toBe(5)
		expect(LaunchMath.bonus(10000, cfg)).toBe(10)
		expect(LaunchMath.bonus(10, cfg)).toBe(0)
	end)

	it("Himmel-Chance", function()
		expect(LaunchMath.isSky(0.1, 0.25)).toBe(true)
		expect(LaunchMath.isSky(0.3, 0.25)).toBe(false)
		expect(LaunchMath.isSky(0.99, 2)).toBe(true)
		expect(LaunchMath.isSky(0, 0)).toBe(false)
	end)
end)

return nil
