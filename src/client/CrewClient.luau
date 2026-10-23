--!strict
-- Duo- und Chaos-Wagen, Client-Seite.
--   * Reiter "Wagen" im Menue: Typ waehlen (Solo/Duo/Chaos), Plaetze, Spieler einladen,
--     aussteigen. Einladungs-Popup mit Annehmen/Ablehnen.
--   * Fremde Wagen mit freiem Platz: Schild "1 Platz frei" und Hinweis "Mitfahren" (E).
--   * Mitfahrer: Kamera folgt dem Wagen, E = aussteigen. Chaos: eigene Steuerelemente als
--     Bits an den Server (UnreliableRemoteEvent, bei Aenderung und alle InputSendInterval s),
--     Einmal-Aktionen (Sprung, Boost, Tomate) mit laufender Nummer.
--   * Gastgeber (Chaos): CrewClient.drive mischt eigene und gemeldete Eingaben (CrewRules.merge,
--     Timeout = losgelassen), optional mit kuenstlicher Verzoegerung (Config.Crew.HostInputDelay).
--   * Grosse Anzeige "DEINE STEUERUNG" und Countdown vor dem Neu-Mischen.
-- Server: server/Crew. Logik: shared/Crew/CrewRules.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CrewRules = require(Shared:WaitForChild("Crew"):WaitForChild("CrewRules"))
local ChaseCamera = require(script.Parent:WaitForChild("ChaseCamera"))
local RaceUI = require(script.Parent:WaitForChild("RaceUI"))
local ShopUI = require(script.Parent:WaitForChild("ShopUI"))
local SoundSystem = require(script.Parent:WaitForChild("SoundSystem"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local crewRemote = remotes:WaitForChild("Crew") :: RemoteEvent
local inputRemote = remotes:WaitForChild("CrewInput") :: UnreliableRemoteEvent

local player = Players.LocalPlayer

local CrewClient = {}

export type SeatInfo = { seat: string, userId: number, name: string }
export type State = {
	kind: string,
	hostId: number,
	hostName: string,
	seats: { SeatInfo },
	assignment: { [string]: number },
	nextShuffleAt: number?,
}

-- Eingaben des Gastgebers fuer einen Physik-Schritt
export type DriveInput = {
	throttle: number,
	steer: number,
	shift: boolean,
	hop: boolean,
	jumpHeld: boolean,
	boost: boolean, -- Boost ausloesen (Turbo bzw. kleiner Schub)
	items: boolean, -- Tomate nach vorne werfen
}

local state: State? = nil
local LEAVE_ACTION = "GetToSchoolCrewLeave"
local KEYS_ACTION = "GetToSchoolCrewKeys"
local ONE_SHOT: { [string]: boolean } = { Jump = true, Boost = true, Items = true }

-- Gastgeber: gemeldete Eingaben und Einmal-Aktionen der Mitfahrer
local remote: { [number]: CrewRules.Remote } = {}
local pendingActions: { string } = {}
local hostHistory: { { at: number, bits: number } } = {} -- fuer HostInputDelay
local lastHostBits = 0

-- Mitfahrer: eigene Tasten
local touchHeld: { [string]: boolean } = {}
local lastSentBits = -1
local lastSentAt = 0
local actionSeq = 0
local riding: BasePart? = nil -- Wagen-Base, auf dem wir mitfahren

local invitePopup: Frame? = nil
local controlsPanel: Frame? = nil
local controlsList: Frame? = nil
local controlsTitle: TextLabel? = nil
local onItems: (() -> ())? = nil

local function myControls(): { string }
	local current = state
	if not current or current.kind ~= "Chaos" then
		return {}
	end
	return CrewRules.controlsOf(current.assignment, player.UserId)
end

local function owns(control: string): boolean
	local current = state
	return current ~= nil and current.assignment[control] == player.UserId
end

-- Ist dieser Client Gastgeber eines Chaos-Wagens? (dann gelten die verteilten Steuerelemente)
function CrewClient.isChaosHost(): boolean
	local current = state
	return current ~= nil and current.kind == "Chaos" and current.hostId == player.UserId
end

function CrewClient.isGuest(): boolean
	local current = state
	return current ~= nil and current.hostId ~= player.UserId
end

function CrewClient.getState(): State?
	return state
end

-- Tomate werfen (setzt server/Tomato-Client)
function CrewClient.setItemsHandler(handler: () -> ())
	onItems = handler
end

local function keyDown(code: Enum.KeyCode): boolean
	local name = code.Name
	if string.sub(name, 1, 6) == "Button" or string.sub(name, 1, 4) == "DPad" then
		if not UserInputService.GamepadEnabled then
			return false
		end
		if code == Enum.KeyCode.ButtonR2 or code == Enum.KeyCode.ButtonL2 then
			for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
				if input.KeyCode == code and input.Position.Z > Config.Input.TriggerDeadzone then
					return true
				end
			end
			return false
		end
		return UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, code)
	end
	return UserInputService:IsKeyDown(code)
end

local function controlDown(control: string): boolean
	if touchHeld[control] then
		return true
	end
	if UserInputService:GetFocusedTextBox() then
		return false
	end
	for _, code in (Config.Crew.Keys :: any)[control] do
		if keyDown(code) then
			return true
		end
	end
	return false
end

local function sendAction(control: string)
	actionSeq += 1
	crewRemote:FireServer("Action", control, actionSeq)
end

-- Gastgeber ---------------------------------------------------------------------------

-- Eigene Bits mit kuenstlicher Verzoegerung (Config.Crew.HostInputDelay, 0 = sofort)
local function delayedHostBits(bits: number): number
	local delay = Config.Crew.HostInputDelay
	if delay <= 0 then
		table.clear(hostHistory)
		return bits
	end
	local now = os.clock()
	table.insert(hostHistory, { at = now, bits = bits })
	local result = hostHistory[1].bits
	while #hostHistory > 1 and now - hostHistory[2].at >= delay do
		table.remove(hostHistory, 1)
		result = hostHistory[1].bits
	end
	if now - hostHistory[1].at < delay then
		return 0 -- noch nichts alt genug
	end
	return result
end

-- Chaos-Gastgeber: eigene Eingaben (`own`) mit denen der Mitfahrer mischen. Ohne Chaos kommt
-- `own` unveraendert zurueck.
function CrewClient.drive(own: DriveInput): DriveInput
	local current = state
	if not current or current.kind ~= "Chaos" or current.hostId ~= player.UserId then
		return own
	end
	local held = {
		Gas = own.throttle > 0.3,
		Brake = own.throttle < -0.3,
		Left = own.steer < -0.3,
		Right = own.steer > 0.3,
		Jump = own.jumpHeld,
		Drift = own.shift,
		Boost = controlDown("Boost"),
		Items = controlDown("Items"),
	}
	local bits = delayedHostBits(CrewRules.toBits(held))
	local merged =
		CrewRules.merge(player.UserId, bits, remote, current.assignment, os.clock(), Config.Crew.InputTimeout)
	local throttle, steer = CrewRules.drive(merged)
	-- Einmal-Aktionen: eigene steigende Flanke (nur was uns gehoert) oder Meldung eines Mitfahrers
	local result: DriveInput = {
		throttle = throttle,
		steer = steer,
		shift = merged.Drift,
		hop = false,
		jumpHeld = merged.Jump,
		boost = false,
		items = false,
	}
	for control in ONE_SHOT do
		local bit = CrewRules.BITS[control]
		local rising = bit32.band(bits, bit) ~= 0 and bit32.band(lastHostBits, bit) == 0
		if rising and current.assignment[control] == player.UserId then
			if control == "Jump" then
				result.hop = true
			elseif control == "Boost" then
				result.boost = true
			else
				result.items = true
			end
		end
	end
	lastHostBits = bits
	for _, control in pendingActions do
		if control == "Jump" then
			result.hop = true
		elseif control == "Boost" then
			result.boost = true
		elseif control == "Items" then
			result.items = true
		end
	end
	table.clear(pendingActions)
	return result
end

-- Tomate nach vorne (Chaos "Items")
function CrewClient.throwItem()
	local handler = onItems
	if handler then
		handler()
	end
end

-- Anzeige "DEINE STEUERUNG" -----------------------------------------------------------

local function keyName(control: string): string
	local names = if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
		then Config.Crew.PadNames
		else Config.Crew.KeyNames
	return (names :: any)[control] or "?"
end

local function buildControlsPanel(gui: ScreenGui)
	local panel = Instance.new("Frame")
	panel.Name = "CrewControls"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -110)
	panel.Size = UDim2.fromOffset(560, 130)
	panel.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	panel.BackgroundTransparency = 0.25
	panel.Visible = false
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 6)
	title.Size = UDim2.new(1, 0, 0, 26)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 22
	title.TextColor3 = Color3.fromRGB(255, 220, 90)
	title.Text = "DEINE STEUERUNG"
	title.Parent = panel
	controlsTitle = title
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(10, 38)
	list.Size = UDim2.new(1, -20, 1, -46)
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list
	controlsPanel = panel
	controlsList = list
