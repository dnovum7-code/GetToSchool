--!strict
local TestLib = require("./TestLib")
local GhostCodec = require("../src/shared/Progression/GhostCodec")
local serde = require("@lune/serde")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

local function run(count: number)
	local samples = {}
	for i = 0, count - 1 do
		table.insert(samples, { i * 2.5, 100 - i * 0.13, -i * 3.07, 1, (i * 7) % 360 - 180, -2 })
	end
	return samples
end

describe("GhostCodec (Geist)", function()
	it("einpacken und auspacken ergibt (fast) dieselben Werte", function()
		local samples = run(50)
		local ghost = GhostCodec.encode(samples, 0.1, 4.9)
		local decoded, dt, time = GhostCodec.decode(ghost, 10000)
		assert(decoded)
		expect(#decoded).toBe(50)
		expect(dt).toBe(0.1)
		expect(time).toBe(4.9)
		for i = 1, 50 do
			for v = 1, 3 do
				expect(decoded[i][v]).toBeNear(samples[i][v], 0.051)
			end
			for v = 4, 6 do
				local diff = math.abs((decoded[i][v] - samples[i][v] + 180) % 360 - 180)
				expect(diff).toBeLessThan(0.51)
			end
		end
	end)

	it("uebersteht JSON (wie im DataStore)", function()
		local ghost = GhostCodec.encode(run(20), 0.1, 1.9)
		local json = serde.encode("json", ghost)
		local decoded = GhostCodec.decode(serde.decode("json", json), 10000)
		expect(decoded ~= nil).toBe(true)
	end)

	it("ist platzsparend (60 s Lauf unter 20 KB)", function()
		local ghost = GhostCodec.encode(run(600), 0.1, 60)
		local json = serde.encode("json", ghost)
		expect(#json).toBeLessThan(20000)
	end)

	it("kaputte oder zu lange Daten werden abgelehnt", function()
		expect((GhostCodec.decode(nil, 100))).toBeNil()
		expect((GhostCodec.decode({ v = 1, dt = 0.1, time = 1, data = { 1, 2, 3 } }, 100))).toBeNil()
		expect((GhostCodec.decode({ v = 99, dt = 0.1, time = 1, data = {} }, 100))).toBeNil()
		local long = GhostCodec.encode(run(200), 0.1, 20)
		expect((GhostCodec.decode(long, 100))).toBeNil()
		expect((GhostCodec.decode({ v = 1, dt = 0.1, time = 1, data = { 1, 2, 3, 4, 5, "x" } }, 100))).toBeNil()
	end)

	it("Zwischenwerte werden weich verbunden, auch ueber 180 Grad", function()
		local samples = { { 0, 0, 0, 0, 170, 0 }, { 10, 0, -10, 0, -170, 0 } }
		local middle = GhostCodec.sample(samples, 0.1, 0.05)
		assert(middle)
		expect(middle[1]).toBeNear(5)
		expect(middle[3]).toBeNear(-5)
		expect(math.abs(middle[5])).toBeNear(180, 0.001)
		local after = GhostCodec.sample(samples, 0.1, 99)
		assert(after)
		expect(after[1]).toBe(10)
		expect(GhostCodec.duration(samples, 0.1)).toBeNear(0.1)
		expect(GhostCodec.sample({}, 0.1, 0)).toBeNil()
	end)
end)

return nil
