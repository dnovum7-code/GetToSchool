--!strict
-- Hupe: welche Hupe hat ein Spieler, darf er schon wieder hupen? Reine Logik (getestet in
-- tests/HornSpec.luau). Hupen-Liste: Config.Horn.Horns. Kostenlose (price 0) hat jeder,
-- andere sind spaeter als Kosmetik kaufbar (Spielstand cosmetics.horns / cosmetics.horn).

local HornRules = {}

export type HornDef = {
	id: string,
	name: string, -- Anzeigename
	sound: string, -- Eintrag in Config.Sounds
	price: number, -- 0 = kostenlos
}

function HornRules.find(list: { HornDef }, id: string?): HornDef?
	for _, def in list do
		if def.id == id then
			return def
		end
	end
	return nil
end

function HornRules.isOwned(def: HornDef, owned: { [string]: boolean }): boolean
	return def.price <= 0 or owned[def.id] == true
end

-- Gewaehlte Hupe, wenn es sie gibt und sie gehoert; sonst die Standard-Hupe; sonst die
-- erste kostenlose.
function HornRules.selected(
	list: { HornDef },
	owned: { [string]: boolean },
	selectedId: string?,
	defaultId: string
): HornDef?
	local chosen = HornRules.find(list, selectedId)
	if chosen and HornRules.isOwned(chosen, owned) then
		return chosen
	end
	local fallback = HornRules.find(list, defaultId)
	if fallback and HornRules.isOwned(fallback, owned) then
		return fallback
	end
	for _, def in list do
		if def.price <= 0 then
			return def
		end
	end
	return nil
end

-- Abklingzeit: `last` = Zeit des letzten Hupens (nil = noch nie)
function HornRules.ready(last: number?, now: number, cooldown: number): boolean
	return last == nil or now - last >= cooldown
end

return HornRules
