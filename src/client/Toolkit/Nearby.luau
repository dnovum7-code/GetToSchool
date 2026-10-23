--!strict
-- Gemeinsamer Helfer fuer das Umgebungsleben: Wo ist der Spieler (Wagen, sonst Kamera)?
-- Welche Bausteine sind nah genug, um aktiv zu sein (mit Obergrenze)?

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local AmbientLogic =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Atmosphere"):WaitForChild("AmbientLogic"))
local ToolkitTypes = require(script.Parent:WaitForChild("ToolkitTypes"))

local Nearby = {}

-- Bezugspunkt: eigener Wagen, sonst wohin die Kamera schaut
function Nearby.focus(ctx: ToolkitTypes.Context): Vector3?
	local base = ctx.base
	if base then
		return base.Position
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.Focus.Position else nil
end

-- Sollen wir jetzt neu auswaehlen? (nicht jeden Frame, Config.Ambient.CheckInterval)
function Nearby.timer(): (dt: number) -> boolean
	local left = 0
	return function(dt: number): boolean
		left -= dt
		if left <= 0 then
			left = Config.Ambient.CheckInterval
			return true
		end
		return false
	end
end

-- Aus `items` die naechsten innerhalb `range` (hoechstens `maxActive`) als Menge
function Nearby.select<T>(
	items: { T },
	positionOf: (T) -> Vector3,
	focus: Vector3,
	range: number,
	maxActive: number
): { [T]: boolean }
	local distances = {}
	for index, item in items do
		distances[index] = (positionOf(item) - focus).Magnitude
	end
	local active: { [T]: boolean } = {}
	for _, index in AmbientLogic.pickActive(distances, range, maxActive) do
		active[items[index]] = true
	end
	return active
end

-- Sound-Id aus Attribut "SoundId" (Zahl oder Text) oder aus Config.Sounds[name]
function Nearby.soundId(instance: Instance, fallbackName: string?): string?
	local id = instance:GetAttribute("SoundId")
	if type(id) == "number" and id > 0 then
		return tostring(math.floor(id))
	elseif type(id) == "string" and id ~= "" then
		return id
	end
	local entry = fallbackName and (Config.Sounds :: any)[fallbackName]
	local configId = entry and entry.Id
	if type(configId) == "number" and configId > 0 then
		return tostring(math.floor(configId))
	elseif type(configId) == "string" and configId ~= "" then
		return configId
	end
	return nil
end

return Nearby
