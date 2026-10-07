--!nocheck
-- Erzeugt den Test-Place (Teststrecke, Testflaeche, Vorlagen) als Modell-Dateien in test/
-- und die Projektdatei test.project.json. Ausfuehren im Projektordner:
--     lune run tools/build_testplace
-- Danach:  rojo build test.project.json -o TestPlace.rbxl   (siehe README "Test-Place")
--
-- Die Strecke ist nur aus einfachen Parts gebaut. Sie laeuft bergab Richtung -Z.
-- Jede Station hat links ein Schild mit Nummer und dem, was dort getestet wird
-- (Nummern = Checkliste im README).

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local NumberRange = roblox.NumberRange
local UDim2 = roblox.UDim2

-- Abmessungen der Teststrecke
local SLOPE = math.rad(3) -- Gefaelle
local START_Y = 140
local ROAD_WIDTH = 28
local GROUND_WIDTH = 160
local STATION_LENGTH = 70
local FIRST_STATION = 50 -- Strecke vor Station 1 (Start)

local COLORS = {
	road = Color3.fromRGB(70, 70, 76),
	ground = Color3.fromRGB(96, 150, 70),
	rail = Color3.fromRGB(200, 200, 205),
	sign = Color3.fromRGB(35, 40, 55),
	post = Color3.fromRGB(120, 90, 60),
	zone = Color3.fromRGB(120, 255, 140),
	checkpoint = Color3.fromRGB(90, 200, 255),
	water = Color3.fromRGB(40, 110, 220),
	gold = Color3.fromRGB(255, 200, 40),
}

local function part(props: { [string]: any }): any
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "ClassName" and key ~= "Tags" and key ~= "Attributes" and key ~= "Parent" then
			p[key] = value
		end
	end
	for _, tag in props.Tags or {} do
		p:AddTag(tag)
	end
	for name, value in props.Attributes or {} do
		p:SetAttribute(name, value)
	end
	if props.Parent then
		p.Parent = props.Parent
	end
	return p
end

local function model(name: string, parent: any, tags: { string }?, attributes: { [string]: any }?): any
	local m = Instance.new("Model")
	m.Name = name
	for _, tag in tags or {} do
		m:AddTag(tag)
	end
	for key, value in attributes or {} do
		m:SetAttribute(key, value)
	end
	m.Parent = parent
	return m
end

-- Lage auf der Strasse: `s` = Strecke bergab (Studs), `x` = seitlich (+ = rechts in
-- Fahrtrichtung), `h` = Hoehe ueber der Fahrbahn. Vorderseite (-Z) zeigt bergab.
local function frame(s: number, x: number?, h: number?): any
	local surface = Vector3.new(0, START_Y - s * math.sin(SLOPE), -s * math.cos(SLOPE))
	return CFrame.new(surface) * CFrame.Angles(-SLOPE, 0, 0) * CFrame.new(x or 0, h or 0, 0)
end

