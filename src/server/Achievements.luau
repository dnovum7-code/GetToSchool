--!strict
-- Erfolge, Server-Seite: prueft bei jedem Ereignis (PlayerEvents) und beim Laden, ob neue
-- Erfolge erreicht sind, speichert sie, zeigt dem Spieler ein Popup und vergibt das
-- Roblox-Badge (wenn in Config.Achievements eine Badge-Id steht). Logik und Liste:
-- src/shared/Progression/Achievements, Config.Achievements.

local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local AchievementsLogic = require(Shared:WaitForChild("Progression"):WaitForChild("Achievements"))
local Vehicles = require(Shared:WaitForChild("Vehicles"))
local PlayerEvents = require(script.Parent:WaitForChild("PlayerEvents"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local ProgressSync = require(script.Parent:WaitForChild("ProgressSync"))
local Track = require(script.Parent:WaitForChild("Track"))

local progressRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Progress") :: RemoteEvent

local Achievements = {}

local function defs(): { AchievementsLogic.Def }
	return Config.Achievements.List :: any
end

-- Strecken, die fuer "Note 6 auf allen Strecken" zaehlen: die aus Config.Tracks, die es gibt
local function trackIds(): { string }
	local existing = Track.list()
	local result = {}
	for _, def in Config.Tracks do
		if table.find(existing, def.id) then
			table.insert(result, def.id)
		end
	end
	return result
end

local function factsFor(player: Player, event: PlayerEvents.Event?): AchievementsLogic.Facts
	local data = Profiles.get(player)
	local owned, total = 0, 0
	for _, vehicle in Vehicles.list() do
		total += 1
		if data.vehicles[vehicle.id] then -- echte Kaeufe (nicht Debug.AllUpgrades)
			owned += 1
		end
	end
	return {
		event = event :: any,
		finishedRuns = data.stats.finishedRuns,
		objectsLaunched = data.stats.objectsLaunched,
		driftSeconds = data.stats.driftSeconds,
		bestGrades = data.bestGrades,
		trackIds = trackIds(),
		vehiclesOwned = owned,
		vehiclesTotal = total,
	}
end

local function awardBadge(player: Player, badge: number?)
	if not badge or badge <= 0 or RunService:IsStudio() and player.UserId <= 0 then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			if not BadgeService:UserHasBadgeAsync(player.UserId, badge) then
				BadgeService:AwardBadge(player.UserId, badge)
			end
		end)
		if not ok then
			warn(`[Achievements] Badge {badge} fuer {player.Name} nicht vergeben: {err}`)
		end
	end)
end

local function check(player: Player, event: PlayerEvents.Event?)
	if Profiles.getState(player) ~= "Ready" then
		return -- erst mit geladenem Spielstand (sonst falsche Zaehler)
	end
	local data = Profiles.get(player)
	local newly = AchievementsLogic.check(defs(), data.achievements, factsFor(player, event))
	if #newly == 0 then
		return
	end
	Profiles.markChanged(player)
	Profiles.saveSoon(player)
	for index, def in newly do
		awardBadge(player, def.badge)
		-- mehrere gleichzeitig: nacheinander zeigen
		task.delay((index - 1) * (Config.Achievements.PopupTime + 0.5), function()
			if player.Parent then
				progressRemote:FireClient(
					player,
					"Achievement",
					def.name,
					AchievementsLogic.describe(def, Track.displayName)
				)
			end
		end)
	end
end

function Achievements.init()
	PlayerEvents.on(function(player, event)
		-- Muenzen und Drift kommen oft: nur die Zaehler pruefen, wenn es sich lohnt
		if event.type == "Coins" then
			return
		end
		check(player, event)
	end)
	Profiles.onLoaded(function(player)
		check(player, nil) -- z. B. Erfolge, die es beim letzten Besuch noch nicht gab
		-- Badges fuer schon freigeschaltete Erfolge nachreichen (falls die Id spaeter kam)
		local data = Profiles.get(player)
		for _, def in defs() do
			if data.achievements[def.id] then
				awardBadge(player, def.badge)
			end
		end
	end)
	ProgressSync.addExtender(function(player, snapshot)
		local data = Profiles.get(player)
		local facts = factsFor(player, nil)
		local list = {}
		for _, def in defs() do
			local current, goal = AchievementsLogic.progress(def, facts)
			table.insert(list, {
				id = def.id,
				name = def.name,
				description = AchievementsLogic.describe(def, Track.displayName),
				unlocked = data.achievements[def.id] == true,
				progress = current,
				goal = goal,
				counter = goal > 1,
			})
		end
		snapshot.achievements = list
	end)
end

return Achievements
