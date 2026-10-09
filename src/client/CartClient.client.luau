--!strict
-- Einstiegspunkt auf dem Client: Eingabe lesen, Fahrphysik und Kamera steuern.
-- Sobald die eigene Spielfigur im eigenen Wagen sitzt, wird das Fahren aktiviert.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AbilityHud = require(script.Parent:WaitForChild("AbilityHud"))
local Abilities = require(script.Parent:WaitForChild("Abilities"))
local CartController = require(script.Parent:WaitForChild("CartController"))
local ChaseCamera = require(script.Parent:WaitForChild("ChaseCamera"))
local CoinsClient = require(script.Parent:WaitForChild("CoinsClient"))
local CrashDetector = require(script.Parent:WaitForChild("CrashDetector"))
local DevPanel = require(script.Parent:WaitForChild("DevPanel"))
local DriftEffects = require(script.Parent:WaitForChild("DriftEffects"))
local EnterPrompt = require(script.Parent:WaitForChild("EnterPrompt"))
local AchievementUI = require(script.Parent:WaitForChild("AchievementUI"))
local ComboUI = require(script.Parent:WaitForChild("ComboUI"))
local MeterUI = require(script.Parent:WaitForChild("MeterUI"))
local ControlsInfo = require(script.Parent:WaitForChild("ControlsInfo"))
local GarageUI = require(script.Parent:WaitForChild("GarageUI"))
local GhostClient = require(script.Parent:WaitForChild("GhostClient"))
local HomeworkUI = require(script.Parent:WaitForChild("HomeworkUI"))
local LeaderboardClient = require(script.Parent:WaitForChild("LeaderboardClient"))
local PaintShopUI = require(script.Parent:WaitForChild("PaintShopUI"))
local Settings = require(script.Parent:WaitForChild("Settings"))
local SettingsUI = require(script.Parent:WaitForChild("SettingsUI"))
local SpinUI = require(script.Parent:WaitForChild("SpinUI"))
local LaunchablesClient = require(script.Parent:WaitForChild("LaunchablesClient"))
local FlyMode = require(script.Parent:WaitForChild("FlyMode"))
local OwnCart = require(script.Parent:WaitForChild("OwnCart"))
local ProgressClient = require(script.Parent:WaitForChild("ProgressClient"))
local ProgressUI = require(script.Parent:WaitForChild("ProgressUI"))
local RaceUI = require(script.Parent:WaitForChild("RaceUI"))
local ShopUI = require(script.Parent:WaitForChild("ShopUI"))
local TrackSensors = require(script.Parent:WaitForChild("TrackSensors"))
local Rewind = require(script.Parent:WaitForChild("Rewind"))
local Tricks = require(script.Parent:WaitForChild("Tricks"))
local VisualFX = require(script.Parent:WaitForChild("VisualFX"))
local Toolkit = require(script.Parent:WaitForChild("Toolkit"))
local Obstacles = require(script.Parent:WaitForChild("Obstacles"))
local RandomEventsClient = require(script.Parent:WaitForChild("RandomEventsClient"))
local SoundSystem = require(script.Parent:WaitForChild("SoundSystem"))
local StatReporter = require(script.Parent:WaitForChild("StatReporter"))
local TerrainRescue = require(script.Parent:WaitForChild("TerrainRescue"))

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local RaceTime = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RaceTime"))

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
local crashToken = 0 -- damit ein alter verzoegerter Neustart nicht nach einem neuen Crash feuert
local gameOver = false -- Game-Over-Screen laeuft (0 Leben)
local helmetGraceUntil = 0 -- nach einer Helm-Rettung kurz keine neuen Crashs
-- Leben und Helm-Ladungen (vom Server; die Helm-Ladung wird hier vorhergesagt, damit die
-- Rettung ohne Verzoegerung passiert - der Server entscheidet trotzdem)
local lifeState = { lives = Config.Lives.PerRun, maxLives = Config.Lives.PerRun, shield = 0, maxShield = 0 }
local wasGrounded = true -- fuer die Landungs-Erkennung (Kamera-Wackeln)

-- Zeitmessung: Der Server entscheidet Start und Ziel. Die laufende Zeit zaehlen wir
-- hier nur zur Anzeige mit; das Endergebnis kommt vom Server.
local runPhase: "Ready" | "Running" | "Finished" | "Aborted" | "GameOver" = "Ready"
local runStartedAt = 0
local finishedTime = 0 -- Endzeit des letzten Laufs (bleibt auf dem Timer stehen)
local wasBoostingForCrash = false