-- Schild mit Text (Vorderseite zum ankommenden Fahrer)
local function sign(parent: any, s: number, text: string, x: number?)
	local holder = model("Schild", parent)
	local board = part({
		Name = "Board",
		Size = Vector3.new(16, 6, 0.4),
		CFrame = frame(s, x or -21, 6),
		Color = COLORS.sign,
		CanCollide = false,
		Parent = holder,
	})
	part({
		Name = "Post",
		Size = Vector3.new(0.6, 6, 0.6),
		CFrame = frame(s, x or -21, 1.5),
		Color = COLORS.post,
		CanCollide = false,
		Parent = holder,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- der Fahrer kommt von hinten (bergauf)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.FontFace = roblox.Font.fromEnum(Enum.Font.GothamBold)
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = text
	label.Parent = gui
end

-- Strassenstueck von s1 bis s2 (mit Gelaende darunter und Leitplanken)
local function road(parent: any, s1: number, s2: number, rails: boolean)
	local length = s2 - s1
	local mid = (s1 + s2) / 2
	part({
		Name = "Road",
		Size = Vector3.new(ROAD_WIDTH, 2, length),
		CFrame = frame(mid, 0, -1),
		Color = COLORS.road,
		Material = Enum.Material.Asphalt,
		Parent = parent,
	})
	part({
		Name = "Ground",
		Size = Vector3.new(GROUND_WIDTH, 4, length),
		CFrame = frame(mid, 0, -2.6),
		Color = COLORS.ground,
		Material = Enum.Material.Grass,
		Parent = parent,
	})
	if rails then
		for _, side in { -1, 1 } do
			part({
				Name = "Rail",
				Size = Vector3.new(1, 2.5, length),
				CFrame = frame(mid, side * (ROAD_WIDTH / 2 + 0.5), 1.25),
				Color = COLORS.rail,
				Material = Enum.Material.Metal,
				Parent = parent,
			})
		end
	end
end

local function stationStart(index: number): number
	return FIRST_STATION + (index - 1) * STATION_LENGTH
end

local function coin(parent: any, cf: any, value: number?, size: number?)
	local d = size or 3
	part({
		Name = "Coin",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, d, d),
		-- Zylinder-Achse ist X: um 90 Grad drehen, damit die Muenze zum Fahrer schaut
		CFrame = cf * CFrame.Angles(0, math.rad(90), 0),
		Color = COLORS.gold,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Tags = { "Coin" },
		Attributes = if value then { Value = value } else nil,
		Parent = parent,
	})
end

local function zone(
	parent: any,
	name: string,
	cf: any,
	size: any,
	color: any,
	tags: { string },
	attributes: any?
)
	return part({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Transparency = 0.8,
		CanCollide = false,
		Tags = tags,
		Attributes = attributes,
		Parent = parent,
	})
end

-- Platzhalter-Kuh (Modell, Vorderseite -Z)
local function cow(parent: any, cf: any): any
	local m = model("Kuh", parent, { "Launchable" }, { DisplayName = "Kuh", ComicText = "MUUH!" })
	local body = part({
		Name = "Body",
		Size = Vector3.new(3.2, 3, 6),
		CFrame = cf * CFrame.new(0, 3.5, 0),
		Color = Color3.fromRGB(245, 245, 245),
		Parent = m,
	})
	part({
		Name = "Head",
		Size = Vector3.new(2.2, 2, 2.4),
		CFrame = cf * CFrame.new(0, 4.4, -3.8),
		Color = Color3.fromRGB(245, 245, 245),
		Parent = m,
	})
	part({
		Name = "Nose",
		Size = Vector3.new(1.8, 1, 0.6),
		CFrame = cf * CFrame.new(0, 3.9, -5.1),
		Color = Color3.fromRGB(240, 170, 180),
		Parent = m,
	})
	for _, xz in { { -1, -2 }, { 1, -2 }, { -1, 2 }, { 1, 2 } } do
		part({
			Name = "Leg",
			Size = Vector3.new(0.8, 2.2, 0.8),
			CFrame = cf * CFrame.new(xz[1], 1.1, xz[2]),
			Color = Color3.fromRGB(245, 245, 245),
			Parent = m,
		})
	end
	for _, spot in { { 1.61, 3.8, -1 }, { -1.61, 3.3, 1.2 }, { 1.61, 3.1, 1.8 } } do
		part({
			Name = "Spot",
			Size = Vector3.new(0.05, 1.2, 1.6),
			CFrame = cf * CFrame.new(spot[1], spot[2], spot[3]),
			Color = Color3.fromRGB(20, 20, 20),
			Parent = m,
		})
	end
	m.PrimaryPart = body
	return m
end

-- Platzhalter-Hund (Modell, Schnauze vorne = -Z)
local function dog(parent: any, cf: any): any
	local m = model("Hund", parent, { "Chaser" }, { Radius = 35, MaxSpeed = 28 })
	local brown = Color3.fromRGB(150, 100, 55)
	local body = part({
		Name = "Body",
		Size = Vector3.new(1.6, 1.6, 3.6),
		CFrame = cf * CFrame.new(0, 1.9, 0),
		Color = brown,
		Parent = m,
	})
	part({
		Name = "Head",
		Size = Vector3.new(1.4, 1.4, 1.4),
		CFrame = cf * CFrame.new(0, 2.7, -2.2),
		Color = brown,
		Parent = m,
	})
	part({
		Name = "Snout",
		Size = Vector3.new(0.8, 0.6, 0.8),
		CFrame = cf * CFrame.new(0, 2.4, -3.1),
		Color = Color3.fromRGB(40, 30, 25),
		Parent = m,
	})
	for _, xz in { { -0.5, -1.3 }, { 0.5, -1.3 }, { -0.5, 1.3 }, { 0.5, 1.3 } } do
		part({
			Name = "Leg",
			Size = Vector3.new(0.4, 1.1, 0.4),
			CFrame = cf * CFrame.new(xz[1], 0.55, xz[2]),
			Color = brown,
			Parent = m,
		})
	end
	part({
		Name = "Tail",
		Size = Vector3.new(0.3, 0.3, 1.2),
		CFrame = cf * CFrame.new(0, 2.5, 2.2) * CFrame.Angles(math.rad(-30), 0, 0),
		Color = brown,
		Parent = m,
	})
	m.PrimaryPart = body
	return m
end

-- Platzhalter-Auto (Modell, Vorderseite -Z), auch als Vorlage
local function car(parent: any, cf: any, name: string, color: any): any
	local m = model(name, parent)
	local body = part({
		Name = "Body",
		Size = Vector3.new(5, 2.4, 9),
		CFrame = cf * CFrame.new(0, 2, 0),
		Color = color,
		Parent = m,
	})
	part({
		Name = "Cabin",
		Size = Vector3.new(4.4, 1.8, 4.4),
		CFrame = cf * CFrame.new(0, 4.1, 0.6),
		Color = Color3.fromRGB(180, 220, 255),
		Transparency = 0.2,
		Parent = m,
	})
	for _, xz in { { -2.6, -3 }, { 2.6, -3 }, { -2.6, 3 }, { 2.6, 3 } } do
		part({
			Name = "Wheel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.8, 1.8, 1.8),
			CFrame = cf * CFrame.new(xz[1], 0.9, xz[2]),
			Color = Color3.fromRGB(25, 25, 25),
			Parent = m,
		})
	end
	m.PrimaryPart = body
	return m
end

------------------------------------------------------------------------------------------
-- Teststrecke
------------------------------------------------------------------------------------------
local track = model("TestTrack", nil, nil, { TrackId = "Track1", TrackName = "Teststrecke" })

-- Start
road(track, -30, FIRST_STATION, true)
zone(track, "StartZone", frame(10, 0, 4), Vector3.new(ROAD_WIDTH, 10, 24), COLORS.zone, { "StartZone" })
sign(track, -5, "START  -  R: Checkpoint  ·  T: Neustart  ·  B: Shop")

local stationList = {}
local function station(number: number, title: string, rails: boolean?, build: (s: number) -> ())
	local s = stationStart(number)
	table.insert(stationList, { number = number, title = title, s = s })
	if rails ~= "none" then
		road(track, s, s + STATION_LENGTH, rails ~= false)
	end
	sign(track, s + 4, `{number} · {title}`)
	build(s + STATION_LENGTH / 2)
end

station(1, "Muenzen: einsammeln, oben rechts +1", true, function(s)
	for i = -2, 2 do
		coin(track, frame(s + i * 6, 0, 2.5))
	end
	coin(track, frame(s + 20, 0, 3), 5, 4.5)
end)

station(2, "BoostPad: drueberfahren = Schub", true, function(s)
	part({
		Name = "BoostPad",
		Size = Vector3.new(10, 0.2, 10),
		CFrame = frame(s, 0, 0.05),
		Color = Color3.fromRGB(60, 255, 120),
		Material = Enum.Material.Neon,
		Tags = { "BoostPad" },
		Parent = track,
	})
end)

station(3, "JumpPad: Sprung nach oben", true, function(s)
	part({
		Name = "JumpPad",
		Size = Vector3.new(10, 0.4, 8),
		CFrame = frame(s - 10, 0, 0.1),
		Color = Color3.fromRGB(255, 120, 230),
		Material = Enum.Material.Neon,
		Tags = { "JumpPad" },
		Parent = track,
	})
end)

station(4, "Mud: bremst stark", true, function(s)
	part({
		Name = "Mud",
		Size = Vector3.new(ROAD_WIDTH, 0.3, 24),
		CFrame = frame(s, 0, 0.05),
		Color = Color3.fromRGB(100, 70, 40),
		Material = Enum.Material.Mud,
		Tags = { "Mud" },
		Parent = track,
	})
end)

station(5, "Ice: rutschig, lenkt kaum", true, function(s)
	part({
		Name = "Ice",
		Size = Vector3.new(ROAD_WIDTH, 0.3, 24),
		CFrame = frame(s, 0, 0.05),
		Color = Color3.fromRGB(190, 230, 255),
		Material = Enum.Material.Ice,
		Tags = { "Ice" },
		Parent = track,
	})
end)

station(6, "Bouncy: links gegen die Wand = federt, kein Crash", true, function(s)
	part({
		Name = "BouncyWall",
		Size = Vector3.new(12, 5, 1.5),
		CFrame = frame(s, -7, 2.5) * CFrame.Angles(0, math.rad(25), 0),
		Color = Color3.fromRGB(255, 110, 200),
		Tags = { "Bouncy" },
		Parent = track,
	})
end)

station(7, "Hazard: rechts ins Wasser = Crash", true, function(s)
	part({
		Name = "Wasser",
		Size = Vector3.new(12, 1, 20),
		CFrame = frame(s, 7, 0),
		Color = COLORS.water,
		Transparency = 0.35,
		CanCollide = false,
		Tags = { "Hazard" },
		Attributes = { Message = "Ins Wasser gefallen!" },
		Parent = track,
	})
end)

station(8, "Checkpoint 1: R bringt dich hierher", true, function(s)
	zone(
		track,
		"Checkpoint1",
		frame(s, 0, 6),
		Vector3.new(ROAD_WIDTH, 12, 3),
		COLORS.checkpoint,
		{ "Checkpoint" },
		{ Order = 1 }
	)
end)

station(9, "Mover: Block faehrt quer", true, function(s)
	part({
		Name = "Mover",
		Size = Vector3.new(6, 4, 4),
		CFrame = frame(s, -10, 2),
		Color = Color3.fromRGB(240, 150, 40),
		Tags = { "Mover" },
		Attributes = { Offset = Vector3.new(20, 0, 0), Duration = 2, Pause = 0.5 },
		Parent = track,
	})
end)

station(10, "Spinner: drehender Balken", true, function(s)
	part({
		Name = "Spinner",
		Size = Vector3.new(22, 2, 2),
		CFrame = frame(s, 0, 1.2),
		Color = Color3.fromRGB(220, 60, 60),
		Tags = { "Spinner" },
		Attributes = { Speed = 60 },
		Parent = track,
	})
end)

station(11, "Pendulum: schwingender Block", true, function(s)
	-- Pendel haengt an der Oberkante und schwingt quer (deshalb um 90 Grad gedreht)
	part({
		Name = "Pendulum",
		Size = Vector3.new(3, 14, 3),
		CFrame = frame(s, 0, 9) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(150, 80, 220),
		Tags = { "Pendulum" },
		Attributes = { Angle = 50, Duration = 3 },
		Parent = track,
	})
	part({
		Name = "Balken",
		Size = Vector3.new(ROAD_WIDTH + 4, 1, 1),
		CFrame = frame(s, 0, 16.5),
		Color = COLORS.post,
		CanCollide = false,
		Parent = track,
	})
end)

station(12, "Zufall: eine Seite gesperrt (nach T evtl. die andere)", true, function(s)
	for _, side in { -1, 1 } do
		part({
			Name = if side < 0 then "SperreLinks" else "SperreRechts",
			Size = Vector3.new(13, 4, 1.5),
			CFrame = frame(s, side * 7, 2),
			Color = Color3.fromRGB(255, 80, 60),
			Tags = { "RandomEvent" },
			Attributes = { Group = "Sperre" },
			Parent = track,
		})
	end
end)

station(13, "Launchable: Kuh (links) und Muelltonne (rechts, fliegt ins All)", true, function(s)
	cow(track, frame(s, -6, 0))
	part({
		Name = "Muelltonne",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3.5, 2.6, 2.6),
		CFrame = frame(s, 6, 1.75) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(90, 100, 95),
		Tags = { "Launchable" },
		Attributes = { DisplayName = "Muelltonne", SkyChance = 1, ComicText = "SCHEPPER!" },
		Parent = track,
	})
end)

