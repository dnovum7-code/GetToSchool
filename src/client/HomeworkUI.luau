--!strict
-- Reiter "Hausaufgaben" im Menue (B): die Aufgaben des Tages mit Fortschrittsbalken,
-- Belohnung und Zeit bis zu den neuen Aufgaben. Daten: Spielstand-Snapshot (Feld homework).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ProgressClient = require(script.Parent:WaitForChild("ProgressClient"))
local ProgressUI = require(script.Parent:WaitForChild("ProgressUI"))
local ShopUI = require(script.Parent:WaitForChild("ShopUI"))

local HomeworkUI = {}

type TaskInfo = { text: string, progress: number, goal: number, reward: number, done: boolean, kind: string }
type Info = { tasks: { TaskInfo }, bonus: number, bonusDone: boolean, nextReset: number }

local function timeLeft(nextReset: number): string
	local seconds = math.max(0, nextReset - workspace:GetServerTimeNow())
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	if hours > 0 then
		return `{hours} Std {minutes} Min`
	end
	return `{math.max(minutes, 1)} Min`
end

local function render(snapshot: ProgressClient.Snapshot)
	local C = ShopUI.COLORS
	local info = snapshot.homework :: Info?
	if not info then
		ShopUI.label(ShopUI.card(60, 1), {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 1, 0),
			Text = "Hausaufgaben werden geladen ...",
		})
		return
	end
	for index, task in info.tasks do
		local frame = ShopUI.card(78, index)
		if task.done then
			frame.BackgroundColor3 = Color3.fromRGB(40, 80, 50)
		end
		ShopUI.label(frame, {
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -150, 0, 26),
			Font = Enum.Font.GothamBold,
			TextSize = 18,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = (if task.done then "✔ " else "") .. task.text,
		})
		-- Belohnung rechts oben
		local icon = ProgressUI.makeCoinIcon(frame, 20)
		icon.AnchorPoint = Vector2.new(1, 0)
		icon.Position = UDim2.new(1, -70, 0, 11)
		ShopUI.label(frame, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 8),
			Size = UDim2.fromOffset(54, 26),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = C.ACCENT,
			Font = Enum.Font.GothamBold,
			Text = `+{task.reward}`,
		})
		-- Fortschrittsbalken
		local bar = Instance.new("Frame")
		bar.Position = UDim2.fromOffset(14, 44)
		bar.Size = UDim2.new(1, -130, 0, 18)
		bar.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
		bar.BorderSizePixel = 0
		bar.Parent = frame
		local barCorner = Instance.new("UICorner")
		barCorner.CornerRadius = UDim.new(0, 9)
		barCorner.Parent = bar
		local fraction = math.clamp(task.progress / math.max(task.goal, 1), 0, 1)
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(fraction, 1)
		fill.BackgroundColor3 = if task.done then C.GREEN else C.ACCENT
		fill.BorderSizePixel = 0
		fill.Visible = fraction > 0
		fill.Parent = bar
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 9)
		fillCorner.Parent = fill
		ShopUI.label(frame, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 40),
			Size = UDim2.fromOffset(104, 26),
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = if task.done then "Erledigt!" else `{math.floor(task.progress)} / {task.goal}`,
		})
	end
	if #info.tasks == 0 then
		ShopUI.label(ShopUI.card(60, 1), {
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 1, 0),
			Text = "Heute keine Hausaufgaben. Glueck gehabt!",
		})
	end
	local footer = ShopUI.card(56, 50)
	footer.BackgroundTransparency = 0.5
	ShopUI.label(footer, {
		Position = UDim2.fromOffset(14, 4),
		Size = UDim2.new(1, -28, 0, 24),
		Text = if info.bonusDone
			then "Alle erledigt, Bonus abgeholt. Morgen gibt es neue!"
			else `Alle erledigt: Bonus +{info.bonus}`,
	})
	ShopUI.label(footer, {
		Position = UDim2.fromOffset(14, 28),
		Size = UDim2.new(1, -28, 0, 22),
		TextColor3 = Color3.fromRGB(190, 190, 205),
		TextSize = 14,
		Text = `Neue Hausaufgaben in {timeLeft(info.nextReset)} (Wechsel {Config.Homework.ResetHourUtc} Uhr UTC)`,
	})
end

function HomeworkUI.init()
	ShopUI.addTab("Homework", "Hausaufgaben", render)
end

return HomeworkUI
