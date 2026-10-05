--!strict
-- Schickt dem Client eine Kopie seines Spielstands (Muenzen, Upgrades ...) fuer UI und
-- Abilities. Nur zur Anzeige: Entscheidungen trifft immer der Server.
-- Mehrere Aenderungen im selben Frame werden zu einer Nachricht zusammengefasst.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Profiles = require(script.Parent:WaitForChild("Profiles"))

local progressRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Progress") :: RemoteEvent

local ProgressSync = {}

local scheduled: { [Player]: boolean } = {}
-- Weitere Felder (z. B. Track-Liste), von anderen Modulen ergaenzt
local extenders: { (player: Player, snapshot: { [string]: any }) -> () } = {}

function ProgressSync.snapshot(player: Player): { [string]: any }
	local data = Profiles.get(player)
	local snapshot: { [string]: any } = {
		coins = data.coins,
		upgrades = table.clone(data.upgrades),
		unlockedTracks = table.clone(data.unlockedTracks),
		bestGrades = table.clone(data.bestGrades),
		launchRecords = table.clone(data.launchRecords),
		state = Profiles.getState(player),
		storage = Profiles.getBackendName(),
	}
	for _, extend in extenders do
		extend(player, snapshot)
	end
	return snapshot
end

-- Spielstand demnaechst (am Ende dieses Frames) an den Client schicken
function ProgressSync.schedule(player: Player)
	if scheduled[player] then
		return
	end
	scheduled[player] = true
	task.defer(function()
		scheduled[player] = nil
		if player.Parent then
			progressRemote:FireClient(player, "Data", ProgressSync.snapshot(player))
		end
	end)
end

-- `extend(player, snapshot)` darf dem Snapshot weitere Felder hinzufuegen
function ProgressSync.addExtender(extend: (player: Player, snapshot: { [string]: any }) -> ())
	table.insert(extenders, extend)
end

-- Kurze Meldung beim Client anzeigen (z. B. "Neuer Track freigeschaltet!")
function ProgressSync.notice(player: Player, text: string, color: Color3?)
	progressRemote:FireClient(player, "Notice", text, color)
end

function ProgressSync.init()
	Profiles.onChanged(ProgressSync.schedule)
	Profiles.onLoaded(ProgressSync.schedule)
	local function onPlayerAdded(player: Player)
		-- Erste Daten (noch vorlaeufig), bis der Spielstand geladen ist
		task.delay(1, ProgressSync.schedule, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		scheduled[player] = nil
	end)
end

return ProgressSync
