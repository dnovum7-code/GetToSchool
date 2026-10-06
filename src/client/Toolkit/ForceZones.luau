--!strict
-- ForceZone (Tag "ForceZone", Part = Bereich): Solange der eigene Wagen darin ist, drueckt
-- sie ihn in Richtung ihrer Vorderseite (LookVector). Strength = Beschleunigung.
--   Pulse > 0:      an/aus im Takt (PulseOn = Anteil "an"), nach der Serveruhr
--   ListenSignal:   nur ActiveTime Sekunden nach dem Signal an
-- Die Kraft kommt ueber die Fahrphysik (CartController:addForce), also ohne Verzoegerung.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TagList = require(Shared:WaitForChild("TagList"))
local LocalHide = require(script.Parent.Parent:WaitForChild("LocalHide"))
local Pieces = require(script.Parent:WaitForChild("Pieces"))
local Signals = require(script.Parent:WaitForChild("Signals"))
local ToolkitTypes = require(script.Parent:WaitForChild("ToolkitTypes"))

type Zone = {
	part: BasePart,
	signalAt: number?,
	disconnect: (() -> ())?,
}

local zones: { [Instance]: Zone } = {}

local function register(instance: Instance)
	if zones[instance] or not instance:IsA("BasePart") then
		return
	end
	local zone: Zone = { part = instance, signalAt = nil, disconnect = nil }
	local listen = Pieces.string(instance, "ListenSignal", nil)
	if listen then
		zone.disconnect = Signals.on(listen, function()
			zone.signalAt = os.clock()
		end)
	end
	zones[instance] = zone
end

local function isActive(zone: Zone): boolean
	local part = zone.part
	local F = Config.ForceZone
	if zone.disconnect then
		local at = zone.signalAt
		return at ~= nil and os.clock() - at < Pieces.number(part, "ActiveTime", F.ActiveTime)
	end
	local pulse = Pieces.number(part, "Pulse", F.Pulse)
	if pulse <= 0 then
		return true
	end
	local t = (workspace:GetServerTimeNow() + Pieces.number(part, "Phase", 0)) % pulse
	return t < pulse * math.clamp(Pieces.number(part, "PulseOn", F.PulseOn), 0, 1)
end

local ForceZones: ToolkitTypes.Piece = {
	init = function()
		TagList.watch("ForceZone", register)
	end,

	step = function(ctx)
		local base, controller = ctx.base, ctx.controller
		for instance, zone in zones do
			if not instance:IsDescendantOf(workspace) then
				if zone.disconnect then
					zone.disconnect()
				end
				zones[instance] = nil
				continue
			end
			-- 1 Stud Spielraum nach oben/unten: auch duenne Zonen (z. B. Foerderband) wirken
			if
				base
				and controller
				and Pieces.inBox(zone.part, base.Position, 1)
				and isActive(zone)
				and not LocalHide.isHidden(instance)
			then
				local strength = Pieces.number(instance, "Strength", Config.ForceZone.Strength)
				controller:addForce(zone.part.CFrame.LookVector * strength * controller:getMass())
			end
		end
	end,

	-- R und T: Signal-Zonen aus
	reset = function()
		for _, zone in zones do
			zone.signalAt = nil
		end
	end,
}

return ForceZones
