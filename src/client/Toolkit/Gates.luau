--!strict
-- Gate (Tag "Gate", Modell oder Part): Schiebetor, Schranke, Klappbruecke. Oeffnet sich um
-- Offset (Verschiebung) und/oder Angle (Drehung um die Achse Axis des Pivots).
--   Ohne ListenSignal: im Takt (ClosedTime - Duration - OpenTime - Duration), nach der
--                      Serveruhr fuer alle Spieler gleich. Attribut Phase verschiebt den Takt.
--   Mit ListenSignal:  oeffnet beim Signal, schliesst nach CloseAfter Sekunden (0 = nie).
-- StartOpen = true dreht das um (Grundzustand offen, Signal schliesst).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TagList = require(Shared:WaitForChild("TagList"))
local PathMath = require(Shared:WaitForChild("Toolkit"):WaitForChild("PathMath"))
local Kinematic = require(script.Parent.Parent:WaitForChild("Kinematic"))
local LocalClone = require(script.Parent.Parent:WaitForChild("LocalClone"))
local LocalHide = require(script.Parent.Parent:WaitForChild("LocalHide"))
local Pieces = require(script.Parent:WaitForChild("Pieces"))
local Signals = require(script.Parent:WaitForChild("Signals"))
local ToolkitTypes = require(script.Parent:WaitForChild("ToolkitTypes"))

type Gate = {
	instance: PVInstance,
	home: CFrame, -- Pivot im Grundzustand (wie in Studio gebaut)
	last: CFrame,
	signalAt: number?, -- os.clock() beim Signal
	disconnect: (() -> ())?,
	parts: { BasePart }, -- zwischengespeichert
	moving: boolean, -- hat sich im letzten Frame bewegt
	snap: boolean, -- naechste Bewegung ohne Geschwindigkeit (nach Neustart)
	alpha: number, -- aktuelle Oeffnung 0..1
}

local gates: { [Instance]: Gate } = {}

local function register(instance: Instance)
	if gates[instance] or not (instance:IsA("Model") or instance:IsA("BasePart")) then
		return
	end
	local pv = instance :: PVInstance
	local home = pv:GetPivot()
	local gate: Gate = {
		instance = pv,
		home = home,
		last = home,
		signalAt = nil,
		disconnect = nil,
		parts = LocalClone.allParts(instance),
		moving = false,
		snap = false,
		alpha = 0,
	}
	local listen = Pieces.string(instance, "ListenSignal", nil)
	if listen then
		gate.disconnect = Signals.on(listen, function()
			if LocalHide.isHidden(instance) then
				return
			end
			local G = Config.Gate
			local duration = math.max(Pieces.number(instance, "Duration", G.Duration), 0.01)
			local at = gate.signalAt
			if at == nil then
				gate.signalAt = os.clock()
				return
			end
			-- Schon offen oder am Oeffnen: nicht von vorne beginnen (sonst klappt es zu und
			-- wieder auf). Offen: Haltezeit neu starten. Schliesst gerade: von der aktuellen
			-- Oeffnung aus wieder oeffnen.
			local since = os.clock() - at
			if since < duration then
				return
			end
			local closeAfter = Pieces.number(instance, "CloseAfter", G.CloseAfter)
			if closeAfter <= 0 or since < duration + closeAfter then
				gate.signalAt = os.clock() - duration
			else
				gate.signalAt = os.clock() - duration * gate.alpha
			end
		end)
	end
	local G = Config.Gate
	if
		Pieces.vector(instance, "Offset", G.Offset).Magnitude < 0.01
		and Pieces.number(instance, "Angle", G.Angle) == 0
	then
		warn(`[Baukasten] {instance:GetFullName()}: Gate ohne Offset und Angle bewegt sich nicht.`)
	end
	gates[instance] = gate
end

-- Lage bei Oeffnung `alpha` (0 = Grundzustand, 1 = ganz offen)
local function targetFor(gate: Gate, alpha: number): CFrame
	local instance = gate.instance
	local G = Config.Gate
	local offset = Pieces.vector(instance, "Offset", G.Offset)
	local angle = math.rad(Pieces.number(instance, "Angle", G.Angle)) * alpha
	local axis = string.upper(Pieces.string(instance, "Axis", G.Axis) or "X")
	local rotation = if axis == "Y"
		then CFrame.Angles(0, angle, 0)
		elseif axis == "Z" then CFrame.Angles(0, 0, angle)
		else CFrame.Angles(angle, 0, 0)
	return gate.home * CFrame.new(offset * alpha) * rotation
end

local Gates: ToolkitTypes.Piece = {
	init = function()
		TagList.watch("Gate", register)
	end,

	step = function(ctx)
		local G = Config.Gate
		for instance, gate in gates do
			if not instance:IsDescendantOf(workspace) then
				if gate.disconnect then
					gate.disconnect()
				end
				gates[instance] = nil
				continue
			end
			local duration = Pieces.number(instance, "Duration", G.Duration)
			local alpha
			if gate.disconnect then
				local since = if gate.signalAt then os.clock() - gate.signalAt else nil
				alpha =
					PathMath.gateSignal(since, duration, Pieces.number(instance, "CloseAfter", G.CloseAfter))
			else
				local t = workspace:GetServerTimeNow() + Pieces.number(instance, "Phase", 0)
				alpha = PathMath.gateTimer(
					t,
					duration,
					Pieces.number(instance, "OpenTime", G.OpenTime),
					Pieces.number(instance, "ClosedTime", G.ClosedTime)
				)
			end
			gate.alpha = alpha
			if Pieces.bool(instance, "StartOpen", G.StartOpen) then
				alpha = 1 - alpha
			end
			local target = targetFor(gate, alpha)
			if target ~= gate.last then
				Kinematic.move(
					gate.instance,
					gate.last,
					target,
					if gate.snap then 0 else ctx.dt,
					true,
					gate.parts
				)
				gate.last = target
				gate.moving = true
			elseif gate.moving then
				-- gerade angekommen: Geschwindigkeit einmal auf 0 (nicht jeden Frame)
				Kinematic.stop(gate.instance, gate.parts)
				gate.moving = false
			end
			gate.snap = false
		end
	end,

	-- R und T: Signal-Tore zurueck in den Grundzustand
	reset = function()
		for _, gate in gates do
			if gate.disconnect then
				gate.signalAt = nil
				gate.snap = true -- in den Grundzustand springen, ohne den Wagen wegzuschleudern
			end
		end
	end,
}

return Gates
