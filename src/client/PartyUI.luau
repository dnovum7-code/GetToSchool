--!strict
-- Party-Modi, Client-Seite (Server: server/Party):
--   * Menue-Reiter "Party": Modi mit Beschreibung, Anmeldestand, Countdown, Anmelden/Abmelden.
--   * Waehrend der Runde: Modus + Restzeit oben, Live-Rangliste rechts, eigene Leben
--     (Letzter Wagen), Knopf "Party verlassen".
--   * Ausgeschieden (Letzter Wagen): Kamera auf die anderen, Knopf "Naechster".
--   * Gefahr (Letzter Wagen): Signal an die Arena (Baukasten, ListenSignal), Meldung.
--   * Kuh-Wuerfe der anderen: unsere Kopie der Kuh fliegt mit (LaunchablesClient).
--   * Ergebnis-Screen: Rangliste und Muenzen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ChaseCamera = require(script.Parent:WaitForChild("ChaseCamera"))
local LaunchablesClient = require(script.Parent:WaitForChild("LaunchablesClient"))
local OwnCart = require(script.Parent:WaitForChild("OwnCart"))
local PartyState = require(script.Parent:WaitForChild("PartyState"))
local RaceUI = require(script.Parent:WaitForChild("RaceUI"))
local ShopUI = require(script.Parent:WaitForChild("ShopUI"))
local SoundSystem = require(script.Parent:WaitForChild("SoundSystem"))
local Signals = require(script.Parent:WaitForChild("Toolkit"):WaitForChild("Signals"))

local partyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Party") :: RemoteEvent

local PartyUI = {}

type ModeInfo = {
	count: number,
	min: number,
	countdown: number?,
	running: boolean,
	roundEndsAt: number?,
	hasArena: boolean,
}
type Score = { name: string, score: number, lives: number, alive: boolean, place: number, id: number }

local player = Players.LocalPlayer
local queueInfo: { [string]: ModeInfo } = {}
local myQueue: string? = nil
local roundEndsAt = 0
local scores: { Score } = {}
local myLives = 0
local watchIndex = 0

-- HUD
local hud: ScreenGui
local titleLabel: TextLabel
local infoLabel: TextLabel -- Countdown vor der Runde / Leben / Ausgeschieden
local board: Frame
local leaveButton: TextButton
local nextButton: TextButton
local resultFrame: Frame
local resultToken = 0

local GOLD = Color3.fromRGB(255, 215, 80)

local function modeName(mode: string?): string
	return if mode then (Config.Party.Names :: any)[mode] or mode else ""
end

local function formatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function makeLabel(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	for key, value in props do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, text: string, position: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(170, 38)
	button.Position = position
	button.BackgroundColor3 = Color3.fromRGB(200, 70, 60)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.Text = text
	button.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	button.Parent = parent
	return button
end

local function buildHud()
	hud = Instance.new("ScreenGui")
	hud.Name = "PartyHUD"
	hud.ResetOnSpawn = false
	hud.IgnoreGuiInset = true
	hud.DisplayOrder = 3
	titleLabel = makeLabel(hud, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(520, 36),
		TextScaled = true,
		Font = Enum.Font.LuckiestGuy,
		Visible = false,
	})
	infoLabel = makeLabel(hud, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.fromOffset(520, 26),
		TextScaled = true,
		Visible = false,
	})
	board = Instance.new("Frame")
	board.Name = "Board"
	board.AnchorPoint = Vector2.new(1, 0)
	board.Position = UDim2.new(1, -12, 0, 140)
	board.Size = UDim2.fromOffset(230, 0)
	board.AutomaticSize = Enum.AutomaticSize.Y
	board.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	board.BackgroundTransparency = 0.35
	board.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = board
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = board
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = board
	board.Parent = hud
	leaveButton = makeButton(hud, "Party verlassen", UDim2.new(0, 12, 1, -150))
	leaveButton.Activated:Connect(function()
		partyRemote:FireServer("Leave")
	end)
	nextButton = makeButton(hud, "Naechster Spieler", UDim2.new(0, 12, 1, -200))
	nextButton.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
	resultFrame = Instance.new("Frame")
	resultFrame.Name = "Results"
	resultFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	resultFrame.Position = UDim2.fromScale(0.5, 0.5)
	resultFrame.Size = UDim2.fromOffset(420, 0)
	resultFrame.AutomaticSize = Enum.AutomaticSize.Y
	resultFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
	resultFrame.BackgroundTransparency = 0.1
	resultFrame.Visible = false
	local rCorner = Instance.new("UICorner")
	rCorner.CornerRadius = UDim.new(0, 12)
	rCorner.Parent = resultFrame
	local rLayout = Instance.new("UIListLayout")
	rLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rLayout.Padding = UDim.new(0, 4)
	rLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rLayout.Parent = resultFrame
	local rPadding = Instance.new("UIPadding")
	rPadding.PaddingTop = UDim.new(0, 12)
	rPadding.PaddingBottom = UDim.new(0, 12)
	rPadding.Parent = resultFrame
	resultFrame.Parent = hud
	hud.Parent = player:WaitForChild("PlayerGui")
