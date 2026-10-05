--!strict
-- Strecken freischalten und waehlen (Server):
--   * Track-Liste fuer das Menue (in der Spielstand-Kopie, siehe ProgressSync)
--   * Noten-Bedingung erfuellt (z. B. Note 4 auf Track1)? Strecke wird automatisch und
--     dauerhaft freigeschaltet, mit Meldung.
--   * Menue-Anfragen "UnlockTrack" (fuer Muenzen) und "SelectTrack" (dorthin wechseln).
--     Gemeinsame Pruefungen (geladen, ausserhalb eines Laufs, Spam) macht der Shop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Unlocks = require(Shared:WaitForChild("Progression"):WaitForChild("Unlocks"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local ProgressSync = require(script.Parent:WaitForChild("ProgressSync"))
local RaceManager = require(script.Parent:WaitForChild("RaceManager"))
local Shop = require(script.Parent:WaitForChild("Shop"))
local Track = require(script.Parent:WaitForChild("Track"))

local TrackUnlocks = {}

-- Reihenfolge im Menue: wie in Config.Tracks, danach Strecken ohne Config-Eintrag
local function orderedTrackIds(): { string }
	local existing = Track.list()
	local ordered = {}
	for _, def in Config.Tracks do
		if table.find(existing, def.id) then
			table.insert(ordered, def.id)
		end
	end
	for _, id in existing do
		if not table.find(ordered, id) then
			table.insert(ordered, id)
		end
	end
	return ordered
end

local function trackList(player: Player): { { [string]: any } }
	local data = Profiles.get(player)
	local current = RaceManager.getTrackId(player)
	local list = {}
	for _, id in orderedTrackIds() do
		local def = Unlocks.find(Config.Tracks, id)
		local unlocked = Unlocks.isUnlocked(def, data)
		local best = data.bestTimes[id]
		table.insert(list, {
			id = id,
			name = Track.displayName(id),
			unlocked = unlocked,
			current = id == current,
			condition = if def and not unlocked then Unlocks.describe(def, Track.displayName) else nil,
			price = if def and def.unlock and not unlocked then def.unlock.price else nil,
			bestTime = if best then best.time else nil,
			bestGrade = data.bestGrades[id],
		})
	end
	return list
end

-- Noten-Bedingungen pruefen (nach jeder Aenderung am Spielstand, z. B. neue beste Note)
local function checkGradeUnlocks(player: Player)
	local data = Profiles.get(player)
	local newly = Unlocks.newlyUnlocked(Config.Tracks, data)
	if #newly == 0 then
		return
	end
	for _, id in newly do
		data.unlockedTracks[id] = true
		if Track.exists(id) then
			ProgressSync.notice(
				player,
				`Neue Strecke freigeschaltet: {Track.displayName(id)}! (Menue: B)`,
				Color3.fromRGB(255, 215, 80)
			)
		end
	end
	Profiles.markChanged(player)
end

local function unlockTrack(player: Player, id: unknown): (boolean, string)
	local def = Unlocks.find(Config.Tracks, id)
	if not def or not Track.exists(def.id) then
		return false, "Diese Strecke gibt es nicht."
	end
	local data = Profiles.get(player)
	local ok, reason, price = Unlocks.purchase(def, data)
	if not ok then
		if reason == "AlreadyUnlocked" then
			return false, `{def.name} ist schon frei.`
		elseif reason == "NotForSale" then
			return false, `{def.name} gibt es nicht fuer Muenzen.`
		end
		return false, `Zu wenig Muenzen: {def.name} kostet {price}.`
	end
	Profiles.markChanged(player)
	Profiles.saveSoon(player)
	return true, `Freigeschaltet: {def.name}!`
end

local function selectTrack(player: Player, id: unknown): (boolean, string)
	if type(id) ~= "string" or not Track.exists(id) then
		return false, "Diese Strecke gibt es nicht."
	end
	local def = Unlocks.find(Config.Tracks, id)
	if not Unlocks.isUnlocked(def, Profiles.get(player)) then
		return false, `{Track.displayName(id)} ist noch gesperrt.`
	end
	-- Wechsel im Hintergrund (Laden der Startgegend kann kurz dauern)
	task.spawn(function()
		RaceManager.selectTrack(player, id)
		ProgressSync.schedule(player) -- "gewaehlt" im Menue aktualisieren
	end)
	return true, `Auf zur Strecke: {Track.displayName(id)}!`
end

function TrackUnlocks.init()
	ProgressSync.addExtender(function(player, snapshot)
		snapshot.tracks = trackList(player)
	end)
	Profiles.onChanged(checkGradeUnlocks)
	Profiles.onLoaded(checkGradeUnlocks)
	Shop.addHandler("UnlockTrack", unlockTrack)
	Shop.addHandler("SelectTrack", selectTrack)
end

return TrackUnlocks
