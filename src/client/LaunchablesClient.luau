--!strict
-- Launchables (Tag "Launchable"), Client-Seite: Treffer erkennen und die grosse Show.
--   * Faehrt der eigene Wagen in ein Objekt: sofort Comic-Text ("BONK!"), Sound, Hit-Stop
--     und Kamera-Wackeln (macht CartClient), Objekt bei uns ausblenden, Server fragen.
--   * Der Server plant den Flug und schickt ihn zurueck ("Launch"). Wir spielen ihn mit
--     einer Kopie des Objekts ab: wilde Drehung, Luftspur, hochzaehlende Flugweite.
--     Himmelsfluege verschwinden mit einem Stern-Blinken.
--   * Kompletter Neustart (T): alle Objekte stehen wieder.
-- Die Kopie fliegt nur bei uns; andere Spieler sehen das Objekt weiter an seinem Platz.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local LaunchMath =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"):WaitForChild("LaunchMath"))
local TagList = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TagList"))
local LocalHide = require(script.Parent:WaitForChild("LocalHide"))
local SoundSystem = require(script.Parent:WaitForChild("SoundSystem"))
local TrackSensors = require(script.Parent:WaitForChild("TrackSensors"))

local hitRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("HitLaunchable") :: RemoteEvent

local LaunchablesClient = {}

-- Vom Server geplanter Flug (siehe server/Launchables.luau)
export type LaunchInfo = {
	direction: Vector3,
	flight: LaunchMath.Flight,
	spin: number,
	name: string,
	meters: number,
	bonus: number,
	isRecord: boolean,
}

type Pending = {
	ghost: PVInstance, -- Kopie, die gleich fliegt
	home: CFrame,
	hitAt: number,
}

type Flying = {
	model: PVInstance,
	parts: { BasePart },
	home: CFrame,
	info: LaunchInfo,
	spinAxis: Vector3,
	t: number,
	landed: boolean,
}

local hitIds: { [string]: boolean } = {} -- in diesem Lauf getroffen
local retryAfter: { [string]: number } = {}
local pending: { [Instance]: Pending } = {}
local flying: { Flying } = {}
local labelFlight: Flying? = nil -- dessen Flugweite gerade angezeigt wird
local effectsFolder: Folder? = nil
local flightLabel: TextLabel
local labelToken = 0

local STAR_IMAGE = "rbxasset://textures/particles/sparkles_main.dds" -- in Roblox eingebaut

local function getEffectsFolder(): Folder
	local folder = effectsFolder
	if folder and folder.Parent then
		return folder
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "LocalLaunchEffects" -- existiert nur auf diesem Client
	newFolder.Parent = workspace
	effectsFolder = newFolder
	return newFolder
end

local function getCFrame(instance: PVInstance): CFrame
	if instance:IsA("BasePart") then
		return instance.CFrame
	end
	return instance:GetPivot()
end

local function setCFrame(instance: PVInstance, cframe: CFrame)
	if instance:IsA("BasePart") then
		instance.CFrame = cframe
	elseif instance:IsA("Model") then
		instance:PivotTo(cframe)
	end
end

local function allParts(instance: Instance): { BasePart }
	local parts: { BasePart } = {}
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end
	for _, item in instance:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(parts, item)
		end
	end
	return parts
end

-- Kopie zum Fliegen: ohne Tags (sonst waere sie selbst ein Baustein), ohne Kollision
local function makeGhost(object: Instance): PVInstance?
	local instance: Instance = object
	if not (object:IsA("BasePart") or object:IsA("Model")) then
		return nil
	end
	local wasArchivable = instance.Archivable
	instance.Archivable = true -- nur Archivable-Objekte lassen sich kopieren
	local ghost = instance:Clone() :: PVInstance
	instance.Archivable = wasArchivable
	for _, item in { ghost :: Instance, table.unpack(ghost:GetDescendants()) } do
		for _, tag in item:GetTags() do
			CollectionService:RemoveTag(item, tag)
		end
		if item:IsA("Script") or item:IsA("LocalScript") then
			item:Destroy()
		end
	end
	for _, part in allParts(ghost) do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end
	return ghost
end

