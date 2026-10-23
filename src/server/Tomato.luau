--!strict
-- Tomaten (Duo-Schuetze, Chaos "Items"), Server-Seite.
--   * Munition pro Werfer (Config.Tomato.MaxAmmo), laedt langsam nach (RegenInterval) oder per
--     ItemBox (Tag) wieder auf. Abklingzeit zwischen Wuerfen.
--   * Der Server rechnet die Bahn mit seinen Positionen der Ziele (TomatoMath.firstHit) und
--     grosszuegigem Spielraum (HitRadius). Ziele: andere Wagen und Spieler zu Fuss; Solo-Laeufe
--     sind geschuetzt (ProtectSolo), ausser Einstellung "bewerfbar" (TomatoOptIn).
--   * Alle sehen die Tomate fliegen ("Fly"); Getroffene bekommen "Splat" (Matsch, Schubs; den
--     Schubs wendet der Client an, der die Physik rechnet). Kein Lebensverlust.
-- Client: client/TomatoClient.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CrewRules = require(Shared:WaitForChild("Crew"):WaitForChild("CrewRules"))
local TomatoMath = require(Shared:WaitForChild("Crew"):WaitForChild("TomatoMath"))
local TagList = require(Shared:WaitForChild("TagList"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local Crew = require(script.Parent:WaitForChild("Crew"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local RaceManager = require(script.Parent:WaitForChild("RaceManager"))

local tomatoRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Tomato") :: RemoteEvent

local Tomato = {}

type Ammo = { ammo: number, lastRegen: number, lastThrow: number }

local ammoOf: { [Player]: Ammo } = {}
local boxCooldown: { [Instance]: { [Player]: number } } = {} -- ItemBox -> Gastgeber -> frei ab

local function getAmmo(player: Player): Ammo
	local state = ammoOf[player]
	if not state then
		state = { ammo = Config.Tomato.MaxAmmo, lastRegen = os.clock(), lastThrow = -math.huge }
		ammoOf[player] = state
	end
	local current = state :: Ammo
	current.ammo, current.lastRegen = CrewRules.regen(
		current.ammo,
		Config.Tomato.MaxAmmo,
		current.lastRegen,
		os.clock(),
		Config.Tomato.RegenInterval
	)
	return current
end

local function sendAmmo(player: Player)
	tomatoRemote:FireClient(player, "Ammo", getAmmo(player).ammo, Config.Tomato.MaxAmmo)
end

local function vec(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

-- Darf `victim` getroffen werden?
local function hittable(victim: Player): boolean
	local inCrew = Crew.isActive(victim)
	local soloRunning = not inCrew and not RaceManager.isOutsideRun(victim)
	local data = Profiles.get(victim)
	local optIn = data ~= nil and (data.settings :: any).TomatoOptIn == true
	return CrewRules.canBeHit(inCrew, soloRunning, optIn, Config.Tomato.ProtectSolo)
end

type Target = TomatoMath.Target & { part: BasePart, victims: { Player }, push: Player }

-- Alle Ziele ausser der eigenen Crew
local function collectTargets(thrower: Player): { Target }
	local crew = Crew.of(thrower)
	local own: { [Player]: boolean } = { [thrower] = true }
	if crew then
		for _, member in Crew.members(crew) do
			own[member] = true
		end
	end
	local targets: { Target } = {}
	local radius = Config.Tomato.HitRadius
	for _, other in Players:GetPlayers() do
		if not own[other] then
			local cart = CartManager.getCart(other)
			local base = cart and cart:FindFirstChild("Base")
			local mode = CartManager.getMode(other)
			if mode == "Riding" and base and base:IsA("BasePart") and hittable(other) then
				local otherCrew = Crew.ofCart(cart :: Model)
				local victims = if otherCrew then Crew.members(otherCrew) else { other }
				local p = base.Position
				table.insert(targets, {
					id = #targets + 1,
					x = p.X,
					y = p.Y,
					z = p.Z,
					radius = radius,
					part = base,
					victims = victims,
					push = other,
				})
			elseif mode == "OnFoot" and hittable(other) then
				local character = other.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					local p = root.Position
					table.insert(targets, {
						id = #targets + 1,
						x = p.X,
						y = p.Y,
						z = p.Z,
						radius = radius * 0.6,
						part = root,
						victims = { other },
						push = other,
					})
				end
			end
		end
	end
	return targets
end

local function throw(player: Player, aim: unknown)
	if not Crew.canThrow(player) then
		return
	end
	local state = getAmmo(player)
	local now = os.clock()
	if state.ammo <= 0 then
		tomatoRemote:FireClient(player, "Empty")
		return
	end
	if now - state.lastThrow < Config.Tomato.Cooldown then
		return
	end
	local crew = Crew.of(player)
	local cart = crew and CartManager.getCart(crew.host)
	local base = cart and cart:FindFirstChild("Base")
	if not crew or not base or not base:IsA("BasePart") then
		return
	end
	-- Richtung: Duo = Zielrichtung vom Client (gepruefte Einheitsrichtung), sonst nach vorne
	local direction = base.CFrame.LookVector
	if typeof(aim) == "Vector3" and aim.Magnitude > 0.1 and aim.Magnitude < 1e4 then
		direction = (aim :: Vector3).Unit
	end
	direction = Vector3.new(direction.X, math.max(direction.Y, -0.3), direction.Z).Unit
	state.ammo -= 1
	state.lastThrow = now
	if state.ammo == Config.Tomato.MaxAmmo - 1 then
		state.lastRegen = now -- Nachladen zaehlt ab dem ersten fehlenden Wurf
	end
	local T = Config.Tomato
	local origin = base.Position + Vector3.new(0, 3, 0)
	local velocity = direction * T.Speed + Vector3.new(0, T.Up, 0) + base.AssemblyLinearVelocity
	local targets = collectTargets(player)
	local hitId, hitTime =
		TomatoMath.firstHit(vec(origin), vec(velocity), T.Gravity, targets, T.MaxTime, 0.03)
	local flightTime = hitTime or T.MaxTime
	tomatoRemote:FireAllClients("Fly", origin, velocity, T.Gravity, flightTime, player.UserId)
	sendAmmo(player)
	if not hitId then
		return
	end
	local target = targets[hitId :: number]
	task.delay(flightTime, function()
		local push = Vector3.new(velocity.X, 0, velocity.Z)
		push = if push.Magnitude > 0.01 then push.Unit * T.Push else Vector3.zero
		for _, victim in target.victims do
			if victim.Parent then
				tomatoRemote:FireClient(
					victim,
					"Splat",
					player.DisplayName,
					if victim == target.push then push else nil
				)
			end
		end
		tomatoRemote:FireClient(player, "Hit", target.push.DisplayName)
	end)
end

-- ItemBox: Wagen einer Crew faehrt durch -> alle Werfer der Crew wieder voll
local function checkItemBoxes()
	local boxes = TagList.get("ItemBox")
	if #boxes == 0 then
		return
	end
	local now = os.clock()
	for _, host in Players:GetPlayers() do
		local crew, role = Crew.of(host)
		if crew and role == "Host" then
			local cart = CartManager.getCart(host)
			local base = cart and cart:FindFirstChild("Base")
			if base and base:IsA("BasePart") then
				for _, box in boxes do
					local part = if box:IsA("BasePart")
						then box
						else box:FindFirstChildWhichIsA("BasePart", true)
					local cooldowns = boxCooldown[box] or {}
					boxCooldown[box] = cooldowns
					if
						part
						and (part.Position - base.Position).Magnitude <= Config.Tomato.ItemBoxRadius
						and now >= (cooldowns[host] or 0)
					then
						cooldowns[host] = now + Config.Tomato.ItemBoxCooldown
						for _, member in Crew.members(crew) do
							local state = getAmmo(member)
							state.ammo =
								math.min(Config.Tomato.MaxAmmo, state.ammo + Config.Tomato.ItemBoxRefill)
							sendAmmo(member)
							tomatoRemote:FireClient(member, "ItemBox", box, Config.Tomato.ItemBoxCooldown)
						end
					end
				end
			end
		end
	end
end

function Tomato.init()
	tomatoRemote.OnServerEvent:Connect(function(player, kind, aim)
		if kind == "Throw" then
			throw(player, aim)
		elseif kind == "Ammo" then
			sendAmmo(player)
		end
	end)
	Crew.setItemsHandler(function(player)
		throw(player, nil)
	end)
	Players.PlayerRemoving:Connect(function(player)
		ammoOf[player] = nil
		for _, cooldowns in boxCooldown do
			cooldowns[player] = nil
		end
	end)
	local last = 0
	RunService.Heartbeat:Connect(function()
		if os.clock() - last > 0.15 then
			last = os.clock()
			checkItemBoxes()
		end
	end)
end

return Tomato
