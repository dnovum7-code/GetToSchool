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
--   Ragdoll ist nach einem Crash als schlaffe Puppe aus dem Wagen geflogen

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CartBuilder = require(script.Parent:WaitForChild("CartBuilder"))

local CartManager = {}

export type Mode = "Riding" | "OnFoot" | "Ragdoll"

type PlayerState = {
	cart: Model?,
	seatConnection: RBXScriptConnection?,
	mode: Mode,
	lastAction: number, -- Zeitpunkt des letzten Aus-/Einsteigens (Spam-Schutz)
	ragdollSince: number, -- Zeitpunkt des letzten Crashs mit Ragdoll
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
		state = { mode = "Riding", lastAction = -math.huge, ragdollSince = 0 }
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
-- Als Ragdoll hat sie wieder Gewicht, bleibt aber in der Wagen-Gruppe, damit sie sich
-- nicht im eigenen Wagen verhakt.
local function applyModeToPart(part: BasePart, mode: Mode)
	if part:GetAttribute("OriginalMassless") == nil then
		part:SetAttribute("OriginalMassless", part.Massless)
	end
	part.Massless = if mode == "Riding" then true else part:GetAttribute("OriginalMassless") == true
	part.CollisionGroup = if mode == "OnFoot" then "Default" else CartBuilder.COLLISION_GROUP
end

local function setCharacterMode(character: Model, mode: Mode)
	character:SetAttribute("CartMode", mode)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			applyModeToPart(part, mode)
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Im Wagen nicht springen (der Client sperrt den Sprung zusaetzlich).
		local onFoot = mode == "OnFoot"
		humanoid.JumpPower = if onFoot then StarterPlayer.CharacterJumpPower else 0
		humanoid.JumpHeight = if onFoot then StarterPlayer.CharacterJumpHeight else 0
	end
end

-- Ragdoll an/aus. Unity-Vergleich: Animator aus, Character Joints an.
-- In Roblox halten Motor6D-Gelenke die Koerperteile starr zusammen (die Animation bewegt
-- sie). Fuer die Ragdoll schalten wir sie ab und setzen an dieselben Stellen lose
-- Kugelgelenke (BallSocketConstraint) mit Winkelgrenzen.
local function setRagdoll(character: Model, humanoid: Humanoid, enabled: boolean)
	if enabled then
		humanoid.RequiresNeck = false -- sonst stirbt die Figur ohne festen Hals
		local angle = Config.Crash.RagdollJointAngle
		for _, motor in character:GetDescendants() do
			-- Root-Gelenk (unsichtbarer HumanoidRootPart <-> Koerper) bleibt fest
			if motor:IsA("Motor6D") and motor.Name ~= "Root" and motor.Name ~= "RootJoint" then
				local part0, part1 = motor.Part0, motor.Part1
				if part0 and part1 then
					local a0 = Instance.new("Attachment")
					a0.Name = "RagdollAttachment"
					a0.CFrame = motor.C0
					a0:SetAttribute("Ragdoll", true)
					a0.Parent = part0
					local a1 = Instance.new("Attachment")
					a1.Name = "RagdollAttachment"
					a1.CFrame = motor.C1
					a1:SetAttribute("Ragdoll", true)
					a1.Parent = part1
					local socket = Instance.new("BallSocketConstraint")
					socket.Name = "RagdollSocket"
					socket.Attachment0 = a0
					socket.Attachment1 = a1
					socket.LimitsEnabled = true
					socket.UpperAngle = angle
					socket.TwistLimitsEnabled = true
					socket.TwistLowerAngle = -angle
					socket.TwistUpperAngle = angle
					socket:SetAttribute("Ragdoll", true)
					socket.Parent = part1
					motor.Enabled = false
				end
			end
		end
		-- Arme und Beine kollidieren normalerweise nicht; als Ragdoll sollen sie aufschlagen
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				if part:GetAttribute("OriginalCanCollide") == nil then
					part:SetAttribute("OriginalCanCollide", part.CanCollide)
				end
				part.CanCollide = true
			end
		end
	else
		for _, item in character:GetDescendants() do
			if item:GetAttribute("Ragdoll") then
				item:Destroy()
			elseif item:IsA("Motor6D") then
				item.Enabled = true
			elseif item:IsA("BasePart") and item:GetAttribute("OriginalCanCollide") ~= nil then
				item.CanCollide = item:GetAttribute("OriginalCanCollide") == true
			end
		end
		humanoid.RequiresNeck = true
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

local function createCart(player: Player, state: PlayerState, at: CFrame): Model
	if state.cart then
		state.cart:Destroy()
	end
	local cart = CartBuilder.build(player, at)
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
	(character:FindFirstChildOfClass("Humanoid") :: Humanoid).BreakJointsOnDeath = false
	setCharacterMode(character, "Riding")
	-- Accessoires etc. koennen spaeter nachgeladen werden: gleichen Modus anwenden
	character.DescendantAdded:Connect(function(part)
		local mode = character:GetAttribute("CartMode")
		if part:IsA("BasePart") and type(mode) == "string" then
			applyModeToPart(part, mode :: Mode)
		end
	end)
	task.wait() -- einen Frame warten, bis die Figur vollstaendig in der Welt ist
end

-- Neustart: Wagen samt Fahrer sofort an den Start setzen. Ist der Wagen kaputt
-- (z. B. ins Nichts gefallen), wird ein neuer gebaut. Gibt die Startposition zurueck,
-- oder nil, wenn gerade kein Neustart moeglich ist (Figur tot / noch nicht da).
-- `at`: anderer Ort als der Start (z. B. ein Checkpoint).
function CartManager.reset(player: Player, at: CFrame?): CFrame?
	local humanoid = getAliveHumanoid(player)
	if not humanoid then
		return nil
	end
	local state = getState(player)
	local character = humanoid.Parent :: Model
	if state.mode == "Ragdoll" then
		setRagdoll(character, humanoid, false)
	end
	if state.mode ~= "Riding" then
		state.mode = "Riding"
		setCharacterMode(character, "Riding")
	end
	local spawnCFrame = at or spawnResolver(player)
	local cart = state.cart
	if cart and isCartIntact(cart) then
		-- PivotTo verschiebt das ganze Modell; ein angeschweisster Fahrer kommt mit.
		cart:PivotTo(spawnCFrame)
	else
		cart = createCart(player, state, spawnCFrame)
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
	setCharacterMode(character, "OnFoot")
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
	setCharacterMode(humanoid.Parent :: Model, "Riding")
	task.spawn(seatPlayer, player, cart) -- gibt den Physik-Besitz wieder an den Client
	return true
end

-- Crash (vom Client gemeldet): Figur fliegt als Ragdoll aus dem Wagen.
-- Der Wagen bleibt beim Client, damit er sich fluessig weiter ueberschlaegt.
-- Gibt true zurueck, wenn die Ragdoll ausgeloest wurde.
function CartManager.crash(player: Player): boolean
	if not Config.Crash.Ragdoll or not CartManager.isSeated(player) then
		return false
	end
	local state = states[player] :: PlayerState
	local humanoid = getAliveHumanoid(player) :: Humanoid
	local character = humanoid.Parent :: Model
	local seat = getSeat(state.cart :: Model)

	state.mode = "Ragdoll" -- zuerst, damit watchSeat nicht wieder hineinsetzt
	state.ragdollSince = os.clock()
	local seatWeld = seat:FindFirstChild("SeatWeld")
	if seatWeld then
		seatWeld:Destroy()
	end
	setCharacterMode(character, "Ragdoll")
	setRagdoll(character, humanoid, true)
	return true
end

function CartManager.getMode(player: Player): Mode?
	local state = states[player]
	return if state then state.mode else nil
end

-- Seit wann (Sekunden) liegt der Spieler als Ragdoll herum? nil = gar nicht.
function CartManager.getRagdollTime(player: Player): number?
	local state = states[player]
	if state and state.mode == "Ragdoll" then
		return os.clock() - state.ragdollSince
	end
	return nil
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