station(14, "Checkpoint 2", true, function(s)
	zone(
		track,
		"Checkpoint2",
		frame(s, 0, 6),
		Vector3.new(ROAD_WIDTH, 12, 3),
		COLORS.checkpoint,
		{ "Checkpoint" },
		{ Order = 2 }
	)
end)

station(15, "Steinschlag: Trigger ausloesen, Steinen ausweichen", true, function(s)
	zone(
		track,
		"TriggerSteinschlag",
		frame(s - 22, 0, 5),
		Vector3.new(ROAD_WIDTH, 10, 4),
		Color3.fromRGB(255, 70, 90),
		{ "TriggerZone" },
		{ Signal = "Steinschlag1" }
	)
	-- Spawner ueber der Strasse vor dir: Steine fallen auf die Fahrbahn und rollen bergab
	local spawnCF = frame(s + 8, 0, 25) * CFrame.Angles(math.rad(-60), 0, 0)
	part({
		Name = "SpawnerSteinschlag",
		Size = Vector3.new(22, 2, 8),
		CFrame = spawnCF,
		Color = Color3.fromRGB(255, 150, 40),
		Transparency = 0.6,
		CanCollide = false,
		Tags = { "Spawner" },
		Attributes = {
			Template = "Stein1, Stein2",
			ListenSignal = "Steinschlag1",
			Burst = 6,
			Speed = 8,
			SpeedRandom = 3,
			SpreadAngle = 15,
			Spin = 4,
			ScaleRandom = 0.3,
			Hazard = true,
			Message = "Steinschlag!",
			Lifetime = 8,
		},
		Parent = track,
	})
end)

