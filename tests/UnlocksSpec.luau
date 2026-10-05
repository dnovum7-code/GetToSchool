--!strict
local TestLib = require("./TestLib")
local Unlocks = require("../src/shared/Progression/Unlocks")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local tracks = {
	{ id = "Track1", name = "Der Schulweg" },
	{ id = "Track2", name = "Die Abkuerzung", unlock = { track = "Track1", grade = 4, price = 250 } },
	{ id = "Track3", name = "Ueber den Berg", unlock = { track = "Track2", grade = 5 } },
	{ id = "Track4", name = "Geheimweg", unlock = { price = 500 } },
}

local function data(coins: number, grades: { [string]: number }?, unlocked: { [string]: boolean }?)
	return { coins = coins, bestGrades = grades or {}, unlockedTracks = unlocked or {} }
end

local function nameOf(id: string): string
	local def = Unlocks.find(tracks, id)
	return if def then def.name else id
end

describe("Unlocks", function()
	it("ohne Bedingung oder unbekannt: frei", function()
		expect(Unlocks.isUnlocked(tracks[1], data(0))).toBe(true)
		expect(Unlocks.isUnlocked(nil, data(0))).toBe(true)
	end)

	it("Noten-Bedingung: erst ab der verlangten Note", function()
		expect(Unlocks.isUnlocked(tracks[2], data(0, { Track1 = 3 }))).toBe(false)
		expect(Unlocks.isUnlocked(tracks[2], data(0, { Track1 = 4 }))).toBe(true)
		expect(Unlocks.isUnlocked(tracks[2], data(0, { Track1 = 6 }))).toBe(true)
	end)

	it("einmal freigeschaltet bleibt frei", function()
		expect(Unlocks.isUnlocked(tracks[3], data(0, {}, { Track3 = true }))).toBe(true)
	end)

	it("neu freigeschaltete Strecken werden gefunden (nur einmal)", function()
		local d = data(0, { Track1 = 5, Track2 = 5 })
		expect(Unlocks.newlyUnlocked(tracks, d)).toEqual({ "Track2", "Track3" })
		d.unlockedTracks.Track2 = true
		d.unlockedTracks.Track3 = true
		expect(Unlocks.newlyUnlocked(tracks, d)).toEqual({})
	end)

	it("Kauf mit Muenzen", function()
		local d = data(600)
		local ok, reason, price = Unlocks.purchase(tracks[4], d)
		expect(ok).toBe(true)
		expect(reason).toBe("Ok")
		expect(price).toBe(500)
		expect(d.coins).toBe(100)
		expect(d.unlockedTracks.Track4).toBe(true)
	end)

	it("Kauf: zu wenig Muenzen, nicht kaeuflich, schon frei", function()
		local poor = data(100)
		expect((Unlocks.purchase(tracks[4], poor))).toBe(false)
		expect(poor.coins).toBe(100)
		local _, reason = Unlocks.purchase(tracks[3], data(9999))
		expect(reason).toBe("NotForSale")
		local _, already = Unlocks.purchase(tracks[2], data(9999, { Track1 = 6 }))
		expect(already).toBe("AlreadyUnlocked")
	end)

	it("Beschreibung fuer das Menue", function()
		expect(Unlocks.describe(tracks[2], nameOf)).toBe("Note 4 auf Der Schulweg oder 250 Muenzen")
		expect(Unlocks.describe(tracks[4], nameOf)).toBe("500 Muenzen")
		expect(Unlocks.describe(tracks[1], nameOf)).toBeNil()
	end)
end)

return nil
