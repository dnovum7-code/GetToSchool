--!strict
-- AmbientSound (Tag, Part): Klangquelle mit Schleife, z. B. Kuhglocken, Bach, Kirche.
-- Attribute: SoundId (Pflicht, sonst still), Volume (Config.Ambient.Sound.Volume),
-- Range (Hoerweite in Studs, Config.Ambient.Sound.Range), Pitch (1).
-- Nur die naechsten Config.Ambient.Sound.MaxActive innerhalb ihrer Reichweite spielen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local TagList = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TagList"))
local Nearby = require(script.Parent:WaitForChild("Nearby"))
local Pieces = require(script.Parent:WaitForChild("Pieces"))
local ToolkitTypes = require(script.Parent:WaitForChild("ToolkitTypes"))

type Source = { part: BasePart, sound: Sound? }

local sources: { [Instance]: Source } = {}
local list: { Source } = {}
local due = Nearby.timer()
local warned: { [Instance]: boolean } = {}

local function range(source: Source): number
	return Pieces.number(source.part, "Range", Config.Ambient.Sound.Range)
end

local function start(source: Source)
	local id = Nearby.soundId(source.part, nil)
	if not id then
		if not warned[source.part] then
			warned[source.part] = true
			Pieces.debugWarn(source.part, `AmbientSound ohne Attribut "SoundId" (bleibt still).`)
		end
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "AmbientSound"
	sound.SoundId = if string.match(id, "^%d+$") then "rbxassetid://" .. id else id
	sound.Looped = true
	sound.Volume = Pieces.number(source.part, "Volume", Config.Ambient.Sound.Volume)
	sound.PlaybackSpeed = Pieces.number(source.part, "Pitch", 1)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = range(source)
	sound.RollOffMinDistance = math.max(range(source) * 0.15, 4)
	local group = SoundService:FindFirstChild("Effects")
	if group and group:IsA("SoundGroup") then
		sound.SoundGroup = group
	end
	sound.Parent = source.part
	sound:Play()
	source.sound = sound
end

local function stop(source: Source)
	local sound = source.sound
	if sound then
		sound:Destroy()
		source.sound = nil
	end
end

local AmbientSounds: ToolkitTypes.Piece = {
	init = function()
		TagList.watch("AmbientSound", function(instance)
			if instance:IsA("BasePart") and not sources[instance] then
				local source: Source = { part = instance, sound = nil }
				sources[instance] = source
				table.insert(list, source)
			end
		end)
	end,

	step = function(ctx)
		if not due(ctx.dt) then
			return
		end
		for index = #list, 1, -1 do
			local source = list[index]
			if not source.part:IsDescendantOf(workspace) then
				stop(source)
				sources[source.part] = nil
				table.remove(list, index)
			end
		end
		local focus = Nearby.focus(ctx)
		if not focus then
			return
		end
		-- jede Quelle nur innerhalb ihrer eigenen Reichweite (plus etwas Puffer)
		local inRange = {}
		for _, source in list do
			if (source.part.Position - focus).Magnitude <= range(source) * 1.1 then
				table.insert(inRange, source)
			end
		end
		local active = Nearby.select(inRange, function(source: Source)
			return source.part.Position
		end, focus, math.huge, Config.Ambient.Sound.MaxActive)
		for _, source in list do
			if active[source] and not source.sound then
				start(source)
			elseif not active[source] and source.sound then
				stop(source)
			end
		end
	end,
}

return AmbientSounds
