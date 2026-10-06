--!strict
-- Fahrphysik des Einkaufswagens. Laeuft auf dem Client des Fahrers, weil dieser die
-- Physik seines Wagens rechnet (Network Ownership). Jeden Physik-Frame werden aus der
-- Eingabe eine Kraft (DriveForce) und ein Drehmoment (SteerTorque) berechnet.
--
-- Unity-Vergleich: wie AddForce/AddTorque in FixedUpdate, nur dass hier die Werte an
-- Constraint-Objekten gesetzt werden, die bis zum naechsten Frame wirken.
--
-- Drift (Standard-Modus; Shift = normal fahren, siehe Config.Drift.DriftByDefault): Die
-- Lenkung bestimmt weiter, wie schnell sich der Wagen dreht (die Front "zieht"), nur
-- staerker als normal. Der Seitenhalt wird weicher, also laeuft die
-- Fahrtrichtung der Drehung hinterher und das Heck schwingt aus. Ueber der Winkelgrenze
-- dreht der Wagen zurueck und haelt fester. Weil die Drehung immer geregelt bleibt, kann
-- sich der Wagen nicht von selbst aufschaukeln (kein Dreher).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Vehicles = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Vehicles"))
local TrackSensors = require(script.Parent:WaitForChild("TrackSensors"))

local CartController = {}
CartController.__index = CartController

export type Telemetry = {
	speed: number,
	forwardSpeed: number,
	grounded: boolean,
	driftAmount: number, -- 0 = normal, 1 = voller Drift-Modus
	slipAngle: number, -- Grad zwischen Blick- und Fahrtrichtung
	driftCharging: boolean, -- Driftzeit zaehlt gerade (fuer Funken)
	skidding: boolean, -- rutscht sichtbar seitlich, also in einer Kurve (Reifenspuren, Quietschen)
	boostLevel: number, -- 0, 1 oder 2 (aktuelle Ladung)
	boosting: boolean,
	boostStarted: boolean, -- in diesem Frame hat ein Drift-Boost begonnen
	onMud: boolean,
	onIce: boolean,
	padEvent: string?, -- "Boost" oder "Jump", wenn in diesem Frame ein Pad ausgeloest hat
	hopped: boolean, -- in diesem Frame gehuepft
	-- Tempo-Sprung, den der Wagen in diesem Frame selbst verursacht hat (Pads usw.).
	-- Die Crash-Erkennung zieht ihn ab, damit er nicht als Aufprall zaehlt.
	selfImpulse: Vector3,
}

type ControllerData = {
	cart: Model,
	base: BasePart,
	driveForce: VectorForce,
	steerTorque: Torque,
	mass: number,
	inertia: number,
	rayParams: RaycastParams,
	time: number,
	nextMeasure: number,
	wobbleSeed: number,
	-- Drift und Boost
	driftAmount: number,
	driftTime: number,
	wasDriftMode: boolean,
	straightTime: number, -- so lange (s) faehrt der Wagen nach einem Drift schon wieder gerade
	boostTime: number, -- Restzeit des laufenden Schubs
	boostAcceleration: number,
	padCooldowns: { [Instance]: number }, -- wann welches Pad zuletzt unter dem Wagen war
	hopTime: number, -- Sekunden seit dem letzten Hopp
	settleTime: number, -- Restzeit der Beruhigung nach Einsteigen/Neustart
	freezeTime: number, -- Hit-Stop: Restzeit, in der der Wagen still steht
	freezeVelocity: Vector3, -- Tempo nach dem Hit-Stop
	hopSpeedOverride: number?, -- Sprung-Tempo statt Config.Hop.Speed (Sprungfeder)
	stats: Vehicles.Stats, -- Fahrwerte des Fahrzeugs (Config.Cart/Drive/Drift/Hop mit Aenderungen)
}

export type Controller = typeof(setmetatable({} :: ControllerData, CartController))

