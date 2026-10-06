--!strict
-- Drift-Effekte, nur auf diesem Client sichtbar:
--   Funken an den Hinterraedern (ParticleEmitter, Farbe = Boost-Stufe)
--   Reifenspuren auf dem Boden (duenne Streifen, die verblassen)
--
-- Unity-Vergleich: ParticleSystem an den Raedern und ein selbstgebauter "TrailRenderer".
-- Die Spuren kommen aus einem festen Vorrat (Pool): Ist er voll, wird die aelteste Spur
-- wiederverwendet. So entstehen nie mehr als Config.Drift.MaxSkidMarks Teile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Vehicles = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Vehicles"))
local CartController = require(script.Parent:WaitForChild("CartController"))

local DriftEffects = {}

type Wheel = {
	attachment: Attachment, -- am Boden unter dem Rad
	emitter: ParticleEmitter,
	lastMarkPoint: Vector3?,
}

type Mark = {
	part: Part,
	bornAt: number,
}

local wheels: { Wheel } = {}
local currentCart: Model? = nil
local marks: { Mark } = {}
local nextMark = 1
local markTimer = 0
local marksFolder: Folder? = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local MARK_START_TRANSPARENCY = 0.35

local function getMarksFolder(): Folder
	local folder = marksFolder
	if not folder or not folder.Parent then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "LocalSkidMarks" -- existiert nur auf diesem Client
		newFolder.Parent = workspace
		marksFolder = newFolder
		return newFolder
	end
	return folder
end

local function makeEmitter(parent: Attachment): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "DriftSparks"
	-- Standard-Textur des ParticleEmitters (kein Toolbox-Asset noetig)
	emitter.EmissionDirection = Enum.NormalId.Back -- nach hinten spruehen
	emitter.Rate = 60
	emitter.Lifetime = NumberRange.new(0.15, 0.35)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Drag = 2
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Enabled = false
	emitter.Parent = parent
	return emitter
end

-- Effekte an einen Wagen haengen (beim Einsteigen).
function DriftEffects.attach(cart: Model, character: Model)
	DriftEffects.detach()
	local base = cart:FindFirstChild("Base")
	if not base or not base:IsA("BasePart") then
		return
	end
	currentCart = cart
	rayParams.FilterDescendantsInstances = { cart, character, getMarksFolder() }

	local c = Vehicles.forCart(cart).Cart
	local r = c.WheelDiameter / 2
	local wheelX = c.Width / 2 - r - 0.1
	local wheelZ = c.Length / 2 - r - 0.1 -- hinten ist +Z
	local groundY = -(c.FloorThickness / 2 + c.WheelGap + c.WheelDiameter)
	for _, x in { -wheelX, wheelX } do
		local attachment = Instance.new("Attachment")
		attachment.Name = "DriftEffectAttachment"
		attachment.Position = Vector3.new(x, groundY, wheelZ)
		attachment.Parent = base
		table.insert(
			wheels,
			{ attachment = attachment, emitter = makeEmitter(attachment), lastMarkPoint = nil }
		)
	end
end

function DriftEffects.detach()
	for _, wheel in wheels do
		wheel.attachment:Destroy()
	end
	table.clear(wheels)
	currentCart = nil
end

-- Ein Stueck Reifenspur von `from` nach `to` legen (aeltestes wiederverwenden, wenn voll).
local function placeMark(from: Vector3, to: Vector3, normal: Vector3)
	local length = (to - from).Magnitude
	if length < 0.05 or length > 6 then
		return -- zu kurz, oder ein Sprung (z. B. Neustart)
	end
	local mark = marks[nextMark]
	if not mark then
		local part = Instance.new("Part")
		part.Name = "SkidMark"
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false -- Raycasts (Boden, Kamera) gehen hindurch
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Color3.fromRGB(25, 25, 25)
		part.Parent = getMarksFolder()
		mark = { part = part, bornAt = 0 }
		marks[nextMark] = mark
	end
	local middle = (from + to) / 2 + normal * 0.03 -- knapp ueber dem Boden
	mark.part.Size = Vector3.new(Config.Drift.SkidMarkWidth, 0.05, length)
	mark.part.CFrame = CFrame.lookAt(middle, middle + (to - from), normal)
	mark.part.Transparency = MARK_START_TRANSPARENCY
	mark.bornAt = os.clock()
	nextMark = nextMark % math.max(Config.Drift.MaxSkidMarks, 1) + 1
end

-- Jeden Frame aufrufen, auch ohne Wagen (damit alte Spuren weiter verblassen).
function DriftEffects.update(dt: number, telemetry: CartController.Telemetry?)
	local DR = Config.Drift

	-- Funken: nur waehrend die Driftzeit zaehlt; Farbe zeigt die Boost-Stufe
	local sparksOn = telemetry ~= nil and telemetry.driftCharging
	local color = DR.SparkColor
	if telemetry and telemetry.boostLevel >= 2 then
		color = DR.Level2Color
	elseif telemetry and telemetry.boostLevel == 1 then
		color = DR.Level1Color
	end
	for _, wheel in wheels do
		wheel.emitter.Enabled = sparksOn
		wheel.emitter.Color = ColorSequence.new(color)
	end

	-- Reifenspuren nur, solange der Wagen seitlich rutscht (in Kurven), nicht geradeaus
	local marking = telemetry ~= nil and currentCart ~= nil and telemetry.skidding
	markTimer += dt
	if marking and markTimer >= DR.SkidMarkInterval then
		markTimer = 0
		for _, wheel in wheels do
			local origin = wheel.attachment.WorldPosition + wheel.attachment.WorldCFrame.UpVector * 1.5
			local hit = workspace:Raycast(origin, -wheel.attachment.WorldCFrame.UpVector * 3, rayParams)
			if hit then
				local last = wheel.lastMarkPoint
				if last then
					placeMark(last, hit.Position, hit.Normal)
				end
				wheel.lastMarkPoint = hit.Position
			else
				wheel.lastMarkPoint = nil
			end
		end
	elseif not marking then
		for _, wheel in wheels do
			wheel.lastMarkPoint = nil -- neue Spur beginnt beim naechsten Drift neu
		end
	end

	-- Spuren verblassen lassen und abgelaufene unsichtbar parken
	local now = os.clock()
	local lifetime = math.max(DR.SkidMarkLifetime, 0.1)
	for _, mark in marks do
		if mark.part.Transparency < 1 then
			local age = (now - mark.bornAt) / lifetime
			mark.part.Transparency = if age >= 1
				then 1
				else MARK_START_TRANSPARENCY + (1 - MARK_START_TRANSPARENCY) * age
		end
	end
end

return DriftEffects
