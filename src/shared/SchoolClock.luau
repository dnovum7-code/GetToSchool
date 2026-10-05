--!strict
-- Spielzeit rund um die Schulglocke: Uhrzeiten lesen/anzeigen, Tempo der Spielzeit und
-- Schulnote. Wird vom Server (Ergebnis) und vom Client (Uhr im UI) benutzt.
-- Uhrzeiten werden intern als "Sekunden seit Mitternacht" gerechnet (7:45 = 27900).

local Config = require(script.Parent:WaitForChild("Config"))

local SchoolClock = {}

-- "7:45" oder "7:45:30" -> Sekunden seit Mitternacht. nil, wenn der Text ungueltig ist.
function SchoolClock.parse(text: unknown): number?
	if type(text) ~= "string" then
		return nil
	end
	local h, m, s = string.match(text, "^%s*(%d+):(%d%d):?(%d*)%s*$")
	if not h then
		return nil
	end
	return tonumber(h) :: number * 3600 + tonumber(m) :: number * 60 + (tonumber(s) or 0)
end

-- Sekunden seit Mitternacht -> "7:58" bzw. "7:58:12"
function SchoolClock.format(seconds: number, withSeconds: boolean?): string
	local total = math.max(0, math.floor(seconds))
	local h = total // 3600
	local m = (total // 60) % 60
	if withSeconds then
		return string.format("%d:%02d:%02d", h, m, total % 60)
	end
	return string.format("%d:%02d", h, m)
end

-- Dauer in Sekunden -> "3:40" (Minuten:Sekunden)
function SchoolClock.formatDuration(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

function SchoolClock.startSeconds(): number
	return SchoolClock.parse(Config.Clock.StartTime) or (7 * 3600 + 45 * 60)
end

function SchoolClock.schoolSeconds(): number
	return SchoolClock.parse(Config.Clock.SchoolTime) or (8 * 3600)
end

-- Spielsekunden pro echter Sekunde: Attribut "TimeScale" an der StartZone, sonst Config.
function SchoolClock.timeScaleFor(startZone: Instance?): number
	local value = startZone and startZone:GetAttribute("TimeScale")
	if type(value) == "number" and value > 0 then
		return value
	end
	return Config.Clock.TimeScale
end

-- Schulnote 1-6 (6 = beste) fuer eine Ankunftszeit. Grenzen aus den Attributen
-- "Grade6" ... "Grade2" an der FinishZone, sonst aus Config.Clock.GradeLimits.
function SchoolClock.gradeFor(arrival: number, finishZone: Instance?): number
	for grade = 6, 2, -1 do
		local limit = finishZone and SchoolClock.parse(finishZone:GetAttribute("Grade" .. grade))
		if not limit then
			limit = SchoolClock.parse(Config.Clock.GradeLimits[grade])
		end
		if limit and arrival <= limit then
			return grade
		end
	end
	return 1
end

return SchoolClock
