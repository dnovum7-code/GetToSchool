--!strict
-- Villager (Tag, Model): Dorfbewohner. Steht herum (leichtes Wippen) oder laeuft herum
-- (Attribut WalkRadius > 0). Faehrt dein Wagen schnell und nah vorbei (ReactRadius), reagiert
-- er: springt zur Seite ("Dodge"), schimpft ("Scold") oder winkt ("Wave"); Attribut
-- Reaction = "Dodge" / "Scold" / "Wave" / "Random" (Standard). Comic-Text, Sound
-- (Attribut "SoundId", sonst Config.Sounds.VillagerScold / VillagerWave).
-- Bewegt wird nur bei dir (wie alle Bausteine). Werte: Config.Ambient.Villager.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TagList = require(Shared:WaitForChild("TagList"))
local AmbientLogic = require(Shared:WaitForChild("Atmosphere"):WaitForChild("AmbientLogic"))
local ComicText = require(script.Parent.Parent:WaitForChild("ComicText"))
local Nearby = require(script.Parent:WaitForChild("Nearby"))
local Pieces = require(script.Parent:WaitForChild("Pieces"))
local ToolkitTypes = require(script.Parent:WaitForChild("ToolkitTypes"))

type Action = "None" | "Dodge" | "Scold" | "Wave"

type Villager = {
	model: PVInstance,
	home: CFrame,
	spot: CFrame, -- wo er gerade steht (ohne Wippen/Hopser)
	height: number,
	target: Vector3?,
	pauseUntil: number,
	action: Action,
	actionStart: number,
	actionFrom: CFrame,
	actionTo: CFrame,
	cooldownUntil: number,
	phase: number,
}

local villagers: { [Instance]: Villager } = {}
local list: { Villager } = {}
local active: { [Villager]: boolean } = {}
local due = Nearby.timer()

local ACTION_TIME = 0.8

local function sizeY(model: PVInstance): number
	if model:IsA("Model") then
		return model:GetExtentsSize().Y
	elseif model:IsA("BasePart") then
		return model.Size.Y
	end
	return 5
end

local function textAbove(v: Villager, text: string, color: Color3)
	ComicText.show(v.spot.Position + Vector3.new(0, v.height / 2 + 1.5, 0), text, color, 0.8)
end

