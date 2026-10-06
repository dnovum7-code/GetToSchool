--!strict
-- Baut den Wagen (Einkaufswagen, Buerostuhl, Schultisch ...) aus einfachen Parts.
-- Physik (Boden, Raeder, Ballast) ist bei allen Fahrzeugen gleich aufgebaut, nur mit den
-- Werten des Fahrzeugs (Config.Vehicles, src/shared/Vehicles). Das Aussehen kommt aus einem
-- eigenen Modell (ReplicatedStorage/VehicleModels/<Id>) oder einem Platzhalter (style).
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
local Vehicles = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Vehicles"))

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
-- `vehicleId` nil = Einkaufswagen.
function CartBuilder.getRideHeight(vehicleId: string?): number
	local c = Vehicles.stats(vehicleId).Cart
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

-- Ballast eines bestehenden Wagens auf die aktuelle Ballast-Hoehe setzen (Tuning-Panel).
function CartBuilder.applyBallastHeight(cart: Model)
	local c = Vehicles.forCart(cart).Cart
	local ballast = cart:FindFirstChild("Ballast")
	local ballastWeld = ballast and ballast:FindFirstChild("BallastWeld")
	if ballastWeld and ballastWeld:IsA("Weld") then
		ballastWeld.C0 = CFrame.new(0, c.FloorThickness / 2 + c.BallastHeight, 0)
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

-- Teil des Aussehens: fest an Base, ohne Masse
local function visual(model: Model, base: BasePart, cframe: CFrame, props: { [string]: any }): Part
	local offset: CFrame = props.Offset or CFrame.identity
	local partProps = table.clone(props)
	partProps.Offset = nil -- kein Part-Property, nur Lage relativ zum Boden
	local part = makePart(partProps)
	part.Massless = true
	part.CFrame = cframe * offset
	part.Parent = model
	weld(base, part)
	return part
end

-- Platzhalter: Einkaufswagen (Korb aus Gitter-Waenden, roter Griff)
local function buildCartLook(model: Model, base: BasePart, cframe: CFrame, c: typeof(Config.Cart))
	local w, l, h, t = c.Width, c.Length, c.WallHeight, c.FloorThickness
	local metal = Color3.fromRGB(190, 195, 200)
	base.Color = metal
	base.Material = Enum.Material.DiamondPlate
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
		local part = visual(model, base, cframe, {
			Name = def.name,
			Size = def.size,
			Offset = CFrame.new(def.offset),
			Color = metal,
			Material = Enum.Material.Metal,
			Transparency = 0.35, -- "Gitter"-Optik, man sieht den Fahrer
		})
		part:SetAttribute("Paint", true) -- Lackiererei faerbt den Korb
	end
	-- Roter Schiebegriff (Zylinder liegt entlang der X-Achse)
	visual(model, base, cframe, {
		Name = "Handle",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(w + 0.4, 0.35, 0.35),
		Offset = CFrame.new(0, t / 2 + h + 0.9, l / 2 + 0.1),
		Color = Color3.fromRGB(200, 40, 40),
		Material = Enum.Material.SmoothPlastic,
	})
end

