--!strict
-- Physik-Tags fuer lose Objekte (Kopien aus Spawnern, Props, lose Teile in der Welt):
--   LowGravity  = wenig Schwerkraft: fliegt weiter, rutscht/rollt den ganzen Berg hinunter
--                 (Config.ObjectPhysics.GravityScale, Attribut "GravityScale")
--   NoFriction  = (fast) keine Reibung: rutscht statt stehen zu bleiben
--                 (Config.ObjectPhysics.Friction, Attribut "Friction")
--   KeepUpright = bleibt aufrecht (z. B. Kuh): eine begrenzte Kraft dreht die Hochachse
--                 zurueck nach oben. Nicht starr: Stoesse und Flips gehen weiter, dreht es
--                 sich schnell, ist die Kraft aus; nur liegen bleiben geht nicht.
--                 Achse: Attribut "UprightAxis" (Vector3 im Objekt, Standard 0, 1, 0).
-- Statt Tag geht auch ein gleichnamiges Attribut = true. Wo setzen: an die Vorlage
-- (ReplicatedStorage/Templates), an den Spawner (gilt fuer alle seine Objekte), an einen
-- Prop oder an ein loses (nicht verankertes) Teil/Modell in der Welt.
-- Unity-Vergleich: Rigidbody mit eigenem Gravity-Scale, PhysicMaterial ohne Reibung und
-- einem weichen "Stehaufmaennchen"-Joint statt Freeze Rotation.

local RunService = game:GetService("RunService")

local Config = require(script.Parent:WaitForChild("Config"))
local TagList = require(script.Parent:WaitForChild("TagList"))
local ObjectPhysicsMath = require(script.Parent:WaitForChild("Toolkit"):WaitForChild("ObjectPhysicsMath"))

local ObjectPhysics = {}

ObjectPhysics.TAGS = { "LowGravity", "NoFriction", "KeepUpright" }

export type Flags = {
	lowGravity: boolean,
	noFriction: boolean,
	keepUpright: boolean,
	gravityScale: number?, -- Attribut, sonst Config (live aus dem Panel)
	friction: number?,
	uprightAxis: Vector3,
}

type Tracked = {
	root: BasePart,
	mass: number,
	extent: number,
	flags: Flags,
	force: VectorForce?,
	align: AlignOrientation?,
}

local tracked: { [BasePart]: Tracked } = setmetatable({}, { __mode = "k" }) :: any
local heartbeat: RBXScriptConnection? = nil

-- Debug-Ausgabe (nur Studio, Config.Debug.Toolkit)
function ObjectPhysics.debugWarn(message: string)
	if Config.Debug.Toolkit and RunService:IsStudio() then
		warn(message)
	end
end

local function hasFlag(source: Instance, name: string): boolean
	if source:HasTag(name) or source:GetAttribute(name) == true then
		return true
	end
	-- Tag an einem Teil innerhalb der Vorlage (z. B. am MeshPart im Modell) zaehlt auch
	if source:IsA("Model") then
		for _, item in source:GetDescendants() do
			if item:HasTag(name) then
				return true
			end
		end
	end
	return false
end

local function firstNumber(sources: { Instance }, name: string): number?
	for _, source in sources do
		local value = source:GetAttribute(name)
		if type(value) == "number" and value == value then
			return value
		end
	end
	return nil
end

-- Flags aus mehreren Quellen (z. B. Vorlage und Spawner): ein Tag reicht.
function ObjectPhysics.flags(sources: { Instance }): Flags
	local flags: Flags = {
		lowGravity = false,
		noFriction = false,
		keepUpright = false,
		gravityScale = firstNumber(sources, "GravityScale"),
		friction = firstNumber(sources, "Friction"),
		uprightAxis = Vector3.yAxis,
	}
	for _, source in sources do
		flags.lowGravity = flags.lowGravity or hasFlag(source, "LowGravity")
		flags.noFriction = flags.noFriction or hasFlag(source, "NoFriction")
		flags.keepUpright = flags.keepUpright or hasFlag(source, "KeepUpright")
		local axis = source:GetAttribute("UprightAxis")
		if typeof(axis) == "Vector3" and axis.Magnitude > 0.01 then
			flags.uprightAxis = axis.Unit
		end
	end
	return flags
end

function ObjectPhysics.any(flags: Flags): boolean
	return flags.lowGravity or flags.noFriction or flags.keepUpright
end

-- "LowGravity, KeepUpright" (fuer die Debug-Ausgabe)
function ObjectPhysics.describe(flags: Flags): string
	local names = {}
	if flags.lowGravity then
		table.insert(names, "LowGravity")
	end
	if flags.noFriction then
		table.insert(names, "NoFriction")
	end
	if flags.keepUpright then
		table.insert(names, "KeepUpright")
	end
	return if #names > 0 then table.concat(names, ", ") else "keine"
end

local function allParts(object: Instance): { BasePart }
	local parts: { BasePart } = {}
	if object:IsA("BasePart") then
		table.insert(parts, object)
	end
	for _, item in object:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(parts, item)
		end
	end
	return parts
end

local function child<T>(parent: Instance, name: string, className: string): T
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing :: any
	end
	local created = Instance.new(className :: any)
	created.Name = name
	created.Parent = parent
	return created :: any
end

