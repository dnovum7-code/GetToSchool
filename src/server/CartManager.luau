--!strict
-- Verwaltet pro Spieler einen Einkaufswagen: erzeugen, Spieler hineinsetzen,
-- Physik an den Client uebergeben und den Wagen an den Start zuruecksetzen.
--
-- Netzwerk-Besitz (Network Ownership): Der Client des Fahrers rechnet die Physik
-- seines Wagens selbst. Dadurch reagiert die Steuerung ohne Verzoegerung.
-- Fortschritt, Zeit und Neustarts entscheidet trotzdem der Server.

local Players = game:GetService("Players")

local CartBuilder = require(script.Parent:WaitForChild("CartBuilder"))

local CartManager = {}

type PlayerState = {
	cart: Model?,
	seatConnection: RBXScriptConnection?,
}

local states: { [Player]: PlayerState } = {}
local cartsFolder: Folder

-- Liefert die Start-Position (Mitte des Korbbodens) fuer einen Spieler.
-- Wird von GameServer gesetzt (spaeter: Startzone).
local spawnResolver: (player: Player) -> CFrame = function(_player)
	return CFrame.new(0, 10, 0)
end

function CartManager.init(folder: Folder)
	cartsFolder = folder
end

function CartManager.setSpawnResolver(resolver: (player: Player) -> CFrame)
	spawnResolver = resolver
end

local function getState(player: Player): PlayerState
	local state = states[player]
	if not state then
		state = {}
		states[player] = state
	end
	return state
end

local function getAliveHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character or not character:IsDescendantOf(workspace) then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function isCartIntact(cart: Model?): boolean
	if not cart or not cart:IsDescendantOf(workspace) then
		return false
	end
	-- Teile unter workspace.FallenPartsDestroyHeight loescht Roblox automatisch.
	local base = cart:FindFirstChild("Base")
	local seat = cart:FindFirstChild("Seat")
	return base ~= nil and base:IsDescendantOf(workspace) and seat ~= nil and seat:IsDescendantOf(workspace)
end

local function getSeat(cart: Model): Seat
	return cart:FindFirstChild("Seat") :: Seat
end

-- Der Client des Fahrers soll die Physik des ganzen Wagens rechnen.
local function giveOwnership(cart: Model, player: Player)
	for _, part in cart:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored and part:CanSetNetworkOwnership() then
			part:SetNetworkOwner(player)
		end
	end
end

-- Spielfigur fuer die Fahrt vorbereiten: kein Gewicht (das Gewicht steckt im Ballast des
-- Wagens) und gleiche Kollisionsgruppe wie die Wagen (Fahrer anderer Wagen stoeren nicht).
local function prepareCharacter(character: Model, humanoid: Humanoid)
	local function preparePart(part: Instance)
		if part:IsA("BasePart") then
			part.Massless = true
			part.CollisionGroup = CartBuilder.COLLISION_GROUP
		end
	end
	for _, part in character:GetDescendants() do
		preparePart(part)
	end
	-- Accessoires etc. koennen spaeter nachgeladen werden
	character.DescendantAdded:Connect(preparePart)

	-- Nicht aus dem Wagen springen (der Client sperrt den Sprung zusaetzlich).
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
end

-- Setzt die Spielfigur in den Sitz. Wiederholt es kurz, falls die Figur noch nicht bereit ist.
local function seatPlayer(player: Player, cart: Model)
	local seat = getSeat(cart)
	for _ = 1, 10 do
		local humanoid = getAliveHumanoid(player)
		if not humanoid or not isCartIntact(cart) then
			return
		end
		if seat.Occupant == humanoid then
			giveOwnership(cart, player)
			return
		end
		seat:Sit(humanoid)
		task.wait(0.1)
	end
	warn(`[CartManager] Konnte {player.Name} nicht in den Wagen setzen`)
end

-- Falls die Figur doch aus dem Sitz faellt (z. B. Sprung), sofort wieder hineinsetzen.
local function watchSeat(player: Player, state: PlayerState, cart: Model)
	if state.seatConnection then
		state.seatConnection:Disconnect()
	end
	local seat = getSeat(cart)
	state.seatConnection = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant == nil and state.cart == cart and getAliveHumanoid(player) then
			task.delay(0.1, function()
				if seat.Occupant == nil and state.cart == cart then
					seatPlayer(player, cart)
				end
			end)
		end
	end)
end

local function createCart(player: Player, state: PlayerState): Model
	if state.cart then
		state.cart:Destroy()
	end
	local cart = CartBuilder.build(player, spawnResolver(player))
	cart.Parent = cartsFolder
	state.cart = cart
	watchSeat(player, state, cart)
	return cart
end

-- Neue Spielfigur: Wagen an den Start setzen (oder neu bauen) und Figur hineinsetzen.
function CartManager.onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	character:WaitForChild("HumanoidRootPart")
	if not character:IsDescendantOf(workspace) then
		character.AncestryChanged:Wait()
	end
	prepareCharacter(character, humanoid)

	local state = getState(player)
	local cart = state.cart
	if cart and isCartIntact(cart) then
		cart:PivotTo(spawnResolver(player))
	else
		cart = createCart(player, state)
	end
	task.wait() -- einen Frame warten, bis die Figur vollstaendig in der Welt ist
	seatPlayer(player, cart :: Model)
end

function CartManager.getCart(player: Player): Model?
	local state = states[player]
	return if state then state.cart else nil
end

function CartManager.removePlayer(player: Player)
	local state = states[player]
	if not state then
		return
	end
	if state.seatConnection then
		state.seatConnection:Disconnect()
	end
	if state.cart then
		state.cart:Destroy()
	end
	states[player] = nil
end

Players.PlayerRemoving:Connect(CartManager.removePlayer)

return CartManager
