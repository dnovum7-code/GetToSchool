--!strict
-- Verfolger (Tag "Pursuer", Modell oder Part, z. B. Schulbus oder Hauswart) mit Ordner
-- "Waypoints" (Parts "1", "2", ... entlang der Strecke, wie beim PathMover).
--   * Startet StartDelay Sekunden nach dem Losfahren hinter dir und faehrt die Wegpunkte ab.
--   * Gummiband (shared/Toolkit/PursuerLogic): langsam oder Crash = er holt auf, gut
--     fahren = er faellt zurueck, aber nie weiter als MaxGap.
--   * Erwischt er dich: ein Leben weg und du fliegst (CartClient, Pursuers.onCaught).
--     Attribut GameOverOnCatch = true: sofort Game Over.
--   * Anzeige: Abstand oben, rote Bildschirmraender, Warnton (Config.Sounds.PursuerWarn
--     oder Attribut "Sound").
--   * R: startet MinGap hinter dir neu, T: wieder am Anfang (nach StartDelay).
--   * Im Ziel: faehrt bis zum letzten Wegpunkt und kracht dort in den Zaun (bleibt stecken).
-- Attribute: StartDelay, BaseSpeed, CatchUpSpeed, MinGap, MaxGap, CatchRadius, WarnGap,
-- GameOverOnCatch, DisplayName, Sound. Laeuft nur bei dir (jeder Spieler hat seinen eigenen).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TagList = require(Shared:WaitForChild("TagList"))
local PursuerLogic = require(Shared:WaitForChild("Toolkit"):WaitForChild("PursuerLogic"))
local Kinematic = require(script.Parent.Parent:WaitForChild("Kinematic"))
local LocalClone = require(script.Parent.Parent:WaitForChild("LocalClone"))
local LocalHide = require(script.Parent.Parent:WaitForChild("LocalHide"))
local SoundSystem = require(script.Parent.Parent:WaitForChild("SoundSystem"))
local Pieces = require(script.Parent:WaitForChild("Pieces"))
local Signals = require(script.Parent:WaitForChild("Signals"))
local ToolkitTypes = require(script.Parent:WaitForChild("ToolkitTypes"))

type State = "Idle" | "Waiting" | "Chasing" | "Finishing" | "Crashed"

type Pursuer = {
	instance: PVInstance,
	points: { Vector3 },
	cum: { number },
	length: number,
	parts: { BasePart },
	home: CFrame,
	last: CFrame,
	rotation: CFrame,
	state: State,
	startAt: number,
	s: number,
	cooldownUntil: number,
	reposition: boolean,
	snap: boolean,
	lastWarn: number,
}

local pursuers: { [Instance]: Pursuer } = {}
local caughtCallback: ((gameOver: boolean, push: Vector3, name: string) -> ())? = nil

-- Anzeige
local gui: ScreenGui? = nil
local gapLabel: TextLabel
local edges: { Frame } = {}

local function buildGui()
	local screen = Instance.new("ScreenGui")
	screen.Name = "PursuerUI"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 2
	-- rote Raender: vier Streifen mit Verlauf nach innen
	local specs: { { size: UDim2, position: UDim2, rotation: number } } = {
		{ size = UDim2.fromScale(1, 0.18), position = UDim2.fromScale(0, 0), rotation = 90 },
		{ size = UDim2.fromScale(1, 0.18), position = UDim2.fromScale(0, 0.82), rotation = -90 },
		{ size = UDim2.fromScale(0.12, 1), position = UDim2.fromScale(0, 0), rotation = 0 },
		{ size = UDim2.fromScale(0.12, 1), position = UDim2.fromScale(0.88, 0), rotation = 180 },
	}
	for _, spec in specs do
		local frame = Instance.new("Frame")
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = Color3.fromRGB(255, 20, 20)
		frame.Size = spec.size
		frame.Position = spec.position
		frame.BackgroundTransparency = 1
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = spec.rotation
		gradient.Transparency = NumberSequence.new(0, 1)
		gradient.Parent = frame
		frame.Parent = screen
		table.insert(edges, frame)
	end
	gapLabel = Instance.new("TextLabel")
	gapLabel.Name = "Gap"
	gapLabel.AnchorPoint = Vector2.new(0.5, 0)
	gapLabel.Position = UDim2.new(0.5, 0, 0, 205)
	gapLabel.Size = UDim2.fromOffset(420, 34)
	gapLabel.BackgroundTransparency = 1
	gapLabel.Font = Enum.Font.LuckiestGuy
	gapLabel.TextScaled = true
	gapLabel.TextColor3 = Color3.new(1, 1, 1)
	gapLabel.TextStrokeTransparency = 0
	gapLabel.Visible = false
	gapLabel.Parent = screen
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
end

