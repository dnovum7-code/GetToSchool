--!strict
-- Spectator (Tag, Model): Zuschauer am Ziel und an Set-Pieces. Sie jubeln (Hopser, Comic-Text,
-- Sound Config.Sounds.Cheer bzw. Attribut "SoundId"), wenn du schnell vorbeifaehrst, in ihrer
-- Naehe springst oder eine Kuh wegschleuderst (Spectators.cheerAt aus LaunchablesClient).
-- Werte: Config.Ambient.Spectator (CheerRadius, CheerMinSpeed ...).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TagList = require(Shared:WaitForChild("TagList"))
local AmbientLogic = require(Shared:WaitForChild("Atmosphere"):WaitForChild("AmbientLogic"))
local ComicText = require(script.Parent.Parent:WaitForChild("ComicText"))
local Nearby = require(script.Parent:WaitForChild("Nearby"))
local Pieces = require(script.Parent:WaitForChild("Pieces"))
local ToolkitTypes = require(script.Parent:WaitForChild("ToolkitTypes"))

type Spectator = {
	model: PVInstance,
	home: CFrame,
	height: number,
	cheerStart: number,
	cheerUntil: number,
	cooldownUntil: number,
	phase: number,
}

local spectators: { [Instance]: Spectator } = {}
local list: { Spectator } = {}
local active: { [Spectator]: boolean } = {}
local due = Nearby.timer()
local lastText = 0
local lastSound = 0
local CHEER_TIME = 1.4
local HOP_TIME = 0.35

local function cheer(s: Spectator, now: number)
	if now < s.cooldownUntil then
		return
	end
	local S = Config.Ambient.Spectator
	s.cheerStart = now + s.phase * 0.05 -- nicht alle exakt gleichzeitig
	s.cheerUntil = now + CHEER_TIME
	s.cooldownUntil = now + S.Cooldown
	-- Text und Sound nicht von jedem einzelnen (sonst Text-Regen)
	if now - lastText > 0.6 then
		lastText = now
		ComicText.show(
			s.home.Position + Vector3.new(0, s.height / 2 + 2, 0),
			S.CheerTexts[math.random(1, #S.CheerTexts)],
			Color3.fromRGB(120, 220, 255),
			0.9
		)
	end
	if now - lastSound > 1 then
		lastSound = now
		local primary = s.model :: Instance
		ComicText.sound(primary, Nearby.soundId(primary, "Cheer"), Config.Sounds.Cheer.Volume, 150)
	end
end

local Spectators = {}

-- Jubel bei allen aktiven Zuschauern in der Naehe von `position` (z. B. Kuh-Wurf)
function Spectators.cheerAt(position: Vector3)
	local radius = Config.Ambient.Spectator.CheerRadius
	local now = os.clock()
	for s in active do
		if (s.home.Position - position).Magnitude <= radius then
			cheer(s, now)
		end
	end
end

local piece: ToolkitTypes.Piece = {
	init = function()
		TagList.watch("Spectator", function(instance)
			if spectators[instance] or not (instance:IsA("Model") or instance:IsA("BasePart")) then
				return
			end
			local pv = instance :: PVInstance
			local height = if pv:IsA("Model")
				then pv:GetExtentsSize().Y
				elseif pv:IsA("BasePart") then pv.Size.Y
				else 5
			local s: Spectator = {
				model = pv,
				home = pv:GetPivot(),
				height = height,
				cheerStart = 0,
				cheerUntil = 0,
				cooldownUntil = 0,
				phase = (Pieces.seed(instance) % 100) / 10,
			}
			CollectionService:AddTag(instance, "SoftHit")
			spectators[instance] = s
			table.insert(list, s)
		end)
	end,

	step = function(ctx)
		local S = Config.Ambient.Spectator
		if due(ctx.dt) then
			for index = #list, 1, -1 do
				if not list[index].model:IsDescendantOf(workspace) then
					spectators[list[index].model] = nil
					table.remove(list, index)
				end
			end
			local focus = Nearby.focus(ctx)
			active = if focus
				then Nearby.select(list, function(s: Spectator)
					return s.home.Position
				end, focus, S.Range, S.MaxActive)
				else {}
		end
		local now = os.clock()
		local base = ctx.base
		local telemetry = ctx.telemetry
		local fast = base ~= nil and base.AssemblyLinearVelocity.Magnitude >= S.CheerMinSpeed
		local airborne = telemetry ~= nil and telemetry.grounded == false
		for s in active do
			if
				base
				and (fast or airborne)
				and (s.home.Position - base.Position).Magnitude <= S.CheerRadius
			then
				cheer(s, now)
			end
			local y = 0
			if now < s.cheerUntil and now >= s.cheerStart then
				local t = (now - s.cheerStart) % HOP_TIME
				y = AmbientLogic.hop(t, HOP_TIME, S.JumpHeight)
			end
			s.model:PivotTo(s.home + Vector3.new(0, y, 0))
		end
	end,
}

Spectators.init = piece.init
Spectators.step = piece.step

return Spectators
