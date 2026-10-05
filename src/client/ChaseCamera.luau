--!strict
-- Verfolgerkamera hinter dem Wagen. Unity-Vergleich: ein Follow-Script in LateUpdate.
-- Die Kamera schaut in die waagerechte Fahrtrichtung des Wagens. Wenn sich der Wagen
-- ueberschlaegt, behaelt sie die letzte Richtung, damit das Bild nicht wild dreht.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local ChaseCamera = {}

local BIND_NAME = "GetToSchoolChaseCamera"

local target: BasePart? = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local direction = -Vector3.zAxis -- geglaettete Blickrichtung (waagerecht)
local position: Vector3? = nil -- geglaettete Kameraposition
local fov = Config.Camera.BaseFov

local function smoothing(rate: number, dt: number): number
	-- bildratenunabhaengiges Lerp
	return 1 - math.exp(-rate * dt)
end

local function flatLook(part: BasePart): Vector3?
	local cf = part.CFrame
	-- liegt der Wagen auf der Seite oder auf dem Kopf, ist seine Blickrichtung unbrauchbar
	if cf.UpVector.Y < 0.3 then
		return nil
	end
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 0.1 then
		return nil
	end
	return look.Unit
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	local part = target
	if not camera or not part or not part.Parent then
		return
	end
	local C = Config.Camera
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local look = flatLook(part)
	if look then
		direction = direction:Lerp(look, smoothing(C.RotationSmoothing, dt))
		if direction.Magnitude < 0.01 then
			direction = look
		end
		direction = direction.Unit
	end

	local focus = part.Position + Vector3.new(0, C.LookHeight, 0)
	local desired = part.Position - direction * C.Distance + Vector3.new(0, C.Height, 0)
	local current = position or desired
	current = current:Lerp(desired, smoothing(C.PositionSmoothing, dt))

	-- Nicht durch Huegel oder Waende schauen: Kamera vor das Hindernis ziehen
	local toCamera = current - focus
	local hit = workspace:Raycast(focus, toCamera, rayParams)
	local final = current
	if hit then
		final = hit.Position - toCamera.Unit * C.CollisionPadding
	end
	position = current

	-- Mehr Sichtfeld bei hohem Tempo (Geschwindigkeitsgefuehl)
	local speed = part.AssemblyLinearVelocity.Magnitude
	local targetFov = C.BaseFov + (C.MaxFov - C.BaseFov) * math.clamp(speed / C.FovFullSpeed, 0, 1)
	fov += (targetFov - fov) * smoothing(4, dt)
	camera.FieldOfView = fov

	camera.CFrame = CFrame.lookAt(final, focus + direction * C.LookAhead)
end

-- Kamera an den Wagen haengen. `ignore`: Objekte, durch die die Kamera schauen darf.
function ChaseCamera.start(part: BasePart, ignore: { Instance })
	target = part
	rayParams.FilterDescendantsInstances = ignore
	ChaseCamera.snap()
	RunService:UnbindFromRenderStep(BIND_NAME)
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, update)
end

-- Ohne Glaettung direkt hinter den Wagen springen (z. B. nach einem Neustart).
function ChaseCamera.snap()
	position = nil
	local part = target
	if part then
		direction = flatLook(part) or direction
	end
end

function ChaseCamera.stop(humanoid: Humanoid?)
	target = nil
	RunService:UnbindFromRenderStep(BIND_NAME)
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = Config.Camera.BaseFov
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

return ChaseCamera