-- Platzhalter: Buerostuhl (Polster, Lehne, Armlehnen, Gasfeder, Sternfuss)
local function buildChairLook(model: Model, base: BasePart, cframe: CFrame, c: typeof(Config.Cart))
	local w, l, t = c.Width, c.Length, c.FloorThickness
	local fabric = Color3.fromRGB(40, 70, 150)
	local black = Color3.fromRGB(35, 35, 40)
	base.Color = black
	base.Material = Enum.Material.SmoothPlastic
	local cushion = visual(model, base, cframe, {
		Name = "Cushion",
		Size = Vector3.new(w, 0.4, l),
		Offset = CFrame.new(0, t / 2 + 0.2, 0),
		Color = fabric,
		Material = Enum.Material.Fabric,
	})
	cushion:SetAttribute("Paint", true)
	local backrest = visual(model, base, cframe, {
		Name = "Backrest",
		Size = Vector3.new(w * 0.9, 2.6, 0.35),
		Offset = CFrame.new(0, t / 2 + 1.6, l / 2 - 0.1) * CFrame.Angles(math.rad(-8), 0, 0),
		Color = fabric,
		Material = Enum.Material.Fabric,
	})
	backrest:SetAttribute("Paint", true)
	for _, side in { -1, 1 } do
		visual(model, base, cframe, {
			Name = "Armrest",
			Size = Vector3.new(0.3, 0.25, l * 0.6),
			Offset = CFrame.new(side * (w / 2 - 0.15), t / 2 + 1.1, 0.2),
			Color = black,
		})
		visual(model, base, cframe, {
			Name = "ArmrestPost",
			Size = Vector3.new(0.2, 0.9, 0.2),
			Offset = CFrame.new(side * (w / 2 - 0.15), t / 2 + 0.55, 0.4),
			Color = black,
			CanCollide = false,
		})
	end
	-- Gasfeder: vom Sitz bis knapp ueber die Rollen
	local liftLength = math.max(c.WheelGap, 0.2)
	visual(model, base, cframe, {
		Name = "GasLift",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(liftLength, 0.4, 0.4),
		Offset = CFrame.new(0, -(t / 2 + liftLength / 2), 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(150, 150, 160),
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	-- Sternfuss: Arme zu den Rollen (nur Optik)
	local r = c.WheelDiameter / 2
	local wheelX = w / 2 - r - 0.1
	local wheelZ = l / 2 - r - 0.1
	local armY = -(t / 2 + c.WheelGap - 0.1)
	for _, corner in
		{ Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) }
	do
		local tip = Vector3.new(corner.X * wheelX, armY, corner.Z * wheelZ)
		local middle = Vector3.new(tip.X / 2, armY, tip.Z / 2)
		visual(model, base, cframe, {
			Name = "StarArm",
			Size = Vector3.new(0.25, 0.2, Vector3.new(tip.X, 0, tip.Z).Magnitude),
			Offset = CFrame.lookAt(middle, Vector3.new(tip.X, armY, tip.Z)),
			Color = black,
			CanCollide = false,
		})
	end
end

-- Platzhalter: Schultisch auf Skateboard (Brett, Achsen, Tischplatte auf vier Beinen)
local function buildDeskLook(model: Model, base: BasePart, cframe: CFrame, c: typeof(Config.Cart))
	local w, l, t = c.Width, c.Length, c.FloorThickness
	local wood = Color3.fromRGB(205, 160, 105)
	local metal = Color3.fromRGB(120, 125, 135)
	base.Color = Color3.fromRGB(60, 60, 65) -- Griptape
	base.Material = Enum.Material.Sand
	local deskDepth = l * 0.45
	local deskZ = -l / 2 + deskDepth / 2 + 0.1
	local deskY = t / 2 + 2.4
	local top = visual(model, base, cframe, {
		Name = "DeskTop",
		Size = Vector3.new(w + 0.6, 0.25, deskDepth),
		Offset = CFrame.new(0, deskY, deskZ),
		Color = wood,
		Material = Enum.Material.Wood,
	})
	top:SetAttribute("Paint", true)
	local tray = visual(model, base, cframe, {
		Name = "BookTray",
		Size = Vector3.new(w * 0.8, 0.5, deskDepth * 0.8),
		Offset = CFrame.new(0, deskY - 0.6, deskZ),
		Color = metal,
		Material = Enum.Material.Metal,
	})
	tray:SetAttribute("Paint", true)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			visual(model, base, cframe, {
				Name = "DeskLeg",
				Size = Vector3.new(0.2, deskY - t / 2, 0.2),
				Offset = CFrame.new(
					x * (w / 2 + 0.1),
					t / 2 + (deskY - t / 2) / 2,
					deskZ + z * (deskDepth / 2 - 0.15)
				),
				Color = metal,
				Material = Enum.Material.Metal,
			})
		end
	end
	-- Achsen unter dem Brett (nur Optik)
	local r = c.WheelDiameter / 2
	local wheelZ = l / 2 - r - 0.1
	for _, z in { -1, 1 } do
		visual(model, base, cframe, {
			Name = "Truck",
			Size = Vector3.new(w * 0.75, 0.2, 0.4),
			Offset = CFrame.new(0, -(t / 2 + 0.1), z * wheelZ),
			Color = metal,
			Material = Enum.Material.Metal,
			CanCollide = false,
		})
	end
end

-- Eigenes Modell aus ReplicatedStorage/VehicleModels/<Id> (Pivot = Mitte des Bodens,
-- Vorderseite -Z). Gibt zurueck, ob es eins gab.
local function addCustomModel(model: Model, base: BasePart, cframe: CFrame, vehicleId: string): boolean
	local folder = ReplicatedStorage:FindFirstChild(Config.Vehicles.ModelsFolder)
	local template = folder and folder:FindFirstChild(vehicleId)
	if not template or not template:IsA("Model") then
		return false
	end
	local look = template:Clone()
	look.Name = "Look"
	look:PivotTo(cframe)
	for _, item in look:GetDescendants() do
		if item:IsA("BasePart") then
			local collide = item:GetAttribute("Collide") == true
			item.Anchored = false
			item.Massless = true
			item.CanCollide = collide
			item.CanTouch = false
			if not collide then
				item.CanQuery = false
			end
			item.CollisionGroup = CartBuilder.COLLISION_GROUP
			weld(base, item)
		elseif item:IsA("Script") or item:IsA("LocalScript") then
			item:Destroy() -- keine Skripte aus Modellen mitnehmen
		end
	end
	look.Parent = model
	if template:GetAttribute("HideBase") == true then
		base.Transparency = 1
	end
	model:SetAttribute("HideWheels", template:GetAttribute("HideWheels") == true)
	return true
end

-- Aussehen aus der Lackiererei: Farbe (nil = Original) und Spur (nil = keine).
-- Gefaerbt werden Teile mit Attribut Paint = true; ihr Original merkt sich der Wagen.
export type TrailLook = {
	colors: { Color3 }?,
	rainbow: boolean?,
	lifetime: number?,
	lightEmission: number?,
}

function CartBuilder.applyLook(cart: Model, color: Color3?, material: Enum.Material?, trail: TrailLook?)
	for _, part in cart:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("Paint") == true then
			local original = part:GetAttribute("OriginalColor")
			if typeof(original) ~= "Color3" then
				part:SetAttribute("OriginalColor", part.Color)
				part:SetAttribute("OriginalMaterial", part.Material.Name)
				original = part.Color
			end
			local originalMaterial = (Enum.Material :: any)[part:GetAttribute("OriginalMaterial") or "Plastic"]
			part.Color = color or original :: Color3
			part.Material = material or originalMaterial or part.Material
		end
	end

	-- Spur: Band zwischen zwei Punkten hinten links und rechts am Boden
	local base = cart:FindFirstChild("Base")
	if not base or not base:IsA("BasePart") then
		return
	end
	local old = base:FindFirstChild("CosmeticTrail")
	if old then
		old:Destroy()
	end
	for _, name in { "TrailLeft", "TrailRight" } do
		local attachment = base:FindFirstChild(name)
		if attachment then
			attachment:Destroy()
		end
	end
	if not trail then
		return
	end
	local size = base.Size
	local left = Instance.new("Attachment")
	left.Name = "TrailLeft"
	left.Position = Vector3.new(-size.X / 2 + 0.2, 0, size.Z / 2)
	left.Parent = base
	local right = Instance.new("Attachment")
	right.Name = "TrailRight"
	right.Position = Vector3.new(size.X / 2 - 0.2, 0, size.Z / 2)
	right.Parent = base
	local effect = Instance.new("Trail")
	effect.Name = "CosmeticTrail"
	effect.Attachment0 = left
	effect.Attachment1 = right
	effect.Lifetime = trail.lifetime or 0.7
	effect.LightEmission = trail.lightEmission or 0
	effect.MinLength = 0.2
	effect.Transparency = NumberSequence.new(0.15, 1)
	if trail.rainbow then
		local keypoints = {}
		for i = 0, 6 do
			table.insert(keypoints, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.8, 1)))
		end
		effect.Color = ColorSequence.new(keypoints)
	else
		local colors = trail.colors or { Color3.new(1, 1, 1) }
		effect.Color = ColorSequence.new(colors[1], colors[2] or colors[1])
	end
	effect.Parent = base