-- Masse und Traegheitsmoment (um die Hochachse) des ganzen Wagens schaetzen.
-- Damit rechnen wir Beschleunigungen aus der Config in Kraefte um.
local function measure(cart: Model, base: BasePart): (number, number)
	local mass, inertia = 0, 0
	local center = base.CFrame
	for _, part in cart:GetDescendants() do
		if part:IsA("BasePart") and not part.Massless then
			local m = part.Mass
			local offset = center:PointToObjectSpace(part.Position)
			local size = part.Size
			mass += m
			inertia += m * (offset.X ^ 2 + offset.Z ^ 2) + m * (size.X ^ 2 + size.Z ^ 2) / 12
		end
	end
	return math.max(mass, 0.1), math.max(inertia, 0.1)
end

function CartController.new(cart: Model, character: Model): Controller
	local base = cart:WaitForChild("Base") :: BasePart
	local mass, inertia = measure(cart, base)
	local stats = Vehicles.forCart(cart)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { cart, character }

	local self = setmetatable({
		cart = cart,
		base = base,
		driveForce = base:WaitForChild("DriveForce") :: VectorForce,
		steerTorque = base:WaitForChild("SteerTorque") :: Torque,
		mass = mass,
		inertia = inertia,
		rayParams = rayParams,
		time = 0,
		nextMeasure = 0.5,
		wobbleSeed = math.random() * 100,
		driftAmount = 0,
		driftTime = 0,
		wasDriftMode = false,
		straightTime = 0,
		boostTime = 0,
		boostAcceleration = 0,
		padCooldowns = {},
		hopTime = math.huge,
		settleTime = stats.Drive.SettleTime,
		freezeTime = 0,
		freezeVelocity = Vector3.zero,
		hopSpeedOverride = nil,
		stats = stats,
	}, CartController)
	return self
end

function CartController.isGrounded(self: Controller): boolean
	local cf = self.base.CFrame
	local c = self.stats.Cart
	local length = c.WheelDiameter + c.WheelGap + c.FloorThickness / 2
	length += self.stats.Drive.GroundCheckExtra
	return workspace:Raycast(cf.Position, -cf.UpVector * length, self.rayParams) ~= nil
end

-- Aktuelle Boost-Stufe aus der gesammelten Driftzeit
local function boostLevelFor(driftTime: number, DR: typeof(Config.Drift)): number
	if driftTime >= DR.Level2Time then
		return 2
	elseif driftTime >= DR.Level1Time then
		return 1
	end
	return 0
end

-- Nach einem Neustart: kurz Restdrehungen wegdaempfen (wie nach dem Einsteigen)
function CartController.settle(self: Controller)
	self.settleTime = self.stats.Drive.SettleTime
	self.freezeTime = 0 -- laufender Hit-Stop gilt nach dem Neustart nicht mehr
	self.freezeVelocity = Vector3.zero
end

-- Drift-Ladung und laufenden Boost verwerfen (Crash, Neustart, Aussteigen).
function CartController.resetDrift(self: Controller)
	self.driftAmount = 0
	self.driftTime = 0
	self.wasDriftMode = false
	self.straightTime = 0
	self.boostTime = 0
	self.boostAcceleration = 0
end

-- Ganzen Wagen um `delta` schneller machen. Wichtig: einmal pro Physik-Koerper (Assembly)!
-- Alle verschweissten Teile teilen sich eine Geschwindigkeit; wuerde man `delta` an jedem
-- Teil addieren, bekaeme der Korb den Schub zehnfach (das war der BoostPad-Crash-Bug).
local function addVelocity(cart: Model, delta: Vector3)
	local done: { [BasePart]: boolean } = {}
	for _, part in cart:GetDescendants() do
		if part:IsA("BasePart") then
			local root = part.AssemblyRootPart or part
			if not done[root] then
				done[root] = true
				root.AssemblyLinearVelocity += delta
			end
		end
	end
end