station(16, "Auto-Strom: Autos schubsen dich (kein Crash)", false, function(s)
	-- Spawner links neben der Strasse, schaut quer ueber die Strasse (nach rechts)
	part({
		Name = "SpawnerAutos",
		Size = Vector3.new(6, 4, 2),
		CFrame = frame(s, -22, 2) * CFrame.Angles(0, math.rad(-90), 0),
		Color = Color3.fromRGB(255, 150, 40),
		Transparency = 0.6,
		CanCollide = false,
		Tags = { "Spawner" },
		Attributes = {
			Template = "Auto",
			Kinematic = true,
			Interval = 2.5,
			IntervalRandom = 0.8,
			Speed = 30,
			SpeedRandom = 0,
			SpreadAngle = 0,
			Lifetime = 1.6,
			MaxActive = 4,
			Hazard = false,
		},
		Parent = track,
	})
end)

station(17, "PathMover: Lieferwagen faehrt im Kreis", true, function(s)
	local van = model("Lieferwagen", track, { "PathMover" }, { Loop = true, Speed = 12, WaitAtPoints = 0.5 })
	local body = part({
		Name = "Body",
		Size = Vector3.new(6, 4, 10),
		CFrame = frame(s - 18, -9, 2.5),
		Color = Color3.fromRGB(250, 250, 250),
		Parent = van,
	})
	part({
		Name = "Stripe",
		Size = Vector3.new(6.05, 0.8, 9),
		CFrame = frame(s - 18, -9, 2.5),
		Color = Color3.fromRGB(230, 60, 60),
		Parent = van,
	})
	van.PrimaryPart = body
	local waypoints = Instance.new("Folder")
	waypoints.Name = "Waypoints"
	waypoints.Parent = van
	local points = { { -9, -18 }, { 9, -18 }, { 9, 18 }, { -9, 18 } }
	for index, p in points do
		part({
			Name = tostring(index),
			Size = Vector3.new(1, 1, 1),
			CFrame = frame(s + p[2], p[1], 2.5),
			Color = Color3.fromRGB(60, 220, 230),
			Transparency = 0.5,
			CanCollide = false,
			Parent = waypoints,
		})
	end
end)

