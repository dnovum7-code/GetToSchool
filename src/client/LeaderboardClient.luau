--!strict
-- Bestenlisten, Client-Seite:
--   * Reiter "Bestenliste" im Menue (B): Liste waehlen (Strecken, Kuh-Wurf), Ansicht
--     Global / Server / Freunde, Top 10 und dein Platz
--   * Bretter in der Welt: Part mit Tag "Leaderboard" (Attribut Board = TrackId oder
--     "Flight", Face = Seite). Jeder Spieler zeichnet sein Brett selbst (mit eigenem Platz).
-- Die Daten kommen vom Server (server/Leaderboards).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local RaceTime = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RaceTime"))
local ProgressClient = require(script.Parent:WaitForChild("ProgressClient"))
local ShopUI = require(script.Parent:WaitForChild("ShopUI"))

local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Leaderboard") :: RemoteEvent

local LeaderboardClient = {}

type Scope = "Global" | "Server" | "Friends"

type Payload = {
	boardId: string,
	scope: Scope,
	kind: string,
	name: string,
	entries: { { rank: number, name: string, value: number, self: boolean } },
	own: { rank: number?, value: number }?,
	loading: boolean?,
	note: string?,
}

local SCOPES: { { id: Scope, text: string } } = {
	{ id = "Global", text = "Global" },
	{ id = "Server", text = "Server" },
	{ id = "Friends", text = "Freunde" },
}

local payloads: { [string]: Payload } = {} -- "boardId|scope" -> Daten
local boardNames: { [string]: string } = {} -- boardId -> Name
local boardOrder: { string } = {}
local selectedBoard: string? = nil
local selectedScope: Scope = "Global"
local lastRequest = -math.huge
local worldBoards: { [Instance]: { gui: SurfaceGui, boardId: string } } = {}

local function formatValue(kind: string, value: number): string
	if kind == "Time" then
		return RaceTime.format(value)
	end
	return `{math.floor(value * 10 + 0.5) / 10} m`
end

local function knowBoard(boardId: string, name: string)
	if not boardNames[boardId] then
		-- Strecken in der Reihenfolge von Config.Tracks, Kuh-Wurf ans Ende
		table.insert(boardOrder, boardId)
		local rank = {}
		for index, def in Config.Tracks do
			rank[def.id] = index
		end
		table.sort(boardOrder, function(a, b)
			local ra = if a == Config.Leaderboard.FlightBoardId then math.huge else rank[a] or 1000
			local rb = if b == Config.Leaderboard.FlightBoardId then math.huge else rank[b] or 1000
			if ra ~= rb then
				return ra < rb
			end
			return a < b
		end)
	end
	boardNames[boardId] = name
end

local function request(boardId: string, scope: Scope)
	local now = os.clock()
	if now - lastRequest < Config.Leaderboard.RequestCooldown then
		task.delay(Config.Leaderboard.RequestCooldown, function()
			-- spaeter nachholen, wenn es noch die gewaehlte Liste ist
			if
				selectedBoard == boardId
				and selectedScope == scope
				and os.clock() - lastRequest >= Config.Leaderboard.RequestCooldown
			then
				lastRequest = os.clock()
				remote:FireServer("Request", boardId, scope)
			end
		end)
		return
	end
	lastRequest = now
	remote:FireServer("Request", boardId, scope)
end

-- ===== Brett in der Welt =====

local function boardIdFor(part: Instance): string
	local attribute = part:GetAttribute("Board")
	if type(attribute) == "string" and attribute ~= "" then
		return attribute
	end
	local ancestor = part.Parent
	while ancestor and ancestor ~= workspace do
		local trackId = ancestor:GetAttribute("TrackId")
		if type(trackId) == "string" then
			return trackId
		end
		ancestor = ancestor.Parent
	end
	local first = Config.Tracks[1]
	return if first then first.id else "Track1"
end

local function faceFor(part: Instance): Enum.NormalId
	local attribute = part:GetAttribute("Face")
	if type(attribute) == "string" then
		for _, item in Enum.NormalId:GetEnumItems() do
			if item.Name == attribute then
				return item :: Enum.NormalId
			end
		end
	end
	return Enum.NormalId.Front
end