local function showDanger(danger: number, text: string?)
	if not gui then
		return
	end
	for _, frame in edges do
		frame.BackgroundTransparency = 1 - 0.75 * danger
	end
	gapLabel.Visible = text ~= nil
	if text then
		gapLabel.Text = text
		gapLabel.TextColor3 = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 70, 60), danger)
	end
end

local function attr(p: Pursuer, name: string): number
	return Pieces.number(p.instance, name, (Config.Pursuer :: any)[name])
end

local function params(p: Pursuer): PursuerLogic.Params
	return {
		baseSpeed = attr(p, "BaseSpeed"),
		catchUpSpeed = attr(p, "CatchUpSpeed"),
		minGap = attr(p, "MinGap"),
		maxGap = attr(p, "MaxGap"),
	}
end

local function displayName(instance: Instance): string
	return Pieces.string(instance, "DisplayName", nil) or Config.Pursuer.DisplayName
end

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

-- Spieler auf den Weg projizieren: Strecke s des naechsten Punkts
local function project(p: Pursuer, position: Vector3): number
	local bestS, bestDistance = 0, math.huge
	for i = 1, #p.points - 1 do
		local a, b = p.points[i], p.points[i + 1]
		local ab = b - a
		local lengthSq = ab:Dot(ab)
		local t = if lengthSq > 0 then math.clamp((position - a):Dot(ab) / lengthSq, 0, 1) else 0
		local distance = (a + ab * t - position).Magnitude
		if distance < bestDistance then
			bestDistance = distance
			bestS = p.cum[i] + (p.cum[i + 1] - p.cum[i]) * t
		end
	end
	return bestS
end

local function setVisible(p: Pursuer, visible: boolean)
	LocalHide.set(p.instance, "Pursuer", not visible)
end

