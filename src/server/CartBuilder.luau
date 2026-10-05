--!strict
-- Baut den Platzhalter-Einkaufswagen aus einfachen Parts.
--
-- Aufbau (Unity-Vergleich: ein Rigidbody mit mehreren Collidern als Kinder):
--   Base       Korbboden, Wurzel der Physik. Alle festen Teile sind per WeldConstraint
--              daran geschweisst und bilden zusammen eine "Assembly" (ein Rigidbody).
--   Waende, Griff, Sitz, Ballast   fest an Base geschweisst
--   4 Raeder   Kugeln, per BallSocketConstraint (Kugelgelenk) befestigt. Sie rollen in
--              jede Richtung; den Seitenhalt erzeugt das Fahrskript per Kraft.
--   DriveForce / SteerTorque   Kraft und Drehmoment, die das Fahrskript jeden Frame setzt.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local CartBuilder = {}

CartBuilder.COLLISION_GROUP = "Carts"

local function ensureCollisionGroup()
	if not PhysicsService:IsCollisionGroupRegistered(CartBuilder.COLLISION_GROUP) then
		PhysicsService:RegisterCollisionGroup(CartBuilder.COLLISION_GROUP)
	end
	-- Wagen verschiedener Spieler fahren durcheinander hindurch (alle starten am selben Ort).
	PhysicsService:CollisionGroupSetCollidable(
		CartBuilder.COLLISION_GROUP,
		CartBuilder.COLLISION_GROUP,
		false
	)
end

-- Hoehe der Bodenmitte ueber dem Untergrund, wenn alle Raeder aufsetzen.
function CartBuilder.getRideHeight(): number
	local c = Config.Cart
	return c.WheelDiameter + c.WheelGap + c.FloorThickness / 2
end

-- Gesamtmasse des Wagens (alle Teile, die zur Masse beitragen; Raeder eingeschlossen).
function CartBuilder.getMass(cart: Model): number
	local mass = 0
	for _, part in cart:GetDescendants() do
		if part:IsA("BasePart") and not part.Massless then
			mass += part.Mass
		end
	end
	return math.max(mass, 0.1)
end

-- Ballast eines bestehenden Wagens auf die aktuelle Config.Cart.BallastHeight setzen.
function CartBuilder.applyBallastHeight(cart: Model)
	local ballast = cart:FindFirstChild("Ballast")
	local ballastWeld = ballast and ballast:FindFirstChild("BallastWeld")
	if ballastWeld and ballastWeld:IsA("Weld") then
		ballastWeld.C0 = CFrame.new(0, Config.Cart.FloorThickness / 2 + Config.Cart.BallastHeight, 0)
	end
end

local function makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CollisionGroup = CartBuilder.COLLISION_GROUP
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

