--!strict
local TestLib = require("./TestLib")
local Economy = require("../src/shared/Progression/Economy")
local SaveData = require("../src/shared/Progression/SaveData")
local VehicleStats = require("../src/shared/Progression/VehicleStats")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local function baseConfig()
	return {
		Cart = { Width = 4, Length = 6, BallastHeight = 2 },
		Drive = { SteerRate = 1, MaxPushSpeed = 60, AirDrag = 0.001 },
		Drift = { SteerRate = 2, DriftByDefault = true },
		Hop = { Speed = 37 },
	}
end

describe("VehicleStats (Fahrzeugwerte)", function()
	it("ohne Aenderungen: Werte des Einkaufswagens", function()
		local base = baseConfig()
		local stats = VehicleStats.resolve(base, nil)
		expect(stats.Cart.Width).toBe(4)
		expect(stats.Drive.SteerRate).toBe(1)
		expect(stats.Drift.DriftByDefault).toBe(true)
		expect(stats.Hop.Speed).toBe(37)
	end)

	it("fester Wert und Faktor", function()
		local base = baseConfig()
		local stats = VehicleStats.resolve(base, {
			set = { Cart = { Width = 3 } },
			scale = { Drive = { SteerRate = 1.5, MaxPushSpeed = 0.5 } },
		})
		expect(stats.Cart.Width).toBe(3)
		expect(stats.Cart.Length).toBe(6)
		expect(stats.Drive.SteerRate).toBe(1.5)
		expect(stats.Drive.MaxPushSpeed).toBe(30)
		expect(stats.Drive.AirDrag).toBe(0.001)
	end)

	it("liest Grundwerte frisch (Tuning-Panel)", function()
		local base = baseConfig()
		local stats = VehicleStats.resolve(base, { scale = { Drive = { SteerRate = 2 } } })
		base.Drive.SteerRate = 3
		expect(stats.Drive.SteerRate).toBe(6)
		base.Cart.Length = 8
		expect(stats.Cart.Length).toBe(8)
	end)

	it("Faktor auf Nicht-Zahlen wird ignoriert", function()
		local base = baseConfig()
		local stats = VehicleStats.resolve(base, { scale = { Drift = { DriftByDefault = 2 } } })
		expect(stats.Drift.DriftByDefault).toBe(true)
	end)

	it("nur lesen", function()
		local stats = VehicleStats.resolve(baseConfig(), nil)
		local ok = pcall(function()
			stats.Drive.SteerRate = 5
		end)
		expect(ok).toBe(false)
	end)

	it("Verhaeltnis zum Einkaufswagen", function()
		local base = baseConfig()
		local stats = VehicleStats.resolve(base, { scale = { Drive = { MaxPushSpeed = 1.25 } } })
		expect(VehicleStats.ratio(base, stats, "Drive", "MaxPushSpeed")).toBe(1.25)
		expect(VehicleStats.ratio(base, stats, "Drive", "SteerRate")).toBe(1)
	end)
end)

describe("Economy.buyOnce (Fahrzeuge, Kosmetik)", function()
	it("kaufen, zu teuer, schon gekauft", function()
		local data = { coins = 500 }
		local owned = {}
		local ok, reason = Economy.buyOnce(data, owned, "OfficeChair", 400)
		expect(ok).toBe(true)
		expect(reason).toBe("Bought")
		expect(data.coins).toBe(100)
		expect(owned.OfficeChair).toBe(true)
		ok, reason = Economy.buyOnce(data, owned, "OfficeChair", 400)
		expect(ok).toBe(false)
		expect(reason).toBe("Owned")
		ok, reason = Economy.buyOnce(data, owned, "SchoolDesk", 800)
		expect(ok).toBe(false)
		expect(reason).toBe("NotEnough")
		expect(data.coins).toBe(100)
	end)
end)

describe("SaveData: gewaehltes Fahrzeug", function()
	it("Standard ist der Einkaufswagen, nur gekaufte sind waehlbar", function()
		expect(SaveData.new().selectedVehicle).toBe("ShoppingCart")
		local data = SaveData.migrate({ version = 2, vehicles = { OfficeChair = true }, selectedVehicle = "OfficeChair" })
		assert(data)
		expect(data.selectedVehicle).toBe("OfficeChair")
		data = SaveData.migrate({ version = 2, selectedVehicle = "SchoolDesk" })
		assert(data)
		expect(data.selectedVehicle).toBe("ShoppingCart")
	end)

	it("merge behaelt die Wahl aus der Sitzung", function()
		local stored = SaveData.new()
		stored.vehicles.SchoolDesk = true
		stored.selectedVehicle = "SchoolDesk"
		local session = SaveData.new()
		expect(SaveData.merge(stored, session).selectedVehicle).toBe("SchoolDesk")
		session.vehicles.OfficeChair = true
		session.selectedVehicle = "OfficeChair"
		expect(SaveData.merge(stored, session).selectedVehicle).toBe("OfficeChair")
	end)
end)