end

local function refreshControls()
	local panel, list = controlsPanel, controlsList
	if not panel or not list then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local current = state
	local mine = myControls()
	panel.Visible = current ~= nil and current.kind == "Chaos" and #current.seats > 0 and #mine > 0
	local title = controlsTitle
	if title then
		title.Text = "DEINE STEUERUNG"
	end
	table.clear(touchHeld)
	for index, control in mine do
		local card = Instance.new("TextButton")
		card.LayoutOrder = index
		card.AutoButtonColor = false
		card.Size = UDim2.fromOffset(120, 76)
		card.BackgroundColor3 = Color3.fromRGB(230, 120, 40)
		card.Font = Enum.Font.GothamBlack
		card.TextSize = 20
		card.TextColor3 = Color3.new(1, 1, 1)
		card.TextWrapped = true
		card.Text = `{(Config.Crew.Names :: any)[control]}\n[{keyName(control)}]`
		card.Parent = list
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = card
		-- Touch: Karte gedrueckt halten
		card.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				touchHeld[control] = true
				if ONE_SHOT[control] and not CrewClient.isChaosHost() then
					sendAction(control)
				end
			end
		end)
		card.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				touchHeld[control] = false
			end
		end)
	end
end

-- Mitfahrer ---------------------------------------------------------------------------

