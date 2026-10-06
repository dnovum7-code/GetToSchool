--!strict
-- Reiter "Lackiererei" im Menue (B): Farbe fuer das gewaehlte Fahrzeug und eine Spur.
-- Ungekauftes zeigt den Preis; ein Klick kauft es (der Server prueft, server/Cosmetics).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Vehicles = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Vehicles"))
local ProgressClient = require(script.Parent:WaitForChild("ProgressClient"))
local ShopUI = require(script.Parent:WaitForChild("ShopUI"))

local shopRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ShopRequest") :: RemoteEvent

local PaintShopUI = {}

type Info = { colors: { [string]: boolean }, trails: { [string]: boolean }, color: string, trail: string }

local function swatchText(name: string, owned: boolean, price: number, selected: boolean): string
	if selected then
		return "✔ " .. name
	end
	return if owned then name else `{name}\n{price} Muenzen`
end

local function render(snapshot: ProgressClient.Snapshot)
	local C = ShopUI.COLORS
	local info = snapshot.cosmetics :: Info?
	if not info then
		ShopUI.label(ShopUI.card(60, 1), {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 1, 0),
			Text = "Wird geladen ...",
		})
		return
	end
	local vehicle = Vehicles.get(snapshot.selectedVehicle)
	ShopUI.label(ShopUI.card(30, 1), {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -28, 1, 0),
		Font = Enum.Font.GothamBold,
		Text = `Farbe fuer: {if vehicle then vehicle.name else "dein Fahrzeug"} (andere Fahrzeuge: in der Garage waehlen)`,
	})
	-- Farben als Kacheln (4 pro Zeile)
	local perRow = 4
	local colors = Config.Cosmetics.Colors
	for rowIndex = 0, math.ceil(#colors / perRow) - 1 do
		local row = ShopUI.buttonRow(64, 2 + rowIndex)
		for i = 1, perRow do
			local item = colors[rowIndex * perRow + i]
			if not item then
				break
			end
			local owned = info.colors[item.id] == true
			local selected = info.color == item.id
			local swatch = ShopUI.button(row, {
				LayoutOrder = i,
				Size = UDim2.fromOffset(152, 58),
				BackgroundColor3 = item.color or Color3.fromRGB(150, 155, 165),
				TextColor3 = Color3.new(1, 1, 1),
				TextStrokeTransparency = 0.3,
				TextSize = 15,
				TextWrapped = true,
				Text = swatchText(item.name, owned, item.price, selected),
			})
			if selected then
				local stroke = Instance.new("UIStroke")
				stroke.Thickness = 3
				stroke.Color = C.ACCENT
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.Parent = swatch
			end
			swatch.Activated:Connect(function()
				shopRemote:FireServer("Color", item.id)
			end)
		end
	end

	ShopUI.label(ShopUI.card(30, 20), {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -28, 1, 0),
		Font = Enum.Font.GothamBold,
		Text = "Spur hinter dem Wagen",
	})
	local trailRow = ShopUI.buttonRow(52, 21)
	local none = ShopUI.button(trailRow, {
		LayoutOrder = 0,
		Size = UDim2.fromOffset(120, 46),
		BackgroundColor3 = if info.trail == "" then C.GREEN else C.GREY,
		Text = if info.trail == "" then "✔ Keine" else "Keine",
	})
	none.Activated:Connect(function()
		shopRemote:FireServer("Trail", "")
	end)
	for index, item in Config.Cosmetics.Trails do
		local owned = info.trails[item.id] == true
		local selected = info.trail == item.id
		local first = if item.colors then item.colors[1] else Color3.fromHSV(0.8, 0.6, 0.9)
		local b = ShopUI.button(trailRow, {
			LayoutOrder = index,
			Size = UDim2.fromOffset(150, 46),
			BackgroundColor3 = if selected then C.GREEN else first:Lerp(Color3.new(0, 0, 0), 0.45),
			TextSize = 14,
			TextWrapped = true,
			Text = swatchText(item.name, owned, item.price, selected),
		})
		b.Activated:Connect(function()
			shopRemote:FireServer("Trail", item.id)
		end)
	end
end

function PaintShopUI.init()
	ShopUI.addTab("PaintShop", "Lackiererei", render)
end

return PaintShopUI
