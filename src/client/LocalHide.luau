--!strict
-- Objekte nur auf diesem Client aus- und wieder einblenden (andere Spieler sehen sie weiter).
-- "Ausblenden" heisst: unsichtbar, keine Kollision, fuer Raycasts und Beruehrungs-Abfragen
-- unsichtbar (CanQuery), Partikel/Lichter aus.
--
-- Mehrere Gruende koennen dasselbe Objekt ausblenden (z. B. "Zufallsereignis" und
-- "eingesammelt"). Sichtbar ist es erst wieder, wenn kein Grund mehr uebrig ist - weder am
-- Objekt selbst noch an einem Objekt darueber (z. B. Muenze in einem ausgeblendeten
-- Zufallsereignis bleibt unsichtbar, auch wenn sie bei T "wieder erscheint").

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

local function hasReasons(instance: Instance): boolean
	local set = reasons[instance]
	return set ~= nil and next(set) ~= nil
end

-- Ist das Objekt selbst oder eines darueber ausgeblendet?
local function hiddenInTree(item: Instance): boolean
	local current: Instance? = item
	while current and current ~= workspace and current ~= game do
		if hasReasons(current) then
			return true
		end
		current = current.Parent
	end
	return false
end

local function apply(instance: Instance)
	if not hasReasons(instance) then
		reasons[instance] = nil
	end
	setItemHidden(instance, hiddenInTree(instance))
	for _, descendant in instance:GetDescendants() do
		setItemHidden(descendant, hiddenInTree(descendant))
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

-- Ist das Objekt (oder eines darueber) gerade bei diesem Spieler ausgeblendet?
-- `ignoreReason`: dieser Grund am Objekt selbst zaehlt nicht (z. B. "Prop": das Original
-- ist immer ausgeblendet, interessant ist nur, ob ein Zufallsereignis darueber aus ist).
function LocalHide.isHidden(instance: Instance, ignoreReason: string?): boolean
	if ignoreReason then
		local set = reasons[instance]
		if set then
			for reason in set do
				if reason ~= ignoreReason then
					return true
				end
			end
		end
		local parent = instance.Parent
		return parent ~= nil and hiddenInTree(parent)
	end
	return hiddenInTree(instance)
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
