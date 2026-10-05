--!strict
-- Server-Seite des Tuning-Panels: uebernimmt Werte, die der Server braucht (z. B. die
-- Ballast-Hoehe, weil der Server den Wagen baut).
-- Funktioniert NUR in Studio. In einem veroeffentlichten Spiel wird jede Anfrage ignoriert,
-- damit Spieler keine Werte verstellen koennen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local TuningSliders = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TuningSliders"))
local CartBuilder = require(script.Parent:WaitForChild("CartBuilder"))

local DevTuning = {}

function DevTuning.init(cartsFolder: Folder)
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DevTuning") :: RemoteEvent
	remote.OnServerEvent:Connect(function(_player, section: unknown, key: unknown, value: unknown)
		if not RunService:IsStudio() then
			return
		end
		if type(section) ~= "string" or type(key) ~= "string" or type(value) ~= "number" then
			return
		end
		if value ~= value then -- NaN abfangen
			return
		end
		-- Nur Werte aus der Regler-Liste, die der Server braucht, und nur im erlaubten Bereich
		for _, slider in TuningSliders do
			if slider.server and slider.section == section and slider.key == key then
				local clamped = math.clamp(value, slider.min, slider.max)
				local sectionTable: any = (Config :: any)[section]
				sectionTable[key] = clamped
				if section == "Cart" and key == "BallastHeight" then
					for _, cart in cartsFolder:GetChildren() do
						if cart:IsA("Model") then
							CartBuilder.applyBallastHeight(cart)
						end
					end
				end
				return
			end
		end
	end)
end

return DevTuning
