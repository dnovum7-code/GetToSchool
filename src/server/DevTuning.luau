--!strict
-- Server-Seite des Tuning-Panels: uebernimmt Werte, die der Server braucht (z. B. die
-- Ballast-Hoehe, weil der Server den Wagen baut).
-- Funktioniert NUR in Studio. In einem veroeffentlichten Spiel wird jede Anfrage ignoriert,
-- damit Spieler keine Werte verstellen koennen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CartBuilder = require(script.Parent:WaitForChild("CartBuilder"))

local DevTuning = {}

-- Groesster erlaubter Betrag (nur Schutz gegen Tippfehler wie 1e30)
local MAX_ABS_VALUE = 1e6

function DevTuning.init(cartsFolder: Folder)
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DevTuning") :: RemoteEvent
	remote.OnServerEvent:Connect(function(_player, path: unknown, value: unknown)
		if not RunService:IsStudio() then
			return
		end
		if type(path) ~= "string" or type(value) ~= "number" then
			return
		end
		if value ~= value or math.abs(value) > MAX_ABS_VALUE then -- NaN / Unsinn abfangen
			return
		end
		-- Nur Werte aus der Regler-Liste, die der Server braucht
		for _, entry in (Config :: any).TuningPanel do
			if entry.server and entry.path == path then
				local section, key = string.match(path, "^(%w+)%.(%w+)$")
				local sectionTable = section and (Config :: any)[section]
				if type(sectionTable) ~= "table" or type(sectionTable[key]) ~= "number" then
					return
				end
				sectionTable[key] = value
				if path == "Cart.BallastHeight" then
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
