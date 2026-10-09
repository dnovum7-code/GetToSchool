--!strict
-- Einstellungen und gesehene Einstiegs-Hinweise speichern (im Spielstand). Der Client schickt
-- ("Set", Name, Wert); der Server prueft Name und Typ
-- (SaveData.validateSetting) und speichert. Zurueck an den Client gehen sie im Snapshot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SaveData = require(Shared:WaitForChild("Progression"):WaitForChild("SaveData"))
local DayClock = require(script.Parent:WaitForChild("DayClock"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local ProgressSync = require(script.Parent:WaitForChild("ProgressSync"))

local settingsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Settings") :: RemoteEvent

local PlayerSettings = {}

local MAX_PER_SECOND = 30 -- Spam-Schutz (normale Klicks gehen nie verloren)
type Window = { start: number, count: number }
local window: { [Player]: Window } = {}

function PlayerSettings.init()
	settingsRemote.OnServerEvent:Connect(function(player, kind, key, value)
		local now = os.clock()
		local current: Window = window[player] or { start = now, count = 0 }
		if now - current.start >= 1 then
			current = { start = now, count = 0 }
		end
		window[player] = current
		current.count += 1
		if current.count > MAX_PER_SECOND then
			return
		end
		local data = Profiles.get(player)
		if kind == "Set" then
			local ok, clean = SaveData.validateSetting(key, value)
			if ok and (data.settings :: any)[key] ~= clean then
				(data.settings :: any)[key] = clean
				Profiles.markChanged(player)
			end
		elseif kind == "DebugNextDay" then
			-- nur Studio + Config.Debug.DayTravel (DayClock prueft das)
			if DayClock.advance() then
				for _, other in Players:GetPlayers() do
					ProgressSync.schedule(other)
				end
			end
		end
	end)
	ProgressSync.addExtender(function(player, snapshot)
		local data = Profiles.get(player)
		snapshot.settings = table.clone(data.settings)
	end)
	Players.PlayerRemoving:Connect(function(player)
		window[player] = nil
	end)
end

return PlayerSettings
