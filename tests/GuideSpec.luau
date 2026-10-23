--!strict
local TestLib = require("./TestLib")
local GuideMath = require("../src/shared/Toolkit/GuideMath")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

describe("GuideMath (Barrieren, Stabil-Zone)", function()
	it("gleitet entlang statt abzuprallen, Tempo bleibt", function()
		-- Wand rechts (Normale zeigt nach links, -X), Wagen faehrt schraeg nach vorne-rechts
		local vx, vz = GuideMath.slide(30, -40, -1, 0, 1, 0)
		expect(near(vx, 0)).toBe(true)
		expect(near(vz, -50)).toBe(true) -- ganzes Tempo (50) jetzt entlang der Wand
	end)

	it("drueckt etwas von der Wand weg, bremst mit keep", function()
		local vx, vz = GuideMath.slide(30, -40, -1, 0, 0.9, 4)
		expect(near(vx, -4)).toBe(true)
		expect(near(vz, -45)).toBe(true)
	end)

	it("faehrt von der Wand weg: nichts aendern", function()
		local vx, vz = GuideMath.slide(-10, -40, -1, 0, 0.5, 4)
		expect(vx).toBe(-10)
		expect(vz).toBe(-40)
	end)

	it("dreht den Blick zur Fahrtrichtung entlang der Wand", function()
		-- Blick nach vorne (-Z), Ziel nach links (-X): Drehung nach links = positiv
		expect(GuideMath.yawRate(0, -1, -1, 0, 2) > 0).toBe(true)
		expect(GuideMath.yawRate(0, -1, 1, 0, 2) < 0).toBe(true)
		expect(GuideMath.yawRate(0, -1, 0, -1, 2)).toBe(0)
	end)

	it("Neigung und Aufrichten erst ab MaxTilt, weich", function()
		expect(near(GuideMath.tilt(1), 0)).toBe(true)
		expect(near(GuideMath.tilt(0), 90)).toBe(true)
		expect(GuideMath.rightingRate(20, 25, 3)).toBe(0)
		expect(near(GuideMath.rightingRate(40, 25, 3), 1.5)).toBe(true)
		expect(GuideMath.rightingRate(120, 25, 3)).toBe(3)
	end)

	it("weicher Uebergang rein und raus", function()
		expect(GuideMath.blend(0, true, 0.25, 0.5)).toBe(0.5)
		expect(GuideMath.blend(0.9, true, 0.25, 0.5)).toBe(1)
		expect(GuideMath.blend(0.5, false, 0.25, 0.5)).toBe(0)
	end)
end)

return nil
