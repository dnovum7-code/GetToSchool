--!strict
-- Rechenteil fuer die Objekt-Tags LowGravity, NoFriction, KeepUpright (siehe
-- shared/ObjectPhysics.luau). Reine Logik, getestet in tests/SpawnedHitSpec.luau.

local ObjectPhysicsMath = {}

-- Kraft nach oben, damit nur noch `scale` der Schwerkraft wirkt (0.3 = 30 %).
function ObjectPhysicsMath.antiGravity(mass: number, gravity: number, scale: number): number
	return mass * gravity * (1 - math.clamp(scale, 0, 1))
end

-- Hoechstes Drehmoment der Aufricht-Kraft: `strength`-mal so viel, wie noetig ist, um das
-- Objekt aus dem Liegen hochzuheben (Gewicht mal halbe Groesse). Klein genug, dass ein
-- Treffer es trotzdem herumwirbelt, gross genug, dass es nicht liegen bleibt.
function ObjectPhysicsMath.uprightTorque(
	mass: number,
	gravity: number,
	extent: number,
	strength: number
): number
	return mass * gravity * math.max(extent, 0.5) * math.max(strength, 0)
end

-- Aufrichten nur, wenn es sich nicht gerade schnell dreht: Flips nach einem Stoss duerfen
-- ausdrehen, erst danach zieht die Kraft es wieder hoch. freeSpin <= 0 = immer aktiv.
function ObjectPhysicsMath.uprightActive(angularSpeed: number, freeSpin: number): boolean
	return freeSpin <= 0 or angularSpeed < freeSpin
end

-- Reibung fuer NoFriction: FrictionWeight hoch, damit beim Mischen mit dem Boden (Roblox
-- nimmt den gewichteten Mittelwert) fast nur unsere Reibung zaehlt.
ObjectPhysicsMath.NO_FRICTION_WEIGHT = 100

function ObjectPhysicsMath.mixedFriction(
	own: number,
	ownWeight: number,
	ground: number,
	groundWeight: number
): number
	return (own * ownWeight + ground * groundWeight) / math.max(ownWeight + groundWeight, 1e-6)
end

return ObjectPhysicsMath
