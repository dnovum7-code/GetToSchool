--!strict
-- Lufttricks, Server-Seite: Der Client meldet eine saubere Trick-Landung ("Trick", halbe
-- Drehungen) ueber ReportStat. Der Server prueft (im Wagen, Lauf laeuft, nicht zu oft,
-- Muenzen pro Minute begrenzt) und schreibt die Muenzen gut. Logik: Progression/TrickMath.
-- Ausserdem beobachtet er selbst, wann der Wagen in der Luft war: Ein Trick zaehlt nur nach
-- einem echten Flug, und hoechstens so viele Drehungen, wie in die Flugzeit passen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TrickMath = require(Shared:WaitForChild("Progression"):WaitForChild("TrickMath"))
local CartBuilder = require(script.Parent:WaitForChild("CartBuilder"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local PlayerEvents = require(script.Parent:WaitForChild("PlayerEvents"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local RaceManager = require(script.Parent:WaitForChild("RaceManager"))

local reportRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ReportStat") :: RemoteEvent

local Tricks = {}

type Budget = { coins: number, at: number, last: number }
local budgets: { [Player]: Budget } = {}

-- Flug-Beobachtung pro Spieler: seit wann in der Luft, wie lange der letzte Flug ging
type Air = { since: number?, lastDuration: number, landedAt: number }
local air: { [Player]: Air } = {}
local LANDING_GRACE = 1.5 -- so lange (s) nach der Landung darf die Meldung kommen
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function isAirborne(player: Player, cart: Model, base: BasePart): boolean
	local vehicle = cart:GetAttribute("VehicleId")
	local reach = CartBuilder.getRideHeight(if type(vehicle) == "string" then vehicle else nil) + 1.5
	local character = player.Character
	rayParams.FilterDescendantsInstances = if character then { cart, character } else { cart }
	return workspace:Raycast(base.Position, Vector3.new(0, -reach, 0), rayParams) == nil
end

local function watchAir()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local cart = CartManager.getCart(player)
		local base = cart and cart:FindFirstChild("Base")
		if not cart or not base or not base:IsA("BasePart") or not RaceManager.isRunning(player) then
			air[player] = nil
			continue
		end
		local state = air[player]
		if not state then
			state = { since = nil, lastDuration = 0, landedAt = -math.huge }
			air[player] = state
		end
		if isAirborne(player, cart, base) then
			state.since = state.since or now
		elseif state.since then
			state.lastDuration = now - state.since
			state.landedAt = now
			state.since = nil
		end
	end
end

-- Wie lange war der Wagen beim letzten (oder laufenden) Flug in der Luft? 0 = gar nicht
local function recentAirTime(player: Player): number
	local state = air[player]
	if not state then
		return 0
	end
	local now = os.clock()
	if state.since then
		return now - state.since
	end
	return if now - state.landedAt <= LANDING_GRACE then state.lastDuration else 0
end

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
		-- Nur nach einem echten Flug, und nur so viele Drehungen, wie in die Flugzeit passen
		-- (mit Puffer, weil der Server die Lage des Wagens etwas verspaetet sieht)
		local airTime = recentAirTime(player)
		if airTime < T.MinAirTime * 0.5 then
			return
		end
		local possible = math.floor((airTime + 0.3) * math.deg(T.SpinSpeed) / 180) + 1
		spins = math.min(spins, possible)
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
	RunService.Heartbeat:Connect(watchAir)
	Players.PlayerRemoving:Connect(function(player)
		budgets[player] = nil
		air[player] = nil
	end)
end

return Tricks
