--!strict
-- Lufttricks, Client-Seite: In der Luft dreht Q/E (Gamepad LB, Touch "Trick") den Wagen um
-- die Hochachse. Bei der Landung wird bewertet (Progression/TrickMath):
--   sauber  -> grosse Anzeige "360° SAUBER! +6", Meldung an den Server (Muenzen)
--   wackelig -> "wackelig ...", nichts passiert
--   schief  -> Crash "Schief gelandet!" (kostet ein Leben, Helm rettet)
-- Am Boden bleibt E "Aussteigen": die Trick-Taste gibt die Eingabe dann weiter.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local TrickMath =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"):WaitForChild("TrickMath"))
local CartController = require(script.Parent:WaitForChild("CartController"))
local SoundSystem = require(script.Parent:WaitForChild("SoundSystem"))

local reportRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ReportStat") :: RemoteEvent

local Tricks = {}

local ACTION = "GetToSchoolTrick"

local held = { left = false, right = false, auto = 0 } -- auto: Richtung von LB/Touch (-1/1)
local airTime = 0
local totalYaw = 0 -- Grad seit dem Abheben
local usedTrick = false
local wasAirborne = false
local steerSource: () -> number = function()
	return 0
end
local label: TextLabel? = nil
local labelScale: UIScale? = nil
local labelToken = 0

-- In der Luft gehoeren Q/E der Trick-Taste (auch kurz nach dem Abheben, damit E dann nicht
-- aussteigen laesst); die Drehung selbst beginnt erst nach MinAirTime (siehe step).
local function canTrick(): boolean
	return Config.Tricks.Enabled and wasAirborne
end

local function showText(text: string, color: Color3)
	local l, scale = label, labelScale
	if not l or not scale then
		return
	end
	labelToken += 1
	local token = labelToken
	l.Text = text
	l.TextColor3 = color
	l.Visible = true
	scale.Scale = 0.4
	TweenService
		:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	task.delay(1.6, function()
		if labelToken == token then
			l.Visible = false
		end
	end)
end

local function reset()
	airTime = 0
	totalYaw = 0
	usedTrick = false
	wasAirborne = false
end

local function spinInput(): number
	local value = (if held.right then 1 else 0) - (if held.left then 1 else 0)
	if value == 0 then
		value = held.auto
	end
	return value
end

-- Bindet die Trick-Taste (beim Einsteigen). `getSteer`: aktuelle Lenkung (fuer LB/Touch).
function Tricks.activate(getSteer: () -> number)
	steerSource = getSteer
	ContextActionService:BindActionAtPriority(
		ACTION,
		function(_, inputState, input)
			local pressed = inputState == Enum.UserInputState.Begin
			local released = inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel
			local key = input.KeyCode
			if released then
				if key == Enum.KeyCode.Q then
					held.left = false
				elseif key == Enum.KeyCode.E then
					held.right = false
				else
					held.auto = 0
				end
				return Enum.ContextActionResult.Pass
			end
			if not pressed or not canTrick() then
				return Enum.ContextActionResult.Pass -- am Boden: E = Aussteigen usw.
			end
			if key == Enum.KeyCode.Q then
				held.left = true
			elseif key == Enum.KeyCode.E then
				held.right = true
			else
				held.auto = if steerSource() < 0 then -1 else 1 -- LB / Touch: in Lenkrichtung
			end
			return Enum.ContextActionResult.Sink
		end,
		true,
		Enum.ContextActionPriority.High.Value + 10,
		Enum.KeyCode.Q,
		Enum.KeyCode.E,
		Enum.KeyCode.ButtonL1
	)
	ContextActionService:SetTitle(ACTION, "Trick")
end

function Tricks.deactivate()
	ContextActionService:UnbindAction(ACTION)
	held.left, held.right, held.auto = false, false, 0
	reset()
end

