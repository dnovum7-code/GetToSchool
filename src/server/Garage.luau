--!strict
-- Garage, Server-Seite: Fahrzeuge kaufen und waehlen (ueber den Shop, nur ausserhalb eines
-- Laufs). Das gewaehlte Fahrzeug steht im Spielstand (selectedVehicle); CartManager baut den
-- Wagen beim naechsten Neustart passend neu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Progression"):WaitForChild("Economy"))
local Vehicles = require(Shared:WaitForChild("Vehicles"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local PlayerEvents = require(script.Parent:WaitForChild("PlayerEvents"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local ProgressSync = require(script.Parent:WaitForChild("ProgressSync"))
local RaceManager = require(script.Parent:WaitForChild("RaceManager"))
local Shop = require(script.Parent:WaitForChild("Shop"))

local Garage = {}

-- Config.Debug.AllUpgrades: in Studio sind auch alle Fahrzeuge frei (zum Testen)
local function allFree(): boolean
	return Config.Debug.AllUpgrades and RunService:IsStudio()
end

function Garage.owns(player: Player, id: string): boolean
	return allFree() or Profiles.get(player).vehicles[id] == true
end

-- Fahrzeug, mit dem der Spieler faehrt (fuer CartManager)
function Garage.selected(player: Player): string
	local id = Profiles.get(player).selectedVehicle
	if Vehicles.get(id) and Garage.owns(player, id) then
		return id
	end
	return Vehicles.defaultId()
end

local function select(player: Player, id: string)
	Profiles.get(player).selectedVehicle = id
	Profiles.markChanged(player)
	Profiles.saveSoon(player)
	RaceManager.restart(player) -- neuer Wagen am Start
end

local function buyVehicle(player: Player, id: unknown): (boolean, string)
	local def = Vehicles.get(id)
	if not def then
		return false, "Unbekanntes Fahrzeug."
	end
	if Garage.owns(player, def.id) then
		return false, `{def.name} steht schon in deiner Garage.`
	end
	local data = Profiles.get(player)
	local ok, reason = Economy.buyOnce(data, data.vehicles, def.id, def.price)
	if not ok then
		return false,
			if reason == "NotEnough"
				then `Zu wenig Muenzen: {def.name} kostet {def.price}.`
				else "Geht nicht."
	end
	select(player, def.id) -- neues Fahrzeug gleich nehmen
	PlayerEvents.fire(player, { type = "VehicleBought" }) -- Erfolg "Fuhrpark"
	return true, `Gekauft: {def.name}! Viel Spass.`
end

local function selectVehicle(player: Player, id: unknown): (boolean, string)
	local def = Vehicles.get(id)
	if not def then
		return false, "Unbekanntes Fahrzeug."
	end
	if not Garage.owns(player, def.id) then
		return false, `{def.name} musst du erst kaufen.`
	end
	if Garage.selected(player) == def.id then
		return true, `Du faehrst schon: {def.name}`
	end
	select(player, def.id)
	return true, `Du faehrst jetzt: {def.name}`
end

function Garage.init()
	CartManager.setVehicleResolver(Garage.selected)
	Shop.addHandler("BuyVehicle", buyVehicle)
	Shop.addHandler("SelectVehicle", selectVehicle)
	ProgressSync.addExtender(function(player, snapshot)
		local owned = {}
		for _, def in Vehicles.list() do
			owned[def.id] = Garage.owns(player, def.id)
		end
		snapshot.vehicles = owned
		snapshot.selectedVehicle = Garage.selected(player)
	end)
	-- Spielstand geladen: anderes Fahrzeug gewaehlt? Dann den Wagen tauschen (nur vor dem Lauf)
	Profiles.onLoaded(function(player)
		local cart = CartManager.getCart(player)
		if
			cart
			and cart:GetAttribute("VehicleId") ~= Garage.selected(player)
			and RaceManager.isOutsideRun(player)
		then
			RaceManager.restart(player)
		end
	end)
end

return Garage
