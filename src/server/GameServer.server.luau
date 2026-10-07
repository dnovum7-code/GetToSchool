--!strict
-- Einstiegspunkt auf dem Server: verbindet Spieler, Wagen und Strecke.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Achievements = require(script.Parent:WaitForChild("Achievements"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local DailySpin = require(script.Parent:WaitForChild("DailySpin"))
local Coins = require(script.Parent:WaitForChild("Coins"))
local Cosmetics = require(script.Parent:WaitForChild("Cosmetics"))
local DevTuning = require(script.Parent:WaitForChild("DevTuning"))
local Garage = require(script.Parent:WaitForChild("Garage"))
local Homework = require(script.Parent:WaitForChild("Homework"))
local Launchables = require(script.Parent:WaitForChild("Launchables"))
local Leaderboards = require(script.Parent:WaitForChild("Leaderboards"))
local Leaderstats = require(script.Parent:WaitForChild("Leaderstats"))
local PlayerEvents = require(script.Parent:WaitForChild("PlayerEvents"))
local PlayerSettings = require(script.Parent:WaitForChild("PlayerSettings"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local ProgressSync = require(script.Parent:WaitForChild("ProgressSync"))
local RaceManager = require(script.Parent:WaitForChild("RaceManager"))
local RandomEvents = require(script.Parent:WaitForChild("RandomEvents"))
local Shop = require(script.Parent:WaitForChild("Shop"))
local Track = require(script.Parent:WaitForChild("Track"))
local TrackPieces = require(script.Parent:WaitForChild("TrackPieces"))
local TrackUnlocks = require(script.Parent:WaitForChild("TrackUnlocks"))
local Tricks = require(script.Parent:WaitForChild("Tricks"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestRestart = remotes:WaitForChild("RequestRestart") :: RemoteEvent
local requestExit = remotes:WaitForChild("RequestExit") :: RemoteEvent
local requestEnter = remotes:WaitForChild("RequestEnter") :: RemoteEvent
local reportCrash = remotes:WaitForChild("ReportCrash") :: RemoteEvent
local hitLaunchable = remotes:WaitForChild("HitLaunchable") :: RemoteEvent

Players.RespawnTime = Config.Race.RespawnTime

local cartsFolder = Instance.new("Folder")
cartsFolder.Name = "Carts"
cartsFolder.Parent = workspace

Profiles.init() -- Spielstaende laden/speichern (zuerst, damit beim Beitreten geladen wird)
ProgressSync.init() -- Kopie des Spielstands an den Client (fuer die Anzeige)
Track.init(cartsFolder)
CartManager.init(cartsFolder)
CartManager.setSpawnResolver(function(player)
	return Track.getSpawn(RaceManager.getTrackId(player)) -- Start der gewaehlten Strecke
end)
RaceManager.start()
TrackPieces.init() -- getaggte Streckenbausteine einstellen
RandomEvents.init() -- Zufallsereignisse durchnummerieren
Coins.init() -- Muenzen einsammeln (Server prueft)
Launchables.init() -- Objekte zum Wegschleudern
Shop.init() -- Kaeufe pruefen
TrackUnlocks.init() -- Strecken freischalten und waehlen
Garage.init() -- Fahrzeuge kaufen und waehlen
Cosmetics.init() -- Lackiererei: Farben und Spur
Achievements.init() -- Erfolge (Popup, Badges)
PlayerSettings.init() -- Einstellungen und Einstiegs-Hinweise speichern
Tricks.init() -- Lufttricks: Muenzen fuer saubere Landungen
DailySpin.init() -- taegliches Gluecksrad und Powerups
Leaderboards.init() -- Bestenlisten (Global, Server, Freunde)
Leaderstats.init() -- Spielerliste oben rechts: Meter und Muenzen
PlayerEvents.init() -- Ereignisse (Ziel, Wurf, Drift ...) fuer Hausaufgaben und Erfolge
Homework.init() -- Hausaufgaben (taegliche Aufgaben)
DevTuning.init(cartsFolder) -- Tuning-Panel (nur in Studio aktiv)

-- Eingaben vom Client nie blind vertrauen: Der Client darf nur "bitte Neustart" sagen
-- ("Checkpoint" oder "Full"). RaceManager prueft die Art und hat einen Spam-Schutz.
requestRestart.OnServerEvent:Connect(function(player, kind)
	RaceManager.requestRestart(player, kind)
end)
-- Aus-/Einsteigen: Der Server prueft selbst, ob es erlaubt ist (sitzt er? nah genug?).
requestExit.OnServerEvent:Connect(function(player)
	RaceManager.requestExit(player)
end)
requestEnter.OnServerEvent:Connect(function(player)
	RaceManager.requestEnter(player)
end)
-- Crash-Meldung: wird nur angenommen, wenn der Spieler gerade wirklich faehrt.
reportCrash.OnServerEvent:Connect(function(player, reason)
	RaceManager.reportCrash(player, reason)
end)
-- Treffer an einem Launchable: Server prueft Abstand und plant den Flug
hitLaunchable.OnServerEvent:Connect(function(player, object)
	RaceManager.hitLaunchable(player, object)
end)

local function onCharacterAdded(player: Player, character: Model)
	CartManager.onCharacterAdded(player, character)
	-- Mit StreamingEnabled laedt der Client nur die Welt in seiner Naehe. Die Spielfigur
	-- spawnt evtl. weit weg vom Start, also die Startgegend vorher laden lassen,
	-- sonst faellt der Wagen durch noch nicht geladenen Boden.
	if workspace.StreamingEnabled then
		local ok, err = pcall(function()
			player:RequestStreamAroundAsync(Track.getSpawn(RaceManager.getTrackId(player)).Position, 3)
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
