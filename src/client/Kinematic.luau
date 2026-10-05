--!strict
-- Verankerte Teile per Skript bewegen, so dass die Physik sie "versteht":
-- Neben der neuen Lage setzen wir die passende Geschwindigkeit am Teil. Dann schiebt das
-- Teil den Wagen sauber weg bzw. nimmt ihn mit, statt ihn durch das Teil zu teleportieren.
-- Unity-Vergleich: kinematischer Rigidbody mit MovePosition/MoveRotation.
-- Benutzt von Obstacles (Mover, Spinner, Pendulum) und den Baukasten-Bausteinen.

local Kinematic = {}

function Kinematic.getCFrame(instance: PVInstance): CFrame
	if instance:IsA("BasePart") then
		return instance.CFrame
	end
	return instance:GetPivot()
end

-- `instance` von `last` nach `target` bewegen (`dt` = Zeit seit dem letzten Aufruf).
-- `usePivot`: die Lagen sind Pivot-Lagen (GetPivot/PivotTo), auch bei einzelnen Parts.
function Kinematic.move(instance: PVInstance, last: CFrame, target: CFrame, dt: number, usePivot: boolean?)
	if usePivot then
		instance:PivotTo(target)
	elseif instance:IsA("BasePart") then
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

-- Bewegung anhalten (Geschwindigkeit 0), z. B. wenn ein Tor stillsteht
function Kinematic.stop(instance: PVInstance)
	local function zero(part: BasePart)
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
	end
	if instance:IsA("BasePart") then
		zero(instance)
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			zero(descendant)
		end
	end
end

return Kinematic
