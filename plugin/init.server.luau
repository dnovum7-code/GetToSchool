--!strict
-- Bau-Hilfe fuer Studio (Plugin): zeigt im Bearbeitungsmodus Richtungen, Bereiche und Wege
-- der Bausteine als Pfeile, Kaesten und Linien. Im Spiel (Play) zeigt es nichts.
-- Installieren/aktualisieren: siehe README, Abschnitt "Bau-Hilfe (Studio-Plugin)".
--
-- Farben:
--   orange  Spawner (Spawn-Bereich, Richtung, Streuung)
--   gruen   BoostPad (Schub), JumpPad (nach oben)
--   weiss   StartZone (Vorderseite)
--   lila    Mover (Weg bis Offset)
--   tuerkis PathMover (Wegpunkte und Weg)
--   gelb    Gate (Lage im geoeffneten Zustand)
--   blau    ForceZone (Bereich und Richtung)
--   rot     TriggerZone (Bereich, Name des Signals)
--   braun   Chaser (Radius, ab dem er losrennt)
--   gelb    UpgradeDoor (welches Upgrade die Abkuerzungs-Tuer braucht)
-- Bausteine mit ListenSignal zeigen "hoert: <Signal>".
--
-- Unity-Vergleich: wie OnDrawGizmos, nur als Plugin (Spiel-Skripte laufen in Studio nicht,
-- solange man baut).

local CollectionService = game:GetService("CollectionService")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Im laufenden Spiel (Play-Test) nichts anzeigen
if RunService:IsRunning() then
	return
end

local COLORS = {
	Spawner = Color3.fromRGB(255, 150, 40),
	Pad = Color3.fromRGB(80, 230, 110),
	Start = Color3.fromRGB(255, 255, 255),
	Mover = Color3.fromRGB(190, 110, 255),
	Path = Color3.fromRGB(60, 220, 230),
	Gate = Color3.fromRGB(255, 220, 60),
	Force = Color3.fromRGB(70, 140, 255),
	Trigger = Color3.fromRGB(255, 70, 90),
	Chaser = Color3.fromRGB(170, 110, 60),
	Label = Color3.fromRGB(255, 255, 255),
}

-- Standardwerte aus der Config des Spiels (falls lesbar)
local config: any = nil
pcall(function()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild("Config")
	if module and module:IsA("ModuleScript") then
		config = (require :: any)(module)
	end
end)

local function default(section: string, key: string, fallback: any): any
	local sectionTable = config and config[section]
	local value = if type(sectionTable) == "table" then sectionTable[key] else nil
	return if value ~= nil then value else fallback
end

local function numberAttr(instance: Instance, name: string, fallback: number): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local toolbar = plugin:CreateToolbar("Get to School")
local button = toolbar:CreateButton(
	"Bau-Hilfe",
	"Richtungen, Bereiche und Wege der Bausteine anzeigen (nur beim Bauen)",
	"rbxasset://textures/ui/GuiImagePlaceholder.png"
)
button.ClickableWhenViewportHidden = true

local enabled = plugin:GetSetting("Enabled") ~= false
button:SetActive(enabled)

local folder = Instance.new("Folder")
folder.Name = "GetToSchoolBauhilfe"
folder.Parent = CoreGui

-- Wiederverwendbare Zeichen-Objekte (statt jedes Mal neu erzeugen)
type Pool = { items: { Instance }, used: number }
local pools: { [string]: Pool } = {}

local function take(className: string): any
	local pool = pools[className]
	if not pool then
		pool = { items = {}, used = 0 }
		pools[className] = pool
	end
	pool.used += 1
	local item: any = pool.items[pool.used]
	if not item then
		item = (Instance.new :: any)(className)
		if item:IsA("HandleAdornment") then
			item.Adornee = workspace.Terrain -- Terrain liegt im Ursprung: Lagen = Welt-Lagen
			item.AlwaysOnTop = true
			item.ZIndex = 1
		end
		item.Parent = folder
		table.insert(pool.items, item)
	end
	if item:IsA("HandleAdornment") then
		item.Visible = true
	elseif item:IsA("BillboardGui") then
		item.Enabled = true
	end
	return item
