--!strict
-- Geist vom besten Lauf, Client-Seite: spielt die Aufnahme des besten Laufs dieser Strecke
-- als halbdurchsichtigen Wagen ab, ab dem Moment, in dem der Lauf startet. Nur bei dir.
-- Abschaltbar in den Einstellungen ("Geist").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GhostCodec =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"):WaitForChild("GhostCodec"))
local RaceTime = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RaceTime"))
local Vehicles = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Vehicles"))
local Settings = require(script.Parent:WaitForChild("Settings"))

local ghostRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Ghost") :: RemoteEvent

local GhostClient = {}

type Loaded = {
	samples: { GhostCodec.Sample },
	dt: number,
	time: number,
	vehicle: string?,
}

local ghosts: { [string]: Loaded } = {}
local currentTrack: string? = nil
local playing: Loaded? = nil
local startedAt = 0
local ghostModel: Model? = nil
local ghostVehicle: string? = nil -- fuer welches Fahrzeug das Modell gebaut ist
local ghostParts: { BasePart } = {}
local label: TextLabel? = nil

local function maxSamples(): number
	return math.floor(Config.Ghost.MaxDuration / math.max(Config.Ghost.SampleInterval, 0.02)) + 2
end

-- Einfacher, halbdurchsichtiger Wagen (Boden + Waende) in der Groesse des Fahrzeugs, nur Optik
local function getModel(vehicle: string?): Model
	local existing = ghostModel
	if existing and existing.Parent and ghostVehicle == vehicle then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	ghostVehicle = vehicle
	local c = Vehicles.stats(vehicle).Cart
	local model = Instance.new("Model")
	model.Name = "Geist"
	local function piece(name: string, size: Vector3, offset: Vector3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.ForceField
		p.Color = Config.Ghost.Color
		p.Transparency = 1
		p:SetAttribute("Offset", offset)
		p.Parent = model
		table.insert(ghostParts, p)
		return p
	end
	table.clear(ghostParts)
	local base = piece("Base", Vector3.new(c.Width, c.FloorThickness, c.Length), Vector3.zero)
	local wallY = c.FloorThickness / 2 + c.WallHeight / 2
	piece("Left", Vector3.new(0.2, c.WallHeight, c.Length), Vector3.new(-c.Width / 2, wallY, 0))
	piece("Right", Vector3.new(0.2, c.WallHeight, c.Length), Vector3.new(c.Width / 2, wallY, 0))
	piece("Front", Vector3.new(c.Width, c.WallHeight, 0.2), Vector3.new(0, wallY, -c.Length / 2))
	piece("Back", Vector3.new(c.Width, c.WallHeight, 0.2), Vector3.new(0, wallY, c.Length / 2))
	model.PrimaryPart = base

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(160, 24)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	billboard.Adornee = base
	billboard.LightInfluence = 0
	billboard.MaxDistance = 150
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Config.Ghost.Color
	text.TextStrokeTransparency = 0.4
	text.Parent = billboard
	billboard.Parent = model
	label = text

	model.Parent = workspace
	ghostModel = model
	return model
end

local function setVisible(visible: boolean)
	local model = ghostModel
	if not model then
		return
	end
	for _, p in ghostParts do
		p.Transparency = if visible then Config.Ghost.Transparency else 1
	end
	local billboard = model:FindFirstChildOfClass("BillboardGui")
	if billboard then
		billboard.Enabled = visible
	end
end

local function place(sample: GhostCodec.Sample)
	local root = CFrame.new(sample[1], sample[2], sample[3])
		* CFrame.fromEulerAnglesXYZ(math.rad(sample[4]), math.rad(sample[5]), math.rad(sample[6]))
	for _, p in ghostParts do
		local offset = p:GetAttribute("Offset")
		p.CFrame = root * CFrame.new(if typeof(offset) == "Vector3" then offset else Vector3.zero)
	end
end

-- Lauf beginnt: Geist der aktuellen Strecke abspielen (falls vorhanden und eingeschaltet)
function GhostClient.startRun()
	local track = currentTrack
	local ghost = if track then ghosts[track] else nil
	if not ghost or not Settings.get("Ghost") then
		playing = nil
		setVisible(false)
		return
	end
	playing = ghost
	startedAt = os.clock()
	getModel(ghost.vehicle)
	local text = label
	if text then
		text.Text = "Geist " .. RaceTime.format(ghost.time)
	end
	setVisible(true)
end

-- Lauf vorbei / Neustart: Geist weg
function GhostClient.stopRun()
	playing = nil
	setVisible(false)
end

function GhostClient.init()
	ghostRemote.OnClientEvent:Connect(function(kind: string, trackId: string, raw: any)
		if kind == "Current" then
			currentTrack = trackId
		elseif kind == "Data" then
			local samples, dt, time = GhostCodec.decode(raw, maxSamples())
			if samples then
				local vehicle = if type(raw) == "table" and type(raw.vehicle) == "string"
					then raw.vehicle
					else nil
				ghosts[trackId] = { samples = samples, dt = dt, time = time, vehicle = vehicle }
			end
		end
	end)
	Settings.onChanged(function(key, value)
		if key == "Ghost" and value == false then
			GhostClient.stopRun()
		end
	end)
	RunService.RenderStepped:Connect(function()
		local ghost = playing
		if not ghost then
			return
		end
		local t = os.clock() - startedAt
		if t > GhostCodec.duration(ghost.samples, ghost.dt) + 1 then
			GhostClient.stopRun() -- Geist ist angekommen
			return
		end
		local sample = GhostCodec.sample(ghost.samples, ghost.dt, t)
		if sample then
			place(sample)
		end
	end)
end

return GhostClient
