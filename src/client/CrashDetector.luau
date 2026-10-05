--!strict
-- Erkennt Crashs des eigenen Wagens. Laeuft auf dem Client, weil dort die Physik
-- gerechnet wird (sofortige Reaktion). Drei Arten:
--   1. Umgekippt: Wagen ist laenger als TiltTime staerker als MaxTiltAngle geneigt
--   2. Harter Aufprall: Geschwindigkeit aendert sich in einem Frame um mehr als ImpactSpeedChange
--   3. Abgestuerzt: Wagen ist unter KillY gefallen

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local CrashDetector = {}
CrashDetector.__index = CrashDetector

export type CrashReason = "Tipped" | "Impact" | "Fell"

type DetectorData = {
	tiltTime: number,
	graceTime: number,
	lastVelocity: Vector3?,
}

export type Detector = typeof(setmetatable({} :: DetectorData, CrashDetector))

function CrashDetector.new(): Detector
	local self = setmetatable({
		tiltTime = 0,
		graceTime = Config.Crash.GracePeriod,
		lastVelocity = nil,
	}, CrashDetector)
	return self
end

-- Nach einem Neustart: Zustand vergessen und kurz nichts erkennen
-- (das Zuruecksetzen selbst ist eine riesige Tempoaenderung).
function CrashDetector.reset(self: Detector)
	self.tiltTime = 0
	self.graceTime = Config.Crash.GracePeriod
	self.lastVelocity = nil
end

-- Gibt den Crash-Grund zurueck oder nil, wenn alles in Ordnung ist.
function CrashDetector.update(self: Detector, dt: number, base: BasePart): CrashReason?
	local C = Config.Crash
	local velocity = base.AssemblyLinearVelocity
	local lastVelocity = self.lastVelocity
	self.lastVelocity = velocity

	if self.graceTime > 0 then
		self.graceTime -= dt
		self.tiltTime = 0
		return nil
	end

	if base.Position.Y < C.KillY then
		return "Fell"
	end

	if lastVelocity and (velocity - lastVelocity).Magnitude >= C.ImpactSpeedChange then
		return "Impact"
	end

	-- UpVector.Y ist der Cosinus des Neigungswinkels gegenueber der Senkrechten
	if base.CFrame.UpVector.Y < math.cos(math.rad(C.MaxTiltAngle)) then
		self.tiltTime += dt
		if self.tiltTime >= C.TiltTime then
			return "Tipped"
		end
	else
		self.tiltTime = 0
	end

	return nil
end

return CrashDetector
