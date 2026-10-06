--!strict
local TestLib = require("./TestLib")
local Homework = require("../src/shared/Progression/Homework")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local POOL: { Homework.Def } = {
	{ id = "Cows", type = "Launch", name = "Kuh", goal = 5, reward = 60, text = "Schleudere {goal} Kuehe" },
	{ id = "Fast1", type = "FinishUnder", track = "Track1", time = 45, reward = 100, text = "Fahre {track} unter {time}" },
	{ id = "Drift", type = "Drift", goal = 30, reward = 50, text = "Drifte insgesamt {goal} Sekunden" },
	{ id = "Flawless", type = "Flawless", reward = 80, text = "Beende einen Lauf ohne Leben zu verlieren" },
	{ id = "Coins", type = "Coins", goal = 40, reward = 40, text = "Sammle {goal} Muenzen" },
	{ id = "Grade", type = "Grade", grade = 5, reward = 70, text = "Schaffe eine {grade}" },
	{ id = "Far", type = "Flight", meters = 200, reward = 60, text = "Schleudere etwas {meters} m weit" },
	{ id = "Runs", type = "Finish", goal = 3, reward = 50, text = "Beende {goal} Laeufe" },
}

local function stateWith(ids: { string }): Homework.State
	local tasks = {}
	for _, id in ids do
		table.insert(tasks, { id = id, progress = 0, done = false })
	end
	return { day = 1, tasks = tasks, bonusDone = false }
end

