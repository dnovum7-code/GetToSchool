--!strict
-- Vorausschauendes Nachladen bei StreamingEnabled.
--
-- Mit StreamingEnabled hat der Client nur die Welt in seiner Naehe (StreamingMinRadius sicher,
-- bis StreamingTargetRadius wenn moeglich). Die Physik des Wagens rechnet der Client. Faehrt
-- man schnell bergab, kommt man in Gelaende, das beim Client noch fehlt oder nur grob (als
-- Vorschau ohne Kollision) da ist: Der Wagen faellt hindurch oder scheint darueber zu schweben.
--
-- Deshalb laedt der Server fuer jeden fahrenden Spieler regelmaessig die Gegend an der Stelle,
-- an der der Wagen in Config.Streaming.LookaheadTime Sekunden sein wird
-- (Player:RequestStreamAroundAsync). Zusaetzlich warnt er in Studio, wenn die Workspace-
-- Einstellungen fuer Streaming kleiner sind als empfohlen.
--
-- Unity-Vergleich: wie Addressables/Scene-Streaming, das Chunks vor der Kamera vorlaedt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CartManager = require(script.Parent:WaitForChild("CartManager"))

local StreamAhead = {}

type PlayerState = { busy: boolean, lastTarget: Vector3? }
local states: { [Player]: PlayerState } = {}

-- In Studio: Workspace-Einstellungen mit den Empfehlungen vergleichen
local function checkWorkspaceSettings()
	local S = Config.Streaming
	local problems = {}
	local ok, err = pcall(function()
		if workspace.StreamingMinRadius < S.RecommendedMinRadius then
			table.insert(
				problems,
				`StreamingMinRadius = {S.RecommendedMinRadius} (jetzt {workspace.StreamingMinRadius})`
			)
		end
		if workspace.StreamingTargetRadius < S.RecommendedTargetRadius then
			table.insert(
				problems,
				`StreamingTargetRadius = {S.RecommendedTargetRadius} (jetzt {workspace.StreamingTargetRadius})`
			)
		end
		local mode = (workspace :: any).StreamingIntegrityMode
		if mode and mode.Name ~= S.RecommendedIntegrityMode then
			table.insert(
				problems,
				`StreamingIntegrityMode = {S.RecommendedIntegrityMode} (jetzt {mode.Name})`
			)
		end
	end)
	if not ok then
		warn("[StreamAhead] Streaming-Einstellungen nicht lesbar:", err)
	elseif #problems > 0 then
		warn(
			"[StreamAhead] Empfehlung fuer grosse Karten (Workspace -> Streaming, siehe README "
				.. '"Streaming und Terrain"): '
				.. table.concat(problems, ", ")
		)
	end
end

local function stepPlayer(player: Player)
	local S = Config.Streaming
	local state = states[player]
	if not state or state.busy or not CartManager.isSeated(player) then
		return
	end
	local cart = CartManager.getCart(player)
	local base = cart and cart.PrimaryPart
	if not base then
		return
	end
	local velocity = base.AssemblyLinearVelocity
	if velocity.Magnitude < S.MinSpeed then
		return
	end
	local target = base.Position + velocity * S.LookaheadTime
	if state.lastTarget and (target - state.lastTarget).Magnitude < S.MinMove then
		return
	end
	state.lastTarget = target
	state.busy = true
	task.spawn(function()
		-- Wartet, bis die Gegend beim Client ist (oder Timeout). Fehler sind nicht schlimm:
		-- Dann laedt das normale Streaming, nur etwas spaeter.
		pcall(function()
			player:RequestStreamAroundAsync(target, S.Timeout)
		end)
		state.busy = false
	end)
end

function StreamAhead.init()
	if not workspace.StreamingEnabled then
		return -- ohne Streaming hat der Client sowieso die ganze Welt
	end
	if RunService:IsStudio() and Config.Streaming.WarnInStudio then
		checkWorkspaceSettings()
	end
	local function add(player: Player)
		states[player] = { busy = false, lastTarget = nil }
	end
	Players.PlayerAdded:Connect(add)
	for _, player in Players:GetPlayers() do
		add(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Streaming.Interval)
			for player in states do
				stepPlayer(player)
			end
		end
	end)
end

return StreamAhead
