--!strict
-- Rennablauf pro Spieler, komplett auf dem Server (autoritativ):
--   Ready    Wagen steht am Start. Die Zeit startet, sobald er die Startzone verlaesst.
--   Running  Spielzeit laeuft (ab 7:45). Erreicht der Wagen die Zielzone, ist der Lauf beendet.
--   Finished Ergebnis wird angezeigt, danach automatischer Neustart.
--   Aborted  Spieler ist waehrend des Laufs ausgestiegen: Zeit ungueltig, weiter mit R.
--
-- Checkpoints: Faehrt der Wagen waehrend des Laufs durch ein Part mit Tag "Checkpoint",
-- merken wir uns Position und Richtung. Neustart nach Crash und Taste R gehen dorthin
-- zurueck (Spielzeit laeuft weiter), Taste T startet komplett neu.
--
-- Der Server misst die Zeit selbst (os.clock) und schaut sich jeden Frame die Position
-- des Wagens an. Der Client kann also keine Zeit "melden", er bekommt sie nur gesagt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local SchoolClock = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SchoolClock"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local Track = require(script.Parent:WaitForChild("Track"))

local runState = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RunState") :: RemoteEvent

local RaceManager = {}

type Phase = "Ready" | "Running" | "Finished" | "Aborted"

type Checkpoint = {
	part: BasePart,
	cframe: CFrame, -- hier wird der Wagen beim Checkpoint-Neustart abgesetzt
	order: number?, -- Attribut "Order" (fuer die Reihenfolge), nil = beliebig
}

type RaceState = {
	phase: Phase,
	checkpoint: Checkpoint?,
	usedCheckpointRestart: boolean,
	wrongCheckpoint: Instance?, -- zuletzt gemeldeter Checkpoint in falscher Reihenfolge
	spawnPosition: Vector3,
	startTime: number, -- os.clock() beim Verlassen der Startzone
	timeScale: number, -- Spielsekunden pro echter Sekunde in diesem Lauf
	runId: number,
	bestArrival: number?, -- beste Ankunftszeit (Sekunden seit Mitternacht, Spielzeit)
	lastRestart: number,
}

-- Ergebnis eines Laufs, so wie es an den Client geht
export type RunResult = {
	arrival: number, -- Ankunft (Spielzeit, Sekunden seit Mitternacht)
	schoolTime: number,
	onTime: boolean,
	grade: number, -- 1-6, 6 = beste
	bestArrival: number,
	isNewBest: boolean,
	realTime: number, -- echte Sekunden
	noCheckpointRestart: boolean, -- ohne einen einzigen Checkpoint-Neustart geschafft
}

local races: { [Player]: RaceState } = {}

local function getRace(player: Player): RaceState
	local race = races[player]
	if not race then
		race = {
			phase = "Ready",
			checkpoint = nil,
			usedCheckpointRestart = false,
			wrongCheckpoint = nil,
			spawnPosition = Vector3.zero,
			startTime = 0,
			timeScale = Config.Clock.TimeScale,
			runId = 0,
			bestArrival = nil,
			lastRestart = -math.huge,
		}
		races[player] = race
	end
	return race
end

-- Kompletter Neustart (Taste T): Wagen an den Start, neuer Lauf, Uhr wieder auf 7:45.
function RaceManager.restart(player: Player)
	local spawnCFrame = CartManager.reset(player)
	if not spawnCFrame then
		return
	end
	local race = getRace(player)
	race.phase = "Ready"
	race.checkpoint = nil
	race.usedCheckpointRestart = false
	race.wrongCheckpoint = nil
	race.spawnPosition = spawnCFrame.Position
	race.runId += 1
	race.lastRestart = os.clock()
	runState:FireClient(player, "Reset", spawnCFrame, false)
end

-- Zurueck zum letzten Checkpoint (Taste R, nach Crash). Die Spielzeit laeuft weiter.
-- Ohne Checkpoint (oder wenn gerade kein Lauf laeuft) = kompletter Neustart.
function RaceManager.restartAtCheckpoint(player: Player)
	local race = getRace(player)
	local checkpoint = race.checkpoint
	if race.phase ~= "Running" or not checkpoint then
		RaceManager.restart(player)
		return
	end
	local cframe = CartManager.reset(player, checkpoint.cframe)
	if not cframe then
		return
	end
	race.usedCheckpointRestart = true
	race.lastRestart = os.clock()
	runState:FireClient(player, "Reset", cframe, true)
end

