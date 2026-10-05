--!strict
-- Einstiegspunkt auf dem Server.
-- Schritt b (Test): Fuer jeden Spieler erscheint ein Einkaufswagen vor seiner Spielfigur.

local Players = game:GetService("Players")

local CartBuilder = require(script.Parent:WaitForChild("CartBuilder"))

local cartsFolder = Instance.new("Folder")
cartsFolder.Name = "Carts"
cartsFolder.Parent = workspace

local carts: { [Player]: Model } = {}

local function onCharacterAdded(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local old = carts[player]
	if old then
		old:Destroy()
	end
	-- 10 Studs vor dem Spieler, leicht erhoeht, damit der Wagen auf den Boden faellt
	local spawnCFrame = root.CFrame * CFrame.new(0, 2, -10)
	local cart = CartBuilder.build(player, spawnCFrame)
	cart.Parent = cartsFolder
	carts[player] = cart
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	local cart = carts[player]
	if cart then
		cart:Destroy()
		carts[player] = nil
	end
end)
