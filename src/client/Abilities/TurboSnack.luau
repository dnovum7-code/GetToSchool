--!strict
-- Turbo-Pausenbrot (Upgrade "Turbo"), Taste F / Gamepad RB: kurzer Schub nach vorne,
-- danach Abklingzeit. Hoehere Stufen = kuerzere Abklingzeit (Config.Abilities.TurboCooldownX).
-- Feedback: Kruemel-Wolke hinten am Wagen, Sichtfeld zieht auf, Sound.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local RunRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"):WaitForChild("RunRules"))
local AbilityTypes = require(script.Parent:WaitForChild("AbilityTypes"))

local cooldownLeft = 0
local cooldownTotal = 1
local emitter: ParticleEmitter? = nil

-- Brotkruemel: braun-gelbe Partikel hinten am Wagen
local function crumbs(base: BasePart)
	local current = emitter
	if not current or current.Parent == nil or current:FindFirstAncestorOfClass("Model") ~= base.Parent then
		local attachment = Instance.new("Attachment")
		attachment.Name = "TurboCrumbs"
		attachment.Position = Vector3.new(0, 0.5, Config.Cart.Length / 2)
		attachment.Parent = base
		local newEmitter = Instance.new("ParticleEmitter")
		newEmitter.Rate = 0
		newEmitter.Lifetime = NumberRange.new(0.4, 0.8)
		newEmitter.Speed = NumberRange.new(10, 20)
		newEmitter.SpreadAngle = Vector2.new(40, 40)
		newEmitter.EmissionDirection = Enum.NormalId.Back
		newEmitter.Acceleration = Vector3.new(0, -60, 0)
		newEmitter.Color = ColorSequence.new(Color3.fromRGB(210, 160, 80), Color3.fromRGB(255, 220, 120))
		newEmitter.Size = NumberSequence.new(0.35, 0.1)
		newEmitter.Parent = attachment
		emitter = newEmitter
		current = newEmitter
	end
	(current :: ParticleEmitter):Emit(40)
end

local TurboSnack: AbilityTypes.Ability = {
	id = "Turbo",

	afterStep = function(ctx)
		cooldownLeft = math.max(0, cooldownLeft - ctx.dt)
		if ctx.level < 1 or not ctx.input.turboPressed then
			return
		end
		if cooldownLeft > 0 then
			ctx.effects.toast(string.format("Pausenbrot noch nicht verdaut (%.1f s)", cooldownLeft))
			return
		end
		local A = Config.Abilities
		ctx.controller:startBoost(A.TurboGain, A.TurboDuration)
		ctx.expectImpulse(Vector3.zero) -- Schub ist kein Aufprall
		cooldownTotal = math.max(RunRules.levelValue(A, "TurboCooldown", ctx.level, 10), 0.1)
		cooldownLeft = cooldownTotal
		crumbs(ctx.controller.base)
		ctx.effects.fovKick(Config.Camera.BoostFovKick)
		ctx.effects.sound("Turbo")
	end,

	reset = function(kind)
		if kind == "Full" then
			cooldownLeft = 0
		end
	end,

	hud = function(level)
		if level <= 0 then
			return nil
		end
		local ready = cooldownLeft <= 0
		return {
			name = "Turbo-Pausenbrot",
			key = "F",
			status = if ready then "bereit" else string.format("%.1f s", cooldownLeft),
			fill = if ready then 1 else 1 - cooldownLeft / cooldownTotal,
			active = ready,
			color = Color3.fromRGB(255, 190, 70),
		}
	end,
}

return TurboSnack
