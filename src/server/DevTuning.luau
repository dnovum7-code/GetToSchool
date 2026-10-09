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

-- Eintrag im Tuning-Panel mit server = true suchen (nur die darf der Client setzen)
local function findServerItem(path: string): Config.TuningItem?
	for _, section in Config.TuningPanel do
		for _, item in section.items do
			if item.server and item.path == path then
				return item
			end
		end
	end
	return nil
end

-- "A.B.C" -> Tabelle Config.A.B und Schluessel "C"
local function resolvePath(path: string): (any, string?)
	local parts = string.split(path, ".")
	local holder: any = Config
	for i = 1, #parts - 1 do
		holder = if type(holder) == "table" then holder[parts[i]] else nil
	end
	if type(holder) ~= "table" or #parts < 2 then
		return nil, nil
	end
	return holder, parts[#parts]
end

function DevTuning.init(cartsFolder: Folder)
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DevTuning") :: RemoteEvent
	remote.OnServerEvent:Connect(function(_player, path: unknown, value: unknown)
		if not RunService:IsStudio() then
			return
		end
		if type(path) ~= "string" then
			return
		end
		-- Nur Eintraege aus dem Tuning-Panel mit server = true
		local item = findServerItem(path)
		if not item then
			return
		end
		local holder, key = resolvePath(path)
		if not holder or not key then
			return
		end
		if item.switch then
			if type(value) == "boolean" and type(holder[key]) == "boolean" then
				holder[key] = value
			end
			return
		end
		if type(value) ~= "number" or value ~= value or math.abs(value) > MAX_ABS_VALUE then
			return -- NaN / Unsinn abfangen
		end
		if type(holder[key]) ~= "number" then
			return
		end
		holder[key] = value
		if path == "Cart.BallastHeight" then
			for _, cart in cartsFolder:GetChildren() do
				if cart:IsA("Model") then
					CartBuilder.applyBallastHeight(cart)
				end
			end
		end
	end)
end

return DevTuning
