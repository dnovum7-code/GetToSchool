--!strict
-- Kosmetik (Farben pro Fahrzeug, Spuren) - reine Logik ohne Roblox-Dienste
-- (getestet in tests/CosmeticsSpec.luau). Angebot und Preise: Config.Cosmetics.

local Cosmetics = {}

export type Item = {
	id: string,
	name: string,
	price: number,
	exclusive: boolean?, -- nicht kaufbar, nur als Belohnung (z. B. Login-Tag 7)
}

function Cosmetics.find(items: { Item }, id: unknown): Item?
	for _, item in items do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- Darf der Spieler das benutzen? (kostenlos oder gekauft; exklusiv nur, wenn bekommen)
function Cosmetics.isOwned(item: Item, owned: { [string]: boolean }): boolean
	if item.exclusive then
		return owned[item.id] == true
	end
	return item.price <= 0 or owned[item.id] == true
end

-- Zufaellige kaufbare Farbe, die man noch nicht hat (Gluecksrad). `roll` 0..1. nil = keine mehr
function Cosmetics.pickUnowned(items: { Item }, owned: { [string]: boolean }, roll: number): Item?
	local candidates = {}
	for _, item in items do
		if not item.exclusive and item.price > 0 and not owned[item.id] then
			table.insert(candidates, item)
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[math.clamp(math.floor(roll * #candidates) + 1, 1, #candidates)]
end

-- Farbe eines Fahrzeugs (Id); unbekannt oder nicht (mehr) besessen = erste Farbe (Standard)
function Cosmetics.colorFor(
	colors: { Item },
	owned: { [string]: boolean },
	vehicleColors: { [string]: string },
	vehicleId: string
): Item?
	local item = Cosmetics.find(colors, vehicleColors[vehicleId])
	if item and Cosmetics.isOwned(item, owned) then
		return item
	end
	return colors[1]
end

-- Gewaehlte Spur (nil = keine)
function Cosmetics.trailFor(trails: { Item }, owned: { [string]: boolean }, selected: string): Item?
	local item = Cosmetics.find(trails, selected)
	if item and Cosmetics.isOwned(item, owned) then
		return item
	end
	return nil
end

return Cosmetics