-- Unsichtbares Hilfs-Part fuer Anzeigen in der Welt (BillboardGui braucht einen Ort)
local function anchorPart(position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = "EffectAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.Position = position
	part.Parent = getEffectsFolder()
	return part
end

-- Comic-Text am Treffpunkt: ploppt auf, steigt, verblasst
local function showComicText(position: Vector3, text: string)
	local anchor = anchorPart(position)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(260, 110)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = anchor
	billboard.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = Color3.fromHSV(math.random() * 0.15, 0.85, 1) -- gelb bis rot
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.Rotation = math.random(-14, 14)
	label.Parent = billboard
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1.15,
	}):Play()
	TweenService:Create(billboard, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, 4, 0),
	}):Play()
	task.delay(0.6, function()
		TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 })
			:Play()
	end)
	task.delay(1.1, function()
		anchor:Destroy()
	end)
end

-- Stern-Blinken, wenn ein Objekt im Himmel verschwindet (wie Team Rocket)
local function showStar(position: Vector3)
	local anchor = anchorPart(position)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(90, 90)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = anchor
	billboard.Parent = anchor
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromScale(0, 0)
	image.Image = STAR_IMAGE
	image.ImageColor3 = Color3.fromRGB(255, 250, 200)
	image.Parent = billboard
	local grow =
		TweenService:Create(image, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(1, 1),
			Rotation = 90,
		})
	grow.Completed:Once(function()
		TweenService:Create(image, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.fromScale(0, 0),
			Rotation = 180,
		}):Play()
	end)
	grow:Play()
	SoundSystem.play("SkyStar")
	task.delay(0.7, function()
		anchor:Destroy()
	end)
end

-- Luftspur hinter dem fliegenden Objekt
local function addTrail(model: PVInstance)
	local main: BasePart? = if model:IsA("BasePart") then model else nil
	if not main and model:IsA("Model") then
		main = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not main then
		return
	end
	local height = math.max(main.Size.Y, 1)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, height / 2, 0)
	a0.Parent = main
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -height / 2, 0)
	a1.Parent = main
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.7
	trail.FaceCamera = true
	trail.LightEmission = 0.5
	trail.Transparency = NumberSequence.new(0.25, 1)
	trail.Parent = main
end

-- Flugweite oben in der Mitte anzeigen
local function setLabel(text: string, color: Color3?)
	labelToken += 1
	flightLabel.Text = text
	flightLabel.TextColor3 = color or Color3.new(1, 1, 1)
	flightLabel.Visible = true
end

local function hideLabelLater(seconds: number)
	labelToken += 1
	local token = labelToken
	task.delay(seconds, function()
		if labelToken == token then
			flightLabel.Visible = false
		end
	end)
end

local function finalText(flight: Flying): string
	local info = flight.info
	local text = `{info.name}: {info.meters} m!`
	if info.flight.sky then
		text ..= "  Ab ins All!"
	end
	if info.isRecord then
		text ..= "  NEUER REKORD!"
	end
	if info.bonus > 0 then
		text ..= `  +{info.bonus} Muenzen`
	end
	return text
end