station(18, "Gate: Schranke im Takt", true, function(s)
	local gate = model(
		"Schranke",
		track,
		{ "Gate" },
		{ Angle = 80, Axis = "Z", Duration = 1.5, OpenTime = 3, ClosedTime = 3 }
	)
	-- Scharnier = PrimaryPart (bestimmt den Pivot), der Balken reicht von dort nach rechts
	local hinge = part({
		Name = "Scharnier",
		Size = Vector3.new(1, 1, 1),
		CFrame = frame(s, -13, 3),
		Color = Color3.fromRGB(60, 60, 60),
		Parent = gate,
	})
	part({
		Name = "Balken",
		Size = Vector3.new(25, 0.8, 0.8),
		CFrame = frame(s, -13 + 12.5, 3),
		Color = Color3.fromRGB(255, 255, 255),
		Parent = gate,
	})
	gate.PrimaryPart = hinge
	part({
		Name = "Pfosten",
		Size = Vector3.new(1, 3, 1),
		CFrame = frame(s, -13, 1.5),
		Color = Color3.fromRGB(200, 40, 40),
		Parent = track,
	})
end)

station(19, "Abkuerzungs-Tuer: links nur mit Sprungfeder (Bonus-Muenzen)", true, function(s)
	part({
		Name = "Trennwand",
		Size = Vector3.new(1, 5, 40),
		CFrame = frame(s, 0, 2.5),
		Color = COLORS.rail,
		Parent = track,
	})
	part({
		Name = "Tuer",
		Size = Vector3.new(13.5, 7, 1.2),
		CFrame = frame(s - 20, -7, 3.5),
		Color = Color3.fromRGB(120, 80, 50),
		Material = Enum.Material.WoodPlanks,
		Tags = { "UpgradeDoor" },
		Attributes = { RequiredUpgrade = "Spring", RequiredLevel = 1 },
		Parent = track,
	})
	for i = -1, 1 do
		coin(track, frame(s + i * 8, -7, 2.5), 3)
	end
end)