-- Verfolger an die Stelle s setzen (Blick in Fahrtrichtung, weich gedreht)
local function place(p: Pursuer, dt: number, extraRotation: CFrame?)
	local i, alpha = PursuerLogic.locate(p.cum, p.s)
	local a, b = p.points[i], p.points[math.min(i + 1, #p.points)]
	local position = a:Lerp(b, alpha)
	if (b - a).Magnitude > 0.01 then
		local wanted = CFrame.lookAt(Vector3.zero, b - a).Rotation
		local turn = if p.snap then 1 else 1 - math.exp(-Config.Pursuer.TurnSpeed * dt)
		p.rotation = p.rotation:Lerp(wanted, turn)
	end
	local target = CFrame.new(position) * p.rotation * (extraRotation or CFrame.identity)
	Kinematic.move(p.instance, p.last, target, if p.snap then 0 else dt, true, p.parts)
	p.snap = false
	p.last = target
end

local function comicText(position: Vector3, text: string)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = position
	anchor.Parent = LocalClone.folder("LocalPursuerFX")
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(300, 110)
	billboard.AlwaysOnTop = true
	billboard.Adornee = anchor
	billboard.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 200, 60)
	label.TextStrokeTransparency = 0
	label.Rotation = -8
	label.Parent = billboard
	TweenService:Create(billboard, TweenInfo.new(2), { StudsOffset = Vector3.new(0, 5, 0) }):Play()
	task.delay(2.5, function()
		anchor:Destroy()
	end)
end

local function register(instance: Instance)
	if pursuers[instance] or not (instance:IsA("Model") or instance:IsA("BasePart")) then
		return
	end
	local points, folder = readWaypoints(instance)
	if #points < 2 then
		warn(
			`[Baukasten] {instance:GetFullName()}: Pursuer braucht einen Ordner "Waypoints" mit mindestens 2 Parts ("1", "2", ...).`
		)
		return
	end
	if folder then
		folder.Parent = LocalClone.folder("LocalWaypoints") -- sonst fahren die Punkte mit
	end
	local lengths = {}
	for i = 1, #points - 1 do
		table.insert(lengths, (points[i + 1] - points[i]).Magnitude)
	end
	local cum = PursuerLogic.cumulative(lengths)
	local pv = instance :: PVInstance
	local home = pv:GetPivot()
	local p: Pursuer = {
		instance = pv,
		points = points,
		cum = cum,
		length = cum[#cum],
		parts = LocalClone.allParts(instance),
		home = home,
		last = home,
		rotation = home.Rotation,
		state = "Idle",
		startAt = 0,
		s = 0,
		cooldownUntil = 0,
		reposition = false,
		snap = true,
		lastWarn = -math.huge,
	}
	-- Beruehren ist kein harter Aufprall (das Erwischen regelt das Modul selbst)
	CollectionService:AddTag(instance, "SoftHit")
	setVisible(p, false)
	pursuers[instance] = p
end

local Pursuers = {}

-- CartClient: was passiert, wenn er dich erwischt (Leben weg, wegschleudern)
function Pursuers.onCaught(callback: (gameOver: boolean, push: Vector3, name: string) -> ())
	caughtCallback = callback
end

-- Lauf-Ereignisse aus CartClient: "Started", "Finished", "GameOver"
function Pursuers.runEvent(kind: string)
	for _, p in pursuers do
		if kind == "Started" then
			p.state = "Waiting"
			p.startAt = os.clock() + attr(p, "StartDelay")
		elseif kind == "Finished" then
			if p.state == "Chasing" then
				p.state = "Finishing"
			else
				p.state = "Idle"
				setVisible(p, false)
			end
		elseif kind == "GameOver" then
			p.state = "Idle"
			setVisible(p, false)
		end
	end
	if kind ~= "Started" then
		showDanger(0, nil)
	end
end

local piece: ToolkitTypes.Piece = {
	init = function()
		buildGui()
		TagList.watch("Pursuer", register)
	end,

	step = function(ctx)
		local now = os.clock()
		local base = ctx.base
		local worstDanger, worstText = 0, nil :: string?
		for instance, p in pursuers do
			if not instance:IsDescendantOf(workspace) then
				pursuers[instance] = nil
				continue
			end
			if p.state == "Waiting" and base and now >= p.startAt then
				p.state = "Chasing"
				p.s = PursuerLogic.behind(project(p, base.Position), attr(p, "MaxGap"))
				p.snap = true
				setVisible(p, true)
				Signals.debugLog(`Pursuer "{instance.Name}" startet`)
			end
			if p.state == "Chasing" then
				if not base then
					continue -- ausgestiegen / Crash: steht still
				end
				local playerS = project(p, base.Position)
				if p.reposition then
					p.reposition = false
					p.s = PursuerLogic.behind(playerS, attr(p, "MinGap"))
					p.snap = true
				else
					p.s = PursuerLogic.advance(p.s, playerS, ctx.dt, params(p), p.length)
				end
				place(p, ctx.dt)
				local distance = (p.last.Position - base.Position).Magnitude
				local catchRadius = attr(p, "CatchRadius")
				local danger = PursuerLogic.danger(distance, catchRadius, attr(p, "WarnGap"))
				if danger >= worstDanger then
					worstDanger = danger
					local meters = math.max(0, math.floor((playerS - p.s) * Config.UI.StudsToMeters + 0.5))
					worstText = `{displayName(instance)}: {meters} m`
				end
				if danger > 0.5 and now - p.lastWarn > 4 then
					p.lastWarn = now
					SoundSystem.playId(
						instance:GetAttribute("Sound"),
						Config.Sounds.PursuerWarn.Volume,
						"PursuerWarn"
					)
				end
				if distance <= catchRadius and now >= p.cooldownUntil then
					p.cooldownUntil = now + Config.Pursuer.CatchCooldown
					local push = base.Position - p.last.Position
					push = Vector3.new(push.X, 0, push.Z)
					if push.Magnitude < 0.1 then
						push = p.last.LookVector
					end
					SoundSystem.play("PursuerCatch")
					local callback = caughtCallback
					if callback then
						local gameOver =
							Pieces.bool(instance, "GameOverOnCatch", Config.Pursuer.GameOverOnCatch)
						callback(gameOver, push.Unit, displayName(instance))
					end
					-- danach etwas Abstand (sonst erwischt er dich sofort wieder)
					p.s = PursuerLogic.behind(playerS, attr(p, "MinGap"))
					p.snap = true
				end
			elseif p.state == "Finishing" then
				-- Ziel: weiter bis zum letzten Wegpunkt, dort in den Zaun
				p.s = math.min(p.s + attr(p, "BaseSpeed") * ctx.dt, p.length)
				place(p, ctx.dt)
				if p.s >= p.length then
					p.state = "Crashed"
					local tilt = math.rad(Config.Pursuer.CrashTilt)
					place(p, 0, CFrame.Angles(-tilt * 0.5, 0, tilt))
					comicText(p.last.Position + Vector3.new(0, 6, 0), "KRACH!")
					SoundSystem.play("PursuerCrash")
				end
			end
		end
		showDanger(worstDanger, worstText)
	end,

	-- T: wieder am Anfang (startet nach dem Losfahren neu), R: MinGap hinter dir
	reset = function(kind: string)
		for _, p in pursuers do
			if kind == "Full" then
				p.state = "Idle"
				p.s = 0
				p.snap = true
				p.rotation = p.home.Rotation
				p.last = p.home
				Kinematic.move(p.instance, p.home, p.home, 0, true, p.parts)
				setVisible(p, false)
			elseif p.state == "Chasing" or p.state == "Waiting" then
				p.reposition = p.state == "Chasing"
				p.cooldownUntil = os.clock() + 1
			end
		end
		showDanger(0, nil)
	end,
}

Pursuers.init = piece.init
Pursuers.step = piece.step
Pursuers.reset = piece.reset

return Pursuers