end

-- Live-Rangliste rechts
local function renderBoard()
	for _, child in board:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local lastCart = PartyState.mode == "LastCart"
	for index, entry in scores do
		if index > 8 then
			break
		end
		local value = if lastCart
			then (if entry.alive then string.rep("♥", entry.lives) else "raus")
			else `{entry.score} m`
		makeLabel(board, {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 16,
			Text = `{entry.place}. {entry.name}   {value}`,
			TextColor3 = if entry.id == player.UserId
				then GOLD
				elseif lastCart and not entry.alive then Color3.fromRGB(150, 150, 150)
				else Color3.new(1, 1, 1),
		})
	end
end

-- Zuschauen: Kamera auf einen Spieler, der noch faehrt
local function aliveOthers(): { number }
	local ids = {}
	for _, entry in scores do
		if entry.alive and entry.id ~= player.UserId then
			table.insert(ids, entry.id)
		end
	end
	return ids
end

local function watchNext(step: number)
	local ids = aliveOthers()
	if #ids == 0 then
		ChaseCamera.watch(nil)
		return
	end
	watchIndex = (watchIndex + step - 1) % #ids + 1
	local cart = OwnCart.findFor(ids[watchIndex])
	local base = cart and cart:FindFirstChild("Base")
	ChaseCamera.watch(if base and base:IsA("BasePart") then base else nil)
end

local function showResults(data: { [string]: any })
	for _, child in resultFrame:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	makeLabel(resultFrame, {
		LayoutOrder = 0,
		Size = UDim2.new(1, -20, 0, 40),
		TextScaled = true,
		Font = Enum.Font.LuckiestGuy,
		TextColor3 = GOLD,
		Text = `{modeName(data.mode)}: ERGEBNIS`,
	})
	local results = data.results :: { { [string]: any } }
	for index, item in results do
		local value = if data.mode == "LastCart"
			then (if item.alive then `{item.lives} Leben` else "raus")
			else `{item.score} m`
		makeLabel(resultFrame, {
			LayoutOrder = index,
			Size = UDim2.new(1, -30, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 18,
			Text = `{item.place}.  {item.name}   {value}   +{item.coins} Muenzen`,
			TextColor3 = if item.id == player.UserId then GOLD else Color3.new(1, 1, 1),
		})
	end
	resultFrame.Visible = true
	resultToken += 1
	local token = resultToken
	local showFor = if type(data.showFor) == "number" then data.showFor else Config.Party.ResultTime
	task.delay(showFor, function()
		if token == resultToken then
			resultFrame.Visible = false
		end
	end)
	SoundSystem.play("Finish")
end

local function roundUi(on: boolean)
	titleLabel.Visible = on
	board.Visible = on
	leaveButton.Visible = on
	if not on then
		nextButton.Visible = false
		infoLabel.Visible = false
	end
end

-- Jede Frame: Restzeit, Countdown vor der Runde
local function updateHud()
	local serverNow = workspace:GetServerTimeNow()
	if PartyState.active then
		titleLabel.Text = `{string.upper(modeName(PartyState.mode))}   {formatTime(roundEndsAt - serverNow)}`
		if PartyState.mode == "LastCart" then
			infoLabel.Visible = true
			infoLabel.Text = if PartyState.eliminated
				then "Ausgeschieden - du schaust zu"
				else `Leben: {string.rep("♥", math.max(myLives, 0))}`
		end
		return
	end
	local info = myQueue and queueInfo[myQueue]
	if info and info.countdown then
		infoLabel.Visible = true
		infoLabel.Text =
			`{modeName(myQueue)} startet in {math.max(0, math.ceil(info.countdown - serverNow))} s`
	elseif info then
		infoLabel.Visible = true
		infoLabel.Text = `{modeName(myQueue)}: angemeldet ({info.count} / {info.min})`
	else
		infoLabel.Visible = false
	end
end

-- Menue-Reiter "Party"
local function renderTab()
	local C = ShopUI.COLORS
	local serverNow = workspace:GetServerTimeNow()
	for index, mode in Config.Party.ModeOrder do
		local info = queueInfo[mode]
		local card = ShopUI.card(118, index)
		ShopUI.label(card, {
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -200, 0, 26),
			TextSize = 20,
			Font = Enum.Font.GothamBold,
			Text = modeName(mode),
		})
		ShopUI.label(card, {
			Position = UDim2.fromOffset(12, 32),
			Size = UDim2.new(1, -200, 0, 44),
			TextSize = 14,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = (Config.Party.Descriptions :: any)[mode] or "",
		})
		local status = "Lade ..."
		if info then
			if not info.hasArena then
				status = `Keine Arena: Model mit Tag "PartyArena" und Attribut Mode = "{mode}" bauen`
			elseif info.running then
				status =
					`Runde laeuft (noch {formatTime((info.roundEndsAt or serverNow) - serverNow)}) - melde dich fuer die naechste an`
			elseif info.countdown then
				status =
					`Start in {math.max(0, math.ceil(info.countdown - serverNow))} s  ({info.count} angemeldet)`
			else
				status = `Angemeldet: {info.count} / {info.min}`
			end
		end
		ShopUI.label(card, {
			Position = UDim2.fromOffset(12, 84),
			Size = UDim2.new(1, -200, 0, 26),
			TextSize = 14,
			TextColor3 = C.ACCENT,
			TextWrapped = true,
			Text = status,
		})
		local joined = myQueue == mode
		local button = ShopUI.button(card, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(170, 44),
			Text = if joined then "Abmelden" else "Anmelden",
			BackgroundColor3 = if joined then C.GREY else C.GREEN,
		})
		button.Activated:Connect(function()
			partyRemote:FireServer(if joined then "Leave" else "Join", mode)
		end)
	end
