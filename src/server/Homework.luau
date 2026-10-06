--!strict
-- Hausaufgaben (taegliche Aufgaben), Server-Seite: Aufgaben des Tages auswuerfeln, Ereignisse
-- verbuchen (Launch, Muenzen, Drift, Ziel), Belohnung gutschreiben. Die Logik steht in
-- src/shared/Progression/Homework (getestet), die Aufgaben in Config.Homework.
-- Der Client bekommt die Aufgaben im Spielstand-Snapshot (Feld "homework").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local HomeworkLogic = require(Shared:WaitForChild("Progression"):WaitForChild("Homework"))
local Unlocks = require(Shared:WaitForChild("Progression"):WaitForChild("Unlocks"))
local PlayerEvents = require(script.Parent:WaitForChild("PlayerEvents"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local ProgressSync = require(script.Parent:WaitForChild("ProgressSync"))
local Track = require(script.Parent:WaitForChild("Track"))

local Homework = {}

local GREEN = Color3.fromRGB(120, 255, 140)

local function pool(): { HomeworkLogic.Def }
	return Config.Homework.Pool :: any
end

local function today(): number
	return HomeworkLogic.dayIndex(os.time(), Config.Homework.ResetHourUtc)
end

-- Darf diese Aufgabe beim Spieler vorkommen? (Strecke vorhanden und frei)
local function availableFor(player: Player): (HomeworkLogic.Def) -> boolean
	local data = Profiles.get(player)
	return function(def)
		local track = def.track
		if not track then
			return true
		end
		return Track.exists(track) and Unlocks.isUnlocked(Unlocks.find(Config.Tracks, track), data)
	end
end

-- Neuer Tag? Dann neue Aufgaben (gibt zurueck, ob sich etwas geaendert hat)
local function ensureToday(player: Player): boolean
	if Profiles.getState(player) ~= "Ready" then
		return false -- erst wenn der Spielstand geladen ist (sonst falscher Tag/Fortschritt)
	end
	local data = Profiles.get(player)
	local changed = HomeworkLogic.ensureDay(
		data.homework,
		today(),
		pool(),
		Config.Homework.TasksPerDay,
		math.abs(player.UserId),
		availableFor(player)
	)
	if changed then
		Profiles.markChanged(player)
	end
	return changed
end

-- Ereignis verbuchen (kommt ueber PlayerEvents von RaceManager, Coins, Launchables, Drift)
function Homework.report(player: Player, event: HomeworkLogic.Event)
	ensureToday(player)
	local data = Profiles.get(player)
	if data.homework.day ~= today() then
		return
	end
	local before = {}
	for index, task in data.homework.tasks do
		before[index] = task.progress
	end
	local finished = HomeworkLogic.report(data.homework, pool(), event)
	local changed = #finished > 0
	for index, task in data.homework.tasks do
		if task.progress ~= before[index] then
			changed = true
		end
	end
	for _, def in finished do
		Profiles.addCoins(player, def.reward)
		ProgressSync.notice(
			player,
			`Hausaufgabe erledigt: {HomeworkLogic.describe(def, Track.displayName)}  +{def.reward}`,
			GREEN
		)
	end
	if #finished > 0 and HomeworkLogic.takeBonus(data.homework) then
		PlayerEvents.fire(player, { type = "HomeworkDone" })
		local bonus = Config.Homework.AllDoneBonus
		if bonus > 0 then
			Profiles.addCoins(player, bonus)
		end
		task.delay(3.2, function()
			if player.Parent then
				ProgressSync.notice(
					player,
					`Alle Hausaufgaben erledigt! Bonus +{bonus}`,
					Color3.fromRGB(255, 215, 80)
				)
			end
		end)
	end
	if changed then
		Profiles.markChanged(player)
	end
end

-- Fuer den Snapshot: Aufgaben mit Text, Fortschritt, Ziel, Belohnung
local function snapshotFor(player: Player): { [string]: any }?
	local data = Profiles.get(player)
	if data.homework.day ~= today() then
		return nil
	end
	local tasks = {}
	for _, task in data.homework.tasks do
		local def = HomeworkLogic.find(pool(), task.id)
		if def then
			table.insert(tasks, {
				text = HomeworkLogic.describe(def, Track.displayName),
				progress = task.progress,
				goal = HomeworkLogic.goalOf(def),
				reward = def.reward,
				done = task.done,
				kind = def.type,
			})
		end
	end
	return {
		tasks = tasks,
		bonus = Config.Homework.AllDoneBonus,
		bonusDone = data.homework.bonusDone,
		nextReset = HomeworkLogic.nextReset(os.time(), Config.Homework.ResetHourUtc),
	}
end

function Homework.init()
	ProgressSync.addExtender(function(player, snapshot)
		snapshot.homework = snapshotFor(player)
	end)
	Profiles.onLoaded(function(player)
		ensureToday(player)
	end)
	PlayerEvents.on(function(player, event)
		if event.type ~= "HomeworkDone" then
			Homework.report(player, event :: any)
		end
	end)
	-- Tageswechsel, waehrend jemand spielt: neue Aufgaben und Hinweis
	task.spawn(function()
		while true do
			task.wait(30)
			for _, player in Players:GetPlayers() do
				if ensureToday(player) then
					ProgressSync.notice(player, "Neue Hausaufgaben! (Menue B)", Color3.fromRGB(255, 215, 80))
				end
			end
		end
	end)
end

return Homework
