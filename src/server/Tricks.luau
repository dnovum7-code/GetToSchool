--!strict
-- Lufttricks, Server-Seite: Der Client meldet eine saubere Trick-Landung ("Trick", halbe
-- Drehungen) ueber ReportStat. Der Server prueft (im Wagen, Lauf laeuft, nicht zu oft,
-- Muenzen pro Minute begrenzt) und schreibt die Muenzen gut. Logik: Progression/TrickMath.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TrickMath = require(Shared:WaitForChild("Progression"):WaitForChild("TrickMath"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local PlayerEvents = require(script.Parent:WaitForChild("PlayerEvents"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local RaceManager = require(script.Parent:WaitForChild("RaceManager"))

local reportRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ReportStat") :: RemoteEvent

local Tricks = {}

type Budget = { coins: number, at: number, last: number }
local budgets: { [Player]: Budget } = {}

function Tricks.init()
	reportRemote.OnServerEvent:Connect(function(player, kind, halfSpins)
		local T = Config.Tricks
		if kind ~= "Trick" or not T.Enabled or type(halfSpins) ~= "number" or halfSpins ~= halfSpins then
			return
		end
		local spins = math.clamp(math.floor(halfSpins), 0, T.MaxHalfSpins)
		if spins < 1 or not CartManager.isSeated(player) or not RaceManager.isRunning(player) then
			return
		end
		local now = os.clock()
		local budget = budgets[player]
		if not budget then
			budget = { coins = T.MaxCoinsPerMinute, at = now, last = -math.huge }
			budgets[player] = budget
		end
		if now - budget.last < T.MinInterval then
			return
		end
		budget.last = now
		-- Muenz-Budget fuellt sich mit MaxCoinsPerMinute pro Minute wieder auf
		budget.coins =
			math.min(T.MaxCoinsPerMinute, budget.coins + (now - budget.at) * T.MaxCoinsPerMinute / 60)
		budget.at = now
		local coins = math.min(TrickMath.coins(spins, T :: any), math.floor(budget.coins))
		if coins > 0 then
			budget.coins -= coins
			Profiles.addCoins(player, coins)
		end
		PlayerEvents.fire(player, { type = "Trick", amount = spins })
	end)
	Players.PlayerRemoving:Connect(function(player)
		budgets[player] = nil
	end)
end

return Tricks
