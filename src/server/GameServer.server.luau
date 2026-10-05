--!strict
-- Einstiegspunkt auf dem Server: verbindet Spieler, Wagen und Strecke.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local RaceManager = require(script.Parent:WaitForChild("RaceManager"))
local Track = require(script.Parent:WaitForChild("Track"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestRestart = remotes:WaitForChild("RequestRestart") :: RemoteEvent

Players.RespawnTime = Config.Race.RespawnTime

local cartsFolder = Instance.new("Folder")
cartsFolder.Name = "Carts"
cartsFolder.Parent = workspace

Track.init(cartsFolder)
CartManager.init(cartsFolder)
CartManager.setSpawnResolver(function(_player)
	return Track.getSpawn()
end)
RaceManager.start()

-- Eingaben vom Client nie blind vertrauen: Der Client darf nur "bitte Neustart" sagen.
-- Argumente werden ignoriert, der Spam-Schutz steckt in RaceManager.requestRestart.
requestRestart.OnServerEvent:Connect(function(player)
	RaceManager.requestRestart(player)
end)

local function onCharacterAdded(player: Player, character: Model)
	CartManager.onCharacterAdded(player, character)
	-- Mit StreamingEnabled laedt der Client nur die Welt in seiner Naehe. Die Spielfigur
	-- spawnt evtl. weit weg vom Start, also die Startgegend vorher laden lassen,
	-- sonst faellt der Wagen durch noch nicht geladenen Boden.
	if workspace.StreamingEnabled then
		local ok, err = pcall(function()
			player:RequestStreamAroundAsync(Track.getSpawn().Position, 3)
		end)
		if not ok then
			warn("[GameServer] RequestStreamAroundAsync fehlgeschlagen:", err)
		end
	end
	if player.Character == character then
		RaceManager.restart(player)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