local function textLabel(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local function drawWorldBoard(gui: SurfaceGui, boardId: string)
	gui:ClearAllChildren()
	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(28, 60, 40) -- Tafelgruen
	background.BorderSizePixel = 0
	background.Parent = gui
	local payload = payloads[boardId .. "|Global"]
	local name = boardNames[boardId] or boardId
	textLabel(background, {
		Position = UDim2.fromScale(0.04, 0.02),
		Size = UDim2.fromScale(0.92, 0.12),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(255, 220, 90),
		Font = Enum.Font.LuckiestGuy,
		Text = `Bestenliste: {name}`,
	})
	if not payload then
		textLabel(background, {
			Position = UDim2.fromScale(0.04, 0.4),
			Size = UDim2.fromScale(0.92, 0.08),
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "Wird geladen ...",
		})
		return
	end
	local rowHeight = 0.068
	for index = 1, Config.Leaderboard.TopCount do
		local entry = payload.entries[index]
		local y = 0.16 + (index - 1) * rowHeight
		local color = if entry and entry.self then Color3.fromRGB(120, 255, 140) else Color3.new(1, 1, 1)
		textLabel(background, {
			Position = UDim2.fromScale(0.05, y),
			Size = UDim2.fromScale(0.62, rowHeight * 0.85),
			TextColor3 = color,
			Text = if entry then `{entry.rank}. {entry.name}` else `{index}. -`,
		})
		if entry then
			textLabel(background, {
				Position = UDim2.fromScale(0.67, y),
				Size = UDim2.fromScale(0.28, rowHeight * 0.85),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = color,
				Text = formatValue(payload.kind, entry.value),
			})
		end
	end
	local own = payload.own
	local ownText = if own
		then `Du: {if own.rank then "Platz " .. own.rank else "Platz >" .. Config.Leaderboard.SearchCount}  {formatValue(
			payload.kind,
			own.value
		)}`
		else "Du: noch kein Eintrag"
	textLabel(background, {
		Position = UDim2.fromScale(0.05, 0.88),
		Size = UDim2.fromScale(0.9, 0.08),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(120, 255, 140),
		Text = ownText,
	})
end

local function addWorldBoard(part: Instance)
	if not part:IsA("BasePart") or not part:IsDescendantOf(workspace) or worldBoards[part] then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Leaderboard"
	gui.Adornee = part
	gui.Face = faceFor(part)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = Config.Leaderboard.BoardPixelsPerStud
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Parent = playerGui
	local boardId = boardIdFor(part)
	worldBoards[part] = { gui = gui, boardId = boardId }
	drawWorldBoard(gui, boardId)
end

local function removeWorldBoard(part: Instance)
	local board = worldBoards[part]
	if board then
		board.gui:Destroy()
		worldBoards[part] = nil
	end
end

-- ===== Reiter im Menue =====

local function currentTrackId(snapshot: ProgressClient.Snapshot): string?
	local tracks = snapshot.tracks
	if type(tracks) == "table" then
		for _, track in tracks do
			if type(track) == "table" and track.current then
				return track.id
			end
		end
	end
	return nil
end

local function renderTab(snapshot: ProgressClient.Snapshot)
	local C = ShopUI.COLORS
	if not selectedBoard then
		selectedBoard = currentTrackId(snapshot) or boardOrder[1]
	end
	local boardId = selectedBoard
	if not boardId then
		ShopUI.label(ShopUI.card(60, 1), {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 1, 0),
			Text = "Bestenlisten werden geladen ...",
		})
		return
	end

	-- Auswahl: Liste
	local boardRow = ShopUI.buttonRow(48, 1)
	for index, id in boardOrder do
		local b = ShopUI.button(boardRow, {
			LayoutOrder = index,
			Size = UDim2.fromOffset(150, 42),
			TextScaled = true,
			BackgroundColor3 = if id == boardId then C.ACCENT else C.GREY,
			TextColor3 = if id == boardId then C.DARK else Color3.new(1, 1, 1),
			Text = boardNames[id] or id,
		})
		b.Activated:Connect(function()
			selectedBoard = id
			request(id, selectedScope)
			ShopUI.refresh()
		end)
	end
	-- Auswahl: Ansicht
	local scopeRow = ShopUI.buttonRow(40, 2)
	for index, scope in SCOPES do
		local b = ShopUI.button(scopeRow, {
			LayoutOrder = index,
			Size = UDim2.fromOffset(120, 34),
			BackgroundColor3 = if scope.id == selectedScope then C.GREEN else C.GREY,
			Text = scope.text,
		})
		b.Activated:Connect(function()
			selectedScope = scope.id
			request(boardId, scope.id)
			ShopUI.refresh()
		end)
	end

	local payload = payloads[boardId .. "|" .. selectedScope]
	if not payload then
		ShopUI.label(ShopUI.card(50, 3), {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 1, 0),
			Text = "Wird geladen ...",
		})
		return
	end
	if #payload.entries == 0 then
		ShopUI.label(ShopUI.card(50, 3), {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 1, 0),
			Text = payload.note
				or (if payload.loading then "Wird geladen ..." else "Noch keine Eintraege. Sei der Erste!"),
		})
	end
	for index, entry in payload.entries do
		local row = ShopUI.card(36, 2 + index)
		if entry.self then
			row.BackgroundColor3 = Color3.fromRGB(40, 80, 50)
		end
		ShopUI.label(row, {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 1, 0),
			Font = Enum.Font.GothamBold,
			Text = `{entry.rank}.  {entry.name}`,
		})
		ShopUI.label(row, {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = C.ACCENT,
			Font = Enum.Font.GothamBold,
			Text = formatValue(payload.kind, entry.value),
		})
	end
	local own = payload.own
	local ownRow = ShopUI.card(40, 100)
	ownRow.BackgroundColor3 = Color3.fromRGB(40, 80, 50)
	ShopUI.label(ownRow, {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -28, 1, 0),
		Font = Enum.Font.GothamBold,
		Text = if own
			then `Dein Platz: {if own.rank
				then tostring(own.rank)
				else "ueber " .. Config.Leaderboard.SearchCount}   {formatValue(payload.kind, own.value)}`
			else "Dein Platz: noch kein Eintrag",
	})
end

function LeaderboardClient.init()
	remote.OnClientEvent:Connect(function(kind: string, data: any)
		if kind ~= "Board" or type(data) ~= "table" then
			return
		end
		local payload = data :: Payload
		knowBoard(payload.boardId, payload.name)
		payloads[payload.boardId .. "|" .. payload.scope] = payload
		if payload.scope == "Global" then
			for _, board in worldBoards do
				if board.boardId == payload.boardId then
					drawWorldBoard(board.gui, board.boardId)
				end
			end
		end
		if ShopUI.openTab() == "Leaderboard" then
			ShopUI.refresh()
		end
	end)
	ShopUI.addTab("Leaderboard", "Bestenliste", renderTab, function()
		-- Reiter wird sichtbar: frische Daten holen
		if selectedBoard then
			request(selectedBoard, selectedScope)
		end
	end)

	local tag = Config.Leaderboard.BoardTag
	CollectionService:GetInstanceAddedSignal(tag):Connect(addWorldBoard)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(removeWorldBoard)
	for _, part in CollectionService:GetTagged(tag) do
		addWorldBoard(part)
	end
end

return LeaderboardClient
