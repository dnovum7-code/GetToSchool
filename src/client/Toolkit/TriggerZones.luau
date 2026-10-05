--!strict
-- TriggerZone (Tag "TriggerZone", Part): Faehrt der eigene Wagen hinein, wird das Signal
-- aus dem Attribut "Signal" ausgeloest. Attribute: Once (nur einmal pro Lauf),
-- Cooldown (Sekunden). Bei Neustart (R und T) wieder scharf.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TagList = require(Shared:WaitForChild("TagList"))
local TriggerRules = require(Shared:WaitForChild("Toolkit"):WaitForChild("TriggerRules"))
local Pieces = require(script.Parent:WaitForChild("Pieces"))
local Signals = require(script.Parent:WaitForChild("Signals"))
local ToolkitTypes = require(script.Parent:WaitForChild("ToolkitTypes"))

type Zone = {
	part: BasePart,
	state: TriggerRules.State,
}

local zones: { [Instance]: Zone } = {}
local warnedNoSignal: { [Instance]: boolean } = {}

local TriggerZones: ToolkitTypes.Piece = {
	init = function()
		TagList.watch("TriggerZone", function(instance)
			if instance:IsA("BasePart") and not zones[instance] then
				zones[instance] = { part = instance, state = TriggerRules.new() }
			end
		end)
	end,

	step = function(ctx)
		local base = ctx.base
		local now = os.clock()
		local T = Config.Toolkit
		for instance, zone in zones do
			if not instance:IsDescendantOf(workspace) then
				zones[instance] = nil
				continue
			end
			local inside = base ~= nil and Pieces.inBox(zone.part, base.Position, T.TriggerMargin)
			local once = Pieces.bool(instance, "Once", T.TriggerOnce)
			local cooldown = Pieces.number(instance, "Cooldown", T.TriggerCooldown)
			if TriggerRules.update(zone.state, inside, now, once, cooldown) then
				local signal = Pieces.string(instance, "Signal", nil)
				if signal then
					Signals.fire(signal, `TriggerZone "{instance.Name}"`)
				elseif not warnedNoSignal[instance] then
					warnedNoSignal[instance] = true
					warn(`[Baukasten] {instance:GetFullName()}: TriggerZone ohne Attribut "Signal".`)
				end
			end
		end
	end,

	reset = function()
		for _, zone in zones do
			TriggerRules.rearm(zone.state)
		end
	end,
}

return TriggerZones