-- Aktuelle Laufzeit (Sekunden) fuer den Timer im UI
local function currentRunTime(): number
	if runPhase == "Running" then
		return os.clock() - runStartedAt
	elseif runPhase == "Finished" then
		return finishedTime
	end
	return 0
end

-- Ergebnis-Screen. Die Werte hat der Server berechnet, hier wird nur angezeigt.
type RunResult = {
	time: number,
	bestTime: number,
	previousBest: number?,
	isNewBest: boolean,
	grade: number,
	noCheckpointRestart: boolean,
	coinsReward: number,
	coinsBase: number,
	coinsGradeBonus: number,
	coinsCollected: number,
	lives: number,
	maxLives: number,
	hits: number,
	bestFlightName: string?,
	bestFlightMeters: number?,
	leaderboardNote: string?,
	meters: number?,
	meterCoins: number?,
	meterBoost: boolean?,
}
local GOLD = Color3.fromRGB(255, 215, 80)
local function showResult(result: RunResult)
	local lines = { "Zeit: " .. RaceTime.format(result.time) }
	local previous = result.previousBest
	if result.isNewBest and previous then
		table.insert(
			lines,
			"Alte Bestzeit: "
				.. RaceTime.format(previous)
				.. "  ("
				.. RaceTime.formatDelta(result.time - previous)
				.. ")"
		)
	elseif result.isNewBest then
		table.insert(lines, "Erste Zeit auf diesem Track!")
	else
		table.insert(
			lines,
			"Bestzeit: "
				.. RaceTime.format(result.bestTime)
				.. "  ("
				.. RaceTime.formatDelta(result.time - result.bestTime)
				.. ")"
		)
	end
	table.insert(
		lines,
		if result.noCheckpointRestart then "Ohne Checkpoint-Neustart!" else "Mit Checkpoint-Neustart"
	)
	table.insert(lines, `Leben uebrig: {result.lives} von {result.maxLives}`)
	table.insert(lines, `Getroffene Objekte: {result.hits}`)
	local chaos = Toolkit.getChaos()
	if chaos > 0 then
		table.insert(lines, `Chaos: {chaos} Gegenstaende umgefahren`)
	end
	if result.bestFlightName and result.bestFlightMeters then
		table.insert(lines, `Weitester Flug: {result.bestFlightName} {result.bestFlightMeters} m`)
	end
	table.insert(
		lines,
		`Muenzen: +{result.coinsReward} im Ziel ({result.coinsBase} + {result.coinsGradeBonus} Notenbonus), `
			.. `{result.coinsCollected} eingesammelt`
	)
	if result.meters then
		table.insert(
			lines,
			`Gefahren: {result.meters} m  (+{result.meterCoins or 0} Muenzen{if result.meterBoost
				then ", x" .. Config.Meters.BoostMultiplier .. "-Boost"
				else ""})`
		)
	end
	if result.leaderboardNote then
		table.insert(lines, result.leaderboardNote) -- Zeit zaehlt nur persoenlich
	end
	if result.isNewBest then
		RaceUI.showResult("NEUE BESTZEIT!", GOLD, lines, result.grade, Config.UI.ResultDisplayTime)
	else
		RaceUI.showResult(
			"ZIEL!",
			Color3.fromRGB(120, 255, 120),
			lines,
			result.grade,
			Config.UI.ResultDisplayTime
		)
	end
end

local CRASH_TEXTS: { [string]: string } = {
	HitHazard = "Getroffen!",
	Impact = "Harter Aufprall",
	Fell = "Abgestuerzt",
}

