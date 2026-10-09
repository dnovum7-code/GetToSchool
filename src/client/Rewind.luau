--!strict
-- Rueckspulen wie in Forza (fuer Streckentests). Waehrend der Fahrt nimmt ein Ringpuffer die
-- letzten Config.Rewind.Seconds Sekunden auf (Lage, Tempo, Drehung des Wagens). Taste halten
-- (Z, Gamepad Steuerkreuz runter, Touch "Zurueck") spult sichtbar zurueck, loslassen setzt die
-- Fahrt an dieser Stelle mit dem damaligen Tempo fort. Unten zeigt eine Zeitleiste, wie weit.
--
-- Was beim Rueckspulen passiert (der Server prueft und merkt es sich, server/Rewind):
--   Timer laeuft weiter, Leben kommen nicht zurueck, erreichte Checkpoints bleiben erreicht,
--   Meter zaehlen nicht, der Lauf zaehlt nicht fuer die Bestenliste, kein Geist.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CartController = require(script.Parent:WaitForChild("CartController"))

local reportRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ReportStat") :: RemoteEvent

local Rewind = {}

local ACTION = "GetToSchoolRewind"

type Sample = { cframe: CFrame, velocity: Vector3, angular: Vector3 }

local buffer: { Sample } = {} -- aelteste zuerst
local sinceSample = 0
local held = false
local active = false
local cursor = 0 -- Position im Puffer (Index mit Bruchteil) beim Rueckspulen

local gui: ScreenGui
local timeline: Frame
local fill: Frame
local label: TextLabel

function Rewind.allowed(): boolean
	return Config.Rewind.EnabledLive or (RunService:IsStudio() and Config.Debug.Rewind)
end

local function capacity(): number
	return math.max(2, math.floor(Config.Rewind.Seconds * Config.Rewind.SampleRate))
end

local function setActive(on: boolean)
	if active == on then
		return
	end
	active = on
	gui.Enabled = on
	reportRemote:FireServer("Rewind", on) -- Server: Meter pausieren, Lauf markieren
end

-- Puffer leeren (Neustart, Checkpoint, Crash, Aussteigen)
function Rewind.clear()
	table.clear(buffer)
	sinceSample = 0
	if active then
		setActive(false)
	end
end

function Rewind.activate()
	if not Rewind.allowed() then
		return
	end
	ContextActionService:BindAction(ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			held = true
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			held = false
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.Z, Enum.KeyCode.DPadDown)
	ContextActionService:SetTitle(ACTION, "Zurueck")
end

function Rewind.deactivate()
	ContextActionService:UnbindAction(ACTION)
	held = false
	Rewind.clear()
end

-- Waehrend der Fahrt (nicht beim Rueckspulen): Lage aufnehmen
function Rewind.record(dt: number, base: BasePart)
	if not Rewind.allowed() or active then
		return
	end
	sinceSample += dt
	if sinceSample < 1 / Config.Rewind.SampleRate then
		return
	end
	sinceSample = 0
	table.insert(buffer, {
		cframe = base.CFrame,
		velocity = base.AssemblyLinearVelocity,
		angular = base.AssemblyAngularVelocity,
	})
	while #buffer > capacity() do
		table.remove(buffer, 1)
	end
end

local function place(controller: CartController.Controller, cframe: CFrame)
	local cart = controller.cart
	local offset = controller.base.CFrame:Inverse() * cart:GetPivot()
	cart:PivotTo(cframe * offset)
	for _, part in cart:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	-- Schwerkraft aufheben, solange zurueckgespult wird
	controller.driveForce.Force = Vector3.new(0, workspace.Gravity * controller.mass, 0)
	controller.steerTorque.Torque = Vector3.zero
end

-- Jeden Physik-Frame vor der Fahrphysik. Gibt true zurueck, solange zurueckgespult wird
-- (dann keine Fahrphysik und keine Crash-Erkennung in diesem Frame).
function Rewind.step(dt: number, controller: CartController.Controller): boolean
	if not Rewind.allowed() then
		return false
	end
	if held and #buffer >= 2 then
		if not active then
			cursor = #buffer
			setActive(true)
		end
		cursor = math.max(1, cursor - dt * Config.Rewind.SampleRate * Config.Rewind.PlaybackSpeed)
		local index = math.floor(cursor)
		local alpha = cursor - index
		local a = buffer[index]
		local b = buffer[math.min(index + 1, #buffer)]
		place(controller, a.cframe:Lerp(b.cframe, alpha))
		local seconds = (#buffer - cursor) / Config.Rewind.SampleRate
		fill.Size = UDim2.fromScale(cursor / capacity(), 1)
		label.Text = `◀◀  Rueckspulen  -{string.format("%.1f", seconds)} s`
		return true
	end
	if active then
		-- Loslassen: ab hier weiterfahren, mit dem damaligen Tempo
		local index = math.clamp(math.floor(cursor + 0.5), 1, #buffer)
		local sample = buffer[index]
		for i = #buffer, index + 1, -1 do
			table.remove(buffer, i) -- die "Zukunft" verwerfen
		end
		if sample then
			place(controller, sample.cframe)
			for _, part in controller.cart:GetDescendants() do
				if part:IsA("BasePart") then
					part.AssemblyLinearVelocity = sample.velocity
				end
			end
			controller.base.AssemblyAngularVelocity = sample.angular
		end
		controller:settle()
		setActive(false)
	end
	return false
end

function Rewind.isActive(): boolean
	return active
end

function Rewind.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "Rewind"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = 6
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -96)
	label.Size = UDim2.fromOffset(360, 28)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.TextColor3 = Color3.fromRGB(140, 210, 255)
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
	timeline = Instance.new("Frame")
	timeline.AnchorPoint = Vector2.new(0.5, 1)
	timeline.Position = UDim2.new(0.5, 0, 1, -80)
	timeline.Size = UDim2.fromOffset(360, 10)
	timeline.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	timeline.BackgroundTransparency = 0.2
	timeline.BorderSizePixel = 0
	timeline.Parent = gui
	fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 170, 255)
	fill.BorderSizePixel = 0
	fill.Parent = timeline
end

return Rewind
