--!strict
-- Alles rund um die Strecke: Wo startet der Wagen?

local CartBuilder = require(script.Parent:WaitForChild("CartBuilder"))

local Track = {}

local cartsFolder: Instance? = nil

function Track.init(folder: Instance)
	cartsFolder = folder
end

-- Sucht unterhalb von `origin` den Boden und gibt die passende Position fuer die
-- Mitte des Korbbodens zurueck. Blickrichtung = LookVector von `origin` (waagerecht).
function Track.placeOnGround(origin: CFrame, ignore: { Instance }): CFrame
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = table.clone(ignore)
	if cartsFolder then
		table.insert(exclude, cartsFolder)
	end
	for _, player in game:GetService("Players"):GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude

	local start = origin.Position + Vector3.new(0, 5, 0)
	local hit = workspace:Raycast(start, Vector3.new(0, -200, 0), params)
	local groundPos = if hit then hit.Position else origin.Position
	local up = if hit then hit.Normal else Vector3.yAxis

	local look = Vector3.new(origin.LookVector.X, 0, origin.LookVector.Z)
	if look.Magnitude < 0.01 then
		look = -Vector3.zAxis
	end
	-- Blickrichtung an den Hang anpassen (rechtwinklig zur Bodennormalen)
	local right = look.Unit:Cross(up).Unit
	local position = groundPos + up * (CartBuilder.getRideHeight() + 0.3)
	return CFrame.fromMatrix(position, right, up)
end

-- Ersatz-Start, solange es keine Startzone gibt: vor dem ersten SpawnLocation.
function Track.getFallbackSpawn(): CFrame
	local spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnLocation then
		local origin = (spawnLocation :: BasePart).CFrame * CFrame.new(0, 0, -10)
		return Track.placeOnGround(origin, { spawnLocation })
	end
	return Track.placeOnGround(CFrame.new(0, 10, 0), {})
end

return Track