end

local function beginFrame()
	for _, pool in pools do
		pool.used = 0
	end
end

local function endFrame()
	for _, pool in pools do
		for index = pool.used + 1, #pool.items do
			local item = pool.items[index]
			if item:IsA("HandleAdornment") then
				item.Visible = false
			elseif item:IsA("BillboardGui") then
				item.Enabled = false
			end
		end
	end
end

local function line(from: Vector3, to: Vector3, color: Color3, thickness: number?)
	local length = (to - from).Magnitude
	if length < 0.01 then
		return
	end
	local adorn = take("LineHandleAdornment") :: LineHandleAdornment
	adorn.CFrame = CFrame.lookAt(from, to)
	adorn.Length = length
	adorn.Thickness = thickness or 3
	adorn.Color3 = color
	adorn.Transparency = 0
end

-- Pfeil von `from` in Richtung `direction` (Laenge = Laenge des Vektors)
local function arrow(from: Vector3, direction: Vector3, color: Color3)
	local length = direction.Magnitude
	if length < 0.01 then
		return
	end
	local to = from + direction
	line(from, to, color, 4)
	local back = -direction.Unit * math.min(2.5, length * 0.35)
	local side = direction.Unit:Cross(Vector3.yAxis)
	if side.Magnitude < 0.1 then
		side = direction.Unit:Cross(Vector3.xAxis)
	end
	side = side.Unit * math.min(1.2, length * 0.2)
	line(to, to + back + side, color, 4)
	line(to, to + back - side, color, 4)
end

local function box(cframe: CFrame, size: Vector3, color: Color3, transparency: number?)
	local adorn = take("BoxHandleAdornment") :: BoxHandleAdornment
	adorn.CFrame = cframe
	adorn.Size = size
	adorn.Color3 = color
	adorn.Transparency = transparency or 0.75
end

local function ball(position: Vector3, radius: number, color: Color3)
	local adorn = take("SphereHandleAdornment") :: SphereHandleAdornment
	adorn.CFrame = CFrame.new(position)
	adorn.Radius = radius
	adorn.Color3 = color
	adorn.Transparency = 0.2
end

local function ring(center: Vector3, radius: number, color: Color3)
	local adorn = take("CylinderHandleAdornment") :: CylinderHandleAdornment
	-- Zylinder-Achse ist Z: um 90 Grad kippen, damit der Ring flach liegt
	adorn.CFrame = CFrame.new(center) * CFrame.Angles(math.rad(90), 0, 0)
	adorn.Radius = radius
	adorn.InnerRadius = math.max(radius - 0.4, 0)
	adorn.Height = 0.2
	adorn.Color3 = color
	adorn.Transparency = 0.3
end

local function label(part: BasePart, text: string, color: Color3?)
	local gui = take("BillboardGui") :: BillboardGui
	gui.Adornee = part
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(220, 22)
	gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 2, 0)
	gui.LightInfluence = 0
	local text_ = gui:FindFirstChild("Text") :: TextLabel?
	if not text_ then
		local newLabel = Instance.new("TextLabel")
		newLabel.Name = "Text"
		newLabel.BackgroundTransparency = 1
		newLabel.Size = UDim2.fromScale(1, 1)
		newLabel.Font = Enum.Font.GothamBold
		newLabel.TextScaled = true
		newLabel.TextStrokeTransparency = 0.3
		newLabel.Parent = gui
		text_ = newLabel
	end
	local textLabel = text_ :: TextLabel
	textLabel.Text = text
	textLabel.TextColor3 = color or COLORS.Label
end

-- Haupt-Part eines Bausteins (Part selbst oder PrimaryPart/erstes Part im Modell)
local function mainPart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	elseif instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function pivotOf(instance: Instance): CFrame?
	if instance:IsA("PVInstance") then
		return (instance :: PVInstance):GetPivot()
	end
	return nil
