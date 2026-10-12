--!strict
-- Party-Modi, Server-Seite: Runden-Manager.
--   1. Spieler melden sich im Menue-Reiter "Party" fuer einen Modus an ("Join" / "Leave").
--   2. Ab Config.Party.MinPlayers (Studio mit Debug.PartySolo: 1) laeuft ein Countdown,
--      sofern eine freie Arena fuer den Modus da ist.
--   3. Alle Angemeldeten (hoechstens so viele wie Spawnpunkte) kommen in die Arena
--      (Model mit Tag "PartyArena", Attribut Mode, Parts "Spawn1", "Spawn2" ...).
--   4. Runde: Kuh-Bowling (Punkte = Summe der Flugweiten) oder Letzter Wagen (Leben, wer
--      zuletzt faehrt, gewinnt; die Arena wird gefaehrlicher).
--   5. Ergebnis-Screen mit Rangliste und Muenzen je nach Platz, danach zurueck ins Spiel.
-- Wer waehrend einer Runde beitritt, kann sich fuer die naechste anmelden; wer geht, faellt
-- aus der Runde (ohne Belohnung). Rechenregeln: shared/Progression/PartyRules.
-- An die Clients (Remote "Party"): "Queue", "RoundStart", "Scores", "Lives", "Eliminated",
-- "Danger", "Launch" (Kuh-Wurf eines anderen), "Results", "RoundEnd".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PartyRules = require(Shared:WaitForChild("Progression"):WaitForChild("PartyRules"))
local TagList = require(Shared:WaitForChild("TagList"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local RaceManager = require(script.Parent:WaitForChild("RaceManager"))

local partyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Party") :: RemoteEvent

local Party = {}

type Round = {
	mode: string,
	arena: Instance,
	spawns: { CFrame },
	entries: { [Player]: PartyRules.Entry },
	startedAt: number, -- os.clock()
	duration: number,
	endsAt: number, -- Serverzeit (fuer die Anzeige beim Client)
	dangerLevel: number,
	ended: boolean,
	nextSpawn: number,
	lastScores: number,
}

local queues: { [string]: { Player } } = {}
local countdowns: { [string]: number } = {} -- Modus -> Serverzeit des Starts
local rounds: { [string]: Round } = {}
local roundOf: { [Player]: Round } = {}
local queueDirty = true
local warned: { [string]: boolean } = {}

for _, mode in Config.Party.ModeOrder do
	queues[mode] = {}
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function minPlayers(): number
	if Config.Debug.PartySolo and RunService:IsStudio() then
		return 1
	end
	return Config.Party.MinPlayers
end

local function isMode(mode: unknown): boolean
	return type(mode) == "string" and queues[mode] ~= nil
end

-- Arenen fuer einen Modus (Tag "PartyArena", Attribut Mode)
local function arenasFor(mode: string): { Instance }
	local result = {}
	for _, arena in TagList.get("PartyArena") do
		if arena:GetAttribute("Mode") == mode then
			table.insert(result, arena)
		end
	end
	return result
end

local function arenaInUse(arena: Instance): boolean
	for _, round in rounds do
		if round.arena == arena then
			return true
		end
	end
	return false
end

local function freeArena(mode: string): Instance?
	for _, arena in arenasFor(mode) do
		if not arenaInUse(arena) then
			return arena
		end
	end
	return nil
end

-- Spawnpunkte "Spawn1", "Spawn2" ... (nach Nummer sortiert)
local function spawnsOf(arena: Instance): { CFrame }
	local numbered: { { n: number, cframe: CFrame } } = {}
	for _, item in arena:GetDescendants() do
		local n = tonumber(string.match(item.Name, "^Spawn(%d+)$"))
		if n and item:IsA("BasePart") then
			table.insert(
				numbered,
				{ n = n, cframe = item.CFrame * CFrame.new(0, item.Size.Y / 2 + Config.Party.SpawnLift, 0) }
			)
		end
	end
	table.sort(numbered, function(a, b)
		return a.n < b.n
	end)
	local result = {}
	for _, entry in numbered do
		table.insert(result, entry.cframe)
	end
	if #result == 0 and arena:IsA("PVInstance") then
		if not warned[arena:GetFullName()] then
			warned[arena:GetFullName()] = true
			warn(`[Party] {arena:GetFullName()}: keine Parts "Spawn1", "Spawn2" ... - starte in der Mitte.`)
		end
		table.insert(result, arena:GetPivot() * CFrame.new(0, 5, 0))
	end
	return result
end

-- Zuschauerplatz (Part "Spectate" in der Arena, sonst ueber der Mitte)
local function spectateCFrame(arena: Instance): CFrame
	local part = arena:FindFirstChild("Spectate", true)
	if part and part:IsA("BasePart") then
		return part.CFrame * CFrame.new(0, part.Size.Y / 2 + Config.Party.SpawnLift, 0)
	end
	local pivot = if arena:IsA("PVInstance") then arena:GetPivot() else CFrame.identity
	return pivot * CFrame.new(0, 60, 0)
end

local function removeFromQueues(player: Player)
	for _, queue in queues do
		local index = table.find(queue, player)
		if index then
			table.remove(queue, index)
			queueDirty = true
		end
	end
end

local function queuedMode(player: Player): string?
	for mode, queue in queues do
		if table.find(queue, player) then
			return mode
		end
	end
	return nil
end

local function participants(round: Round): { Player }
	local list = {}
	for player in round.entries do
		table.insert(list, player)
	end
	return list
end

local function sendToRound(round: Round, ...: any)
	for player in round.entries do
		if player.Parent then
			partyRemote:FireClient(player, ...)
		end
	end
end

local function ranked(round: Round): { PartyRules.Ranked }
	local list = {}
	for _, entry in round.entries do
		table.insert(list, entry)
	end
	return if round.mode == "LastCart" then PartyRules.rankLastCart(list) else PartyRules.rankCowBowling(list)
end

-- Live-Rangliste fuer die Anzeige
local function scoreList(round: Round): {
	{
		name: string,
		score: number,
		lives: number,
		alive: boolean,
		place: number,
		id: number,
	}
}
	local list = {}
	for _, item in ranked(round) do
		local e = item.entry
		table.insert(list, {
			name = e.name,
			score = math.floor(e.score + 0.5),
			lives = e.lives,
			alive = e.alive,
			place = item.place,
			id = e.id,
		})
	end
	return list
end

-- Anmeldestand an alle (fuer den Reiter "Party")
local function broadcastQueue()
	queueDirty = false
	local info = {}
	for _, mode in Config.Party.ModeOrder do
		local round = rounds[mode]
		info[mode] = {
			count = #queues[mode],
			min = minPlayers(),
			countdown = countdowns[mode], -- Serverzeit des Starts oder nil
			running = round ~= nil,
			roundEndsAt = if round then round.endsAt else nil,
			hasArena = #arenasFor(mode) > 0,
		}
	end
	for _, player in Players:GetPlayers() do
		local round = roundOf[player]
		partyRemote:FireClient(player, "Queue", info, queuedMode(player), if round then round.mode else nil)
	end
end

local function spawnPlayer(round: Round, player: Player)
	local spawns = round.spawns
	round.nextSpawn = round.nextSpawn % #spawns + 1
	RaceManager.teleport(player, spawns[round.nextSpawn])
end

local function startRound(mode: string)
	countdowns[mode] = nil
	local arena = freeArena(mode)
	if not arena then
		return
	end
	local spawns = spawnsOf(arena)
	local queue = queues[mode]
	local duration = if mode == "LastCart"
		then Config.Party.LastCart.MaxDuration
		else Config.Party.CowBowling.Duration
	local round: Round = {
		mode = mode,
		arena = arena,
		spawns = spawns,
		entries = {},
		startedAt = os.clock(),
		duration = duration,
		endsAt = now() + duration,
		dangerLevel = 0,
		ended = false,
		nextSpawn = 0,
		lastScores = 0,
	}
	local lives = if mode == "LastCart" then Config.Party.LastCart.Lives else 0
	-- so viele, wie es Spawnpunkte gibt (die anderen warten auf die naechste Runde)
	local count = math.min(#queue, math.max(#spawns, 1))
	for _ = 1, count do
		local player = table.remove(queue, 1) :: Player
		round.entries[player] = {
			id = player.UserId,
			name = player.DisplayName,
			score = 0,
			lives = lives,
			alive = true,
			outAt = 0,
		}
		roundOf[player] = round
	end
	rounds[mode] = round
	queueDirty = true
	for index, player in participants(round) do
		RaceManager.enterParty(player)
		round.nextSpawn = index - 1
		spawnPlayer(round, player)
	end
	round.nextSpawn = #participants(round)
	sendToRound(round, "RoundStart", {
		mode = mode,
		endsAt = round.endsAt,
		lives = lives,
		duration = duration,
	})
	sendToRound(round, "Scores", scoreList(round))
end

local function endRound(round: Round)
	if round.ended then
		return
	end
	round.ended = true
	local results = {}
	for _, item in ranked(round) do
		local e = item.entry
		local coins = PartyRules.reward(item.place, Config.Party.Rewards, Config.Party.Participation)
		table.insert(results, {
			name = e.name,
			id = e.id,
			place = item.place,
			score = math.floor(e.score + 0.5),
			lives = e.lives,
			alive = e.alive,
			coins = coins,
		})
		local player = Players:GetPlayerByUserId(e.id)
		if player and round.entries[player] and coins > 0 then
			Profiles.addCoins(player, coins)
		end
	end
	sendToRound(round, "Results", { mode = round.mode, results = results, showFor = Config.Party.ResultTime })
	task.delay(Config.Party.ResultTime, function()
		for player in round.entries do
			if roundOf[player] == round then
				roundOf[player] = nil
				if player.Parent then
					partyRemote:FireClient(player, "RoundEnd")
					RaceManager.leaveParty(player)
				end
			end
		end
		if rounds[round.mode] == round then
			rounds[round.mode] = nil
		end
		queueDirty = true
	end)
end

-- Spieler ist raus (Letzter Wagen): Zuschauerplatz, Kamera auf die anderen
local function eliminate(round: Round, player: Player)
	local entry = round.entries[player]
	if not entry or not entry.alive then
		return
	end
	entry.alive = false
	entry.lives = 0
	entry.outAt = os.clock() - round.startedAt
	partyRemote:FireClient(player, "Eliminated")
	sendToRound(round, "Scores", scoreList(round))
	task.delay(Config.Party.LastCart.EliminatedDelay, function()
		if roundOf[player] == round and not round.ended and player.Parent then
			RaceManager.teleport(player, spectateCFrame(round.arena))
		end
	end)
end

-- Spieler verlaesst die Runde (Knopf "Party verlassen" oder Spiel verlassen)
local function leaveRound(player: Player, backToGame: boolean)
	local round = roundOf[player]
	if not round then
		return
	end
	roundOf[player] = nil
	round.entries[player] = nil
	if backToGame and player.Parent then
		partyRemote:FireClient(player, "RoundEnd")
		RaceManager.leaveParty(player)
	end
	if not round.ended then
		if next(round.entries) == nil then
			round.ended = true
			rounds[round.mode] = nil
		else
			sendToRound(round, "Scores", scoreList(round))
		end
	end
	queueDirty = true
end

local function updateRound(round: Round)
	if round.ended then
		return
	end
	local elapsed = os.clock() - round.startedAt
	local clock = os.clock()
	if clock - round.lastScores >= Config.Party.ScoreInterval then
		round.lastScores = clock
		sendToRound(round, "Scores", scoreList(round))
	end
	if round.mode == "LastCart" then
		local L = Config.Party.LastCart
		local level = PartyRules.dangerLevel(elapsed, L.DangerAfter, L.DangerInterval)
		if level > round.dangerLevel then
			round.dangerLevel = level
			sendToRound(round, "Danger", level, L.DangerSignal)
		end
		local alive, total = 0, 0
		for _, entry in round.entries do
			total += 1
			if entry.alive then
				alive += 1
			end
		end
		if PartyRules.lastCartOver(alive, total, elapsed, round.duration) then
			endRound(round)
		end
	elseif elapsed >= round.duration then
		endRound(round)
	end
end

local function updateQueues()
	local serverNow = now()
	for _, mode in Config.Party.ModeOrder do
		local queue = queues[mode]
		-- Wer inzwischen weg ist oder schon spielt, faellt aus der Warteschlange
		for index = #queue, 1, -1 do
			local player = queue[index]
			if not player.Parent or roundOf[player] then
				table.remove(queue, index)
				queueDirty = true
			end
		end
		local ready = PartyRules.canStart(#queue, minPlayers())
			and rounds[mode] == nil
			and freeArena(mode) ~= nil
		local countdown = countdowns[mode]
		if ready and not countdown then
			countdowns[mode] = serverNow + Config.Party.Countdown
			queueDirty = true
		elseif not ready and countdown then
			countdowns[mode] = nil -- zu wenige: Countdown abbrechen
			queueDirty = true
		elseif ready and countdown and serverNow >= countdown then
			startRound(mode)
		end
	end
end

-- Hooks fuer RaceManager (Phase "Party") -----------------------------------------------

local function respawn(player: Player)
	local round = roundOf[player]
	if not round then
		RaceManager.leaveParty(player) -- sollte nicht passieren: zurueck ins Spiel
		return
	end
	local entry = round.entries[player]
	if entry and not entry.alive then
		RaceManager.teleport(player, spectateCFrame(round.arena))
		return
	end
	spawnPlayer(round, player)
end

local LIFE_REASONS = { Hazard = true, HitHazard = true, Fell = true }

local function onCrash(player: Player, reason: string)
	local round = roundOf[player]
	if not round or round.ended then
		return
	end
	local entry = round.entries[player]
	if round.mode == "LastCart" and entry and entry.alive and LIFE_REASONS[reason] then
		entry.lives -= 1
		partyRemote:FireClient(player, "Lives", entry.lives)
		if entry.lives <= 0 then
			eliminate(round, player)
		end
		sendToRound(round, "Scores", scoreList(round))
	end
	RaceManager.ragdoll(player) -- Crashen macht Spass; danach zurueck an einen Spawnpunkt
end

local function onLaunch(player: Player, object: unknown, spawn: unknown, info: any)
	local round = roundOf[player]
	if not round or round.ended then
		return
	end
	local entry = round.entries[player]
	if round.mode == "CowBowling" and entry and type(info) == "table" and type(info.meters) == "number" then
		entry.score += info.meters
	end
	-- Alle anderen sehen den Wurf (ihre Kopie der Kuh fliegt mit)
	local key = if type(spawn) == "table" and type((spawn :: any).key) == "string"
		then (spawn :: any).key
		else nil
	for other in round.entries do
		if other ~= player and other.Parent then
			partyRemote:FireClient(other, "Launch", object, key, info, player.DisplayName)
		end
	end
end

local function canEnter(player: Player): boolean
	local round = roundOf[player]
	local entry = round and round.entries[player]
	return entry == nil or entry.alive
end

function Party.init()
	RaceManager.setPartyHooks({
		respawn = respawn,
		crash = onCrash,
		launch = onLaunch,
		canEnter = canEnter,
	})
	partyRemote.OnServerEvent:Connect(function(player, kind, mode)
		if kind == "Join" then
			if not isMode(mode) or roundOf[player] or not RaceManager.isOutsideRun(player) then
				return
			end
			removeFromQueues(player)
			table.insert(queues[mode :: string], player)
			queueDirty = true
		elseif kind == "Leave" then
			removeFromQueues(player)
			leaveRound(player, true)
		elseif kind == "Hello" then
			queueDirty = true -- Client ist bereit: Stand schicken
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		removeFromQueues(player)
		leaveRound(player, false)
	end)
	Players.PlayerAdded:Connect(function()
		queueDirty = true
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		for _, round in rounds do
			updateRound(round)
		end
		accumulator += dt
		if accumulator >= 0.25 then
			accumulator = 0
			updateQueues()
			if queueDirty then
				broadcastQueue()
			end
		end
	end)
end

return Party