local function rideSeat(): (BasePart?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if seat and string.sub(seat.Name, 1, 8) == "CrewSeat" then
		return seat, humanoid
	end
	return nil, humanoid
end

local function bindPassenger(humanoid: Humanoid)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	ContextActionService:BindAction(LEAVE_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			crewRemote:FireServer("Leave")
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle(LEAVE_ACTION, "Raus")
	-- Alle Chaos-Tasten schlucken (sonst laeuft/springt die Figur); Einmal-Aktionen melden
	local codes = {}
	for _, list in Config.Crew.Keys :: any do
		for _, code in list do
			table.insert(codes, code)
		end
	end
	ContextActionService:BindActionAtPriority(KEYS_ACTION, function(_, inputState, input)
		if inputState == Enum.UserInputState.Begin then
			for control in ONE_SHOT do
				if owns(control) and table.find((Config.Crew.Keys :: any)[control], input.KeyCode) then
					sendAction(control)
				end
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, table.unpack(codes))
end

local function unbindPassenger(humanoid: Humanoid?)
	ContextActionService:UnbindAction(LEAVE_ACTION)
	ContextActionService:UnbindAction(KEYS_ACTION)
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
end

local function updatePassenger()
	local seat, humanoid = rideSeat()
	local cart = seat and seat.Parent
	local base = cart and cart:FindFirstChild("Base")
	local newRiding = if base and base:IsA("BasePart") then base else nil
	if newRiding ~= riding then
		if riding then
			unbindPassenger(humanoid)
			-- jetzt selbst Fahrer (Uebergabe)? Dann gehoert die Kamera schon CartClient
			if not (humanoid and humanoid.SeatPart) then
				ChaseCamera.stop(humanoid)
			end
		end
		riding = newRiding
		if newRiding and humanoid and cart then
			ChaseCamera.start(newRiding, { cart, player.Character :: Model })
			bindPassenger(humanoid)
		end
	end
	-- Chaos: gehaltene Steuerelemente melden
	local current = state
	if not riding or not current or current.kind ~= "Chaos" then
		return
	end
	local held = {}
	for _, control in myControls() do
		held[control] = controlDown(control)
	end
	local bits = CrewRules.toBits(held)
	local now = os.clock()
	if bits ~= lastSentBits or now - lastSentAt >= Config.Crew.InputSendInterval then
		lastSentBits = bits
		lastSentAt = now
		inputRemote:FireServer(bits)
	end
end

-- Fremde Wagen: Schild mit freien Plaetzen und "Mitfahren"-Hinweis ---------------------

local function decorate(cart: Model)
	local base = cart:FindFirstChild("Base")
	if not base or not base:IsA("BasePart") then
		return
	end
	local free = cart:GetAttribute("CrewFree")
	local ownerId = cart:GetAttribute("OwnerUserId")
	local kind = cart:GetAttribute("CrewKind")
	local show = type(free) == "number" and type(kind) == "string"
	local sign = base:FindFirstChild("CrewSign") :: BillboardGui?
	local prompt = base:FindFirstChild("CrewJoinPrompt") :: ProximityPrompt?
	if not show then
		if sign then
			sign:Destroy()
		end
		if prompt then
			prompt:Destroy()
		end
		return
	end
	local freeCount = free :: number
	if not sign then
		local newSign = Instance.new("BillboardGui")
		newSign.Name = "CrewSign"
		newSign.Size = UDim2.fromOffset(180, 40)
		newSign.StudsOffset = Vector3.new(0, 7, 0)
		newSign.MaxDistance = 120
		newSign.AlwaysOnTop = true
		local text = Instance.new("TextLabel")
		text.Name = "Text"
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
		text.BackgroundTransparency = 0.3
		text.TextColor3 = Color3.new(1, 1, 1)
		text.Font = Enum.Font.GothamBold
		text.TextScaled = true
		text.Parent = newSign
		newSign.Parent = base
		sign = newSign
	end
	local label = (sign :: BillboardGui):FindFirstChild("Text") :: TextLabel
	label.Text = if freeCount > 0
		then `{kind}: {freeCount} {if freeCount == 1 then "Platz" else "Plaetze"} frei`
		else `{kind}: voll`
	local mine = ownerId == player.UserId
	if not prompt and not mine then
		local newPrompt = Instance.new("ProximityPrompt")
		newPrompt.Name = "CrewJoinPrompt"
		newPrompt.ActionText = "Mitfahren"
		newPrompt.KeyboardKeyCode = Enum.KeyCode.E
		newPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		newPrompt.HoldDuration = 0
		newPrompt.RequiresLineOfSight = false
		newPrompt.MaxActivationDistance = Config.Exit.EnterDistance + 4
		newPrompt.Triggered:Connect(function()
			crewRemote:FireServer("Join", cart:GetAttribute("OwnerUserId"))
		end)
		newPrompt.Parent = base
		prompt = newPrompt
	end
	if prompt then
		local host = cart:GetAttribute("CrewHostName")
		prompt.ObjectText = `{if type(host) == "string" then host else "?"}s {kind}-Wagen`
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local onFoot = humanoid ~= nil and humanoid.SeatPart == nil and humanoid.Health > 0
		prompt.Enabled = freeCount > 0 and onFoot and state == nil
	end
end

local function scanCarts()
	local folder = workspace:FindFirstChild("Carts")
	if not folder then
		return
	end
	for _, cart in folder:GetChildren() do
		if cart:IsA("Model") then
			decorate(cart)
		end
	end
end

-- Einladung -----------------------------------------------------------------------------

local function closeInvite()
	local popup = invitePopup
	if popup then
		popup:Destroy()
	end
	invitePopup = nil
end

local function showInvite(gui: ScreenGui, from: Player, kind: string)
	closeInvite()
	local popup = Instance.new("Frame")
	popup.AnchorPoint = Vector2.new(0.5, 0)
	popup.Position = UDim2.new(0.5, 0, 0, 90)
	popup.Size = UDim2.fromOffset(420, 120)
	popup.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
	popup.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = popup
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromOffset(10, 8)
	text.Size = UDim2.new(1, -20, 0, 50)
	text.Font = Enum.Font.GothamBold
	text.TextSize = 18
	text.TextWrapped = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Text = `{from.DisplayName} laedt dich in den {kind}-Wagen ein!`
	text.Parent = popup
	local function makeButton(label: string, x: number, color: Color3, answer: string)
		local button = Instance.new("TextButton")
		button.Position = UDim2.new(x, 0, 0, 66)
		button.Size = UDim2.new(0.42, 0, 0, 42)
		button.BackgroundColor3 = color
		button.Font = Enum.Font.GothamBold
		button.TextSize = 18
		button.TextColor3 = Color3.new(1, 1, 1)
		button.Text = label
		button.Parent = popup
		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 8)
		buttonCorner.Parent = button
		button.Activated:Connect(function()
			crewRemote:FireServer(answer, from)
			closeInvite()
		end)
	end
	makeButton("Annehmen", 0.05, Color3.fromRGB(60, 170, 80), "Accept")
	makeButton("Ablehnen", 0.53, Color3.fromRGB(120, 120, 130), "Decline")
	invitePopup = popup
	SoundSystem.play("Checkpoint")
	task.delay(Config.Crew.InviteTime, function()
		if invitePopup == popup then
			closeInvite()
		end
	end)
end

-- Reiter "Wagen" -------------------------------------------------------------------------

local KIND_TEXT = {
	Solo = "Allein im Einkaufswagen (Garage-Fahrzeug).",
	Duo = "Fahrer + Tomaten-Schuetze hinten. Schuetze zielt mit der Maus (Gamepad: rechter Stick).",
	Chaos = "2-4 Spieler, jeder hat nur ein paar Steuerelemente - zufaellig verteilt!",
}

local function renderTab()
	local C = ShopUI.COLORS
	local current = state
	local guest = current ~= nil and current.hostId ~= player.UserId
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	if guest and current then
		local card = ShopUI.card(90, nextOrder())
		ShopUI.label(card, {
			Position = UDim2.fromOffset(12, 8),
			Size = UDim2.new(1, -200, 0, 70),
			TextSize = 18,
			TextWrapped = true,
			Font = Enum.Font.GothamBold,
			Text = `Du faehrst im {current.kind}-Wagen von {current.hostName} mit.`,
		})
		local leave = ShopUI.button(card, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(170, 44),
			Text = "Aussteigen",
			BackgroundColor3 = C.GREY,
		})
		leave.Activated:Connect(function()
			crewRemote:FireServer("Leave")
		end)
	else
		local currentKind = if current then current.kind else "Solo"
		local row = ShopUI.buttonRow(54, nextOrder())
		for index, kind in { "Solo", "Duo", "Chaos" } do
			local button = ShopUI.button(row, {
				LayoutOrder = index,
				Size = UDim2.fromOffset(150, 48),
				Text = kind,
				BackgroundColor3 = if kind == currentKind then C.GREEN else C.GREY,
			})
			button.Activated:Connect(function()
				crewRemote:FireServer("SetKind", kind)
			end)
		end
		local info = ShopUI.card(50, nextOrder())
		ShopUI.label(info, {
			Position = UDim2.fromOffset(12, 4),
			Size = UDim2.new(1, -24, 1, -8),
			TextSize = 15,
			TextWrapped = true,
			Text = (KIND_TEXT :: any)[currentKind],
		})
	end
	if not current then
		return
	end
	-- Plaetze
	local seatsCard = ShopUI.card(30 + 26 * (#current.seats + 1), nextOrder())
	local lines = { `Fahrer: {current.hostName}` }
	for index, seat in current.seats do
		table.insert(lines, `Platz {index + 1}: {if seat.userId ~= 0 then seat.name else "frei"}`)
	end
	ShopUI.label(seatsCard, {
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 1, -16),
		TextSize = 16,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = table.concat(lines, "\n"),
	})
	if guest then
		return
	end
	-- Einladen (alle anderen Spieler auf dem Server)
	local inCrew = {}
	for _, seat in current.seats do
		inCrew[seat.userId] = true
	end
	for _, other in Players:GetPlayers() do
		if other ~= player and not inCrew[other.UserId] then
			local card = ShopUI.card(54, nextOrder())
			ShopUI.label(card, {
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.new(1, -200, 1, 0),
				TextSize = 16,
				Text = other.DisplayName,
			})
			local button = ShopUI.button(card, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(150, 40),
				Text = "Einladen",
				BackgroundColor3 = C.ACCENT,
			})
			button.Activated:Connect(function()
				crewRemote:FireServer("Invite", other)
				RaceUI.showToast(`Einladung an {other.DisplayName} geschickt`, 2)
			end)
		end
	end
