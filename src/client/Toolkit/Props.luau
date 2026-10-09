--!strict
-- Prop (Tag "Prop", Part oder Modell): lose Gegenstaende, die der Wagen wegschiesst, ohne
-- selbst zu crashen. Jeder Spieler hat seine eigenen: Das Original wird bei dir
-- ausgeblendet und durch eine lose, leichte Kopie ersetzt (nur bei dir).
-- Beim ersten Treffer im Lauf gibt es einen kleinen Extra-Schubs und der Chaos-Zaehler
-- steigt (Ergebnis-Screen). T: alles zurueck an den Ursprung, Zaehler 0. R: bleibt liegen.
-- Physik-Tags LowGravity / NoFriction / KeepUpright am Prop wirken auf die lose Kopie.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ObjectPhysics = require(Shared:WaitForChild("ObjectPhysics"))
local TagList = require(Shared:WaitForChild("TagList"))
local LocalClone = require(script.Parent.Parent:WaitForChild("LocalClone"))
local LocalHide = require(script.Parent.Parent:WaitForChild("LocalHide"))
local Pieces = require(script.Parent:WaitForChild("Pieces"))
local ToolkitTypes = require(script.Parent:WaitForChild("ToolkitTypes"))

type Prop = {
	instance: PVInstance,
	template: PVInstance, -- unveraenderte Kopie (ohne Parent) fuer das Zuruecksetzen
	copy: PVInstance?, -- lose Kopie in der Welt
	hit: boolean, -- in diesem Lauf schon getroffen
	hidden: boolean, -- Original liegt in einem ausgeblendeten Zufallsereignis
}

local props: { [Instance]: Prop } = {}
local byCopy: { [Instance]: Prop } = {}
local chaos = 0
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include

local function spawnCopy(prop: Prop)
	local old = prop.copy
	if old then
		byCopy[old] = nil
		old:Destroy()
	end
	local copy = prop.template:Clone()
	LocalClone.weldTogether(copy) -- lose Kopie darf nicht zerfallen
	local density = Pieces.number(prop.instance, "Density", Config.Props.Density)
	for _, part in LocalClone.allParts(copy) do
		part.Anchored = false
		part.CanCollide = true
		part.CanQuery = true
		part.CanTouch = false
		local current = part.CurrentPhysicalProperties
		part.CustomPhysicalProperties = PhysicalProperties.new(
			math.clamp(density, 0.01, 100),
			current.Friction,
			current.Elasticity,
			current.FrictionWeight,
			current.ElasticityWeight
		)
	end
	-- Beruehrung mit dem Wagen ist kein harter Aufprall (siehe CartClient, "SoftHit")
	CollectionService:AddTag(copy, "SoftHit")
	copy.Parent = LocalClone.folder("LocalProps")
	prop.copy = copy
	prop.hit = false
	byCopy[copy] = prop
	-- Physik-Tags am Prop (LowGravity, NoFriction, KeepUpright), siehe shared/ObjectPhysics
	ObjectPhysics.apply(copy, ObjectPhysics.flags({ prop.instance }))
	if prop.hidden then
		LocalHide.set(copy, "Prop", true)
	end
end

local function register(instance: Instance)
	if props[instance] then
		return
	end
	local template = LocalClone.copy(instance)
	if not template then
		return
	end
	local prop: Prop =
		{ instance = instance :: PVInstance, template = template, copy = nil, hit = false, hidden = false }
	props[instance] = prop
	LocalHide.set(instance, "Prop", true) -- Original bei uns weg, die Kopie uebernimmt
	spawnCopy(prop)
end

local function hitProp(prop: Prop, base: BasePart)
	if prop.hit then
		return
	end
	prop.hit = true
	chaos += 1
	local copy = prop.copy
	if copy then
		local P = Config.Props
		local kick = base.AssemblyLinearVelocity * P.KickBoost + Vector3.new(0, P.KickUp, 0)
		local spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 8
		for _, part in LocalClone.allParts(copy) do
			part.AssemblyLinearVelocity = kick
			part.AssemblyAngularVelocity = spin
		end
	end
end

local Props = {}

function Props.getChaos(): number
	return chaos
end

local piece: ToolkitTypes.Piece = {
	init = function()
		TagList.watch("Prop", register)
	end,

	step = function(ctx)
		for instance, prop in props do
			if not instance:IsDescendantOf(workspace) then
				local copy = prop.copy
				if copy then
					byCopy[copy] = nil
					copy:Destroy()
				end
				prop.template:Destroy()
				props[instance] = nil
				continue
			end
			-- Original in einem ausgeblendeten Zufallsereignis? Dann die Kopie auch ausblenden
			local hidden = LocalHide.isHidden(instance, "Prop")
			if hidden ~= prop.hidden then
				prop.hidden = hidden
				local copy = prop.copy
				if copy then
					LocalHide.set(copy, "Prop", hidden)
				end
			end
		end
		local cart, base = ctx.cart, ctx.base
		if not cart or not base then
			return
		end
		-- Trifft der Wagen eine Prop-Kopie?
		local include = {}
		for copy, prop in byCopy do
			if not prop.hit and not prop.hidden then
				table.insert(include, copy)
			end
		end
		if #include == 0 then
			return
		end
		overlapParams.FilterDescendantsInstances = include
		local cframe, size = cart:GetBoundingBox()
		for _, part in workspace:GetPartBoundsInBox(cframe, size + Vector3.one * 0.6, overlapParams) do
			local current: Instance? = part
			while current and current ~= workspace do
				local prop = byCopy[current]
				if prop then
					hitProp(prop, base)
					break
				end
				current = current.Parent
			end
		end
	end,

	-- T: alles zurueck, Chaos 0. R: Props bleiben, wo sie sind.
	reset = function(kind)
		if kind ~= "Full" then
			return
		end
		chaos = 0
		for _, prop in props do
			spawnCopy(prop)
		end
	end,
}

Props.init = piece.init
Props.step = piece.step
Props.reset = piece.reset

return Props
