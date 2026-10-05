--!strict
local TestLib = require("./TestLib")
local ChaserLogic = require("../src/shared/Toolkit/ChaserLogic")
local PathMath = require("../src/shared/Toolkit/PathMath")
local Rng = require("../src/shared/Toolkit/Rng")
local SpawnSchedule = require("../src/shared/Toolkit/SpawnSchedule")
local TriggerRules = require("../src/shared/Toolkit/TriggerRules")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

describe("Rng (reproduzierbarer Zufall)", function()
	it("gleiche Eingabe gibt gleiche Zahl", function()
		expect(Rng.at(42, 7, 1)).toBe(Rng.at(42, 7, 1))
	end)
	it("andere Eingabe gibt andere Zahl", function()
		expect(Rng.at(42, 7, 1) ~= Rng.at(42, 8, 1)).toBe(true)
		expect(Rng.at(42, 7, 1) ~= Rng.at(42, 7, 2)).toBe(true)
		expect(Rng.at(42, 7, 1) ~= Rng.at(43, 7, 1)).toBe(true)
	end)
	it("Werte liegen zwischen 0 und 1 und sind gut verteilt", function()
		local sum, low, high = 0, 0, 0
		for i = 1, 2000 do
			local r = Rng.at(1234, i, 3)
			assert(r >= 0 and r < 1, "ausserhalb 0..1")
			sum += r
			if r < 0.5 then
				low += 1
			else
				high += 1
			end
		end
		expect(sum / 2000).toBeNear(0.5, 0.05)
		expect(math.abs(low - high)).toBeLessThan(200)
	end)
	it("grosse Indizes (Serverzeit) funktionieren", function()
		local r = Rng.at(5, 900000000, 1)
		expect(r >= 0 and r < 1).toBe(true)
	end)
	it("range und seedFromString", function()
		local v = Rng.range(1, 2, 3, 10, 20)
		expect(v >= 10 and v < 20).toBe(true)
		expect(Rng.seedFromString("Spawner1")).toBe(Rng.seedFromString("Spawner1"))
		expect(Rng.seedFromString("Spawner1") ~= Rng.seedFromString("Spawner2")).toBe(true)
	end)
end)

describe("TriggerRules", function()
	it("loest nur beim Hineinfahren aus, nicht solange man drin ist", function()
		local state = TriggerRules.new()
		expect(TriggerRules.update(state, false, 0, false, 0)).toBe(false)
		expect(TriggerRules.update(state, true, 1, false, 0)).toBe(true)
		expect(TriggerRules.update(state, true, 2, false, 0)).toBe(false)
		expect(TriggerRules.update(state, false, 3, false, 0)).toBe(false)
		expect(TriggerRules.update(state, true, 4, false, 0)).toBe(true)
	end)
	it("Once: nur einmal pro Lauf, nach rearm wieder", function()
		local state = TriggerRules.new()
		expect(TriggerRules.update(state, true, 1, true, 0)).toBe(true)
		TriggerRules.update(state, false, 2, true, 0)
		expect(TriggerRules.update(state, true, 3, true, 0)).toBe(false)
		TriggerRules.rearm(state)
		expect(TriggerRules.update(state, true, 4, true, 0)).toBe(true)
	end)
	it("Cooldown: zu schnelles Wiederholen zaehlt nicht", function()
		local state = TriggerRules.new()
		expect(TriggerRules.update(state, true, 10, false, 2)).toBe(true)
		TriggerRules.update(state, false, 10.5, false, 2)
		expect(TriggerRules.update(state, true, 11, false, 2)).toBe(false)
		TriggerRules.update(state, false, 11.5, false, 2)
		expect(TriggerRules.update(state, true, 12.5, false, 2)).toBe(true)
	end)
	it("rearm: Wagen steht nach dem Neustart draussen", function()
		local state = TriggerRules.new()
		TriggerRules.update(state, true, 1, false, 0)
		TriggerRules.rearm(state)
		expect(state.inside).toBe(false)
	end)
end)

