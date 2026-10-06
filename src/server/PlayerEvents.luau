--!strict
-- Ereignisse eines Spielers (Lauf beendet, Objekt geschleudert, Muenzen, Driftzeit ...) an alle
-- verteilen, die sich dafuer interessieren (Hausaufgaben, Erfolge). So muessen RaceManager,
-- Coins und Launchables die Abnehmer nicht kennen.
--
-- Unity-Vergleich: ein statisches C#-Event, an das sich mehrere Systeme haengen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))

local reportRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ReportStat") :: RemoteEvent

local PlayerEvents = {}

-- Alle Felder sind optional, je nach Art (type)
export type Event = {
	type: string, -- "Finish", "Launch", "Coins", "Drift", "HomeworkDone"
	amount: number?, -- Coins/Drift
	name: string?, -- Launch: DisplayName
	meters: number?, -- Launch: Flugweite
	sky: boolean?, -- Launch: ins All
	trackId: string?, -- Finish
	time: number?, -- Finish
	grade: number?, -- Finish
	livesLost: number?, -- Finish
	allCoins: boolean?, -- Finish: alle Muenzen der Strecke eingesammelt
	isNewBest: boolean?, -- Finish
	hadPrevious: boolean?, -- Finish: es gab schon eine Bestzeit
}

local listeners: { (player: Player, event: Event) -> () } = {}
local lastDriftReport: { [Player]: number } = {}

function PlayerEvents.on(callback: (player: Player, event: Event) -> ())
	table.insert(listeners, callback)
end

function PlayerEvents.fire(player: Player, event: Event)
	for _, callback in listeners do
		local ok, err = pcall(function()
			callback(player, event)
			return true
		end)
		if not ok then
			warn(`[PlayerEvents] Fehler bei "{event.type}": {err}`)
		end
	end
end

function PlayerEvents.init()
	-- Driftzeit meldet der Client (Fahrphysik laeuft dort). Der Server glaubt hoechstens so
	-- viel, wie seit der letzten Meldung wirklich vergangen ist, und nur im Wagen.
	reportRemote.OnServerEvent:Connect(function(player, kind, amount)
		if kind ~= "Drift" or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
			return
		end
		local now = os.clock()
		local last = lastDriftReport[player] or (now - Config.Homework.DriftReportInterval)
		lastDriftReport[player] = now
		if not CartManager.isSeated(player) then
			return
		end
		local allowed = math.min(amount, now - last + 0.5)
		if allowed > 0 then
			Profiles.get(player).stats.driftSeconds += allowed
			Profiles.markChanged(player)
			PlayerEvents.fire(player, { type = "Drift", amount = allowed })
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastDriftReport[player] = nil
	end)
end

return PlayerEvents
