--!strict
local TestLib = require("./TestLib")
local Cosmetics = require("../src/shared/Progression/Cosmetics")
local SaveData = require("../src/shared/Progression/SaveData")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local COLORS = {
	{ id = "Standard", name = "Standard", price = 0 },
	{ id = "Red", name = "Rot", price = 0 },
	{ id = "Gold", name = "Gold", price = 500 },
}
local TRAILS = {
	{ id = "Sparkle", name = "Glitzer", price = 300 },
	{ id = "Free", name = "Gratis", price = 0 },
}

describe("Cosmetics (Farben und Spuren)", function()
	it("kostenlos oder gekauft", function()
		expect(Cosmetics.isOwned(COLORS[2], {})).toBe(true)
		expect(Cosmetics.isOwned(COLORS[3], {})).toBe(false)
		expect(Cosmetics.isOwned(COLORS[3], { Gold = true })).toBe(true)
	end)

	it("Farbe pro Fahrzeug, sonst Standard", function()
		local chosen = { OfficeChair = "Red", SchoolDesk = "Gold", ShoppingCart = "Weg" }
		local chair = Cosmetics.colorFor(COLORS, {}, chosen, "OfficeChair")
		expect(chair and chair.id).toBe("Red")
		local desk = Cosmetics.colorFor(COLORS, {}, chosen, "SchoolDesk")
		expect(desk and desk.id).toBe("Standard") -- Gold nicht gekauft
		desk = Cosmetics.colorFor(COLORS, { Gold = true }, chosen, "SchoolDesk")
		expect(desk and desk.id).toBe("Gold")
		local cart = Cosmetics.colorFor(COLORS, {}, chosen, "ShoppingCart")
		expect(cart and cart.id).toBe("Standard")
	end)

	it("Spur nur wenn gekauft", function()
		expect(Cosmetics.trailFor(TRAILS, {}, "")).toBeNil()
		expect(Cosmetics.trailFor(TRAILS, {}, "Sparkle")).toBeNil()
		local trail = Cosmetics.trailFor(TRAILS, { Sparkle = true }, "Sparkle")
		expect(trail and trail.id).toBe("Sparkle")
		local free = Cosmetics.trailFor(TRAILS, {}, "Free")
		expect(free and free.id).toBe("Free")
	end)

	it("Spielstand: bereinigt und zusammengefuehrt", function()
		local data = SaveData.migrate({
			version = 2,
			cosmetics = { colors = { Gold = true, X = "ja" }, vehicleColors = { OfficeChair = "Red", Bad = 5 }, trail = 7 },
		})
		assert(data)
		expect(data.cosmetics.colors.Gold).toBe(true)
		expect(data.cosmetics.colors.X).toBeNil()
		expect(data.cosmetics.vehicleColors.OfficeChair).toBe("Red")
		expect(data.cosmetics.vehicleColors.Bad).toBeNil()
		expect(data.cosmetics.trail).toBe("")

		local stored = SaveData.new()
		stored.cosmetics.trails.Sparkle = true
		stored.cosmetics.trail = "Sparkle"
		local session = SaveData.new()
		session.cosmetics.colors.Gold = true
		session.cosmetics.vehicleColors.ShoppingCart = "Gold"
		local merged = SaveData.merge(stored, session)
		expect(merged.cosmetics.trails.Sparkle).toBe(true)
		expect(merged.cosmetics.colors.Gold).toBe(true)
		expect(merged.cosmetics.trail).toBe("Sparkle")
		expect(merged.cosmetics.vehicleColors.ShoppingCart).toBe("Gold")
	end)
end)
