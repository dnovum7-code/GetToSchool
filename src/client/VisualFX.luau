--!strict
-- Visuelle Extras (nur Optik, nur beim eigenen Spieler):
--   * Speed-Linien am Bildrand bei hohem Tempo
--   * Staubwolke bei harten Landungen
--   * Flammen hinten am Wagen waehrend eines Boosts
--   * Konfetti im Ziel (neue Bestzeit: mehr)
-- Werte: Config.Effects. Abschaltbar in den Einstellungen ("Extra-Effekte").
-- Alles mit eingebauten Mitteln (Frames, ParticleEmitter), keine Toolbox-Assets.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CartController = require(script.Parent:WaitForChild("CartController"))
local Settings = require(script.Parent:WaitForChild("Settings"))

local VisualFX = {}

type Line = { frame: Frame, angle: number, radius: number, speed: number }

local gui: ScreenGui
local lines: { Line } = {}
local dust: ParticleEmitter? = nil
local flame: ParticleEmitter? = nil
local attachments: { Attachment } = {}

local CONFETTI_COLORS = {
	Color3.fromRGB(255, 80, 80),
	Color3.fromRGB(255, 210, 60),
	Color3.fromRGB(80, 200, 120),
	Color3.fromRGB(80, 160, 255),
	Color3.fromRGB(230, 110, 230),
}

local function enabled(): boolean
	return Settings.get("VisualEffects") == true
end

-- Speed-Linie neu setzen: zufaelliger Winkel, startet etwas innerhalb des Bildrands
local function respawn(line: Line)
	line.angle = math.random() * math.pi * 2
	line.radius = 0.35 + math.random() * 0.2
	line.speed = 0.9 + math.random() * 0.8
	line.frame.Rotation = math.deg(line.angle) + 90
end

-- Wagen bekommt Staub- und Flammen-Emitter (beim Einsteigen)
function VisualFX.attach(cart: Model)
	VisualFX.detach()
	local base = cart:FindFirstChild("Base")
	if not base or not base:IsA("BasePart") then
		return
	end
	local size = base.Size
	local bottom = Instance.new("Attachment")
	bottom.Name = "FxDust"
	bottom.Position = Vector3.new(0, -size.Y / 2 - 1, 0)
	bottom.Parent = base
	local back = Instance.new("Attachment")
	back.Name = "FxFlame"
	back.Position = Vector3.new(0, 0.3, size.Z / 2 + 0.3)
	back.Parent = base
	attachments = { bottom, back }

	local dustEmitter = Instance.new("ParticleEmitter")
	dustEmitter.Name = "LandingDust"
	dustEmitter.Enabled = false
	dustEmitter.Color = ColorSequence.new(Color3.fromRGB(200, 180, 150))
	dustEmitter.Transparency = NumberSequence.new(0.3, 1)
	dustEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 4),
	})
	dustEmitter.Lifetime = NumberRange.new(0.6, 1.2)
	dustEmitter.Speed = NumberRange.new(8, 18)
	dustEmitter.SpreadAngle = Vector2.new(80, 10)
	dustEmitter.EmissionDirection = Enum.NormalId.Top
	dustEmitter.Drag = 3
	dustEmitter.Acceleration = Vector3.new(0, 4, 0)
	dustEmitter.Parent = bottom
	dust = dustEmitter

	local flameEmitter = Instance.new("ParticleEmitter")
	flameEmitter.Name = "BoostFlame"
	flameEmitter.Enabled = false
	flameEmitter.Rate = Config.Effects.BoostFlameRate
	flameEmitter.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 80, 20))
	flameEmitter.LightEmission = 1
	flameEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	flameEmitter.Lifetime = NumberRange.new(0.15, 0.3)
	flameEmitter.Speed = NumberRange.new(10, 18)
	flameEmitter.SpreadAngle = Vector2.new(15, 15)
	flameEmitter.EmissionDirection = Enum.NormalId.Back
	flameEmitter.Parent = back
	flame = flameEmitter
end

function VisualFX.detach()
	for _, attachment in attachments do
		attachment:Destroy()
	end
	attachments = {}
	dust = nil
	flame = nil
	for _, line in lines do
		line.frame.Visible = false
	end
end

-- Jeden Frame waehrend der Fahrt
function VisualFX.update(dt: number, telemetry: CartController.Telemetry)
	local E = Config.Effects
	local on = enabled()
	local current = flame
	if current then
		current.Enabled = on and telemetry.boosting
	end
	local intensity = if on
		then math.clamp(
			(telemetry.speed - E.SpeedLinesStart) / math.max(E.SpeedLinesFull - E.SpeedLinesStart, 1),
			0,
			1
		)
		else 0
	for _, line in lines do
		if intensity <= 0 then
			line.frame.Visible = false
			continue
		end
		line.radius += line.speed * dt * (0.6 + intensity)
		if line.radius > 0.85 then
			respawn(line)
		end
		local frame = line.frame
		frame.Visible = true
		frame.Position = UDim2.fromScale(
			0.5 + math.cos(line.angle) * line.radius,
			0.5 + math.sin(line.angle) * line.radius
		)
		frame.Size = UDim2.new(0, 2, 0.06 + 0.12 * intensity, 0)
		frame.BackgroundTransparency = 1 - (1 - E.SpeedLineTransparency) * intensity
	end
end

-- Harte Landung: Staub (Staerke nach Fallgeschwindigkeit)
function VisualFX.landing(fallSpeed: number)
	local E = Config.Effects
	local emitter = dust
	if not emitter or not enabled() or fallSpeed < E.DustMinFallSpeed then
		return
	end
	emitter:Emit(math.clamp(math.floor(fallSpeed * E.DustPerSpeed), 5, 80))
end

-- Konfetti von oben ueber den Bildschirm
function VisualFX.confetti(big: boolean)
	if not enabled() then
		return
	end
	local E = Config.Effects
	local count = if big then E.ConfettiCount * 2 else E.ConfettiCount
	for _ = 1, count do
		local piece = Instance.new("Frame")
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Size = UDim2.fromOffset(math.random(6, 12), math.random(10, 18))
		piece.Position = UDim2.new(math.random(), 0, -0.05 - math.random() * 0.3, 0)
		piece.BackgroundColor3 = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)]
		piece.BorderSizePixel = 0
		piece.Rotation = math.random(0, 360)
		piece.Parent = gui
		local time = E.ConfettiTime * (0.7 + math.random() * 0.6)
		local tween =
			TweenService:Create(piece, TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				Position = UDim2.new(piece.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1.1, 0),
				Rotation = piece.Rotation + math.random(-540, 540),
				BackgroundTransparency = 0.3,
			})
		tween.Completed:Once(function()
			piece:Destroy()
		end)
		tween:Play()
	end
end

function VisualFX.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "VisualFX"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2 -- unter der normalen Anzeige
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _ = 1, Config.Effects.SpeedLineCount do
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BackgroundColor3 = Color3.new(1, 1, 1)
		frame.BorderSizePixel = 0
		frame.Visible = false
		frame.Parent = gui
		local line: Line = { frame = frame, angle = 0, radius = 0, speed = 1 }
		respawn(line)
		line.radius = 0.35 + math.random() * 0.5
		table.insert(lines, line)
	end
end

return VisualFX