-- Jeden Frame waehrend der Fahrt: Beruehrt der Wagen ein Launchable?
-- `onHit` macht die Fahr-Effekte (Hit-Stop, Kamera), siehe CartClient.
function LaunchablesClient.update(cart: Model, base: BasePart, onHit: () -> ())
	local object = TrackSensors.touching(cart, "Launchable")
	if not object then
		return
	end
	local id = object:GetAttribute("LaunchId")
	if type(id) ~= "string" or hitIds[id] or (retryAfter[id] or 0) > os.clock() then
		return
	end
	hitIds[id] = true
	local ghost = makeGhost(object) -- vor dem Ausblenden kopieren (sonst ist die Kopie unsichtbar)
	if ghost then
		pending[object] = { ghost = ghost, home = getCFrame(ghost), hitAt = os.clock() }
	end
	LocalHide.set(object, "Launched", true)
	hitRemote:FireServer(object)

	-- Show sofort, ohne auf den Server zu warten
	local center = if ghost then getCFrame(ghost).Position else base.Position
	local comic = object:GetAttribute("ComicText")
	local texts = Config.Launch.ComicTexts
	local text = if type(comic) == "string" and comic ~= "" then comic else texts[math.random(1, #texts)]
	showComicText((center + base.Position) / 2 + Vector3.new(0, 3, 0), text)
	SoundSystem.playId(object:GetAttribute("Sound"), Config.Sounds.Launch.Volume, "Launch")
	onHit()
end

-- Server hat den Flug geplant: Kopie fliegen lassen
function LaunchablesClient.onLaunch(object: Instance, info: LaunchInfo)
	local entry = pending[object]
	pending[object] = nil
	if not entry then
		return
	end
	local model = entry.ghost
	model.Parent = getEffectsFolder()
	addTrail(model)
	local axis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	local flight: Flying = {
		model = model,
		parts = allParts(model),
		home = entry.home,
		info = info,
		spinAxis = if axis.Magnitude > 0.01 then axis.Unit else Vector3.xAxis,
		t = 0,
		landed = false,
	}
	table.insert(flying, flight)
	labelFlight = flight
	setLabel(`{info.name}: 0 m`)
end

-- Server hat den Treffer nicht anerkannt: Objekt wieder zeigen
function LaunchablesClient.onRejected(object: Instance)
	local entry = pending[object]
	pending[object] = nil
	if entry then
		entry.ghost:Destroy()
	end
	if typeof(object) == "Instance" then
		local id = object:GetAttribute("LaunchId")
		if type(id) == "string" then
			hitIds[id] = nil
			retryAfter[id] = os.clock() + 1
		end
		LocalHide.set(object, "Launched", false)
	end
end

-- Kompletter Neustart: alle Objekte stehen wieder, fliegende Kopien weg
function LaunchablesClient.resetAll()
	table.clear(hitIds)
	table.clear(retryAfter)
	for _, entry in pending do
		entry.ghost:Destroy()
	end
	table.clear(pending)
	for _, flight in flying do
		flight.model:Destroy()
	end
	table.clear(flying)
	labelFlight = nil
	for _, object in TagList.get("Launchable") do
		LocalHide.set(object, "Launched", false)
	end
end

local function updateFlights(dt: number)
	local L = Config.Launch
	local studsToMeters = Config.UI.StudsToMeters
	for index = #flying, 1, -1 do
		local flight = flying[index]
		flight.t += dt
		local info = flight.info
		if not flight.landed then
			local along, up = LaunchMath.offset(info.flight, flight.t)
			local position = flight.home.Position + info.direction * along + Vector3.yAxis * up
			local rotation = CFrame.fromAxisAngle(flight.spinAxis, info.spin * flight.t)
				* flight.home.Rotation
			setCFrame(flight.model, CFrame.new(position) * rotation)
			if labelFlight == flight then
				local meters = LaunchMath.meters(LaunchMath.distanceAt(info.flight, flight.t), studsToMeters)
				setLabel(`{info.name}: {meters} m`)
			end
			if flight.t >= info.flight.duration then
				flight.landed = true
				if labelFlight == flight then
					setLabel(finalText(flight), if info.isRecord then Color3.fromRGB(255, 215, 80) else nil)
					hideLabelLater(2.5)
				end
				if info.flight.sky then
					showStar(position)
					flight.model:Destroy()
					table.remove(flying, index)
				end
			end
		else
			-- gelandet: kurz liegen lassen, dann ausblenden
			local lying = flight.t - info.flight.duration
			local fade = math.clamp((lying - L.LandedTime) / 0.5, 0, 1)
			for _, part in flight.parts do
				part.LocalTransparencyModifier = fade
			end
			if fade >= 1 then
				flight.model:Destroy()
				table.remove(flying, index)
			end
		end
	end
	-- Kopien ohne Antwort vom Server (z. B. verlorene Nachricht) aufraeumen
	for object, entry in pending do
		if os.clock() - entry.hitAt > 5 then
			entry.ghost:Destroy()
			pending[object] = nil
		end
	end
end

function LaunchablesClient.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "LaunchUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	flightLabel = Instance.new("TextLabel")
	flightLabel.Name = "FlightDistance"
	flightLabel.AnchorPoint = Vector2.new(0.5, 0)
	flightLabel.Position = UDim2.new(0.5, 0, 0, 165)
	flightLabel.Size = UDim2.fromOffset(560, 40)
	flightLabel.BackgroundTransparency = 1
	flightLabel.Font = Enum.Font.LuckiestGuy
	flightLabel.TextScaled = true
	flightLabel.TextColor3 = Color3.new(1, 1, 1)
	flightLabel.TextStrokeTransparency = 0
	flightLabel.Text = ""
	flightLabel.Visible = false
	flightLabel.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	RunService.RenderStepped:Connect(updateFlights)
end

return LaunchablesClient
