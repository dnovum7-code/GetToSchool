--!strict
-- Gemeinsame Tages-Uhr fuer alles Taegliche (Hausaufgaben, Gluecksrad, Login-Belohnung).
-- Tageswechsel in UTC um Config.Homework.ResetHourUtc. Es zaehlt nur die Uhr des Servers,
-- die Systemzeit des Clients wird nie benutzt.
--
-- Debug (nur Studio, Config.Debug.DayTravel): F3 im Spiel schaltet einen Tag weiter, um
-- Serie und Rad sofort zu testen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local HomeworkLogic = require(Shared:WaitForChild("Progression"):WaitForChild("Homework"))

local DayClock = {}

local DAY = 86400
local offsetDays = 0 -- nur Studio: simulierte Tage
local listeners: { () -> () } = {}

-- "Jetzt" (Unix-Zeit, UTC) inklusive simulierter Tage
function DayClock.now(): number
	return os.time() + offsetDays * DAY
end

function DayClock.today(): number
	return HomeworkLogic.dayIndex(DayClock.now(), Config.Homework.ResetHourUtc)
end

-- Naechster Tageswechsel als echte Unix-Zeit (fuer "noch 5 Std" beim Client)
function DayClock.nextReset(): number
	return HomeworkLogic.nextReset(DayClock.now(), Config.Homework.ResetHourUtc) - offsetDays * DAY
end

function DayClock.canTravel(): boolean
	return Config.Debug.DayTravel and RunService:IsStudio()
end

-- Debug: einen Tag weiter. Gibt false zurueck, wenn nicht erlaubt.
function DayClock.advance(): boolean
	if not DayClock.canTravel() then
		return false
	end
	offsetDays += 1
	print(`[DayClock] Simulierter Tageswechsel: Tag {DayClock.today()} (+{offsetDays})`)
	for _, callback in listeners do
		task.spawn(callback)
	end
	return true
end

-- Wird nach einem (simulierten) Tageswechsel aufgerufen
function DayClock.onAdvance(callback: () -> ())
	table.insert(listeners, callback)
end

return DayClock
