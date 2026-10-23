--!strict
-- Sound-Landschaft:
--   * Ambiente: Wind/Natur je nach Bereich. Parts mit Tag "SoundZone" und Attribut Ambience
--     ("Meadow", "Forest", "Village", "Stream" ... -> Config.Soundscape.Ambiences -> Eintrag
--     in Config.Sounds) oder eigenem Attribut "SoundId". Ausserhalb aller Zonen: "Default".
--     Liegen Zonen ineinander, gilt die kleinste. Wechsel = weiche Ueberblendung (FadeTime).
--   * Musik pro Strecke: Attribute MusicId und MusicIntenseId am Track-Model (TrackId). Die
--     zweite Spur wird mit dem Tempo lauter, beim Boost voll (Config.Soundscape.IntenseStart).
--     Ohne MusicId laeuft die allgemeine Musik (Config.Sounds.Music).
--   * Stille-Moment: lange in der Luft (grosser Sprung) = Musik fast still, bei der Landung
--     wieder da.
-- Lautstaerke-Regler im Menue: Ambiente = "Effekte", Musik = "Musik".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SpeedFeel = require(Shared:WaitForChild("Atmosphere"):WaitForChild("SpeedFeel"))
local TagList = require(Shared:WaitForChild("TagList"))
local CartController = require(script.Parent:WaitForChild("CartController"))
local SoundSystem = require(script.Parent:WaitForChild("SoundSystem"))

local Soundscape = {}

type Layer = { sound: Sound, level: number } -- level 0..1 (Ueberblendung)

local ambience: { [string]: Layer } = {} -- Sound-Id -> Ebene
local currentAmbience: string? = nil
local checkTimer = 0
local telemetry: CartController.Telemetry? = nil
local airTime = 0
local musicFactor = 1 -- 1 = normal, SilenceVolume = Stille-Moment
local intensity = 0
local trackMusic: Sound? = nil
local trackIntense: Sound? = nil

local function toId(value: unknown): string?
	if type(value) == "number" and value > 0 then
		return "rbxassetid://" .. tostring(math.floor(value))
	elseif type(value) == "string" and value ~= "" then
		return if string.match(value, "^%d+$") then "rbxassetid://" .. value else value
	end
	return nil
end

local function group(name: string): SoundGroup?
	local found = SoundService:FindFirstChild(name)
	return if found and found:IsA("SoundGroup") then found else nil
end

local function loop(id: string, groupName: string): Sound
	local sound = Instance.new("Sound")
	sound.Name = "Soundscape"
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = group(groupName)
	sound.Parent = SoundService
	sound:Play()
	return sound
end

local function inZone(part: BasePart, position: Vector3): boolean
	local p = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

-- Welches Ambiente gilt an dieser Stelle? (Sound-Id)
local function ambienceAt(position: Vector3): string?
	local best: BasePart? = nil
	local bestVolume = math.huge
	for _, zone in TagList.get("SoundZone") do
		if zone:IsA("BasePart") and inZone(zone, position) then
			local volume = zone.Size.X * zone.Size.Y * zone.Size.Z
			if volume < bestVolume then
				best = zone
				bestVolume = volume
			end
		end
	end
	local names = Config.Soundscape.Ambiences :: any
	local name = "Default"
	if best then
		local own = toId(best:GetAttribute("SoundId"))
		if own then
			return own
		end
		local ambienceName = best:GetAttribute("Ambience")
		if type(ambienceName) == "string" and names[ambienceName] then
			name = ambienceName
		end
	end
	local entry = (Config.Sounds :: any)[names[name] or ""]
	return entry and toId(entry.Id)
end

local function updateAmbience(dt: number)
	checkTimer -= dt
	if checkTimer <= 0 then
		checkTimer = Config.Soundscape.CheckInterval
		local camera = workspace.CurrentCamera
		if camera then
			currentAmbience = ambienceAt(camera.Focus.Position)
		end
	end
	local current = currentAmbience
	if current and not ambience[current] then
		ambience[current] = { sound = loop(current, "Effects"), level = 0 }
	end
	local S = Config.Soundscape
	for id, layer in ambience do
		layer.level = SpeedFeel.approach(layer.level, if id == current then 1 else 0, dt, S.FadeTime)
		layer.sound.Volume = layer.level * S.AmbienceVolume
		if layer.level <= 0 and id ~= current then
			layer.sound:Destroy()
			ambience[id] = nil
		end
	end
end

local function updateMusic(dt: number)
	local S = Config.Soundscape
	local data = telemetry
	-- Stille-Moment bei grossen Spruengen
	if data and not data.grounded then
		airTime += dt
	else
		airTime = 0
	end
	local silent = airTime >= S.SilenceAirTime
	musicFactor = SpeedFeel.approach(musicFactor, if silent then S.SilenceVolume else 1, dt, S.SilenceFade)
	-- zweite Spur mit Tempo und Boost
	local fraction = if data then SpeedFeel.fraction(data.speed, Config.Atmosphere.TopSpeed) else 0
	local wanted = if data then SpeedFeel.musicIntensity(fraction, S.IntenseStart, data.boosting) else 0
	intensity = SpeedFeel.approach(intensity, wanted, dt, S.IntenseFade)
	local base = trackMusic
	if base then
		base.Volume = S.MusicVolume * musicFactor
		local intense = trackIntense
		if intense then
			intense.Volume = S.MusicVolume * intensity * musicFactor
		end
	else
		local global = SoundSystem.music()
		if global then
			global.Volume = Config.Sounds.Music.Volume * musicFactor
		end
	end
end

local function findTrackModel(trackId: string): Instance?
	for _, item in workspace:GetDescendants() do
		if item:GetAttribute("TrackId") == trackId and not item:IsA("BasePart") then
			return item
		end
	end
	return nil
end

-- Neue Strecke (vom Server bei jedem Neustart): deren Musik spielen
function Soundscape.setTrack(trackId: string)
	local model = findTrackModel(trackId)
	local musicId = model and toId(model:GetAttribute("MusicId"))
	local intenseId = model and toId(model:GetAttribute("MusicIntenseId"))
	if trackMusic and trackMusic.SoundId == (musicId or "") then
		return -- dieselbe Musik laeuft schon
	end
	for _, sound in { trackMusic, trackIntense } do
		if sound then
			sound:Destroy()
		end
	end
	trackMusic = if musicId then loop(musicId, "Music") else nil
	trackIntense = if musicId and intenseId then loop(intenseId, "Music") else nil
	-- Strecken-Musik ersetzt die allgemeine Musik
	local global = SoundSystem.music()
	if global then
		if musicId then
			global:Stop()
		elseif not global.IsPlaying then
			global:Play()
		end
	end
end

-- Jeden Frame aus CartClient: Fahrdaten (nil = nicht im Wagen)
function Soundscape.setTelemetry(data: CartController.Telemetry?)
	telemetry = data
end

function Soundscape.init()
	RunService.RenderStepped:Connect(function(dt)
		updateAmbience(dt)
		updateMusic(dt)
	end)
end

return Soundscape
