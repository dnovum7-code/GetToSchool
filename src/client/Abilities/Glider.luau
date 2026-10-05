--!strict
-- Rucksack-Fallschirm (Upgrade "Glider"): Leertaste in der Luft halten = langsamer fallen
-- und weiter fliegen, lenken geht auch. Sichtbar als Schirm ueber dem Wagen (nur bei dir).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local AbilityTypes = require(script.Parent:WaitForChild("AbilityTypes"))

local gliding = false
local canopy: Model? = nil

-- Schirm aus einfachen Teilen, am Wagen festgeschweisst (ohne Gewicht). Er liegt nicht im
-- Wagen-Modell, sonst wuerde er dessen Groesse (Beruehrungs-Abfragen) veraendern.
local function getCanopy(base: BasePart): Model
	local current = canopy
	if current and current.Parent and current:GetAttribute("ForBase") == base:GetFullName() then
		local first = current:FindFirstChildWhichIsA("WeldConstraint", true)
		if first and first.Part0 == base then
			return current
		end
	end
	if current then
		current:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "GliderCanopy"
	local function part(name: string, size: Vector3, offset: CFrame, color: Color3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = base.CFrame * offset
		p.Color = color
		p.Material = Enum.Material.Fabric
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Transparency = 1
		p.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = base
		weld.Part1 = p
		weld.Parent = p
		return p
	end
	part("Canopy", Vector3.new(8, 0.6, 5), CFrame.new(0, 8, 0), Color3.fromRGB(240, 80, 120))
	part("CanopyStripe", Vector3.new(2, 0.65, 5.05), CFrame.new(0, 8, 0), Color3.fromRGB(255, 230, 90))
	for _, x in { -3.5, 3.5 } do
		part(
			"Cord",
			Vector3.new(0.1, 6.5, 0.1),
			CFrame.new(x * 0.8, 4.8, 0) * CFrame.Angles(0, 0, math.rad(x * 3)),
			Color3.new(1, 1, 1)
		)
	end
	model:SetAttribute("ForBase", base:GetFullName())
	model.Parent = workspace
	canopy = model
	return model
end

local function setVisible(base: BasePart, visible: boolean)
	if not visible and not canopy then
		return
	end
	for _, item in getCanopy(base):GetChildren() do
		if item:IsA("BasePart") then
			item.Transparency = if visible then 0 else 1
		end
	end
end

local Glider: AbilityTypes.Ability = {
	id = "Glider",

	afterStep = function(ctx)
		local telemetry = ctx.telemetry
		local controller = ctx.controller
		local base = controller.base
		local velocity = base.AssemblyLinearVelocity
		local active = ctx.level >= 1
			and ctx.input.jumpHeld
			and telemetry ~= nil
			and not telemetry.grounded
			and velocity.Y < 0
		if active then
			local A = Config.Abilities
			local gravity = workspace.Gravity
			-- Fallen auf GlideFallSpeed bremsen (gleich schnell wie die Schwerkraft = schweben)
			local lift =
				math.clamp(gravity + (-A.GlideFallSpeed - velocity.Y) * A.GlideResponse, 0, gravity * 2)
			local force = Vector3.new(0, lift, 0)
			local look = Vector3.new(base.CFrame.LookVector.X, 0, base.CFrame.LookVector.Z)
			local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			if look.Magnitude > 0.1 and flatSpeed < A.GlideMaxSpeed then
				force += look.Unit * A.GlideForwardAccel
			end
			controller:addForce(force * controller:getMass())
			-- Lenken in der Luft (A/D): Ziel-Drehgeschwindigkeit um die Hochachse
			local steer = 0
			if
				UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right)
			then
				steer += 1
			end
			if
				UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left)
			then
				steer -= 1
			end
			local yawRate = base.AssemblyAngularVelocity.Y
			local target = -steer * A.GlideSteerRate
			controller:addTorque(Vector3.yAxis * (target - yawRate) * 4 * controller:getInertia())
			if not gliding then
				ctx.effects.sound("Glide")
			end
		end
		if active ~= gliding then
			setVisible(base, active)
		end
		gliding = active
	end,

	reset = function()
		gliding = false
		local current = canopy
		if current then
			current:Destroy()
			canopy = nil
		end
	end,

	hud = function(level)
		if level <= 0 then
			return nil
		end
		return {
			name = "Rucksack-Fallschirm",
			key = "Leertaste halten",
			status = if gliding then "gleitet!" else "in der Luft",
			active = gliding,
			color = Color3.fromRGB(240, 80, 120),
		}
	end,
}

return Glider