describe("Homework (Hausaufgaben)", function()
	it("Tag wechselt um die Reset-Stunde (UTC)", function()
		local midnight = 20000 * 86400
		expect(Homework.dayIndex(midnight, 0)).toBe(20000)
		expect(Homework.dayIndex(midnight - 1, 0)).toBe(19999)
		expect(Homework.dayIndex(midnight + 3 * 3600, 4)).toBe(19999) -- 3 Uhr, Wechsel erst um 4
		expect(Homework.nextReset(midnight + 10, 0)).toBe(midnight + 86400)
		expect(Homework.nextReset(midnight + 3 * 3600, 4)).toBe(midnight + 4 * 3600)
	end)

	it("waehlt verschiedene Aufgaben, gleich fuer gleichen Tag und Spieler", function()
		local a = Homework.pick(POOL, 3, 100, 42)
		local b = Homework.pick(POOL, 3, 100, 42)
		expect(#a).toBe(3)
		expect(a).toEqual(b)
		expect(a[1].id ~= a[2].id and a[2].id ~= a[3].id and a[1].id ~= a[3].id).toBe(true)
		-- andere Tage ergeben (meist) andere Aufgaben
		local different = false
		for day = 101, 110 do
			local other = Homework.pick(POOL, 3, day, 42)
			if other[1].id ~= a[1].id or other[2].id ~= a[2].id then
				different = true
			end
		end
		expect(different).toBe(true)
	end)

	it("nur verfuegbare Aufgaben, hoechstens so viele wie es gibt", function()
		local picked = Homework.pick(POOL, 10, 5, 1, function(def)
			return def.track == nil
		end)
		expect(#picked).toBe(#POOL - 1)
		for _, task in picked do
			expect(task.id ~= "Fast1").toBe(true)
		end
	end)

	it("Gewicht 0 kommt nie vor", function()
		local pool = { { id = "Never", type = "Coins", reward = 1, text = "", weight = 0 }, POOL[1] }
		for day = 1, 20 do
			local picked = Homework.pick(pool, 1, day, 3)
			expect(picked[1].id).toBe("Cows")
		end
	end)

	it("ensureDay wuerfelt nur bei neuem Tag", function()
		local state = { day = -1, tasks = {}, bonusDone = true }
		expect(Homework.ensureDay(state, 7, POOL, 3, 9)).toBe(true)
		expect(#state.tasks).toBe(3)
		expect(state.bonusDone).toBe(false)
		state.tasks[1].progress = 2
		expect(Homework.ensureDay(state, 7, POOL, 3, 9)).toBe(false)
		expect(state.tasks[1].progress).toBe(2)
	end)

	it("Kuehe zaehlen, andere Objekte nicht", function()
		local state = stateWith({ "Cows" })
		for _ = 1, 4 do
			Homework.report(state, POOL, { type = "Launch", name = "Kuh", meters = 50 })
		end
		Homework.report(state, POOL, { type = "Launch", name = "Muelltonne", meters = 50 })
		expect(state.tasks[1].progress).toBe(4)
		local finished = Homework.report(state, POOL, { type = "Launch", name = "Kuh", meters = 50 })
		expect(#finished).toBe(1)
		expect(state.tasks[1].done).toBe(true)
		-- danach keine zweite Meldung
		expect(#Homework.report(state, POOL, { type = "Launch", name = "Kuh" })).toBe(0)
	end)

	it("Strecke unter Zeit: nur die richtige Strecke und schnell genug", function()
		local state = stateWith({ "Fast1" })
		Homework.report(state, POOL, { type = "Finish", trackId = "Track2", time = 30 })
		Homework.report(state, POOL, { type = "Finish", trackId = "Track1", time = 46 })
		expect(state.tasks[1].done).toBe(false)
		Homework.report(state, POOL, { type = "Finish", trackId = "Track1", time = 44.9 })
		expect(state.tasks[1].done).toBe(true)
	end)

	it("Drift und Muenzen summieren sich, hoechstens bis zum Ziel", function()
		local state = stateWith({ "Drift", "Coins" })
		Homework.report(state, POOL, { type = "Drift", amount = 12.5 })
		Homework.report(state, POOL, { type = "Drift", amount = 30 })
		Homework.report(state, POOL, { type = "Coins", amount = 5 })
		expect(state.tasks[1].progress).toBe(30)
		expect(state.tasks[1].done).toBe(true)
		expect(state.tasks[2].progress).toBe(5)
	end)

	it("ohne Lebensverlust, Note und Flugweite", function()
		local state = stateWith({ "Flawless", "Grade", "Far", "Runs" })
		Homework.report(state, POOL, { type = "Finish", trackId = "Track1", livesLost = 1, grade = 4, time = 60 })
		expect(state.tasks[1].done).toBe(false)
		expect(state.tasks[2].done).toBe(false)
		expect(state.tasks[4].progress).toBe(1)
		Homework.report(state, POOL, { type = "Finish", trackId = "Track1", livesLost = 0, grade = 5, time = 60 })
		expect(state.tasks[1].done).toBe(true)
		expect(state.tasks[2].done).toBe(true)
		Homework.report(state, POOL, { type = "Launch", name = "Kuh", meters = 150 })
		expect(state.tasks[3].done).toBe(false)
		Homework.report(state, POOL, { type = "Launch", name = "Kuh", meters = 250 })
		expect(state.tasks[3].done).toBe(true)
		expect(state.tasks[3].progress).toBe(1)
	end)

	it("Bonus nur einmal, wenn alle erledigt", function()
		local state = stateWith({ "Flawless", "Runs" })
		expect(Homework.takeBonus(state)).toBe(false)
		Homework.report(state, POOL, { type = "Finish", livesLost = 0 })
		Homework.report(state, POOL, { type = "Finish", livesLost = 0 })
		Homework.report(state, POOL, { type = "Finish", livesLost = 0 })
		expect(Homework.takeBonus(state)).toBe(true)
		expect(Homework.takeBonus(state)).toBe(false)
	end)

	it("unbekannte Aufgaben (aus der Config entfernt) stoeren nicht", function()
		local state = stateWith({ "Weg", "Runs" })
		Homework.report(state, POOL, { type = "Finish" })
		expect(state.tasks[1].progress).toBe(0)
		expect(state.tasks[2].progress).toBe(1)
	end)

	it("Texte mit Platzhaltern", function()
		expect(Homework.describe(POOL[1])).toBe("Schleudere 5 Kuehe")
		expect(Homework.describe(POOL[2], function(id)
			return if id == "Track1" then "Der Schulweg" else id
		end)).toBe("Fahre Der Schulweg unter 0:45")
		expect(Homework.describe(POOL[7])).toBe("Schleudere etwas 200 m weit")
	end)
end)
