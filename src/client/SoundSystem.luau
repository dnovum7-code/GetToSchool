--!strict
-- Einfaches Sound-System (nur auf diesem Client).
--   Einmal-Sounds (Boost, Crash, Checkpoint, Ziel): SoundSystem.play("Crash")
--   Dauer-Sounds am eigenen Wagen (Rollen, Drift-Quietschen): attach/detach/update
-- Die IDs stehen in Config.Sounds. Fehlt eine ID, gibt es diesen Sound einfach nicht.
--
-- Unity-Vergleich: AudioSource-Komponenten; "Sound" in Roblox = AudioSource + AudioClip.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local SoundSystem = {}

-- Dauer-Sounds am Wagen; alle anderen Eintraege in Config.Sounds sind Einmal-Sounds
local LOOPED = { Engine = true, Drift = true }

local oneShots: { [string]: Sound } = {}
local engineSound: Sound? = nil
local driftSound: Sound? = nil

-- 1234567, "1234567" oder "rbxassetid://1234567" -> "rbxassetid://1234567"; leer -> nil
local function toSoundId(id: unknown): string?
	if type(id) == "number" then
		return if id > 0 then "rbxassetid://" .. tostring(math.floor(id)) else nil
	elseif type(id) == "string" then
		local trimmed = string.match(id, "^%s*(.-)%s*$") or ""
		if trimmed == "" then
			return nil
		elseif string.match(trimmed, "^%d+$") then
			return "rbxassetid://" .. trimmed
		end
		return trimmed
	end
	return nil
end

local function makeSound(name: string, parent: Instance, looped: boolean): Sound?
	local settings = (Config.Sounds :: any)[name]
	local soundId = settings and toSoundId(settings.Id)
	if not soundId then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Volume = if type(settings.Volume) == "number" then settings.Volume else 0.5
	sound.Looped = looped
	sound.Parent = parent
	return sound
end

function SoundSystem.init()
	for name in Config.Sounds :: { [string]: any } do
		if LOOPED[name] then
			continue
		end
		local sound = makeSound(name, SoundService, false)
		if sound then
			oneShots[name] = sound
		end
	end
end

-- Einmal-Sound abspielen (von vorne). Ohne ID passiert nichts.
function SoundSystem.play(name: string)
	local sound = oneShots[name]
	if sound then
		sound.TimePosition = 0
		sound:Play()
	end
end

-- Sound mit beliebiger Id einmal abspielen (z. B. Attribut "Sound" an einem Objekt).
-- Ohne gueltige Id: Ersatz-Sound `fallback` aus Config.Sounds (falls angegeben).
function SoundSystem.playId(id: unknown, volume: number?, fallback: string?)
	local soundId = toSoundId(id)
	if not soundId then
		if fallback then
			SoundSystem.play(fallback)
		end
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.8
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	task.delay(15, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

-- Dauer-Sounds an den eigenen Wagen haengen (3D: kommen vom Wagen)
function SoundSystem.attach(cart: Model)
	SoundSystem.detach()
	local base = cart:FindFirstChild("Base")
	if not base then
		return
	end
	engineSound = makeSound("Engine", base, true)
	driftSound = makeSound("Drift", base, true)
	for _, sound in { engineSound, driftSound } do
		if sound then
			sound.Volume = 0
			sound:Play()
		end
	end
end

function SoundSystem.detach()
	for _, sound in { engineSound, driftSound } do
		if sound then
			sound:Destroy()
		end
	end
	engineSound = nil
	driftSound = nil
end

-- Jeden Frame: Tonhoehe/Lautstaerke an Tempo und Drift anpassen
function SoundSystem.update(speed: number, grounded: boolean, drifting: boolean)
	local engine = engineSound
	if engine then
		local E = Config.Sounds.Engine
		local t = math.clamp(speed / math.max(E.FullSpeed, 1), 0, 1)
		engine.PlaybackSpeed = E.MinPitch + (E.MaxPitch - E.MinPitch) * t
		-- leise im Stand und in der Luft
		engine.Volume = E.Volume * t * (if grounded then 1 else 0.3)
	end
	local drift = driftSound
	if drift then
		local target = if drifting then Config.Sounds.Drift.Volume else 0
		drift.Volume += (target - drift.Volume) * 0.3 -- weich ein-/ausblenden
	end
end

return SoundSystem
