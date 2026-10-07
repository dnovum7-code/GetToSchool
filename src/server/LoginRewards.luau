--!strict
-- Taegliche Login-Belohnung (7-Tage-Serie), Server-Seite. Der Client zeigt den Kalender und
-- schickt ("ClaimLogin") ueber das Settings-Remote; der Server prueft mit der eigenen Uhr
-- (DayClock), ob heute schon abgeholt wurde, und schreibt die Belohnung gut.
-- Logik: Progression/LoginStreak, Belohnungen: Config.LoginRewards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CosmeticsLogic = require(Shared:WaitForChild("Progression"):WaitForChild("Cosmetics"))
local LoginStreak = require(Shared:WaitForChild("Progression"):WaitForChild("LoginStreak"))
local Cosmetics = require(script.Parent:WaitForChild("Cosmetics"))
local DayClock = require(script.Parent:WaitForChild("DayClock"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local ProgressSync = require(script.Parent:WaitForChild("ProgressSync"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local settingsRemote = remotes:WaitForChild("Settings") :: RemoteEvent
local progressRemote = remotes:WaitForChild("Progress") :: RemoteEvent

local LoginRewards = {}

local function skinName(id: string?): string
	local item = CosmeticsLogic.find(Config.Cosmetics.Colors :: any, id)
	return if item then item.name else "Wagen-Skin"
end

-- Belohnung gutschreiben. Gibt den Text fuer die Anzeige zurueck.
local function grant(player: Player, reward: Config.LoginRewardDef): string
	local data = Profiles.get(player)
	if reward.kind == "Coins" then
		Profiles.addCoins(player, reward.amount or 0)
		return `{reward.amount or 0} Muenzen`
	elseif reward.kind == "MeterBoost" then
		data.meterBoostRuns = math.min(data.meterBoostRuns + (reward.runs or 1), 99)
		Profiles.markChanged(player)
		return LoginStreak.describe(reward :: any)
	elseif reward.kind == "Skin" and reward.skin then
		if data.cosmetics.colors[reward.skin] then
			-- schon vorhanden: stattdessen Muenzen
			local coins = reward.fallbackCoins or 0
			Profiles.addCoins(player, coins)
			return `{coins} Muenzen (den {skinName(reward.skin)} hast du schon)`
		end
		Cosmetics.grantColor(player, reward.skin)
		return `{skinName(reward.skin)} - exklusiv! (Lackiererei)`
	end
	return ""
end

-- Hat der Spieler den Skin von Tag 7 schon? (dann gibt es dort Muenzen)
local function skinOwned(data: any): boolean
	for _, reward in Config.LoginRewards.Days do
		if reward.kind == "Skin" and reward.skin and data.cosmetics.colors[reward.skin] then
			return true
		end
	end
	return false
end

local function claim(player: Player)
	if Profiles.getState(player) ~= "Ready" then
		return
	end
	local data = Profiles.get(player)
	local day = LoginStreak.claim(data.login, DayClock.today())
	if not day then
		return -- heute schon abgeholt
	end
	local reward = Config.LoginRewards.Days[day]
	local text = if reward then grant(player, reward) else ""
	Profiles.markChanged(player)
	Profiles.saveSoon(player)
	progressRemote:FireClient(player, "LoginClaimed", day, text)
end

function LoginRewards.init()
	settingsRemote.OnServerEvent:Connect(function(player, kind)
		if kind == "ClaimLogin" then
			claim(player)
		end
	end)
	ProgressSync.addExtender(function(player, snapshot)
		local data = Profiles.get(player)
		local today = DayClock.today()
		local canClaim, day = LoginStreak.status(data.login, today)
		snapshot.login = {
			canClaim = canClaim and Profiles.getState(player) == "Ready",
			day = day,
			today = today,
			skinOwned = skinOwned(data),
		}
		snapshot.meterBoostRuns = data.meterBoostRuns
	end)
end

return LoginRewards
