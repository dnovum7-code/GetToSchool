--!strict
-- Verwaltet pro Spieler einen Einkaufswagen: erzeugen, Spieler hinein- und hinaussetzen,
-- Physik-Besitz verteilen und den Wagen an den Start zuruecksetzen.
--
-- Netzwerk-Besitz (Network Ownership): Sitzt der Spieler im Wagen, rechnet sein Client die
-- Physik des Wagens selbst (Steuerung ohne Verzoegerung). Ist der Wagen leer, rechnet
-- wieder der Server. Fortschritt, Zeit und Neustarts entscheidet immer der Server.
--
-- Modus pro Spieler:
--   Riding  sitzt im Wagen (wird automatisch wieder hineingesetzt, falls er herausfaellt)
--   OnFoot  ist mit E ausgestiegen und laeuft herum

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CartBuilder = require(script.Parent:WaitForChild("CartBuilder"))

local CartManager = {}

export type Mode = "Riding" | "OnFoot"

type PlayerState = {
	cart: Model?,
	seatConnection: RBXScriptConnection?,
	mode: Mode,
	lastAction: number, -- Zeitpunkt des letzten Aus-/Einsteigens (Spam-Schutz)
}

local states: { [Player]: PlayerState } = {}
local cartsFolder: Folder

-- Liefert die Start-Position (Mitte des Korbbodens) fuer einen Spieler.
-- Wird von GameServer gesetzt (Startzone, siehe Track.getSpawn).
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
		state = { mode = "Riding", lastAction = -math.huge }
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

local function getBase(cart: Model): BasePart
	return cart:FindFirstChild("Base") :: BasePart
end

-- Physik des ganzen Wagens an `owner` geben (nil = Server).
local function setOwner(cart: Model, owner: Player?)
	for _, part in cart:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored and part:CanSetNetworkOwnership() then
			part:SetNetworkOwner(owner)
		end
	end
end

-- Im Wagen hat die Figur kein Gewicht (das Gewicht steckt im Ballast) und gehoert zur
-- Kollisionsgruppe der Wagen (Fahrer anderer Wagen stoeren nicht). Zu Fuss: alles normal.
local function applyRidingToPart(part: BasePart, riding: boolean)
	if part:GetAttribute("OriginalMassless") == nil then
		part:SetAttribute("OriginalMassless", part.Massless)
	end
	if riding then
		part.Massless = true
		part.CollisionGroup = CartBuilder.COLLISION_GROUP
	else
		part.Massless = part:GetAttribute("OriginalMassless") == true
		part.CollisionGroup = "Default"
	end
end

local function setRiding(character: Model, riding: boolean)
	character:SetAttribute("Riding", riding)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			applyRidingToPart(part, riding)
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Im Wagen nicht springen (der Client sperrt den Sprung zusaetzlich).
		humanoid.JumpPower = if riding then 0 else StarterPlayer.CharacterJumpPower
		humanoid.JumpHeight = if riding then 0 else StarterPlayer.CharacterJumpHeight
	end
end

-- Setzt die Spielfigur in den Sitz. Wiederholt es kurz, falls die Figur noch nicht bereit ist.
local function seatPlayer(player: Player, cart: Model)
	local seat = getSeat(cart)
	for _ = 1, 10 do
		local humanoid = getAliveHumanoid(player)
		if not humanoid or not isCartIntact(cart) or getState(player).mode ~= "Riding" then
			return
		end
		if seat.Occupant == humanoid then
			setOwner(cart, player)
			return
		end
		seat:Sit(humanoid)
		task.wait(0.1)
	end
	warn(`[CartManager] Konnte {player.Name} nicht in den Wagen setzen`)
end

