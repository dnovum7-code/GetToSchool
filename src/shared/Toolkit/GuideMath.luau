--!strict
-- Barrieren (Tag "Barrier") und Stabil-Zone (Tag "StableZone"): reine Rechnung, getestet in
-- tests/GuideSpec.luau. Alles waagerecht in (x, z); Roblox: -Z = vorne.

local GuideMath = {}

-- Entlanggleiten: Tempo-Anteil in die Wand (gegen die Wand-Normale n, die vom Hindernis weg
-- zeigt) entfernen, Rest so strecken, dass `keep` vom bisherigen Tempo bleibt, dazu `push`
-- Studs/s von der Wand weg. Rueckgabe: neue Geschwindigkeit (x, z).
function GuideMath.slide(
	vx: number,
	vz: number,
	nx: number,
	nz: number,
	keep: number,
	push: number
): (number, number)
	local speed = math.sqrt(vx * vx + vz * vz)
	local into = vx * nx + vz * nz
	if into >= 0 or speed < 1e-6 then
		return vx, vz -- faehrt nicht in die Wand: nichts tun
	end
	local tx, tz = vx - nx * into, vz - nz * into
	local tLength = math.sqrt(tx * tx + tz * tz)
	local wanted = speed * math.clamp(keep, 0, 1)
	if tLength > 1e-6 then
		tx, tz = tx / tLength * wanted, tz / tLength * wanted
	end
	return tx + nx * push, tz + nz * push
end

-- Drehrate (rad/s um die Hochachse), die den Blick (fx, fz) zur Richtung (tx, tz) dreht.
-- Positiv = nach links (gegen den Uhrzeigersinn von oben gesehen).
function GuideMath.yawRate(fx: number, fz: number, tx: number, tz: number, rate: number): number
	local tLength = math.sqrt(tx * tx + tz * tz)
	local fLength = math.sqrt(fx * fx + fz * fz)
	if tLength < 1e-6 or fLength < 1e-6 then
		return 0
	end
	-- Winkel von f nach t (Drehung um +Y): atan2 des Kreuzprodukts (Y-Teil) und Skalarprodukt
	local cross = fz * tx - fx * tz
	local dot = fx * tx + fz * tz
	return math.atan2(cross, dot) * rate
end

-- Neigung in Grad aus dem Y-Anteil der Hochachse (1 = gerade, 0 = auf der Seite)
function GuideMath.tilt(upY: number): number
	return math.deg(math.acos(math.clamp(upY, -1, 1)))
end

-- Stabil-Zone: Aufricht-Drehrate (rad/s). Erst ab maxTilt, steigt weich an, hoechstens `speed`.
function GuideMath.rightingRate(tilt: number, maxTilt: number, speed: number): number
	if tilt <= maxTilt then
		return 0
	end
	return speed * math.clamp((tilt - maxTilt) / 30, 0, 1)
end

-- Weicher Uebergang 0..1 (rein = 1, raus = 0) in `time` Sekunden
function GuideMath.blend(current: number, inside: boolean, dt: number, time: number): number
	local step = dt / math.max(time, 0.01)
	return if inside then math.min(current + step, 1) else math.max(current - step, 0)
end

return GuideMath
