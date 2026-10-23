--!strict
-- Tempogefuehl und Klang: reine Rechnung (getestet in tests/AtmosphereSpec.luau).
-- Alles haengt am Anteil vom Hoechsttempo (Config.Atmosphere.TopSpeed): 0 = Stand, 1 = voll.
-- "start" heisst: erst ab diesem Anteil passiert etwas (z. B. Sichtfeld ab 70 %).

local SpeedFeel = {}

function SpeedFeel.fraction(speed: number, topSpeed: number): number
	return math.clamp(speed / math.max(topSpeed, 1), 0, 1)
end

-- Weicher Anstieg 0..1 zwischen `start` und vollem Tempo (smoothstep, kein Knick)
function SpeedFeel.ramp(fraction: number, start: number): number
	local x = math.clamp((fraction - start) / math.max(1 - start, 0.01), 0, 1)
	return x * x * (3 - 2 * x)
end

-- Zusaetzliches Sichtfeld (Grad)
function SpeedFeel.fovExtra(speed: number, topSpeed: number, start: number, extra: number): number
	return extra * SpeedFeel.ramp(SpeedFeel.fraction(speed, topSpeed), start)
end

-- Speed-Linien 0..1: bei hohem Tempo, waehrend eines Boosts mindestens `boostLevel`
function SpeedFeel.speedLines(
	speed: number,
	topSpeed: number,
	start: number,
	boosting: boolean,
	boostLevel: number
): number
	local value = SpeedFeel.ramp(SpeedFeel.fraction(speed, topSpeed), start)
	if boosting then
		value = math.max(value, boostLevel)
	end
	return value
end

-- Fahrtwind: Lautstaerke und Tonhoehe
function SpeedFeel.wind(
	speed: number,
	topSpeed: number,
	start: number,
	volume: number,
	minPitch: number,
	maxPitch: number
): (number, number)
	local t = SpeedFeel.ramp(SpeedFeel.fraction(speed, topSpeed), start)
	return volume * t, minPitch + (maxPitch - minPitch) * t
end

-- Untergrund -> Partikel-Art. `material` = Name des Roblox-Materials (Enum.Material.X.Name)
local SURFACES: { [string]: string } = {
	Grass = "Grass",
	LeafyGrass = "Grass",
	Ground = "Dirt",
	Mud = "Dirt",
	Sand = "Dirt",
	Sandstone = "Dirt",
	Snow = "Snow",
	Glacier = "Snow",
	Ice = "Snow",
	Asphalt = "Asphalt",
	Concrete = "Asphalt",
	Pavement = "Asphalt",
	Cobblestone = "Asphalt",
	Slate = "Asphalt",
	Rock = "Asphalt",
	Brick = "Asphalt",
	Basalt = "Asphalt",
	SmoothPlastic = "Asphalt",
	Plastic = "Asphalt",
	WoodPlanks = "Asphalt",
	Wood = "Asphalt",
}

function SpeedFeel.surface(material: string): string?
	return SURFACES[material]
end

-- Partikel pro Sekunde an einem Rad: Grundmenge des Untergrunds mal Tempo-Anteil (ab
-- minSpeed), beim Driften mal driftFactor, hoechstens maxRate.
function SpeedFeel.wheelRate(
	baseRate: number,
	speed: number,
	topSpeed: number,
	minSpeed: number,
	drifting: boolean,
	driftFactor: number,
	maxRate: number
): number
	if speed < minSpeed then
		return 0
	end
	local rate = baseRate * SpeedFeel.fraction(speed, topSpeed)
	if drifting then
		rate *= driftFactor
	end
	return math.min(rate, maxRate)
end

-- Musik: Anteil der zweiten (intensiven) Spur 0..1 - mit dem Tempo, beim Boost voll
function SpeedFeel.musicIntensity(fraction: number, start: number, boosting: boolean): number
	if boosting then
		return 1
	end
	return SpeedFeel.ramp(fraction, start)
end

-- Weich ueberblenden: `current` in Richtung `target`, volle Strecke in `fadeTime` Sekunden
function SpeedFeel.approach(current: number, target: number, dt: number, fadeTime: number): number
	local step = dt / math.max(fadeTime, 0.01)
	if current < target then
		return math.min(current + step, target)
	end
	return math.max(current - step, target)
end

return SpeedFeel
