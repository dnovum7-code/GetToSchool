--!strict
-- Menue "Pausen-Kiosk" (Taste B, Gamepad Select, oder Knopf oben rechts): Upgrades kaufen,
-- Strecken waehlen/freischalten, Flug-Rekorde ansehen. Nur ausserhalb eines Laufs.
-- Der Client fragt nur; ob ein Kauf klappt, entscheidet der Server (siehe server/Shop).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Economy =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"):WaitForChild("Economy"))
local RaceTime = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RaceTime"))
local ProgressClient = require(script.Parent:WaitForChild("ProgressClient"))
local ProgressUI = require(script.Parent:WaitForChild("ProgressUI"))
local RaceUI = require(script.Parent:WaitForChild("RaceUI"))
local SoundSystem = require(script.Parent:WaitForChild("SoundSystem"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local shopRemote = remotes:WaitForChild("ShopRequest") :: RemoteEvent
local progressRemote = remotes:WaitForChild("Progress") :: RemoteEvent

local ShopUI = {}

-- Eintrag der Track-Liste (kommt vom Server, siehe server/TrackUnlocks)
export type TrackEntry = {
	id: string,
	name: string,
	unlocked: boolean,
	current: boolean,
	condition: string?, -- Bedingung als Text, z. B. "Note 4 auf Der Schulweg"
	price: number?, -- kann mit Muenzen freigeschaltet werden
	bestTime: number?,
	bestGrade: number?,
}

type Tab = "Upgrades" | "Tracks" | "Records"

local gui: ScreenGui
local panel: Frame
local content: ScrollingFrame
local coinLabel: TextLabel
local tabButtons: { [string]: TextButton } = {}
local currentTab: Tab = "Upgrades"
local canOpen: () -> boolean = function()
	return true
end

local DARK = Color3.fromRGB(24, 24, 34)
local CARD = Color3.fromRGB(38, 38, 52)
local ACCENT = Color3.fromRGB(255, 200, 40)
local GREEN = Color3.fromRGB(70, 170, 90)
local GREY = Color3.fromRGB(80, 80, 92)

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.Gotham
	l.TextSize = 16
	l.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local function button(parent: Instance, props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	for key, value in props do
		(b :: any)[key] = value
	end
	corner(b, 8)
	b.Parent = parent
	return b
end

local function card(height: number, order: number): Frame
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, -12, 0, height)
	frame.BackgroundColor3 = CARD
	frame.BorderSizePixel = 0
	frame.LayoutOrder = order
	corner(frame, 10)
	frame.Parent = content
	return frame
end

local function clearContent()
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function request(kind: string, id: string)
	shopRemote:FireServer(kind, id)
end

local function renderUpgrades(snapshot: ProgressClient.Snapshot)
	for index, def in Config.Upgrades do
		local level = Economy.effectiveLevel(snapshot.upgrades, def)
		local maxLevel = Economy.maxLevel(def)
		local price = Economy.nextPrice(def, level)
		local frame = card(104, index)
		label(frame, {
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -200, 0, 24),
			Font = Enum.Font.GothamBold,
			TextSize = 20,
			Text = def.name,
		})
		label(frame, {
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -200, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = ACCENT,
			Text = `Stufe {level}/{maxLevel}`,
		})
		local lines = {}
		if level >= 1 then
			table.insert(lines, "Jetzt: " .. Economy.describe(def.levels[level].description, Config))
		end
		if price then
			table.insert(
				lines,
				"Naechste Stufe: " .. Economy.describe(def.levels[level + 1].description, Config)
			)
		else
			table.insert(lines, "Hoechste Stufe erreicht!")
		end
		label(frame, {
			Position = UDim2.fromOffset(14, 36),
			Size = UDim2.new(1, -200, 0, 62),
			TextSize = 14,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = Color3.fromRGB(215, 215, 225),
			Text = table.concat(lines, "\n"),
		})
		local affordable = price ~= nil and snapshot.coins >= price
		local buy = button(frame, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(160, 46),
			BackgroundColor3 = if affordable then GREEN else GREY,
			Text = if price then `Kaufen  {price}` else "Maximal",
			AutoButtonColor = affordable,
		})
		if price then
			local icon = ProgressUI.makeCoinIcon(buy, 18)
			icon.Position = UDim2.new(1, -28, 0.5, -9)
			buy.Activated:Connect(function()
				if not affordable then
					RaceUI.showToast(
						`Zu wenig Muenzen ({snapshot.coins}/{price})`,
						2,
						Color3.fromRGB(255, 140, 110)
					)
					return
				end
				request("Upgrade", def.id)
			end)
		end
	end
