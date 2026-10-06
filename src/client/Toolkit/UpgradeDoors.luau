--!strict
-- UpgradeDoor (Tag "UpgradeDoor", Part oder Modell): Abkuerzungs-Tuer. Hat der Spieler das
-- Upgrade aus "RequiredUpgrade" mindestens auf Stufe "RequiredLevel", faehrt die Tuer bei
-- ihm nach unten weg (auch direkt nach dem Kauf). Sonst bleibt sie zu, und ein Schild sagt,
-- welches Upgrade fehlt. Jeder Spieler sieht seinen eigenen Zustand ("Upgrades oeffnen neue
-- Wege"). Die Stufen kommen vom Server (Spielstand-Kopie, siehe Abilities.getLevel).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Progression"):WaitForChild("Economy"))
local TagList = require(Shared:WaitForChild("TagList"))
local Abilities = require(script.Parent.Parent:WaitForChild("Abilities"))
local Kinematic = require(script.Parent.Parent:WaitForChild("Kinematic"))
local LocalClone = require(script.Parent.Parent:WaitForChild("LocalClone"))
local LocalHide = require(script.Parent.Parent:WaitForChild("LocalHide"))
local Pieces = require(script.Parent:WaitForChild("Pieces"))
local ToolkitTypes = require(script.Parent:WaitForChild("ToolkitTypes"))

type Door = {
	instance: PVInstance,
	home: CFrame,
	height: number, -- so weit faehrt sie nach unten
	parts: { BasePart },
	state: string, -- "Closed", "Opening", "Open"
	openedAt: number,
	last: CFrame,
	sign: BillboardGui?,
	signText: TextLabel?,
}

local doors: { [Instance]: Door } = {}
local warnedUnknown: { [Instance]: boolean } = {}

local function makeSign(door: Door)
	local main = if door.instance:IsA("BasePart")
		then door.instance
		else (door.instance :: Model).PrimaryPart or door.instance:FindFirstChildWhichIsA(
			"BasePart",
			true
		)
	if not main then
		return
	end
	local sign = Instance.new("BillboardGui")
	sign.Name = "UpgradeDoorSign"
	sign.Adornee = main
	sign.Size = UDim2.fromScale(16, 3.2) -- in Studs (waechst mit der Entfernung nicht mit)
	sign.StudsOffsetWorldSpace = Vector3.new(0, door.height / 2 + 2.5, 0)
	sign.MaxDistance = Config.UpgradeDoor.SignDistance
	sign.LightInfluence = 0
	local text = Instance.new("TextLabel")
	text.BackgroundColor3 = Color3.fromRGB(30, 25, 20)
	text.BackgroundTransparency = 0.2
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 200, 80)
	text.Text = ""
	text.Parent = sign
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = text
	sign.Parent = LocalClone.folder("LocalSigns")
	door.sign = sign
	door.signText = text
end

local function register(instance: Instance)
	if doors[instance] or not (instance:IsA("Model") or instance:IsA("BasePart")) then
		return
	end
	local pv = instance :: PVInstance
	local size = if pv:IsA("Model") then pv:GetExtentsSize() else (pv :: BasePart).Size
	local home = pv:GetPivot()
	local door: Door = {
		instance = pv,
		home = home,
		height = size.Y,
		parts = LocalClone.allParts(instance),
		state = "Closed",
		openedAt = 0,
		last = home,
		sign = nil,
		signText = nil,
	}
	makeSign(door)
	doors[instance] = door
end

-- Erfuellt der Spieler die Bedingung? Rueckgabe: erfuellt, Text fuer das Schild
local function check(instance: Instance): (boolean, string)
	local id = Pieces.string(instance, "RequiredUpgrade", nil)
	local level =
		math.max(1, math.floor(Pieces.number(instance, "RequiredLevel", Config.UpgradeDoor.RequiredLevel)))
	if not id then
		if not warnedUnknown[instance] then
			warnedUnknown[instance] = true
			warn(`[Baukasten] {instance:GetFullName()}: UpgradeDoor ohne Attribut "RequiredUpgrade".`)
		end
		return false, "Abkuerzung (gesperrt)"
	end
	local upgrades: { [string]: number } = {}
	for _, def in Config.Upgrades do
		upgrades[def.id] = Abilities.getLevel(def.id)
	end
	local ok, def = Economy.meetsRequirement(upgrades, Config.Upgrades, id, level)
	if not def then
		if not warnedUnknown[instance] then
			warnedUnknown[instance] = true
			warn(
				`[Baukasten] {instance:GetFullName()}: Upgrade "{id}" gibt es nicht (siehe Config.Upgrades).`
			)
		end
		return false, `Abkuerzung: braucht "{id}"`
	end
	local levelText = if #def.levels > 1 then ` Stufe {level}` else ""
	return ok, `Abkuerzung: nur mit {def.name}{levelText} (Shop: B)`
end

local UpgradeDoors: ToolkitTypes.Piece = {
	init = function()
		TagList.watch("UpgradeDoor", register)
	end,

	step = function(ctx)
		local now = os.clock()
		for instance, door in doors do
			if not instance:IsDescendantOf(workspace) then
				if door.sign then
					door.sign:Destroy()
				end
				doors[instance] = nil
				continue
			end
			local allowed, text = check(instance)
			local sign, signText = door.sign, door.signText
			if sign and signText then
				signText.Text = text
				-- Schild nur, solange die Tuer zu ist (und nicht in einem ausgeblendeten Ereignis)
				sign.Enabled = door.state == "Closed" and not LocalHide.isHidden(instance, "UpgradeDoor")
			end
			if allowed and door.state == "Closed" then
				door.state = "Opening"
				door.openedAt = now
			elseif not allowed and door.state ~= "Closed" then
				-- Upgrade weg (z. B. Test-Schalter aus): Tuer wieder zu
				door.state = "Closed"
				LocalHide.set(instance, "UpgradeDoor", false)
				Kinematic.move(door.instance, door.last, door.home, 0, true, door.parts)
				door.last = door.home
			end
			if door.state == "Opening" then
				local alpha =
					math.clamp((now - door.openedAt) / math.max(Config.UpgradeDoor.OpenTime, 0.05), 0, 1)
				local target = door.home * CFrame.new(0, -door.height * alpha, 0)
				Kinematic.move(door.instance, door.last, target, ctx.dt, true, door.parts)
				door.last = target
				if alpha >= 1 then
					door.state = "Open"
					Kinematic.stop(door.instance, door.parts)
					LocalHide.set(instance, "UpgradeDoor", true) -- ganz weg: unsichtbar, ohne Kollision
				end
			end
		end
	end,
}

return UpgradeDoors