-- Neustart-Wunsch vom Client: "Checkpoint" (R, Crash) oder "Full" (T). Mit Spam-Schutz.
function RaceManager.requestRestart(player: Player, kind: unknown)
	local race = getRace(player)
	if os.clock() - race.lastRestart < Config.Race.MinRestartInterval then
		return
	end
	if kind == "Full" then
		RaceManager.restart(player)
	else
		RaceManager.restartAtCheckpoint(player)
	end
end

-- Faehrt der Wagen gerade durch einen Checkpoint? Dann Position und Richtung merken.
local function checkCheckpoints(player: Player, race: RaceState, base: BasePart)
	local position = base.Position
	local current = race.checkpoint
	for _, instance in Track.getCheckpoints() do
		if
			not instance:IsA("BasePart")
			or not instance:IsDescendantOf(workspace)
			or (current and current.part == instance)
			or not Track.isInZone(instance, position)
		then
			continue
		end
		local orderAttribute = instance:GetAttribute("Order")
		local order = if type(orderAttribute) == "number" then orderAttribute else nil
		local lastOrder = current and current.order
		if order and lastOrder and order < lastOrder then
			-- falsche Reihenfolge: einmal melden, nicht speichern
			if race.wrongCheckpoint ~= instance then
				race.wrongCheckpoint = instance
				runState:FireClient(player, "WrongCheckpoint")
			end
			continue
		end
		-- Richtung: dorthin, wohin der Wagen faehrt (beim Driften nicht quer abgesetzt werden)
		local velocity = base.AssemblyLinearVelocity
		local direction = Vector3.new(velocity.X, 0, velocity.Z)
		if direction.Magnitude < 5 then
			direction = Vector3.new(base.CFrame.LookVector.X, 0, base.CFrame.LookVector.Z)
		end
		if direction.Magnitude < 0.01 then
			direction = instance.CFrame.LookVector
		end
		local cframe = Track.placeOnGround(CFrame.lookAt(position, position + direction), { instance })
		race.checkpoint = { part = instance, cframe = cframe, order = order or lastOrder }
		race.wrongCheckpoint = nil
		runState:FireClient(player, "Checkpoint")
		return
	end
end

local function finish(player: Player, race: RaceState, finishZone: BasePart)
	local realTime = os.clock() - race.startTime
	local arrival = SchoolClock.startSeconds() + realTime * race.timeScale
	local isNewBest = race.bestArrival == nil or arrival < (race.bestArrival :: number)
	if isNewBest then
		race.bestArrival = arrival
	end
	race.phase = "Finished"
	local schoolTime = SchoolClock.schoolSeconds()
	local result: RunResult = {
		arrival = arrival,
		schoolTime = schoolTime,
		onTime = arrival < schoolTime,
		grade = SchoolClock.gradeFor(arrival, finishZone),
		bestArrival = race.bestArrival :: number,
		isNewBest = isNewBest,
		realTime = realTime,
		noCheckpointRestart = not race.usedCheckpointRestart,
	}
	runState:FireClient(player, "Finished", result)

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

-- Crash (vom Client gemeldet). Der Server prueft, ob der Spieler wirklich faehrt, und
-- laesst die Figur als Ragdoll herausfliegen. Den Neustart fragt der Client danach an.
function RaceManager.reportCrash(player: Player)
	if CartManager.crash(player) then
		runState:FireClient(player, "Ragdoll")
	end
end

local function updatePlayer(player: Player, race: RaceState)
	-- Sicherheitsnetz: Liegt die Figur zu lange als Ragdoll herum (z. B. Neustart-Anfrage
	-- des Clients verloren), startet der Server selbst neu.
	local ragdollTime = CartManager.getRagdollTime(player)
	if ragdollTime and ragdollTime > Config.Crash.ServerRestartTimeout then
		RaceManager.restartAtCheckpoint(player)
		return
	end

	local cart = CartManager.getCart(player)
	local base = cart and cart:FindFirstChild("Base")
	if not base or not base:IsA("BasePart") or not base:IsDescendantOf(workspace) then
		-- Wagen ist weg (z. B. ins Nichts gefallen und von Roblox geloescht)
		if cart and os.clock() - race.lastRestart > 1 then
			RaceManager.restartAtCheckpoint(player)
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
			-- Tempo der Spielzeit: Attribut an der StartZone oder Config
			race.timeScale = SchoolClock.timeScaleFor(startZone)
			runState:FireClient(player, "Started", race.timeScale)
		end
	elseif race.phase == "Running" then
		checkCheckpoints(player, race, base)
		local finishZone = Track.findZone(Config.Race.FinishZoneTag)
		if finishZone and Track.isInZone(finishZone, position) then
			finish(player, race, finishZone)
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
