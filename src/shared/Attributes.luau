--!strict
-- Attribute von Bausteinen sicher lesen: Fehlt ein Attribut oder hat es den falschen Typ
-- (z. B. Text "40" statt Zahl 40), gilt der Standardwert aus der Config. Dann steht einmal
-- pro Objekt und Attribut eine Warnung im Output, damit Tippfehler auffallen.

local Attributes = {}

local warned: { [Instance]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any

local function warnOnce(instance: Instance, name: string, message: string)
	local perInstance = warned[instance]
	if not perInstance then
		perInstance = {}
		warned[instance] = perInstance
	end
	if not perInstance[name] then
		perInstance[name] = true
		warn(`[Baukasten] {instance:GetFullName()}: {message}`)
	end
end

-- Zahl-Attribut lesen. `warnIfMissing`: auch warnen, wenn das Attribut ganz fehlt.
function Attributes.number(instance: Instance, name: string, default: number, warnIfMissing: boolean?): number
	local value = instance:GetAttribute(name)
	if type(value) == "number" and value == value then -- value == value: kein NaN
		return value
	end
	if value == nil then
		if warnIfMissing then
			warnOnce(instance, name, `Attribut "{name}" fehlt, Standardwert {default} wird benutzt.`)
		end
	else
		warnOnce(
			instance,
			name,
			`Attribut "{name}" muss eine Zahl sein (ist {typeof(value)}: {tostring(value)}), Standardwert {default} wird benutzt.`
		)
	end
	return default
end

return Attributes