RaceUI.init()
ProgressUI.init() -- Muenzzaehler
CoinsClient.init() -- Muenzen drehen und einsammeln
LaunchablesClient.init() -- Objekte wegschleudern (Kuh, Muelltonne ...)
ProgressClient.init() -- Spielstand-Kopie vom Server
AbilityHud.init() -- Abilities unten links
Toolkit.init() -- erweiterter Baukasten (Trigger, Spawner, Tore ...)
GhostClient.init() -- Geist vom besten Lauf
-- Shop (Taste B): nur ausserhalb eines Laufs (der Server prueft das auch)
ShopUI.init(function()
	return runPhase == "Ready" or runPhase == "Finished" or runPhase == "Aborted"
end)
LeaderboardClient.init() -- Bestenlisten (Reiter im Menue, Bretter in der Welt)
HomeworkUI.init() -- Hausaufgaben (Reiter im Menue)
GarageUI.init() -- Fahrzeuge (Reiter im Menue)
PaintShopUI.init() -- Farben und Spur (Reiter im Menue)
AchievementUI.init() -- Erfolge (Reiter im Menue, Popup)
SpinUI.init() -- taegliches Gluecksrad (Reiter im Menue)
SettingsUI.init() -- Einstellungen und Steuerung (Reiter im Menue)
-- Powerups aus dem Gluecksrad wirken beim Losfahren (Leben/Helm zaehlt der Server)
remotes:WaitForChild("Progress").OnClientEvent:Connect(function(kind: string, used: unknown)
	if kind ~= "Powerups" or type(used) ~= "table" then
		return
	end
	local names = {}
	for _, id in used :: { any } do
		local def = (Config.DailySpin.Items :: any)[id]
		if def then
			table.insert(names, `{def.icon} {def.name}`)
		end
		if id == "StartBoost" and controller then
			controller:startBoost(Config.DailySpin.StartBoostSpeed, Config.DailySpin.StartBoostDuration)
			SoundSystem.play("Boost")
			ChaseCamera.kickFov(Config.Camera.BoostFovKick)
		end
	end
	if #names > 0 then
		RaceUI.showToast("Powerup: " .. table.concat(names, ", "), 3, Color3.fromRGB(120, 220, 255))
	end
end)
Tricks.init() -- Lufttricks (Anzeige)
Rewind.init() -- Rueckspulen (Zeitleiste)
VisualFX.init() -- Speed-Linien, Konfetti ...
ComboUI.init() -- Kuh-Kombo-Anzeige
MeterUI.init() -- Meterzaehler und x2-Anzeige
ProgressClient.onChanged(function(snapshot)
	Abilities.setLevels(snapshot.upgrades) -- gekaufte Upgrade-Stufen
	Settings.load(snapshot) -- gespeicherte Einstellungen (einmal nach dem Laden)
end)
-- Hilfezeile unten passend zum Geraet (Tastatur, Gamepad, Touch)
RaceUI.setHelpText(ControlsInfo.helpLine(ControlsInfo.device()))
UserInputService.LastInputTypeChanged:Connect(function()
	RaceUI.setHelpText(ControlsInfo.helpLine(ControlsInfo.device()))
end)
Obstacles.init() -- bewegte Hindernisse (Mover, Spinner, Pendulum)
RandomEventsClient.init() -- Zufallsereignisse ein-/ausblenden
SoundSystem.init()
DevPanel.init() -- Tuning-Panel, nur in Studio (F2)
EnterPrompt.init(function()
	requestEnter:FireServer()
end)

