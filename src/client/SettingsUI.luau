--!strict
-- Reiter "Einstellungen" im Menue (B): Musik- und Effekt-Lautstaerke, Kamera-Wackeln,
-- Geist an/aus, Einstiegs-Hinweise nochmal zeigen, Steuerungsuebersicht.
-- Knoepfe statt Schieberegler, damit es auch mit Gamepad und Touch gut geht.

local ControlsInfo = require(script.Parent:WaitForChild("ControlsInfo"))
local Onboarding = require(script.Parent:WaitForChild("Onboarding"))
local ProgressClient = require(script.Parent:WaitForChild("ProgressClient"))
local Settings = require(script.Parent:WaitForChild("Settings"))
local ShopUI = require(script.Parent:WaitForChild("ShopUI"))

local SettingsUI = {}

local STEP = 0.1 -- Lautstaerke in 10-%-Schritten

local function row(order: number, title: string): Frame
	local frame = ShopUI.card(52, order)
	ShopUI.label(frame, {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -260, 1, 0),
		Font = Enum.Font.GothamBold,
		Text = title,
	})
	return frame
end

local function toggleRow(order: number, title: string, key: string)
	local C = ShopUI.COLORS
	local frame = row(order, title)
	local on = Settings.get(key) == true
	local b = ShopUI.button(frame, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(120, 38),
		BackgroundColor3 = if on then C.GREEN else C.GREY,
		Text = if on then "An" else "Aus",
	})
	b.Activated:Connect(function()
		Settings.change(key, not (Settings.get(key) == true))
		ShopUI.refresh()
	end)
end

local function volumeRow(order: number, title: string, key: string)
	local C = ShopUI.COLORS
	local frame = row(order, title)
	local value = Settings.get(key) :: number
	local minus = ShopUI.button(frame, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -184, 0.5, 0),
		Size = UDim2.fromOffset(44, 38),
		BackgroundColor3 = C.GREY,
		Text = "-",
	})
	ShopUI.label(frame, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -64, 0.5, 0),
		Size = UDim2.fromOffset(110, 38),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextColor3 = C.ACCENT,
		Text = `{math.floor(value * 100 + 0.5)} %`,
	})
	local plus = ShopUI.button(frame, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(44, 38),
		BackgroundColor3 = C.GREY,
		Text = "+",
	})
	local function step(delta: number)
		local current = Settings.get(key) :: number
		Settings.change(key, math.clamp(math.floor((current + delta) * 10 + 0.5) / 10, 0, 1))
		ShopUI.refresh()
	end
	minus.Activated:Connect(function()
		step(-STEP)
	end)
	plus.Activated:Connect(function()
		step(STEP)
	end)
end

local function render(_snapshot: ProgressClient.Snapshot)
	local C = ShopUI.COLORS
	volumeRow(1, "Musik", "MusicVolume")
	volumeRow(2, "Effekte (Gerauesche)", "EffectsVolume")
	toggleRow(3, "Kamera-Wackeln", "CameraShake")
	toggleRow(4, "Geist vom besten Lauf", "Ghost")
	toggleRow(5, "Extra-Effekte (Speed-Linien, Staub, Konfetti)", "VisualEffects")
	local hints = row(6, "Einstiegs-Hinweise")
	local again = ShopUI.button(hints, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(200, 38),
		BackgroundColor3 = Color3.fromRGB(60, 120, 200),
		Text = "Nochmal zeigen",
	})
	again.Activated:Connect(function()
		Onboarding.reset()
		again.Text = "Beim naechsten Lauf"
	end)

	-- Steuerung: Spalte des aktuellen Geraets hervorgehoben
	local device = ControlsInfo.device()
	local header = ShopUI.card(30, 10)
	header.BackgroundTransparency = 1
	local columns = { "Aktion", "Tastatur", "Gamepad", "Touch" }
	local widths = { 0.4, 0.2, 0.22, 0.18 }
	local function cells(parent: Instance, texts: { string }, bold: boolean)
		local x = 0
		for index, text in texts do
			local highlight = (index == 2 and device == "Keyboard")
				or (index == 3 and device == "Gamepad")
				or (index == 4 and device == "Touch")
			ShopUI.label(parent, {
				Position = UDim2.new(x, 10, 0, 0),
				Size = UDim2.new(widths[index], -12, 1, 0),
				TextSize = 14,
				TextWrapped = true,
				Font = if bold or highlight then Enum.Font.GothamBold else Enum.Font.Gotham,
				TextColor3 = if highlight then C.ACCENT else Color3.new(1, 1, 1),
				Text = text,
			})
			x += widths[index]
		end
	end
	cells(header, columns, true)
	for index, rowTexts in ControlsInfo.ROWS do
		local frame = ShopUI.card(36, 10 + index)
		cells(frame, rowTexts, false)
	end
end

function SettingsUI.init()
	ShopUI.addTab("Settings", "Einstellungen", render)
end

return SettingsUI