end

local function onEvent(kind: string, ...: any)
	if kind == "Queue" then
		local info, queued, inRound = ...
		queueInfo = info
		myQueue = queued
		if ShopUI.openTab() == "Party" then
			ShopUI.refresh()
		end
		if inRound == nil and PartyState.active then
			-- Server sagt: keine Runde (z. B. verlassen) - Anzeige aufraeumen
			roundUi(false)
		end
	elseif kind == "RoundStart" then
		local data = ... :: { [string]: any }
		PartyState.active = true
		PartyState.mode = data.mode
		PartyState.eliminated = false
		myLives = data.lives
		roundEndsAt = data.endsAt
		myQueue = nil
		ShopUI.close()
		roundUi(true)
		RaceUI.showMessage("LOS!", GOLD, modeName(data.mode), 1.5)
	elseif kind == "Scores" then
		scores = ...
		renderBoard()
		if PartyState.eliminated then
			-- zugeschauter Spieler raus? Dann zum naechsten
			watchNext(0)
		end
	elseif kind == "Lives" then
		myLives = ...
	elseif kind == "Eliminated" then
		PartyState.eliminated = true
		myLives = 0
		RaceUI.showMessage("AUSGESCHIEDEN", Color3.fromRGB(255, 90, 70), "Du schaust jetzt zu", 2.5)
		nextButton.Visible = true
		task.delay(Config.Party.LastCart.EliminatedDelay + 0.5, function()
			if PartyState.eliminated then
				watchNext(1)
			end
		end)
	elseif kind == "Danger" then
		local level, signal = ...
		if type(signal) == "string" then
			Signals.fire(signal, "Party")
			Signals.fire(signal .. tostring(level), "Party")
		end
		RaceUI.showMessage("ACHTUNG!", Color3.fromRGB(255, 120, 40), "Die Arena wird gefaehrlicher!", 2)
	elseif kind == "Launch" then
		local object, key, info, byName = ...
		if type(info) == "table" then
			LaunchablesClient.onRemoteLaunch(
				if typeof(object) == "Instance" then object else nil,
				if type(key) == "string" then key else nil,
				info,
				if type(byName) == "string" then byName else nil
			)
		end
	elseif kind == "Results" then
		local data = ... :: { [string]: any }
		ChaseCamera.watch(nil)
		nextButton.Visible = false
		showResults(data)
	elseif kind == "RoundEnd" then
		PartyState.reset()
		ChaseCamera.watch(nil)
		roundUi(false)
	end
end

function PartyUI.init()
	buildHud()
	nextButton.Activated:Connect(function()
		watchNext(1)
	end)
	ShopUI.addTab("Party", "Party", renderTab)
	partyRemote.OnClientEvent:Connect(onEvent)
	local lastRefresh = 0
	RunService.RenderStepped:Connect(function()
		updateHud()
		-- Countdown im offenen Reiter mitzaehlen
		if ShopUI.openTab() == "Party" and os.clock() - lastRefresh > 1 then
			lastRefresh = os.clock()
			ShopUI.refresh()
		end
	end)
	partyRemote:FireServer("Hello")
end

return PartyUI
