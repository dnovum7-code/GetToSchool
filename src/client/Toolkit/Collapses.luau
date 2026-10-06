--!strict
-- Collapse (Tag "Collapse", Part oder Modell): Faehrt der eigene Wagen darauf (oder kommt
-- das Signal aus ListenSignal), wackelt das Stueck Delay Sekunden und stuerzt dann ab.
-- Nur bei dir: Das Original wird bei dir ausgeblendet, eine lokale Kopie faellt.
-- Bei R und T steht es wieder.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TagList = require(Shared:WaitForChild("TagList"))
local LocalClone = require(script.Parent.Parent:WaitForChild("LocalClone"))
local LocalHide = require(script.Parent.Parent:WaitForChild("LocalHide"))
local Pieces = require(script.Parent:WaitForChild("Pieces"))
local Signals = require(script.Parent:WaitForChild("Signals"))
local ToolkitTypes = require(script.Parent:WaitForChild("ToolkitTypes"))

type Piece = {
	instance: PVInstance,
	home: CFrame,
	state: string, -- "Idle", "Shaking", "Fallen"
	triggeredAt: number,
	falling: PVInstance?, -- lokale, fallende Kopie
	disconnect: (() -> ())?,
}

local pieces: { [Instance]: Piece } = {}
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include

local function trigger(piece: Piece)
	if piece.state == "Idle" and not LocalHide.isHidden(piece.instance) then
		piece.state = "Shaking"
		piece.triggeredAt = os.clock()
		Signals.debugLog(`Collapse "{piece.instance.Name}" gibt nach`)
	end
end

local function register(instance: Instance)
	if pieces[instance] or not (instance:IsA("Model") or instance:IsA("BasePart")) then
		return
	end
	local pv = instance :: PVInstance
	local piece: Piece = {
		instance = pv,
		home = pv:GetPivot(),
		state = "Idle",
		triggeredAt = 0,
		falling = nil,
		disconnect = nil,
	}
	local listen = Pieces.string(instance, "ListenSignal", nil)
	if listen then
		piece.disconnect = Signals.on(listen, function()
			trigger(piece)
		end)
	end
	pieces[instance] = piece
end

local function fall(piece: Piece)
	piece.state = "Fallen"
	piece.instance:PivotTo(piece.home)
	local copy = LocalClone.copy(piece.instance)
	LocalHide.set(piece.instance, "Collapsed", true)
	if not copy then
		return
	end
	LocalClone.weldTogether(copy) -- faellt als ein Stueck
	local spin = Pieces.number(piece.instance, "FallSpin", Config.Collapse.FallSpin)
	for _, part in LocalClone.allParts(copy) do
		part.Anchored = false
		part.CanCollide = true
		part.CanQuery = false
		part.CanTouch = false
	end
	copy.Parent = LocalClone.folder("LocalToolkit")
	local angular = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 2 * spin
	for _, part in LocalClone.allParts(copy) do
		part.AssemblyLinearVelocity = Vector3.new(0, -5, 0)
		part.AssemblyAngularVelocity = angular
	end
	piece.falling = copy
end

local function restore(piece: Piece)
	local copy = piece.falling
	if copy then
		copy:Destroy()
		piece.falling = nil
	end
	piece.state = "Idle"
	piece.instance:PivotTo(piece.home)
	LocalHide.set(piece.instance, "Collapsed", false)
end

local Collapses: ToolkitTypes.Piece = {
	init = function()
		TagList.watch("Collapse", register)
	end,

	step = function(ctx)
		-- Steht der eigene Wagen auf einem Collapse-Stueck? (Kasten um den Wagen, etwas nach unten)
		local cart = ctx.cart
		if cart then
			local include = {}
			for instance, piece in pieces do
				if piece.state == "Idle" and not piece.disconnect then
					table.insert(include, instance)
				end
			end
			if #include > 0 then
				overlapParams.FilterDescendantsInstances = include
				local cframe, size = cart:GetBoundingBox()
				local box = cframe * CFrame.new(0, -0.5, 0)
				for _, part in
					workspace:GetPartBoundsInBox(box, size + Vector3.new(0.4, 1, 0.4), overlapParams)
				do
					local current: Instance? = part
					while current and current ~= workspace do
						local piece = pieces[current]
						if piece then
							trigger(piece)
							break
						end
						current = current.Parent
					end
				end
			end
		end

		local C = Config.Collapse
		local now = os.clock()
		for instance, piece in pieces do
			if not instance:IsDescendantOf(workspace) then
				if piece.disconnect then
					piece.disconnect()
				end
				if piece.falling then
					piece.falling:Destroy()
				end
				pieces[instance] = nil
				continue
			end
			if piece.state == "Shaking" then
				local elapsed = now - piece.triggeredAt
				if elapsed >= Pieces.number(instance, "Delay", C.Delay) then
					fall(piece)
				else
					-- wackeln (nur bei uns; verankert, nur die Lage aendert sich)
					local amount = Pieces.number(instance, "Shake", C.Shake)
					local speed = C.ShakeSpeed
					local offset = Vector3.new(
						math.noise(elapsed * speed, 1.3) * amount,
						math.noise(elapsed * speed, 7.9) * amount * 0.5,
						math.noise(elapsed * speed, 4.1) * amount
					)
					piece.instance:PivotTo(piece.home + offset)
				end
			elseif piece.state == "Fallen" then
				local copy = piece.falling
				if
					copy
					and now - piece.triggeredAt > Pieces.number(instance, "Delay", C.Delay) + C.FallTime
				then
					copy:Destroy()
					piece.falling = nil
				end
			end
		end
	end,

	-- R und T: alles steht wieder
	reset = function()
		for _, piece in pieces do
			restore(piece)
		end
	end,
}

return Collapses
