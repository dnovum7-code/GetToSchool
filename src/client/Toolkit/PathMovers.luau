--!strict
-- PathMover (Tag "PathMover", Modell oder Part): faehrt Wegpunkte ab (Ordner "Waypoints" mit
-- Parts "1", "2", "3" ...). Ohne ListenSignal im Dauerbetrieb nach der Serveruhr (alle
-- Spieler sehen ihn an derselben Stelle), mit ListenSignal ein Durchgang pro Signal.
-- Bewegt wird wie bei Mover: verankert, mit passender Geschwindigkeit, damit er den Wagen
-- sauber wegschiebt (siehe Kinematic).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TagList = require(Shared:WaitForChild("TagList"))
local PathMath = require(Shared:WaitForChild("Toolkit"):WaitForChild("PathMath"))
local Kinematic = require(script.Parent.Parent:WaitForChild("Kinematic"))
local LocalClone = require(script.Parent.Parent:WaitForChild("LocalClone"))
local Pieces = require(script.Parent:WaitForChild("Pieces"))
local Signals = require(script.Parent:WaitForChild("Signals"))
local ToolkitTypes = require(script.Parent:WaitForChild("ToolkitTypes"))

type Mover = {
	instance: PVInstance,
	points: { Vector3 },
	path: PathMath.Path,
	home: CFrame, -- Lage aus Studio (Drehung, wenn FaceDirection aus ist)
	last: CFrame,
	rotation: CFrame, -- aktuelle (geglaettete) Drehung
	signalStart: number?, -- Mit ListenSignal: os.clock() beim letzten Signal
	disconnect: (() -> ())?,
}

local movers: { [Instance]: Mover } = {}

-- Wegpunkte lesen ("1", "2", ... nach Zahl sortiert)
local function readWaypoints(instance: Instance): ({ Vector3 }, Instance?)
	local folder = instance:FindFirstChild("Waypoints")
	if not folder then
		return {}, nil
	end
	local numbered: { { n: number, position: Vector3 } } = {}
	for _, child in folder:GetChildren() do
		local n = tonumber(child.Name)
		if n and child:IsA("BasePart") then
			table.insert(numbered, { n = n, position = child.Position })
		end
	end
	table.sort(numbered, function(a, b)
		return a.n < b.n
	end)
	local points = {}
	for _, entry in numbered do
		table.insert(points, entry.position)
	end
	return points, folder
end

local function register(instance: Instance)
	if movers[instance] or not (instance:IsA("Model") or instance:IsA("BasePart")) then
		return
	end
	local points, folder = readWaypoints(instance)
	if #points < 2 then
		warn(
			`[Baukasten] {instance:GetFullName()}: PathMover braucht einen Ordner "Waypoints" mit mindestens 2 Parts ("1", "2", ...).`
		)
		return
	end
	-- Wegpunkte aus dem Modell nehmen (nur bei uns), sonst wuerden sie mitfahren
	if folder then
		folder.Parent = LocalClone.folder("LocalWaypoints")
	end
	local P = Config.PathMover
	local loop = Pieces.bool(instance, "Loop", P.Loop)
	local speed = Pieces.number(instance, "Speed", P.Speed)
	local wait = Pieces.number(instance, "WaitAtPoints", P.WaitAtPoints)
	local path = PathMath.build(#points, function(a, b)
		return (points[b] - points[a]).Magnitude
	end, speed, wait, loop)
	local pv = instance :: PVInstance
	local home = pv:GetPivot()
	local mover: Mover = {
		instance = pv,
		points = points,
		path = path,
		home = home,
		last = home,
		rotation = home.Rotation,
		signalStart = nil,
		disconnect = nil,
	}
	local listen = Pieces.string(instance, "ListenSignal", nil)
	if listen then
		mover.disconnect = Signals.on(listen, function()
			mover.signalStart = os.clock()
		end)
	end
	movers[instance] = mover
end

-- Zeit im Fahrplan: Dauerbetrieb = Serverzeit (+ Phase); Signal = Zeit seit dem Signal,
-- nach einem Durchgang bleibt er am Start stehen
local function planTime(mover: Mover): number
	if mover.disconnect then
		local start = mover.signalStart
		if not start then
			return 0
		end
		local since = os.clock() - start
		if since >= mover.path.cycle then
			mover.signalStart = nil
			return 0
		end
		return since
	end
	return workspace:GetServerTimeNow() + Pieces.number(mover.instance, "Phase", 0)
end

local PathMovers: ToolkitTypes.Piece = {
	init = function()
		TagList.watch("PathMover", register)
	end,

	step = function(ctx)
		for instance, mover in movers do
			if not instance:IsDescendantOf(workspace) then
				if mover.disconnect then
					mover.disconnect()
				end
				movers[instance] = nil
				continue
			end
			local from, to, alpha = PathMath.sample(mover.path, planTime(mover))
			local a, b = mover.points[from], mover.points[to]
			local position = a:Lerp(b, alpha)
			local rotation = mover.home.Rotation
			if
				Pieces.bool(instance, "FaceDirection", Config.PathMover.FaceDirection)
				and (b - a).Magnitude > 0.01
			then
				local wanted = CFrame.lookAt(Vector3.zero, b - a).Rotation
				local turn = 1 - math.exp(-Config.PathMover.TurnSpeed * ctx.dt)
				mover.rotation = mover.rotation:Lerp(wanted, turn)
				rotation = mover.rotation
			end
			local target = CFrame.new(position) * rotation
			Kinematic.move(mover.instance, mover.last, target, ctx.dt, true)
			mover.last = target
		end
	end,

	-- R und T: Signal-Mover zurueck an den Start
	reset = function()
		for _, mover in movers do
			mover.signalStart = nil
		end
	end,
}

return PathMovers