-- Ganzen Wagen auf ein Tempo setzen (alle Physik-Koerper) und Drehungen anhalten
local function setVelocity(cart: Model, velocity: Vector3)
	local done: { [BasePart]: boolean } = {}
	for _, part in cart:GetDescendants() do
		if part:IsA("BasePart") then
			local root = part.AssemblyRootPart or part
			if not done[root] then
				done[root] = true
				root.AssemblyLinearVelocity = velocity
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
end

-- Schnittstelle fuer Abilities -------------------------------------------------------------
-- (Aufruf nach step() im selben Frame: Kraefte gelten dann fuer diesen Physik-Schritt.)

-- Zusaetzliche Kraft (Newton-artig: Beschleunigung * Masse) fuer diesen Frame
function CartController.addForce(self: Controller, force: Vector3)
	self.driveForce.Force += force
end

-- Zusaetzliches Drehmoment fuer diesen Frame
function CartController.addTorque(self: Controller, torque: Vector3)
	self.steerTorque.Torque += torque
end

-- Sprung in der Luft (Doppelsprung): Tempo nach oben auf `speed` setzen. Danach dreht der
-- Wagen wie beim Hopp in Lenkrichtung. Gibt den Tempo-Sprung zurueck (fuer die Crash-Erkennung).
function CartController.airJump(self: Controller, speed: number): Vector3
	local current = self.base.AssemblyLinearVelocity.Y
	local delta = Vector3.yAxis * (speed - math.min(current, speed))
	addVelocity(self.cart, delta)
	self.hopTime = 0
	return delta
end

-- Schub nach vorne: `gain` Studs/s mehr Tempo, verteilt auf `duration` Sekunden
-- (wie der Drift-Boost; ein laufender Boost wird ersetzt)
function CartController.startBoost(self: Controller, gain: number, duration: number)
	self.boostTime = math.max(duration, 0.05)
	self.boostAcceleration = gain / self.boostTime
end

function CartController.getMass(self: Controller): number
	return self.mass
end

function CartController.getInertia(self: Controller): number
	return self.inertia
end

-- Hit-Stop: Wagen steht `duration` Sekunden still (schwebt), danach faehrt er mit dem
-- `keep`-fachen Tempo weiter. Fuer die Treffer-Show (Launchables).
function CartController.hitStop(self: Controller, duration: number, keep: number)
	if duration <= 0 then
		return
	end
	if self.freezeTime <= 0 then
		self.freezeVelocity = self.base.AssemblyLinearVelocity * math.clamp(keep, 0, 1)
	end
	self.freezeTime = math.max(self.freezeTime, duration)
end

