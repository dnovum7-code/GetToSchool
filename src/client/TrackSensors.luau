--!strict
-- Erkennt, auf bzw. an welchen Streckenbausteinen der eigene Wagen gerade ist.
--   Boden (BoostPad, JumpPad, Mud, Ice): je ein kleiner Kasten an der Aufstandsflaeche
--   jedes der 4 Raeder. (Frueher ein Raycast: Der meldet nur das erste Part, das er trifft.
--   Liegt ein Pad buendig in der Strasse, traf er die Strasse und das Pad blieb unerkannt.)
--   Hazard, Bouncy: raeumliche Abfrage um den Wagen herum (auch Waende, nicht nur Boden).
-- Unity-Vergleich: Physics.OverlapBox pro Rad und um den Wagen.
-- Bewusst nicht ueber Touched-Events: die sind bei schnellen Objekten unzuverlaessig.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Vehicles = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Vehicles"))
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
local FLOOR_TAGS = { "BoostPad", "JumpPad", "Mud", "Ice" }

-- Debug-Ausgaben (nur in Studio, an/aus: Config.Debug.TrackPieces)
function TrackSensors.debugLog(message: string)
	if Config.Debug.TrackPieces and RunService:IsStudio() then
		print("[Baustein-Debug] " .. message)
	end
end

-- Falscher Typ -> Standardwert und Warnung im Output (siehe shared/Attributes)
local function numberAttribute(instance: Instance, name: string, default: number): number
	return Attributes.number(instance, name, default)
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

local floorParams = OverlapParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include
local lastWheelReport: { [string]: string } = {} -- fuer Debug: nur Aenderungen melden
local lastPieceCounts = ""

-- Was liegt unter den Raedern?
function TrackSensors.sampleGround(cart: Model): Surface
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

	-- Nur getaggte Bodenbausteine pruefen (Strasse usw. werden ignoriert)
	local include = {}
	local counts = {}
	for _, tag in FLOOR_TAGS do
		local tagged = TagList.get(tag)
		table.insert(counts, `{tag} {#tagged}`)
		for _, instance in tagged do
			table.insert(include, instance)
		end
	end
	local countText = table.concat(counts, ", ")
	if countText ~= lastPieceCounts then
		lastPieceCounts = countText
		TrackSensors.debugLog("Bodenbausteine in der Welt: " .. countText)
	end
	if #include == 0 then
		return surface
	end
	floorParams.FilterDescendantsInstances = include

	-- Kasten an der Aufstandsflaeche jedes Rads: etwas darueber und darunter, damit
	-- aufliegende, buendige und leicht eingelassene Bausteine erkannt werden.
	local cf = base.CFrame
	local up = cf.UpVector
	local radius = Vehicles.forCart(cart).Cart.WheelDiameter / 2
	local above, below = T.FloorSensorAbove, T.FloorSensorBelow
	local size = Vector3.new(radius * 1.5, above + below, radius * 1.5)
	local count = 0
	local mud, ice = 0, 0
	for _, name in WHEEL_NAMES do
		local wheel = cart:FindFirstChild(name) :: BasePart?
		if not wheel then
			continue
		end
		count += 1
		local contact = wheel.Position - up * radius
		local boxCFrame = CFrame.fromMatrix(contact + up * ((above - below) / 2), cf.RightVector, up)
		local found: { [string]: Instance } = {}
		for _, part in workspace:GetPartBoundsInBox(boxCFrame, size, floorParams) do
			for _, tag in FLOOR_TAGS do
				if not found[tag] then
					local piece = findTagged(part, tag)
					if piece then
						found[tag] = piece
					end
				end
			end
		end
		local mudPiece = found.Mud
		if mudPiece then
			mud += 1
			surface.mudDrag = numberAttribute(mudPiece, "Drag", T.MudDrag)
		end
		local icePiece = found.Ice
		if icePiece then
			ice += 1
			surface.iceGrip = numberAttribute(icePiece, "Grip", T.IceGrip)
		end
		surface.boostPad = surface.boostPad or found.BoostPad
		surface.jumpPad = surface.jumpPad or found.JumpPad

		-- Debug: melden, wenn sich aendert, was dieses Rad erkennt
		if Config.Debug.TrackPieces then
			local names = {}
			for _, tag in FLOOR_TAGS do
				local piece = found[tag]
				if piece then
					table.insert(names, `{tag} "{piece.Name}"`)
				end
			end
			local report = if #names > 0 then table.concat(names, ", ") else "nichts"
			if lastWheelReport[name] ~= report then
				lastWheelReport[name] = report
				TrackSensors.debugLog(`Rad {name} erkennt: {report}`)
			end
		end
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
-- `skip`: Objekte, die nicht zaehlen sollen (z. B. ein Spawner mit Tag "Launchable").
function TrackSensors.touching(cart: Model, tag: string, skip: ((Instance) -> boolean)?): Instance?
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
		if piece and not (skip and skip(piece)) then
			return piece
		end
	end
	return nil
end

return TrackSensors
