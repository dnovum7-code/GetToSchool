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
local RunRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"):WaitForChild("RunRules"))
local RunValidation = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"):WaitForChild("RunValidation")
)
local RaceTime = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RaceTime"))
local BestTimes = require(script.Parent:WaitForChild("BestTimes"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local Coins = require(script.Parent:WaitForChild("Coins"))
local Ghosts = require(script.Parent:WaitForChild("Ghosts"))
local Homework = require(script.Parent:WaitForChild("Homework"))
local Leaderboards = require(script.Parent:WaitForChild("Leaderboards"))
local Launchables = require(script.Parent:WaitForChild("Launchables"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local RandomEvents = require(script.Parent:WaitForChild("RandomEvents"))
local Track = require(script.Parent:WaitForChild("Track"))

local runState = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RunState") :: RemoteEvent

local RaceManager = {}

type Phase = "Ready" | "Running" | "Finished" | "Aborted" | "GameOver"

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
	life: RunRules.LifeState, -- Leben und Helm-Ladungen in diesem Lauf
	hits: number, -- getroffene Objekte (Launchables) in diesem Lauf
	bestFlight: { name: string, meters: number }?, -- weitester Flug in diesem Lauf
	visits: { RunValidation.Visit }, -- Checkpoints in diesem Lauf (fuer die Plausibilitaet)
	startPosition: Vector3, -- wo der Wagen die Startzone verlassen hat
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
	lives: number, -- verbleibende Leben
	maxLives: number,
	hits: number, -- getroffene Objekte
	bestFlightName: string?, -- weitester Flug in diesem Lauf (z. B. "Kuh") ...
	bestFlightMeters: number?, -- ... und wie weit
	leaderboardNote: string?, -- Lauf zaehlt nicht fuer die globale Bestenliste: warum
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
			trackId = Track.defaultTrackId(),
			splits = {},
			runId = 0,
			lastRestart = -math.huge,
			life = RunRules.newRun(Config.Lives.PerRun, 0),
			hits = 0,
			bestFlight = nil,
			visits = {},
			startPosition = Vector3.zero,
		}
		races[player] = race
	end
	return race
end

-- Gewaehlte Strecke des Spielers (fuer Startposition, Zonen, Bestzeit)
function RaceManager.getTrackId(player: Player): string
	return getRace(player).trackId
end

-- Bestzeit des Spielers fuer seinen aktuellen Track an den Client schicken (fuer die Anzeige)
local function sendBest(player: Player, race: RaceState)
	local best = BestTimes.get(player, race.trackId)
	runState:FireClient(player, "Best", if best then best.time else nil)
end

-- Helm-Ladungen je nach gekaufter Stufe (Upgrade "Helmet")
local function maxShieldFor(player: Player): number
	local def = Economy.findUpgrade(Config.Upgrades, "Helmet")
	if not def then
		return 0
	end
	-- Config.Debug.AllUpgrades: in Studio alle Upgrades auf hoechster Stufe (zum Testen)
	local allMax = Config.Debug.AllUpgrades and RunService:IsStudio()
	local level = Economy.effectiveLevel(Profiles.get(player).upgrades, def, allMax)
	return math.max(0, math.floor(RunRules.levelValue(Config.Abilities, "HelmetCharges", level, 0)))
end

-- Leben und Helm an den Client schicken (Anzeige)
local function sendLives(player: Player, race: RaceState)
	local life = race.life
	runState:FireClient(player, "Lives", life.lives, life.maxLives, life.shield, life.maxShield)
end

-- Kompletter Neustart (Taste T): Wagen an den Start, neuer Lauf, Zeit wieder auf 0.
function RaceManager.restart(player: Player)
	local race = getRace(player)
	-- Gewaehlte Strecke gibt es nicht (mehr)? Dann die Standard-Strecke
	if not Track.exists(race.trackId) then
		race.trackId = Track.defaultTrackId()
	end
	local spawnCFrame = CartManager.reset(player)
	if not spawnCFrame then
		return
	end
	race.phase = "Ready"
	race.checkpoint = nil
	race.usedCheckpointRestart = false
	race.wrongCheckpoint = nil
	race.spawnPosition = spawnCFrame.Position
	race.splits = {}
	race.visits = {}
	race.runId += 1
	race.lastRestart = os.clock()
	Coins.resetRun(player) -- Lauf-Summe auf 0 (Muenzen erscheinen erst nach dem Ziel wieder)
	race.life = RunRules.newRun(Config.Lives.PerRun, maxShieldFor(player)) -- Leben wieder voll
	race.hits = 0
	race.bestFlight = nil
	Launchables.resetRun(player) -- umgeschleuderte Objekte stehen wieder
	-- Neuer Lauf: Zufallsereignisse neu wuerfeln (vor "Reset", damit die Strecke steht)
	runState:FireClient(player, "Events", RandomEvents.roll())
	runState:FireClient(player, "Reset", spawnCFrame, false)
	sendBest(player, race)
	sendLives(player, race)
	Ghosts.cancel(player)
	Ghosts.announce(player, race.trackId) -- Geist dieser Strecke an den Client
end

-- Zurueck zum letzten Checkpoint (Taste R, nach Crash). Die Zeit laeuft weiter, Leben und
-- eingesammelte Muenzen bleiben. Ohne Checkpoint geht es zurueck an den Start (Zeit laeuft
-- trotzdem weiter). Nach dem Ziel oder Abbruch: kompletter Neustart (neuer Lauf).
function RaceManager.restartAtCheckpoint(player: Player)
	local race = getRace(player)
	if race.phase == "GameOver" then
		return -- der Game-Over-Screen laeuft; danach startet der Server selbst neu
	end
	if race.phase ~= "Running" and race.phase ~= "Ready" then
		RaceManager.restart(player)
		return
	end
	local checkpoint = race.checkpoint
	local cframe = CartManager.reset(player, if checkpoint then checkpoint.cframe else nil)
	if not cframe then
		return
	end
	if checkpoint then
		race.usedCheckpointRestart = true
	end
	race.lastRestart = os.clock()
	runState:FireClient(player, "Reset", cframe, true)
end

-- Game Over (0 Leben): lustiger Screen beim Client, dann kompletter Neustart
local function gameOver(player: Player, race: RaceState)
	Ghosts.cancel(player)
	local wasRunning = race.phase == "Running"
	race.phase = "GameOver"
	local runId = race.runId
	runState:FireClient(player, "GameOver", {
		hits = race.hits,
		coins = Coins.getRunTotal(player),
		time = if wasRunning then os.clock() - race.startTime else nil,
	})
	task.delay(Config.Lives.GameOverTime, function()
		if races[player] == race and race.runId == runId and race.phase == "GameOver" then
			RaceManager.restart(player)
		end
	end)
end

-- Crash oder Treffer: kostet ein Leben (oder eine Helm-Ladung). Zaehlt nur waehrend eines
-- Laufs (vor dem Start und waehrend der Fahrt). Rueckgabe: "Shielded", "LifeLost",
-- "GameOver" (siehe RunRules.applyHit) oder nil.
function RaceManager.applyHit(player: Player): string?
	local race = getRace(player)
	if race.phase ~= "Ready" and race.phase ~= "Running" then
		return nil
	end
	local outcome: string = RunRules.applyHit(race.life)
	sendLives(player, race)
	if outcome == "GameOver" then
		gameOver(player, race)
	end
	return outcome
end

-- Treffer an einem Launchable (vom Client gemeldet). Der Server prueft und plant den Flug,
-- zieht ein Leben ab (der Wagen faehrt aber weiter) und schickt dem Client den Flug.
function RaceManager.hitLaunchable(player: Player, object: unknown)
	local info = Launchables.tryLaunch(player, object)
	if not info then
		runState:FireClient(player, "LaunchRejected", object)
		return
	end
	local race = getRace(player)
	race.hits += 1
	local best = race.bestFlight
	if not best or info.meters > best.meters then
		race.bestFlight = { name = info.name, meters = info.meters }
	end
	runState:FireClient(player, "Launch", object, info)
	local outcome = RaceManager.applyHit(player)
	-- Letztes Leben weg: Figur fliegt auch noch hinterher
	if outcome == "GameOver" and CartManager.crash(player) then
		runState:FireClient(player, "Ragdoll")
	end
end

-- Andere Strecke waehlen (geprueft wird vorher: frei? ausserhalb eines Laufs?):
-- Spieler wird an deren Start gesetzt, neuer Lauf.
function RaceManager.selectTrack(player: Player, trackId: string)
	-- Mit StreamingEnabled die neue Startgegend vorher laden lassen (sonst faellt der Wagen
	-- durch noch nicht geladenen Boden). Die Strecke wird erst danach umgestellt, sonst
	-- wuerde der Wagen (noch am alten Start) als "aus der neuen Startzone gefahren" gelten.
	if workspace.StreamingEnabled then
		pcall(function()
			player:RequestStreamAroundAsync(Track.getSpawn(trackId).Position, 3)
		end)
	end
	if player.Parent and RaceManager.isOutsideRun(player) then
		getRace(player).trackId = trackId
		RaceManager.restart(player)
	end
end

-- Ist der Spieler gerade ausserhalb eines Laufs (Shop, Track-Wahl erlaubt)?
-- Erlaubt: am Start vor dem Losfahren, nach dem Ziel, nach einem Abbruch.
function RaceManager.isOutsideRun(player: Player): boolean
	local phase = getRace(player).phase
	return phase == "Ready" or phase == "Finished" or phase == "Aborted"
end

-- Helm-Stufe hat sich geaendert (Kauf): Ladungen neu berechnen
function RaceManager.refreshShield(player: Player)
	local race = getRace(player)
	race.life.maxShield = maxShieldFor(player)
	race.life.shield = race.life.maxShield
	sendLives(player, race)
end

-- Neustart-Wunsch vom Client: "Checkpoint" (R, Crash) oder "Full" (T). Mit Spam-Schutz.
function RaceManager.requestRestart(player: Player, kind: unknown)
	local race = getRace(player)
	if os.clock() - race.lastRestart < Config.Race.MinRestartInterval then
		return
	end
	if race.phase == "GameOver" and kind ~= "Full" then
		return -- R waehrend Game Over: nichts; T startet sofort neu
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
	for _, instance in Track.getCheckpoints(race.trackId) do
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
		-- Neuer Checkpoint: Fahrradhelm laedt sich wieder auf
		if RunRules.rechargeShield(race.life) then
			sendLives(player, race)
		end

		-- Zwischenzeit: beim ersten Durchfahren in diesem Lauf mit der Bestzeit vergleichen
		local key = instance:GetFullName()
		local elapsed = os.clock() - race.startTime
		local delta: number? = nil
		if race.splits[key] == nil then
			race.splits[key] = elapsed
			table.insert(race.visits, {
				key = key,
				order = order,
				at = elapsed,
				position = { position.X, position.Y, position.Z },
			})
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

-- Checkpoints der Strecke fuer die Plausibilitaet. Optional: Attribut Optional = true oder
-- in einem RandomEvent (der Server weiss nicht, ob es beim Spieler aktiv war).
local function trackCheckpoints(trackId: string): { RunValidation.TrackCheckpoint }
	local result = {}
	for _, instance in Track.getCheckpoints(trackId) do
		if not instance:IsA("BasePart") or not instance:IsDescendantOf(workspace) then
			continue
		end
		local optional = instance:GetAttribute("Optional") == true
		local ancestor: Instance? = instance
		while ancestor and ancestor ~= workspace and not optional do
			optional = ancestor:HasTag("RandomEvent")
			ancestor = ancestor.Parent
		end
		local order = instance:GetAttribute("Order")
		table.insert(result, {
			key = instance:GetFullName(),
			order = if type(order) == "number" then order else nil,
			optional = optional,
		})
	end
	return result
end

local function minTimeFor(trackId: string): number
	for _, def in Config.Tracks do
		if def.id == trackId and type(def.minTime) == "number" then
			return def.minTime
		end
	end
	return Config.Leaderboard.MinTime
end

-- Lauf plausibel? Dann in die globale Bestenliste. Sonst: Grund fuer die Anzeige.
local function submitToLeaderboard(player: Player, race: RaceState, time: number, position: Vector3): string?
	local LB = Config.Leaderboard
	local ok, reason = RunValidation.check(
		{
			time = time,
			startPosition = { race.startPosition.X, race.startPosition.Y, race.startPosition.Z },
			finishPosition = { position.X, position.Y, position.Z },
			visits = race.visits,
		},
		trackCheckpoints(race.trackId),
		{
			minTime = minTimeFor(race.trackId),
			minGap = LB.MinCheckpointGap,
			maxSpeed = LB.MaxSpeed,
		}
	)
	if ok then
		Leaderboards.submitTime(player, race.trackId, time)
		return nil
	end
	local text = RunValidation.REASONS[reason or ""] or "unplausibel"
	return `Nicht in der Bestenliste: {text}`
end

local function finish(player: Player, race: RaceState, finishZone: BasePart, position: Vector3)
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
		lives = race.life.lives,
		maxLives = race.life.maxLives,
		hits = race.hits,
		bestFlightName = if race.bestFlight then race.bestFlight.name else nil,
		bestFlightMeters = if race.bestFlight then race.bestFlight.meters else nil,
		leaderboardNote = submitToLeaderboard(player, race, time, position),
	}
	runState:FireClient(player, "Finished", result)
	-- Ziel erreicht: die eingesammelten Muenzen dieser Strecke erscheinen wieder
	Coins.restoreTrack(player, race.trackId)
	-- Neue Bestzeit: Aufnahme wird der neue Geist
	Ghosts.finish(player, race.trackId, isNewBest, time)
	Homework.report(player, {
		type = "Finish",
		trackId = race.trackId,
		time = time,
		grade = grade,
		livesLost = math.max(0, race.life.maxLives - race.life.lives),
	})

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
		Ghosts.cancel(player)
		runState:FireClient(player, "Aborted")
	end
	runState:FireClient(player, "Exited", landing)
end

function RaceManager.requestEnter(player: Player)
	CartManager.enter(player)
end

local CRASH_REASONS = { Tipped = true, Impact = true, Fell = true, Hazard = true, HitHazard = true }

-- Crash (vom Client gemeldet, mit Grund). Der Server prueft, ob der Spieler wirklich faehrt.
-- Kostet ein Leben, ausser der Helm faengt ihn ab ("Shielded": keine Ragdoll). Sonst fliegt
-- die Figur als Ragdoll heraus; den Neustart am Checkpoint fragt der Client danach an.
-- (Dem Client beim Crash zu glauben ist unbedenklich: er schadet damit nur sich selbst.)
function RaceManager.reportCrash(player: Player, reason: unknown)
	if type(reason) ~= "string" or not CRASH_REASONS[reason] or not CartManager.isSeated(player) then
		return
	end
	local outcome = RaceManager.applyHit(player)
	if outcome == "Shielded" then
		runState:FireClient(player, "Shielded", reason, getRace(player).life.shield)
		return
	end
	if CartManager.crash(player) then
		runState:FireClient(player, "Ragdoll")
	end
end

local function updatePlayer(player: Player, race: RaceState)
	if race.phase == "GameOver" then
		return -- nach dem Game-Over-Screen startet der Server selbst neu
	end
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
		local startZone = Track.findZone(race.trackId, Config.Race.StartZoneTag)
		local leftStart = if startZone
			then not Track.isInZone(startZone, position)
			else (position - race.spawnPosition).Magnitude > Config.Race.StartDistanceWithoutZone
		if leftStart then
			race.phase = "Running"
			race.startTime = os.clock()
			race.startPosition = position
			local vehicle = if cart then cart:GetAttribute("VehicleId") else nil
			Ghosts.start(player, race.trackId, if type(vehicle) == "string" then vehicle else "")
			runState:FireClient(player, "Started")
		end
	elseif race.phase == "Running" then
		Ghosts.record(player, base.CFrame, os.clock() - race.startTime)
		checkCheckpoints(player, race, base)
		local finishZone = Track.findZone(race.trackId, Config.Race.FinishZoneTag)
		if finishZone and Track.isInZone(finishZone, position) then
			finish(player, race, finishZone, position)
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
			-- Gekaufter Helm gilt sofort, wenn der Lauf noch nicht begonnen hat
			if race.phase == "Ready" then
				RaceManager.refreshShield(player)
			end
		end
	end)
end

return RaceManager