-- Station 20: Einsturz-Bruecke ueber einer Grube (eigene Strasse mit Luecke)
do
	local number = 20
	local s = stationStart(number)
	table.insert(
		stationList,
		{ number = number, title = "Collapse: Bruecke stuerzt nach dem Befahren ein", s = s }
	)
	road(track, s, s + 20, true)
	road(track, s + 50, s + STATION_LENGTH, true)
	sign(track, s + 4, `{number} · Collapse: Bruecke stuerzt nach dem Befahren ein`)
	for i = 0, 5 do
		part({
			Name = "Brett" .. (i + 1),
			Size = Vector3.new(ROAD_WIDTH, 1, 4.8),
			CFrame = frame(s + 22.5 + i * 5, 0, -0.5),
			Color = Color3.fromRGB(150, 110, 70),
			Material = Enum.Material.WoodPlanks,
			Tags = { "Collapse" },
			Attributes = { Delay = 0.4 + i * 0.1 },
			Parent = track,
		})
	end
	part({
		Name = "GrubenWasser",
		Size = Vector3.new(GROUND_WIDTH, 2, 30),
		CFrame = frame(s + 35, 0, -25),
		Color = COLORS.water,
		Transparency = 0.3,
		CanCollide = false,
		Tags = { "Hazard" },
		Attributes = { Message = "In die Grube gefallen!" },
		Parent = track,
	})
	part({
		Name = "GrubenBoden",
		Size = Vector3.new(GROUND_WIDTH, 2, 30),
		CFrame = frame(s + 35, 0, -27),
		Color = Color3.fromRGB(90, 70, 50),
		Parent = track,
	})
end

station(21, "Props: Kisten und Pylonen umfahren (Chaos-Zaehler)", true, function(s)
	local spots =
		{ { -8, -12 }, { -3, -6 }, { 4, -10 }, { 9, -2 }, { -6, 4 }, { 2, 8 }, { 7, 12 }, { -2, 14 } }
	for index, spot in spots do
		local isCone = index % 2 == 0
		part({
			Name = if isCone then "Pylone" else "Kiste",
			Size = if isCone then Vector3.new(1.6, 2.6, 1.6) else Vector3.new(3, 3, 3),
			CFrame = frame(s + spot[2], spot[1], if isCone then 1.3 else 1.5),
			Color = if isCone then Color3.fromRGB(255, 120, 20) else Color3.fromRGB(160, 110, 60),
			Material = if isCone then Enum.Material.SmoothPlastic else Enum.Material.WoodPlanks,
			Tags = { "Prop" },
			Parent = track,
		})
	end
end)

station(22, "ForceZone: Wind drueckt nach rechts (im Takt)", true, function(s)
	part({
		Name = "Wind",
		Size = Vector3.new(ROAD_WIDTH, 10, 30),
		-- Vorderseite zeigt nach rechts (Druckrichtung)
		CFrame = frame(s, 0, 5) * CFrame.Angles(0, math.rad(-90), 0),
		Color = Color3.fromRGB(170, 220, 255),
		Transparency = 0.85,
		CanCollide = false,
		Tags = { "ForceZone" },
		Attributes = { Strength = 70, Pulse = 2, PulseOn = 0.5 },
		Parent = track,
	})
end)

station(23, "Chaser: der Hund rennt dir nach", false, function(s)
	dog(track, frame(s - 10, -24, 0) * CFrame.Angles(0, math.rad(-90), 0))
end)

station(24, "Checkpoint 3", true, function(s)
	zone(
		track,
		"Checkpoint3",
		frame(s, 0, 6),
		Vector3.new(ROAD_WIDTH, 12, 3),
		COLORS.checkpoint,
		{ "Checkpoint" },
		{ Order = 3 }
	)
end)

