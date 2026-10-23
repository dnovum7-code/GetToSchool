--!strict
-- Near-Miss, Server-Seite: Der Client meldet "NearMiss" ueber ReportStat (er sieht die
-- Hindernisse, viele gibt es nur bei ihm). Der Server zahlt nur waehrend eines Laufs, im
-- Wagen, hoechstens alle Config.NearMiss.MinInterval Sekunden und MaxPerRun Mal pro Lauf.
-- Logik: Progression/NearMissRules.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local NearMissRules = require(Shared:WaitForChild("Progression"):WaitForChild("NearMissRules"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local PlayerEvents = require(script.Parent:WaitForChild("PlayerEvents"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local RaceManager = require(script.Parent:WaitForChild("RaceManager"))

local reportRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ReportStat") :: RemoteEvent

local NearMiss = {}

local budgets: { [Player]: NearMissRules.Budget } = {}

function NearMiss.init()
	reportRemote.OnServerEvent:Connect(function(player, kind)
		if kind ~= "NearMiss" or not RaceManager.isRunning(player) or not CartManager.isSeated(player) then
			return
		end
		local budget = budgets[player]
		if not budget then
			budget = { runId = -1, count = 0, last = -math.huge }
			budgets[player] = budget
		end
		local N = Config.NearMiss
		if
			not NearMissRules.allow(
				budget,
				RaceManager.getRunId(player),
				os.clock(),
				N.MinInterval,
				N.MaxPerRun
			)
		then
			return
		end
		if N.Coins > 0 then
			Profiles.addCoins(player, N.Coins)
		end
		PlayerEvents.fire(player, { type = "NearMiss", amount = N.Coins })
	end)
	Players.PlayerRemoving:Connect(function(player)
		budgets[player] = nil
	end)
end

return NearMiss
