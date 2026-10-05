--!strict
-- Rennablauf pro Spieler, komplett auf dem Server (autoritativ):
--   Ready    Wagen steht am Start. Die Zeit startet, sobald er die Startzone verlaesst.
--   Running  Zeit laeuft. Erreicht der Wagen die Zielzone, ist der Lauf beendet.
--   Finished Ergebnis wird angezeigt, danach automatischer Neustart.
--   Aborted  Spieler ist waehrend des Laufs ausgestiegen: Zeit ungueltig, weiter mit R.
--
-- Der Server misst die Zeit selbst (os.clock) und schaut sich jeden Frame die Position
-- des Wagens an. Der Client kann also keine Zeit "melden", er bekommt sie nur gesagt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local Track = require(script.Parent:WaitForChild("Track"))

local runState = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RunState") :: RemoteEvent

local RaceManager = {}

type Phase = "Ready" | "Running" | "Finished" | "Aborted"

type RaceState = {
	phase: Phase,
	spawnPosition: Vector3,
	startTime: number,
	runId: number,
	bestTime: number?,
	lastRestart: number,
}

local races: { [Player]: RaceState } = {}

local function getRace(player: Player): RaceState
	local race = races[player]
	if not race then
		race = {
			phase = "Ready",
			spawnPosition = Vector3.zero,
			startTime = 0,
			runId = 0,
			bestTime = nil,
			lastRestart = -math.huge,
		}
		races[player] = race
	end
	return race
end

-- Wagen an den Start, Lauf zuruecksetzen, Client informieren.
function RaceManager.restart(player: Player)
	local spawnCFrame = CartManager.reset(player)
	if not spawnCFrame then
		return
	end
	local race = getRace(player)
	race.phase = "Ready"
	race.spawnPosition = spawnCFrame.Position
	race.runId += 1
	race.lastRestart = os.clock()
	runState:FireClient(player, "Reset", spawnCFrame)
end

-- Neustart-Wunsch vom Client: nur mit Spam-Schutz erlauben.
function RaceManager.requestRestart(player: Player)
	local race = getRace(player)
	if os.clock() - race.lastRestart < Config.Race.MinRestartInterval then
		return
	end
	RaceManager.restart(player)
end

local function finish(player: Player, race: RaceState)
	local time = os.clock() - race.startTime
	local isNewBest = race.bestTime == nil or time < (race.bestTime :: number)
	if isNewBest then
		race.bestTime = time
	end
	race.phase = "Finished"
	runState:FireClient(player, "Finished", time, race.bestTime, isNewBest)

	local delay = Config.Race.AutoRestartAfterFinish
	if delay > 0 then
		local runId = race.runId
		task.delay(delay, function()
			-- nur, wenn der Spieler nicht inzwischen selbst neu gestartet hat
			if races[player] == race and race.runId == runId and race.phase == "Finished" then
				RaceManager.restart(player)
			end
		end)
	end
end

-- Aussteigen (vom Client gewuenscht, vom CartManager geprueft).
function RaceManager.requestExit(player: Player)
	local landing = CartManager.exit(player)
	if not landing then
		return
	end
	local race = getRace(player)
	if race.phase == "Running" or race.phase == "Finished" then
		-- Wer aussteigt, hat keinen gueltigen Lauf mehr (und kein Auto-Neustart nach dem Ziel)
		race.phase = "Aborted"
		runState:FireClient(player, "Aborted")
	end
	runState:FireClient(player, "Exited", landing)
end

function RaceManager.requestEnter(player: Player)
	CartManager.enter(player)
end

local function updatePlayer(player: Player, race: RaceState)
	local cart = CartManager.getCart(player)
	local base = cart and cart:FindFirstChild("Base")
	if not base or not base:IsA("BasePart") or not base:IsDescendantOf(workspace) then
		-- Wagen ist weg (z. B. ins Nichts gefallen und von Roblox geloescht)
		if cart and os.clock() - race.lastRestart > 1 then
			RaceManager.restart(player)
		end
		return
	end
	-- Zonen zaehlen nur, wenn der Spieler wirklich im Wagen sitzt
	-- (ein leerer Wagen, der ins Ziel rollt, gewinnt nichts).
	if not CartManager.isSeated(player) then
		return
	end
	local position = base.Position

	if race.phase == "Ready" then
		-- Kurz nach dem Neustart koennen vom Client noch alte Positionen (von vor dem
		-- Zuruecksetzen) ankommen. Die ignorieren wir, sonst startet die Zeit zu frueh.
		if os.clock() - race.lastRestart < Config.Race.StartGrace then
			return
		end
		local startZone = Track.findZone(Config.Race.StartZoneTag)
		local leftStart = if startZone
			then not Track.isInZone(startZone, position)
			else (position - race.spawnPosition).Magnitude > Config.Race.StartDistanceWithoutZone
		if leftStart then
			race.phase = "Running"
			race.startTime = os.clock()
			runState:FireClient(player, "Started")
		end
	elseif race.phase == "Running" then
		local finishZone = Track.findZone(Config.Race.FinishZoneTag)
		if finishZone and Track.isInZone(finishZone, position) then
			finish(player, race)
		end
	end
end

function RaceManager.start()
	RunService.Heartbeat:Connect(function()
		for player, race in races do
			if player.Parent then
				updatePlayer(player, race)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		races[player] = nil
	end)
end

return RaceManager
