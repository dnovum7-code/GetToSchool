--!strict
local TestLib = require("./TestLib")
local SaveData = require("../src/shared/Progression/SaveData")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

describe("SaveData", function()
	it("neuer Spielstand hat aktuelle Version und Einkaufswagen", function()
		local data = SaveData.new()
		expect(data.version).toBe(SaveData.VERSION)
		expect(data.coins).toBe(0)
		expect(data.vehicles.ShoppingCart).toBe(true)
	end)

	it("nil laedt als neuer Spielstand", function()
		local data, note = SaveData.migrate(nil)
		expect(note).toBe("new")
		expect(data and data.coins).toBe(0)
	end)

	it("altes Format (Version 0, nur Bestzeiten) wird migriert", function()
		local old = {
			Track1 = { time = 61.5, splits = { ["Workspace.CP1"] = 20.25 } },
			Kaputt = { time = "schnell" },
		}
		local data, note = SaveData.migrate(old)
		expect(note).toBe("migrated")
		assert(data)
		expect(data.version).toBe(SaveData.VERSION)
		expect(data.bestTimes.Track1.time).toBe(61.5)
		expect(data.bestTimes.Track1.splits["Workspace.CP1"]).toBe(20.25)
		expect(data.bestTimes.Kaputt).toBeNil()
		expect(data.coins).toBe(0)
	end)

	it("Spielstand einer neueren Version wird nicht angefasst", function()
		local data, note = SaveData.migrate({ version = SaveData.VERSION + 1, coins = 5 })
		expect(data).toBeNil()
		expect(note).toBe("newer")
	end)

	it("kaputte Werte werden bereinigt", function()
		local data = SaveData.migrate({
			version = 1,
			coins = -20,
			upgrades = { Turbo = 2.7, Helmet = "drei", [5] = 1 },
			bestGrades = { Track1 = 9 },
			unlockedTracks = { Track2 = true, Track3 = "ja" },
			launchRecords = { Kuh = 412.5, Zwerg = 0 / 0 },
		})
		assert(data)
		expect(data.coins).toBe(0)
		expect(data.upgrades.Turbo).toBe(2)
		expect(data.upgrades.Helmet).toBeNil()
		expect(data.bestGrades.Track1).toBe(6)
		expect(data.unlockedTracks.Track2).toBe(true)
		expect(data.unlockedTracks.Track3).toBeNil()
		expect(data.launchRecords.Kuh).toBe(412.5)
		expect(data.launchRecords.Zwerg).toBeNil()
	end)

	it("kein Tabellen-Spielstand wird als neu behandelt", function()
		local data, note = SaveData.migrate("Unsinn")
		expect(note).toBe("invalid")
		expect(data and data.coins).toBe(0)
	end)

	it("merge addiert Muenzen und behaelt jeweils das Bessere", function()
		local stored = SaveData.new()
		stored.coins = 100
		stored.upgrades.Turbo = 2
		stored.bestTimes.Track1 = { time = 70, splits = {} }
		stored.launchRecords.Kuh = 300
		local session = SaveData.new()
		session.coins = 7
		session.upgrades.Turbo = 1
		session.bestTimes.Track1 = { time = 65, splits = { a = 1 } }
		session.launchRecords.Kuh = 200
		session.unlockedTracks.Track2 = true
		session.stats.finishedRuns = 1
		local merged = SaveData.merge(stored, session)
		expect(merged.coins).toBe(107)
		expect(merged.upgrades.Turbo).toBe(2)
		expect(merged.bestTimes.Track1.time).toBe(65)
		expect(merged.launchRecords.Kuh).toBe(300)
		expect(merged.unlockedTracks.Track2).toBe(true)
		expect(merged.stats.finishedRuns).toBe(1)
	end)

	it("Version 1 wird auf Version 2 hochgestuft (Hausaufgaben leer)", function()
		local data, note = SaveData.migrate({ version = 1, coins = 12 })
		expect(note).toBe("migrated")
		assert(data)
		expect(data.version).toBe(2)
		expect(data.coins).toBe(12)
		expect(data.homework.day).toBe(-1)
		expect(#data.homework.tasks).toBe(0)
	end)

	it("Hausaufgaben werden bereinigt", function()
		local data = SaveData.migrate({
			version = 2,
			homework = {
				day = 20000,
				tasks = { { id = "A", progress = 3, done = false }, { id = 5 }, { id = "B", progress = -2, done = true } },
				bonusDone = "ja",
			},
		})
		assert(data)
		expect(data.homework.day).toBe(20000)
		expect(#data.homework.tasks).toBe(2)
		expect(data.homework.tasks[2].progress).toBe(0)
		expect(data.homework.tasks[2].done).toBe(true)
		expect(data.homework.bonusDone).toBe(false)
	end)

	it("merge: Hausaufgaben vom neueren Tag, sonst groesserer Fortschritt", function()
		local stored = SaveData.new()
		stored.homework = { day = 10, tasks = { { id = "A", progress = 2, done = false } }, bonusDone = false }
		local session = SaveData.new()
		session.homework = { day = 10, tasks = { { id = "A", progress = 4, done = true } }, bonusDone = false }
		local merged = SaveData.merge(stored, session)
		expect(merged.homework.tasks[1].progress).toBe(4)
		expect(merged.homework.tasks[1].done).toBe(true)
		session.homework = { day = 11, tasks = { { id = "B", progress = 1, done = false } }, bonusDone = false }
		merged = SaveData.merge(stored, session)
		expect(merged.homework.day).toBe(11)
		expect(merged.homework.tasks[1].id).toBe("B")
		session.homework = SaveData.newHomework() -- beim Laden noch nichts
		merged = SaveData.merge(stored, session)
		expect(merged.homework.day).toBe(10)
	end)

	it("serialize -> migrate ergibt dieselben Daten", function()
		local data = SaveData.new()
		data.coins = 42
		data.upgrades.Glider = 1
		data.bestTimes.Track1 = { time = 59.99, splits = { cp = 12 } }
		data.bestGrades.Track1 = 6
		local loaded = SaveData.migrate(SaveData.serialize(data))
		expect(loaded).toEqual(data)
	end)
end)

describe("SaveData.withRetry", function()
	it("versucht es nach Fehlern erneut, mit wachsender Wartezeit", function()
		local calls = 0
		local waits = {}
		local ok, result, tries = SaveData.withRetry(
			function()
				calls += 1
				if calls < 3 then
					error("Netzwerkfehler")
				end
				return "Daten"
			end,
			5,
			1,
			function(seconds)
				table.insert(waits, seconds)
			end
		)
		expect(ok).toBe(true)
		expect(result).toBe("Daten")
		expect(tries).toBe(3)
		expect(waits).toEqual({ 1, 2 })
	end)

	it("gibt nach allen Versuchen auf und meldet den Fehler", function()
		local ok, err, tries = SaveData.withRetry(function()
			error("immer kaputt")
		end, 3, 0.5, function() end)
		expect(ok).toBe(false)
		expect(tries).toBe(3)
		expect(string.find(tostring(err), "immer kaputt", 1, true) ~= nil).toBe(true)
	end)

	it("bricht bei Zugriffsfehlern sofort ab", function()
		local calls = 0
		local ok, _, tries = SaveData.withRetry(function()
			calls += 1
			error("403: Cannot write to DataStore from studio if API access is not enabled.")
		end, 5, 1, function() end, SaveData.isAccessError)
		expect(ok).toBe(false)
		expect(tries).toBe(1)
		expect(calls).toBe(1)
	end)

	it("erkennt Zugriffsfehler, aber nicht normale Fehler", function()
		expect(SaveData.isAccessError("StudioAccessToApisNotAllowed")).toBe(true)
		expect(SaveData.isAccessError("502: API Services rejected request with error. HTTP 403 (Forbidden)")).toBe(
			true
		)
		expect(SaveData.isAccessError("You must publish this place to the web to access DataStore.")).toBe(
			true
		)
		expect(SaveData.isAccessError("502: API Services rejected request with error. HTTP 500")).toBe(false)
		expect(SaveData.isAccessError("Request was throttled")).toBe(false)
	end)
end)

describe("SaveData: Sitzungs-Sperre", function()
	local timeout = 150
	it("ohne Datensatz oder ohne Sperre: frei", function()
		expect(SaveData.lockState(nil, "A", 1000, timeout)).toBe("Free")
		expect(SaveData.lockState({ version = 1, coins = 5 }, "A", 1000, timeout)).toBe("Free")
	end)

	it("eigene Sperre", function()
		local record = SaveData.withSession({ version = 1 }, "A", 1000)
		expect(SaveData.lockState(record, "A", 1010, timeout)).toBe("Ours")
	end)

	it("frische fremde Sperre: gesperrt, abgelaufene: frei", function()
		local record = SaveData.withSession({ version = 1 }, "B", 1000)
		expect(SaveData.lockState(record, "A", 1100, timeout)).toBe("Locked")
		expect(SaveData.lockState(record, "A", 1000 + timeout, timeout)).toBe("Free")
	end)

	it("neuere Spielversion wird nicht angefasst", function()
		expect(SaveData.lockState({ version = SaveData.VERSION + 1 }, "A", 0, timeout)).toBe("Newer")
	end)

	it("Sperre freigeben", function()
		local locked = SaveData.withSession({ version = 1, coins = 3 }, "A", 1000)
		local released = SaveData.withSession(locked, nil, 1001)
		expect(released.session).toBeNil()
		expect(released.coins).toBe(3)
		expect(locked.session.id).toBe("A") -- Original bleibt unveraendert
	end)

	it("Sperre stoert das Laden nicht", function()
		local record = SaveData.withSession(SaveData.serialize(SaveData.new()), "A", 1000)
		record.coins = 9
		local data, note = SaveData.migrate(record)
		expect(note).toBe("ok")
		expect(data and data.coins).toBe(9)
	end)
end)

return nil
