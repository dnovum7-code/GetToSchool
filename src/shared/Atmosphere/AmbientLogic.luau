--!strict
-- Umgebungsleben (AmbientSound, AmbientParticles, BirdFlock, Villager, Spectator): reine
-- Rechnung, getestet in tests/AtmosphereSpec.luau.

local AmbientLogic = {}

-- Welche sind aktiv? Nur die innerhalb `range`, die naechsten zuerst, hoechstens `maxActive`.
-- Rueckgabe: Liste der Nummern (in `distances`), die aktiv sein sollen.
function AmbientLogic.pickActive(distances: { number }, range: number, maxActive: number): { number }
	local candidates = {}
	for index, distance in distances do
		if distance <= range then
			table.insert(candidates, index)
		end
	end
	table.sort(candidates, function(a, b)
		return distances[a] < distances[b]
	end)
	local result = {}
	for i = 1, math.min(#candidates, math.max(maxActive, 0)) do
		table.insert(result, candidates[i])
	end
	return result
end

-- Reaktion eines Dorfbewohners: fest ("Dodge", "Scold", "Wave") oder zufaellig (r = 0..1)
local REACTIONS = { "Dodge", "Scold", "Wave" }
function AmbientLogic.reaction(setting: string?, r: number): string
	if setting == "Dodge" or setting == "Scold" or setting == "Wave" then
		return setting
	end
	return REACTIONS[math.clamp(math.floor(r * #REACTIONS) + 1, 1, #REACTIONS)]
end

-- Auf welche Seite springt er weg? Wagen faehrt in Richtung (vx, vz), der Bewohner steht
-- (dx, dz) vom Wagen entfernt. "Links" der Fahrtrichtung ist (vz, -vx) (Roblox: -Z = vorne).
-- +1 = nach links, -1 = nach rechts: weiter weg von der Fahrspur, also auf seine Seite.
function AmbientLogic.dodgeSide(vx: number, vz: number, dx: number, dz: number): number
	local leftDot = dx * vz - dz * vx
	return if leftDot >= 0 then 1 else -1
end

-- Hopser: Hoehe zum Zeitpunkt t (0..duration), Parabel mit Scheitel `height`
function AmbientLogic.hop(t: number, duration: number, height: number): number
	if t <= 0 or t >= duration then
		return 0
	end
	local x = t / duration
	return 4 * height * x * (1 - x)
end

return AmbientLogic
