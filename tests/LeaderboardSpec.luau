--!strict
local TestLib = require("./TestLib")
local LeaderboardMath = require("../src/shared/Progression/LeaderboardMath")
local RunValidation = require("../src/shared/Progression/RunValidation")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local RULES = { minTime = 20, minGap = 2, maxSpeed = 300 }

-- Strecke: Start bei z = 0, Checkpoints alle 1000 Studs, Ziel bei z = 4000
local CHECKPOINTS: { RunValidation.TrackCheckpoint } = {
	{ key = "CP1", order = 1 },
	{ key = "CP2a", order = 2 }, -- zwei alternative Wege
	{ key = "CP2b", order = 2 },
	{ key = "CP3", order = 3 },
}

local function visit(key: string, order: number?, at: number, z: number): RunValidation.Visit
	return { key = key, order = order, at = at, position = { 0, 0, z } }
end

local function run(time: number, visits: { RunValidation.Visit }): RunValidation.Run
	return { time = time, startPosition = { 0, 0, 0 }, finishPosition = { 0, 0, 4000 }, visits = visits }
end

local function goodVisits(): { RunValidation.Visit }
	return {
		visit("CP1", 1, 10, 1000),
		visit("CP2b", 2, 20, 2000),
		visit("CP3", 3, 30, 3000),
	}
end

describe("RunValidation (Plausibilitaet)", function()
	it("normaler Lauf ist gueltig", function()
		local ok, reason = RunValidation.check(run(40, goodVisits()), CHECKPOINTS, RULES)
		expect(ok).toBe(true)
		expect(reason).toBeNil()
	end)

	it("zu schnell fuer die Strecke", function()
		local ok, reason = RunValidation.check(run(19, goodVisits()), CHECKPOINTS, RULES)
		expect(ok).toBe(false)
		expect(reason).toBe("TooFast")
	end)

	it("Checkpoint ausgelassen", function()
		local visits = goodVisits()
		table.remove(visits, 2)
		local ok, reason = RunValidation.check(run(40, visits), CHECKPOINTS, RULES)
		expect(ok).toBe(false)
		expect(reason).toBe("Missed")
	end)

	it("alternativer Weg (gleiche Order) reicht einmal", function()
		local visits = goodVisits()
		visits[2] = visit("CP2a", 2, 20, 2000)
		expect((RunValidation.check(run(40, visits), CHECKPOINTS, RULES))).toBe(true)
	end)

	it("falsche Reihenfolge", function()
		local visits = {
			visit("CP1", 1, 10, 1000),
			visit("CP3", 3, 15, 3000),
			visit("CP2a", 2, 25, 2000),
		}
		local ok, reason = RunValidation.check(run(40, visits), CHECKPOINTS, RULES)
		expect(ok).toBe(false)
		expect(reason).toBe("Order")
	end)

	it("Mindestzeit zwischen Checkpoints", function()
		local visits = goodVisits()
		visits[2] = visit("CP2b", 2, 11, 1100)
		local ok, reason = RunValidation.check(run(40, visits), CHECKPOINTS, RULES)
		expect(ok).toBe(false)
		expect(reason).toBe("Gap")
	end)

	it("unmoeglich schneller Abschnitt (Teleport)", function()
		local visits = goodVisits()
		visits[3] = visit("CP3", 3, 23, 3000) -- 1000 Studs in 3 s, aber Abstand ok
		visits[2] = visit("CP2b", 2, 20, 2000)
		local ok, reason = RunValidation.check(run(40, visits), CHECKPOINTS, RULES)
		expect(ok).toBe(false)
		expect(reason).toBe("Speed")
	end)

	it("letzter Abschnitt bis ins Ziel zaehlt auch", function()
		local ok, reason = RunValidation.check(run(31, goodVisits()), CHECKPOINTS, RULES)
		expect(ok).toBe(false)
		expect(reason).toBe("Speed")
	end)

	it("Optional-Checkpoints sind keine Pflicht, Wiederholungen zaehlen nicht", function()
		local checkpoints = table.clone(CHECKPOINTS)
		table.insert(checkpoints, { key = "Extra", optional = true })
		local visits = goodVisits()
		table.insert(visits, visit("CP1", 1, 35, 1000)) -- R: zurueck zum Checkpoint, spaeter wieder
		expect((RunValidation.check(run(40, visits), checkpoints, RULES))).toBe(true)
	end)

	it("Strecke ohne Checkpoints: nur Mindestzeit und Tempo", function()
		expect((RunValidation.check(run(20, {}), {}, RULES))).toBe(true)
		expect((RunValidation.check(run(10, {}), {}, RULES))).toBe(false)
	end)

	it("Checkpoints ohne Order muessen alle durchfahren werden", function()
		local checkpoints = { { key = "A" }, { key = "B" } }
		local visits = { visit("A", nil, 10, 1000) }
		local ok, reason = RunValidation.check(run(40, visits), checkpoints, RULES)
		expect(ok).toBe(false)
		expect(reason).toBe("Missed")
	end)

	it("jeder Grund hat einen Anzeigetext", function()
		for _, key in { "TooFast", "Missed", "Order", "Gap", "Speed" } do
			expect(type(RunValidation.REASONS[key])).toBe("string")
		end
	end)
end)

