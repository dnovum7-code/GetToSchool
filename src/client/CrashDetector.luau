--!strict
-- Erkennt Crashs des eigenen Wagens. Laeuft auf dem Client, weil dort die Physik
-- gerechnet wird (sofortige Reaktion). Drei Arten:
--   1. Umgekippt: Wagen ist laenger als TiltTime staerker als MaxTiltAngle geneigt
--   2. Harter Aufprall: Geschwindigkeit aendert sich in einem Frame um mehr als ImpactSpeedChange
--   3. Abgestuerzt: Wagen ist unter KillY gefallen

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

export type CrashReason = "Tipped" | "Impact" | "Fell"

local CrashDetector = {}
CrashDetector.__index = CrashDetector

type DetectorData = {
	tiltTime: number,
	graceTime: number,
	lastVelocity: Vector3?,
	impactMultiplier: number, -- Aufprall-Schwelle mal diesem Faktor (z. B. nach JumpPad)
	relaxTime: number, -- so lange gilt impactMultiplier noch
}

export type Detector = typeof(setmetatable({} :: DetectorData, CrashDetector))

function CrashDetector.new(): Detector
	local self = setmetatable({
		tiltTime = 0,
		graceTime = Config.Crash.GracePeriod,
		lastVelocity = nil,
		impactMultiplier = 1,
		relaxTime = 0,
	}, CrashDetector)
	return self
end

-- Nach einem Neustart: Zustand vergessen und kurz nichts erkennen
-- (das Zuruecksetzen selbst ist eine riesige Tempoaenderung).
function CrashDetector.reset(self: Detector)
	self.tiltTime = 0
	self.graceTime = Config.Crash.GracePeriod
	self.lastVelocity = nil
	self.impactMultiplier = 1
	self.relaxTime = 0
end

-- Aufprall-Crashs fuer `seconds` erst ab dem `multiplier`-fachen der normalen Schwelle
-- erkennen (math.huge = gar nicht). Fuer Bouncy-Teile und Landungen nach JumpPads.
function CrashDetector.relaxImpact(self: Detector, multiplier: number, seconds: number)
	if self.relaxTime <= 0 or multiplier > self.impactMultiplier then
		self.impactMultiplier = multiplier
	end
	self.relaxTime = math.max(self.relaxTime, seconds)
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

	local impactThreshold = C.ImpactSpeedChange
	if self.relaxTime > 0 then
		self.relaxTime -= dt
		impactThreshold *= self.impactMultiplier
	else
		self.impactMultiplier = 1
	end
	if lastVelocity and (velocity - lastVelocity).Magnitude >= impactThreshold then
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
