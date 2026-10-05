--!strict
-- Anzeige der Abilities unten links: pro gekaufter Ability Name, Taste, Zustand
-- (bereit / Abklingzeit / Ladungen) und ein Balken.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Abilities = require(script.Parent:WaitForChild("Abilities"))

local AbilityHud = {}

type Row = {
	frame: Frame,
	name: TextLabel,
	status: TextLabel,
	barBack: Frame,
	bar: Frame,
}

local container: Frame
local rows: { Row } = {}

local function makeRow(index: number): Row
	local frame = Instance.new("Frame")
	frame.Name = "Ability" .. index
	frame.Size = UDim2.fromOffset(250, 52)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	frame.BackgroundTransparency = 0.35
	frame.LayoutOrder = index
	frame.Parent = container
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Transparency = 1
	stroke.Parent = frame

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(10, 3)
	name.Size = UDim2.new(1, -20, 0, 18)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 15
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = Color3.new(1, 1, 1)
	name.Parent = frame

	name.TextTruncate = Enum.TextTruncate.AtEnd

	-- Zustand in einer eigenen Zeile (sonst ueberlappen lange Namen)
	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(10, 21)
	status.Size = UDim2.new(1, -20, 0, 16)
	status.Font = Enum.Font.Gotham
	status.TextSize = 14
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextTruncate = Enum.TextTruncate.AtEnd
	status.TextColor3 = Color3.fromRGB(220, 220, 230)
	status.Parent = frame

	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.new(0, 10, 1, -11)
	barBack.Size = UDim2.new(1, -20, 0, 6)
	barBack.BackgroundColor3 = Color3.fromRGB(60, 60, 72)
	barBack.BorderSizePixel = 0
	barBack.Parent = frame
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(0, 1)
	bar.BorderSizePixel = 0
	bar.Parent = barBack
	return { frame = frame, name = name, status = status, barBack = barBack, bar = bar }
end

local function refresh()
	local infos = Abilities.hudRows()
	while #rows < #infos do
		table.insert(rows, makeRow(#rows + 1))
	end
	for index, row in rows do
		local info = infos[index]
		row.frame.Visible = info ~= nil
		if info then
			local color = info.color or Color3.fromRGB(120, 200, 255)
			row.name.Text = if info.key then `{info.name}  [{info.key}]` else info.name
			row.status.Text = info.status
			row.barBack.Visible = info.fill ~= nil
			row.bar.Size = UDim2.fromScale(math.clamp(info.fill or 0, 0, 1), 1)
			row.bar.BackgroundColor3 = color
			local stroke = row.frame:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = color
				stroke.Transparency = if info.active then 0.2 else 1
			end
		end
	end
end

function AbilityHud.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "AbilityHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	container = Instance.new("Frame")
	container.Name = "Abilities"
	container.AnchorPoint = Vector2.new(0, 1)
	container.Position = UDim2.new(0, 16, 1, -40)
	container.Size = UDim2.fromOffset(250, 240)
	container.BackgroundTransparency = 1
	container.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- 10x pro Sekunde reicht fuer die Anzeige
	local timer = 0
	RunService.RenderStepped:Connect(function(dt: number)
		timer += dt
		if timer >= 0.1 then
			timer = 0
			refresh()
		end
	end)
end

return AbilityHud
