--!strict
-- Rueckspulen, Server-Seite: Der Client meldet ("Rewind", true/false) ueber ReportStat.
-- Erlaubt nur in Studio mit Config.Debug.Rewind oder live mit Config.Rewind.EnabledLive.
-- Der RaceManager pausiert dann die Meter und markiert den Lauf (keine Bestenliste, kein Geist).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local RaceManager = require(script.Parent:WaitForChild("RaceManager"))

local reportRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ReportStat") :: RemoteEvent

local Rewind = {}

local function allowed(): boolean
	return Config.Rewind.EnabledLive or (RunService:IsStudio() and Config.Debug.Rewind)
end

function Rewind.init()
	reportRemote.OnServerEvent:Connect(function(player, kind, on)
		if kind ~= "Rewind" or type(on) ~= "boolean" or not allowed() then
			return
		end
		RaceManager.setRewinding(player, on)
	end)
end

return Rewind
