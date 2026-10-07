--!strict
local TestLib = require("./TestLib")
local TerrainMath = require("../plugin_terrain/TerrainMath")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

-- Hoehendatei wie von tools/swissalti_to_terrain.py: heights[row][col] in Metern
local function makeFile(heights: { { number } }, cell: number, magic: string?): string
	local rows, cols = #heights, #heights[1]
	local b = buffer.create(48 + rows * cols * 4)
	buffer.writestring(b, 0, magic or "GTST")
	buffer.writeu16(b, 4, 1)
	buffer.writeu32(b, 8, cols)
	buffer.writeu32(b, 12, rows)
	buffer.writef32(b, 16, cell)
	buffer.writef32(b, 20, cell)
	local minH, maxH = math.huge, -math.huge
	for row = 1, rows do
		for col = 1, cols do
			local h = heights[row][col]
			minH, maxH = math.min(minH, h), math.max(maxH, h)
			buffer.writef32(b, 48 + ((row - 1) * cols + (col - 1)) * 4, h)
		end
	end
	buffer.writef32(b, 24, minH)
	buffer.writef32(b, 28, maxH)
	buffer.writef64(b, 32, 2600000)
	buffer.writef64(b, 40, 1200000)
	return buffer.tostring(b)
end

local function parse(heights: { { number } }, cell: number): TerrainMath.Data
	local data, err = TerrainMath.parse(makeFile(heights, cell))
	assert(data, err)
	return data
end

describe("TerrainMath (Plugin Terrain-Import)", function()
	it("liest Kopf und Werte", function()
		local data = parse({ { 500, 510 }, { 520, 530 } }, 2)
		expect(data.cols).toBe(2)
		expect(data.rows).toBe(2)
		expect(data.minH).toBe(500)
		expect(data.maxH).toBe(530)
		expect(data.originE).toBe(2600000)
		local w, d = TerrainMath.sizeMeters(data)
		expect(w).toBe(4)
		expect(d).toBe(4)
	end)

	it("lehnt falsche Dateien ab", function()
		local data, err = TerrainMath.parse(makeFile({ { 1, 2 }, { 3, 4 } }, 2, "PNG!"))
		expect(data == nil).toBe(true)
		expect(err ~= nil).toBe(true)
		local short = TerrainMath.parse("GTST")
		expect(short == nil).toBe(true)
		-- abgeschnittene Datei
		local full = makeFile({ { 1, 2 }, { 3, 4 } }, 2)
		local cut = TerrainMath.parse(string.sub(full, 1, #full - 4))
		expect(cut == nil).toBe(true)
	end)

	it("Hoehe: Zellmitte genau, dazwischen bilinear, Rand fortgesetzt", function()
		-- Zellen 2 m: Mitten bei 1 m und 3 m
		local data = parse({ { 0, 10 }, { 20, 30 } }, 2)
		expect(TerrainMath.heightAt(data, 1, 1)).toBeNear(0, 1e-4)
		expect(TerrainMath.heightAt(data, 3, 1)).toBeNear(10, 1e-4)
		expect(TerrainMath.heightAt(data, 2, 1)).toBeNear(5, 1e-4)
		expect(TerrainMath.heightAt(data, 2, 2)).toBeNear(15, 1e-4)
		expect(TerrainMath.heightAt(data, 0, 0)).toBeNear(0, 1e-4) -- Rand
		expect(TerrainMath.heightAt(data, 99, 99)).toBeNear(30, 1e-4)
	end)

	it("Lage: auf 4er-Raster, Breite und Steigung", function()
		local data = parse({ { 100, 100, 100, 100 }, { 100, 100, 100, 150 } }, 10) -- 40 x 20 m
		local layout = TerrainMath.layout(data, 400, 2, 1, 3, 10, 16) -- 1 m = 10 Studs
		expect(layout.studsPerMeter).toBeNear(10, 1e-6)
		expect(layout.verticalScale).toBeNear(20, 1e-6)
		expect(layout.nx).toBe(100)
		expect(layout.nz).toBe(50)
		expect(layout.x0 % 4).toBe(0)
		expect(layout.z0 % 4).toBe(0)
		expect(layout.yBottom % 4).toBe(0)
		expect(layout.yBottom <= 10 - 16).toBe(true)
		-- hoechster Punkt: 10 + 50 m * 20 = 1010, darueber ein Voxel Luft
		expect(layout.yTop >= 1010 + 4).toBe(true)
		expect(layout.yTop % 4).toBe(0)
	end)

	it("Mittelt feine Daten pro Voxel", function()
		local data = parse({ { 0, 0 }, { 0, 0 } }, 2)
		-- 1 m = 0.5 Studs: 8 m pro Voxel, Daten 2 m -> 4 x 4 Abtastpunkte
		expect(TerrainMath.layout(data, 2, 1, 0, 0, 0, 8).samples).toBe(4)
		-- 1 m = 10 Studs: Daten viel groeber als ein Voxel -> 1 Punkt
		expect(TerrainMath.layout(data, 40, 1, 0, 0, 0, 8).samples).toBe(1)
	end)

	it("Oberflaeche: flach = baseY, Rampe linear (keine Stufen)", function()
		local flat = parse({ { 700, 700 }, { 700, 700 } }, 2)
		local layoutFlat = TerrainMath.layout(flat, 40, 1, 0, 0, 25, 16)
		expect(TerrainMath.surfaceY(flat, layoutFlat, 3, 4)).toBeNear(25, 1e-4)

		-- Rampe Ost-West: 0 m bis 30 m ueber 4 Zellen zu 10 m, 1 m = 1 Stud (Breite 40)
		local ramp = parse({ { 0, 10, 20, 30 }, { 0, 10, 20, 30 } }, 10)
		local layout = TerrainMath.layout(ramp, 40, 1, 20, 10, 0, 16)
		local previous = -math.huge
		local steps = {}
		for i = 2, 7 do -- innere Voxel (Rand ist abgeflacht)
			local y = TerrainMath.surfaceY(ramp, layout, i, 1)
			expect(y > previous).toBe(true)
			if previous > -math.huge then
				table.insert(steps, y - previous)
			end
			previous = y
		end
		for _, step in steps do
			expect(step).toBeNear(4, 1e-3) -- 4 Studs pro Voxel, gleichmaessig
		end
	end)

	it("Fuellgrad: Bruchteil nur im Oberflaechen-Voxel", function()
		expect(TerrainMath.occupancy(10, 0)).toBe(1) -- ganz darunter
		expect(TerrainMath.occupancy(10, 8)).toBeNear(0.5, 1e-9) -- Oberflaeche halb im Voxel
		expect(TerrainMath.occupancy(10, 9)).toBeNear(0.25, 1e-9)
		expect(TerrainMath.occupancy(10, 12)).toBe(0) -- Luft
	end)

	it("Hoechster Punkt fuer Schild und Spawn", function()
		local data = parse({ { 1, 2, 3 }, { 4, 9, 5 } }, 2)
		local col, row = TerrainMath.highestCell(data)
		expect(col).toBe(1)
		expect(row).toBe(1)
		local layout = TerrainMath.layout(data, 6 * TerrainMath.STUDS_PER_METER, 1, 0, 0, 0, 8)
		local x, z = TerrainMath.cellToWorld(data, layout, col, row)
		expect(x).toBeNear(layout.x0 + 3 * layout.studsPerMeter, 1e-6)
		expect(z).toBeNear(layout.z0 + 3 * layout.studsPerMeter, 1e-6)
	end)
end)

return nil