-- BoostPad / JumpPad unter den Raedern ausloesen. Gibt "Boost"/"Jump" (oder nil) und den
-- verursachten Tempo-Sprung zurueck.
function CartController.applyPads(self: Controller, surface: TrackSensors.Surface): (string?, Vector3)
	local T = Config.Track
	local now = os.clock()
	-- Ein Pad loest nur beim Drauffahren aus: Solange man drauf ist, wird "zuletzt gesehen"
	-- jeden Frame erneuert. Erst wer PadCooldown Sekunden weg war, wird wieder geschoben.
	local function ready(pad: Instance): boolean
		local last = self.padCooldowns[pad]
		self.padCooldowns[pad] = now
		return last == nil or now - last >= T.PadCooldown
	end
	local event: string? = nil
	local impulse = Vector3.zero
	local boostPad = surface.boostPad
	if boostPad and ready(boostPad) then
		-- Schub in Blickrichtung des Pads
		local strength = Attributes.number(boostPad, "Strength", T.BoostPadStrength, true)
		local direction = TrackSensors.pieceCFrame(boostPad).LookVector
		local delta = direction * strength
		addVelocity(self.cart, delta)
		impulse += delta
		if Config.Debug.TrackPieces then
			local source = if type(boostPad:GetAttribute("Strength")) == "number"
				then "Attribut"
				else "Standardwert"
			local alongCart = direction:Dot(self.base.CFrame.LookVector)
			TrackSensors.debugLog(
				`BoostPad "{boostPad.Name}" ausgeloest: +{strength} Studs/s ({source}), `
					.. (
						if alongCart > 0.3
							then "Richtung passt zur Fahrtrichtung"
							else "ACHTUNG: Pad zeigt nicht in Fahrtrichtung (Part um 180 Grad drehen?)"
					)
			)
		end
		event = "Boost"
	end
	local jumpPad = surface.jumpPad
	if jumpPad and ready(jumpPad) then
		-- Tempo entlang der Oberseite des Pads auf `strength` setzen (immer gleich hoch)
		local strength = Attributes.number(jumpPad, "Strength", T.JumpPadStrength, true)
		local up = TrackSensors.pieceCFrame(jumpPad).UpVector
		local current = self.base.AssemblyLinearVelocity:Dot(up)
		local delta = up * (strength - current)
		addVelocity(self.cart, delta)
		impulse += delta
		if Config.Debug.TrackPieces then
			local source = if type(jumpPad:GetAttribute("Strength")) == "number"
				then "Attribut"
				else "Standardwert"
			TrackSensors.debugLog(
				`JumpPad "{jumpPad.Name}" ausgeloest: {strength} Studs/s nach oben ({source})`
			)
		end
		event = "Jump"
	end
	return event, impulse
end