end

local function renderTracks(snapshot: ProgressClient.Snapshot)
	local tracks = snapshot.tracks :: { TrackEntry }?
	if not tracks or #tracks == 0 then
		label(card(60, 1), {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 1, 0),
			Text = "Noch keine Strecken gefunden.",
		})
		return
	end
	for index, track in tracks do
		local frame = card(84, index)
		label(frame, {
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -200, 0, 24),
			Font = Enum.Font.GothamBold,
			TextSize = 20,
			Text = if track.current then track.name .. "  (gewaehlt)" else track.name,
			TextColor3 = if track.current then ACCENT else Color3.new(1, 1, 1),
		})
		local info = {}
		if track.bestTime then
			table.insert(info, "Bestzeit " .. RaceTime.format(track.bestTime))
		end
		if track.bestGrade then
			table.insert(info, `beste Note {track.bestGrade}`)
		end
		if not track.unlocked and track.condition then
			table.insert(info, "Freischalten: " .. track.condition)
		end
		label(frame, {
			Position = UDim2.fromOffset(14, 36),
			Size = UDim2.new(1, -200, 0, 40),
			TextSize = 14,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = Color3.fromRGB(215, 215, 225),
			Text = if #info > 0 then table.concat(info, "   ") else "Noch nicht gefahren",
		})
		local text, color, kind = "Gesperrt", GREY, nil :: string?
		if track.unlocked and not track.current then
			text, color, kind = "Fahren", GREEN, "SelectTrack"
		elseif track.unlocked then
			text, color = "Gewaehlt", GREY
		elseif track.price then
			local affordable = snapshot.coins >= track.price
			text, color, kind =
				`Freischalten  {track.price}`, if affordable then GREEN else GREY, "UnlockTrack"
		end
		local action = button(frame, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(170, 44),
			BackgroundColor3 = color,
			Text = text,
			AutoButtonColor = kind ~= nil,
		})
		if kind then
			local requestKind = kind
			action.Activated:Connect(function()
				request(requestKind, track.id)
			end)
		end
	end
end

local function renderRecords(snapshot: ProgressClient.Snapshot)
	local list = {}
	for name, meters in snapshot.launchRecords do
		table.insert(list, { name = name, meters = meters })
	end
	table.sort(list, function(a, b)
		return a.meters > b.meters
	end)
	if #list == 0 then
		label(card(60, 1), {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 1, 0),
			Text = "Noch nichts weggeschleudert. Fahr mal eine Kuh um!",
		})
		return
	end
	for index, entry in list do
		local frame = card(44, index)
		label(frame, {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 1, 0),
			Font = Enum.Font.GothamBold,
			Text = `{index}.  Weitester {entry.name}-Wurf`,
		})
		label(frame, {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = ACCENT,
			Font = Enum.Font.GothamBold,
			Text = `{entry.meters} m`,
		})
	end
end

local function render()
	if not panel.Visible then
		return
	end
	clearContent()
	local snapshot = ProgressClient.get()
	for name, tabButton in tabButtons do
		tabButton.BackgroundColor3 = if name == currentTab then ACCENT else GREY
		tabButton.TextColor3 = if name == currentTab then DARK else Color3.new(1, 1, 1)
	end
	if not snapshot then
		label(card(60, 1), {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 1, 0),
			Text = "Spielstand wird geladen ...",
		})
		return
	end
	coinLabel.Text = tostring(snapshot.coins)
	if currentTab == "Upgrades" then
		renderUpgrades(snapshot)
	elseif currentTab == "Tracks" then
		renderTracks(snapshot)
	else
		renderRecords(snapshot)
	end
