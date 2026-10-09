--!strict
local TestLib = require("./TestLib")
local ObjectPhysicsMath = require("../src/shared/Toolkit/ObjectPhysicsMath")
local SpawnedHit = require("../src/shared/Toolkit/SpawnedHit")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local PARAMS: SpawnedHit.Params = { interval = 3, intervalRandom = 1, burst = 2, lifetime = 12, slack = 3 }

describe("SpawnedHit (gespawnte Launchables pruefen)", function()
	it("Nummer aus Ausloesung und Platz", function()
		expect(SpawnedHit.index(10, 1)).toBe(641)
		expect(SpawnedHit.index(SpawnedHit.SIGNAL_BASE + 2, 1) // SpawnedHit.PER_EVENT).toBe(SpawnedHit.SIGNAL_BASE + 2)
	end)

	it("passende Nummer im Zeitfenster", function()
		-- Ausloesung 100 bei 300 s (+ bis 1 s), jetzt 305 s
		expect((SpawnedHit.checkIndex(SpawnedHit.index(100, 1), 305, PARAMS))).toBe(true)
		expect((SpawnedHit.checkIndex(SpawnedHit.index(100, 2), 305, PARAMS))).toBe(true)
	end)

	it("ungueltige Nummern", function()
		expect((SpawnedHit.checkIndex("12", 305, PARAMS))).toBe(false)
		expect((SpawnedHit.checkIndex(-1, 305, PARAMS))).toBe(false)
		expect((SpawnedHit.checkIndex(6400.5, 305, PARAMS))).toBe(false)
		expect((SpawnedHit.checkIndex(0 / 0, 305, PARAMS))).toBe(false)
		-- Platz 0 und Platz groesser als Burst
		expect((SpawnedHit.checkIndex(SpawnedHit.index(100, 0), 305, PARAMS))).toBe(false)
		expect((SpawnedHit.checkIndex(SpawnedHit.index(100, 3), 305, PARAMS))).toBe(false)
	end)

	it("Ausloesung in der Zukunft oder laengst verschwunden", function()
		-- Ausloesung 200 waere bei 600 s
		local ok, reason = SpawnedHit.checkIndex(SpawnedHit.index(200, 1), 305, PARAMS)
		expect(ok).toBe(false)
		expect(reason ~= nil).toBe(true)
		-- Ausloesung 10 bei 30 s: verschwunden spaetestens 31 + 12 (+3 Spielraum)
		expect((SpawnedHit.checkIndex(SpawnedHit.index(10, 1), 45, PARAMS))).toBe(true)
		expect((SpawnedHit.checkIndex(SpawnedHit.index(10, 1), 47, PARAMS))).toBe(false)
	end)

	it("Signal-Ausloesungen gehen immer (nur Rate begrenzt)", function()
		expect((SpawnedHit.checkIndex(SpawnedHit.index(SpawnedHit.SIGNAL_BASE + 5, 1), 305, PARAMS))).toBe(true)
	end)

	it("Ratenbegrenzung pro Minute", function()
		local times = {}
		expect(SpawnedHit.allowRate(times, 0, 2)).toBe(true)
		expect(SpawnedHit.allowRate(times, 1, 2)).toBe(true)
		expect(SpawnedHit.allowRate(times, 2, 2)).toBe(false)
		expect(SpawnedHit.allowRate(times, 61.5, 2)).toBe(true) -- der erste ist abgelaufen
	end)
end)

describe("ObjectPhysicsMath (LowGravity, NoFriction, KeepUpright)", function()
	it("Gegenkraft fuer weniger Schwerkraft", function()
		expect(ObjectPhysicsMath.antiGravity(10, 196.2, 1)).toBe(0)
		expect(ObjectPhysicsMath.antiGravity(10, 200, 0.25)).toBe(1500)
		expect(ObjectPhysicsMath.antiGravity(10, 200, -1)).toBe(2000) -- begrenzt auf 0..1
	end)

	it("Aufricht-Kraft waechst mit Gewicht, Groesse und Staerke", function()
		expect(ObjectPhysicsMath.uprightTorque(2, 100, 3, 2)).toBe(1200)
		expect(ObjectPhysicsMath.uprightTorque(2, 100, 0.1, 1)).toBe(100) -- Mindestgroesse 0.5
		expect(ObjectPhysicsMath.uprightTorque(2, 100, 3, -1)).toBe(0)
	end)

	it("dreht es sich schnell (Flip), ist die Kraft aus", function()
		expect(ObjectPhysicsMath.uprightActive(2, 6)).toBe(true)
		expect(ObjectPhysicsMath.uprightActive(8, 6)).toBe(false)
		expect(ObjectPhysicsMath.uprightActive(50, 0)).toBe(true) -- 0 = immer an
	end)

	it("NoFriction: unsere Reibung zaehlt fast allein", function()
		local mixed = ObjectPhysicsMath.mixedFriction(0, ObjectPhysicsMath.NO_FRICTION_WEIGHT, 0.5, 1)
		expect(mixed < 0.01).toBe(true)
	end)
end)

return nil
