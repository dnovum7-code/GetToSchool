--!strict
-- AmbientParticles (Tag, Part): Bereich mit Blaettern, Pollen oder Staub, die dem GlobalWind
-- folgen (Workspace-Eigenschaft GlobalWind). Attribute: Kind ("Leaves", "Pollen", "Dust"),
-- Rate (Teilchen pro Sekunde, sonst je nach Kind), Color (Color3). Das Part selbst ist im
-- Spiel unsichtbar. Nur die naechsten Config.Ambient.Particles.MaxActive in Range sind an.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local TagList = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TagList"))
local Settings = require(script.Parent.Parent:WaitForChild("Settings"))
local Nearby = require(script.Parent:WaitForChild("Nearby"))
local Pieces = require(script.Parent:WaitForChild("Pieces"))
local ToolkitTypes = require(script.Parent:WaitForChild("ToolkitTypes"))

type Zone = { part: BasePart, emitter: ParticleEmitter? }

local zones: { [Instance]: Zone } = {}
local list: { Zone } = {}
local due = Nearby.timer()

local function kindOf(part: BasePart): any
	local kinds = Config.Ambient.Particles.Kinds :: any
	local kind = Pieces.string(part, "Kind", "Leaves") or "Leaves"
	return kinds[kind] or kinds.Leaves
end

local function start(zone: Zone)
	local P = Config.Ambient.Particles
	local def = kindOf(zone.part)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "AmbientParticles"
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Rate = Pieces.number(zone.part, "Rate", def.Rate)
	emitter.Lifetime = NumberRange.new(def.Lifetime * 0.7, def.Lifetime)
	emitter.Speed = NumberRange.new(def.Speed * 0.5, def.Speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(def.Size)
	local color = zone.part:GetAttribute("Color")
	emitter.Color = ColorSequence.new(if typeof(color) == "Color3" then color else def.Color)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.1),
		NumberSequenceKeypoint.new(0.85, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	-- dem GlobalWind folgen
	emitter.Drag = P.WindDrag
	emitter.WindAffectsDrag = P.WindDrag > 0
	emitter.Acceleration = Vector3.new(0, -0.5, 0)
	emitter.Parent = zone.part
	zone.emitter = emitter
end

local function stop(zone: Zone)
	local emitter = zone.emitter
	if emitter then
		emitter:Destroy()
		zone.emitter = nil
	end
end

local AmbientParticles: ToolkitTypes.Piece = {
	init = function()
		TagList.watch("AmbientParticles", function(instance)
			if instance:IsA("BasePart") and not zones[instance] then
				local zone: Zone = { part = instance, emitter = nil }
				zones[instance] = zone
				table.insert(list, zone)
			end
		end)
	end,

	step = function(ctx)
		if not due(ctx.dt) then
			return
		end
		for index = #list, 1, -1 do
			local zone = list[index]
			if not zone.part:IsDescendantOf(workspace) then
				stop(zone)
				zones[zone.part] = nil
				table.remove(list, index)
			end
		end
		local focus = Nearby.focus(ctx)
		local P = Config.Ambient.Particles
		local active = if focus and Settings.get("VisualEffects")
			then Nearby.select(list, function(zone: Zone)
				return zone.part.Position
			end, focus, P.Range, P.MaxActive)
			else {}
		for _, zone in list do
			if active[zone] and not zone.emitter then
				start(zone)
			elseif not active[zone] and zone.emitter then
				stop(zone)
			end
		end
	end,
}

return AmbientParticles
