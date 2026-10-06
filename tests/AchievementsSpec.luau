--!strict
local TestLib = require("./TestLib")
local Achievements = require("../src/shared/Progression/Achievements")
local SaveData = require("../src/shared/Progression/SaveData")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local DEFS: { Achievements.Def } = {
	{ id = "First", name = "Puenktlich", description = "Beende {goal} Lauf", type = "Finishes", goal = 1 },
	{ id = "Space", name = "Kuh im All", description = "", type = "SkyLaunch" },
	{ id = "Far", name = "Weit", description = "{meters} m", type = "Flight", meters = 300 },
	{ id = "Coins1", name = "Sparschwein", description = "Alle Muenzen auf {track}", type = "AllCoins", track = "Track1" },
	{ id = "Grade6", name = "Klassenbester", description = "", type = "AllGrades", grade = 6 },
	{ id = "Clean", name = "Ohne Kratzer", description = "", type = "Flawless" },
	{ id = "Ghost", name = "Geisterjaeger", description = "", type = "BeatGhost" },
	{ id = "Drift", name = "Drift-Koenig", description = "", type = "DriftTotal", goal = 300 },
	{ id = "Garage", name = "Fuhrpark", description = "", type = "AllVehicles" },
	{ id = "Launch50", name = "Kuh-Fluesterer", description = "", type = "Launches", goal = 50 },
	{ id = "Homework", name = "Streber", description = "", type = "HomeworkDay" },
}

local function facts(overrides: { [string]: any }?): Achievements.Facts
	local result: { [string]: any } = {
		event = nil,
		finishedRuns = 0,
		objectsLaunched = 0,
		driftSeconds = 0,
		bestGrades = {},
		trackIds = { "Track1", "Track2" },
		vehiclesOwned = 1,
		vehiclesTotal = 3,
	}
	for key, value in overrides or {} do
		result[key] = value
	end
	return result :: any
end

local function ids(list: { Achievements.Def }): { string }
	local result = {}
	for _, def in list do
		table.insert(result, def.id)
	end
	table.sort(result)
	return result
end

describe("Achievements (Erfolge)", function()
	it("am Anfang nichts", function()
		expect(#Achievements.check(DEFS, {}, facts())).toBe(0)
	end)

	it("erster Lauf, ohne Kratzer, nur einmal", function()
		local unlocked = {}
		local newly = Achievements.check(DEFS, unlocked, facts({
			finishedRuns = 1,
			event = { type = "Finish", trackId = "Track1", livesLost = 0, isNewBest = true, hadPrevious = false },
		}))
		expect(ids(newly)).toEqual({ "Clean", "First" })
		expect(#Achievements.check(DEFS, unlocked, facts({ finishedRuns = 2 }))).toBe(0)
	end)

	it("Geist schlagen braucht eine alte Bestzeit", function()
		local unlocked = {}
		Achievements.check(DEFS, unlocked, facts({ event = { type = "Finish", livesLost = 1, isNewBest = true, hadPrevious = false } }))
		expect(unlocked.Ghost).toBeNil()
		Achievements.check(DEFS, unlocked, facts({ event = { type = "Finish", livesLost = 1, isNewBest = true, hadPrevious = true } }))
		expect(unlocked.Ghost).toBe(true)
	end)

	it("Kuh im All und Weitwurf", function()
		local unlocked = {}
		Achievements.check(DEFS, unlocked, facts({ event = { type = "Launch", sky = false, meters = 299 } }))
		expect(unlocked.Space).toBeNil()
		expect(unlocked.Far).toBeNil()
		Achievements.check(DEFS, unlocked, facts({ event = { type = "Launch", sky = true, meters = 300 } }))
		expect(unlocked.Space).toBe(true)
		expect(unlocked.Far).toBe(true)
	end)

	it("alle Muenzen nur auf der richtigen Strecke", function()
		local unlocked = {}
		Achievements.check(DEFS, unlocked, facts({ event = { type = "Finish", trackId = "Track2", allCoins = true, livesLost = 1 } }))
		expect(unlocked.Coins1).toBeNil()
		Achievements.check(DEFS, unlocked, facts({ event = { type = "Finish", trackId = "Track1", allCoins = true, livesLost = 1 } }))
		expect(unlocked.Coins1).toBe(true)
	end)

	it("Note 6 auf allen Strecken, mit Fortschritt", function()
		local def = DEFS[5]
		local f = facts({ bestGrades = { Track1 = 6, Track2 = 5 } })
		local current, goal = Achievements.progress(def, f)
		expect(current).toBe(1)
		expect(goal).toBe(2)
		expect(Achievements.isMet(def, f)).toBe(false)
		expect(Achievements.isMet(def, facts({ bestGrades = { Track1 = 6, Track2 = 6 } }))).toBe(true)
		expect(Achievements.isMet(def, facts({ trackIds = {} }))).toBe(false)
	end)

	it("Zaehler: Drift, Launches, Fahrzeuge, Hausaufgaben", function()
		local unlocked = {}
		local newly = Achievements.check(DEFS, unlocked, facts({
			driftSeconds = 300.5,
			objectsLaunched = 50,
			vehiclesOwned = 3,
			event = { type = "HomeworkDone" },
		}))
		expect(ids(newly)).toEqual({ "Drift", "Garage", "Homework", "Launch50" })
		local current, goal = Achievements.progress(DEFS[8], facts({ driftSeconds = 12.7 }))
		expect(current).toBe(12)
		expect(goal).toBe(300)
	end)

	it("Texte", function()
		expect(Achievements.describe(DEFS[4], function()
			return "Der Schulweg"
		end)).toBe("Alle Muenzen auf Der Schulweg")
		expect(Achievements.describe(DEFS[3])).toBe("300 m")
	end)

	it("Spielstand: Erfolge und Driftzeit", function()
		local data = SaveData.migrate({ version = 2, achievements = { First = true, Bad = 1 }, stats = { driftSeconds = 12.5 } })
		assert(data)
		expect(data.achievements.First).toBe(true)
		expect(data.achievements.Bad).toBeNil()
		expect(data.stats.driftSeconds).toBe(12.5)
		local stored = SaveData.new()
		stored.achievements.First = true
		stored.stats.driftSeconds = 10
		local session = SaveData.new()
		session.achievements.Space = true
		session.stats.driftSeconds = 2.5
		local merged = SaveData.merge(stored, session)
		expect(merged.achievements.First).toBe(true)
		expect(merged.achievements.Space).toBe(true)
		expect(merged.stats.driftSeconds).toBe(12.5)
	end)
end)
