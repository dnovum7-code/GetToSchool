--!strict
-- TextTrigger (Tag "TextTrigger", Part): Faehrt der eigene Wagen hinein, erscheint ein Text
-- gross auf dem Bildschirm (nur bei dir). Attribute:
--   Text     (Text)    grosse Zeile, z. B. "Achtung, Kuehe!"   (Pflicht)
--   SubText  (Text)    kleine Zeile darunter                    (optional)
--   Color    (Color3)  Farbe der grossen Zeile                  (Standard gelb)
--   Duration (Zahl)    so lange sichtbar (s)                    (Config.TextTrigger.Duration)
--   Once     (Bool)    nur einmal pro Lauf                      (Config.TextTrigger.Once)
--   Cooldown (Zahl)    Wartezeit bis zum naechsten Mal (s)      (Config.TextTrigger.Cooldown)
-- Wie TriggerZone: der Bereich ist im Spiel unsichtbar, bei R und T wieder scharf.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TagList = require(Shared:WaitForChild("TagList"))
local TriggerRules = require(Shared:WaitForChild("Toolkit"):WaitForChild("TriggerRules"))
local LocalHide = require(script.Parent.Parent:WaitForChild("LocalHide"))
local RaceUI = require(script.Parent.Parent:WaitForChild("RaceUI"))
local Pieces = require(script.Parent:WaitForChild("Pieces"))
local Signals = require(script.Parent:WaitForChild("Signals"))
local ToolkitTypes = require(script.Parent:WaitForChild("ToolkitTypes"))

type Zone = {
	part: BasePart,
	state: TriggerRules.State,
}

local zones: { [Instance]: Zone } = {}
local warnedNoText: { [Instance]: boolean } = {}

local function show(instance: Instance)
	local C = Config.TextTrigger
	local text = Pieces.string(instance, "Text", nil)
	if not text then
		if not warnedNoText[instance] then
			warnedNoText[instance] = true
			warn(`[Baukasten] {instance:GetFullName()}: TextTrigger ohne Attribut "Text".`)
		end
		return
	end
	local color = instance:GetAttribute("Color")
	RaceUI.showMessage(
		text,
		if typeof(color) == "Color3" then color else C.Color,
		Pieces.string(instance, "SubText", nil),
		math.max(Pieces.number(instance, "Duration", C.Duration), 0.2)
	)
	Signals.debugLog(`TextTrigger "{instance.Name}": "{text}"`)
end

local TextTriggers: ToolkitTypes.Piece = {
	init = function()
		TagList.watch("TextTrigger", function(instance)
			if instance:IsA("BasePart") and not zones[instance] then
				zones[instance] = { part = instance, state = TriggerRules.new() }
			end
		end)
	end,

	step = function(ctx)
		local base = ctx.base
		local now = os.clock()
		local C = Config.TextTrigger
		for instance, zone in zones do
			if not instance:IsDescendantOf(workspace) then
				zones[instance] = nil
				continue
			end
			local inside = base ~= nil
				and not LocalHide.isHidden(instance)
				and Pieces.inBox(zone.part, base.Position, Config.Toolkit.TriggerMargin)
			local once = Pieces.bool(instance, "Once", C.Once)
			local cooldown = Pieces.number(instance, "Cooldown", C.Cooldown)
			if TriggerRules.update(zone.state, inside, now, once, cooldown) then
				show(instance)
			end
		end
	end,

	reset = function()
		for _, zone in zones do
			TriggerRules.rearm(zone.state)
		end
	end,
}

return TextTriggers
