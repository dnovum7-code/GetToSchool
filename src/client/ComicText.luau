--!strict
-- Comic-Text in der Welt (z. B. "HEY!", "JUHU!", "KNAPP!"): ploppt auf, steigt, verblasst.
-- Existiert nur auf diesem Client.

local TweenService = game:GetService("TweenService")

local LocalClone = require(script.Parent:WaitForChild("LocalClone"))

local ComicText = {}

function ComicText.show(position: Vector3, text: string, color: Color3?, size: number?)
	local anchor = Instance.new("Part")
	anchor.Name = "ComicTextAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = position
	anchor.Parent = LocalClone.folder("LocalComicText")
	local scale = size or 1
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220 * scale, 80 * scale)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 250
	billboard.Adornee = anchor
	billboard.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color or Color3.fromRGB(255, 230, 90)
	label.TextStrokeTransparency = 0
	label.Rotation = math.random(-12, 12)
	label.Parent = billboard
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 0.3
	uiScale.Parent = label
	TweenService:Create(uiScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
	TweenService:Create(billboard, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, 3, 0),
	}):Play()
	task.delay(0.8, function()
		TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 })
			:Play()
	end)
	task.delay(1.3, function()
		anchor:Destroy()
	end)
end

-- 3D-Sound einmal an einer Stelle (Platzhalter-Name aus Config.Sounds oder Id)
function ComicText.sound(parent: Instance, soundId: string?, volume: number, range: number)
	if not soundId or soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = if string.match(soundId, "^%d+$") then "rbxassetid://" .. soundId else soundId
	sound.Volume = volume
	sound.RollOffMaxDistance = range
	sound.RollOffMinDistance = math.max(range * 0.1, 5)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	local group = game:GetService("SoundService"):FindFirstChild("Effects")
	if group and group:IsA("SoundGroup") then
		sound.SoundGroup = group
	end
	sound.Parent = parent
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	task.delay(15, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

return ComicText
