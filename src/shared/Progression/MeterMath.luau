--!strict
-- Gefahrene Meter - reine Logik ohne Roblox-Dienste (getestet in tests/MetersSpec.luau).
-- Der Server misst jeden Frame, wie weit der Wagen gefahren ist. Weil die Physik beim
-- Client laeuft, zaehlt ein Stueck nur, wenn es plausibel ist (nicht schneller als MaxSpeed).
-- Teleports (Neustart, Checkpoint) zaehlen nie: Dann setzt der Server den Startpunkt neu.

local MeterMath = {}

export type Config = {
	StudsPerMeter: number, -- 1 m = 3.57 Studs
	MaxSpeed: number, -- hoechstens so schnell (Studs/s), sonst zaehlt das Stueck nicht
	Slack: number, -- Puffer (Studs) fuer kleine Ruckler
	MetersPerCoin: number,
}

export type Point = { number } -- { x, y, z }

-- Wie viele Studs zaehlen fuer dieses Stueck? 0 = unplausibel (Teleport, Ruckler, Cheat)
function MeterMath.segment(from: Point, to: Point, dt: number, cfg: Config): number
	if dt <= 0 then
		return 0
	end
	local dx, dy, dz = to[1] - from[1], to[2] - from[2], to[3] - from[3]
	local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
	if distance > cfg.MaxSpeed * dt + cfg.Slack then
		return 0
	end
	return distance
end

function MeterMath.toMeters(studs: number, cfg: Config): number
	return studs / math.max(cfg.StudsPerMeter, 0.01)
end

-- Wie viele Muenzen sind neu faellig? (`paid` = schon ausgezahlt in diesem Lauf)
function MeterMath.coinsDue(meters: number, paid: number, cfg: Config): number
	local total = math.floor(meters / math.max(cfg.MetersPerCoin, 1))
	return math.max(0, total - paid)
end

return MeterMath
