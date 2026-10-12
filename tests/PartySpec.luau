--!strict
local TestLib = require("./TestLib")
local PartyRules = require("../src/shared/Progression/PartyRules")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local function entry(name: string, score: number, lives: number, alive: boolean, outAt: number): PartyRules.Entry
	return { id = #name, name = name, score = score, lives = lives, alive = alive, outAt = outAt }
end

local function places(ranked: { PartyRules.Ranked }): { string }
	local result = {}
	for _, item in ranked do
		table.insert(result, `{item.place}:{item.entry.name}`)
	end
	return result
end

describe("PartyRules (Party-Modi)", function()
	it("Kuh-Bowling: mehr Meter gewinnt, Gleichstand teilt den Platz", function()
		local ranked = PartyRules.rankCowBowling({
			entry("Anna", 120, 0, true, 0),
			entry("Ben", 300, 0, true, 0),
			entry("Cleo", 120, 0, true, 0),
			entry("Dan", 0, 0, true, 0),
		})
		expect(places(ranked)).toEqual({ "1:Ben", "2:Anna", "2:Cleo", "4:Dan" })
	end)

	it("Letzter Wagen: wer noch faehrt vor Ausgeschiedenen, spaeter raus = besser", function()
		local ranked = PartyRules.rankLastCart({
			entry("Anna", 0, 0, false, 40),
			entry("Ben", 0, 2, true, 0),
			entry("Cleo", 0, 0, false, 75),
			entry("Dan", 0, 1, true, 0),
		})
		expect(places(ranked)).toEqual({ "1:Ben", "2:Dan", "3:Cleo", "4:Anna" })
	end)

	it("Letzter Wagen: Zeit um, gleich viele Leben = Gleichstand", function()
		local ranked = PartyRules.rankLastCart({
			entry("Anna", 0, 2, true, 0),
			entry("Ben", 0, 2, true, 0),
			entry("Cleo", 0, 1, true, 0),
		})
		expect(places(ranked)).toEqual({ "1:Anna", "1:Ben", "3:Cleo" })
	end)

	it("Belohnung je nach Platz, sonst Teilnahme", function()
		local rewards = { 60, 35, 20 }
		expect(PartyRules.reward(1, rewards, 10)).toBe(60)
		expect(PartyRules.reward(3, rewards, 10)).toBe(20)
		expect(PartyRules.reward(4, rewards, 10)).toBe(10)
	end)

	it("Start ab genug Spielern", function()
		expect(PartyRules.canStart(1, 2)).toBe(false)
		expect(PartyRules.canStart(2, 2)).toBe(true)
		expect(PartyRules.canStart(1, 1)).toBe(true)
	end)

	it("Letzter Wagen: Rundenende", function()
		expect(PartyRules.lastCartOver(2, 3, 30, 180)).toBe(false)
		expect(PartyRules.lastCartOver(1, 3, 30, 180)).toBe(true)
		expect(PartyRules.lastCartOver(3, 3, 180, 180)).toBe(true)
		-- allein (Test in Studio): erst vorbei, wenn man selbst raus ist
		expect(PartyRules.lastCartOver(1, 1, 30, 180)).toBe(false)
		expect(PartyRules.lastCartOver(0, 1, 30, 180)).toBe(true)
	end)

	it("Eskalation: erst nach einer Weile, dann in Stufen", function()
		expect(PartyRules.dangerLevel(59, 60, 30)).toBe(0)
		expect(PartyRules.dangerLevel(60, 60, 30)).toBe(1)
		expect(PartyRules.dangerLevel(95, 60, 30)).toBe(2)
	end)
end)

return nil