-- Kraefte jeden Frame nachfuehren (Werte aus dem Panel wirken sofort)
local function update()
	local P = Config.ObjectPhysics
	local gravity = workspace.Gravity
	for root, entry in tracked do
		if not root:IsDescendantOf(workspace) then
			continue -- im Pool (Spawner) oder geloescht
		end
		local force = entry.force
		if force then
			local scale = entry.flags.gravityScale or P.GravityScale
			force.Force = Vector3.new(0, ObjectPhysicsMath.antiGravity(entry.mass, gravity, scale), 0)
		end
		local align = entry.align
		if align then
			align.MaxTorque =
				ObjectPhysicsMath.uprightTorque(entry.mass, gravity, entry.extent, P.UprightStrength)
			align.Responsiveness = math.max(P.UprightResponsiveness, 1)
			align.Enabled =
				ObjectPhysicsMath.uprightActive(root.AssemblyAngularVelocity.Magnitude, P.UprightFreeSpin)
		end
	end
end

-- Flags auf ein loses Objekt anwenden (erneut aufrufen ist ok, z. B. nach Groessenaenderung
-- einer wiederverwendeten Spawner-Kopie). Das Objekt muss zusammengeschweisst sein.
function ObjectPhysics.apply(object: PVInstance, flags: Flags)
	local parts = allParts(object)
	if #parts == 0 then
		return
	end
	local root: BasePart = if object:IsA("Model") and object.PrimaryPart then object.PrimaryPart else parts[1]
	local P = Config.ObjectPhysics

	if flags.noFriction then
		local friction = math.max(flags.friction or P.Friction, 0)
		for _, part in parts do
			local current = part.CurrentPhysicalProperties
			part.CustomPhysicalProperties = PhysicalProperties.new(
				current.Density,
				friction,
				current.Elasticity,
				ObjectPhysicsMath.NO_FRICTION_WEIGHT,
				current.ElasticityWeight
			)
		end
	end

	local mass = 0
	for _, part in parts do
		if not part.Massless then
			mass += part.Mass
		end
	end
	local size = if object:IsA("Model") then object:GetExtentsSize() else root.Size
	local entry: Tracked = {
		root = root,
		mass = mass,
		extent = math.max(size.X, size.Y, size.Z) / 2,
		flags = flags,
		force = nil,
		align = nil,
	}

	local oldForce = root:FindFirstChild("LowGravityForce")
	if flags.lowGravity then
		local attachment = child(root, "ObjectPhysicsCenter", "Attachment") :: Attachment
		local force = child(root, "LowGravityForce", "VectorForce") :: VectorForce
		force.Attachment0 = attachment
		force.RelativeTo = Enum.ActuatorRelativeTo.World
		force.ApplyAtCenterOfMass = true
		entry.force = force
	elseif oldForce then
		oldForce:Destroy()
	end

	local oldAlign = root:FindFirstChild("KeepUpright")
	if flags.keepUpright then
		-- Hochachse (im Objekt, bezogen auf den Pivot) als X-Achse eines Attachments am Root
		local axisWorld = object:GetPivot():VectorToWorldSpace(flags.uprightAxis)
		local axisLocal = root.CFrame:VectorToObjectSpace(axisWorld).Unit
		local other = if math.abs(axisLocal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
		local attachment = child(root, "KeepUprightAxis", "Attachment") :: Attachment
		attachment.CFrame = CFrame.fromMatrix(Vector3.zero, axisLocal, axisLocal:Cross(other).Unit)
		local align = child(root, "KeepUpright", "AlignOrientation") :: AlignOrientation
		align.Mode = Enum.OrientationAlignmentMode.OneAttachment
		align.Attachment0 = attachment
		align.AlignType = Enum.AlignType.PrimaryAxisParallel
		align.PrimaryAxis = Vector3.yAxis
		align.RigidityEnabled = false
		entry.align = align
	elseif oldAlign then
		oldAlign:Destroy()
	end

	if entry.force or entry.align then
		tracked[root] = entry
		if not heartbeat then
			heartbeat = RunService.Heartbeat:Connect(update)
		end
	else
		tracked[root] = nil
	end
	update()
end

-- Server: lose Objekte direkt in der Welt (nicht Spawner, Props, Launchables - die
-- erledigen ihre Module). Verankerte Objekte bewegen sich nicht: Hinweis im Output.
function ObjectPhysics.watchWorld()
	local function onTagged(instance: Instance)
		if instance:HasTag("Spawner") or instance:HasTag("Prop") or instance:HasTag("Launchable") then
			return
		end
		if not (instance:IsA("BasePart") or instance:IsA("Model")) then
			ObjectPhysics.debugWarn(
				`[Physik-Tag] {instance:GetFullName()} ist ein {instance.ClassName}; der Tag muss an ein Part oder Model.`
			)
			return
		end
		local parts = allParts(instance)
		local loose = false
		for _, part in parts do
			loose = loose or not part.Anchored
		end
		local flags = ObjectPhysics.flags({ instance })
		if not loose then
			ObjectPhysics.debugWarn(
				`[Physik-Tag] {instance:GetFullName()} ist verankert (Anchored) - {ObjectPhysics.describe(
					flags
				)} ` .. "wirkt nur bei losen Objekten, Spawner-Kopien und Props."
			)
			return
		end
		ObjectPhysics.apply(instance :: PVInstance, flags)
		ObjectPhysics.debugWarn(`[Physik-Tag] {instance:GetFullName()}: {ObjectPhysics.describe(flags)}`)
	end
	for _, tag in ObjectPhysics.TAGS do
		TagList.watch(tag, onTagged)
	end
end

return ObjectPhysics
