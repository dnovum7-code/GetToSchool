--!strict
local TestLib = require("./TestLib")
local SpeedFeel = require("../src/shared/Atmosphere/SpeedFeel")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

describe("SpeedFeel (Tempogefuehl)", function()
	it("Sichtfeld erst ab 70 %, weich bis zum vollen Wert", function()
		expect(SpeedFeel.fovExtra(50, 140, 0.7, 10)).toBe(0)
		expect(SpeedFeel.fovExtra(98, 140, 0.7, 10)).toBe(0) -- genau 70 %
		expect(near(SpeedFeel.fovExtra(119, 140, 0.7, 10), 5)).toBe(true) -- Mitte = halb
		expect(SpeedFeel.fovExtra(140, 140, 0.7, 10)).toBe(10)
		expect(SpeedFeel.fovExtra(400, 140, 0.7, 10)).toBe(10)
	end)

	it("Speed-Linien: hohes Tempo oder Boost", function()
		expect(SpeedFeel.speedLines(40, 140, 0.8, false, 0.7)).toBe(0)
		expect(SpeedFeel.speedLines(40, 140, 0.8, true, 0.7)).toBe(0.7)
		expect(SpeedFeel.speedLines(140, 140, 0.8, true, 0.7)).toBe(1)
	end)

	it("Fahrtwind lauter und hoeher mit dem Tempo", function()
		local v0, p0 = SpeedFeel.wind(0, 140, 0.15, 0.6, 0.8, 1.5)
		local v1, p1 = SpeedFeel.wind(140, 140, 0.15, 0.6, 0.8, 1.5)
		expect(v0).toBe(0)
		expect(p0).toBe(0.8)
		expect(v1).toBe(0.6)
		expect(p1).toBe(1.5)
	end)

	it("Untergrund nach Material", function()
		expect(SpeedFeel.surface("LeafyGrass")).toBe("Grass")
		expect(SpeedFeel.surface("Mud")).toBe("Dirt")
		expect(SpeedFeel.surface("Asphalt")).toBe("Asphalt")
		expect(SpeedFeel.surface("Snow")).toBe("Snow")
		expect(SpeedFeel.surface("Neon")).toBeNil()
	end)

	it("Radpartikel: Tempo, Drift, Obergrenze", function()
		expect(SpeedFeel.wheelRate(20, 5, 140, 8, false, 3, 40)).toBe(0)
		expect(SpeedFeel.wheelRate(20, 70, 140, 8, false, 3, 40)).toBe(10)
		expect(SpeedFeel.wheelRate(20, 70, 140, 8, true, 3, 40)).toBe(30)
		expect(SpeedFeel.wheelRate(20, 140, 140, 8, true, 3, 40)).toBe(40)
	end)

	it("Musik: zweite Spur mit Tempo, beim Boost voll", function()
		expect(SpeedFeel.musicIntensity(0.3, 0.6, false)).toBe(0)
		expect(SpeedFeel.musicIntensity(1, 0.6, false)).toBe(1)
		expect(SpeedFeel.musicIntensity(0.1, 0.6, true)).toBe(1)
	end)

	it("Ueberblenden: gleichmaessig, nie ueber das Ziel", function()
		expect(SpeedFeel.approach(0, 1, 0.5, 2)).toBe(0.25)
		expect(SpeedFeel.approach(0.9, 1, 0.5, 2)).toBe(1)
		expect(SpeedFeel.approach(1, 0, 1, 2)).toBe(0.5)
	end)
end)

return nil
