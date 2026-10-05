--!strict
-- Rennablauf pro Spieler, komplett auf dem Server (autoritativ):
--   Ready    Wagen steht am Start. Die Zeit startet, sobald er die Startzone verlaesst.
--   Running  Zeit laeuft (ab 0:00.00). Erreicht der Wagen die Zielzone, ist der Lauf beendet.
--   Finished Ergebnis wird angezeigt, danach automatischer Neustart.
--   Aborted  Spieler ist waehrend des Laufs ausgestiegen: Zeit ungueltig, weiter mit R.
--
-- Checkpoints: Faehrt der Wagen waehrend des Laufs durch ein Part mit Tag "Checkpoint",
-- merken wir uns Position und Richtung. Neustart nach Crash und Taste R gehen dorthin
-- zurueck (Zeit laeuft weiter), Taste T startet komplett neu. An jedem Checkpoint bekommt
-- der Spieler den Abstand zu seiner Bestzeit (Zwischenzeit) angezeigt.
--
-- Der Server misst die Zeit selbst (os.clock) und schaut sich jeden Frame die Position
-- des Wagens an. Der Client kann also keine Zeit "melden", er bekommt sie nur gesagt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Economy =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"):WaitForChild("Economy"))
local RaceTime = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RaceTime"))
local BestTimes = require(script.Parent:WaitForChild("BestTimes"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local Coins = require(script.Parent:WaitForChild("Coins"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local RandomEvents = require(script.Parent:WaitForChild("RandomEvents"))
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
	trackId: string, -- fuer welchen Track die Bestzeit gilt
	splits: { [string]: number }, -- Zwischenzeiten dieses Laufs (Checkpoint -> Sekunden)
	runId: number,
	lastRestart: number,
}

-- Ergebnis eines Laufs, so wie es an den Client geht
export type RunResult = {
	time: number, -- Fahrzeit in Sekunden
	bestTime: number, -- Bestzeit (nach diesem Lauf)
	previousBest: number?, -- Bestzeit vor diesem Lauf (nil = erster Lauf)
	isNewBest: boolean,
	grade: number, -- 1-6, 6 = beste
	noCheckpointRestart: boolean, -- ohne einen einzigen Checkpoint-Neustart geschafft
	coinsReward: number, -- Belohnung im Ziel (gesamt)
	coinsBase: number, -- davon Grundbetrag
	coinsGradeBonus: number, -- davon Notenbonus
	coinsCollected: number, -- in diesem Lauf eingesammelte Muenzen
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
			trackId = Config.Race.DefaultTrackId,
			splits = {},
			runId = 0,
			lastRestart = -math.huge,
		}
		races[player] = race
	end
	return race
end

-- Welcher Track? Attribut "TrackId" an der StartZone, sonst Config.Race.DefaultTrackId
local function currentTrackId(): string
	local startZone = Track.findZone(Config.Race.StartZoneTag)
	local id = startZone and startZone:GetAttribute("TrackId")
	return if type(id) == "string" and id ~= "" then id else Config.Race.DefaultTrackId
end

-- Bestzeit des Spielers fuer seinen aktuellen Track an den Client schicken (fuer die Anzeige)
local function sendBest(player: Player, race: RaceState)
	local best = BestTimes.get(player, race.trackId)
	runState:FireClient(player, "Best", if best then best.time else nil)
end

-- Kompletter Neustart (Taste T): Wagen an den Start, neuer Lauf, Zeit wieder auf 0.
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
	race.trackId = currentTrackId()
	race.splits = {}
	race.runId += 1
	race.lastRestart = os.clock()
	Coins.resetRun(player) -- Muenzen erscheinen wieder (die eingesammelten behaelt man)
	-- Neuer Lauf: Zufallsereignisse neu wuerfeln (vor "Reset", damit die Strecke steht)
	runState:FireClient(player, "Events", RandomEvents.roll())
	runState:FireClient(player, "Reset", spawnCFrame, false)
	sendBest(player, race)
end

-- Zurueck zum letzten Checkpoint (Taste R, nach Crash). Die Zeit laeuft weiter.
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

		-- Zwischenzeit: beim ersten Durchfahren in diesem Lauf mit der Bestzeit vergleichen
		local key = instance:GetFullName()
		local elapsed = os.clock() - race.startTime
		local delta: number? = nil
		if race.splits[key] == nil then
			race.splits[key] = elapsed
			local best = BestTimes.get(player, race.trackId)
			local bestSplit = best and best.splits[key]
			if bestSplit then
				delta = elapsed - bestSplit
			end
		end
		runState:FireClient(player, "Checkpoint", elapsed, delta)
		return
	end
end

local function finish(player: Player, race: RaceState, finishZone: BasePart)
	local time = os.clock() - race.startTime
	race.phase = "Finished"
	local isNewBest, previousBest = BestTimes.submit(player, race.trackId, time, race.splits)
	local grade = RaceTime.gradeFor(time, finishZone)

	-- Belohnung: Grundbetrag plus Bonus je nach Note
	local reward, rewardBase, gradeBonus = Economy.finishReward(grade, Config.Coins)
	local data = Profiles.get(player)
	data.bestGrades[race.trackId] = math.max(data.bestGrades[race.trackId] or 0, grade)
	data.stats.finishedRuns += 1
	Profiles.addCoins(player, reward) -- speichert und meldet die Aenderung

	local result: RunResult = {
		time = time,
		bestTime = if isNewBest or not previousBest then time else previousBest,
		previousBest = previousBest,
		isNewBest = isNewBest,
		grade = grade,
		noCheckpointRestart = not race.usedCheckpointRestart,
		coinsReward = reward,
		coinsBase = rewardBase,
		coinsGradeBonus = gradeBonus,
		coinsCollected = Coins.getRunTotal(player),
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
			runState:FireClient(player, "Started")
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
	-- Sobald der Spielstand geladen ist, die Bestzeit anzeigen
	Profiles.onLoaded(function(player)
		local race = races[player]
		if race then
			sendBest(player, race)
		end
	end)
end

return RaceManager
