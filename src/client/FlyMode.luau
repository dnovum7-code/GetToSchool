--!strict
-- Flugmodus (nur Studio, Schalter "Flugmodus" im F2-Panel unter Cheats / Test): fliegen
-- wie in Minecraft (Kreativmodus) zum Erkunden der Map.
--   W / S           vor / zurueck (in Blickrichtung des Wagens)
--   A / D           drehen
--   Leertaste       steigen   (Gamepad A, Touch "Hopp")
--   Shift           sinken    (Gamepad B, Touch "Normal")
-- Keine Schwerkraft, kein Crash; der Wagen bleibt waagerecht. Kollision bleibt an.
-- Werte: Config.FlyMode (Regler im Panel).

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
local CartController = require(script.Parent:WaitForChild("CartController"))

local FlyMode = {}

local flying = false
local yaw = 0

local function setVelocity(cart: Model, velocity: Vector3)
	for _, part in cart:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = velocity
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

-- Jeden Physik-Frame vor der Fahrphysik. true = es wird geflogen (dann keine Fahrphysik).
function FlyMode.step(
	dt: number,
	controller: CartController.Controller,
	throttle: number,
	steer: number,
	up: boolean,
	down: boolean
): boolean
	if not Config.Debug.FlyMode then
		if flying then
			flying = false
			controller:settle() -- normal weiterfahren (Schwerkraft wieder an)
		end
		return false
	end
	local F = Config.FlyMode
	local base = controller.base
	if not flying then
		flying = true
		local look = base.CFrame.LookVector
		yaw = math.atan2(-look.X, -look.Z)
	end
	yaw -= steer * F.TurnSpeed * dt
	local rotation = CFrame.Angles(0, yaw, 0)
	local forward = rotation.LookVector
	local vertical = (if up then 1 else 0) - (if down then 1 else 0)
	local target = forward * throttle * F.Speed + Vector3.yAxis * vertical * F.VerticalSpeed
	local alpha = 1 - math.exp(-math.max(F.Responsiveness, 0.1) * dt)
	local velocity = base.AssemblyLinearVelocity:Lerp(target, alpha)

	-- Waagerecht in Flugrichtung ausrichten (weich), Tempo setzen, Schwerkraft aufheben
	local cart = controller.cart
	local offset = base.CFrame:Inverse() * cart:GetPivot()
	local goal = CFrame.new(base.Position) * rotation
	cart:PivotTo(base.CFrame:Lerp(goal, alpha) * offset)
	setVelocity(cart, velocity)
	controller.driveForce.Force = Vector3.new(0, workspace.Gravity * controller.mass, 0)
	controller.steerTorque.Torque = Vector3.zero
	return true
end

function FlyMode.isFlying(): boolean
	return flying
end

return FlyMode
