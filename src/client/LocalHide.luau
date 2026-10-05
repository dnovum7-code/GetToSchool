--!strict
-- Objekte nur auf diesem Client aus- und wieder einblenden (andere Spieler sehen sie weiter).
-- "Ausblenden" heisst: unsichtbar, keine Kollision, fuer Raycasts und Beruehrungs-Abfragen
-- unsichtbar (CanQuery), Partikel/Lichter aus.
--
-- Mehrere Gruende koennen dasselbe Objekt ausblenden (z. B. "Zufallsereignis" und
-- "eingesammelt"). Sichtbar ist es erst wieder, wenn kein Grund mehr uebrig ist.

local LocalHide = {}

-- Originalwerte, damit wir sie beim Wieder-Einblenden zuruecksetzen koennen
local originals: { [Instance]: { [string]: any } } = {}
local reasons: { [Instance]: { [string]: boolean } } = {}

-- Eigenschaften, die beim Ausblenden geaendert werden (pro Klasse)
local function hiddenValues(item: Instance): { [string]: any }?
	if item:IsA("BasePart") then
		return { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }
	elseif item:IsA("Decal") then -- Decal und Texture
		return { Transparency = 1 }
	elseif item:IsA("ParticleEmitter") or item:IsA("Light") or item:IsA("Beam") or item:IsA("Trail") then
		return { Enabled = false }
	elseif item:IsA("SurfaceGui") or item:IsA("BillboardGui") then
		return { Enabled = false }
	end
	return nil
end

local function setItemHidden(item: Instance, hidden: boolean)
	local values = hiddenValues(item)
	if not values then
		return
	end
	if not hidden then
		local saved = originals[item]
		if saved then
			for property, value in saved do
				(item :: any)[property] = value
			end
			originals[item] = nil
		end
	else
		if not originals[item] then
			local saved = {}
			for property in values do
				saved[property] = (item :: any)[property]
			end
			originals[item] = saved
		end
		for property, value in values do
			(item :: any)[property] = value
		end
	end
end

local function apply(instance: Instance)
	local set = reasons[instance]
	local hidden = set ~= nil and next(set) ~= nil
	setItemHidden(instance, hidden)
	for _, descendant in instance:GetDescendants() do
		setItemHidden(descendant, hidden)
	end
	if not hidden then
		reasons[instance] = nil
	end
end

-- `instance` aus Grund `reason` aus- (true) oder einblenden (false)
function LocalHide.set(instance: Instance, reason: string, hidden: boolean)
	local set = reasons[instance]
	if hidden then
		if not set then
			set = {}
			reasons[instance] = set
		end
		if set[reason] then
			return
		end
		set[reason] = true
	else
		if not set or not set[reason] then
			return
		end
		set[reason] = nil
	end
	apply(instance)
end

function LocalHide.isHidden(instance: Instance): boolean
	local set = reasons[instance]
	return set ~= nil and next(set) ~= nil
end

-- Originalwert einer Eigenschaft (falls ausgeblendet, der Wert von vorher)
function LocalHide.original(item: Instance, property: string): any
	local saved = originals[item]
	if saved and saved[property] ~= nil then
		return saved[property]
	end
	return (item :: any)[property]
end

return LocalHide
