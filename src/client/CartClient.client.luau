--!strict
-- Einstiegspunkt auf dem Client: Eingabe lesen, Fahrphysik und Kamera steuern.
-- Sobald die eigene Spielfigur im eigenen Wagen sitzt, wird das Fahren aktiviert.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CartController = require(script.Parent:WaitForChild("CartController"))
local ChaseCamera = require(script.Parent:WaitForChild("ChaseCamera"))
local CrashDetector = require(script.Parent:WaitForChild("CrashDetector"))
local DevPanel = require(script.Parent:WaitForChild("DevPanel"))
local DriftEffects = require(script.Parent:WaitForChild("DriftEffects"))
local EnterPrompt = require(script.Parent:WaitForChild("EnterPrompt"))
local OwnCart = require(script.Parent:WaitForChild("OwnCart"))
local RaceUI = require(script.Parent:WaitForChild("RaceUI"))
local TrackSensors = require(script.Parent:WaitForChild("TrackSensors"))
local Obstacles = require(script.Parent:WaitForChild("Obstacles"))
local RandomEventsClient = require(script.Parent:WaitForChild("RandomEventsClient"))
local SoundSystem = require(script.Parent:WaitForChild("SoundSystem"))

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local SchoolClock = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SchoolClock"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestRestart = remotes:WaitForChild("RequestRestart") :: RemoteEvent
local runState = remotes:WaitForChild("RunState") :: RemoteEvent
local requestExit = remotes:WaitForChild("RequestExit") :: RemoteEvent
local requestEnter = remotes:WaitForChild("RequestEnter") :: RemoteEvent
local reportCrash = remotes:WaitForChild("ReportCrash") :: RemoteEvent

local player = Players.LocalPlayer

local controller: CartController.Controller? = nil
local activeSeat: BasePart? = nil
local activeHumanoid: Humanoid? = nil
local crashDetector = CrashDetector.new()
local crashed = false
local crashedAt = 0
local previousVelocity = Vector3.zero -- Wagen-Tempo im letzten Frame (vor einem Aufprall)
local ragdollLaunch = Vector3.zero -- Schwung fuer die Ragdoll, beim Crash berechnet
local wasGrounded = true -- fuer die Landungs-Erkennung (Kamera-Wackeln)

-- Zeitmessung: Der Server entscheidet Start und Ziel. Die laufende Zeit zaehlen wir
-- hier nur zur Anzeige mit; das Endergebnis kommt vom Server.
local runPhase: "Ready" | "Running" | "Finished" | "Aborted" = "Ready"
local runStartedAt = 0
local runTimeScale = Config.Clock.TimeScale -- Spielsekunden pro echter Sekunde (vom Server)
local bellRung = false -- Schulglocke in diesem Lauf schon gelaeutet?
local wasBoosting = false
local wasBoostingForCrash = false

-- Aktuelle Spielzeit (Sekunden seit Mitternacht) fuer die Uhr im UI
local finishedArrival = 0 -- Ankunftszeit des letzten Laufs (bleibt auf der Uhr stehen)

local function currentGameTime(): number
	if runPhase == "Running" then
		return SchoolClock.startSeconds() + (os.clock() - runStartedAt) * runTimeScale
	elseif runPhase == "Finished" then
		return finishedArrival
	end
	return SchoolClock.startSeconds()
end

-- Ergebnis-Screen. Die Werte hat der Server berechnet, hier wird nur angezeigt.
type RunResult = {
	arrival: number,
	schoolTime: number,
	onTime: boolean,
	grade: number,
	bestArrival: number,
	isNewBest: boolean,
	realTime: number,
	noCheckpointRestart: boolean,
}
local function showResult(result: RunResult)
	local title, color
	if result.onTime then
		title, color = Config.Clock.OnTimeTitle, Color3.fromRGB(120, 255, 120)
	else
		local messages = Config.Clock.LateMessages
		title = if #messages > 0 then messages[math.random(1, #messages)] else "Zu spaet!"
		color = Color3.fromRGB(255, 110, 80)
	end
	local arrivalLine = "Ankunft: " .. SchoolClock.format(result.arrival, true)
	if result.onTime then
		arrivalLine ..= "  (puenktlich)"
	else
		arrivalLine ..= "  (" .. SchoolClock.formatDuration(result.arrival - result.schoolTime) .. " zu spaet)"
	end
	local lines = {
		arrivalLine,
		"Bestzeit: " .. SchoolClock.format(result.bestArrival, true) .. (if result.isNewBest
			then "  - Neue Bestzeit!"
			else ""),
		string.format("Fahrzeit: %.2f s", result.realTime),
		if result.noCheckpointRestart then "Ohne Checkpoint-Neustart!" else "Mit Checkpoint-Neustart",
	}
	RaceUI.showResult(title, color, lines, result.grade, Config.UI.ResultDisplayTime)
