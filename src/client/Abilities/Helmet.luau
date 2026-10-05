--!strict
-- Fahrradhelm (Upgrade "Helmet"): faengt einen Crash/Treffer ab, laedt sich am naechsten
-- Checkpoint wieder auf. Die Ladungen zaehlt der Server (siehe RaceManager/RunRules); hier
-- nur Anzeige und der sichtbare Helm auf dem Kopf (nur bei dir).
-- Die Rettung selbst (Wagen aufstellen usw.) macht CartClient beim Crash.

local AbilityTypes = require(script.Parent:WaitForChild("AbilityTypes"))

local shield = 0
local maxShield = 0
local helmetPart: Part? = nil

local function updateHelmet(character: Model?)
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local current = helmetPart
	if not current or current.Parent ~= head then
		if current then
			current:Destroy()
		end
		local part = Instance.new("Part")
		part.Name = "AbilityHelmet"
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(1.6, 1.6, 1.6) * (head.Size.Y / 1.2)
		part.Color = Color3.fromRGB(70, 160, 255)
		part.Material = Enum.Material.SmoothPlastic
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CFrame = head.CFrame * CFrame.new(0, head.Size.Y * 0.25, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = part
		weld.Parent = part
		part.Parent = head
		helmetPart = part
		current = part
	end
	(current :: Part).Transparency = if shield > 0 then 0 else 1
end

local Helmet = {}
Helmet.id = "Helmet"

function Helmet.afterStep(ctx: AbilityTypes.Context)
	if ctx.level >= 1 or maxShield > 0 then
		updateHelmet(ctx.character)
	end
end

function Helmet.hud(level: number): AbilityTypes.HudInfo?
	if level <= 0 and maxShield <= 0 then
		return nil
	end
	return {
		name = "Fahrradhelm",
		status = `{shield}/{maxShield}`,
		fill = if maxShield > 0 then shield / maxShield else 0,
		active = shield > 0,
		color = Color3.fromRGB(70, 160, 255),
	}
end

-- Ladungen vom Server (bzw. vorhergesagt nach einer Rettung)
function Helmet.setShield(current: number, max: number)
	shield, maxShield = current, max
	local part = helmetPart
	if part and part.Parent then
		part.Transparency = if shield > 0 then 0 else 1
	end
end

return Helmet