local function pick(list: { string }): string
	return list[math.random(1, #list)]
end

local function react(v: Villager, cartPosition: Vector3, cartVelocity: Vector3, now: number)
	local V = Config.Ambient.Villager
	local kind = AmbientLogic.reaction(Pieces.string(v.model, "Reaction", nil), math.random())
	v.action = kind :: Action
	v.actionStart = now
	v.actionFrom = v.spot
	v.cooldownUntil = now + V.Cooldown
	local primary = v.model :: Instance
	if kind == "Dodge" then
		local flat = Vector3.new(cartVelocity.X, 0, cartVelocity.Z)
		local d = v.spot.Position - cartPosition
		local side = AmbientLogic.dodgeSide(flat.X, flat.Z, d.X, d.Z)
		local left = if flat.Magnitude > 0.1 then Vector3.new(flat.Z, 0, -flat.X).Unit else Vector3.xAxis
		v.actionTo = v.spot + left * side * V.DodgeDistance
		textAbove(v, "HUCH!", Color3.fromRGB(255, 230, 90))
		ComicText.sound(
			primary,
			Nearby.soundId(primary, "VillagerScold"),
			Config.Sounds.VillagerScold.Volume,
			80
		)
	elseif kind == "Scold" then
		v.actionTo = v.spot
		textAbove(v, pick(V.ScoldTexts), Color3.fromRGB(255, 90, 70))
		ComicText.sound(
			primary,
			Nearby.soundId(primary, "VillagerScold"),
			Config.Sounds.VillagerScold.Volume,
			80
		)
	else
		v.actionTo = v.spot
		textAbove(v, pick(V.WaveTexts), Color3.fromRGB(120, 255, 140))
		ComicText.sound(
			primary,
			Nearby.soundId(primary, "VillagerWave"),
			Config.Sounds.VillagerWave.Volume,
			80
		)
	end
end

local function register(instance: Instance)
	if villagers[instance] or not (instance:IsA("Model") or instance:IsA("BasePart")) then
		return
	end
	local pv = instance :: PVInstance
	local home = pv:GetPivot()
	local v: Villager = {
		model = pv,
		home = home,
		spot = home,
		height = sizeY(pv),
		target = nil,
		pauseUntil = 0,
		action = "None",
		actionStart = 0,
		actionFrom = home,
		actionTo = home,
		cooldownUntil = 0,
		phase = (Pieces.seed(instance) % 1000) / 100,
	}
	CollectionService:AddTag(instance, "SoftHit") -- anfahren ist kein harter Aufprall
	villagers[instance] = v
	table.insert(list, v)
end

local function update(v: Villager, ctx: ToolkitTypes.Context, now: number)
	local V = Config.Ambient.Villager
	local base = ctx.base
	-- Reaktion auf den vorbeifahrenden Wagen
	if base and v.action == "None" and now >= v.cooldownUntil then
		local velocity = base.AssemblyLinearVelocity
		local radius = Pieces.number(v.model, "ReactRadius", V.ReactRadius)
		if
			velocity.Magnitude >= V.ReactMinSpeed
			and (base.Position - v.spot.Position).Magnitude <= radius
		then
			react(v, base.Position, velocity, now)
		end
	end
	local pose = v.spot
	if v.action ~= "None" then
		local t = now - v.actionStart
		if v.action == "Dodge" then
			local duration = V.DodgeTime
			local alpha = math.clamp(t / duration, 0, 1)
			v.spot = v.actionFrom:Lerp(v.actionTo, alpha)
			pose = v.spot + Vector3.new(0, AmbientLogic.hop(t, duration, 2.5), 0)
			if t >= duration then
				v.action = "None"
				v.target = v.home.Position -- spaeter langsam zurueck
				v.pauseUntil = now + 1.5
			end
		elseif v.action == "Scold" then
			pose = v.spot * CFrame.Angles(0, math.sin(t * 30) * 0.25, 0)
			if t >= ACTION_TIME then
				v.action = "None"
			end
		else -- Wave: zwei kleine Hopser
			pose = v.spot + Vector3.new(0, AmbientLogic.hop(t % (ACTION_TIME / 2), ACTION_TIME / 2, 1.2), 0)
			if t >= ACTION_TIME then
				v.action = "None"
			end
		end
	else
		local walkRadius = Pieces.number(v.model, "WalkRadius", 0)
		local target = v.target
		if target then
			-- laufen (zurueck nach Hause oder zu einem Punkt im WalkRadius)
			if now >= v.pauseUntil then
				local flat = Vector3.new(target.X - v.spot.Position.X, 0, target.Z - v.spot.Position.Z)
				local step = V.WalkSpeed * ctx.dt
				if flat.Magnitude <= step then
					v.spot = CFrame.new(Vector3.new(target.X, v.spot.Position.Y, target.Z)) * v.spot.Rotation
					v.target = nil
					v.pauseUntil = now + 1 + math.random() * 2
				else
					local position = v.spot.Position + flat.Unit * step
					v.spot = CFrame.lookAt(position, position + flat.Unit)
				end
			end
		elseif walkRadius > 0 and now >= v.pauseUntil then
			local angle = math.random() * math.pi * 2
			local distance = math.random() * walkRadius
			v.target = v.home.Position
				+ Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		end
		-- leichtes Wippen im Stehen
		if v.target == nil then
			pose = v.spot * CFrame.Angles(0, math.sin(now * 0.7 + v.phase) * 0.12, 0)
		end
	end
	v.model:PivotTo(pose)
end

local Villagers: ToolkitTypes.Piece = {
	init = function()
		TagList.watch("Villager", register)
	end,

	step = function(ctx)
		if due(ctx.dt) then
			for index = #list, 1, -1 do
				local v = list[index]
				if not v.model:IsDescendantOf(workspace) then
					villagers[v.model] = nil
					table.remove(list, index)
				end
			end
			local focus = Nearby.focus(ctx)
			local V = Config.Ambient.Villager
			active = if focus
				then Nearby.select(list, function(v: Villager)
					return v.spot.Position
				end, focus, V.Range, V.MaxActive)
				else {}
		end
		local now = os.clock()
		for v in active do
			update(v, ctx, now)
		end
	end,

	-- T: alle wieder an ihren Platz
	reset = function(kind: string)
		if kind ~= "Full" then
			return
		end
		for _, v in list do
			v.spot = v.home
			v.target = nil
			v.action = "None"
			v.model:PivotTo(v.home)
		end
	end,
}

return Villagers
