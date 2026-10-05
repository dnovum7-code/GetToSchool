--!strict
-- Fahrplan fuer PathMover (reine Logik, getestet in tests/ToolkitSpec.luau).
-- Aus den Abstaenden zwischen den Wegpunkten, dem Tempo und der Wartezeit wird ein Plan:
-- welcher Abschnitt (von Punkt A nach Punkt B) zu welcher Zeit gefahren wird.
--   loop = true:  1 -> 2 -> ... -> n -> 1 (Kreis)
--   loop = false: 1 -> ... -> n -> ... -> 1 (hin und zurueck)
-- An jedem Punkt wird `wait` Sekunden gewartet.

local PathMath = {}

export type Leg = {
	from: number, -- Punkt-Nummer
	to: number,
	start: number, -- Startzeit im Zyklus
	duration: number, -- Fahrzeit
}

export type Path = {
	legs: { Leg },
	wait: number,
	cycle: number, -- Dauer eines ganzen Durchgangs
}

-- `distance(a, b)`: Abstand zwischen Punkt a und b, `count`: Anzahl Punkte (mind. 2)
function PathMath.build(
	count: number,
	distance: (a: number, b: number) -> number,
	speed: number,
	wait: number,
	loop: boolean
): Path
	local order: { { number } } = {}
	if loop then
		for i = 1, count do
			table.insert(order, { i, i % count + 1 })
		end
	else
		for i = 1, count - 1 do
			table.insert(order, { i, i + 1 })
		end
		for i = count, 2, -1 do
			table.insert(order, { i, i - 1 })
		end
	end
	local legs: { Leg } = {}
	local time = 0
	local safeSpeed = math.max(speed, 0.01)
	local pause = math.max(wait, 0)
	for _, pair in order do
		local duration = math.max(distance(pair[1], pair[2]) / safeSpeed, 0.001)
		table.insert(legs, { from = pair[1], to = pair[2], start = time, duration = duration })
		time += duration + pause
	end
	return { legs = legs, wait = pause, cycle = math.max(time, 0.001) }
end

-- Wo ist der Mover zum Zeitpunkt `t`? Rueckgabe: Abschnitt (from, to), Anteil 0..1 auf dem
-- Abschnitt, und ob er gerade faehrt (false = wartet an Punkt `to`).
function PathMath.sample(path: Path, t: number): (number, number, number, boolean)
	local time = t % path.cycle
	for _, leg in path.legs do
		local arrive = leg.start + leg.duration
		if time < arrive then
			return leg.from, leg.to, math.clamp((time - leg.start) / leg.duration, 0, 1), true
		elseif time < arrive + path.wait then
			return leg.from, leg.to, 1, false
		end
	end
	local last = path.legs[#path.legs]
	return last.from, last.to, 1, false
end

-- weiches Anfahren und Abbremsen (0..1 -> 0..1)
function PathMath.smoothstep(x: number): number
	local v = math.clamp(x, 0, 1)
	return v * v * (3 - 2 * v)
end

-- Tor im Taktbetrieb: 0 = zu, 1 = offen. Ablauf: zu (closedTime) - oeffnen (duration) -
-- offen (openTime) - schliessen (duration).
function PathMath.gateTimer(t: number, duration: number, openTime: number, closedTime: number): number
	local move = math.max(duration, 0.01)
	local open = math.max(openTime, 0)
	local closed = math.max(closedTime, 0)
	local cycle = closed + move + open + move
	local time = t % cycle
	if time < closed then
		return 0
	elseif time < closed + move then
		return PathMath.smoothstep((time - closed) / move)
	elseif time < closed + move + open then
		return 1
	end
	return 1 - PathMath.smoothstep((time - closed - move - open) / move)
end

-- Tor per Signal: `since` = Sekunden seit dem Signal (nil = kein Signal), oeffnet in
-- `duration`, bleibt `closeAfter` Sekunden offen (0 = bleibt offen) und schliesst dann.
function PathMath.gateSignal(since: number?, duration: number, closeAfter: number): number
	if not since then
		return 0
	end
	local move = math.max(duration, 0.01)
	if since < move then
		return PathMath.smoothstep(since / move)
	end
	if closeAfter <= 0 or since < move + closeAfter then
		return 1
	end
	return 1 - PathMath.smoothstep((since - move - closeAfter) / move)
end

return PathMath
