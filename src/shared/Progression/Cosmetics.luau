--!strict
-- Kosmetik (Farben pro Fahrzeug, Spuren) - reine Logik ohne Roblox-Dienste
-- (getestet in tests/CosmeticsSpec.luau). Angebot und Preise: Config.Cosmetics.

local Cosmetics = {}

export type Item = { id: string, name: string, price: number }

function Cosmetics.find(items: { Item }, id: unknown): Item?
	for _, item in items do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- Darf der Spieler das benutzen? (kostenlos oder gekauft)
function Cosmetics.isOwned(item: Item, owned: { [string]: boolean }): boolean
	return item.price <= 0 or owned[item.id] == true
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
