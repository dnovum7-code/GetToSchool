--!strict
-- Duo- und Chaos-Wagen, Server-Seite.
--   * Wagen-Typ waehlen (Menue-Reiter "Wagen"): Solo, Duo (2 Plaetze), Chaos (bis 4 Plaetze).
--     Der Wagen wird mit Zusatzsitzen neu gebaut (CartBuilder, Attribut CrewKind).
--   * Mitfahren: Einladung (Annehmen im Popup) oder zu Fuss mit E an einen Wagen mit freiem
--     Platz. Mitfahrer haben keinen eigenen Wagen (CartManager "Passenger") und sind in der
--     RaceManager-Phase "Crew": Zeit, Leben, Muenzen und Belohnung gelten fuer alle.
--   * Physik: rechnet der Fahrer/Gastgeber. Chaos: Steuerelemente werden verteilt
--     (CrewRules.assign, alle Config.Crew.Chaos.ShuffleInterval s neu mit Countdown); die
--     Mitfahrer schicken ihre gedrueckten Steuerelemente als Bits (UnreliableRemoteEvent
--     "CrewInput"), Einmal-Aktionen mit laufender Nummer ("Crew", "Action"). Der Server laesst
--     nur durch, was dem Absender gehoert, und leitet an den Gastgeber weiter.
--   * Wer geht: Mitfahrer -> Steuerelemente neu verteilt. Gastgeber -> der erste Mitfahrer
--     uebernimmt Wagen, Physik und Lauf (CartManager.transferCart, RaceManager.transferRace).
-- Logik: shared/Crew/CrewRules.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CrewRules = require(Shared:WaitForChild("Crew"):WaitForChild("CrewRules"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local RaceManager = require(script.Parent:WaitForChild("RaceManager"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local crewRemote = remotes:WaitForChild("Crew") :: RemoteEvent
local inputRemote = remotes:WaitForChild("CrewInput") :: UnreliableRemoteEvent

local Crew = {}

export type Kind = "Duo" | "Chaos"

export type CrewData = {
	host: Player,
	kind: Kind,
	seats: { [string]: Player }, -- "CrewSeat2" -> Mitfahrer
	assignment: { [string]: number }, -- Chaos: Steuerelement -> UserId
	seed: number,
	nextShuffleAt: number?, -- Serverzeit
	countdown: number, -- zuletzt angesagte Countdown-Zahl
	lastSeq: { [Player]: number },
}

local crews: { [Player]: CrewData } = {} -- Gastgeber -> Crew
local guestCrew: { [Player]: CrewData } = {} -- Mitfahrer -> Crew
local invites: { [Player]: { from: Player, at: number } } = {}
local itemsHandler: ((Player) -> ())? = nil -- Tomate werfen (server/Tomato)

local function seatNames(kind: Kind): { string }
	local result = {}
	for i = 2, Config.Crew.Seats[kind] do
		table.insert(result, "CrewSeat" .. i)
	end
	return result
end

-- Mitfahrer in Sitz-Reihenfolge
local function guests(crew: CrewData): { Player }
	local result = {}
	for _, name in seatNames(crew.kind) do
		local guest = crew.seats[name]
		if guest then
			table.insert(result, guest)
		end
	end
	return result
end

local function members(crew: CrewData): { Player }
	local result = { crew.host }
	for _, guest in guests(crew) do
		table.insert(result, guest)
	end
	return result
end

local function freeSeat(crew: CrewData): string?
	for _, name in seatNames(crew.kind) do
		if not crew.seats[name] then
			return name
		end
	end
	return nil
end

-- Chaos: Steuerelemente verteilen (zu wenige Mitfahrer: alles beim Gastgeber)
local function reassign(crew: CrewData)
	if crew.kind ~= "Chaos" then
		crew.assignment = {}
		crew.nextShuffleAt = nil
		return
	end
	local list = members(crew)
	local ids = {}
	for _, player in list do
		table.insert(ids, player.UserId)
	end
	if #ids < Config.Crew.Chaos.MinPlayers then
		ids = { crew.host.UserId }
	end
	crew.assignment = CrewRules.assign(ids, crew.seed)
	local interval = Config.Crew.Chaos.ShuffleInterval
	crew.nextShuffleAt = if interval > 0 and #ids >= 2 then workspace:GetServerTimeNow() + interval else nil
	crew.countdown = 0
end

-- Wagen-Anzeige fuer alle (freie Plaetze ueber dem Wagen) und Stand an die Crew
local function broadcast(crew: CrewData)
	local cart = CartManager.getCart(crew.host)
	local free = 0
	for _, name in seatNames(crew.kind) do
		if not crew.seats[name] then
			free += 1
		end
	end
	if cart then
		cart:SetAttribute("CrewFree", free)
		cart:SetAttribute("CrewHostName", crew.host.DisplayName)
	end
	local seatList = {}
	for _, name in seatNames(crew.kind) do
		local guest = crew.seats[name]
		table.insert(seatList, {
			seat = name,
			userId = if guest then guest.UserId else 0,
			name = if guest then guest.DisplayName else "",
		})
	end
	local data = {
		kind = crew.kind,
		hostId = crew.host.UserId,
		hostName = crew.host.DisplayName,
		seats = seatList,
		assignment = crew.assignment,
		nextShuffleAt = crew.nextShuffleAt,
	}
	for _, player in members(crew) do
		crewRemote:FireClient(player, "State", data)
	end
end

local function sendNone(player: Player)
	crewRemote:FireClient(player, "State", nil)
end

-- Mitfahrer steigt aus (oder hat das Spiel verlassen: `stillHere` = false)
local function removeGuest(player: Player, stillHere: boolean)
	local crew = guestCrew[player]
	if not crew then
		return
	end
	guestCrew[player] = nil
	for name, guest in crew.seats do
		if guest == player then
			crew.seats[name] = nil
		end
	end
	crew.lastSeq[player] = nil
	CartManager.removePassenger(player)
	if stillHere then
		sendNone(player)
		RaceManager.leaveCrew(player) -- normaler Neustart mit eigenem Wagen
	end
	reassign(crew)
	broadcast(crew)
end

-- Gastgeber gibt den Wagen ab: der erste Mitfahrer uebernimmt (Physik, Lauf, Crew)
local function handover(oldHost: Player)
	local crew = crews[oldHost]
	if not crew then
		return
	end
	crews[oldHost] = nil
	local list = guests(crew)
	local newHost = list[1]
	if not newHost then
		return
	end
	for name, guest in crew.seats do
		if guest == newHost then
			crew.seats[name] = nil
		end
	end
	guestCrew[newHost] = nil
	crew.host = newHost
	crews[newHost] = crew
	RaceManager.transferRace(oldHost, newHost)
	if not CartManager.transferCart(oldHost, newHost) then
		-- Wagen kaputt: neuer Gastgeber startet neu (baut seinen Duo-/Chaos-Wagen)
		RaceManager.restart(newHost)
	end
	reassign(crew)
	broadcast(crew)
	for _, player in members(crew) do
		crewRemote:FireClient(player, "Handover", newHost.DisplayName)
	end
end

-- Crew aufloesen (Gastgeber waehlt Solo): alle Mitfahrer steigen aus
local function dissolve(host: Player)
	local crew = crews[host]
	if not crew then
		return
	end
	for _, guest in guests(crew) do
		removeGuest(guest, true)
	end
	crews[host] = nil
	local cart = CartManager.getCart(host)
	if cart then
		cart:SetAttribute("CrewFree", nil)
		cart:SetAttribute("CrewHostName", nil)
	end
	sendNone(host)
end

local function join(player: Player, crew: CrewData): boolean
	local seat = freeSeat(crew)
	local cart = CartManager.getCart(crew.host)
	if not seat or not cart or player == crew.host or guestCrew[player] then
		return false
	end
	if RaceManager.isInParty(player) or RaceManager.isInParty(crew.host) then
		return false
	end
	dissolve(player) -- war selbst Gastgeber: eigene Crew aufloesen
	RaceManager.enterCrew(player)
	if not CartManager.seatPassenger(player, cart, seat) then
		RaceManager.leaveCrew(player)
		return false
	end
	crew.seats[seat] = player
	guestCrew[player] = crew
	invites[player] = nil
	reassign(crew)
	broadcast(crew)
	-- gemeinsam von vorne
	RaceManager.restart(crew.host)
	return true
end

local function setKind(player: Player, kind: unknown)
	if guestCrew[player] or not RaceManager.isOutsideRun(player) then
		return
	end
	if kind == "Solo" then
		dissolve(player)
	elseif kind == "Duo" or kind == "Chaos" then
		local existing = crews[player]
		if existing and existing.kind ~= kind then
			dissolve(player)
		end
		if not crews[player] then
			crews[player] = {
				host = player,
				kind = kind :: Kind,
				seats = {},
				assignment = {},
				seed = math.random(1, 1000000),
				nextShuffleAt = nil,
				countdown = 0,
				lastSeq = {},
			}
		end
	else
		return
	end
	RaceManager.restart(player) -- Wagen neu bauen (mit/ohne Zusatzsitze)
	local crew = crews[player]
	if crew then
		reassign(crew)
		broadcast(crew)
	end
end

-- Zu Fuss mit E an einem fremden Wagen mit freiem Platz
local function joinNearby(player: Player, hostId: unknown)
	if type(hostId) ~= "number" then
		return
	end
	local host = Players:GetPlayerByUserId(hostId)
	local crew = host and crews[host]
	local cart = host and CartManager.getCart(host)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local base = cart and cart:FindFirstChild("Base")
	if not crew or not root or not base or not root:IsA("BasePart") or not base:IsA("BasePart") then
		return
	end
	if (root.Position - base.Position).Magnitude > Config.Exit.EnterDistance + 8 then
		return
	end
	join(player, crew)
end

local function invite(host: Player, target: unknown)
	local crew = crews[host]
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target == host or not crew then
		return
	end
	local targetPlayer = target :: Player
	if not freeSeat(crew) or guestCrew[targetPlayer] then
		return
	end
	invites[targetPlayer] = { from = host, at = os.clock() }
	crewRemote:FireClient(targetPlayer, "Invite", host, crew.kind)
end

local function accept(player: Player, from: unknown)
	local pending = invites[player]
	invites[player] = nil
	if not pending or (pending.from :: any) ~= from or os.clock() - pending.at > Config.Crew.InviteTime then
		return
	end
	local crew = crews[pending.from]
	if crew then
		join(player, crew)
	end
end

-- Einmal-Aktion eines Mitfahrers (Sprung, Boost, Tomate) -> an den Gastgeber
local function action(player: Player, name: unknown, seq: unknown)
	local crew = guestCrew[player]
	if not crew or crew.kind ~= "Chaos" or type(name) ~= "string" then
		return
	end
	if not CrewRules.acceptSeq(crew.lastSeq[player], seq) then
		return -- doppelt oder alt
	end
	crew.lastSeq[player] = seq :: number
	if crew.assignment[name] ~= player.UserId then
		return -- gehoert ihm nicht
	end
	if name == "Items" then
		-- Tomate: wirft der Server direkt (Munition gehoert dem Werfer)
		local handler = itemsHandler
		if handler then
			handler(player)
		end
		return
	end
	crewRemote:FireClient(crew.host, "Action", name, player.UserId)
end

-- Gedrueckte Steuerelemente eines Mitfahrers -> gefiltert an den Gastgeber
local function onInput(player: Player, bits: unknown)
	local crew = guestCrew[player]
	if not crew or crew.kind ~= "Chaos" or type(bits) ~= "number" or bits ~= bits then
		return
	end
	local allowed = CrewRules.allowedBits(crew.assignment, player.UserId, bits)
	inputRemote:FireClient(crew.host, player.UserId, allowed)
end

-- Fuer andere Module ----------------------------------------------------------------------

-- Crew eines Spielers (als Gastgeber oder Mitfahrer) und seine Rolle
function Crew.of(player: Player): (CrewData?, string?)
	local own = crews[player]
	if own then
		return own, "Host"
	end
	local guest = guestCrew[player]
	if guest then
		return guest, "Guest"
	end
	return nil, nil
end

-- Ist der Spieler in einem Duo-/Chaos-Wagen mit mindestens einem Mitfahrer?
function Crew.isActive(player: Player): boolean
	local crew = Crew.of(player)
	return crew ~= nil and #guests(crew) > 0
end

-- Darf dieser Spieler Tomaten werfen? Duo: der Schuetze hinten. Chaos: wer "Items" hat.
function Crew.canThrow(player: Player): boolean
	local crew = Crew.of(player)
	if not crew then
		return false
	end
	if crew.kind == "Duo" then
		return crew.seats.CrewSeat2 == player
	end
	return crew.assignment.Items == player.UserId
end

function Crew.setItemsHandler(handler: (Player) -> ())
	itemsHandler = handler
end

-- Crew dieses Wagens (ueber den Besitzer)
function Crew.ofCart(cart: Model): CrewData?
	local ownerId = cart:GetAttribute("OwnerUserId")
	local owner = if type(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
	return if owner then crews[owner] else nil
end

function Crew.members(crew: CrewData): { Player }
	return members(crew)
end

function Crew.init()
	RaceManager.setCrewHooks({
		hostOf = function(player)
			local crew = guestCrew[player]
			return if crew then crew.host else nil
		end,
		guestsOf = function(host)
			local crew = crews[host]
			return if crew then guests(crew) else {}
		end,
		kindOf = function(host)
			local crew = crews[host]
			return if crew then crew.kind else nil
		end,
		respawnGuest = function(player)
			local crew = guestCrew[player]
			local cart = crew and CartManager.getCart(crew.host)
			if not crew or not cart then
				return
			end
			for name, guest in crew.seats do
				if guest == player then
					CartManager.seatPassenger(player, cart, name)
				end
			end
		end,
	})
	CartManager.setCrewKindResolver(function(player)
		local crew = crews[player]
		return if crew then crew.kind else nil
	end)
	CartManager.setRemoveHook(function(player)
		invites[player] = nil
		if crews[player] then
			handover(player)
		end
		removeGuest(player, false)
	end)
	Profiles.setCoinShare(function(player)
		local crew = crews[player]
		return if crew then guests(crew) else {}
	end)
	crewRemote.OnServerEvent:Connect(function(player, kind, a, b)
		if kind == "SetKind" then
			setKind(player, a)
		elseif kind == "Invite" then
			invite(player, a)
		elseif kind == "Accept" then
			accept(player, a)
		elseif kind == "Decline" then
			invites[player] = nil
		elseif kind == "Join" then
			joinNearby(player, a)
		elseif kind == "Leave" then
			if guestCrew[player] then
				removeGuest(player, true)
			end
		elseif kind == "Action" then
			action(player, a, b)
		elseif kind == "Hello" then
			local crew = Crew.of(player)
			if crew then
				broadcast(crew)
			end
		end
	end)
	inputRemote.OnServerEvent:Connect(onInput)
	-- Gastgeber stirbt (Figur weg): der naechste Mitfahrer uebernimmt
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid
			humanoid.Died:Connect(function()
				local crew = crews[player]
				if crew and #guests(crew) > 0 then
					handover(player)
				end
			end)
		end)
	end)
	-- Chaos: regelmaessig neu mischen, mit Countdown
	RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		for _, crew in crews do
			local at = crew.nextShuffleAt
			if at then
				local left = math.ceil(at - now)
				if left <= Config.Crew.Chaos.ShuffleCountdown and left > 0 and left ~= crew.countdown then
					crew.countdown = left
					for _, player in members(crew) do
						crewRemote:FireClient(player, "ShuffleSoon", left)
					end
				elseif now >= at then
					crew.seed += 1
					reassign(crew)
					broadcast(crew)
					for _, player in members(crew) do
						crewRemote:FireClient(player, "Shuffled")
					end
				end
			end
		end
	end)
end

return Crew