station(25, "ZIEL: Noten 6 / 5 / 4 / 3 / 2 bis 50 / 65 / 80 / 100 / 130 s", true, function(s)
	zone(
		track,
		"FinishZone",
		frame(s, 0, 5),
		Vector3.new(ROAD_WIDTH, 10, 10),
		Color3.fromRGB(255, 220, 80),
		{ "FinishZone" },
		{
			Grade6 = 50,
			Grade5 = 65,
			Grade4 = 80,
			Grade3 = 100,
			Grade2 = 130,
		}
	)
end)

-- Auslauf hinter dem Ziel und eine Platzhalter-Schule
do
	local s = stationStart(26)
	road(track, s, s + 120, true)
	part({
		Name = "Schule",
		Size = Vector3.new(80, 30, 20),
		CFrame = frame(s + 110, 0, 15),
		Color = Color3.fromRGB(200, 120, 90),
		Material = Enum.Material.Brick,
		Parent = track,
	})
	sign(track, s + 4, "Geschafft! Gleich startet der naechste Lauf (oder T)")
	-- Bestenlisten an der Schulwand (Tag "Leaderboard", zeigen zum ankommenden Fahrer)
	for _, info in { { x = -18, board = "Track1" }, { x = 18, board = "Flight" } } do
		part({
			Name = "Bestenliste_" .. info.board,
			Size = Vector3.new(22, 16, 0.5),
			CFrame = frame(s + 99.5, info.x, 14),
			Color = Color3.fromRGB(28, 60, 40),
			CanCollide = false,
			Tags = { "Leaderboard" },
			Attributes = { Board = info.board, Face = "Back" },
			Parent = track,
		})
	end
	-- Gesamtmeter aller Spieler (oben in der Mitte)
	part({
		Name = "Bestenliste_Meters",
		Size = Vector3.new(22, 16, 0.5),
		CFrame = frame(s + 99.5, 0, 31),
		Color = Color3.fromRGB(28, 60, 40),
		CanCollide = false,
		Tags = { "Leaderboard" },
		Attributes = { Board = "Meters", Face = "Back" },
		Parent = track,
	})
end

------------------------------------------------------------------------------------------
-- Testflaeche fuer Lenkung und Drift (eigene Strecke, im Menue B -> Strecken)
------------------------------------------------------------------------------------------
local flat =
	model("Testflaeche", nil, nil, { TrackId = "Testflaeche", TrackName = "Testflaeche (Lenkung & Drift)" })
local FLAT_CENTER = Vector3.new(-700, 40, 0)
part({
	Name = "Boden",
	Size = Vector3.new(500, 4, 500),
	CFrame = CFrame.new(FLAT_CENTER - Vector3.new(0, 2, 0)),
	Color = Color3.fromRGB(110, 110, 118),
	Material = Enum.Material.Concrete,
	Parent = flat,
})
part({
	Name = "StartZone",
	Size = Vector3.new(24, 10, 20),
	CFrame = CFrame.new(FLAT_CENTER + Vector3.new(0, 4, 200)),
	Color = COLORS.zone,
	Transparency = 0.8,
	CanCollide = false,
	Tags = { "StartZone" },
	Parent = flat,
})
part({
	Name = "FinishZone",
	Size = Vector3.new(60, 10, 10),
	CFrame = CFrame.new(FLAT_CENTER + Vector3.new(0, 4, -235)),
	Color = Color3.fromRGB(255, 220, 80),
	Transparency = 0.8,
	CanCollide = false,
	Tags = { "FinishZone" },
	Parent = flat,
})
-- Slalom (Pylonen sind Props: umfahren erlaubt, kein Crash)
for i = 0, 7 do
	part({
		Name = "SlalomPylone",
		Size = Vector3.new(1.6, 2.6, 1.6),
		CFrame = CFrame.new(FLAT_CENTER + Vector3.new(if i % 2 == 0 then -8 else 8, 1.3, 150 - i * 30)),
		Color = Color3.fromRGB(255, 120, 20),
		Tags = { "Prop" },
		Parent = flat,
	})
end
-- Kuh-Kombo: vier Kuehe hintereinander (alle in 2,5 s treffen = 4x KOMBO)
for i = 0, 3 do
	cow(flat, CFrame.new(FLAT_CENTER + Vector3.new(-60, 0, 120 - i * 30)))
