--!strict
-- Fahrphysik des Einkaufswagens. Laeuft auf dem Client des Fahrers, weil dieser die
-- Physik seines Wagens rechnet (Network Ownership). Jeden Physik-Frame werden aus der
-- Eingabe eine Kraft (DriveForce) und ein Drehmoment (SteerTorque) berechnet.
--
-- Unity-Vergleich: wie AddForce/AddTorque in FixedUpdate, nur dass hier die Werte an
-- Constraint-Objekten gesetzt werden, die bis zum naechsten Frame wirken.
--
-- Drift (Handbremse): Die Lenkung bestimmt weiter, wie schnell sich der Wagen dreht (die
-- Front "zieht"), nur staerker als normal. Der Seitenhalt wird weicher, also laeuft die
-- Fahrtrichtung der Drehung hinterher und das Heck schwingt aus. Ueber der Winkelgrenze
-- dreht der Wagen zurueck und haelt fester. Weil die Drehung immer geregelt bleibt, kann
-- sich der Wagen nicht von selbst aufschaukeln (kein Dreher).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local TrackSensors = require(script.Parent:WaitForChild("TrackSensors"))

local CartController = {}
CartController.__index = CartController

export type Telemetry = {
	speed: number,
	forwardSpeed: number,
	grounded: boolean,
	driftAmount: number, -- 0 = normal, 1 = Handbremse voll
	slipAngle: number, -- Grad zwischen Blick- und Fahrtrichtung
	driftCharging: boolean, -- Driftzeit zaehlt gerade (fuer Funken)
	boostLevel: number, -- 0, 1 oder 2 (aktuelle Ladung)
	boosting: boolean,
	onMud: boolean,
	onIce: boolean,
	padEvent: string?, -- "Boost" oder "Jump", wenn in diesem Frame ein Pad ausgeloest hat
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
	wasHandbrake: boolean,
	boostTime: number, -- Restzeit des laufenden Schubs
	boostAcceleration: number,
	padCooldowns: { [Instance]: number }, -- wann welches Pad zuletzt unter dem Wagen war
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
		wasHandbrake = false,
		boostTime = 0,
		boostAcceleration = 0,
		padCooldowns = {},
	}, CartController)
	return self
end

function CartController.isGrounded(self: Controller): boolean
	local cf = self.base.CFrame
	local length = Config.Cart.WheelDiameter + Config.Cart.WheelGap + Config.Cart.FloorThickness / 2
	length += Config.Drive.GroundCheckExtra
	return workspace:Raycast(cf.Position, -cf.UpVector * length, self.rayParams) ~= nil
end

-- Aktuelle Boost-Stufe aus der gesammelten Driftzeit
local function boostLevelFor(driftTime: number): number
	if driftTime >= Config.Drift.Level2Time then
		return 2
	elseif driftTime >= Config.Drift.Level1Time then
		return 1
	end
	return 0
end

-- Drift-Ladung und laufenden Boost verwerfen (Crash, Neustart, Aussteigen).
function CartController.resetDrift(self: Controller)
	self.driftAmount = 0
	self.driftTime = 0
	self.wasHandbrake = false
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
		local delta = TrackSensors.pieceCFrame(boostPad).LookVector * strength
		addVelocity(self.cart, delta)
		impulse += delta
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
		event = "Jump"
	end
	return event, impulse
end

-- throttle: -1 (S) .. 1 (W), steer: -1 (A) .. 1 (D), handbrake: Shift gedrueckt,
-- surface: Streckenbausteine unter den Raedern (siehe TrackSensors)
function CartController.step(
	self: Controller,
	dt: number,
	throttle: number,
	steer: number,
	handbrake: boolean,
	surface: TrackSensors.Surface
): Telemetry
	local D = Config.Drive
	local DR = Config.Drift
	local base = self.base
	local cf = base.CFrame
	local up, forward, right = cf.UpVector, cf.LookVector, cf.RightVector
	local velocity = base.AssemblyLinearVelocity
	local angular = base.AssemblyAngularVelocity
	self.time += dt
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

	local speed = velocity.Magnitude
	local forwardSpeed = velocity:Dot(forward)
	local lateralSpeed = velocity:Dot(right)
	local grounded = self:isGrounded()

	-- Driftwinkel: positiv, wenn die Fahrtrichtung rechts von der Blickrichtung liegt
	local slipAngle = if speed > 1 then math.deg(math.atan2(lateralSpeed, math.abs(forwardSpeed))) else 0

	-- Handbremse weich ein- und ausblenden (0 = normal, 1 = voller Drift)
	if handbrake then
		self.driftAmount = math.min(1, self.driftAmount + dt / math.max(DR.EngageTime, 0.01))
	else
		self.driftAmount = math.max(0, self.driftAmount - dt / math.max(DR.GripRecoverTime, 0.01))
	end
	local drift = self.driftAmount

	-- Driftzeit zaehlt nur am Boden, ab Mindesttempo und Mindest-Driftwinkel
	-- (sonst koennte man den Boost im Stand "farmen").
	-- Auf Schlamm pausiert die Ladung.
	local driftCharging = handbrake
		and grounded
		and not onMud
		and speed >= DR.MinSpeed
		and math.abs(slipAngle) >= DR.MinAngle
	if driftCharging then
		self.driftTime += dt
	end

	-- Handbremse losgelassen: Boost je nach Ladung, dann Ladung leeren
	if self.wasHandbrake and not handbrake then
		local level = boostLevelFor(self.driftTime)
		if level > 0 then
			local share = if level == 2 then DR.Level2Boost else DR.Level1Boost
			local gain = share * D.MaxPushSpeed -- Tempo-Zuwachs in Studs/s (Anteil am Motor-Hoechsttempo)
			self.boostTime = DR.BoostDuration
			self.boostAcceleration = gain / math.max(DR.BoostDuration, 0.05)
		end
		self.driftTime = 0
	end
	self.wasHandbrake = handbrake

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

		-- Handbremse bremst leicht
		if drift > 0 and math.abs(forwardSpeed) > 1 then
			force -= forward * math.sign(forwardSpeed) * DR.HandbrakeDeceleration * drift * m
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

		-- Wackelrad: langsames, zufaelliges Ziehen zur Seite
		local wobble = math.clamp(math.noise(self.time * D.WobbleFrequency, self.wobbleSeed) * 2, -1, 1)
		targetYawRate += wobble * D.WobbleStrength * math.clamp(absSpeed / D.WobbleFullSpeed, 0, 1)

		-- Wirres Heck: im Drift kleines, unregelmaessiges Pendeln
		local tail =
			math.clamp(math.noise(self.time * DR.TailWobbleFrequency, self.wobbleSeed + 17) * 2, -1, 1)
		targetYawRate += tail * DR.TailWobble * drift * math.clamp(absSpeed / D.SteerFullSpeed, 0, 1)

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
		boostLevel = boostLevelFor(self.driftTime),
		boosting = boosting,
		onMud = onMud,
		onIce = onIce,
		padEvent = padEvent,
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
