--!strict
-- Fahrzeuge: Daten aus Config.Vehicles und die Fahrwerte pro Fahrzeug (Server und Client).
-- Die Werte rechnet src/shared/Progression/VehicleStats aus (getestet).
--
-- Jeder Wagen traegt das Attribut "VehicleId". Code, der Fahrwerte braucht, fragt
-- Vehicles.forCart(cart) statt direkt Config.Cart/Drive/Drift/Hop.

local Config = require(script.Parent:WaitForChild("Config"))
local VehicleStats = require(script.Parent:WaitForChild("Progression"):WaitForChild("VehicleStats"))

local Vehicles = {}

export type Stats = {
	Cart: typeof(Config.Cart),
	Drive: typeof(Config.Drive),
	Drift: typeof(Config.Drift),
	Hop: typeof(Config.Hop),
}

export type Def = {
	id: string,
	name: string,
	description: string,
	price: number,
	style: string,
	ratings: { speed: number, handling: number, stability: number },
	set: { [string]: { [string]: any } },
	scale: { [string]: { [string]: number } },
}

local cache: { [string]: Stats } = {}

function Vehicles.defaultId(): string
	return Config.Vehicles.Default
end

-- Fahrzeug aus der Config (nil = gibt es nicht)
function Vehicles.get(id: unknown): Def?
	if type(id) ~= "string" or id == "Default" or id == "ModelsFolder" or id == "Order" then
		return nil
	end
	local raw = (Config.Vehicles :: any)[id]
	if type(raw) ~= "table" then
		return nil
	end
	return {
		id = id,
		name = raw.name or id,
		description = raw.description or "",
		price = raw.price or 0,
		style = raw.style or "Cart",
		ratings = raw.ratings or { speed = 3, handling = 3, stability = 3 },
		set = raw.set or {},
		scale = raw.scale or {},
	}
end

-- Alle Fahrzeuge in der Reihenfolge der Garage
function Vehicles.list(): { Def }
	local result = {}
	for _, id in Config.Vehicles.Order do
		local def = Vehicles.get(id)
		if def then
			table.insert(result, def)
		end
	end
	return result
end

-- Fahrwerte eines Fahrzeugs (unbekannt = Einkaufswagen)
function Vehicles.stats(id: string?): Stats
	local key = if id and Vehicles.get(id) then id else Vehicles.defaultId()
	local cached = cache[key]
	if cached then
		return cached
	end
	local raw = (Config.Vehicles :: any)[key]
	local stats = VehicleStats.resolve(Config :: any, if type(raw) == "table" then raw else nil) :: any
	cache[key] = stats
	return stats
end

-- Fahrwerte des Fahrzeugs, aus dem dieser Wagen gebaut wurde
function Vehicles.forCart(cart: Instance?): Stats
	local id = cart and cart:GetAttribute("VehicleId")
	return Vehicles.stats(if type(id) == "string" then id else nil)
end

return Vehicles