end

local function tagged(tag: string): { Instance }
	local result = {}
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsDescendantOf(workspace) then
			table.insert(result, instance)
		end
	end
	return result
end

local function drawListen(instance: Instance)
	local signal = instance:GetAttribute("ListenSignal")
	local part = mainPart(instance)
	if type(signal) == "string" and signal ~= "" and part then
		label(part, "hoert: " .. signal, COLORS.Trigger)
	end
end

local function draw()
	beginFrame()

	for _, instance in tagged("Spawner") do
		if instance:IsA("BasePart") then
			local cf = instance.CFrame
			box(cf, instance.Size, COLORS.Spawner, 0.7)
			local speed = numberAttr(instance, "Speed", default("Spawner", "Speed", 30))
			local length = math.clamp(speed * 0.3, 6, 30)
			arrow(cf.Position, cf.LookVector * length, COLORS.Spawner)
			local spread =
				math.rad(numberAttr(instance, "SpreadAngle", default("Spawner", "SpreadAngle", 10)))
			if spread > 0.01 then
				for _, sign in { -1, 1 } do
					local dir = (cf.Rotation * CFrame.Angles(0, sign * spread, 0)).LookVector
					line(cf.Position, cf.Position + dir * length * 0.8, COLORS.Spawner, 1)
				end
			end
			local template = instance:GetAttribute("Template")
			local listen = instance:GetAttribute("ListenSignal")
			local text = "Spawner: "
				.. (if type(template) == "string" and template ~= "" then template else "?")
			if type(listen) == "string" and listen ~= "" then
				text ..= "  (hoert: " .. listen .. ")"
			end
			label(instance, text, COLORS.Spawner)
		end
	end

	for _, instance in tagged("BoostPad") do
		local cf = pivotOf(instance)
		if cf then
			arrow(cf.Position + cf.UpVector, cf.LookVector * 8, COLORS.Pad)
		end
	end
	for _, instance in tagged("JumpPad") do
		local cf = pivotOf(instance)
		if cf then
			arrow(cf.Position, cf.UpVector * 8, COLORS.Pad)
		end
	end
	for _, instance in tagged("StartZone") do
		local cf = pivotOf(instance)
		if cf then
			arrow(cf.Position, cf.LookVector * 10, COLORS.Start)
		end
	end

	for _, instance in tagged("Mover") do
		local cf = pivotOf(instance)
		if cf then
			local offset = instance:GetAttribute("Offset")
			local vector = if typeof(offset) == "Vector3"
				then offset
				else default("Movers", "MoverOffset", Vector3.new(0, 0, -30))
			local to = (cf * CFrame.new(vector)).Position
			line(cf.Position, to, COLORS.Mover, 3)
			ball(to, 0.8, COLORS.Mover)
		end
	end

	for _, instance in tagged("PathMover") do
		local waypoints = instance:FindFirstChild("Waypoints")
		local points: { { n: number, part: BasePart } } = {}
		if waypoints then
			for _, child in waypoints:GetChildren() do
				local n = tonumber(child.Name)
				if n and child:IsA("BasePart") then
					table.insert(points, { n = n, part = child })
				end
			end
		end
		table.sort(points, function(a, b)
			return a.n < b.n
		end)
		for index, entry in points do
			ball(entry.part.Position, 0.7, COLORS.Path)
			label(entry.part, tostring(entry.n), COLORS.Path)
			local nextEntry = points[index + 1]
			if nextEntry then
				arrow(entry.part.Position, nextEntry.part.Position - entry.part.Position, COLORS.Path)
			end
		end
		local loop = instance:GetAttribute("Loop")
		if (loop == true or (loop == nil and default("PathMover", "Loop", false))) and #points > 2 then
			line(points[#points].part.Position, points[1].part.Position, COLORS.Path, 2)
		end
		local part = mainPart(instance)
		if part and #points < 2 then
			label(part, "PathMover: Ordner Waypoints mit Parts 1, 2, ... fehlt", COLORS.Trigger)
		end
		drawListen(instance)
	end

	for _, instance in tagged("Gate") do
		local home = pivotOf(instance)
		if home and instance:IsA("PVInstance") then
			local offset = instance:GetAttribute("Offset")
			local vector = if typeof(offset) == "Vector3" then offset else Vector3.zero
			local angle = math.rad(numberAttr(instance, "Angle", default("Gate", "Angle", 0)))
			local axisAttr = instance:GetAttribute("Axis")
			local axis =
				string.upper(if type(axisAttr) == "string" then axisAttr else default("Gate", "Axis", "X"))
			local rotation = if axis == "Y"
				then CFrame.Angles(0, angle, 0)
				elseif axis == "Z" then CFrame.Angles(0, 0, angle)
				else CFrame.Angles(angle, 0, 0)
			local open = home * CFrame.new(vector) * rotation
			local bbCFrame, bbSize
			if instance:IsA("Model") then
				bbCFrame, bbSize = instance:GetBoundingBox()
			elseif instance:IsA("BasePart") then
				bbCFrame, bbSize = instance.CFrame, instance.Size
			end
			if bbCFrame and bbSize then
				box(open * home:ToObjectSpace(bbCFrame), bbSize, COLORS.Gate, 0.6)
			end
			ball(home.Position, 0.6, COLORS.Gate)
			drawListen(instance)
		end
	end

	for _, instance in tagged("ForceZone") do
		if instance:IsA("BasePart") then
			box(instance.CFrame, instance.Size, COLORS.Force, 0.8)
			arrow(
				instance.Position,
				instance.CFrame.LookVector * math.clamp(instance.Size.Magnitude * 0.4, 5, 25),
				COLORS.Force
			)
			drawListen(instance)
		end
	end

	for _, instance in tagged("TriggerZone") do
		if instance:IsA("BasePart") then
			box(instance.CFrame, instance.Size, COLORS.Trigger, 0.75)
			local signal = instance:GetAttribute("Signal")
			label(
				instance,
				"Signal: " .. (if type(signal) == "string" and signal ~= "" then signal else "FEHLT"),
				COLORS.Trigger
			)
		end
	end

	for _, instance in tagged("Chaser") do
		local cf = pivotOf(instance)
		if cf then
			local radius = numberAttr(instance, "Radius", default("Chaser", "Radius", 40))
			ring(cf.Position, radius, COLORS.Chaser)
			arrow(cf.Position, cf.LookVector * 5, COLORS.Chaser)
			drawListen(instance)
		end
	end

	for _, tag in { "Collapse" } do
		for _, instance in tagged(tag) do
			drawListen(instance)
		end
	end

	for _, instance in tagged("UpgradeDoor") do
		local part = mainPart(instance)
		if part then
			local upgrade = instance:GetAttribute("RequiredUpgrade")
			local level = numberAttr(instance, "RequiredLevel", 1)
			label(
				part,
				"Tuer: braucht "
					.. (if type(upgrade) == "string" and upgrade ~= "" then upgrade else "FEHLT")
					.. " Stufe "
					.. tostring(level),
				COLORS.Gate
			)
		end
	end

	endFrame()
end

local function clear()
	beginFrame()
	endFrame()
end

button.Click:Connect(function()
	enabled = not enabled
	plugin:SetSetting("Enabled", enabled)
	button:SetActive(enabled)
	if not enabled then
		clear()
	end
end)

local running = true
plugin.Unloading:Connect(function()
	running = false
	folder:Destroy()
end)

-- Regelmaessig neu zeichnen (Teile werden beim Bauen ja verschoben)
task.spawn(function()
	while running do
		if enabled then
			xpcall(draw, function(err)
				warn("[Bau-Hilfe] " .. tostring(err))
			end)
		end
		task.wait(0.25)
	end
end)
