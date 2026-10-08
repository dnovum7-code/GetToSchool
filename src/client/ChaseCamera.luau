--!strict
-- Verfolgerkamera hinter dem Wagen. Unity-Vergleich: ein Follow-Script in LateUpdate.
-- Die Kamera schaut in die waagerechte Fahrtrichtung des Wagens. Wenn sich der Wagen
-- ueberschlaegt, behaelt sie die letzte Richtung, damit das Bild nicht wild dreht.
-- Frei drehen: rechte Maustaste ziehen, Gamepad rechter Stick, Touch: wischen (nicht auf
-- Knoepfen). Mausrad = Zoom. Ohne Eingabe dreht sie nach kurzer Zeit weich zurueck.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Settings = require(script.Parent:WaitForChild("Settings"))

local ChaseCamera = {}

local BIND_NAME = "GetToSchoolChaseCamera"

local target: BasePart? = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local direction = -Vector3.zAxis -- geglaettete Blickrichtung (waagerecht)
local position: Vector3? = nil -- geglaettete Kameraposition
local fov = Config.Camera.BaseFov
local landingShake = 0 -- zusaetzliches Wackeln nach harten Landungen (Grad), klingt ab
local fovKick = 0 -- zusaetzliches Sichtfeld nach einem Boost (Grad), klingt ab
local shakeTime = 0

-- Freie Kamera (Grad) und Zoom (Faktor auf Distance)
local orbitYaw = 0
local orbitPitch = 0
local zoom = 1
local lastOrbitInput = -math.huge
local dragging = false
local stickX, stickY = 0, 0
local touchDrag: InputObject? = nil
local inputConnections: { RBXScriptConnection } = {}

local function orbitBy(dx: number, dy: number)
	local C = Config.Camera
	orbitYaw = (orbitYaw - dx + 180) % 360 - 180
	orbitPitch = math.clamp(orbitPitch + dy, C.OrbitPitchMin, C.OrbitPitchMax)
	lastOrbitInput = os.clock()
end

local function connectInput()
	for _, connection in inputConnections do
		connection:Disconnect()
	end
	inputConnections = {
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				dragging = true
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
			elseif input.UserInputType == Enum.UserInputType.Touch and not processed and not touchDrag then
				-- Wischen auf freiem Bildschirm (nicht auf Joystick/Knoepfen) dreht die Kamera
				if input.Position.X > workspace.CurrentCamera.ViewportSize.X * 0.4 then
					touchDrag = input
				end
			end
		end),
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				dragging = false
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			elseif input == touchDrag then
				touchDrag = nil
			elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
				stickX, stickY = 0, 0
			end
		end),
		UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
			local C = Config.Camera
			if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
				orbitBy(input.Delta.X * C.OrbitMouseSensitivity, input.Delta.Y * C.OrbitMouseSensitivity)
			elseif input == touchDrag then
				orbitBy(input.Delta.X * C.OrbitMouseSensitivity, input.Delta.Y * C.OrbitMouseSensitivity)
			elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
				zoom = math.clamp(zoom - input.Position.Z * C.ZoomStep, C.ZoomMin, C.ZoomMax)
			elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
				local x, y = input.Position.X, input.Position.Y
				stickX = if math.abs(x) > 0.15 then x else 0
				stickY = if math.abs(y) > 0.15 then y else 0
			end
		end),
	}
end

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

	-- Freie Kamera: Stick dreht laufend; ohne Eingabe weich zurueck hinter den Wagen
	if stickX ~= 0 or stickY ~= 0 then
		orbitBy(stickX * C.OrbitStickSpeed * dt, -stickY * C.OrbitStickSpeed * dt)
	end
	if not dragging and touchDrag == nil and os.clock() - lastOrbitInput > C.OrbitReturnDelay then
		local back = smoothing(C.OrbitReturnSpeed, dt)
		orbitYaw -= orbitYaw * back
		orbitPitch -= orbitPitch * back
	end

	local focus = part.Position + Vector3.new(0, C.LookHeight, 0)
	-- Grund-Versatz hinter/ueber dem Wagen, gedreht um die freie Kamera, mal Zoom
	local behind = -direction * C.Distance + Vector3.new(0, C.Height, 0)
	local right = direction:Cross(Vector3.yAxis)
	local rotation = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(orbitYaw))
		* CFrame.fromAxisAngle(
			if right.Magnitude > 0.01 then right.Unit else Vector3.xAxis,
			math.rad(-orbitPitch)
		)
	local desired = part.Position + rotation:VectorToWorldSpace(behind) * zoom
	local viewDirection = rotation:VectorToWorldSpace(direction)
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
	fovKick *= math.exp(-C.BoostFovDecay * dt)
	camera.FieldOfView = fov + fovKick

	-- Kamera-Wackeln: etwas bei hohem Tempo, mehr nach harten Landungen.
	-- math.noise liefert weiches Rauschen (kein hektisches Zufalls-Zittern).
	local speedShake = C.ShakeAtFullSpeed
		* math.clamp((speed - C.ShakeSpeedStart) / math.max(C.FovFullSpeed - C.ShakeSpeedStart, 1), 0, 1)
	landingShake *= math.exp(-C.ShakeDecay * dt)
	local shake = math.min(speedShake + landingShake, C.ShakeMaxAngle)
	if not Settings.get("CameraShake") then
		shake = 0 -- Einstellung "Kamera-Wackeln" aus
	end
	shakeTime += dt * C.ShakeFrequency
	local shakeRotation = CFrame.Angles(
		math.rad(math.noise(shakeTime, 0.3) * 2 * shake),
		math.rad(math.noise(shakeTime, 7.1) * 2 * shake),
		math.rad(math.noise(shakeTime, 13.7) * shake)
	)

	camera.CFrame = CFrame.lookAt(final, focus + viewDirection * C.LookAhead) * shakeRotation
end

-- Harte Landung: Kamera kurz wackeln lassen (Staerke in Grad).
function ChaseCamera.addShake(amount: number)
	landingShake = math.min(landingShake + amount, Config.Camera.ShakeMaxAngle)
end

-- Boost: Sichtfeld kurz weiter aufziehen (Schub spuerbar machen).
function ChaseCamera.kickFov(amount: number)
	fovKick = math.max(fovKick, amount)
end

-- Kamera an den Wagen haengen. `ignore`: Objekte, durch die die Kamera schauen darf.
function ChaseCamera.start(part: BasePart, ignore: { Instance })
	target = part
	rayParams.FilterDescendantsInstances = ignore
	ChaseCamera.snap()
	RunService:UnbindFromRenderStep(BIND_NAME)
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, update)
	connectInput()
end

-- Ohne Glaettung direkt hinter den Wagen springen (z. B. nach einem Neustart).
function ChaseCamera.snap()
	position = nil
	orbitYaw, orbitPitch = 0, 0
	landingShake = 0
	fovKick = 0
	local part = target
	if part then
		direction = flatLook(part) or direction
	end
end

function ChaseCamera.stop(humanoid: Humanoid?)
	target = nil
	for _, connection in inputConnections do
		connection:Disconnect()
	end
	inputConnections = {}
	if dragging then
		dragging = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	touchDrag = nil
	stickX, stickY = 0, 0
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
