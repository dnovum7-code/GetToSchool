--!strict
local TestLib = require("./TestLib")
local TrickMath = require("../src/shared/Progression/TrickMath")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local CFG: TrickMath.Config = {
	MinTrickDegrees = 150,
	SpinTolerance = 30,
	CleanAngle = 35,
	CrashAngle = 70,
	CoinsPerHalfSpin = 3,
	MaxHalfSpins = 6,
}

describe("TrickMath (Lufttricks)", function()
	it("kleine Drehung ist kein Trick", function()
		local result = TrickMath.evaluate(90, 80, CFG)
		expect(result.kind).toBe("None")
		expect(result.coins).toBe(0)
	end)

	it("halbe Drehungen mit Toleranz", function()
		expect(TrickMath.halfSpins(355, 30)).toBe(2)
		expect(TrickMath.halfSpins(-340, 30)).toBe(2)
		expect(TrickMath.halfSpins(320, 30)).toBe(1)
		expect(TrickMath.halfSpins(720, 30)).toBe(4)
	end)

	it("saubere 360 bringt Muenzen", function()
		local result = TrickMath.evaluate(360, 10, CFG)
		expect(result.kind).toBe("Clean")
		expect(result.halfSpins).toBe(2)
		expect(result.coins).toBe(6)
	end)

	it("180 und rueckwaerts gelandet ist auch sauber", function()
		local result = TrickMath.evaluate(-185, 175, CFG)
		expect(result.kind).toBe("Clean")
		expect(result.halfSpins).toBe(1)
	end)

	it("wackelig und schief", function()
		expect(TrickMath.evaluate(360, 50, CFG).kind).toBe("Wobbly")
		expect(TrickMath.evaluate(360, 50, CFG).coins).toBe(0)
		expect(TrickMath.evaluate(360, 90, CFG).kind).toBe("Crash")
		expect(TrickMath.evaluate(360, -100, CFG).kind).toBe("Crash") -- 80 Grad neben vorwaerts und rueckwaerts
		expect(TrickMath.evaluate(360, -120, CFG).kind).toBe("Wobbly") -- 60 Grad neben rueckwaerts
	end)

	it("Belohnung begrenzt", function()
		expect(TrickMath.coins(20, CFG)).toBe(18)
		expect(TrickMath.coins(-1, CFG)).toBe(0)
	end)

	it("Winkel einpacken und Anzeige", function()
		expect(TrickMath.wrap(370)).toBe(10)
		expect(TrickMath.wrap(-190)).toBe(170)
		expect(TrickMath.label(3)).toBe("540°")
	end)
end)