end

-- Server-Nachrichten ----------------------------------------------------------------------

local function onEvent(gui: ScreenGui, kind: string, ...: any)
	if kind == "State" then
		local data = ... :: State?
		local wasChaos = state ~= nil and (state :: State).kind == "Chaos"
		state = data
		if not data then
			table.clear(remote)
			table.clear(pendingActions)
		end
		refreshControls()
		if data and data.kind == "Chaos" and not wasChaos then
			RaceUI.showMessage(
				"CHAOS-WAGEN",
				Color3.fromRGB(255, 140, 40),
				"Jeder steuert nur einen Teil!",
				2
			)
		end
		ShopUI.refresh()
	elseif kind == "Invite" then
		local from, crewKind = ...
		if typeof(from) == "Instance" and from:IsA("Player") then
			showInvite(gui, from, tostring(crewKind))
		end
	elseif kind == "Action" then
		local control, userId = ...
		if type(control) == "string" and CrewClient.isChaosHost() then
			local current = state :: State
			if current.assignment[control] == userId then
				table.insert(pendingActions, control)
			end
		end
	elseif kind == "ShuffleSoon" then
		local left = ...
		RaceUI.showMessage(`Neue Steuerung in {left} ...`, Color3.fromRGB(255, 200, 60), nil, 0.9)
	elseif kind == "Shuffled" then
		SoundSystem.play("ChaosShuffle")
		RaceUI.showMessage("NEUE STEUERUNG!", Color3.fromRGB(255, 120, 40), nil, 1.2)
	elseif kind == "Handover" then
		local name = ...
		RaceUI.showToast(`{name} faehrt jetzt den Wagen`, 2.5)
	end
end

function CrewClient.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "CrewUI"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	buildControlsPanel(gui)
	ShopUI.addTab("Crew", "Wagen", renderTab)
	crewRemote.OnClientEvent:Connect(function(kind: string, ...)
		onEvent(gui, kind, ...)
	end)
	inputRemote.OnClientEvent:Connect(function(userId: unknown, bits: unknown)
		if type(userId) == "number" and type(bits) == "number" then
			remote[userId] = { bits = bits, at = os.clock() }
		end
	end)
	local lastScan = 0
	RunService.RenderStepped:Connect(function()
		updatePassenger()
		if os.clock() - lastScan > 0.3 then
			lastScan = os.clock()
			scanCarts()
		end
	end)
	crewRemote:FireServer("Hello")
end

return CrewClient
