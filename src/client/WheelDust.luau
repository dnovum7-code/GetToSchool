--!strict
-- Partikel an den Raedern je nach Untergrund: Gras (gruene Fetzen), Erde/Sand (brauner
-- Staub), Asphalt (wenig grauer Staub), Schnee (weisse Wolken). Menge steigt mit dem Tempo,
-- beim Driften deutlich mehr. Der Untergrund wird alle Config.Atmosphere.WheelCheckInterval
-- Sekunden per Strahl nach unten bestimmt (Material des Parts bzw. des Terrains).
-- Rechnung: shared/Atmosphere/SpeedFeel. Aus mit der Einstellung "Extra-Effekte".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SpeedFeel = require(Shared:WaitForChild("Atmosphere"):WaitForChild("SpeedFeel"))
local Vehicles = require(Shared:WaitForChild("Vehicles"))
local CartController = require(script.Parent:WaitForChild("CartController"))
local Settings = require(script.Parent:WaitForChild("Settings"))

local WheelDust = {}

type Wheel = {
	attachment: Attachment,
	emitter: ParticleEmitter,
	surface: string?,
}

local wheels: { Wheel } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local checkTimer = 0

local function makeEmitter(parent: Attachment): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "WheelDust"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.4, 0.9)
	emitter.Speed = NumberRange.new(3, 7)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, -18, 0)
	emitter.Drag = 2
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-120, 120)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.LightEmission = 0
	emitter.Parent = parent
	return emitter
end

function WheelDust.attach(cart: Model, character: Model?)
	WheelDust.detach()
	local base = cart:FindFirstChild("Base")
	if not base or not base:IsA("BasePart") then
		return
	end
	rayParams.FilterDescendantsInstances = if character then { cart, character } else { cart }
	local c = Vehicles.forCart(cart).Cart
	local r = c.WheelDiameter / 2
	local wheelX = c.Width / 2 - r - 0.1
	local wheelZ = c.Length / 2 - r - 0.1
	local groundY = -(c.FloorThickness / 2 + c.WheelGap + c.WheelDiameter)
	for _, x in { -wheelX, wheelX } do
		for _, z in { -wheelZ, wheelZ } do
			local attachment = Instance.new("Attachment")
			attachment.Name = "WheelDustAttachment"
			attachment.Position = Vector3.new(x, groundY + 0.2, z)
			attachment.Parent = base
			table.insert(
				wheels,
				{ attachment = attachment, emitter = makeEmitter(attachment), surface = nil }
			)
		end
	end
end

function WheelDust.detach()
	for _, wheel in wheels do
		wheel.attachment:Destroy()
	end
	table.clear(wheels)
end

-- Untergrund unter jedem Rad bestimmen
local function checkSurfaces()
	for _, wheel in wheels do
		local origin = wheel.attachment.WorldPosition + Vector3.new(0, 1, 0)
		local hit = workspace:Raycast(origin, Vector3.new(0, -3, 0), rayParams)
		wheel.surface = if hit then SpeedFeel.surface(hit.Material.Name) else nil
	end
end

function WheelDust.update(dt: number, telemetry: CartController.Telemetry)
	if #wheels == 0 then
		return
	end
	local A = Config.Atmosphere
	checkTimer -= dt
	if checkTimer <= 0 then
		checkTimer = A.WheelCheckInterval
		checkSurfaces()
	end
	local on = Settings.get("VisualEffects") and telemetry.grounded
	local drifting = telemetry.skidding or telemetry.driftCharging
	for _, wheel in wheels do
		local def = wheel.surface and (A.Surfaces :: any)[wheel.surface]
		if not on or not def then
			wheel.emitter.Rate = 0
			continue
		end
		wheel.emitter.Rate = SpeedFeel.wheelRate(
			def.Rate,
			telemetry.speed,
			A.TopSpeed,
			A.WheelMinSpeed,
			drifting,
			A.WheelDriftFactor,
			A.WheelMaxRate
		)
		wheel.emitter.Color = ColorSequence.new(def.Color)
		wheel.emitter.Size = NumberSequence.new(def.Size, def.Size * 1.8)
	end
end

return WheelDust
