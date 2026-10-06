--!strict
-- Reiter "Garage" im Menue (B): Fahrzeuge ansehen, kaufen und waehlen. Der Server prueft
-- alles (server/Garage); nach dem Wechsel steht der neue Wagen am Start.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vehicles = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Vehicles"))
local ProgressClient = require(script.Parent:WaitForChild("ProgressClient"))
local ProgressUI = require(script.Parent:WaitForChild("ProgressUI"))
local ShopUI = require(script.Parent:WaitForChild("ShopUI"))

local shopRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ShopRequest") :: RemoteEvent

local GarageUI = {}

local RATINGS: { { key: string, text: string } } = {
	{ key = "speed", text = "Tempo" },
	{ key = "handling", text = "Wendigkeit" },
	{ key = "stability", text = "Stabilitaet" },
}

local function ratingRow(parent: Instance, y: number, text: string, value: number)
	ShopUI.label(parent, {
		Position = UDim2.fromOffset(14, y),
		Size = UDim2.fromOffset(100, 18),
		TextSize = 14,
		TextColor3 = Color3.fromRGB(190, 190, 205),
		Text = text,
	})
	for i = 1, 5 do
		local dot = Instance.new("Frame")
		dot.Position = UDim2.fromOffset(110 + (i - 1) * 22, y + 2)
		dot.Size = UDim2.fromOffset(18, 14)
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = if i <= value then ShopUI.COLORS.ACCENT else Color3.fromRGB(60, 60, 72)
		dot.Parent = parent
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = dot
	end
end

local function render(snapshot: ProgressClient.Snapshot)
	local C = ShopUI.COLORS
	local owned = (snapshot.vehicles or {}) :: { [string]: boolean }
	local selected = snapshot.selectedVehicle :: string?
	for index, def in Vehicles.list() do
		local frame = ShopUI.card(132, index)
		local isSelected = selected == def.id
		if isSelected then
			frame.BackgroundColor3 = Color3.fromRGB(40, 80, 50)
		end
		ShopUI.label(frame, {
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -200, 0, 26),
			Font = Enum.Font.GothamBold,
			TextSize = 20,
			Text = def.name,
		})
		ShopUI.label(frame, {
			Position = UDim2.fromOffset(14, 34),
			Size = UDim2.new(1, -200, 0, 36),
			TextSize = 14,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = Color3.fromRGB(210, 210, 220),
			Text = def.description,
		})
		for row, rating in RATINGS do
			ratingRow(frame, 70 + (row - 1) * 20, rating.text, (def.ratings :: any)[rating.key] or 3)
		end

		local kind: string? = nil
		local text: string
		local color: Color3
		if isSelected then
			text, color = "Gewaehlt", C.GREEN
		elseif owned[def.id] then
			text, color, kind = "Waehlen", Color3.fromRGB(60, 120, 200), "SelectVehicle"
		else
			local affordable = snapshot.coins >= def.price
			text = `Kaufen  {def.price}`
			color = if affordable then C.ACCENT else C.GREY
			kind = "BuyVehicle"
		end
		local action = ShopUI.button(frame, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(160, 44),
			BackgroundColor3 = color,
			TextColor3 = if color == C.ACCENT then C.DARK else Color3.new(1, 1, 1),
			AutoButtonColor = kind ~= nil,
			Text = text,
		})
		if kind == "BuyVehicle" then
			local icon = ProgressUI.makeCoinIcon(action, 18)
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, 10, 0.5, 0)
		end
		if kind then
			local requestKind = kind
			action.Activated:Connect(function()
				shopRemote:FireServer(requestKind, def.id)
			end)
		end
	end
end

function GarageUI.init()
	ShopUI.addTab("Garage", "Garage", render)
end

return GarageUI