local function weld(base: BasePart, part: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = part
	w.Parent = part
end

-- Erzeugt einen neuen Wagen an `cframe` (Mitte des Korbbodens) fuer `owner`.
-- Der Wagen wird noch nicht in den Workspace gesetzt; das macht der Aufrufer.
function CartBuilder.build(owner: Player, cframe: CFrame): Model
	ensureCollisionGroup()

	local c = Config.Cart
	local w, l, h, t = c.Width, c.Length, c.WallHeight, c.FloorThickness
	local r = c.WheelDiameter / 2
	local metal = Color3.fromRGB(190, 195, 200)

	local model = Instance.new("Model")
	model.Name = "Cart_" .. owner.Name
	model:SetAttribute("IsCart", true)
	model:SetAttribute("OwnerUserId", owner.UserId)
	-- Bei StreamingEnabled kommt der Wagen immer komplett beim Client an (nie nur halb).
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	-- Korbboden: Wurzel der Assembly
	local base = makePart({
		Name = "Base",
		Size = Vector3.new(w, t, l),
		CFrame = cframe,
		Color = metal,
		Material = Enum.Material.DiamondPlate,
		CustomPhysicalProperties = PhysicalProperties.new(c.FloorDensity, c.BodyFriction, 0, 1, 1),
	})
	base.Parent = model
	model.PrimaryPart = base

	-- Feste Teile: Name, Groesse, Position relativ zur Bodenmitte (-Z ist vorne)
	local wallY = t / 2 + h / 2
	local postY = t / 2 + h + 0.45
	local fixedParts: { { name: string, size: Vector3, offset: Vector3 } } = {
		{ name = "WallLeft", size = Vector3.new(0.2, h, l), offset = Vector3.new(-(w / 2 - 0.1), wallY, 0) },
		{ name = "WallRight", size = Vector3.new(0.2, h, l), offset = Vector3.new(w / 2 - 0.1, wallY, 0) },
		{ name = "WallFront", size = Vector3.new(w, h, 0.2), offset = Vector3.new(0, wallY, -(l / 2 - 0.1)) },
		{ name = "WallBack", size = Vector3.new(w, h, 0.2), offset = Vector3.new(0, wallY, l / 2 - 0.1) },
		{
			name = "HandlePostLeft",
			size = Vector3.new(0.2, 0.9, 0.2),
			offset = Vector3.new(-(w / 2 - 0.1), postY, l / 2 + 0.1),
		},
		{
			name = "HandlePostRight",
			size = Vector3.new(0.2, 0.9, 0.2),
			offset = Vector3.new(w / 2 - 0.1, postY, l / 2 + 0.1),
		},
	}
	for _, def in fixedParts do
		local part = makePart({
			Name = def.name,
			Size = def.size,
			CFrame = cframe * CFrame.new(def.offset),
			Color = metal,
			Material = Enum.Material.Metal,
			Transparency = 0.35, -- "Gitter"-Optik, man sieht den Fahrer
			Massless = true, -- Gewicht steckt in Boden und Ballast (einfacher zu tunen)
		})
		part.Parent = model
		weld(base, part)
	end

	-- Roter Schiebegriff (Zylinder liegt entlang der X-Achse)
	local handle = makePart({
		Name = "Handle",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(w + 0.4, 0.35, 0.35),
		CFrame = cframe * CFrame.new(0, t / 2 + h + 0.9, l / 2 + 0.1),
		Color = Color3.fromRGB(200, 40, 40),
		Material = Enum.Material.SmoothPlastic,
		Massless = true,
	})
	handle.Parent = model
	weld(base, handle)

	-- Sitz (unsichtbar). Hinten im Korb, damit die Beine nach vorne Platz haben.
	-- CanTouch = false: niemand setzt sich durch Beruehren hinein, nur per Skript.
	local seat = Instance.new("Seat")
	seat.Name = "Seat"
	seat.Size = Vector3.new(2, 0.2, 2)
	seat.CFrame = cframe * CFrame.new(0, t / 2 + 0.1, l / 2 - 1.4)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false
	seat.CanQuery = false
	seat.Massless = true
	seat.CollisionGroup = CartBuilder.COLLISION_GROUP
	seat.Parent = model
	weld(base, seat)

	-- Ballast: ersetzt das Gewicht des Fahrers. Hoehe bestimmt, wie kippelig der Wagen ist.
	local ballast = makePart({
		Name = "Ballast",
		Size = Vector3.new(1, 1, 1),
		CFrame = cframe * CFrame.new(0, t / 2 + c.BallastHeight, 0),
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		-- Volumen ist 1, also Dichte = Masse (Roblox erlaubt Dichte bis 100)
		CustomPhysicalProperties = PhysicalProperties.new(math.clamp(c.BallastMass, 0.01, 100), 0, 0),
	})
	ballast.Parent = model
	-- Weld statt WeldConstraint: Der Versatz (C0) laesst sich spaeter aendern
	-- (Tuning-Panel: Ballast-Hoehe live verstellen).
	local ballastWeld = Instance.new("Weld")
	ballastWeld.Name = "BallastWeld"
	ballastWeld.Part0 = base
	ballastWeld.Part1 = ballast
	ballastWeld.C0 = CFrame.new(0, t / 2 + c.BallastHeight, 0)
	ballastWeld.Parent = ballast

	-- Kraft und Drehmoment fuer das Fahrskript
	local center = Instance.new("Attachment")
	center.Name = "Center"
	center.Parent = base

	local driveForce = Instance.new("VectorForce")
	driveForce.Name = "DriveForce"
	driveForce.Attachment0 = center
	driveForce.RelativeTo = Enum.ActuatorRelativeTo.World
	driveForce.ApplyAtCenterOfMass = true
	driveForce.Force = Vector3.zero
	driveForce.Parent = base

	local steerTorque = Instance.new("Torque")
	steerTorque.Name = "SteerTorque"
	steerTorque.Attachment0 = center
	steerTorque.RelativeTo = Enum.ActuatorRelativeTo.World
	steerTorque.Torque = Vector3.zero
	steerTorque.Parent = base

	-- Raeder
	local wheelY = -(t / 2 + c.WheelGap + r)
	local wheelX = w / 2 - r - 0.1
	local wheelZ = l / 2 - r - 0.1
	local wheelOffsets: { [string]: Vector3 } = {
		WheelFL = Vector3.new(-wheelX, wheelY, -wheelZ),
		WheelFR = Vector3.new(wheelX, wheelY, -wheelZ),
		WheelBL = Vector3.new(-wheelX, wheelY, wheelZ),
		WheelBR = Vector3.new(wheelX, wheelY, wheelZ),
	}
	for name, offset in wheelOffsets do
		local wheel = makePart({
			Name = name,
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * c.WheelDiameter,
			CFrame = cframe * CFrame.new(offset),
			Color = Color3.fromRGB(40, 40, 45),
			Material = Enum.Material.SmoothPlastic,
			CustomPhysicalProperties = PhysicalProperties.new(c.WheelDensity, c.WheelFriction, 0, 1, 1),
		})
		wheel.Parent = model

		local baseAttachment = Instance.new("Attachment")
		baseAttachment.Name = name .. "Attachment"
		baseAttachment.Position = offset
		baseAttachment.Parent = base

		local wheelAttachment = Instance.new("Attachment")
		wheelAttachment.Name = "Socket"
		wheelAttachment.Parent = wheel

		local socket = Instance.new("BallSocketConstraint")
		socket.Attachment0 = baseAttachment
		socket.Attachment1 = wheelAttachment
		socket.Parent = wheel

		local noCollide = Instance.new("NoCollisionConstraint")
		noCollide.Part0 = base
		noCollide.Part1 = wheel
		noCollide.Parent = wheel
	end

	return model
end

return CartBuilder