-- Jeden Physik-Frame nach der Fahrphysik. Gibt "Crash" zurueck, wenn schief gelandet.
function Tricks.step(
	dt: number,
	controller: CartController.Controller,
	telemetry: CartController.Telemetry,
	running: boolean
): string?
	local T = Config.Tricks
	if not T.Enabled then
		return nil
	end
	local base = controller.base
	local up = base.CFrame.UpVector
	local yawRate = base.AssemblyAngularVelocity:Dot(up)

	if not telemetry.grounded then
		wasAirborne = true
		airTime += dt
		totalYaw += math.deg(yawRate) * dt
		if airTime >= T.MinAirTime then
			local input = spinInput()
			local target: number? = nil
			if input ~= 0 then
				usedTrick = true
				target = -input * T.SpinSpeed -- positive Drehung um Y = links, daher das Minus
			elseif usedTrick then
				target = yawRate * math.exp(-T.StopDamping * dt) -- auslaufen lassen
			end
			if target then
				local torque = controller.steerTorque.Torque
				controller.steerTorque.Torque = torque
					+ up * (target - yawRate) * T.SpinResponse * controller.inertia
			end
		end
		return nil
	end

	-- gelandet
	if not wasAirborne then
		return nil
	end
	held.left, held.right, held.auto = false, false, 0 -- naechster Trick: neu druecken
	local didTrick = usedTrick
	local spun = totalYaw
	reset()
	if not didTrick then
		return nil
	end
	local velocity = base.AssemblyLinearVelocity
	local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local look = Vector3.new(base.CFrame.LookVector.X, 0, base.CFrame.LookVector.Z)
	local angle = 0
	if flatVelocity.Magnitude >= T.SlowLandingSpeed and look.Magnitude > 0.1 then
		angle = math.deg(math.acos(math.clamp(look.Unit:Dot(flatVelocity.Unit), -1, 1)))
	end
	local result = TrickMath.evaluate(spun, angle, T :: any)
	if result.kind == "Clean" then
		local name = TrickMath.label(result.halfSpins)
		showText(
			if result.coins > 0 then `{name} SAUBER! +{result.coins}` else `{name} SAUBER!`,
			Color3.fromRGB(255, 215, 60)
		)
		SoundSystem.play("Trick")
		if running and result.halfSpins > 0 then
			reportRemote:FireServer("Trick", result.halfSpins)
		end
		-- Landehilfe: genau in (oder gegen) die Fahrtrichtung drehen
		if T.LandingAssist and flatVelocity.Magnitude >= T.SlowLandingSpeed then
			local backwards = angle > 90
			local direction = if backwards then -flatVelocity.Unit else flatVelocity.Unit
			-- Neigung (Hang) behalten, nur die Blickrichtung drehen
			local facing = direction - up * direction:Dot(up)
			if facing.Magnitude > 0.1 then
				facing = facing.Unit
				local cart = controller.cart
				local offset = base.CFrame:Inverse() * cart:GetPivot()
				local target = CFrame.fromMatrix(base.Position, facing:Cross(up), up)
				cart:PivotTo(target * offset)
				base.AssemblyAngularVelocity = Vector3.zero
			end
		end
		return nil
	elseif result.kind == "Wobbly" then
		showText(`{TrickMath.label(result.halfSpins)} ... wackelig!`, Color3.fromRGB(255, 160, 80))
		return nil
	elseif result.kind == "Crash" then
		showText("SCHIEF GELANDET!", Color3.fromRGB(255, 90, 90))
		return "Crash"
	end
	return nil
end

-- Crash, Neustart, Aussteigen: laufenden Trick vergessen
function Tricks.cancel()
	reset()
end

function Tricks.init()
	local screen = Instance.new("ScreenGui")
	screen.Name = "Tricks"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 6
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local text = Instance.new("TextLabel")
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.3)
	text.Size = UDim2.fromOffset(600, 70)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.LuckiestGuy
	text.TextScaled = true
	text.TextStrokeTransparency = 0
	text.TextStrokeColor3 = Color3.fromRGB(40, 20, 0)
	text.Visible = false
	text.Parent = screen
	local scale = Instance.new("UIScale")
	scale.Parent = text
	label, labelScale = text, scale
end

return Tricks
