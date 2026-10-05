--!strict
-- Hinweis "E  Einsteigen" am eigenen, leeren Wagen.
--
-- Nutzt einen ProximityPrompt: Roblox zeigt ihn automatisch an, sobald man nah genug ist,
-- und kuemmert sich um Tastatur (E), Gamepad (X) und Touch (antippen).
-- Der Prompt wird nur auf diesem Client erzeugt, andere Spieler sehen ihn also nicht.
-- Beim Ausloesen fragen wir den Server; der prueft Abstand und ob der Wagen frei ist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local OwnCart = require(script.Parent:WaitForChild("OwnCart"))

local EnterPrompt = {}

local prompt: ProximityPrompt? = nil
local promptCart: Model? = nil
local onTriggered: () -> () = function() end

local function createPrompt(cart: Model): ProximityPrompt?
	local base = cart:FindFirstChild("Base")
	if not base then
		return nil
	end
	local newPrompt = Instance.new("ProximityPrompt")
	newPrompt.Name = "EnterPrompt"
	newPrompt.ActionText = "Einsteigen"
	newPrompt.ObjectText = "Einkaufswagen"
	newPrompt.KeyboardKeyCode = Enum.KeyCode.E
	newPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	newPrompt.HoldDuration = 0
	newPrompt.RequiresLineOfSight = false
	newPrompt.MaxActivationDistance = Config.Exit.EnterDistance
	newPrompt.Enabled = false
	newPrompt.Triggered:Connect(function()
		onTriggered()
	end)
	newPrompt.Parent = base
	return newPrompt
end

function EnterPrompt.init(callback: () -> ())
	onTriggered = callback
end

-- Jeden Frame aufrufen. `onFoot`: Spieler laeuft gerade zu Fuss herum.
function EnterPrompt.update(onFoot: boolean)
	local cart = OwnCart.find()
	if cart ~= promptCart then
		-- neuer Wagen (z. B. nach einem Neubau): Prompt umziehen
		if prompt then
			prompt:Destroy()
		end
		promptCart = cart
		prompt = if cart then createPrompt(cart) else nil
	end
	local current = prompt
	if not current or not cart then
		return
	end
	local seat = cart:FindFirstChild("Seat") :: Seat?
	current.Enabled = onFoot and seat ~= nil and seat.Occupant == nil
end

return EnterPrompt