-- throttle: -1 (S) .. 1 (W), steer: -1 (A) .. 1 (D), driftMode: Drift-Modus aktiv,
-- hopPressed: Hopp-Taste (Leertaste) wurde in diesem Frame gedrueckt,
-- surface: Streckenbausteine unter den Raedern (siehe TrackSensors)
function CartController.step(
	self: Controller,
	dt: number,
	throttle: number,
	steer: number,
	driftMode: boolean,
	hopPressed: boolean,
	surface: TrackSensors.Surface
): Telemetry
	local D = self.stats.Drive
	local DR = self.stats.Drift
	local base = self.base
	local cf = base.CFrame
	local up, forward, right = cf.UpVector, cf.LookVector, cf.RightVector
	local velocity = base.AssemblyLinearVelocity
	local angular = base.AssemblyAngularVelocity
	self.time += dt
	self.settleTime = math.max(0, self.settleTime - dt)

	-- Hit-Stop: stillstehen und schweben (Schwerkraft ausgleichen), danach weiterfahren
	if self.freezeTime > 0 then
		self.freezeTime -= dt
		if self.freezeTime > 0 then
			setVelocity(self.cart, Vector3.zero)
			self.driveForce.Force = Vector3.new(0, workspace.Gravity * self.mass, 0)
			self.steerTorque.Torque = Vector3.zero
			return {
				speed = 0,
				forwardSpeed = 0,
				grounded = true,
				driftAmount = self.driftAmount,
				slipAngle = 0,
				driftCharging = false,
				skidding = false,
				boostLevel = boostLevelFor(self.driftTime, DR),
				boosting = false,
				boostStarted = false,
				onMud = false,
				onIce = false,
				padEvent = nil,
				hopped = false,
				selfImpulse = Vector3.zero,
			}
		end
		setVelocity(self.cart, self.freezeVelocity)
		velocity = self.freezeVelocity
		angular = Vector3.zero
	end
	-- Masse regelmaessig neu bestimmen (das Tuning-Panel kann den Ballast verschieben)
	if self.time >= self.nextMeasure then
		self.nextMeasure = self.time + 0.5
		self.mass, self.inertia = measure(self.cart, base)
	end
	local m = self.mass

	local padEvent, selfImpulse = self:applyPads(surface)
	if padEvent then
		velocity = base.AssemblyLinearVelocity
	end
	local onMud = surface.mudFraction > 0
	local onIce = surface.iceFraction > 0
	-- Eis: Seitenhalt und Lenkhilfe nur noch ein Bruchteil (anteilig nach Raedern auf Eis)
	local gripScale = 1 + (surface.iceGrip - 1) * surface.iceFraction
	local steerScale = 1 + (Config.Track.IceSteer - 1) * surface.iceFraction

	local grounded = self:isGrounded()

	-- Hopp: kleiner Sprung nach oben, nur vom Boden aus und nicht zu oft
	local H = self.stats.Hop
	local hopped = false
	self.hopTime += dt
	if H.Enabled and hopPressed and grounded and self.hopTime >= H.Cooldown then
		local delta = up * (self.hopSpeedOverride or H.Speed)
		addVelocity(self.cart, delta)
		selfImpulse += delta
		velocity = base.AssemblyLinearVelocity
		self.hopTime = 0
		hopped = true
	end
	-- Waehrend des Hopps gilt der Wagen als in der Luft (der Boden-Strahl reicht kurz noch
	-- bis zum Boden). Dann wirkt die schnelle Luft-Drehung statt der Bodenkraefte.
	local hopActive = self.hopTime < H.MaxAirTime and (self.hopTime < H.MinAirTime or not grounded)
	if hopActive then
		grounded = false
	end

	local speed = velocity.Magnitude
	local forwardSpeed = velocity:Dot(forward)
	local lateralSpeed = velocity:Dot(right)

	-- Driftwinkel: positiv, wenn die Fahrtrichtung rechts von der Blickrichtung liegt
	local slipAngle = if speed > 1 then math.deg(math.atan2(lateralSpeed, math.abs(forwardSpeed))) else 0

	-- Drift-Modus weich ein- und ausblenden (0 = normal, 1 = voller Drift)
	if driftMode then
		self.driftAmount = math.min(1, self.driftAmount + dt / math.max(DR.EngageTime, 0.01))
	else
		self.driftAmount = math.max(0, self.driftAmount - dt / math.max(DR.GripRecoverTime, 0.01))
	end
	local drift = self.driftAmount
	-- Wie stark der Wagen gerade wirklich seitlich rutscht (0 = geradeaus, 1 = ab MinAngle).
	-- Im Drift-Modus wirken Handbremse und Heck-Pendeln nur damit, also nur in Kurven.
	local sliding = math.clamp(math.abs(slipAngle) / math.max(DR.MinAngle, 1), 0, 1)
	local skidding = grounded and speed > 10 and math.abs(slipAngle) >= DR.SkidMinAngle

	-- Driftzeit zaehlt nur am Boden, ab Mindesttempo und Mindest-Driftwinkel
	-- (sonst koennte man den Boost im Stand "farmen").
	-- Auf Schlamm pausiert die Ladung.
	local driftCharging = driftMode
		and grounded
		and not onMud
		and speed >= DR.MinSpeed
		and math.abs(slipAngle) >= DR.MinAngle
	if driftCharging then
		self.driftTime += dt
	end

	-- Drift zu Ende? Entweder der Modus wird verlassen (Shift), oder der Wagen faehrt am
	-- Boden eine Weile wieder gerade bzw. zu langsam. In der Luft (Hopp) zaehlt das nicht,
	-- so bleibt die Ladung beim Wechsel von einem Links- in einen Rechtsdrift erhalten.
	if self.driftTime > 0 and grounded and not onMud and not driftCharging then
		self.straightTime += dt
	elseif driftCharging or not grounded then
		self.straightTime = 0
	end
	local driftEnded = (self.wasDriftMode and not driftMode) or self.straightTime >= DR.ReleaseDelay
	local boostStarted = false
	if driftEnded then
		-- Boost je nach Ladung, dann Ladung leeren
		local level = boostLevelFor(self.driftTime, DR)
		if level > 0 then
			local share = if level == 2 then DR.Level2Boost else DR.Level1Boost
			local gain = share * D.MaxPushSpeed -- Tempo-Zuwachs in Studs/s (Anteil am Motor-Hoechsttempo)
			self.boostTime = DR.BoostDuration
			self.boostAcceleration = gain / math.max(DR.BoostDuration, 0.05)
			boostStarted = true
		end
		self.driftTime = 0
		self.straightTime = 0
	end
	self.wasDriftMode = driftMode

	local boosting = self.boostTime > 0
	if boosting then
		self.boostTime -= dt
	end

	-- Leichter Luftwiderstand wirkt immer. Bergab darf der Wagen schneller werden als das
	-- Motor-Hoechsttempo; nur ganz oben (TerminalSpeed) bremst eine Sicherheitsgrenze, damit
	-- die Physik nicht durch Waende "tunnelt".
	local force = -velocity * speed * D.AirDrag * m
	if speed > D.TerminalSpeed then
		force -= velocity.Unit * (speed - D.TerminalSpeed) * 10 * m
	end
	if boosting then
		force += forward * self.boostAcceleration * m
	end
	local torque = Vector3.zero

	if grounded then
		-- Ausrollen: nur ohne Gas (W) bremst der Rollwiderstand, sanft wie in echt
		if throttle <= 0 then
			force -= forward * forwardSpeed * D.RollingResistance * m
		end

		-- Schlamm: bremst in alle Richtungen am Boden, anteilig nach Raedern im Schlamm
		if onMud then
			local groundVelocity = velocity - up * velocity:Dot(up)
			force -= groundVelocity * surface.mudDrag * surface.mudFraction * m
		end

		-- Anschieben / Bremsen / Rueckwaerts
		if throttle > 0 then
			if forwardSpeed < D.MaxPushSpeed then
				force += forward * D.PushAcceleration * throttle * m
			end
		elseif throttle < 0 then
			if forwardSpeed > 1 then
				-- nicht staerker bremsen, als noetig ist, um anzuhalten
				local decel = math.min(D.BrakeAcceleration, forwardSpeed / math.max(dt, 1 / 240))
				force -= forward * decel * -throttle * m
			elseif forwardSpeed > -D.MaxReverseSpeed then
				force -= forward * D.ReverseAcceleration * -throttle * m
			end
		end

		-- Rutschen bremst leicht (geradeaus nicht, sonst wuerde der Drift-Modus bergab bremsen)
		if drift > 0 and math.abs(forwardSpeed) > 1 then
			force -= forward * math.sign(forwardSpeed) * DR.HandbrakeDeceleration * drift * sliding * m
		end

		-- Driftwinkel ueber der Grenze? (0 = nein; 1 = 15 Grad oder mehr darueber)
		local excess = math.abs(slipAngle) - DR.RecoverAngle
		local overLimit = if drift > 0 and speed > 5 then math.clamp(excess / 15, 0, 1) else 0

		-- Seitenhalt im Schwerpunkt: im Drift weicher (Heck schwingt aus), ueber der
		-- Winkelgrenze wieder fester (Heck kommt zurueck, bricht nie ganz aus).
		local lateralGrip = (D.LateralGrip + (DR.LateralGrip - D.LateralGrip) * drift) * gripScale
		lateralGrip *= 1 + 2 * overLimit
		local maxGrip = D.MaxGripAcceleration * gripScale
		force += right * math.clamp(-lateralSpeed * lateralGrip, -maxGrip, maxGrip) * m

		-- Lenkung: Ziel-Drehgeschwindigkeit um die Hochachse, abhaengig vom Tempo.
		-- Im Drift staerker: Die Front "zieht" den Wagen durch die Kurve.
		local absSpeed = math.abs(forwardSpeed)
		local factor = math.clamp(absSpeed / D.SteerFullSpeed, D.SteerMinFactor, 1)
		local highSpeed =
			math.clamp((absSpeed - D.SteerFullSpeed) / math.max(D.SteerHighSpeed - D.SteerFullSpeed, 1), 0, 1)
		factor *= 1 + (D.SteerHighSpeedFactor - 1) * highSpeed
		local direction = if forwardSpeed < -1 then -1 else 1 -- rueckwaerts: Lenkung umgekehrt
		-- Positive Drehung um Y ist in Roblox eine Linksdrehung, deshalb das Minus.
		local steerRate = D.SteerRate + (DR.SteerRate - D.SteerRate) * drift
		local targetYawRate = -steer * steerRate * factor * direction

		-- Wackelrad: langsames, zufaelliges Ziehen zur Seite. Erst ab einem Mindesttempo
		-- und nach dem Einsteigen weich eingeblendet (sonst ruckelt es beim Losfahren).
		local wobble = math.clamp(math.noise(self.time * D.WobbleFrequency, self.wobbleSeed) * 2, -1, 1)
		local wobbleSpeed = math.clamp(
			(absSpeed - D.WobbleMinSpeed) / math.max(D.WobbleFullSpeed - D.WobbleMinSpeed, 1),
			0,
			1
		)
		local wobbleFade = math.clamp(self.time / math.max(D.WobbleFadeInTime, 0.01), 0, 1)
		targetYawRate += wobble * D.WobbleStrength * wobbleSpeed * wobbleFade

		-- Wirres Heck: im Drift kleines, unregelmaessiges Pendeln, nur solange der Wagen rutscht
		-- (geradeaus kein zusaetzlicher Drall)
		local tail =
			math.clamp(math.noise(self.time * DR.TailWobbleFrequency, self.wobbleSeed + 17) * 2, -1, 1)
		targetYawRate += tail * DR.TailWobble * drift * sliding * math.clamp(
			absSpeed / D.SteerFullSpeed,
			0,
			1
		)

		-- Winkelgrenze: zu weit ausgeschwungen -> Blickrichtung zur Fahrtrichtung zurueckdrehen.
		-- Positiver Winkel = Fahrtrichtung liegt rechts = nach rechts drehen (negatives Y).
		if overLimit > 0 then
			targetYawRate -= math.sign(slipAngle) * math.rad(excess) * DR.RecoverStrength
		end

		local yawRate = angular:Dot(up)
		local response = D.SteerResponse * (1 + (DR.SteerResponseFactor - 1) * drift) * steerScale
		torque += up * (targetYawRate - yawRate) * response * self.inertia

		-- Kipp- und Nickbewegungen etwas daempfen (nicht verhindern!)
		local otherRotation = angular - up * yawRate
		torque -= otherRotation * D.RollDamping * self.inertia

		-- Gerade eingestiegen / neu gestartet: Restdrehungen kraeftig wegdaempfen
		if self.settleTime > 0 then
			torque -= angular * D.SettleDamping * self.inertia
		end
	elseif hopActive then
		-- Hopp-Drehung in der Luft: schnell in Lenkrichtung drehen (Fahrtrichtung bleibt),
		-- so landet man direkt im Drift in die neue Richtung.
		local yawRate = angular:Dot(up)
		local targetYawRate = -steer * H.TurnRate
		torque += up * (targetYawRate - yawRate) * H.TurnResponse * self.inertia
	end

	self.driveForce.Force = force
	self.steerTorque.Torque = torque

	return {
		speed = speed,
		forwardSpeed = forwardSpeed,
		grounded = grounded,
		driftAmount = drift,
		slipAngle = slipAngle,
		driftCharging = driftCharging,
		skidding = skidding,
		boostLevel = boostLevelFor(self.driftTime, DR),
		boosting = boosting,
		boostStarted = boostStarted,
		onMud = onMud,
		onIce = onIce,
		padEvent = padEvent,
		hopped = hopped,
		selfImpulse = selfImpulse,
	}
end

-- Alle Kraefte aus (z. B. wenn der Spieler aussteigt).
function CartController.stop(self: Controller)
	if self.driveForce.Parent then
		self.driveForce.Force = Vector3.zero
		self.steerTorque.Torque = Vector3.zero
	end
end

return CartController