end

local CRASH_TEXTS: { [string]: string } = {
	Tipped = "Umgekippt",
	Impact = "Harter Aufprall",
	Fell = "Abgestuerzt",
}

RaceUI.init()
Obstacles.init() -- bewegte Hindernisse (Mover, Spinner, Pendulum)
RandomEventsClient.init() -- Zufallsereignisse ein-/ausblenden
SoundSystem.init()
DevPanel.init() -- Tuning-Panel, nur in Studio (F2)
EnterPrompt.init(function()
	requestEnter:FireServer()
end)

local EXIT_ACTION = "GetToSchoolExit"
local HANDBRAKE_ACTION = "GetToSchoolHandbrake"
local handbrakeHeld = false
local hopRequested = false -- Drift-Taste neu gedrueckt: Hopp im naechsten Physik-Frame

-- Diese Zustaende wuerden die Figur aus dem Sitz werfen
local BLOCKED_STATES = {
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
}

local function isOwnCartSeat(seat: BasePart?): boolean
	if not seat then
		return false
	end
	local cart = seat.Parent
	return cart ~= nil
		and cart:GetAttribute("IsCart") == true
		and cart:GetAttribute("OwnerUserId") == player.UserId
end

local function deactivate()
	if controller then
		controller:stop()
	end
	controller = nil
	activeSeat = nil
	ContextActionService:UnbindAction(EXIT_ACTION)
	ContextActionService:UnbindAction(HANDBRAKE_ACTION)
	handbrakeHeld = false
	DriftEffects.detach()
	SoundSystem.detach()
	local humanoid = activeHumanoid
	if humanoid then
		for _, state in BLOCKED_STATES do
			humanoid:SetStateEnabled(state, true)
		end
	end
	ChaseCamera.stop(humanoid)
end

