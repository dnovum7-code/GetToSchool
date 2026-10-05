--!strict
-- Einstiegspunkt auf dem Server: verbindet Spieler, Wagen und Strecke.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local Track = require(script.Parent:WaitForChild("Track"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestRestart = remotes:WaitForChild("RequestRestart") :: RemoteEvent
local runState = remotes:WaitForChild("RunState") :: RemoteEvent

Players.RespawnTime = Config.Race.RespawnTime

local cartsFolder = Instance.new("Folder")
cartsFolder.Name = "Carts"
cartsFolder.Parent = workspace

Track.init(cartsFolder)
CartManager.init(cartsFolder)
CartManager.setSpawnResolver(function(_player)
	return Track.getFallbackSpawn()
end)

local lastRestart: { [Player]: number } = {}

-- Neustart: Wagen an den Start, Client informieren (er setzt Tempo und Kamera zurueck).
local function restart(player: Player)
	local spawnCFrame = CartManager.reset(player)
	if spawnCFrame then
		lastRestart[player] = os.clock()
		runState:FireClient(player, "Reset", spawnCFrame)
	end
end

-- Eingaben vom Client nie blind vertrauen: hier nur "bitte Neustart", mit Spam-Schutz.
requestRestart.OnServerEvent:Connect(function(player)
	local last = lastRestart[player]
	if last and os.clock() - last < Config.Race.MinRestartInterval then
		return
	end
	restart(player)
end)

local function onCharacterAdded(player: Player, character: Model)
	CartManager.onCharacterAdded(player, character)
	if player.Character == character then
		restart(player)
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

Players.PlayerRemoving:Connect(function(player)
	lastRestart[player] = nil
end)
