--!strict
-- Erkennt, auf bzw. an welchen Streckenbausteinen der eigene Wagen gerade ist.
--   Boden (BoostPad, JumpPad, Mud, Ice): je ein Raycast unter jedem der 4 Raeder.
--   Hazard, Bouncy: raeumliche Abfrage um den Wagen herum (auch Waende, nicht nur Boden).
-- Unity-Vergleich: Physics.Raycast pro Rad und Physics.OverlapBox um den Wagen.
-- Bewusst nicht ueber Touched-Events: die sind bei schnellen Objekten unzuverlaessig.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local TagList = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TagList"))

local TrackSensors = {}

export type Surface = {
	mudFraction: number, -- Anteil der Raeder auf Schlamm (0..1)
	mudDrag: number,
	iceFraction: number, -- Anteil der Raeder auf Eis (0..1)
	iceGrip: number,
	boostPad: Instance?, -- Pad (Part oder Modell) unter einem Rad, sonst nil
	jumpPad: Instance?,
}

local WHEEL_NAMES = { "WheelFL", "WheelFR", "WheelBL", "WheelBR" }

local function numberAttribute(instance: Instance, name: string, default: number): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else default
end

-- Hat das getroffene Part (oder ein Modell darueber) den Tag? Liefert das getaggte Objekt.
local function findTagged(part: Instance, tag: string): Instance?
	local current: Instance? = part
	while current and current ~= workspace do
		if current:HasTag(tag) then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Was liegt unter den Raedern?
function TrackSensors.sampleGround(cart: Model, rayParams: RaycastParams): Surface
	local T = Config.Track
	local surface: Surface = {
		mudFraction = 0,
		mudDrag = T.MudDrag,
		iceFraction = 0,
		iceGrip = T.IceGrip,
		boostPad = nil,
		jumpPad = nil,
	}
	local base = cart:FindFirstChild("Base") :: BasePart?
	if not base then
		return surface
	end
	local down = -base.CFrame.UpVector * (Config.Cart.WheelDiameter / 2 + 0.6)
	local count = 0
	local mud, ice = 0, 0
	for _, name in WHEEL_NAMES do
		local wheel = cart:FindFirstChild(name) :: BasePart?
		if not wheel then
			continue
		end
		count += 1
		local hit = workspace:Raycast(wheel.Position, down, rayParams)
		if not hit then
			continue
		end
		local part = hit.Instance
		local mudPiece = findTagged(part, "Mud")
		if mudPiece then
			mud += 1
			surface.mudDrag = numberAttribute(mudPiece, "Drag", T.MudDrag)
		end
		local icePiece = findTagged(part, "Ice")
		if icePiece then
			ice += 1
			surface.iceGrip = numberAttribute(icePiece, "Grip", T.IceGrip)
		end
		surface.boostPad = surface.boostPad or findTagged(part, "BoostPad")
		surface.jumpPad = surface.jumpPad or findTagged(part, "JumpPad")
	end
	if count > 0 then
		surface.mudFraction = mud / count
		surface.iceFraction = ice / count
	end
	return surface
end

-- Lage eines Bausteins (Part: seine CFrame, Modell: sein Pivot)
function TrackSensors.pieceCFrame(piece: Instance): CFrame
	if piece:IsA("BasePart") then
		return piece.CFrame
	elseif piece:IsA("Model") then
		return piece:GetPivot()
	end
	return CFrame.identity
end

function TrackSensors.numberAttribute(instance: Instance, name: string, default: number): number
	return numberAttribute(instance, name, default)
end

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include

-- Beruehrt der Wagen gerade ein Objekt mit diesem Tag? Liefert das getaggte Objekt.
function TrackSensors.touching(cart: Model, tag: string): Instance?
	local tagged = TagList.get(tag)
	if #tagged == 0 then
		return nil
	end
	overlapParams.FilterDescendantsInstances = tagged
	local cframe, size = cart:GetBoundingBox()
	local padding = Vector3.one * Config.Track.SensorPadding * 2
	local parts = workspace:GetPartBoundsInBox(cframe, size + padding, overlapParams)
	for _, part in parts do
		local piece = findTagged(part, tag)
		if piece then
			return piece
		end
	end
	return nil
end

return TrackSensors
