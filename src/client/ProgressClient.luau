--!strict
-- Empfaengt die Kopie des Spielstands vom Server (Muenzen, Upgrades ...) und verteilt sie an
-- UI und Abilities. Nur zur Anzeige; Entscheidungen trifft der Server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CoinsClient = require(script.Parent:WaitForChild("CoinsClient"))
local ProgressUI = require(script.Parent:WaitForChild("ProgressUI"))
local RaceUI = require(script.Parent:WaitForChild("RaceUI"))

local progressRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Progress") :: RemoteEvent

local ProgressClient = {}

export type Snapshot = {
	coins: number,
	upgrades: { [string]: number },
	unlockedTracks: { [string]: boolean },
	bestGrades: { [string]: number },
	launchRecords: { [string]: number },
	state: string, -- "Loading", "Ready", "Failed"
	storage: string, -- "DataStore" oder "Memory"
	[string]: any, -- weitere Felder (z. B. Track-Liste)
}

local snapshot: Snapshot? = nil
local listeners: { (Snapshot) -> () } = {}
local warnedState: { [string]: boolean } = {}

function ProgressClient.get(): Snapshot?
	return snapshot
end

-- `callback(snapshot)` bei jeder neuen Kopie (und sofort, falls schon eine da ist)
function ProgressClient.onChanged(callback: (Snapshot) -> ())
	table.insert(listeners, callback)
	if snapshot then
		task.spawn(callback, snapshot)
	end
end

local function onData(newSnapshot: Snapshot)
	local previous = snapshot
	-- Erste Daten oder gerade fertig geladen: Stand direkt zeigen (nicht von 0 hochzaehlen)
	local instant = previous == nil or (previous.state == "Loading" and newSnapshot.state ~= "Loading")
	snapshot = newSnapshot
	ProgressUI.setCoins(newSnapshot.coins, instant)
	if newSnapshot.state == "Failed" and not warnedState.Failed then
		warnedState.Failed = true
		RaceUI.showToast(
			"Spielstand nicht geladen - Fortschritt wird nicht gespeichert!",
			5,
			Color3.fromRGB(255, 120, 90)
		)
	elseif newSnapshot.storage == "Memory" and RunService:IsStudio() and not warnedState.Memory then
		warnedState.Memory = true
		RaceUI.showToast(
			"Studio: Speichern nur im Arbeitsspeicher (siehe Output)",
			4,
			Color3.fromRGB(255, 200, 90)
		)
	end
	for _, callback in listeners do
		task.spawn(callback, newSnapshot)
	end
end

function ProgressClient.init()
	progressRemote.OnClientEvent:Connect(function(kind: string, ...)
		if kind == "Data" then
			onData(...)
		elseif kind == "CoinRejected" then
			CoinsClient.onRejected(...)
		elseif kind == "CoinsRestored" then
			CoinsClient.restore(...)
		elseif kind == "Notice" then
			local text: string, color: Color3? = ...
			RaceUI.showToast(text, 3, color)
		end
	end)
end

return ProgressClient
