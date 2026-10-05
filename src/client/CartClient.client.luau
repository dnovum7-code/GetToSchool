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
local EnterPrompt = require(script.Parent:WaitForChild("EnterPrompt"))
local RaceUI = require(script.Parent:WaitForChild("RaceUI"))

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestRestart = remotes:WaitForChild("RequestRestart") :: RemoteEvent
local runState = remotes:WaitForChild("RunState") :: RemoteEvent
local requestExit = remotes:WaitForChild("RequestExit") :: RemoteEvent
local requestEnter = remotes:WaitForChild("RequestEnter") :: RemoteEvent

local player = Players.LocalPlayer

local controller: CartController.Controller? = nil
local activeSeat: BasePart? = nil
local activeHumanoid: Humanoid? = nil
local crashDetector = CrashDetector.new()
local crashed = false
local crashedAt = 0

-- Zeitmessung: Der Server entscheidet Start und Ziel. Die laufende Zeit zaehlen wir
-- hier nur zur Anzeige mit; das Endergebnis kommt vom Server.
local runPhase: "Ready" | "Running" | "Finished" | "Aborted" = "Ready"
local runStartedAt = 0

local CRASH_TEXTS: { [string]: string } = {
	Tipped = "Umgekippt",
	Impact = "Harter Aufprall",
	Fell = "Abgestuerzt",
}

RaceUI.init()
EnterPrompt.init(function()
	requestEnter:FireServer()
end)

local EXIT_ACTION = "GetToSchoolExit"

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
end

-- Neustart beim Server anfragen. Der Server entscheidet und antwortet mit "Reset".
local lastRestartRequest = 0
local function requestRestartNow()
	-- funktioniert im Wagen und zu Fuss; der Server entscheidet
	if os.clock() - lastRestartRequest < Config.Race.MinRestartInterval then
		return
	end
	lastRestartRequest = os.clock()
	requestRestart:FireServer()
end

local function onCrash(reason: string)
	crashed = true
	crashedAt = os.clock()
	RaceUI.showMessage("CRASH!", Color3.fromRGB(255, 80, 60), CRASH_TEXTS[reason])
	-- Kurz zeigen, was passiert ist, dann automatisch neu starten (gesamt unter 1 s)
	task.delay(Config.Crash.RestartDelay, function()
		if crashed then
			requestRestartNow()
		end
	end)
end

-- Antwort des Servers: Wagen steht wieder am Start.
local function onReset(spawnCFrame: CFrame)
	local current = controller
	if not current then
		return
	end
	-- Wir rechnen die Physik des Wagens, also setzen wir Position und Tempo auch hier
	-- zurueck (Geschwindigkeiten vom Server wuerden bei uns nicht ankommen).
	current.cart:PivotTo(spawnCFrame)
	local models: { Instance } = { current.cart }
	local character = activeHumanoid and activeHumanoid.Parent
	if character then
		table.insert(models, character)
	end
	for _, model in models do
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
	crashDetector:reset()
	crashed = false
	RaceUI.hideMessage()
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
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

runState.OnClientEvent:Connect(function(kind: string, ...)
	if kind == "Reset" then
		runPhase = "Ready"
		RaceUI.setTimer(0)
		onReset(...)
	elseif kind == "Exited" then
		onExited(...)
	elseif kind == "Aborted" then
		runPhase = "Aborted"
		RaceUI.setTimerInvalid()
		RaceUI.showMessage("Lauf abgebrochen", Color3.fromRGB(255, 200, 80), "R: Neustart", 2)
	elseif kind == "Started" then
		runPhase = "Running"
		runStartedAt = os.clock()
	elseif kind == "Finished" then
		local time: number, best: number, isNewBest: boolean = ...
		runPhase = "Finished"
		RaceUI.setTimer(time)
		RaceUI.setBest(best)
		RaceUI.showMessage(
			"ZIEL!",
			Color3.fromRGB(120, 255, 120),
			RaceUI.formatTime(time) .. (if isNewBest then "  -  Neue Bestzeit!" else ""),
			Config.UI.ResultDisplayTime
		)
	end
end)

-- Taste R (Gamepad: Y). Auf Touch-Geraeten erscheint automatisch ein Button.
ContextActionService:BindAction("GetToSchoolRestart", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		requestRestartNow()
	end
	return Enum.ContextActionResult.Sink
end, true, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
ContextActionService:SetTitle("GetToSchoolRestart", "R")

-- Prueft jeden Frame, ob wir (noch) im eigenen Wagen sitzen. Das ist robuster als nur
-- auf Events zu hoeren, z. B. nach einem Respawn.
local function updateSeat()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
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
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	EnterPrompt.update(controller == nil and humanoid ~= nil and humanoid.Health > 0)

	local current = controller
	if not current then
		return
	end
	if not current.base:IsDescendantOf(workspace) then
		deactivate()
		return
	end
	local throttle, steer = readInput()
	local telemetry = current:step(dt, throttle, steer)
	RaceUI.setSpeed(telemetry.speed)
	if runPhase == "Running" then
		RaceUI.setTimer(os.clock() - runStartedAt)
	end

	if not crashed then
		local reason = crashDetector:update(dt, current.base)
		if reason then
			onCrash(reason)
		end
	elseif os.clock() - crashedAt > 1.5 then
		-- Sicherheitsnetz: falls die erste Anfrage verloren ging, nochmal fragen
		crashedAt = os.clock()
		requestRestartNow()
	end
end)