-- Falls die Figur ungewollt aus dem Sitz faellt, sofort wieder hineinsetzen.
-- (Nicht, wenn der Spieler absichtlich ausgestiegen ist.)
local function watchSeat(player: Player, state: PlayerState, cart: Model)
	if state.seatConnection then
		state.seatConnection:Disconnect()
	end
	local seat = getSeat(cart)
	state.seatConnection = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if
			seat.Occupant == nil
			and state.cart == cart
			and state.mode == "Riding"
			and getAliveHumanoid(player)
		then
			task.delay(0.1, function()
				if seat.Occupant == nil and state.cart == cart and state.mode == "Riding" then
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

-- Freien Platz neben dem Wagen suchen: rechts, links, hinten, vorne. Liefert die
-- CFrame fuer die Spielfigur (aufrecht, Blick in Fahrtrichtung).
local function findLandingSpot(cart: Model, character: Model, humanoid: Humanoid): CFrame
	local base = getBase(cart)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local look = Vector3.new(base.CFrame.LookVector.X, 0, base.CFrame.LookVector.Z)
	look = if look.Magnitude > 0.1 then look.Unit else -Vector3.zAxis
	local right = look:Cross(Vector3.yAxis)

	local side = Config.Cart.Width / 2 + Config.Exit.LandingDistance
	local frontBack = Config.Cart.Length / 2 + Config.Exit.LandingDistance
	local candidates = { right * side, -right * side, -look * frontBack, look * frontBack }

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { cartsFolder, character }
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { cartsFolder, character }

	local rootHeight = humanoid.HipHeight + root.Size.Y / 2
	for _, offset in candidates do
		local probe = base.Position + offset + Vector3.new(0, 6, 0)
		local hit = workspace:Raycast(probe, Vector3.new(0, -20, 0), rayParams)
		-- nur auf begehbarem Boden landen (nicht an steilen Waenden)
		if hit and hit.Normal.Y > 0.5 then
			local position = hit.Position + Vector3.new(0, rootHeight + 0.2, 0)
			local blocking =
				workspace:GetPartBoundsInBox(CFrame.new(position), Vector3.new(2, 4, 2), overlapParams)
			if #blocking == 0 then
				return CFrame.lookAt(position, position + look)
			end
		end
	end
	-- Notfall: ueber dem Wagen absetzen
	local position = base.Position + Vector3.new(0, 6, 0)
	return CFrame.lookAt(position, position + look)
end

-- Neue Spielfigur vorbereiten. Danach ruft der Aufrufer CartManager.reset auf,
-- das den Wagen an den Start setzt (oder neu baut) und die Figur hineinsetzt.
function CartManager.onCharacterAdded(_player: Player, character: Model)
	character:WaitForChild("Humanoid")
	character:WaitForChild("HumanoidRootPart")
	if not character:IsDescendantOf(workspace) then
		character.AncestryChanged:Wait()
	end
	setRiding(character, true)
	-- Accessoires etc. koennen spaeter nachgeladen werden: gleichen Modus anwenden
	character.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") then
			applyRidingToPart(part, character:GetAttribute("Riding") == true)
		end
	end)
	task.wait() -- einen Frame warten, bis die Figur vollstaendig in der Welt ist
end

-- Neustart: Wagen samt Fahrer sofort an den Start setzen. Ist der Wagen kaputt
-- (z. B. ins Nichts gefallen), wird ein neuer gebaut. Gibt die Startposition zurueck,
-- oder nil, wenn gerade kein Neustart moeglich ist (Figur tot / noch nicht da).
function CartManager.reset(player: Player): CFrame?
	local humanoid = getAliveHumanoid(player)
	if not humanoid then
		return nil
	end
	local state = getState(player)
	if state.mode ~= "Riding" then
		state.mode = "Riding"
		setRiding(humanoid.Parent :: Model, true)
	end
	local spawnCFrame = spawnResolver(player)
	local cart = state.cart
	if cart and isCartIntact(cart) then
		-- PivotTo verschiebt das ganze Modell; ein angeschweisster Fahrer kommt mit.
		cart:PivotTo(spawnCFrame)
	else
		cart = createCart(player, state)
	end
	local seat = getSeat(cart :: Model)
	if seat.Occupant ~= humanoid then
		task.spawn(seatPlayer, player, cart :: Model)
	end
	return spawnCFrame
end

local function canAct(state: PlayerState): boolean
	if os.clock() - state.lastAction < Config.Exit.ActionCooldown then
		return false
	end
	state.lastAction = os.clock()
	return true
end

