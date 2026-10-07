--!strict
-- leaderstats: die Spielerliste oben rechts zeigt Meter (insgesamt gefahren) und Muenzen.
-- Roblox zeigt automatisch alle Werte im Ordner "leaderstats" eines Spielers an.

local Players = game:GetService("Players")

local Profiles = require(script.Parent:WaitForChild("Profiles"))

local Leaderstats = {}

local METERS = "Meter"
local COINS = "Münzen"

local function ensure(player: Player): Folder
	local folder = player:FindFirstChild("leaderstats")
	if folder and folder:IsA("Folder") then
		return folder
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "leaderstats"
	for _, name in { METERS, COINS } do
		local value = Instance.new("IntValue")
		value.Name = name
		value.Parent = newFolder
	end
	newFolder.Parent = player
	return newFolder
end

local function update(player: Player)
	if not player.Parent then
		return
	end
	local folder = ensure(player)
	local data = Profiles.get(player)
	local meters = folder:FindFirstChild(METERS)
	local coins = folder:FindFirstChild(COINS)
	if meters and meters:IsA("IntValue") then
		meters.Value = math.floor(data.stats.totalMeters)
	end
	if coins and coins:IsA("IntValue") then
		coins.Value = data.coins
	end
end

function Leaderstats.init()
	Players.PlayerAdded:Connect(ensure)
	for _, player in Players:GetPlayers() do
		ensure(player)
	end
	Profiles.onLoaded(update)
	Profiles.onChanged(update)
end

return Leaderstats
