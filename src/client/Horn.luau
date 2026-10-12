--!strict
-- Hupe, Client-Seite: Taste H (Gamepad: linken Stick druecken, Touch: Button "Hupe").
-- Wir fragen den Server ("Honk"); der prueft die Abklingzeit und schickt es an alle. Jeder
-- Client spielt dann den Sound als 3D-Sound am Wagen des Hupenden (wer weit weg ist, hoert
-- nichts) und zeigt ein aufsteigendes Hup-Symbol. Der eigene Wagen hopst kurz.
-- Einstellung "MuteHorns": Hupen anderer Spieler stumm (die eigene hoert man immer).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local HornRules = require(Shared:WaitForChild("Progression"):WaitForChild("HornRules"))
local OwnCart = require(script.Parent:WaitForChild("OwnCart"))
local Settings = require(script.Parent:WaitForChild("Settings"))

local hornRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Horn") :: RemoteEvent

local Horn = {}

local ACTION = "GetToSchoolHorn"
local player = Players.LocalPlayer
local lastLocal: number? = nil
local effectsGroup: SoundGroup? = nil

local function soundIdOf(name: string): string?
	local entry = (Config.Sounds :: any)[name]
	local id = entry and entry.Id
	if type(id) == "number" and id > 0 then
		return "rbxassetid://" .. tostring(math.floor(id))
	elseif type(id) == "string" and id ~= "" then
		return if string.match(id, "^%d+$") then "rbxassetid://" .. id else id
	end
	return nil
end

-- 3D-Sound am Wagen (ohne Id in Config.Sounds: still, nur das Symbol)
local function playAt(base: BasePart, soundName: string)
	local id = soundIdOf(soundName)
	if not id then
		return
	end
	local entry = (Config.Sounds :: any)[soundName]
	local sound = Instance.new("Sound")
	sound.Name = "Horn"
	sound.SoundId = id
	sound.Volume = if type(entry.Volume) == "number" then entry.Volume else 0.9
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 15
	sound.RollOffMaxDistance = Config.Horn.HearDistance
	effectsGroup = effectsGroup or SoundService:FindFirstChild("Effects") :: SoundGroup?
	sound.SoundGroup = effectsGroup
	sound.Parent = base
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	task.delay(10, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

-- Hup-Symbol steigt ueber dem Wagen auf und verblasst
local function showSymbol(base: BasePart)
	local H = Config.Horn
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HornSymbol"
	billboard.Size = UDim2.fromOffset(120, 50)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = H.HearDistance
	billboard.Adornee = base
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.Text = "♪ HUP! ♪"
	label.TextColor3 = Color3.fromRGB(255, 230, 90)
	label.TextStrokeTransparency = 0
	label.Rotation = math.random(-12, 12)
	label.Parent = billboard
	billboard.Parent = base
	local info = TweenInfo.new(H.SymbolTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(billboard, info, { StudsOffset = Vector3.new(0, 3 + H.SymbolRise, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(H.SymbolTime + 0.1, function()
		billboard:Destroy()
	end)
end

local function onHonk(honker: Player, hornId: string)
	local cart = OwnCart.findFor(honker.UserId)
	local base = cart and cart:FindFirstChild("Base")
	if not base or not base:IsA("BasePart") then
		return
	end
	showSymbol(base)
	local isMe = honker == player
	if isMe and Config.Horn.HopSpeed > 0 then
		-- eigener Wagen: kurz hopsen (nur unser Client rechnet seine Physik)
		local velocity = base.AssemblyLinearVelocity
		base.AssemblyLinearVelocity = velocity + Vector3.new(0, Config.Horn.HopSpeed, 0)
	end
	if not isMe and Settings.get("MuteHorns") then
		return
	end
	local def = HornRules.find(Config.Horn.Horns, hornId)
		or HornRules.find(Config.Horn.Horns, Config.Horn.Default)
	if def then
		playAt(base, def.sound)
	end
end

local function honk()
	local now = os.clock()
	if not HornRules.ready(lastLocal, now, Config.Horn.Cooldown) then
		return
	end
	lastLocal = now
	hornRemote:FireServer("Honk")
end

-- Im Wagen: Taste binden (H, linken Stick druecken, Touch-Button)
function Horn.activate()
	ContextActionService:BindAction(ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			honk()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.H, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle(ACTION, "Hupe")
end

function Horn.deactivate()
	ContextActionService:UnbindAction(ACTION)
end

function Horn.init()
	hornRemote.OnClientEvent:Connect(function(kind, honker, hornId)
		if kind == "Honk" and typeof(honker) == "Instance" and honker:IsA("Player") then
			onHonk(honker, if type(hornId) == "string" then hornId else "")
		end
	end)
end

return Horn
