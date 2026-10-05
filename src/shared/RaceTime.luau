--!strict
-- Rennzeit: Anzeige-Formate und Schulnote. Wird von Server (Ergebnis) und Client (UI) benutzt.

local Attributes = require(script.Parent:WaitForChild("Attributes"))
local Config = require(script.Parent:WaitForChild("Config"))

local RaceTime = {}

-- 83.456 -> "1:23.45" (Minuten:Sekunden.Hundertstel)
function RaceTime.format(seconds: number): string
	local hundredths = math.max(0, math.floor(seconds * 100 + 0.5))
	local minutes = hundredths // 6000
	local rest = hundredths % 6000
	return string.format("%d:%02d.%02d", minutes, rest // 100, rest % 100)
end

-- Abstand zur Bestzeit: -0.45 -> "-0.45", 1.2 -> "+1.20"
function RaceTime.formatDelta(seconds: number): string
	local sign = if seconds < 0 then "-" else "+"
	return sign .. string.format("%.2f", math.abs(seconds))
end

-- Schulnote 1-6 (6 = beste) fuer eine Fahrzeit in Sekunden. Grenzen aus den Attributen
-- "Grade6" ... "Grade2" (Zahl, Sekunden) an der FinishZone, sonst aus Config.Race.GradeLimits.
-- Langsamer als Grade2 = Note 1.
function RaceTime.gradeFor(seconds: number, finishZone: Instance?): number
	for grade = 6, 2, -1 do
		local default = Config.Race.GradeLimits[grade]
		local limit = if finishZone then Attributes.number(finishZone, "Grade" .. grade, default) else default
		if seconds <= limit then
			return grade
		end
	end
	return 1
end

return RaceTime
