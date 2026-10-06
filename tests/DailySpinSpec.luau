--!strict
local TestLib = require("./TestLib")
local DailySpin = require("../src/shared/Progression/DailySpin")
local SaveData = require("../src/shared/Progression/SaveData")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local SEGMENTS: { DailySpin.Segment } = {
	{ id = "C20", text = "20", kind = "Coins", amount = 20, weight = 3 },
	{ id = "Life", text = "Leben", kind = "Item", item = "ExtraLife", amount = 1, weight = 1 },
	{ id = "Never", text = "-", kind = "Coins", amount = 999, weight = 0 },
}

describe("DailySpin (Gluecksrad)", function()
	it("einmal pro Tag", function()
		expect(DailySpin.canSpin(-1, 100)).toBe(true)
		expect(DailySpin.canSpin(100, 100)).toBe(false)
		expect(DailySpin.canSpin(99, 100)).toBe(true)
	end)

	it("Gewichte bestimmen das Feld", function()
		expect(DailySpin.pick(SEGMENTS, 0)).toBe(1)
		expect(DailySpin.pick(SEGMENTS, 0.74)).toBe(1)
		expect(DailySpin.pick(SEGMENTS, 0.76)).toBe(2)
		expect(DailySpin.pick(SEGMENTS, 1)).toBe(2) -- Gewicht 0 kommt nie
	end)

	it("Muenzen und Items gutschreiben, nur einmal", function()
		local data = { coins = 5, spinDay = -1, items = {} }
		expect(DailySpin.apply(data, SEGMENTS[1], 50, 9)).toBe(true)
		expect(data.coins).toBe(25)
		expect(data.spinDay).toBe(50)
		expect(DailySpin.apply(data, SEGMENTS[2], 50, 9)).toBe(false)
		expect(data.items.ExtraLife).toBeNil()
		expect(DailySpin.apply(data, SEGMENTS[2], 51, 9)).toBe(true)
		expect(data.items.ExtraLife).toBe(1)
	end)

	it("Items begrenzt", function()
		local data = { coins = 0, spinDay = -1, items = { ExtraLife = 9 } }
		DailySpin.apply(data, SEGMENTS[2], 1, 9)
		expect(data.items.ExtraLife).toBe(9)
	end)

	it("pro Lauf eins verbrauchen", function()
		local items = { ExtraLife = 2, StartBoost = 1, Unknown = 3 }
		local used = DailySpin.consumeForRun(items, { "ExtraLife", "ExtraShield", "StartBoost" })
		expect(used).toEqual({ "ExtraLife", "StartBoost" })
		expect(items.ExtraLife).toBe(1)
		expect(items.StartBoost).toBeNil()
		expect(items.Unknown).toBe(3)
	end)

	it("Spielstand: Tag und Items", function()
		local data = SaveData.migrate({ version = 2, spinDay = 77, items = { ExtraLife = 2, Bad = "x", Big = 500 } })
		assert(data)
		expect(data.spinDay).toBe(77)
		expect(data.items.ExtraLife).toBe(2)
		expect(data.items.Bad).toBeNil()
		expect(data.items.Big).toBe(99)
		local session = SaveData.new()
		session.spinDay = 78
		session.items.ExtraLife = 1
		local merged = SaveData.merge(data, session)
		expect(merged.spinDay).toBe(78)
		expect(merged.items.ExtraLife).toBe(3)
	end)
end)
