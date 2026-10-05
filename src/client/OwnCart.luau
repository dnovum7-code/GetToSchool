--!strict
-- Kleine Helfer rund um den eigenen Wagen.

local Players = game:GetService("Players")

local OwnCart = {}

local player = Players.LocalPlayer

-- Der Wagen dieses Spielers (oder nil, solange er noch nicht existiert).
function OwnCart.find(): Model?
	local folder = workspace:FindFirstChild("Carts")
	if not folder then
		return nil
	end
	for _, cart in folder:GetChildren() do
		if cart:IsA("Model") and cart:GetAttribute("OwnerUserId") == player.UserId then
			return cart
		end
	end
	return nil
end

-- Alle Teile eines Modells anhalten. Wirkt nur bei Teilen, deren Physik dieser Client rechnet.
function OwnCart.stopMotion(model: Instance)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

return OwnCart
