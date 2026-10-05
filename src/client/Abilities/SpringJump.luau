--!strict
-- Trampolin-Sprungfeder (Upgrade "Spring"), Leertaste / Gamepad A:
--   ohne Upgrade: kleiner Hopp (Config.Hop.Speed)
--   Stufe 1:      richtiger Sprung (Config.Abilities.JumpSpeed1)
--   Stufe 2:      dazu Doppelsprung (in der Luft nochmal druecken)
-- Der Sprung selbst passiert in CartController (wie der Hopp, mit Luft-Drehung).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local RunRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"):WaitForChild("RunRules"))
local AbilityTypes = require(script.Parent:WaitForChild("AbilityTypes"))

local usedDouble = false
local wasGrounded = true

-- Kleiner Ring unter dem Wagen beim Doppelsprung
local function puff(base: BasePart)
	local ring = Instance.new("Part")
	ring.Name = "DoubleJumpPuff"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(150, 230, 255)
	ring.Transparency = 0.3
	ring.Size = Vector3.new(0.3, 4, 4)
	ring.CFrame = CFrame.new(base.Position - Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	local start = os.clock()
	task.spawn(function()
		while os.clock() - start < 0.35 do
			local alpha = (os.clock() - start) / 0.35
			ring.Size = Vector3.new(0.3, 4 + alpha * 8, 4 + alpha * 8)
			ring.Transparency = 0.3 + 0.7 * alpha
			task.wait()
		end
		ring:Destroy()
	end)
end

local SpringJump: AbilityTypes.Ability = {
	id = "Spring",

	beforeStep = function(ctx)
		ctx.controller.hopSpeedOverride = if ctx.level >= 1
			then RunRules.levelValue(Config.Abilities, "JumpSpeed", ctx.level, Config.Hop.Speed)
			else nil
	end,

	afterStep = function(ctx)
		local telemetry = ctx.telemetry
		if not telemetry then
			return
		end
		if telemetry.grounded and not wasGrounded then
			usedDouble = false -- gelandet: Doppelsprung wieder bereit
		end
		wasGrounded = telemetry.grounded
		if
			ctx.level >= 2
			and ctx.input.jumpPressed
			and not telemetry.grounded
			and not telemetry.hopped
			and not usedDouble
		then
			usedDouble = true
			ctx.expectImpulse(ctx.controller:airJump(Config.Abilities.DoubleJumpSpeed))
			puff(ctx.controller.base)
			ctx.effects.sound("DoubleJump")
		end
	end,

	reset = function()
		usedDouble = false
		wasGrounded = true
	end,

	hud = function(level)
		if level <= 0 then
			return nil
		end
		if level >= 2 then
			return {
				name = "Sprungfeder",
				key = "Leertaste",
				status = if usedDouble then "Doppelsprung weg" else "Doppelsprung bereit",
				fill = if usedDouble then 0 else 1,
				color = Color3.fromRGB(150, 230, 255),
			}
		end
		return {
			name = "Sprungfeder",
			key = "Leertaste",
			status = "Sprung",
			color = Color3.fromRGB(150, 230, 255),
		}
	end,
}

return SpringJump
