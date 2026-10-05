--!strict
-- Shop, Server-Seite: Jeder Kauf wird hier geprueft (der Client fragt nur):
--   * Spielstand geladen? Ausserhalb eines Laufs? Nicht zu schnell hintereinander?
--   * Gibt es das Upgrade, ist die naechste Stufe noch frei, reichen die Muenzen?
-- Erst dann werden Muenzen abgezogen und die Stufe erhoeht (siehe Economy.purchase).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Progression"):WaitForChild("Economy"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local RaceManager = require(script.Parent:WaitForChild("RaceManager"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local shopRemote = remotes:WaitForChild("ShopRequest") :: RemoteEvent
local progressRemote = remotes:WaitForChild("Progress") :: RemoteEvent

local Shop = {}

local MIN_INTERVAL = 0.25 -- Schutz gegen Spam
local lastRequest: { [Player]: number } = {}
-- Weitere Anfragen (z. B. Track freischalten), von anderen Modulen ergaenzt
local handlers: { [string]: (player: Player, id: unknown) -> (boolean, string) } = {}

local function reply(player: Player, ok: boolean, message: string)
	progressRemote:FireClient(player, "ShopResult", ok, message)
end

-- Gemeinsame Pruefungen fuer alle Shop-Anfragen. Gibt eine Fehlermeldung zurueck oder nil.
function Shop.checkAllowed(player: Player): string?
	if Profiles.getState(player) == "Loading" then
		return "Spielstand wird noch geladen ..."
	end
	if not RaceManager.isOutsideRun(player) then
		return "Shop gibt es nur vor oder nach einem Lauf (T = Neustart)."
	end
	return nil
end

local function buyUpgrade(player: Player, id: unknown): (boolean, string)
	local def = Economy.findUpgrade(Config.Upgrades, id)
	if not def then
		return false, "Unbekanntes Upgrade."
	end
	local data = Profiles.get(player)
	local ok, reason, level, price = Economy.purchase(data, def)
	if not ok then
		if reason == "MaxLevel" then
			return false, `{def.name} hat schon die hoechste Stufe.`
		end
		return false, `Zu wenig Muenzen: {def.name} kostet {price}.`
	end
	Profiles.markChanged(player)
	Profiles.saveSoon(player) -- Kaeufe gleich speichern
	if def.id == "Helmet" then
		RaceManager.refreshShield(player)
	end
	return true, `Gekauft: {def.name} Stufe {level}!`
end

-- Weitere Anfrage-Art anmelden: handler(player, id) -> (Erfolg, Meldung)
function Shop.addHandler(kind: string, handler: (player: Player, id: unknown) -> (boolean, string))
	handlers[kind] = handler
end

function Shop.init()
	handlers.Upgrade = buyUpgrade
	shopRemote.OnServerEvent:Connect(function(player, kind: unknown, id: unknown)
		local now = os.clock()
		if now - (lastRequest[player] or 0) < MIN_INTERVAL then
			return
		end
		lastRequest[player] = now
		local handler = if type(kind) == "string" then handlers[kind] else nil
		if not handler then
			return
		end
		local blocked = Shop.checkAllowed(player)
		if blocked then
			reply(player, false, blocked)
			return
		end
		local ok, message = handler(player, id)
		reply(player, ok, message)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return Shop