end
-- Trick-Schanze links: JumpPad (Sprung ~19 Studs), Lufttricks mit Q/E
part({
	Name = "TrickJumpPad",
	Size = Vector3.new(12, 0.4, 10),
	CFrame = CFrame.new(FLAT_CENTER + Vector3.new(-120, 0.2, 60)),
	Color = Color3.fromRGB(255, 120, 230),
	Material = Enum.Material.Neon,
	Tags = { "JumpPad" },
	Parent = flat,
})
-- Drift-Kreis (aufgemalt)
for i = 0, 23 do
	local angle = i / 24 * math.pi * 2
	local radius = 45
	part({
		Name = "KreisMarke",
		Size = Vector3.new(2, 0.1, 6),
		CFrame = CFrame.new(
			FLAT_CENTER + Vector3.new(120 + math.cos(angle) * radius, 0.05, math.sin(angle) * radius)
		) * CFrame.Angles(0, -angle, 0),
		Color = Color3.fromRGB(255, 255, 255),
		CanCollide = false,
		Parent = flat,
	})
end
do
	local board = part({
		Name = "Schild",
		Size = Vector3.new(30, 8, 0.4),
		CFrame = CFrame.new(FLAT_CENTER + Vector3.new(-30, 6, 180)),
		Color = COLORS.sign,
		CanCollide = false,
		Parent = flat,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.FontFace = roblox.Font.fromEnum(Enum.Font.GothamBold)
	label.TextScaled = true
	label.TextWrapped = true
	label.Text =
		"Testflaeche: A/D = Drift (Standard) · Shift halten = normal lenken · Leertaste = Hopp · Slalom geradeaus, Drift-Kreis rechts, Trick-Schanze links (Q/E in der Luft), Kuh-Reihe fuer die Kombo · T = Start"
	label.Parent = gui
end

------------------------------------------------------------------------------------------
-- Vorlagen (ReplicatedStorage/Templates)
------------------------------------------------------------------------------------------
local templates = Instance.new("Folder")
templates.Name = "Templates"
part({
	Name = "Stein1",
	Shape = Enum.PartType.Ball,
	Size = Vector3.new(4, 4, 4),
	CFrame = CFrame.new(0, 10, 0),
	Color = Color3.fromRGB(120, 115, 110),
	Material = Enum.Material.Slate,
	Parent = templates,
})
part({
	Name = "Stein2",
	Shape = Enum.PartType.Ball,
	Size = Vector3.new(2.6, 2.6, 2.6),
	CFrame = CFrame.new(5, 10, 0),
	Color = Color3.fromRGB(100, 95, 90),
	Material = Enum.Material.Slate,
	Parent = templates,
})
car(templates, CFrame.new(10, 10, 0), "Auto", Color3.fromRGB(220, 40, 40))

-- SpawnLocation neben dem Start
local spawnLocation = Instance.new("SpawnLocation")
spawnLocation.Name = "SpawnLocation"
spawnLocation.Anchored = true
spawnLocation.Size = Vector3.new(8, 1, 8)
spawnLocation.CFrame = frame(5, -40, 0.5)
spawnLocation.Neutral = true
spawnLocation.Duration = 0

-- Dateien schreiben
fs.writeDir("test")
fs.writeFile("test/TestTrack.rbxm", roblox.serializeModel({ track }))
fs.writeFile("test/Testflaeche.rbxm", roblox.serializeModel({ flat }))
fs.writeFile("test/Templates.rbxm", roblox.serializeModel({ templates }))
fs.writeFile("test/SpawnLocation.rbxm", roblox.serializeModel({ spawnLocation }))

-- test.project.json = default.project.json + Teststrecke + Vorlagen
local project = serde.decode("json", fs.readFile("default.project.json"))
project.name = "GetToSchoolTest"
local tree = project.tree
tree.ReplicatedStorage.Templates = { ["$path"] = "test/Templates.rbxm" }
tree.Workspace = {
	["$className"] = "Workspace",
	["$ignoreUnknownInstances"] = true,
	TestTrack = { ["$path"] = "test/TestTrack.rbxm" },
	Testflaeche = { ["$path"] = "test/Testflaeche.rbxm" },
	SpawnLocation = { ["$path"] = "test/SpawnLocation.rbxm" },
}
fs.writeFile("test.project.json", serde.encode("json", project, true) .. "\n")

-- Stationen (fuer die Checkliste im README)
print("Stationen:")
table.sort(stationList, function(a, b)
	return a.number < b.number
end)
for _, entry in stationList do
	print(`  {entry.number}. {entry.title}`)
end
print("Fertig: test/*.rbxm und test.project.json geschrieben.")