-- Aussteigen (Taste E). Gibt die Landeposition zurueck oder nil, wenn es nicht geht.
function CartManager.exit(player: Player): CFrame?
	local state = states[player]
	local humanoid = getAliveHumanoid(player)
	local cart = state and state.cart
	if not state or not humanoid or not cart or not isCartIntact(cart) then
		return nil
	end
	local seat = getSeat(cart)
	if state.mode ~= "Riding" or seat.Occupant ~= humanoid or not canAct(state) then
		return nil
	end
	local character = humanoid.Parent :: Model
	local landing = findLandingSpot(cart, character, humanoid)

	state.mode = "OnFoot" -- zuerst, damit watchSeat nicht wieder hineinsetzt
	local seatWeld = seat:FindFirstChild("SeatWeld")
	if seatWeld then
		seatWeld:Destroy() -- so steht man in Roblox von einem Sitz auf
	end
	setRiding(character, false)
	setOwner(cart, nil) -- leerer Wagen: der Server rechnet die Physik
	character:PivotTo(landing)
	return landing
end

-- Einsteigen (Taste E am eigenen, leeren Wagen).
function CartManager.enter(player: Player): boolean
	local state = states[player]
	local humanoid = getAliveHumanoid(player)
	local cart = state and state.cart
	if not state or not humanoid or not cart or not isCartIntact(cart) then
		return false
	end
	if state.mode ~= "OnFoot" or getSeat(cart).Occupant ~= nil then
		return false
	end
	-- Abstand pruefen: dem Client nie blind glauben (etwas Toleranz fuer Verzoegerung)
	local root = (humanoid.Parent :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - getBase(cart).Position).Magnitude > Config.Exit.EnterDistance + 4 then
		return false
	end
	if not canAct(state) then
		return false
	end
	state.mode = "Riding"
	setRiding(humanoid.Parent :: Model, true)
	task.spawn(seatPlayer, player, cart) -- gibt den Physik-Besitz wieder an den Client
	return true
end

-- Sitzt der Spieler gerade wirklich im eigenen Wagen?
function CartManager.isSeated(player: Player): boolean
	local state = states[player]
	local humanoid = getAliveHumanoid(player)
	local cart = state and state.cart
	return state ~= nil
		and state.mode == "Riding"
		and humanoid ~= nil
		and cart ~= nil
		and isCartIntact(cart)
		and getSeat(cart).Occupant == humanoid
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

-- Parkbremse: Ein leerer Wagen (Server rechnet die Physik) bremst ab und bleibt auch am
-- Hang stehen, statt ohne Fahrer ins Tal zu rollen.
local function applyParkBrake(cart: Model)
	local base = getBase(cart)
	local driveForce = base:FindFirstChild("DriveForce") :: VectorForce?
	local steerTorque = base:FindFirstChild("SteerTorque") :: Torque?
	if not driveForce or not steerTorque then
		return
	end
	steerTorque.Torque = Vector3.zero
	if Config.Exit.ParkBrake <= 0 then
		driveForce.Force = Vector3.zero
		return
	end
	local accel = -base.AssemblyLinearVelocity * Config.Exit.ParkBrake
	local maxAccel = Config.Exit.ParkBrakeMaxAcceleration
	if accel.Magnitude > maxAccel then
		accel = accel.Unit * maxAccel
	end
	-- Steht der Wagen aufrecht auf dem Boden, den Hangabtrieb ausgleichen
	local up = base.CFrame.UpVector
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { cart }
	local groundCheck = CartBuilder.getRideHeight() + 0.6
	if up.Y > 0.7 and workspace:Raycast(base.Position, -up * groundCheck, rayParams) then
		local gravity = Vector3.new(0, -workspace.Gravity, 0)
		accel -= gravity - up * gravity:Dot(up)
	end
	driveForce.Force = accel * CartBuilder.getMass(cart)
end

RunService.Heartbeat:Connect(function()
	for _, state in states do
		local cart = state.cart
		if state.mode == "OnFoot" and cart and isCartIntact(cart) then
			applyParkBrake(cart)
		end
	end
end)

Players.PlayerRemoving:Connect(CartManager.removePlayer)

return CartManager
