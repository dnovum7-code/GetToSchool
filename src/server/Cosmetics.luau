--!strict
-- Kosmetik, Server-Seite (Lackiererei im Menue): Farbe fuer das gewaehlte Fahrzeug und Spur
-- kaufen/waehlen. Ein Klick auf etwas Ungekauftes kauft es (Preis steht auf dem Knopf).
-- Angewendet wird sofort am Wagen (alle sehen es) und bei jedem neu gebauten Wagen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CosmeticsLogic = require(Shared:WaitForChild("Progression"):WaitForChild("Cosmetics"))
local Economy = require(Shared:WaitForChild("Progression"):WaitForChild("Economy"))
local Vehicles = require(Shared:WaitForChild("Vehicles"))
local CartBuilder = require(script.Parent:WaitForChild("CartBuilder"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local Garage = require(script.Parent:WaitForChild("Garage"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local ProgressSync = require(script.Parent:WaitForChild("ProgressSync"))
local Shop = require(script.Parent:WaitForChild("Shop"))

local Cosmetics = {}

type Def = Config.CosmeticDef

local function colors(): { Def }
	return Config.Cosmetics.Colors
end

local function trails(): { Def }
	return Config.Cosmetics.Trails
end

-- Lackierung auf einen Wagen anwenden (Fahrzeug des Wagens)
local function applyTo(player: Player, cart: Model)
	local data = Profiles.get(player)
	local vehicle = cart:GetAttribute("VehicleId")
	local vehicleId = if type(vehicle) == "string" then vehicle else Vehicles.defaultId()
	local color = CosmeticsLogic.colorFor(
		colors() :: any,
		data.cosmetics.colors,
		data.cosmetics.vehicleColors,
		vehicleId
	) :: Def?
	local trail =
		CosmeticsLogic.trailFor(trails() :: any, data.cosmetics.trails, data.cosmetics.trail) :: Def?
	CartBuilder.applyLook(
		cart,
		color and color.color,
		color and color.material,
		trail,
		color and color.sparkle
	)
end

local function refresh(player: Player)
	local cart = CartManager.getCart(player)
	if cart then
		applyTo(player, cart)
	end
	Profiles.markChanged(player)
	Profiles.saveSoon(player)
end

-- Kaufen, falls noetig. Gibt (ok, Meldung beim Fehlschlag) zurueck.
local function ensureOwned(player: Player, item: Def, owned: { [string]: boolean }): (boolean, string?)
	if CosmeticsLogic.isOwned(item :: any, owned) then
		return true, nil
	end
	if item.exclusive then
		return false, `{item.name} gibt es nur als Login-Belohnung (Tag 7).`
	end
	local ok, reason = Economy.buyOnce(Profiles.get(player), owned, item.id, item.price)
	if not ok then
		return false,
			if reason == "NotEnough"
				then `Zu wenig Muenzen: {item.name} kostet {item.price}.`
				else "Geht nicht."
	end
	return true, nil
end

local function setColor(player: Player, id: unknown): (boolean, string)
	local item = CosmeticsLogic.find(colors() :: any, id) :: Def?
	if not item then
		return false, "Unbekannte Farbe."
	end
	local data = Profiles.get(player)
	local wasOwned = CosmeticsLogic.isOwned(item :: any, data.cosmetics.colors)
	local ok, message = ensureOwned(player, item, data.cosmetics.colors)
	if not ok then
		return false, message or ""
	end
	local vehicleId = Garage.selected(player)
	data.cosmetics.vehicleColors[vehicleId] = item.id
	refresh(player)
	local vehicle = Vehicles.get(vehicleId)
	local vehicleName = if vehicle then vehicle.name else vehicleId
	return true, if wasOwned then `{vehicleName}: {item.name}` else `Gekauft: {item.name} ({vehicleName})`
end

local function setTrail(player: Player, id: unknown): (boolean, string)
	local data = Profiles.get(player)
	if id == "" then
		data.cosmetics.trail = ""
		refresh(player)
		return true, "Keine Spur"
	end
	local item = CosmeticsLogic.find(trails() :: any, id) :: Def?
	if not item then
		return false, "Unbekannte Spur."
	end
	local wasOwned = CosmeticsLogic.isOwned(item :: any, data.cosmetics.trails)
	local ok, message = ensureOwned(player, item, data.cosmetics.trails)
	if not ok then
		return false, message or ""
	end
	data.cosmetics.trail = item.id
	refresh(player)
	return true, if wasOwned then `Spur: {item.name}` else `Gekauft: {item.name}`
end

-- Belohnung (Login-Tag 7, Gluecksrad): Farbe schenken und fuer das aktuelle Fahrzeug setzen
function Cosmetics.grantColor(player: Player, id: string)
	local data = Profiles.get(player)
	data.cosmetics.colors[id] = true
	data.cosmetics.vehicleColors[Garage.selected(player)] = id
	refresh(player)
end

function Cosmetics.init()
	Shop.addHandler("Color", setColor)
	Shop.addHandler("Trail", setTrail)
	CartManager.onCartBuilt(applyTo)
	-- Spielstand geladen: Lackierung des schon gebauten Wagens nachziehen
	Profiles.onLoaded(function(player)
		local cart = CartManager.getCart(player)
		if cart then
			applyTo(player, cart)
		end
	end)
	ProgressSync.addExtender(function(player, snapshot)
		local data = Profiles.get(player)
		local ownedColors, ownedTrails = {}, {}
		for _, item in colors() do
			ownedColors[item.id] = CosmeticsLogic.isOwned(item :: any, data.cosmetics.colors)
		end
		for _, item in trails() do
			ownedTrails[item.id] = CosmeticsLogic.isOwned(item :: any, data.cosmetics.trails)
		end
		local vehicleId = Garage.selected(player)
		local color = CosmeticsLogic.colorFor(
			colors() :: any,
			data.cosmetics.colors,
			data.cosmetics.vehicleColors,
			vehicleId
		)
		local trail = CosmeticsLogic.trailFor(trails() :: any, data.cosmetics.trails, data.cosmetics.trail)
		snapshot.cosmetics = {
			colors = ownedColors,
			trails = ownedTrails,
			color = if color then color.id else "",
			trail = if trail then trail.id else "",
		}
	end)
end

return Cosmetics
