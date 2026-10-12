--!strict
local TestLib = require("./TestLib")
local PursuerLogic = require("../src/shared/Toolkit/PursuerLogic")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local P: PursuerLogic.Params = { baseSpeed = 40, catchUpSpeed = 60, minGap = 30, maxGap = 130 }

describe("PursuerLogic (Verfolger mit Gummiband)", function()
	it("Strecke entlang der Wegpunkte", function()
		local cum = PursuerLogic.cumulative({ 10, 30, 0, 20 })
		expect(cum).toEqual({ 0, 10, 40, 40, 60 })
		local i, a = PursuerLogic.locate(cum, 25)
		expect(i).toBe(2)
		expect(a).toBe(0.5)
		i, a = PursuerLogic.locate(cum, 999)
		expect(i).toBe(4)
		expect(a).toBe(1)
		i, a = PursuerLogic.locate(cum, -5)
		expect(i).toBe(1)
		expect(a).toBe(0)
	end)

	it("nah dran: Grundtempo, weit weg: volles Aufholen", function()
		expect(PursuerLogic.speed(10, P)).toBe(40)
		expect(PursuerLogic.speed(80, P)).toBe(70)
		expect(PursuerLogic.speed(500, P)).toBe(100)
	end)

	it("faehrt der Spieler gut, faellt er zurueck, aber nie weiter als maxGap", function()
		-- Spieler schon 300 voraus: Verfolger wird auf maxGap nachgezogen
		expect(PursuerLogic.advance(0, 300, 0.1, P, 1000)).toBe(170)
	end)

	it("steht der Spieler (Crash), holt er auf", function()
		local s, player = 100, 200
		for _ = 1, 30 do
			s = PursuerLogic.advance(s, player, 0.1, P, 1000)
		end
		expect(player - s < 30).toBe(true)
	end)

	it("nie ueber das Wegende hinaus", function()
		expect(PursuerLogic.advance(995, 2000, 1, P, 1000)).toBe(1000)
	end)

	it("Startlage hinter dem Spieler, nie vor Punkt 1", function()
		expect(PursuerLogic.behind(200, 30)).toBe(170)
		expect(PursuerLogic.behind(10, 30)).toBe(0)
	end)

	it("Bedrohung fuer die Anzeige", function()
		expect(PursuerLogic.danger(8, 8, 68)).toBe(1)
		expect(PursuerLogic.danger(38, 8, 68)).toBe(0.5)
		expect(PursuerLogic.danger(200, 8, 68)).toBe(0)
	end)
end)

return nil
