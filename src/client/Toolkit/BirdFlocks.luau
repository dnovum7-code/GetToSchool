--!strict
-- BirdFlock (Tag, Part): Vogelschwarm. Auf der Oberseite des Parts sitzen Count kleine
-- Platzhalter-Voegel und hopsen herum. Kommst du naeher als TriggerRadius, fliegen sie mit
-- Fluegelschlagen auf und davon (Sound: Attribut "SoundId", sonst Config.Sounds.BirdsFly).
-- Nach RespawnTime sitzen sie wieder da, sobald du weg bist. Das Part ist unsichtbar.
-- Attribute: Count, TriggerRadius. Werte: Config.Ambient.Birds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local TagList = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TagList"))
local Rng = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Toolkit"):WaitForChild("Rng"))
local ComicText = require(script.Parent.Parent:WaitForChild("ComicText"))
local LocalClone = require(script.Parent.Parent:WaitForChild("LocalClone"))
local Nearby = require(script.Parent:WaitForChild("Nearby"))
local Pieces = require(script.Parent:WaitForChild("Pieces"))
local ToolkitTypes = require(script.Parent:WaitForChild("ToolkitTypes"))

type Bird = {
	model: Model,
	body: BasePart,
	left: BasePart,
	right: BasePart,
	home: CFrame,
	velocity: Vector3,
	phase: number,
}

type Flock = {
	part: BasePart,
	seed: number,
	state: "Off" | "Sitting" | "Flying" | "Gone",
	birds: { Bird },
	timer: number,
}

local flocks: { [Instance]: Flock } = {}
local list: { Flock } = {}
local due = Nearby.timer()
local BIRD_COLOR = Color3.fromRGB(45, 40, 40)

local function makeBird(home: CFrame): Bird
	local model = Instance.new("Model")
	model.Name = "Vogel"
	local function piece(name: string, size: Vector3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Color = BIRD_COLOR
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = model
		return p
	end
	local body = piece("Body", Vector3.new(0.35, 0.35, 0.8))
	local left = piece("WingL", Vector3.new(0.7, 0.06, 0.4))
	local right = piece("WingR", Vector3.new(0.7, 0.06, 0.4))
	model.PrimaryPart = body
	model.Parent = LocalClone.folder("LocalBirds")
	return {
		model = model,
		body = body,
		left = left,
		right = right,
		home = home,
		velocity = Vector3.zero,
		phase = 0,
	}
end

-- Voegel an ihre Lage setzen; `flap` = Fluegelwinkel (Grad)
local function pose(bird: Bird, cframe: CFrame, flap: number)
	bird.body.CFrame = cframe
	local angle = math.rad(flap)
	bird.left.CFrame = cframe
		* CFrame.new(-0.2, 0.05, 0)
		* CFrame.Angles(0, 0, angle)
		* CFrame.new(-0.35, 0, 0)
	bird.right.CFrame = cframe
		* CFrame.new(0.2, 0.05, 0)
		* CFrame.Angles(0, 0, -angle)
		* CFrame.new(0.35, 0, 0)
end

local function sitDown(flock: Flock)
	for _, bird in flock.birds do
		bird.model:Destroy()
	end
	table.clear(flock.birds)
	local part = flock.part
	local count = math.clamp(math.floor(Pieces.number(part, "Count", Config.Ambient.Birds.Count)), 1, 30)
	for i = 1, count do
		local x = (Rng.at(flock.seed, i, 1) - 0.5) * part.Size.X
		local z = (Rng.at(flock.seed, i, 2) - 0.5) * part.Size.Z
		local yaw = Rng.at(flock.seed, i, 3) * math.pi * 2
		local home = part.CFrame * CFrame.new(x, part.Size.Y / 2 + 0.2, z) * CFrame.Angles(0, yaw, 0)
		local bird = makeBird(home)
		bird.phase = Rng.at(flock.seed, i, 4) * 10
		pose(bird, home, 10)
		table.insert(flock.birds, bird)
	end
	flock.state = "Sitting"
end

local function clear(flock: Flock, state: "Off" | "Gone")
	for _, bird in flock.birds do
		bird.model:Destroy()
	end
	table.clear(flock.birds)
	flock.state = state
end

local function takeOff(flock: Flock, from: Vector3)
	local B = Config.Ambient.Birds
	for i, bird in flock.birds do
		local away = bird.home.Position - from
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude < 0.1 then
			away = Vector3.xAxis
		end
		local spread = (Rng.at(flock.seed, i, 5) - 0.5) * 1.2
		local dir = (CFrame.Angles(0, spread, 0):VectorToWorldSpace(away.Unit) + Vector3.new(
			0,
			0.6 + Rng.at(flock.seed, i, 6) * 0.5,
			0
		)).Unit
		bird.velocity = dir * B.FlySpeed * (0.8 + Rng.at(flock.seed, i, 7) * 0.4)
	end
	flock.state = "Flying"
	flock.timer = B.FlyTime
	ComicText.sound(flock.part, Nearby.soundId(flock.part, "BirdsFly"), Config.Sounds.BirdsFly.Volume, 120)
end

local BirdFlocks: ToolkitTypes.Piece = {
	init = function()
		TagList.watch("BirdFlock", function(instance)
			if instance:IsA("BasePart") and not flocks[instance] then
				local flock: Flock =
					{ part = instance, seed = Pieces.seed(instance), state = "Off", birds = {}, timer = 0 }
				flocks[instance] = flock
				table.insert(list, flock)
			end
		end)
	end,

	step = function(ctx)
		local B = Config.Ambient.Birds
		local focus = Nearby.focus(ctx)
		-- Auswahl der aktiven Schwaerme (selten)
		if due(ctx.dt) then
			for index = #list, 1, -1 do
				local flock = list[index]
				if not flock.part:IsDescendantOf(workspace) then
					clear(flock, "Off")
					flocks[flock.part] = nil
					table.remove(list, index)
				end
			end
			local active = if focus
				then Nearby.select(list, function(flock: Flock)
					return flock.part.Position
				end, focus, B.Range, B.MaxActive)
				else {}
			for _, flock in list do
				if active[flock] and flock.state == "Off" then
					sitDown(flock)
				elseif not active[flock] and (flock.state == "Sitting" or flock.state == "Gone") then
					clear(flock, "Off")
				end
			end
		end
		local now = os.clock()
		for _, flock in list do
			local trigger = Pieces.number(flock.part, "TriggerRadius", B.TriggerRadius)
			local distance = if focus then (flock.part.Position - focus).Magnitude else math.huge
			if flock.state == "Sitting" then
				if distance <= trigger then
					takeOff(flock, focus :: Vector3)
				else
					-- ab und zu ein kleiner Hopser auf der Stelle
					for _, bird in flock.birds do
						local hop = math.max(0, math.sin(now * 3 + bird.phase) - 0.92) * 4
						pose(bird, bird.home * CFrame.new(0, hop, 0), 10)
					end
				end
			elseif flock.state == "Flying" then
				flock.timer -= ctx.dt
				for _, bird in flock.birds do
					local position = bird.body.Position + bird.velocity * ctx.dt
					local flap = math.sin(now * 25 + bird.phase) * 45
					pose(bird, CFrame.lookAt(position, position + bird.velocity), flap)
				end
				if flock.timer <= 0 then
					clear(flock, "Gone")
					flock.timer = B.RespawnTime
				end
			elseif flock.state == "Gone" then
				flock.timer -= ctx.dt
				if flock.timer <= 0 and distance > trigger * 1.5 then
					sitDown(flock)
				end
			end
		end
	end,
}

return BirdFlocks