end

function ShopUI.open()
	if not canOpen() then
		RaceUI.showToast(
			"Shop gibt es nur vor oder nach einem Lauf (T = Neustart)",
			2.5,
			Color3.fromRGB(255, 200, 90)
		)
		return
	end
	panel.Visible = true
	local scale = panel:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0.85
	TweenService
		:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	render()
end

function ShopUI.close()
	panel.Visible = false
end

function ShopUI.toggle()
	if panel.Visible then
		ShopUI.close()
	else
		ShopUI.open()
	end
end

function ShopUI.isOpen(): boolean
	return panel.Visible
end

-- `check()`: darf der Shop gerade aufgehen? (ausserhalb eines Laufs)
function ShopUI.init(check: () -> boolean)
	canOpen = check
	gui = Instance.new("ScreenGui")
	gui.Name = "ShopUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5

	-- Knopf oben rechts (unter Muenzen und Leben)
	local openButton = button(gui, {
		Name = "ShopButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 144),
		Size = UDim2.fromOffset(120, 34),
		BackgroundColor3 = Color3.fromRGB(60, 120, 200),
		Text = "Shop  [B]",
	})
	openButton.Activated:Connect(ShopUI.toggle)

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(700, 480)
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.Active = true
	panel.Parent = gui
	corner(panel, 14)
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	-- Kleine Bildschirme: Panel passend verkleinern
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(700, 480)
	sizeConstraint.Parent = panel

	label(panel, {
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.fromOffset(400, 36),
		Font = Enum.Font.LuckiestGuy,
		TextSize = 32,
		TextColor3 = ACCENT,
		Text = "Pausen-Kiosk",
	})
	local coinIcon = ProgressUI.makeCoinIcon(panel, 26)
	coinIcon.AnchorPoint = Vector2.new(1, 0)
	coinIcon.Position = UDim2.new(1, -170, 0, 17)
	coinLabel = label(panel, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -66, 0, 14),
		Size = UDim2.fromOffset(96, 32),
		Font = Enum.Font.GothamBold,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "0",
	})
	local closeButton = button(panel, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Size = UDim2.fromOffset(40, 36),
		BackgroundColor3 = Color3.fromRGB(170, 60, 60),
		Text = "X",
	})
	closeButton.Activated:Connect(ShopUI.close)

	local tabs: { { id: Tab, text: string } } = {
		{ id = "Upgrades", text = "Upgrades" },
		{ id = "Tracks", text = "Strecken" },
		{ id = "Records", text = "Rekorde" },
	}
	for index, tab in tabs do
		local tabButton = button(panel, {
			Position = UDim2.fromOffset(20 + (index - 1) * 150, 58),
			Size = UDim2.fromOffset(140, 34),
			BackgroundColor3 = GREY,
			Text = tab.text,
		})
		tabButtons[tab.id] = tabButton
		tabButton.Activated:Connect(function()
			currentTab = tab.id
			render()
		end)
	end

	content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(20, 104)
	content.Size = UDim2.new(1, -40, 1, -120)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 6
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	content.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Taste B / Gamepad Select
	ContextActionService:BindAction("GetToSchoolShop", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			ShopUI.toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.B, Enum.KeyCode.ButtonSelect)

	-- Neue Daten (Muenzen, Stufen): neu zeichnen
	ProgressClient.onChanged(function()
		render()
	end)
	-- Antwort des Servers auf einen Kauf
	progressRemote.OnClientEvent:Connect(function(kind: string, ok: boolean?, message: string?)
		if kind ~= "ShopResult" then
			return
		end
		if ok then
			SoundSystem.play("Purchase")
			RaceUI.showToast(message or "Gekauft!", 2.5, Color3.fromRGB(120, 255, 140))
		else
			RaceUI.showToast(message or "Geht gerade nicht.", 2.5, Color3.fromRGB(255, 140, 110))
		end
	end)
end

return ShopUI
