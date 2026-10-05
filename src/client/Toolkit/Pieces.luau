--!strict
-- Kleine Helfer fuer alle Baukasten-Bausteine: Attribute lesen (mit Standardwert aus der
-- Config und Warnung bei falschem Typ), Seed fuer reproduzierbaren Zufall, Lage pruefen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local Rng = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Toolkit"):WaitForChild("Rng"))

local Pieces = {}

local warned: { [Instance]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any

local function warnOnce(instance: Instance, name: string, message: string)
	local set = warned[instance]
	if not set then
		set = {}
		warned[instance] = set
	end
	if not set[name] then
		set[name] = true
		warn(`[Baukasten] {instance:GetFullName()}: {message}`)
	end
end

function Pieces.number(instance: Instance, name: string, default: number): number
	return Attributes.number(instance, name, default)
end

function Pieces.bool(instance: Instance, name: string, default: boolean): boolean
	local value = instance:GetAttribute(name)
	if type(value) == "boolean" then
		return value
	elseif value ~= nil then
		warnOnce(
			instance,
			name,
			`Attribut "{name}" muss true/false sein, Standardwert {default} wird benutzt.`
		)
	end
	return default
end

function Pieces.string(instance: Instance, name: string, default: string?): string?
	local value = instance:GetAttribute(name)
	if type(value) == "string" then
		return if value ~= "" then value else default
	elseif value ~= nil then
		warnOnce(instance, name, `Attribut "{name}" muss Text sein, Standardwert wird benutzt.`)
	end
	return default
end

function Pieces.vector(instance: Instance, name: string, default: Vector3): Vector3
	local value = instance:GetAttribute(name)
	if typeof(value) == "Vector3" then
		return value
	elseif value ~= nil then
		warnOnce(instance, name, `Attribut "{name}" muss ein Vector3 sein, Standardwert wird benutzt.`)
	end
	return default
end

-- Zahlenbereich: Attribut als NumberRange (z. B. 0.8 - 1.3) oder als Zahl x (= 1-x .. 1+x)
function Pieces.range(
	instance: Instance,
	name: string,
	defaultMin: number,
	defaultMax: number
): (number, number)
	local value = instance:GetAttribute(name)
	if typeof(value) == "NumberRange" then
		return value.Min, value.Max
	elseif type(value) == "number" then
		return math.max(0, 1 - value), 1 + value
	elseif value ~= nil then
		warnOnce(instance, name, `Attribut "{name}" muss ein NumberRange oder eine Zahl sein.`)
	end
	return defaultMin, defaultMax
end

-- Seed fuer reproduzierbaren Zufall: Nummer vom Server (Attribut "PieceId"), sonst der Pfad
function Pieces.seed(instance: Instance): number
	local id = instance:GetAttribute("PieceId")
	if type(id) == "string" then
		return Rng.seedFromString(id)
	end
	return Rng.seedFromString(instance:GetFullName())
end

-- Liegt `position` in der Box des Parts (plus `margin` Studs ringsum)?
function Pieces.inBox(part: BasePart, position: Vector3, margin: number): boolean
	local localPos = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2 + Vector3.one * margin
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

function Pieces.getCFrame(instance: PVInstance): CFrame
	if instance:IsA("BasePart") then
		return instance.CFrame
	end
	return instance:GetPivot()
end

function Pieces.setCFrame(instance: PVInstance, cframe: CFrame)
	if instance:IsA("BasePart") then
		instance.CFrame = cframe
	elseif instance:IsA("Model") then
		instance:PivotTo(cframe)
	end
end

return Pieces
