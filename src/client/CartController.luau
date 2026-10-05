--!strict
-- Fahrphysik des Einkaufswagens. Laeuft auf dem Client des Fahrers, weil dieser die
-- Physik seines Wagens rechnet (Network Ownership). Jeden Physik-Frame werden aus der
-- Eingabe eine Kraft (DriveForce) und ein Drehmoment (SteerTorque) berechnet.
--
-- Unity-Vergleich: wie AddForce/AddTorque in FixedUpdate, nur dass hier die Werte an
-- Constraint-Objekten gesetzt werden, die bis zum naechsten Frame wirken.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local CartController = {}
CartController.__index = CartController

export type Telemetry = {
	speed: number,
	forwardSpeed: number,
	grounded: boolean,
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
	wobbleSeed: number,
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
		wobbleSeed = math.random() * 100,
	}, CartController)
	return self
end

function CartController.isGrounded(self: Controller): boolean
	local cf = self.base.CFrame
	local length = Config.Cart.WheelDiameter + Config.Cart.WheelGap + Config.Cart.FloorThickness / 2
	length += Config.Drive.GroundCheckExtra
	return workspace:Raycast(cf.Position, -cf.UpVector * length, self.rayParams) ~= nil
end

-- throttle: -1 (S) .. 1 (W), steer: -1 (A) .. 1 (D)
function CartController.step(self: Controller, dt: number, throttle: number, steer: number): Telemetry
	local D = Config.Drive
	local base = self.base
	local cf = base.CFrame
	local up, forward, right = cf.UpVector, cf.LookVector, cf.RightVector
	local velocity = base.AssemblyLinearVelocity
	local angular = base.AssemblyAngularVelocity
	local m = self.mass
	self.time += dt

	local speed = velocity.Magnitude
	local forwardSpeed = velocity:Dot(forward)
	local grounded = self:isGrounded()

	-- Luftwiderstand wirkt immer (begrenzt das Tempo bergab)
	local force = -velocity * speed * D.AirDrag * m
	local torque = Vector3.zero

	if grounded then
		-- Rollwiderstand
		force -= forward * forwardSpeed * D.RollingResistance * m

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

		-- Seitenhalt: seitliches Rutschen abbremsen, aber nur bis zur Grip-Grenze (Drift)
		local lateralSpeed = velocity:Dot(right)
		local grip = math.clamp(-lateralSpeed * D.LateralGrip, -D.MaxGripAcceleration, D.MaxGripAcceleration)
		force += right * grip * m

		-- Lenkung: Ziel-Drehgeschwindigkeit um die Hochachse, abhaengig vom Tempo
		local absSpeed = math.abs(forwardSpeed)
		local factor = math.clamp(absSpeed / D.SteerFullSpeed, D.SteerMinFactor, 1)
		local highSpeed =
			math.clamp((absSpeed - D.SteerFullSpeed) / math.max(D.SteerHighSpeed - D.SteerFullSpeed, 1), 0, 1)
		factor *= 1 + (D.SteerHighSpeedFactor - 1) * highSpeed
		local direction = if forwardSpeed < -1 then -1 else 1 -- rueckwaerts: Lenkung umgekehrt
		-- Positive Drehung um Y ist in Roblox eine Linksdrehung, deshalb das Minus.
		local targetYawRate = -steer * D.SteerRate * factor * direction

		-- Wackelrad: langsames, zufaelliges Ziehen zur Seite
		local wobble = math.clamp(math.noise(self.time * D.WobbleFrequency, self.wobbleSeed) * 2, -1, 1)
		targetYawRate += wobble * D.WobbleStrength * math.clamp(absSpeed / D.WobbleFullSpeed, 0, 1)

		local yawRate = angular:Dot(up)
		torque += up * (targetYawRate - yawRate) * D.SteerResponse * self.inertia

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