local EXIT_ACTION = "GetToSchoolExit"
local HANDBRAKE_ACTION = "GetToSchoolHandbrake"
local HOP_ACTION = "GetToSchoolHop"
local lastSteer = 0 -- Lenkung im letzten Frame (Trick-Richtung fuer Gamepad/Touch)
local shiftHeld = false -- Shift / Gamepad B: wechselt zwischen Drift und normal (Config.Drift.DriftByDefault)
local hopRequested = false -- Hopp-Taste gedrueckt: Hopp im naechsten Physik-Frame
local jumpHeld = false -- Hopp-Taste wird gehalten (Fallschirm)

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
	ContextActionService:UnbindAction(HOP_ACTION)
	shiftHeld = false
	jumpHeld = false
	Abilities.deactivate()
	Tricks.deactivate()
	Rewind.deactivate()
	VisualFX.detach()
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

	-- Shift (Gamepad B), Touch-Button: Standard ist Drift, gehalten = normal fahren
	-- (umgekehrt, wenn Config.Drift.DriftByDefault = false). Hohe Prioritaet und "Sink",
	-- damit Shift nicht nebenbei Roblox' ShiftLock umschaltet.
	ContextActionService:BindActionAtPriority(
		HANDBRAKE_ACTION,
		function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				shiftHeld = true
			elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
				shiftHeld = false
			end
			return Enum.ContextActionResult.Sink
		end,
		true,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift,
		Enum.KeyCode.ButtonB
	)
	ContextActionService:SetTitle(HANDBRAKE_ACTION, if Config.Drift.DriftByDefault then "Normal" else "Drift")

	-- Hopp: Leertaste (Gamepad A), Touch-Button "Hopp". Hohe Prioritaet und "Sink", damit
	-- Roblox' eigener Sprung die Taste im Wagen nicht bekommt.
	-- Gehalten (jumpHeld): Rucksack-Fallschirm.
	ContextActionService:BindActionAtPriority(HOP_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			hopRequested = true
			jumpHeld = true
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			jumpHeld = false
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	ContextActionService:SetTitle(HOP_ACTION, "Hopp")
	Abilities.activate() -- Ability-Tasten (z. B. Turbo F)
	Rewind.activate() -- Rueckspulen (Z, nur Studio bzw. Config.Rewind.EnabledLive)
	Tricks.activate(function() -- Lufttricks (Q/E, Gamepad LB, Touch "Trick")
		return lastSteer
	end)

	DriftEffects.attach(cart, character)
	VisualFX.attach(cart) -- Staub, Boost-Flammen
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

-- Rueckmeldungen fuer Abilities (Kamera, Text, Sound)
local abilityEffects = {
	fovKick = function(degrees: number)
		ChaseCamera.kickFov(degrees)
	end,
	shake = function(degrees: number)
		ChaseCamera.addShake(degrees)
	end,
	toast = function(text: string, color: Color3?)
		RaceUI.showToast(text, 1.5, color)
	end,
	sound = function(name: string)
		SoundSystem.play(name)
	end,
}

-- Schwung fuer die Ragdoll: Tempo von VOR dem Aufprall (sonst waere es ~0), plus Extra-Schwung
local function computeRagdollLaunch(base: BasePart?)
	local C = Config.Crash
	local velocity = if base then base.AssemblyLinearVelocity else Vector3.zero
	if previousVelocity.Magnitude > velocity.Magnitude then
		velocity = previousVelocity
	end
	local forward = Vector3.zero
	if base then
		local look = Vector3.new(base.CFrame.LookVector.X, 0, base.CFrame.LookVector.Z)
		forward = if look.Magnitude > 0.1 then look.Unit else Vector3.zero
	end
	ragdollLaunch = velocity * C.RagdollCarry
		+ forward * C.RagdollForwardBoost
		+ Vector3.yAxis * C.RagdollUpSpeed
end

-- Crash-Zustand: Fahren aus, nach einer Weile automatisch zum Checkpoint (R ueberspringt das)
local function enterCrashed(base: BasePart?)
	crashed = true
	crashedAt = os.clock()
	crashToken += 1
	local token = crashToken
	if controller then
		controller:resetDrift() -- Boost-Ladung geht beim Crash verloren
	end
	computeRagdollLaunch(base)
	task.delay(Config.Crash.RestartDelay, function()
		if crashed and not gameOver and crashToken == token then
			requestRestartNow("Checkpoint")
		end
	end)
end

-- Laeuft ein Lauf, in dem Leben zaehlen? (vor dem Start und waehrend der Fahrt)
local function livesCount(): boolean
	return runPhase == "Ready" or runPhase == "Running"
end

-- Der Fahrradhelm faengt den Crash ab: kein Leben weg, keine Ragdoll.
-- Umgekippt: Wagen wird wieder aufgestellt. Harter Aufprall: einfach weiterfahren.
-- Wasser/Abgrund (Hazard, Absturz): zurueck zum Checkpoint, aber ohne Lebensverlust.
-- `predicted`: true = vom Client vorhergesagt (Ladung hier abziehen), false = der Server hat
-- gerettet, obwohl wir es nicht wussten (Ladung kommt mit "Lives")
local function helmetSave(reason: string, base: BasePart, predicted: boolean)
	if predicted then
		lifeState.shield -= 1
		ProgressUI.setLives(lifeState.lives, lifeState.maxLives, lifeState.shield, lifeState.maxShield)
		Abilities.setShield(lifeState.shield, lifeState.maxShield)
	end
	helmetGraceUntil = os.clock() + Config.Abilities.HelmetGrace
	crashDetector:reset()
	RaceUI.showMessage("HELM!", Color3.fromRGB(90, 180, 255), "Der Fahrradhelm hat dich gerettet!", 1.2)
	SoundSystem.play("Shield")
	ChaseCamera.addShake(1.5)
	if reason == "BadLanding" then
		-- schief gelandet: Wagen in Fahrtrichtung drehen und weiterfahren
		local cart = OwnCart.find()
		local velocity = base.AssemblyLinearVelocity
		local flat = Vector3.new(velocity.X, 0, velocity.Z)
		if cart and flat.Magnitude > 1 then
			local position = base.Position + Vector3.new(0, 0.5, 0)
			cart:PivotTo(CFrame.lookAt(position, position + flat.Unit))
			base.AssemblyAngularVelocity = Vector3.zero
		end
	elseif reason == "Hazard" or reason == "Fell" then
		requestRestartNow("Checkpoint")
	end
end

-- `text`: eigener Untertitel (z. B. Attribut "Message" eines Hazards)
local function onCrash(reason: string, base: BasePart, text: string?)
	-- God Mode / keine Tode (F2, nur Studio): kein Crash, kein Lebensverlust;
	-- abgestuerzt = zum Checkpoint
	if Config.Debug.GodMode or Config.Debug.NoDeaths then
		if reason == "Fell" then
			requestRestartNow("Checkpoint")
		end
		return
	end
	reportCrash:FireServer(reason) -- Server zieht das Leben ab (oder die Helm-Ladung)
	if livesCount() and lifeState.shield > 0 then
		helmetSave(reason, base, true)
		return
	end
	Tricks.cancel()
	Rewind.clear()
	enterCrashed(base)
	RaceUI.showMessage("CRASH!", Color3.fromRGB(255, 80, 60), text or CRASH_TEXTS[reason])
	SoundSystem.play("Crash")
end

-- Fliegende Figur: Schwerkraft teilweise aufheben (fliegt weiter) und Luftspur
local function addRagdollEffects(character: Model)
	local C = Config.Crash
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and not part.Massless and C.RagdollFloat > 0 then
			local attachment = Instance.new("Attachment")
			attachment.Name = "RagdollFloatAttachment"
			attachment.Parent = part
			local force = Instance.new("VectorForce")
			force.Name = "RagdollFloat"
			force.Attachment0 = attachment
			force.RelativeTo = Enum.ActuatorRelativeTo.World
			force.ApplyAtCenterOfMass = true
			force.Force = Vector3.new(0, part.Mass * workspace.Gravity * math.clamp(C.RagdollFloat, 0, 1), 0)
			force.Parent = part
		end
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if C.RagdollTrail and torso and torso:IsA("BasePart") then
		local a0 = Instance.new("Attachment")
		a0.Name = "RagdollTrailAttachment"
		a0.Position = Vector3.new(0, 0.8, 0)
		a0.Parent = torso
		local a1 = Instance.new("Attachment")
		a1.Name = "RagdollTrailAttachment"
		a1.Position = Vector3.new(0, -0.8, 0)
		a1.Parent = torso
		local trail = Instance.new("Trail")
		trail.Name = "RagdollTrail"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.8
		trail.FaceCamera = true
		trail.LightEmission = 0.6
		trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 210, 90))
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.Parent = torso
	end