end

-- Erzeugt einen neuen Wagen an `cframe` (Mitte des Bodens) fuer `owner`.
-- `vehicleId`: Fahrzeug aus Config.Vehicles (nil = Einkaufswagen).
-- Der Wagen wird noch nicht in den Workspace gesetzt; das macht der Aufrufer.
function CartBuilder.build(owner: Player, cframe: CFrame, vehicleId: string?): Model
	ensureCollisionGroup()

	local def = Vehicles.get(vehicleId) or Vehicles.get(Vehicles.defaultId())
	local id = if def then def.id else Vehicles.defaultId()
	local c = Vehicles.stats(id).Cart
	local w, l, t = c.Width, c.Length, c.FloorThickness
	local r = c.WheelDiameter / 2
	local metal = Color3.fromRGB(190, 195, 200)

	local model = Instance.new("Model")
	model.Name = "Cart_" .. owner.Name
	model:SetAttribute("IsCart", true)
	model:SetAttribute("OwnerUserId", owner.UserId)
	model:SetAttribute("VehicleId", id)
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

	-- Aussehen: eigenes Modell oder Platzhalter je nach Fahrzeug
	if not addCustomModel(model, base, cframe, id) then
		local style = if def then def.style else "Cart"
		if style == "Chair" then
			buildChairLook(model, base, cframe, c)
		elseif style == "Desk" then
			buildDeskLook(model, base, cframe, c)
		else
			buildCartLook(model, base, cframe, c)
		end
	end

	-- Sitz (unsichtbar). Hinten im Korb, damit die Beine nach vorne Platz haben.
	-- CanTouch = false: niemand setzt sich durch Beruehren hinein, nur per Skript.
	local seat = Instance.new("Seat")
	seat.Name = "Seat"
	seat.Size = Vector3.new(2, 0.2, 2)
	local seatY = t / 2 + (if def and def.style == "Chair" then 0.5 else 0.1) -- Stuhl: auf dem Polster
	seat.CFrame = cframe * CFrame.new(0, seatY, l / 2 - 1.4)
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
			Transparency = if model:GetAttribute("HideWheels") == true then 1 else 0,
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
