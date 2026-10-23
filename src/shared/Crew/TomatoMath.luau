--!strict
-- Tomatenwurf: Flugbahn und Treffer (reine Rechnung, getestet in tests/CrewSpec.luau).
-- Positionen als { x, y, z } (der Server rechnet mit seinen eigenen Positionen der Ziele).

local TomatoMath = {}

export type Vec = { number }
export type Target = { id: any, x: number, y: number, z: number, radius: number }

function TomatoMath.at(origin: Vec, velocity: Vec, gravity: number, t: number): (number, number, number)
	return origin[1] + velocity[1] * t,
		origin[2] + velocity[2] * t - 0.5 * gravity * t * t,
		origin[3] + velocity[3] * t
end

-- Erster Treffer entlang der Bahn: prueft alle `step` Sekunden bis `maxTime`.
-- Rueckgabe: Ziel-Id und Zeitpunkt, oder nil.
function TomatoMath.firstHit(
	origin: Vec,
	velocity: Vec,
	gravity: number,
	targets: { Target },
	maxTime: number,
	step: number
): (any, number?)
	local t = 0
	while t <= maxTime do
		local x, y, z = TomatoMath.at(origin, velocity, gravity, t)
		for _, target in targets do
			local dx, dy, dz = x - target.x, y - target.y, z - target.z
			if dx * dx + dy * dy + dz * dz <= target.radius * target.radius then
				return target.id, t
			end
		end
		t += math.max(step, 0.01)
	end
	return nil, nil
end

return TomatoMath
