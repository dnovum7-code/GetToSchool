--!strict
-- Muenzen (Tag "Coin"), Client-Seite:
--   * dreht und wippt alle Muenzen (nur Anzeige, jeder Client fuer sich)
--   * merkt, wenn der eigene Wagen eine Muenze beruehrt: Muenze sofort ausblenden, kleine
--     Animation, "+1" im UI, und dem Server melden. Der Server prueft und schreibt gut.
--   * Lehnt der Server ab (z. B. zu weit weg), erscheint die Muenze wieder.
--   * Kompletter Neustart (T): alle Muenzen erscheinen wieder.
-- Wiedererkannt werden Muenzen ueber das Attribut "CoinId" (vom Server vergeben).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Economy =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"):WaitForChild("Economy"))
local TagList = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TagList"))
local LocalHide = require(script.Parent:WaitForChild("LocalHide"))
local ProgressUI = require(script.Parent:WaitForChild("ProgressUI"))
local SoundSystem = require(script.Parent:WaitForChild("SoundSystem"))

local collectRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CollectCoin") :: RemoteEvent

local CoinsClient = {}

type Coin = {
	instance: PVInstance,
	id: string,
	home: CFrame, -- Lage aus Studio
	radius: number,
	phase: number, -- damit nicht alle Muenzen gleich wippen
}

local coins: { [Instance]: Coin } = {}
local collectedIds: { [string]: boolean } = {} -- in diesem Lauf eingesammelt
local retryAfter: { [string]: number } = {} -- nach Ablehnung kurz nicht erneut melden
local effectsFolder: Folder? = nil

local function getEffectsFolder(): Folder
	local folder = effectsFolder
	if folder and folder.Parent then
		return folder
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "LocalCoinEffects" -- existiert nur auf diesem Client
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

local function register(instance: Instance)
	if coins[instance] or not (instance:IsA("BasePart") or instance:IsA("Model")) then
		return
	end
	local id = instance:GetAttribute("CoinId")
	if type(id) ~= "string" then
		-- Nummer kommt vom Server, evtl. etwas spaeter
		instance:GetAttributeChangedSignal("CoinId"):Once(function()
			register(instance)
		end)
		return
	end
	local pv = instance :: PVInstance
	local size = if pv:IsA("BasePart") then pv.Size else (pv :: Model):GetExtentsSize()
	coins[instance] = {
		instance = pv,
		id = id,
		home = getCFrame(pv),
		radius = math.max(size.X, size.Y, size.Z) / 2,
		phase = math.random() * math.pi * 2,
	}
	LocalHide.set(instance, "Collected", collectedIds[id] == true)
end

-- Kleiner Effekt: Kopie der Muenze steigt auf, dreht schnell und verblasst
local function playPickupEffect(coin: Coin)
	local ghost = coin.instance:Clone()
	-- Die Kopie darf keine Muenze sein (sonst wuerde sie selbst eingesammelt)
	for _, item in { ghost :: Instance, table.unpack(ghost:GetDescendants()) } do
		for _, tag in item:GetTags() do
			CollectionService:RemoveTag(item, tag)
		end
	end
	local parts: { BasePart } = {}
	for _, item in { ghost :: Instance, table.unpack(ghost:GetDescendants()) } do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			table.insert(parts, item)
		end
	end
	ghost.Parent = getEffectsFolder()
	local start = getCFrame(coin.instance)
	local startTransparency: { [BasePart]: number } = {}
	for _, part in parts do
		startTransparency[part] = part.Transparency
	end
	local duration = 0.35
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local alpha = math.min(elapsed / duration, 1)
		setCFrame(ghost, CFrame.new(0, alpha * 3, 0) * start * CFrame.Angles(0, alpha * math.pi * 4, 0))
		for _, part in parts do
			part.Transparency = startTransparency[part] + (1 - startTransparency[part]) * alpha
		end
		if alpha >= 1 then
			connection:Disconnect()
			ghost:Destroy()
		end
	end)
end

local function collect(coin: Coin)
	collectedIds[coin.id] = true
	playPickupEffect(coin)
	LocalHide.set(coin.instance, "Collected", true)
	setCFrame(coin.instance, coin.home)
	ProgressUI.coinPickup(Economy.coinValue(coin.instance:GetAttribute("Value"), Config.Coins))
	SoundSystem.play("Coin")
	collectRemote:FireServer(coin.instance)
end

-- Jeden Frame waehrend der Fahrt: Muenzen in Reichweite der Wagenmitte einsammeln
function CoinsClient.update(base: BasePart)
	local position = base.Position
	local now = os.clock()
	for instance, coin in coins do
		if collectedIds[coin.id] or (retryAfter[coin.id] or 0) > now then
			continue
		end
		-- z. B. in einem ausgeblendeten Zufallsereignis: nicht einsammelbar
		if LocalHide.isHidden(instance) then
			continue
		end
		if (coin.home.Position - position).Magnitude <= Config.Coins.PickupRadius + coin.radius then
			collect(coin)
		end
	end
end

-- Server hat abgelehnt. "Already": hatten wir in diesem Lauf schon (bleibt weg).
-- Sonst erscheint die Muenze wieder.
function CoinsClient.onRejected(instance: Instance, reason: string)
	if reason == "Already" then
		return
	end
	local coin = coins[instance]
	if coin then
		collectedIds[coin.id] = nil
		retryAfter[coin.id] = os.clock() + 1
		LocalHide.set(instance, "Collected", false)
	end
end

-- Kompletter Neustart: alle Muenzen wieder da
function CoinsClient.resetAll()
	table.clear(collectedIds)
	table.clear(retryAfter)
	for instance in coins do
		LocalHide.set(instance, "Collected", false)
	end
end

function CoinsClient.init()
	TagList.watch("Coin", register)
	-- Drehen und Wippen (nur sichtbare Muenzen)
	RunService.RenderStepped:Connect(function()
		local C = Config.Coins
		local t = os.clock()
		local angle = math.rad((t * C.SpinSpeed) % 360)
		for instance, coin in coins do
			if not instance:IsDescendantOf(workspace) then
				coins[instance] = nil -- entfernt oder durch Streaming entladen
				continue
			end
			if collectedIds[coin.id] then
				continue
			end
			local bob = math.sin(t * C.BobSpeed + coin.phase) * C.BobHeight
			local home = coin.home
			setCFrame(
				coin.instance,
				CFrame.new(home.Position + Vector3.new(0, bob, 0))
					* CFrame.Angles(0, angle, 0)
					* home.Rotation
			)
		end
	end)
end

return CoinsClient
