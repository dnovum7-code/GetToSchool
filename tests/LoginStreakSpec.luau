--!strict
local TestLib = require("./TestLib")
local Cosmetics = require("../src/shared/Progression/Cosmetics")
local LoginStreak = require("../src/shared/Progression/LoginStreak")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

describe("LoginStreak (7-Tage-Serie)", function()
	it("erster Login: Tag 1", function()
		local state = { lastDay = -1, streak = 0 }
		local canClaim, day = LoginStreak.status(state, 100)
		expect(canClaim).toBe(true)
		expect(day).toBe(1)
		expect(LoginStreak.claim(state, 100)).toBe(1)
		expect(LoginStreak.claim(state, 100)).toBeNil() -- nur einmal pro Tag
		local again, today = LoginStreak.status(state, 100)
		expect(again).toBe(false)
		expect(today).toBe(1)
	end)

	it("jeden Tag: Serie steigt, nach Tag 7 wieder Tag 1", function()
		local state = { lastDay = -1, streak = 0 }
		for day = 1, 7 do
			expect(LoginStreak.claim(state, 200 + day)).toBe(day)
		end
		expect(LoginStreak.claim(state, 208)).toBe(1)
	end)

	it("verpasster Tag: zurueck auf Tag 1", function()
		local state = { lastDay = 300, streak = 4 }
		expect(LoginStreak.claim(state, 302)).toBe(1)
	end)

	it("Texte", function()
		expect(LoginStreak.describe({ kind = "Coins", amount = 25 })).toBe("25 Muenzen")
		expect(LoginStreak.describe({ kind = "MeterBoost", runs = 3 })).toBe("x2 Meter (3 Laeufe)")
		expect(LoginStreak.describe({ kind = "MeterBoost", runs = 1 })).toBe("x2 Meter (1 Lauf)")
		expect(LoginStreak.describe({ kind = "Skin", skin = "Gold" }, "Goldener Glanz")).toBe("Goldener Glanz")
	end)
end)

describe("Cosmetics: exklusive Farben und Zufallsfarbe", function()
	local COLORS = {
		{ id = "Standard", name = "Original", price = 0 },
		{ id = "Red", name = "Rot", price = 0 },
		{ id = "Green", name = "Gruen", price = 40 },
		{ id = "Pink", name = "Pink", price = 60 },
		{ id = "GoldenSkin", name = "Goldener Glanz", price = 0, exclusive = true },
	}

	it("exklusiv heisst: nur wenn wirklich bekommen", function()
		expect(Cosmetics.isOwned(COLORS[5], {})).toBe(false)
		expect(Cosmetics.isOwned(COLORS[5], { GoldenSkin = true })).toBe(true)
		local color = Cosmetics.colorFor(COLORS, {}, { ShoppingCart = "GoldenSkin" }, "ShoppingCart")
		expect(color and color.id).toBe("Standard")
	end)

	it("Zufallsfarbe: nur kaufbare, die man noch nicht hat", function()
		local picked = Cosmetics.pickUnowned(COLORS, { Green = true }, 0.5)
		expect(picked and picked.id).toBe("Pink")
		expect(Cosmetics.pickUnowned(COLORS, { Green = true, Pink = true }, 0.5)).toBeNil()
		local first = Cosmetics.pickUnowned(COLORS, {}, 0)
		expect(first and first.id).toBe("Green")
	end)
end)
