--!strict
-- Einstiegspunkt auf dem Server: verbindet Spieler, Wagen und Strecke.

local Players = game:GetService("Players")

local CartManager = require(script.Parent:WaitForChild("CartManager"))
local Track = require(script.Parent:WaitForChild("Track"))

local cartsFolder = Instance.new("Folder")
cartsFolder.Name = "Carts"
cartsFolder.Parent = workspace

Track.init(cartsFolder)
CartManager.init(cartsFolder)
CartManager.setSpawnResolver(function(_player)
	return Track.getFallbackSpawn()
end)

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		CartManager.onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(CartManager.onCharacterAdded, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