local function activate(seat: BasePart, humanoid: Humanoid)
	local cart = seat.Parent :: Model
	local character = humanoid.Parent :: Model
	controller = CartController.new(cart, character)
	activeSeat = seat
	activeHumanoid = humanoid
	for _, state in BLOCKED_STATES do
		humanoid:SetStateEnabled(state, false)
	end
	ChaseCamera.start(cart:WaitForChild("Base") :: BasePart, { cart, character })
	crashDetector:reset()
	crashed = false

	-- Aussteigen: E (Gamepad X). Auf Touch-Geraeten erscheint ein eigener Button.
	-- Nur gebunden, solange man faehrt; zu Fuss gehoert E dem "Einsteigen"-Hinweis.
	ContextActionService:BindAction(EXIT_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			requestExit:FireServer()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle(EXIT_ACTION, "Raus")

	-- Handbremse / Drift: Shift (Gamepad B), Touch-Button "Drift". Hohe Prioritaet und
	-- "Sink", damit Shift nicht nebenbei Roblox' ShiftLock umschaltet.
	ContextActionService:BindActionAtPriority(
		HANDBRAKE_ACTION,
		function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				handbrakeHeld = true
				hopRequested = true -- Druecken = Hopp (wie Mario Kart), Halten = Drift
			elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
				handbrakeHeld = false
			end
			return Enum.ContextActionResult.Sink
		end,
		true,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift,
		Enum.KeyCode.ButtonB
	)
	ContextActionService:SetTitle(HANDBRAKE_ACTION, "Drift")

	DriftEffects.attach(cart, character)
	SoundSystem.attach(cart)
end

-- Neustart beim Server anfragen. Der Server entscheidet und antwortet mit "Reset".
local lastRestartRequest = 0
-- kind: "Checkpoint" (R, nach Crash) oder "Full" (T, kompletter Neustart am Start)
local function requestRestartNow(kind: "Checkpoint" | "Full")
	-- funktioniert im Wagen und zu Fuss; der Server entscheidet
	if os.clock() - lastRestartRequest < Config.Race.MinRestartInterval then
		return
	end
	lastRestartRequest = os.clock()
	-- Als Ragdoll zuerst aufstehen, damit der Server uns wieder in den Sitz setzen kann
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid:GetState() == Enum.HumanoidStateType.Physics then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	requestRestart:FireServer(kind)
end

-- `text`: eigener Untertitel (z. B. Attribut "Message" eines Hazards)
local function onCrash(reason: string, base: BasePart, text: string?)
	crashed = true
	if controller then
		controller:resetDrift() -- Boost-Ladung geht beim Crash verloren
	end
	crashedAt = os.clock()
	RaceUI.showMessage("CRASH!", Color3.fromRGB(255, 80, 60), text or CRASH_TEXTS[reason])
	SoundSystem.play("Crash")

	-- Schwung fuer die Ragdoll: Tempo von VOR dem Aufprall (sonst waere es ~0)
	local C = Config.Crash
	local velocity = base.AssemblyLinearVelocity
	if previousVelocity.Magnitude > velocity.Magnitude then
		velocity = previousVelocity
	end
	local forward = Vector3.new(base.CFrame.LookVector.X, 0, base.CFrame.LookVector.Z)
	forward = if forward.Magnitude > 0.1 then forward.Unit else Vector3.zero
	ragdollLaunch = velocity * C.RagdollCarry
		+ forward * C.RagdollForwardBoost
		+ Vector3.yAxis * C.RagdollUpSpeed
	if C.Ragdoll then
		reportCrash:FireServer()
	end

	-- Crash eine Weile zeigen, dann automatisch neu starten. R ueberspringt das.
	task.delay(C.RestartDelay, function()
		if crashed then
			requestRestartNow("Checkpoint")
		end
	end)
end

-- Server hat die Ragdoll gebaut: Figur schlaff schalten und wegschleudern.
-- (Unsere Figur rechnet dieser Client, deshalb setzen wir Zustand und Tempo hier.)
local function onRagdoll()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return
	end
	humanoid:ChangeState(Enum.HumanoidStateType.Physics) -- Humanoid steuert nichts mehr
	local spin = Config.Crash.RagdollSpin
	local randomSpin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2 * spin
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = ragdollLaunch
			part.AssemblyAngularVelocity = randomSpin
		end
	end
end

-- Antwort des Servers: Wagen steht wieder am Start.
local function onReset(spawnCFrame: CFrame)
	crashDetector:reset()
	crashed = false
	previousVelocity = Vector3.zero
	RaceUI.hideMessage()
	if controller then
		controller:resetDrift() -- Neustart: Boost-Ladung leeren
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid:GetState() == Enum.HumanoidStateType.Physics then
		-- aus der Ragdoll aufstehen, damit der Server uns wieder hinsetzen kann
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	-- Wir rechnen die Physik des Wagens, also setzen wir Position und Tempo auch hier
	-- zurueck (Geschwindigkeiten vom Server wuerden bei uns nicht ankommen).
	local cart = OwnCart.find()
	if cart then
		cart:PivotTo(spawnCFrame)
		OwnCart.stopMotion(cart)
	end
	if character then
		OwnCart.stopMotion(character)
	end
	ChaseCamera.snap()
end

-- Server hat uns aussteigen lassen: Figur sicher neben den Wagen stellen.
-- Unsere Figur rechnet dieser Client, also Position und Tempo auch hier setzen
-- (sonst fliegt sie mit dem Tempo des Wagens weiter).
local function onExited(landing: CFrame)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return
	end
	humanoid.Sit = false
	character:PivotTo(landing)
	OwnCart.stopMotion(character)
end

runState.OnClientEvent:Connect(function(kind: string, ...)
	if kind == "Reset" then
		local spawnCFrame: CFrame, keepRunning: boolean = ...
		if not keepRunning then
			-- kompletter Neustart: neuer Lauf. Beim Checkpoint-Neustart laeuft die Uhr weiter.
			runPhase = "Ready"
			bellRung = false
			RaceUI.hideResult()
		end
		onReset(spawnCFrame)
	elseif kind == "Events" then
		-- neuer Lauf: Server hat gewuerfelt, welche Zufallsereignisse aktiv sind
		RandomEventsClient.setSelection(...)
	elseif kind == "Checkpoint" then
		RaceUI.showToast("Checkpoint!")
		SoundSystem.play("Checkpoint")
	elseif kind == "WrongCheckpoint" then
		RaceUI.showToast("Falscher Checkpoint - falsche Reihenfolge!", 2)
	elseif kind == "Ragdoll" then
		onRagdoll()
	elseif kind == "Exited" then
		onExited(...)
	elseif kind == "Aborted" then
		runPhase = "Aborted"
		RaceUI.showMessage("Lauf abgebrochen", Color3.fromRGB(255, 200, 80), "R: Neustart", 2)
	elseif kind == "Started" then
		local timeScale: number = ...
		runPhase = "Running"
		runStartedAt = os.clock()
		runTimeScale = timeScale
	elseif kind == "Finished" then
		local result: RunResult = ...
		runPhase = "Finished"
		finishedArrival = result.arrival
		RaceUI.setBest(result.bestArrival)
		showResult(result)
		SoundSystem.play("Finish")
	end
end)

-- Taste R (Gamepad: Y): zurueck zum letzten Checkpoint (ohne Checkpoint: zum Start).
-- Auf Touch-Geraeten erscheint automatisch ein Button.
ContextActionService:BindAction("GetToSchoolRestart", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		requestRestartNow("Checkpoint")
	end
	return Enum.ContextActionResult.Sink
end, true, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
ContextActionService:SetTitle("GetToSchoolRestart", "R")

-- Taste T (Gamepad: Steuerkreuz hoch): kompletter Neustart am Start, Uhr wieder 7:45
ContextActionService:BindAction("GetToSchoolFullRestart", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		requestRestartNow("Full")
	end
	return Enum.ContextActionResult.Sink
end, true, Enum.KeyCode.T, Enum.KeyCode.DPadUp)
ContextActionService:SetTitle("GetToSchoolFullRestart", "Start")

-- Prueft jeden Frame, ob wir (noch) im eigenen Wagen sitzen. Das ist robuster als nur
-- auf Events zu hoeren, z. B. nach einem Respawn.
local seatMismatchSince: number? = nil
local function updateSeat()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart

	-- Der Server hat uns in den Sitz geschweisst, aber der Humanoid hat es (z. B. direkt
	-- nach der Ragdoll) nicht mitbekommen: nach kurzer Zeit selbst hinsetzen.
	local cart = OwnCart.find()
	local cartSeat = cart and cart:FindFirstChild("Seat") :: Seat?
	if humanoid and not seat and cartSeat and cartSeat.Occupant == humanoid then
		seatMismatchSince = seatMismatchSince or os.clock()
		if os.clock() - (seatMismatchSince :: number) > 0.3 then
			humanoid.Sit = true
			seatMismatchSince = nil
		end
	else
		seatMismatchSince = nil
	end

	if humanoid and seat and isOwnCartSeat(seat) and humanoid.Health > 0 then
		if seat ~= activeSeat then
			deactivate()
			activate(seat, humanoid)
		end
	elseif activeSeat then
		deactivate()
	end
end

local function isDown(...: Enum.KeyCode): boolean
	for _, key in { ... } do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function readInput(): (number, number)
	-- Beim Tippen im Chat nicht fahren
	if UserInputService:GetFocusedTextBox() then
		return 0, 0
	end
	local throttle = 0
	if isDown(Enum.KeyCode.W, Enum.KeyCode.Up) then
		throttle += 1
	end
	if isDown(Enum.KeyCode.S, Enum.KeyCode.Down) then
		throttle -= 1
	end
	local steer = 0
	if isDown(Enum.KeyCode.D, Enum.KeyCode.Right) then
		steer += 1
	end
	if isDown(Enum.KeyCode.A, Enum.KeyCode.Left) then
		steer -= 1
	end
	return throttle, steer
end

-- PreSimulation laeuft direkt vor jedem Physik-Schritt (wie FixedUpdate in Unity).
RunService.PreSimulation:Connect(function(dt)
	updateSeat()
	RaceUI.setSpeedometerVisible(controller ~= nil)
	-- Schuluhr laeuft auch weiter, wenn man gerade nicht faehrt (z. B. als Ragdoll)
	if runPhase == "Aborted" then
		RaceUI.setClockInvalid()
	else
		local gameTime = currentGameTime()
		RaceUI.setClock(gameTime)
		-- Schulglocke genau einmal pro Lauf, wenn es 8:00 wird
		if runPhase == "Running" and not bellRung and gameTime >= SchoolClock.schoolSeconds() then
			bellRung = true
			SoundSystem.play("Bell")
		end
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	EnterPrompt.update(controller == nil and not crashed and humanoid ~= nil and humanoid.Health > 0)

	-- Sicherheitsnetz: falls die Neustart-Anfrage nach einem Crash verloren ging, nochmal fragen
	if crashed and os.clock() - crashedAt > Config.Crash.RestartDelay + 1 then
		crashedAt = os.clock()
		requestRestartNow("Checkpoint")
	end

	local current = controller
	if not current then
		DriftEffects.update(dt, nil) -- alte Reifenspuren verblassen trotzdem weiter
		return
	end
	if not current.base:IsDescendantOf(workspace) then
		deactivate()
		return
	end
	local throttle, steer = readInput()
	-- Handbremse nur, wenn nicht gerade im Chat getippt wird
	local handbrake = handbrakeHeld and UserInputService:GetFocusedTextBox() == nil
	local surface = TrackSensors.sampleGround(current.cart, current.rayParams)
	local hop = hopRequested and UserInputService:GetFocusedTextBox() == nil
	hopRequested = false
	local telemetry = current:step(dt, throttle, steer, handbrake, hop, surface)

	-- Bouncy: federt ab, ein harter Aufprall ist hier kein Crash
	if TrackSensors.touching(current.cart, "Bouncy") then
		crashDetector:relaxImpact(math.huge, Config.Track.BouncyCrashGrace)
	end
	-- Nach einem JumpPad: Landung darf haerter sein (bis zur Landung plus etwas Puffer)
	if telemetry.padEvent == "Jump" then
		local airTime = 2 * Config.Track.JumpPadStrength / math.max(workspace.Gravity, 1) + 1
		crashDetector:relaxImpact(Config.Track.JumpLandingTolerance, airTime)
	end
	DriftEffects.update(dt, telemetry)
	local drifting = telemetry.grounded and telemetry.driftAmount > 0.5 and telemetry.speed > 10
	SoundSystem.update(telemetry.speed, telemetry.grounded, drifting)
	if telemetry.padEvent == "Boost" or (telemetry.boosting and not wasBoosting) then
		SoundSystem.play("Boost")
	end
	wasBoosting = telemetry.boosting
	RaceUI.setSpeed(telemetry.speed)

	-- Harte Landung: Fallgeschwindigkeit kurz vor dem Aufsetzen bestimmt das Wackeln
	if telemetry.grounded and not wasGrounded then
		local fallSpeed = -previousVelocity.Y
		local C = Config.Camera
		if fallSpeed > C.LandingShakeMinSpeed then
			ChaseCamera.addShake((fallSpeed - C.LandingShakeMinSpeed) * C.LandingShakePerSpeed)
		end
	end
	wasGrounded = telemetry.grounded

	-- Hazard: sofortiger Crash bei Beruehrung
	local hazard = if crashed then nil else TrackSensors.touching(current.cart, "Hazard")
	if hazard then
		local message = hazard:GetAttribute("Message")
		onCrash(
			"Hazard",
			current.base,
			if type(message) == "string" then message else Config.Track.HazardMessage
		)
	end

	-- Selbst verursachte Tempo-Spruenge (Pads usw.) sind kein Aufprall
	if telemetry.selfImpulse.Magnitude > 0 then
		crashDetector:expectVelocityChange(telemetry.selfImpulse)
	end
	if telemetry.boosting and not wasBoostingForCrash then
		crashDetector:expectVelocityChange(Vector3.zero) -- Drift-Boost: nur toleranter
	end
	wasBoostingForCrash = telemetry.boosting

	if not crashed then
		local reason = crashDetector:update(dt, current.base)
		if reason then
			onCrash(reason, current.base)
		end
	end
	previousVelocity = current.base.AssemblyLinearVelocity
end)
