--!strict
-- Hupe, Server-Seite: Der Client meldet "hupen", wir pruefen (sitzt im Wagen, Abklingzeit)
-- und schicken es an alle Clients ("Honk", Spieler, Hupen-Id). Jeder Client spielt den Sound
-- selbst am Wagen des Hupenden ab - so kann jeder die Hupen anderer stummschalten.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local HornRules = require(Shared:WaitForChild("Progression"):WaitForChild("HornRules"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))

local hornRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Horn") :: RemoteEvent

local Horn = {}

local lastHonk: { [Player]: number } = {}

-- Die Hupe, die der Spieler gerade benutzt (gewaehlt und gekauft, sonst Standard)
function Horn.selected(player: Player): HornRules.HornDef?
	local cosmetics = Profiles.get(player).cosmetics
	return HornRules.selected(Config.Horn.Horns, cosmetics.horns, cosmetics.horn, Config.Horn.Default)
end

function Horn.init()
	hornRemote.OnServerEvent:Connect(function(player, kind)
		if kind ~= "Honk" or not CartManager.isSeated(player) then
			return
		end
		local now = os.clock()
		-- etwas Spielraum fuer Netzwerk-Schwankungen (der Client wartet die volle Zeit)
		if not HornRules.ready(lastHonk[player], now, Config.Horn.Cooldown * 0.8) then
			return
		end
		lastHonk[player] = now
		local def = Horn.selected(player)
		hornRemote:FireAllClients("Honk", player, if def then def.id else "")
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastHonk[player] = nil
	end)
end

return Horn
