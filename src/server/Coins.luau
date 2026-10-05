--!strict
-- Muenzen (Tag "Coin"), Server-Seite. Der Client des Fahrers merkt, wenn er eine Muenze
-- beruehrt, blendet sie bei sich aus und meldet sie. Der Server entscheidet:
--   * Ist es wirklich eine Muenze, und hat dieser Spieler sie in diesem Lauf noch nicht?
--   * Sitzt der Spieler im Wagen, und ist der Wagen nah genug (Plausibilitaetspruefung)?
-- Erst dann gibt es die Muenzen, und zwar sofort in den Spielstand: Sie bleiben auch nach
-- einem Crash oder Abbruch erhalten. Die Muenze erscheint beim kompletten Neustart (T) wieder.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Progression"):WaitForChild("Economy"))
local TagList = require(Shared:WaitForChild("TagList"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local collectRemote = remotes:WaitForChild("CollectCoin") :: RemoteEvent
local progressRemote = remotes:WaitForChild("Progress") :: RemoteEvent

local Coins = {}

local collected: { [Player]: { [Instance]: boolean } } = {} -- in diesem Lauf eingesammelt
local runTotals: { [Player]: number } = {}
local nextId = 0

-- Mitte und halbe Groesse einer Muenze (Part oder Modell)
local function coinShape(coin: Instance): (Vector3?, number)
	if coin:IsA("BasePart") then
		local size = coin.Size
		return coin.Position, math.max(size.X, size.Y, size.Z) / 2
	elseif coin:IsA("Model") then
		local cframe, size = coin:GetBoundingBox()
		return cframe.Position, math.max(size.X, size.Y, size.Z) / 2
	end
	return nil, 0
end

local function prepare(coin: Instance)
	-- Feste Nummer, ueber die der Client "seine" eingesammelten Muenzen wiedererkennt
	-- (auch wenn die Muenze durch Streaming entladen und neu geladen wird)
	if type(coin:GetAttribute("CoinId")) ~= "string" then
		nextId += 1
		coin:SetAttribute("CoinId", tostring(nextId))
	end
	local parts: { BasePart } = {}
	if coin:IsA("BasePart") then
		table.insert(parts, coin)
	end
	for _, descendant in coin:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	for _, part in parts do
		part.Anchored = true
		part.CanCollide = false -- man faehrt hindurch
		part.CanTouch = false
		part.CanQuery = false
		-- Standard-Aussehen (graues Plastik) wird zu Gold, eigene Gestaltung bleibt
		if part.Material == Enum.Material.Plastic and part.Color == Color3.fromRGB(163, 162, 165) then
			part.Material = Enum.Material.Neon
			part.Color = Color3.fromRGB(255, 200, 40)
		end
	end
end

local function reject(player: Player, coin: Instance, reason: string)
	progressRemote:FireClient(player, "CoinRejected", coin, reason)
end

function Coins.collect(player: Player, coin: unknown)
	if typeof(coin) ~= "Instance" then
		return
	end
	local instance = coin :: Instance
	if not instance:HasTag("Coin") or not instance:IsDescendantOf(workspace) then
		reject(player, instance, "Invalid")
		return
	end
	local set = collected[player]
	if not set then
		set = {}
		collected[player] = set
	end
	if set[instance] then
		reject(player, instance, "Already")
		return
	end
	local cart = CartManager.getCart(player)
	local base = cart and cart:FindFirstChild("Base")
	local center, radius = coinShape(instance)
	if not CartManager.isSeated(player) or not base or not base:IsA("BasePart") or not center then
		reject(player, instance, "NotDriving")
		return
	end
	local distance = (base.Position - center).Magnitude
	if not Economy.pickupInRange(distance, base.AssemblyLinearVelocity.Magnitude, radius, Config.Coins) then
		reject(player, instance, "TooFar")
		return
	end

	set[instance] = true
	local value = Economy.coinValue(instance:GetAttribute("Value"), Config.Coins)
	runTotals[player] = (runTotals[player] or 0) + value
	Profiles.get(player).stats.coinsCollected += value
	Profiles.addCoins(player, value)
end

-- Kompletter Neustart (T): Muenzen gibt es wieder, Lauf-Summe auf 0
function Coins.resetRun(player: Player)
	collected[player] = {}
	runTotals[player] = 0
end

-- In diesem Lauf eingesammelt (fuer den Ergebnis-Screen)
function Coins.getRunTotal(player: Player): number
	return runTotals[player] or 0
end

function Coins.init()
	TagList.watch("Coin", prepare)
	collectRemote.OnServerEvent:Connect(function(player, coin)
		Coins.collect(player, coin)
	end)
	Players.PlayerRemoving:Connect(function(player)
		collected[player] = nil
		runTotals[player] = nil
	end)
end

return Coins