end

local function removeRagdollEffects(character: Model)
	for _, item in character:GetDescendants() do
		if
			item.Name == "RagdollFloat"
			or item.Name == "RagdollFloatAttachment"
			or item.Name == "RagdollTrail"
			or item.Name == "RagdollTrailAttachment"
		then
			item:Destroy()
		end
	end
end

-- Server hat die Ragdoll gebaut: Figur schlaff schalten und wegschleudern.
-- (Unsere Figur rechnet dieser Client, deshalb setzen wir Zustand und Tempo hier.)
-- Kommt die Ragdoll ohne eigenen Crash (z. B. Game Over durch einen Treffer, oder der
-- Server kannte keine Helm-Ladung mehr), gilt das jetzt als Crash.
local function onRagdoll()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return
	end
	if not crashed then
		local cart = OwnCart.find()
		local base = cart and cart:FindFirstChild("Base")
		enterCrashed(if base and base:IsA("BasePart") then base else nil)
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
	addRagdollEffects(character)
	SoundSystem.play("Ragdoll")
end

-- Leben/Helm vom Server
local function onLives(lives: number, maxLives: number, shield: number, maxShield: number)
	local lost = lives < lifeState.lives and maxLives == lifeState.maxLives
	lifeState.lives, lifeState.maxLives = lives, maxLives
	lifeState.shield, lifeState.maxShield = shield, maxShield
	ProgressUI.setLives(lives, maxLives, shield, maxShield)
	Abilities.setShield(shield, maxShield)
	if lost and lives > 0 then
		SoundSystem.play("LifeLost")
		RaceUI.showToast(`-1 Leben (noch {lives})`, 2, Color3.fromRGB(255, 110, 100))
	end
end

