--!strict
-- Sicherheitsnetz fuer Terrain: Ist der eigene Wagen unter die Terrain-Oberflaeche geraten
-- (durch noch nicht geladenes Gelaende gefallen, durch die Oberflaeche getunnelt), wird er
-- wieder obendrauf gesetzt und faehrt weiter - kein Crash, kein Leben weg.
--
-- Erkennung (alle Config.TerrainSafety.CheckInterval Sekunden, nur Terrain zaehlt):
--   1. Von weit oben nach unten bis zum Wagen: Liegt die Terrain-Oberflaeche mehr als Margin
--      ueber dem Wagenboden?
--   2. Ausnahme Hoehle/Tunnel: Ueber dem Wagen eine Decke (Flaeche zeigt nach unten) UND direkt
--      darunter Boden -> der Wagen faehrt dort ganz normal.
--   3. Erst wenn das BelowTime Sekunden so bleibt: zuruecksetzen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CartController = require(script.Parent:WaitForChild("CartController"))

local TerrainRescue = {}

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { workspace.Terrain }

local timer = 0
local belowTime = 0
local lastController: CartController.Controller? = nil

-- Wagen auf die Oberflaeche setzen: Blickrichtung behalten, Tempo waagerecht (gekuerzt)
local function rescue(controller: CartController.Controller, surface: RaycastResult)
	local T = Config.TerrainSafety
	local base = controller.base
	local c = controller.stats.Cart
	local up = surface.Normal
	local rideHeight = c.WheelDiameter + c.WheelGap + c.FloorThickness / 2
	local position = surface.Position + up * (rideHeight + T.Lift)

	local look = base.CFrame.LookVector
	look -= up * look:Dot(up)
	if look.Magnitude < 0.05 then
		local fallback = -Vector3.zAxis
		look = fallback - up * fallback:Dot(up)
	end
	controller.cart:PivotTo(CFrame.lookAt(position, position + look.Unit, up))

	local velocity = base.AssemblyLinearVelocity
	local flat = velocity - up * velocity:Dot(up)
	local keep = flat * T.KeepSpeed
	local done: { [BasePart]: boolean } = {}
	for _, part in controller.cart:GetDescendants() do
		if part:IsA("BasePart") then
			local root = part.AssemblyRootPart or part
			if not done[root] then
				done[root] = true
				root.AssemblyLinearVelocity = keep
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
end

-- Jeden Frame aufrufen (nach der Fahrphysik). true = Wagen wurde gerade zurueckgesetzt.
function TerrainRescue.step(dt: number, controller: CartController.Controller): boolean
	local T = Config.TerrainSafety
	if not T.Enabled then
		return false
	end
	if controller ~= lastController then
		lastController = controller
		timer, belowTime = 0, 0
	end
	timer += dt
	if timer < T.CheckInterval then
		return false
	end
	local elapsed = timer
	timer = 0

	local position = controller.base.Position
	local top = workspace:Raycast(
		position + Vector3.new(0, T.ProbeHeight, 0),
		Vector3.new(0, -T.ProbeHeight, 0),
		params
	)
	if not top or top.Position.Y - position.Y < T.Margin then
		belowTime = 0
		return false
	end
	-- Hoehle oder Tunnel aus Terrain: Decke darueber und Boden direkt darunter = normal fahren
	local ceiling = workspace:Raycast(position, Vector3.new(0, T.ProbeHeight, 0), params)
	if ceiling and ceiling.Normal.Y < -0.3 then
		if workspace:Raycast(position, Vector3.new(0, -T.FloorProbe, 0), params) then
			belowTime = 0
			return false
		end
	end
	belowTime += elapsed
	if belowTime < T.BelowTime then
		return false
	end
	belowTime = 0
	rescue(controller, top)
	return true
end

return TerrainRescue
