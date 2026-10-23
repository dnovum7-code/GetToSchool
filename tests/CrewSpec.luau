--!strict
local TestLib = require("./TestLib")
local CrewRules = require("../src/shared/Crew/CrewRules")
local TomatoMath = require("../src/shared/Crew/TomatoMath")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local function count(assignment: { [string]: number }, id: number): number
	return #CrewRules.controlsOf(assignment, id)
end

describe("CrewRules (Duo/Chaos)", function()
	it("Bits hin und zurueck", function()
		local bits = CrewRules.toBits({ Gas = true, Left = true, Items = true })
		expect(CrewRules.has(bits, "Gas")).toBe(true)
		expect(CrewRules.has(bits, "Left")).toBe(true)
		expect(CrewRules.has(bits, "Brake")).toBe(false)
		expect(CrewRules.has(bits, "Items")).toBe(true)
	end)

	it("Chaos: jedes Steuerelement genau einmal, gleich verteilt, reproduzierbar", function()
		local a = CrewRules.assign({ 10, 20 }, 42)
		expect(count(a, 10)).toBe(4)
		expect(count(a, 20)).toBe(4)
		expect(CrewRules.assign({ 10, 20 }, 42)).toEqual(a)
		local four = CrewRules.assign({ 1, 2, 3, 4 }, 7)
		for id = 1, 4 do
			expect(count(four, id)).toBe(2)
		end
		local three = CrewRules.assign({ 1, 2, 3 }, 7)
		expect(count(three, 1) + count(three, 2) + count(three, 3)).toBe(8)
		local solo = CrewRules.assign({ 5 }, 1)
		expect(count(solo, 5)).toBe(8)
	end)

	it("Server laesst nur eigene Steuerelemente durch", function()
		local a = CrewRules.assign({ 10, 20 }, 3)
		local all = 255
		local mine = CrewRules.allowedBits(a, 10, all)
		for _, control in CrewRules.CONTROLS do
			expect(CrewRules.has(mine, control)).toBe(a[control] == 10)
		end
		expect(CrewRules.allowedBits(a, 99, all)).toBe(0)
	end)

	it("Gastgeber setzt zusammen, 0,5 s ohne Meldung = losgelassen", function()
		local a = { Gas = 1, Brake = 2, Left = 1, Right = 2, Jump = 1, Drift = 2, Boost = 1, Items = 2 }
		local remote = { [2] = { bits = CrewRules.toBits({ Right = true, Brake = true }), at = 10 } }
		local held = CrewRules.merge(1, CrewRules.toBits({ Gas = true, Right = true }), remote, a, 10.3, 0.5)
		expect(held.Gas).toBe(true)
		expect(held.Right).toBe(true) -- vom Mitfahrer
		expect(held.Brake).toBe(true)
		local throttle, steer = CrewRules.drive(held)
		expect(throttle).toBe(0)
		expect(steer).toBe(1)
		held = CrewRules.merge(1, 0, remote, a, 10.6, 0.5) -- Meldung zu alt
		expect(held.Right).toBe(false)
		expect(held.Brake).toBe(false)
	end)

	it("laufende Nummern", function()
		expect(CrewRules.acceptSeq(nil, 1)).toBe(true)
		expect(CrewRules.acceptSeq(5, 5)).toBe(false)
		expect(CrewRules.acceptSeq(5, 4)).toBe(false)
		expect(CrewRules.acceptSeq(5, 6)).toBe(true)
		expect(CrewRules.acceptSeq(5, "6")).toBe(false)
	end)

	it("Munition laedt langsam nach", function()
		local ammo, last = CrewRules.regen(2, 5, 0, 7, 3)
		expect(ammo).toBe(4)
		expect(last).toBe(6)
		ammo = CrewRules.regen(5, 5, 0, 100, 3)
		expect(ammo).toBe(5)
	end)

	it("Tomaten-Schutz fuer Solo-Laeufe", function()
		expect(CrewRules.canBeHit(false, true, false, true)).toBe(false) -- Solo im Lauf
		expect(CrewRules.canBeHit(false, true, true, true)).toBe(true) -- freiwillig bewerfbar
		expect(CrewRules.canBeHit(false, false, false, true)).toBe(true) -- ausserhalb eines Laufs
		expect(CrewRules.canBeHit(true, true, false, true)).toBe(true) -- Duo/Chaos
		expect(CrewRules.canBeHit(false, true, false, false)).toBe(true) -- Schutz aus
	end)
end)

describe("TomatoMath (Tomatenwurf)", function()
	it("Bahn mit Schwerkraft", function()
		local x, y, z = TomatoMath.at({ 0, 10, 0 }, { 10, 20, 0 }, 40, 1)
		expect(x).toBe(10)
		expect(y).toBe(10)
		expect(z).toBe(0)
	end)

	it("erster Treffer auf der Bahn, mit Spielraum (Radius)", function()
		local targets = {
			{ id = "weit", x = 100, y = 0, z = 0, radius = 3 },
			{ id = "nah", x = 20, y = 10, z = 0, radius = 3 },
		}
		local id, t = TomatoMath.firstHit({ 0, 10, 0 }, { 40, 0, 0 }, 0, targets, 3, 0.05)
		expect(id).toBe("nah")
		expect(t ~= nil and t < 0.6).toBe(true)
		local none = TomatoMath.firstHit({ 0, 10, 0 }, { 0, 0, 40 }, 0, targets, 3, 0.05)
		expect(none).toBeNil()
	end)
end)

return nil