describe("SpawnSchedule", function()
	local function random(k: number): number
		return Rng.at(99, k, 1)
	end

	it("Ereignisse kommen im Abstand Interval (ohne Zufall exakt)", function()
		local noRandom = function(_k: number): number
			return 0.5
		end
		local due, lastK = SpawnSchedule.due(SpawnSchedule.startIndex(10, 2), 10, 2, 0, noRandom)
		expect(due).toEqual({ 5 })
		expect(lastK).toBe(5)
		local later, lastK2 = SpawnSchedule.due(lastK, 15.9, 2, 0, noRandom)
		expect(later).toEqual({ 6, 7 })
		expect(lastK2).toBe(7)
	end)

	it("Zufallsversatz bleibt im Intervall, Reihenfolge stimmt", function()
		local previous = -math.huge
		for k = 1, 200 do
			local t = SpawnSchedule.timeOf(k, 3, 10, random)
			expect(t >= k * 3).toBe(true)
			expect(t < (k + 1) * 3).toBe(true)
			expect(t > previous).toBe(true)
			previous = t
		end
	end)

	it("zwei Clients berechnen denselben Plan", function()
		local a = SpawnSchedule.due(100, 260, 3, 1, random)
		local b = SpawnSchedule.due(100, 260, 3, 1, random)
		expect(a).toEqual(b)
	end)

	it("kein riesiger Rueckstand nach langer Pause", function()
		local due = SpawnSchedule.due(0, 100000, 1, 0, random)
		expect(#due <= 51).toBe(true)
	end)

	it("maxCount begrenzt", function()
		local due = SpawnSchedule.due(0, 100, 1, 0, random, 3)
		expect(#due).toBe(3)
	end)

	it("Namensliste und Auswahl", function()
		local names = SpawnSchedule.splitNames(" Stein1, Stein2 ,,Auto ")
		expect(names).toEqual({ "Stein1", "Stein2", "Auto" })
		expect(SpawnSchedule.pick(names, 0)).toBe("Stein1")
		expect(SpawnSchedule.pick(names, 0.999)).toBe("Auto")
		expect(SpawnSchedule.pick({}, 0.5)).toBeNil()
	end)
end)

describe("PathMath", function()
	-- drei Punkte auf einer Linie: 0, 10, 30 (Abstaende 10 und 20)
	local positions = { 0, 10, 30 }
	local function distance(a: number, b: number): number
		return math.abs(positions[b] - positions[a])
	end

	it("hin und zurueck: Zyklus und Abschnitte", function()
		local path = PathMath.build(3, distance, 10, 0, false)
		expect(#path.legs).toBe(4)
		expect(path.cycle).toBeNear(6) -- (10 + 20) * 2 / 10
		local from, to, alpha, moving = PathMath.sample(path, 0.5)
		expect(from).toBe(1)
		expect(to).toBe(2)
		expect(alpha).toBeNear(0.5)
		expect(moving).toBe(true)
		from, to = PathMath.sample(path, 3.5)
		expect(from).toBe(3)
		expect(to).toBe(2)
	end)

	it("Kreis: letzter Abschnitt fuehrt zum ersten Punkt", function()
		local path = PathMath.build(3, distance, 10, 0, true)
		expect(#path.legs).toBe(3)
		local last = path.legs[3]
		expect(last.from).toBe(3)
		expect(last.to).toBe(1)
		expect(path.cycle).toBeNear(6) -- 10 + 20 + 30 = 60 / 10
	end)

	it("Wartezeit an den Punkten", function()
		local path = PathMath.build(3, distance, 10, 2, false)
		expect(path.cycle).toBeNear(6 + 4 * 2)
		local _, to, alpha, moving = PathMath.sample(path, 1.5)
		expect(to).toBe(2)
		expect(alpha).toBe(1)
		expect(moving).toBe(false)
	end)

	it("Zeit laeuft im Kreis (Serverzeit gross)", function()
		local path = PathMath.build(3, distance, 10, 0, false)
		local a1, b1, c1 = PathMath.sample(path, 0.5)
		local a2, b2, c2 = PathMath.sample(path, 0.5 + path.cycle * 1000)
		expect(a1).toBe(a2)
		expect(b1).toBe(b2)
		expect(c1).toBeNear(c2, 1e-6)
	end)

	it("Tor im Takt: zu, oeffnet, offen, schliesst", function()
		expect(PathMath.gateTimer(1, 2, 3, 3)).toBe(0)
		expect(PathMath.gateTimer(4, 2, 3, 3)).toBeNear(0.5)
		expect(PathMath.gateTimer(6, 2, 3, 3)).toBe(1)
		expect(PathMath.gateTimer(9, 2, 3, 3)).toBeNear(0.5)
		expect(PathMath.gateTimer(10 + 0.5, 2, 3, 3)).toBe(0)
	end)

	it("Tor per Signal", function()
		expect(PathMath.gateSignal(nil, 2, 0)).toBe(0)
		expect(PathMath.gateSignal(1, 2, 0)).toBeNear(0.5)
		expect(PathMath.gateSignal(100, 2, 0)).toBe(1)
		expect(PathMath.gateSignal(3, 2, 5)).toBe(1)
		expect(PathMath.gateSignal(8, 2, 5)).toBeNear(0.5)
		expect(PathMath.gateSignal(20, 2, 5)).toBe(0)
	end)
end)

describe("ChaserLogic (Hund)", function()
	local settings = {
		radius = 40,
		maxSpeed = 30,
		acceleration = 60,
		giveUpTime = 5,
		returnSpeed = 15,
		cooldown = 3,
	}

	it("startet erst, wenn der Wagen im Radius ist", function()
		local state = ChaserLogic.new()
		ChaserLogic.step(state, 0.1, 100, 0, false, settings)
		expect(state.mode).toBe("Idle")
		ChaserLogic.step(state, 0.1, 30, 0, false, settings)
		expect(state.mode).toBe("Chase")
	end)

	it("Signal startet auch ausserhalb des Radius, aber nicht ohne Wagen", function()
		local state = ChaserLogic.new()
		ChaserLogic.step(state, 0.1, nil, 0, true, settings)
		expect(state.mode).toBe("Idle")
		ChaserLogic.step(state, 0.1, 500, 0, true, settings)
		expect(state.mode).toBe("Chase")
	end)

	it("wird bis MaxSpeed schneller und gibt nach GiveUpTime auf", function()
		local state = ChaserLogic.new()
		ChaserLogic.step(state, 0.1, 10, 0, false, settings)
		local speed = 0
		for _ = 1, 10 do
			speed = ChaserLogic.step(state, 0.1, 10, 5, false, settings)
		end
		expect(speed).toBe(30)
		for _ = 1, 50 do
			ChaserLogic.step(state, 0.1, 10, 5, false, settings)
		end
		expect(state.mode).toBe("Return")
	end)

	it("zu Hause angekommen: Pause, dann wieder bereit", function()
		local state = ChaserLogic.new()
		state.mode = "Return"
		local speed = ChaserLogic.step(state, 0.1, 10, 20, false, settings)
		expect(speed).toBe(15)
		ChaserLogic.step(state, 0.1, 10, 0.5, false, settings)
		expect(state.mode).toBe("Idle")
		ChaserLogic.step(state, 1, 10, 0, false, settings)
		expect(state.mode).toBe("Idle") -- Pause laeuft noch
		ChaserLogic.step(state, 2.5, 10, 0, false, settings)
		expect(state.mode).toBe("Chase")
	end)

	it("Wagen weg (Crash): zurueck nach Hause", function()
		local state = ChaserLogic.new()
		ChaserLogic.step(state, 0.1, 10, 0, false, settings)
		ChaserLogic.step(state, 0.1, nil, 3, false, settings)
		expect(state.mode).toBe("Return")
	end)
end)

return nil