-- 0 Leben: lustiger Game-Over-Screen; der Server startet danach selbst neu (T: sofort)
local function onGameOver(info: { hits: number, coins: number, time: number? })
	gameOver = true
	GhostClient.stopRun()
	runPhase = "GameOver"
	RaceUI.hideMessage()
	local L = Config.Lives
	local title = L.GameOverTitles[math.random(1, #L.GameOverTitles)]
	local text = L.GameOverTexts[math.random(1, #L.GameOverTexts)]
	local lines = {
		`Getroffene Objekte: {info.hits}`,
		`Muenzen in diesem Lauf: {info.coins} (die behaeltst du!)`,
	}
	if info.time then
		table.insert(lines, "Gefahren: " .. RaceTime.format(info.time))
	end
	table.insert(lines, "")
	table.insert(lines, "T: sofort neu starten")
	RaceUI.showGameOver(title, text, lines)
	SoundSystem.play("GameOver")
end

-- Antwort des Servers: Wagen steht wieder am Start.
local function onReset(spawnCFrame: CFrame)
	crashDetector:reset()
	crashed = false
	crashToken += 1
	previousVelocity = Vector3.zero
	RaceUI.hideMessage()
	if controller then
		controller:resetDrift() -- Neustart: Boost-Ladung leeren
		controller:settle() -- und kurz ruhig stellen
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character then
		removeRagdollEffects(character)
	end
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
		Rewind.clear() -- Neustart/Checkpoint: nicht in die Zeit davor zurueckspulen
		if not keepRunning then
			-- kompletter Neustart: neuer Lauf. Beim Checkpoint-Neustart laeuft die Zeit weiter.
			runPhase = "Ready"
			gameOver = false
			GhostClient.stopRun()
			Tricks.cancel()
			RaceUI.hideResult()
			RaceUI.hideGameOver()
			Abilities.reset("Full")
			LaunchablesClient.resetAll() -- weggeschleuderte Objekte stehen wieder
			Toolkit.reset("Full")
		end
		if keepRunning then
			Abilities.reset("Checkpoint")
			Toolkit.reset("Checkpoint")
		end
		onReset(spawnCFrame)
	elseif kind == "Events" then
		-- neuer Lauf: Server hat gewuerfelt, welche Zufallsereignisse aktiv sind
		RandomEventsClient.setSelection(...)
	elseif kind == "Checkpoint" then
		-- Abstand zur Bestzeit an diesem Checkpoint: gruen = schneller, rot = langsamer
		local _elapsed: number, delta: number? = ...
		if delta then
			local color = if delta <= 0 then Color3.fromRGB(110, 255, 120) else Color3.fromRGB(255, 90, 80)
			RaceUI.showToast("Checkpoint   " .. RaceTime.formatDelta(delta), 2, color)
		else
			RaceUI.showToast("Checkpoint!")
		end
		SoundSystem.play("Checkpoint")
	elseif kind == "Best" then
		local best: number? = ...
		RaceUI.setBest(best)
	elseif kind == "WrongCheckpoint" then
		RaceUI.showToast("Falscher Checkpoint - falsche Reihenfolge!", 2)
	elseif kind == "Ragdoll" then
		onRagdoll()
	elseif kind == "Lives" then
		onLives(...)
	elseif kind == "Launch" then
		LaunchablesClient.onLaunch(...)
	elseif kind == "LaunchRejected" then
		LaunchablesClient.onRejected(...)
	elseif kind == "GameOver" then
		onGameOver(...)
	elseif kind == "Shielded" then
		-- Server bestaetigt die Helm-Rettung; Ladungen kommen mit "Lives"
		local reason: string, shield: number = ...
		lifeState.shield = shield
		-- Wir hatten keine Ladung vorhergesagt (z. B. Checkpoint gerade erst erreicht) und
		-- stehen schon im Crash: Crash zuruecknehmen, der Helm hat gerettet.
		if crashed and not gameOver then
			crashed = false
			crashToken += 1 -- verzoegerten Checkpoint-Neustart abbrechen
			local cart = OwnCart.find()
			local base = cart and cart:FindFirstChild("Base")
			if base and base:IsA("BasePart") then
				helmetSave(reason, base, false)
			else
				RaceUI.hideMessage()
			end
		end
	elseif kind == "Exited" then
		onExited(...)
	elseif kind == "Aborted" then
		GhostClient.stopRun()
		runPhase = "Aborted"
		RaceUI.showMessage("Lauf abgebrochen", Color3.fromRGB(255, 200, 80), "R: Neustart", 2)
	elseif kind == "Started" then
		GhostClient.startRun() -- Geist faehrt los
		runPhase = "Running"
		ShopUI.close() -- Lauf beginnt: Menue zu
		runStartedAt = os.clock()
	elseif kind == "Finished" then
		local result: RunResult = ...
		runPhase = "Finished"
		StatReporter.flush()
		finishedTime = result.time
		RaceUI.setBest(result.bestTime)
		showResult(result)
		SoundSystem.play("Finish")
		VisualFX.confetti(result.isNewBest) -- Konfetti (neue Bestzeit: mehr)
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

-- Taste T (Gamepad: Steuerkreuz hoch): kompletter Neustart am Start, Zeit wieder 0
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

-- Roblox-Steuermodul (PlayerModule): liefert die Bewegungsrichtung von Touch-Joystick und
-- Gamepad-Stick (wie Input.GetAxis in Unity). Laedt im Hintergrund.
local playerControls: any = nil
task.spawn(function()
	local ok, module = pcall(function()
		local scripts = player:WaitForChild("PlayerScripts")
		return (require :: any)(scripts:WaitForChild("PlayerModule"))
	end)
	if ok and module then
		playerControls = module:GetControls()
	end
end)

-- Gamepad: RT = Gas, LT = Bremse/rueckwaerts (analog 0..1)
local function triggerThrottle(): number
	if not UserInputService.GamepadEnabled then
		return 0
	end
	local value = 0
	for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		local amount = input.Position.Z
		if amount > Config.Input.TriggerDeadzone then
			if input.KeyCode == Enum.KeyCode.ButtonR2 then
				value += amount
			elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
				value -= amount
			end
		end
	end
	return value
end

-- Gas (-1..1) und Lenkung (-1..1) aus Tastatur, Gamepad (Stick + Trigger) und Touch-Joystick
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
	-- Stick / Touch-Joystick: nach vorne = Gas, zur Seite = lenken. Die Tastatur steckt hier
	-- auch drin, deshalb nur nehmen, wenn keine Taste gedrueckt ist.
	local controls = playerControls
	if controls and throttle == 0 and steer == 0 then
		local ok, move = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(move) == "Vector3" then
			throttle = -move.Z
			steer = move.X
			-- Lenkung ab kleiner Auslenkung voll (der Stick soll nicht "zaeh" wirken)
			steer = math.clamp(steer * Config.Input.StickSteerGain, -1, 1)
		end
	end
	throttle = math.clamp(throttle + triggerThrottle(), -1, 1)
	return throttle, steer
end

-- PreSimulation laeuft direkt vor jedem Physik-Schritt (wie FixedUpdate in Unity).
RunService.PreSimulation:Connect(function(dt)
	updateSeat()
	RaceUI.setSpeedometerVisible(controller ~= nil)
	-- Timer laeuft auch weiter, wenn man gerade nicht faehrt (z. B. als Ragdoll)
	if runPhase == "Aborted" then
		RaceUI.setTimerInvalid()
	else
		RaceUI.setTimer(currentRunTime())
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	EnterPrompt.update(controller == nil and not crashed and humanoid ~= nil and humanoid.Health > 0)

	-- Sicherheitsnetz: falls die Neustart-Anfrage nach einem Crash verloren ging, nochmal fragen
	if crashed and not gameOver and os.clock() - crashedAt > Config.Crash.RestartDelay + 1 then
		crashedAt = os.clock()
		requestRestartNow("Checkpoint")
	end

	local current = controller
	if not current then
		DriftEffects.update(dt, nil) -- alte Reifenspuren verblassen trotzdem weiter
		Toolkit.step({ dt = dt }) -- Baukasten laeuft weiter (z. B. Auto-Strom)
		return
	end
	if not current.base:IsDescendantOf(workspace) then
		deactivate()
		return
	end
	-- Rueckspulen: solange die Taste gehalten wird, keine Fahrphysik und keine Crash-Erkennung
	if not crashed and Rewind.step(dt, current) then
		crashDetector:reset()
		return
	end
	if not crashed then
		Rewind.record(dt, current.base)
	end
	local throttle, steer = readInput()
	lastSteer = steer
	-- Shift zaehlt nur, wenn nicht gerade im Chat getippt wird
	local shift = shiftHeld and UserInputService:GetFocusedTextBox() == nil
	-- Flugmodus (F2 -> Cheats / Test): Leertaste steigen, Shift sinken, keine Fahrphysik
	local typing = UserInputService:GetFocusedTextBox() ~= nil
	if not crashed and FlyMode.step(dt, current, throttle, steer, jumpHeld and not typing, shift) then
		hopRequested = false
		crashDetector:reset()
		Toolkit.step({ dt = dt, cart = current.cart, base = current.base, controller = current })
		CoinsClient.update(current.base)
		RaceUI.setSpeed(current.base.AssemblyLinearVelocity.Magnitude)
		return
	end
	local driftMode = if Config.Drift.DriftByDefault then not shift else shift
	local surface = TrackSensors.sampleGround(current.cart)
	local hop = hopRequested and UserInputService:GetFocusedTextBox() == nil
	hopRequested = false
	-- Abilities (Sprungfeder, Turbo, Fallschirm ...): vor und nach der Fahrphysik
	local abilityContext: Abilities.StepContext = {
		controller = current,
		telemetry = nil,
		character = player.Character,
		jumpPressed = hop,
		jumpHeld = jumpHeld and UserInputService:GetFocusedTextBox() == nil,
		dt = dt,
		expectImpulse = function(delta: Vector3)
			crashDetector:expectVelocityChange(delta)
		end,
		effects = abilityEffects,
	}
	if not crashed then
		Abilities.beforeStep(abilityContext)
	end
	local telemetry = current:step(dt, throttle, steer, driftMode, hop, surface)
	if not crashed then
		abilityContext.telemetry = telemetry
		Abilities.afterStep(abilityContext)
		-- Lufttricks: drehen in der Luft, Landung bewerten (schief = Crash)
		if Tricks.step(dt, current, telemetry, runPhase == "Running") == "Crash" then
			onCrash("BadLanding", current.base, "Schief gelandet!")
			return
		end
	end
	-- Baukasten (Trigger, Spawner, Kraftzonen ...): nach der Fahrphysik, damit zusaetzliche
	-- Kraefte (ForceZone) in diesem Physik-Schritt gelten. Im Crash kein Wagen (keine Trigger).
	if crashed then
		Toolkit.step({ dt = dt })
	else
		Toolkit.step({ dt = dt, cart = current.cart, base = current.base, controller = current })
	end
	if not crashed then
		CoinsClient.update(current.base)
		-- Launchable getroffen: Hit-Stop, Kamera-Wackeln; ein riesiger Tempo-Sprung ist hier
		-- kein Crash (der Wagen steht kurz still und faehrt dann weiter)
		LaunchablesClient.update(current.cart, current.base, function()
			local L = Config.Launch
			current:hitStop(L.HitStop, L.HitSpeedKeep)
			crashDetector:relaxImpact(math.huge, L.HitStop + 0.5)
			ChaseCamera.addShake(L.HitShake)
		end)
	end

	-- Bouncy: federt ab, ein harter Aufprall ist hier kein Crash
	if TrackSensors.touching(current.cart, "Bouncy") then
		crashDetector:relaxImpact(math.huge, Config.Track.BouncyCrashGrace)
	end
	-- Baukasten-Objekte ohne Hazard (Steine, Autos, Props, Hund) schubsen nur
	if TrackSensors.touching(current.cart, "SoftHit") then
		crashDetector:relaxImpact(math.huge, Config.Toolkit.SoftHitGrace)
	end
	-- Nach einem JumpPad: Landung darf haerter sein (bis zur Landung plus etwas Puffer)
	if telemetry.padEvent == "Jump" then
		local airTime = 2 * Config.Track.JumpPadStrength / math.max(workspace.Gravity, 1) + 1
		crashDetector:relaxImpact(Config.Track.JumpLandingTolerance, airTime)
	end
	DriftEffects.update(dt, telemetry)
	VisualFX.update(dt, telemetry) -- Speed-Linien, Boost-Flammen
	StatReporter.step(dt, telemetry, runPhase == "Running") -- Driftzeit fuer die Hausaufgaben
	SoundSystem.update(telemetry.speed, telemetry.grounded, telemetry.skidding)
	if telemetry.padEvent == "Boost" or telemetry.boostStarted then
		SoundSystem.play("Boost")
		ChaseCamera.kickFov(Config.Camera.BoostFovKick)
	end
	RaceUI.setSpeed(telemetry.speed)

	-- Harte Landung: Fallgeschwindigkeit kurz vor dem Aufsetzen bestimmt das Wackeln
	if telemetry.grounded and not wasGrounded then
		local fallSpeed = -previousVelocity.Y
		local C = Config.Camera
		if fallSpeed > C.LandingShakeMinSpeed then
			ChaseCamera.addShake((fallSpeed - C.LandingShakeMinSpeed) * C.LandingShakePerSpeed)
		end
		VisualFX.landing(fallSpeed) -- Staubwolke
	end
	wasGrounded = telemetry.grounded

	-- Hazard: sofortiger Crash bei Beruehrung
	local protected = os.clock() < helmetGraceUntil -- kurz nach einer Helm-Rettung
	local hazard = if crashed or protected then nil else TrackSensors.touching(current.cart, "Hazard")
	if hazard then
		local message = hazard:GetAttribute("Message")
		-- Treffer durch ein Objekt (Stein, Hund): wie ein Aufprall (Helm: weiterfahren);
		-- sonst Wasser/Grube (Helm: zurueck zum Checkpoint)
		onCrash(
			if hazard:GetAttribute("HazardHit") == true then "HitHazard" else "Hazard",
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

	-- Unter das Terrain geraten (durchgefallen)? Zurueck auf die Oberflaeche statt Crash.
	-- Der Sprung nach oben ist kein Aufprall: Crash-Erkennung zuruecksetzen.
	if not crashed and TerrainRescue.step(dt, current) then
		crashDetector:reset()
		current:settle()
		ChaseCamera.snap()
	end

	if not crashed then
		local reason = crashDetector:update(dt, current.base)
		if reason and not protected then
			onCrash(reason, current.base)
		end
	end
	previousVelocity = current.base.AssemblyLinearVelocity
end)
