--!strict
-- Taegliches Gluecksrad, Server-Seite: Drehen ueber den Shop ("Spin", nur ausserhalb eines
-- Laufs), der Server wuerfelt und schreibt gut; der Client bekommt das Feld fuer die Animation
-- ("SpinResult"). Powerups (Items) werden beim Start des naechsten Laufs verbraucht.
-- Logik: Progression/DailySpin, Werte: Config.DailySpin.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CosmeticsLogic = require(Shared:WaitForChild("Progression"):WaitForChild("Cosmetics"))
local DailySpinLogic = require(Shared:WaitForChild("Progression"):WaitForChild("DailySpin"))
local Cosmetics = require(script.Parent:WaitForChild("Cosmetics"))
local DayClock = require(script.Parent:WaitForChild("DayClock"))
local PlayerEvents = require(script.Parent:WaitForChild("PlayerEvents"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local ProgressSync = require(script.Parent:WaitForChild("ProgressSync"))
local RaceManager = require(script.Parent:WaitForChild("RaceManager"))
local Shop = require(script.Parent:WaitForChild("Shop"))

local progressRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Progress") :: RemoteEvent

local DailySpin = {}

local random = Random.new()

local function today(): number
	return DayClock.today()
end

local function freeSpins(): boolean
	return Config.Debug.FreeSpins and RunService:IsStudio()
end

local function itemName(id: string): string
	local item = (Config.DailySpin.Items :: any)[id]
	return if item then item.name else id
end

local function spin(player: Player, _id: unknown): (boolean, string)
	if not Config.DailySpin.Enabled then
		return false, "Das Gluecksrad ist heute zu."
	end
	local data = Profiles.get(player)
	local day = today()
	if freeSpins() then
		data.spinDay = math.min(data.spinDay, day - 1)
	end
	if not DailySpinLogic.canSpin(data.spinDay, day) then
		return false, "Heute schon gedreht - morgen wieder!"
	end
	local segments = Config.DailySpin.Segments :: { any }
	local index = DailySpinLogic.pick(segments, random:NextNumber())
	local segment = segments[index]
	DailySpinLogic.apply(data :: any, segment, day, Config.DailySpin.MaxItems)
	local text: string
	if segment.kind == "Coins" then
		text = `{segment.amount} Muenzen`
	elseif segment.kind == "MeterBoost" then
		text = `x2 Meter fuer {segment.amount} Laeufe`
	elseif segment.kind == "Color" then
		-- zufaellige Wagenfarbe, die man noch nicht hat; hat man alle: Muenzen
		local color = CosmeticsLogic.pickUnowned(
			Config.Cosmetics.Colors :: any,
			data.cosmetics.colors,
			random:NextNumber()
		)
		if color then
			Cosmetics.grantColor(player, color.id)
			text = `Wagenfarbe "{color.name}"`
		else
			data.coins += segment.amount
			text = `{segment.amount} Muenzen (alle Farben schon da)`
		end
	else
		text = `{segment.amount}x {itemName(segment.item or "")}`
	end
	Profiles.markChanged(player)
	Profiles.saveSoon(player)
	progressRemote:FireClient(player, "SpinResult", index, text)
	return true, "Das Rad dreht sich ..."
end

function DailySpin.init()
	Shop.addHandler("Spin", spin)
	-- Lauf startet: von jedem Powerup eins verbrauchen
	PlayerEvents.on(function(player, event)
		if event.type ~= "RunStarted" then
			return
		end
		local data = Profiles.get(player)
		local used = DailySpinLogic.consumeForRun(data.items, Config.DailySpin.ItemOrder)
		if #used == 0 then
			return
		end
		Profiles.markChanged(player)
		local lives = if table.find(used, "ExtraLife") then 1 else 0
		local shield = if table.find(used, "ExtraShield") then 1 else 0
		if lives > 0 or shield > 0 then
			RaceManager.addRunBonus(player, lives, shield)
		end
		progressRemote:FireClient(player, "Powerups", used)
	end)
	ProgressSync.addExtender(function(player, snapshot)
		local data = Profiles.get(player)
		snapshot.spin = {
			canSpin = Config.DailySpin.Enabled
				and (freeSpins() or DailySpinLogic.canSpin(data.spinDay, today())),
			nextReset = DayClock.nextReset(),
			items = table.clone(data.items),
		}
	end)
end

return DailySpin
