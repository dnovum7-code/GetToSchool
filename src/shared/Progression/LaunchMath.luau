--!strict
-- Flugbahn fuer weggeschleuderte Objekte (Baustein "Launchable") - reine Logik ohne
-- Roblox-Dienste (getestet in tests/LaunchMathSpec.luau).
--
-- Der Server plant den Flug (damit Flugweite, Rekord und Bonus nicht vom Client kommen),
-- der Client spielt genau diesen Flug ab. Zwei Arten:
--   normal:  Wurfparabel mit eigener (kleiner) Schwerkraft, landet auf Abwurfhoehe
--   Himmel:  schiesst nach oben, wird immer schneller und verschwindet nach SkyTime mit
--            einem Stern-Blinken (wie Team Rocket)

local LaunchMath = {}

export type LaunchConfig = {
	SpeedCarry: number,
	UpRatio: number,
	Gravity: number,
	SkyUpRatio: number,
	SkyAcceleration: number,
	SkyTime: number,
	MaxFlightTime: number,
	BonusPerMeter: number,
	MaxBonus: number,
}

export type Flight = {
	horizontalSpeed: number, -- Studs/s entlang der Flugrichtung
	verticalSpeed: number, -- Studs/s nach oben (Start)
	gravity: number, -- normal: nach unten; Himmel: 0
	skyAcceleration: number, -- Himmel: Beschleunigung nach oben, sonst 0
	sky: boolean,
	duration: number, -- Sekunden bis zur Landung bzw. bis zum Verschwinden
	distance: number, -- geflogene Strecke in Studs
}

-- Flug planen. `cartSpeed`: Tempo des Wagens beim Treffer, `power`: Schleuderkraft.
function LaunchMath.plan(cartSpeed: number, power: number, sky: boolean, cfg: LaunchConfig): Flight
	local horizontal = math.max(cartSpeed, 0) * cfg.SpeedCarry + math.max(power, 0)
	if sky then
		local vertical = math.max(power, 0) * cfg.SkyUpRatio
		local t = math.max(cfg.SkyTime, 0.1)
		local dx = horizontal * t
		local dy = vertical * t + 0.5 * cfg.SkyAcceleration * t * t
		return {
			horizontalSpeed = horizontal,
			verticalSpeed = vertical,
			gravity = 0,
			skyAcceleration = cfg.SkyAcceleration,
			sky = true,
			duration = t,
			distance = math.sqrt(dx * dx + dy * dy),
		}
	end
	local vertical = math.max(power, 0) * cfg.UpRatio
	local gravity = math.max(cfg.Gravity, 1)
	local t = math.clamp(2 * vertical / gravity, 0.2, math.max(cfg.MaxFlightTime, 0.2))
	return {
		horizontalSpeed = horizontal,
		verticalSpeed = vertical,
		gravity = gravity,
		skyAcceleration = 0,
		sky = false,
		duration = t,
		distance = horizontal * t,
	}
end

-- Versatz nach `t` Sekunden: (entlang der Flugrichtung, nach oben) in Studs
function LaunchMath.offset(flight: Flight, t: number): (number, number)
	local time = math.clamp(t, 0, flight.duration)
	local along = flight.horizontalSpeed * time
	local up = flight.verticalSpeed * time - 0.5 * flight.gravity * time * time
	if flight.sky then
		up = flight.verticalSpeed * time + 0.5 * flight.skyAcceleration * time * time
	end
	return along, up
end

-- Bisher geflogene Strecke (Studs) nach `t` Sekunden (fuer die hochzaehlende Anzeige)
function LaunchMath.distanceAt(flight: Flight, t: number): number
	local along, up = LaunchMath.offset(flight, t)
	if flight.sky then
		return math.sqrt(along * along + up * up)
	end
	return along
end

-- Studs -> ganze Meter
function LaunchMath.meters(studs: number, studsToMeters: number): number
	return math.floor(studs * studsToMeters + 0.5)
end

-- Kleiner Muenzbonus fuer die Flugweite
function LaunchMath.bonus(meters: number, cfg: LaunchConfig): number
	return math.clamp(math.floor(meters * cfg.BonusPerMeter), 0, math.max(math.floor(cfg.MaxBonus), 0))
end

-- Fliegt es in den Himmel? `roll`: Zufallszahl 0..1, `chance`: Wahrscheinlichkeit 0..1
function LaunchMath.isSky(roll: number, chance: number): boolean
	return roll < math.clamp(chance, 0, 1)
end

return LaunchMath
