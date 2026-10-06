--!strict
-- Bestenlisten, Server-Seite.
--   * pro Strecke die schnellste Zeit, dazu "Weitester Kuh-Wurf" (Config.Leaderboard)
--   * Global: OrderedDataStore pro Liste (in Studio eigene Listen, ohne API-Zugriff im
--     Arbeitsspeicher), alle RefreshInterval Sekunden neu geladen
--   * Server: die Spieler in diesem Server; Freunde: die Freunde des Spielers
--   * Zeiten kommen nur hinein, wenn der Lauf plausibel war (RaceManager prueft mit
--     RunValidation); Kuh-Wuerfe plant der Server selbst, die sind immer plausibel
-- Der Client fragt mit ("Request", boardId, scope) und bekommt ("Board", Daten) zurueck.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LeaderboardMath = require(Shared:WaitForChild("Progression"):WaitForChild("LeaderboardMath"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Track = require(script.Parent:WaitForChild("Track"))

local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Leaderboard") :: RemoteEvent

local Leaderboards = {}

type Kind = LeaderboardMath.Kind
type Entry = LeaderboardMath.Entry

export type Scope = "Global" | "Server" | "Friends"

type Board = { id: string, kind: Kind, name: string }

-- So geht eine Liste an den Client
export type Payload = {
	boardId: string,
	scope: Scope,
	kind: Kind,
	name: string,
	entries: { { rank: number, name: string, value: number, self: boolean } },
	own: { rank: number?, value: number }?, -- eigener Eintrag (Platz nil = nicht in den Top SearchCount)
	loading: boolean?,
	note: string?,
}

type Cached = { value: number | false, at: number }

local globalTop: { [string]: { entries: { Entry }, at: number } } = {}
local entryCache: { [string]: { [number]: Cached } } = {} -- boardId -> userId -> Wert
local memoryStores: { [string]: { [number]: number } } = {} -- Ersatz ohne DataStores
local names: { [number]: string } = {}
local friendIds: { [Player]: { number } } = {}
local lastRequest: { [Player]: number } = {}

local function L()
	return Config.Leaderboard
end

local function useMemory(): boolean
	return Profiles.getBackendName() == "Memory"
end

-- Alle Listen: Strecken (Reihenfolge wie in Config.Tracks) und Kuh-Wurf
function Leaderboards.boards(): { Board }
	local result: { Board } = {}
	local existing = Track.list()
	local added: { [string]: boolean } = {}
	local function add(id: string)
		if not added[id] then
			added[id] = true
			table.insert(result, { id = id, kind = "Time", name = Track.displayName(id) })
		end
	end
	for _, def in Config.Tracks do
		if table.find(existing, def.id) then
			add(def.id)
		end
	end
	for _, id in existing do
		add(id)
	end
	table.insert(result, { id = L().FlightBoardId, kind = "Distance", name = L().FlightBoardName })
	return result
end

local function findBoard(boardId: string): Board?
	if boardId == L().FlightBoardId then
		return { id = boardId, kind = "Distance", name = L().FlightBoardName }
	end
	if Track.exists(boardId) then
		return { id = boardId, kind = "Time", name = Track.displayName(boardId) }
	end
	return nil
end

local stores: { [string]: OrderedDataStore } = {}
local function getStore(board: Board): OrderedDataStore?
	local existing = stores[board.id]
	if existing then
		return existing
	end
	local name = L().StorePrefix .. board.id .. (if RunService:IsStudio() then L().StudioSuffix else "")
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if ok then
		stores[board.id] = store
		return store
	end
	return nil
end

-- Genug DataStore-Anfragen uebrig? (Spielstaende haben Vorrang)
local function hasBudget(kind: Enum.DataStoreRequestType): boolean
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(kind)
	end)
	return ok and budget > L().BudgetReserve
end

local function memoryFor(board: Board): { [number]: number }
	local map = memoryStores[board.id]
	if not map then
		map = {}
		memoryStores[board.id] = map
	end
	return map
end

-- Die besten SearchCount Eintraege laden (nil = ging gerade nicht)
local function readTop(board: Board): { Entry }?
	if useMemory() then
		local list = {}
		for userId, value in memoryFor(board) do
			table.insert(list, { userId = userId, value = value })
		end
		return LeaderboardMath.top(LeaderboardMath.rank(board.kind, list), L().SearchCount)
	end
	local store = getStore(board)
	if not store or not hasBudget(Enum.DataStoreRequestType.GetSortedAsync) then
		return nil
	end
	local ok, result = pcall(function()
		local pages = store:GetSortedAsync(LeaderboardMath.ascending(board.kind), L().SearchCount)
		return pages:GetCurrentPage()
	end)
	if not ok then
		warn(`[Leaderboards] {board.id} nicht geladen: {result}`)
		return nil
	end
	local list = {}
	for _, item in result do
		local userId = tonumber(item.key)
		if userId and type(item.value) == "number" then
			table.insert(list, { userId = userId, value = item.value })
		end
	end
	return LeaderboardMath.rank(board.kind, list)
end

-- Eintrag eines Spielers (false = keiner, nil = ging gerade nicht)
local function readEntry(board: Board, userId: number): (number | false)?
	if useMemory() then
		return memoryFor(board)[userId] or false
	end
	local store = getStore(board)
	if not store or not hasBudget(Enum.DataStoreRequestType.GetAsync) then
		return nil
	end
	local ok, value = pcall(function()
		return (store:GetAsync(tostring(userId)))
	end)
	if not ok then
		return nil
	end
	return if type(value) == "number" then value else false
end

local function cacheFor(boardId: string): { [number]: Cached }
	local map = entryCache[boardId]
	if not map then
		map = {}
		entryCache[boardId] = map
	end
	return map
end

-- Eintrag aus dem Zwischenspeicher oder neu laden. refresh = false: nur laden, wenn noch
-- gar nichts bekannt ist (fuer das regelmaessige Verteilen an alle).
local function getEntry(board: Board, userId: number, refresh: boolean): number?
	local cached = cacheFor(board.id)[userId]
	if cached and (os.clock() - cached.at < L().EntryCacheTime or not refresh) then
		return if cached.value then cached.value else nil
	end
	-- steht er in der globalen Liste? Dann kein eigener Abruf noetig
	local top = globalTop[board.id]
	if top then
		local found = LeaderboardMath.find(top.entries, userId)
		if found then
			cacheFor(board.id)[userId] = { value = found.value, at = top.at }
			return found.value
		end
	end
	local value = readEntry(board, userId)
	if value == nil then
		return if cached and cached.value then cached.value else nil
	end
	if type(value) == "number" then
		cacheFor(board.id)[userId] = { value = value, at = os.clock() }
		return value
	end
	cacheFor(board.id)[userId] = { value = false, at = os.clock() }
	return nil
end

-- Neuen Wert eintragen, wenn er besser ist (Wert schon encodiert)
local function writeBest(board: Board, userId: number, value: number)
	local cache = cacheFor(board.id)
	local cached = cache[userId]
	if cached and cached.value and not LeaderboardMath.isBetter(board.kind, value, cached.value) then
		return -- nicht besser als der bekannte Eintrag
	end
	if useMemory() then
		local map = memoryFor(board)
		if LeaderboardMath.isBetter(board.kind, value, map[userId]) then
			map[userId] = value
		end
		cache[userId] = { value = map[userId], at = os.clock() }
		return
	end
	local store = getStore(board)
	if not store then
		return
	end
	local stored: number? = nil
	local ok, err = pcall(function()
		store:UpdateAsync(tostring(userId), function(old: number?): number
			if type(old) == "number" and not LeaderboardMath.isBetter(board.kind, value, old) then
				stored = old
				return nil :: any -- nicht besser: nichts aendern
			end
			stored = value
			return value
		end)
	end)
	if ok and stored then
		cache[userId] = { value = stored, at = os.clock() }
	elseif not ok then
		warn(`[Leaderboards] Eintrag in {board.id} fehlgeschlagen: {err}`)
	end
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	if userId <= 0 then
		return `Test {-userId}` -- Testspieler in Studio
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and type(name) == "string" then name else `Spieler {userId}`
	names[userId] = result
	return result
end

local function toPayload(
	board: Board,
	scope: Scope,
	ranked: { Entry },
	player: Player,
	ownValue: number?
): Payload
	local entries = {}
	for _, entry in LeaderboardMath.top(ranked, L().TopCount) do
		table.insert(entries, {
			rank = entry.rank or 0,
			name = nameOf(entry.userId),
			value = LeaderboardMath.decode(board.kind, entry.value),
			self = entry.userId == player.UserId,
		})
	end
	local own = nil
	if ownValue then
		local found = LeaderboardMath.find(ranked, player.UserId)
		own =
			{ rank = if found then found.rank else nil, value = LeaderboardMath.decode(board.kind, ownValue) }
	end
	return {
		boardId = board.id,
		scope = scope,
		kind = board.kind,
		name = board.name,
		entries = entries,
		own = own,
	}
end

-- Liste aus einzelnen Spielern (Server, Freunde)
local function listFor(board: Board, userIds: { number }): { Entry }
	local list = {}
	for _, userId in userIds do
		local value = getEntry(board, userId, true)
		if value then
			table.insert(list, { userId = userId, value = value })
		end
	end
	return LeaderboardMath.rank(board.kind, list)
end

local function getFriendIds(player: Player): { number }
	local cached = friendIds[player]
	if cached then
		return cached
	end
	local result = {}
	if player.UserId > 0 then
		pcall(function()
			local pages = Players:GetFriendsAsync(player.UserId)
			while #result < L().MaxFriends do
				for _, item in pages:GetCurrentPage() do
					if #result >= L().MaxFriends then
						break
					end
					if type(item.Id) == "number" then
						table.insert(result, item.Id)
					end
				end
				if pages.IsFinished then
					break
				end
				pages:AdvanceToNextPageAsync()
			end
		end)
	end
	friendIds[player] = result
	return result
end

local function build(player: Player, board: Board, scope: Scope, refresh: boolean): Payload
	local ownValue = getEntry(board, player.UserId, refresh)
	if scope == "Global" then
		local top = globalTop[board.id]
		local payload = toPayload(board, scope, if top then top.entries else {}, player, ownValue)
		if not top then
			payload.loading = true
		end
		return payload
	end
	local userIds = {}
	if scope == "Server" then
		for _, other in Players:GetPlayers() do
			table.insert(userIds, other.UserId)
		end
	else
		userIds = table.clone(getFriendIds(player))
		table.insert(userIds, player.UserId)
	end
	local payload = toPayload(board, scope, listFor(board, userIds), player, ownValue)
	if scope == "Friends" and #userIds <= 1 then
		payload.note = "Keine Freunde gefunden (oder in Studio)."
	end
	return payload
end

local function send(player: Player, board: Board, scope: Scope, refresh: boolean?)
	if player.Parent then
		remote:FireClient(player, "Board", build(player, board, scope, refresh ~= false))
	end
end

local function refreshGlobal(board: Board)
	local entries = readTop(board)
	if entries then
		globalTop[board.id] = { entries = entries, at = os.clock() }
		for _, entry in LeaderboardMath.top(entries, L().TopCount) do
			nameOf(entry.userId) -- Namen vorab laden
		end
	end
end

-- Alle globalen Listen neu laden und an alle schicken (fuer die Bretter in der Welt)
local function refreshAll()
	for _, board in Leaderboards.boards() do
		refreshGlobal(board)
		for _, player in Players:GetPlayers() do
			task.spawn(function()
				send(player, board, "Global", false)
			end)
		end
	end
end

-- Plausible Zeit eintragen (RaceManager)
function Leaderboards.submitTime(player: Player, trackId: string, time: number)
	local board = findBoard(trackId)
	if not board or board.kind ~= "Time" then
		return
	end
	task.spawn(function()
		writeBest(board, player.UserId, LeaderboardMath.encode("Time", time))
		refreshGlobal(board)
		send(player, board, "Global")
	end)
end

-- Kuh-Wurf eintragen (Launchables)
function Leaderboards.submitFlight(player: Player, meters: number)
	local board = findBoard(L().FlightBoardId)
	if not board then
		return
	end
	task.spawn(writeBest, board, player.UserId, LeaderboardMath.encode("Distance", meters))
end

function Leaderboards.init()
	remote.OnServerEvent:Connect(function(player, kind, boardId, scope)
		if kind ~= "Request" or type(boardId) ~= "string" then
			return
		end
		if scope ~= "Global" and scope ~= "Server" and scope ~= "Friends" then
			return
		end
		local now = os.clock()
		if now - (lastRequest[player] or -math.huge) < L().RequestCooldown then
			return
		end
		lastRequest[player] = now
		local board = findBoard(boardId)
		if board then
			task.spawn(send, player, board, (scope :: any) :: Scope)
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		-- neue Spieler: globale Listen fuer die Bretter
		task.delay(3, function()
			for _, board in Leaderboards.boards() do
				send(player, board, "Global", false)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		friendIds[player] = nil
		lastRequest[player] = nil
	end)
	task.spawn(function()
		while true do
			refreshAll()
			task.wait(L().RefreshInterval)
		end
	end)
end

return Leaderboards