describe("LeaderboardMath (Bestenlisten)", function()
	it("Zeiten in Millisekunden, Weiten in Zehntel-Metern", function()
		expect(LeaderboardMath.encode("Time", 45.1234)).toBe(45123)
		expect(LeaderboardMath.decode("Time", 45123)).toBe(45.123)
		expect(LeaderboardMath.encode("Distance", 87.26)).toBe(873)
		expect(LeaderboardMath.decode("Distance", 873)).toBe(87.3)
	end)

	it("besser: Zeit kleiner, Weite groesser", function()
		expect(LeaderboardMath.isBetter("Time", 100, 200)).toBe(true)
		expect(LeaderboardMath.isBetter("Time", 200, 100)).toBe(false)
		expect(LeaderboardMath.isBetter("Distance", 200, 100)).toBe(true)
		expect(LeaderboardMath.isBetter("Distance", 5, nil)).toBe(true)
		expect(LeaderboardMath.ascending("Time")).toBe(true)
		expect(LeaderboardMath.ascending("Distance")).toBe(false)
	end)

	it("Plaetze: sortiert, gleicher Wert = gleicher Platz", function()
		local ranked = LeaderboardMath.rank("Time", {
			{ userId = 5, value = 300 },
			{ userId = 2, value = 100 },
			{ userId = 9, value = 200 },
			{ userId = 1, value = 200 },
		})
		expect(ranked[1].userId).toBe(2)
		expect(ranked[1].rank).toBe(1)
		expect(ranked[2].userId).toBe(1)
		expect(ranked[2].rank).toBe(2)
		expect(ranked[3].userId).toBe(9)
		expect(ranked[3].rank).toBe(2)
		expect(ranked[4].rank).toBe(4)
	end)

	it("Weiten absteigend", function()
		local ranked = LeaderboardMath.rank("Distance", {
			{ userId = 1, value = 10 },
			{ userId = 2, value = 30 },
		})
		expect(ranked[1].userId).toBe(2)
	end)

	it("eigenen Platz finden und Top N", function()
		local ranked = LeaderboardMath.rank("Time", {
			{ userId = 1, value = 3 },
			{ userId = 2, value = 1 },
			{ userId = 3, value = 2 },
		})
		local own = LeaderboardMath.find(ranked, 1)
		assert(own)
		expect(own.rank).toBe(3)
		expect(LeaderboardMath.find(ranked, 99)).toBeNil()
		expect(#LeaderboardMath.top(ranked, 2)).toBe(2)
		expect(#LeaderboardMath.top(ranked, 10)).toBe(3)
	end)
end)
