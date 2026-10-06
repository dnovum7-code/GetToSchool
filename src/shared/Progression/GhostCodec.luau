--!strict
-- Aufzeichnung fuer den "Geist vom besten Lauf" - reine Logik ohne Roblox-Dienste
-- (getestet in tests/GhostSpec.luau).
--
-- Aufgezeichnet wird alle `dt` Sekunden die Lage des Wagens: Position (x, y, z) und
-- Drehung (Winkel um x, y, z in Grad). Platzsparend gespeichert:
--   * Positionen auf 0.1 Studs gerundet, Winkel auf ganze Grad
--   * jeweils nur der Unterschied zum vorigen Wert (kleine Zahlen = wenig Text im DataStore)
-- Ein Lauf von 60 s mit dt = 0.1 braucht so etwa 10 KB.

local GhostCodec = {}

GhostCodec.VERSION = 1

-- Eine Lage: { x, y, z, rx, ry, rz } (Studs bzw. Grad)
export type Sample = { number }

export type Ghost = {
	v: number, -- Format-Version
	dt: number, -- Abstand zwischen zwei Aufnahmen (s)
	time: number, -- Fahrzeit des Laufs (s)
	data: { number }, -- 6 Zahlen pro Aufnahme, als Unterschiede
}

local VALUES = 6
local SCALE = { 10, 10, 10, 1, 1, 1 } -- Positionen in Zehntel-Studs, Winkel in Grad

local function wrapAngle(degrees: number): number
	local a = (degrees + 180) % 360 - 180
	return a
end

function GhostCodec.encode(samples: { Sample }, dt: number, time: number): Ghost
	local data = {}
	local previous = { 0, 0, 0, 0, 0, 0 }
	for _, sample in samples do
		for i = 1, VALUES do
			local value = math.floor(sample[i] * SCALE[i] + 0.5)
			local delta = value - previous[i]
			if i > 3 then
				delta = wrapAngle(delta) -- 179 -> -179 ist nur 2 Grad
			end
			table.insert(data, delta)
			previous[i] += delta
		end
	end
	return { v = GhostCodec.VERSION, dt = dt, time = time, data = data }
end

-- Gespeicherte Daten pruefen und auspacken. nil, wenn kaputt.
function GhostCodec.decode(raw: unknown, maxSamples: number): ({ Sample }?, number, number)
	if type(raw) ~= "table" then
		return nil, 0, 0
	end
	local ghost = raw :: { [any]: any }
	local dt, time, data = ghost.dt, ghost.time, ghost.data
	if ghost.v ~= GhostCodec.VERSION or type(dt) ~= "number" or dt <= 0 or type(time) ~= "number" then
		return nil, 0, 0
	end
	if type(data) ~= "table" or #data % VALUES ~= 0 or #data / VALUES > maxSamples then
		return nil, 0, 0
	end
	local samples: { Sample } = {}
	local current = { 0, 0, 0, 0, 0, 0 }
	for index = 1, #data, VALUES do
		local sample = {}
		for i = 1, VALUES do
			local delta = data[index + i - 1]
			if type(delta) ~= "number" or delta ~= delta then
				return nil, 0, 0
			end
			current[i] += delta
			sample[i] = current[i] / SCALE[i]
		end
		table.insert(samples, sample)
	end
	return samples, dt, time
end

-- Dauer der Aufzeichnung (s)
function GhostCodec.duration(samples: { Sample }, dt: number): number
	return math.max(#samples - 1, 0) * dt
end

local function lerpAngle(a: number, b: number, alpha: number): number
	return a + wrapAngle(b - a) * alpha
end

-- Lage zum Zeitpunkt t (zwischen zwei Aufnahmen weich verbunden).
-- Rueckgabe: { x, y, z, rx, ry, rz } oder nil, wenn es keine Aufnahmen gibt.
function GhostCodec.sample(samples: { Sample }, dt: number, t: number): Sample?
	local count = #samples
	if count == 0 then
		return nil
	end
	local position = math.clamp(t / dt, 0, count - 1)
	local index = math.floor(position) + 1
	local nextIndex = math.min(index + 1, count)
	local alpha = position - (index - 1)
	local a, b = samples[index], samples[nextIndex]
	local result = {}
	for i = 1, 3 do
		result[i] = a[i] + (b[i] - a[i]) * alpha
	end
	for i = 4, 6 do
		result[i] = lerpAngle(a[i], b[i], alpha)
	end
	return result
end

return GhostCodec
