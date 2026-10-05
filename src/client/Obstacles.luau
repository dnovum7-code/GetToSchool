--!strict
-- Bewegte Hindernisse: Mover, Spinner, Pendulum (Tags auf Parts oder Modellen).
--
-- So funktioniert die Physik:
--   * Die Teile sind verankert (Anchored) und werden per Skript bewegt, wie ein
--     kinematischer Rigidbody mit MovePosition in Unity.
--   * Zusaetzlich zur Position setzen wir jeden Frame die passende Geschwindigkeit am Teil.
--     Dadurch "weiss" die Physik, wie schnell sich das Teil bewegt, und schiebt den Wagen
--     sauber weg bzw. nimmt ihn mit, statt ihn durch das Teil zu teleportieren.
--   * Jeder Client bewegt die Hindernisse selbst, direkt vor jedem Physik-Schritt
--     (PreSimulation). Als Uhr dient die Serverzeit, damit alle Spieler sie an derselben
--     Stelle sehen. Der eigene Wagen (vom Client gerechnet) stoesst so ohne
--     Netzwerk-Verzoegerung an.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local TagList = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TagList"))

local Obstacles = {}

type Obstacle = {
	instance: PVInstance,
	kind: string, -- "Mover", "Spinner" oder "Pendulum"
	baseCFrame: CFrame, -- Lage aus Studio (Startposition)
	lastCFrame: CFrame,
}

local obstacles: { [Instance]: Obstacle } = {}

local function numberAttribute(instance: Instance, name: string, default: number): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local function getCFrame(instance: PVInstance): CFrame
	if instance:IsA("BasePart") then
		return instance.CFrame
	end
	return instance:GetPivot()
end

-- weiches Anfahren und Abbremsen (0..1 -> 0..1)
local function smoothstep(x: number): number
	return x * x * (3 - 2 * x)
end

-- Wo ist das Hindernis zum Zeitpunkt `t` (Serverzeit)?
local function targetCFrame(obstacle: Obstacle, t: number): CFrame
	local instance = obstacle.instance
	local M = Config.Movers
	t += numberAttribute(instance, "Phase", 0)

	if obstacle.kind == "Mover" then
		local offsetAttribute = instance:GetAttribute("Offset")
		local offset = if typeof(offsetAttribute) == "Vector3" then offsetAttribute else M.MoverOffset
		local duration = math.max(numberAttribute(instance, "Duration", M.MoverDuration), 0.05)
		local pause = math.max(numberAttribute(instance, "Pause", M.MoverPause), 0)
		-- Ablauf: warten - hinfahren - warten - zurueckfahren
		local period = 2 * (duration + pause)
		local phase = t % period
		local alpha
		if phase < pause then
			alpha = 0
		elseif phase < pause + duration then
			alpha = smoothstep((phase - pause) / duration)
		elseif phase < 2 * pause + duration then
			alpha = 1
		else
			alpha = 1 - smoothstep((phase - 2 * pause - duration) / duration)
		end
		return obstacle.baseCFrame * CFrame.new(offset * alpha)
	elseif obstacle.kind == "Spinner" then
		local speed = numberAttribute(instance, "Speed", M.SpinnerSpeed)
		return obstacle.baseCFrame * CFrame.Angles(0, math.rad((speed * t) % 360), 0)
	else
		local angle = numberAttribute(instance, "Angle", M.PendulumAngle)
		local duration = math.max(numberAttribute(instance, "Duration", M.PendulumDuration), 0.05)
		local swing = math.rad(angle) * math.sin(2 * math.pi * t / duration)
		-- Drehpunkt: bei einem Part die Oberkante, bei einem Modell sein Pivot
		local hinge = CFrame.identity
		if instance:IsA("BasePart") then
			hinge = CFrame.new(0, instance.Size.Y / 2, 0)
		end
		return obstacle.baseCFrame * hinge * CFrame.Angles(swing, 0, 0) * hinge:Inverse()
	end
end

-- Teil(e) bewegen und die passende Geschwindigkeit setzen
local function apply(obstacle: Obstacle, target: CFrame, dt: number)
	local last = obstacle.lastCFrame
	obstacle.lastCFrame = target
	local instance = obstacle.instance
	if instance:IsA("BasePart") then
		instance.CFrame = target
	elseif instance:IsA("Model") then
		instance:PivotTo(target)
	end
	if dt <= 0 then
		return
	end

	-- Geschwindigkeit aus der Bewegung seit dem letzten Frame
	local linear = (target.Position - last.Position) / dt
	local axis, angle = (last.Rotation:Inverse() * target.Rotation):ToAxisAngle()
	local angular = Vector3.zero
	if math.abs(angle) > 1e-6 then
		angular = last.Rotation:VectorToWorldSpace(axis) * (angle / dt)
	end
	local pivot = target.Position

	local function setVelocity(part: BasePart)
		-- Punkt auf einem drehenden Teil: Tempo des Drehpunkts + Drehung * Hebelarm
		part.AssemblyLinearVelocity = linear + angular:Cross(part.Position - pivot)
		part.AssemblyAngularVelocity = angular
	end
	if instance:IsA("BasePart") then
		setVelocity(instance)
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			setVelocity(descendant)
		end
	end
end

local function track(kind: string, instance: Instance)
	if obstacles[instance] or not (instance:IsA("BasePart") or instance:IsA("Model")) then
		return
	end
	local pv = instance :: PVInstance
	local base = getCFrame(pv)
	obstacles[instance] = { instance = pv, kind = kind, baseCFrame = base, lastCFrame = base }
end

function Obstacles.init()
	-- TagList meldet auch Hindernisse, die durch Streaming spaeter (wieder) geladen werden
	for _, kind in { "Mover", "Spinner", "Pendulum" } do
		TagList.watch(kind, function(instance)
			track(kind, instance)
		end)
	end

	RunService.PreSimulation:Connect(function(dt)
		local t = workspace:GetServerTimeNow()
		for instance, obstacle in obstacles do
			-- entfernt oder (durch Streaming) entladen: vergessen; kommt es wieder, neu einlesen
			if not instance:IsDescendantOf(workspace) then
				obstacles[instance] = nil
				continue
			end
			apply(obstacle, targetCFrame(obstacle, t), dt)
		end
	end)
end

return Obstacles
