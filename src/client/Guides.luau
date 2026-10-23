--!strict
-- Barrieren, NoDamage und Stabil-Zone (laeuft jeden Frame nach der Fahrphysik, nur beim
-- eigenen Wagen; Rechnung: shared/Toolkit/GuideMath):
--   * NoDamage (Tag, Part/Model): Beruehrung = nie Crash durch harten Aufprall.
--   * Barrier (Tag): Wand/Leitplanke. Der Wagen gleitet entlang (Tempo in die Wand wird zu
--     Tempo entlang der Wand, etwas Zurueckdruecken = Attribut Bounce) und wird sanft in
--     Richtung Wand-Verlauf gedreht. Ohne Tag Hazard = NoDamage; mit Hazard = Crash
--     (macht CartClient wie bei jedem Hazard).
--   * StableZone (Tag, unsichtbarer Bereich): Kippt der Wagen ueber MaxTilt, dreht er sich weich
--     zurueck (nur die Drehung, das Fahrtempo bleibt); Kipp-/Nickbewegungen gedaempft.
--     NoCrash (Standard true): harter Aufprall ist kein Crash. Weicher Uebergang rein/raus.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Attributes = require(Shared:WaitForChild("Attributes"))
local Config = require(Shared:WaitForChild("Config"))
local GuideMath = require(Shared:WaitForChild("Toolkit"):WaitForChild("GuideMath"))
local TagList = require(Shared:WaitForChild("TagList"))
local CartController = require(script.Parent:WaitForChild("CartController"))

local Guides = {}

export type Result = {
	noDamage: boolean, -- an NoDamage/Barrier: kein Crash durch Aufprall
	stable: boolean, -- in einer Stabil-Zone mit NoCrash
}

local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Include
local stableBlend = 0
local stableZone: BasePart? = nil -- zuletzt benutzte Zone (Werte beim Hinausfahren)

local function tagged(part: Instance, tag: string): Instance?
	local current: Instance? = part
	while current and current ~= workspace do
		if current:HasTag(tag) then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Wand-Normale (waagerecht, vom Part weg) am naechsten Punkt zum Wagen
local function normalFrom(part: BasePart, position: Vector3): Vector3?
	local localPos = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local clamped = Vector3.new(
		math.clamp(localPos.X, -half.X, half.X),
		math.clamp(localPos.Y, -half.Y, half.Y),
		math.clamp(localPos.Z, -half.Z, half.Z)
	)
	local away = position - part.CFrame:PointToWorldSpace(clamped)
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.05 then
		return nil -- Mittelpunkt im Part: keine sinnvolle Richtung
	end
	return away.Unit
end

local function barriers(cart: Model, base: BasePart, dt: number): boolean
	local list = {}
	for _, tag in { "Barrier", "NoDamage" } do
		for _, item in TagList.get(tag) do
			table.insert(list, item)
		end
	end
	if #list == 0 then
		return false
	end
	params.FilterDescendantsInstances = list
	local B = Config.Barrier
	local cframe, size = cart:GetBoundingBox()
	local noDamage = false
	local normal = Vector3.zero
	local bounce = 0
	for _, part in workspace:GetPartBoundsInBox(cframe, size + Vector3.one * B.Padding * 2, params) do
		local barrier = tagged(part, "Barrier")
		if barrier then
			if barrier:HasTag("Hazard") then
				continue -- gefaehrliche Barriere: Crash macht CartClient (Hazard)
			end
			noDamage = true
			local n = normalFrom(part, base.Position)
			if n then
				normal += n
				bounce = math.max(bounce, Attributes.number(barrier, "Bounce", B.Bounce))
			end
		elseif tagged(part, "NoDamage") then
			noDamage = true
		end
	end
	if normal.Magnitude > 0.01 then
		local n = normal.Unit
		local v = base.AssemblyLinearVelocity
		local vx, vz = GuideMath.slide(v.X, v.Z, n.X, n.Z, B.SpeedKeep, bounce)
		if vx ~= v.X or vz ~= v.Z then
			base.AssemblyLinearVelocity = Vector3.new(vx, v.Y, vz)
		end
		-- sanft in Richtung Wand-Verlauf drehen
		if math.sqrt(vx * vx + vz * vz) > 5 then
			local look = base.CFrame.LookVector
			local rate = GuideMath.yawRate(look.X, look.Z, vx, vz, B.SteerRate)
			local angular = base.AssemblyAngularVelocity
			local blend = math.min(1, dt * B.SteerResponse)
			base.AssemblyAngularVelocity =
				Vector3.new(angular.X, angular.Y + (rate - angular.Y) * blend, angular.Z)
		end
	end
	return noDamage
end

local function zoneAt(position: Vector3): BasePart?
	for _, zone in TagList.get("StableZone") do
		if zone:IsA("BasePart") then
			local p = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2
			if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
				return zone
			end
		end
	end
	return nil
end

local function stable(base: BasePart, dt: number): boolean
	local S = Config.StableZone
	local zone = zoneAt(base.Position)
	if zone then
		stableZone = zone
	end
	stableBlend = GuideMath.blend(stableBlend, zone ~= nil, dt, S.BlendTime)
	local current = stableZone
	if stableBlend <= 0 or not current then
		return false
	end
	local maxTilt = Attributes.number(current, "MaxTilt", S.MaxTilt)
	local speed = Attributes.number(current, "RightingSpeed", S.RightingSpeed)
	local up = base.CFrame.UpVector
	local rate = GuideMath.rightingRate(GuideMath.tilt(up.Y), maxTilt, speed) * stableBlend
	-- nur die Drehung aendern: Gieren bleibt, Kippen/Nicken gedaempft, Aufrichten dazu
	local angular = base.AssemblyAngularVelocity
	local yaw = Vector3.yAxis * angular.Y
	local horizontal = angular - yaw
	local damp = math.exp(-S.Damping * stableBlend * dt)
	local axis = up:Cross(Vector3.yAxis)
	local result = yaw + horizontal * damp
	if rate > 0 and axis.Magnitude > 1e-3 then
		axis = axis.Unit
		local along = result:Dot(axis)
		result += axis * (rate - along) * math.min(1, dt * 8)
	end
	base.AssemblyAngularVelocity = result
	local noCrash = current:GetAttribute("NoCrash")
	return if type(noCrash) == "boolean" then noCrash else S.NoCrash
end

-- Jeden Frame nach der Fahrphysik (CartClient)
function Guides.step(dt: number, controller: CartController.Controller): Result
	local base = controller.base
	return {
		noDamage = barriers(controller.cart, base, dt),
		stable = stable(base, dt),
	}
end

-- Neustart: Stabil-Zone vergessen (kein Nachwirken am Start)
function Guides.reset()
	stableBlend = 0
	stableZone = nil
end

return Guides
