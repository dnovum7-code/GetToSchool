--!strict
local TestLib = require("./TestLib")
local HornRules = require("../src/shared/Progression/HornRules")
local SaveData = require("../src/shared/Progression/SaveData")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local HORNS: { HornRules.HornDef } = {
	{ id = "Squeak", name = "Quietsch", sound = "HornSqueak", price = 0 },
	{ id = "Bike", name = "Troete", sound = "HornBike", price = 150 },
	{ id = "Train", name = "Zug", sound = "HornTrain", price = 500 },
}

describe("HornRules (Hupe)", function()
	it("Abklingzeit", function()
		expect(HornRules.ready(nil, 10, 1.5)).toBe(true)
		expect(HornRules.ready(9, 10, 1.5)).toBe(false)
		expect(HornRules.ready(8.5, 10, 1.5)).toBe(true)
	end)

	it("kostenlose Hupe gehoert jedem, andere erst nach dem Kauf", function()
		expect(HornRules.isOwned(HORNS[1], {})).toBe(true)
		expect(HornRules.isOwned(HORNS[2], {})).toBe(false)
		expect(HornRules.isOwned(HORNS[2], { Bike = true })).toBe(true)
	end)

	it("gewaehlte Hupe nur, wenn gekauft; sonst Standard", function()
		local selected = HornRules.selected(HORNS, {}, "Train", "Squeak")
		expect(selected and selected.id).toBe("Squeak")
		selected = HornRules.selected(HORNS, { Train = true }, "Train", "Squeak")
		expect(selected and selected.id).toBe("Train")
		selected = HornRules.selected(HORNS, {}, "Gibtsnicht", "AuchNicht")
		expect(selected and selected.id).toBe("Squeak") -- erste kostenlose
	end)

	it("Spielstand: Hupen und Einstellung werden bereinigt und zusammengefuehrt", function()
		local data = SaveData.migrate({
			version = 4,
			cosmetics = { horns = { Bike = true, Bad = 3 }, horn = "Bike" },
			settings = { MuteHorns = true },
		})
		assert(data)
		expect(data.cosmetics.horns.Bike).toBe(true)
		expect(data.cosmetics.horns.Bad).toBeNil()
		expect(data.cosmetics.horn).toBe("Bike")
		expect(data.settings.MuteHorns).toBe(true)
		local fresh = SaveData.new()
		expect(fresh.settings.MuteHorns).toBe(false)
		expect(fresh.cosmetics.horn).toBe("")
		local session = SaveData.new()
		session.cosmetics.horns.Train = true
		local merged = SaveData.merge(data, session)
		expect(merged.cosmetics.horns.Bike).toBe(true)
		expect(merged.cosmetics.horns.Train).toBe(true)
		expect(merged.cosmetics.horn).toBe("Bike")
	end)
end)

return nil
