--!strict
-- Meldet dem Server Werte, die nur der Client kennt (Fahrphysik laeuft hier), z. B. die
-- Driftzeit fuer die Hausaufgaben. Der Server prueft und begrenzt die Werte (server/Homework).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CartController = require(script.Parent:WaitForChild("CartController"))

local reportRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ReportStat") :: RemoteEvent

local StatReporter = {}

local driftSeconds = 0
local sinceReport = 0

-- Gesammelte Driftzeit jetzt schicken (z. B. im Ziel)
function StatReporter.flush()
	if driftSeconds > 0.05 then
		reportRemote:FireServer("Drift", driftSeconds)
	end
	driftSeconds = 0
	sinceReport = 0
end

-- Jeden Frame waehrend der Fahrt. `running` = Lauf laeuft gerade.
function StatReporter.step(dt: number, telemetry: CartController.Telemetry, running: boolean)
	if running and telemetry.grounded and telemetry.driftCharging then
		driftSeconds += dt
	end
	sinceReport += dt
	if sinceReport >= Config.Homework.DriftReportInterval then
		StatReporter.flush()
	end
end

return StatReporter
