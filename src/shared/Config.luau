--!strict
-- Zentrale Tuning-Werte fuer das ganze Spiel.
-- Alles, was man zum Ausprobieren veraendern moechte, gehoert hierher (nicht in den Code).
--
-- Einheiten: Roblox misst in "Studs" (1 Stud ~ 28 cm). Ein Spieler ist ca. 5 Studs gross.
-- Geschwindigkeiten in Studs/Sekunde, Beschleunigungen in Studs/Sekunde^2.
-- Zum Vergleich: die Standard-Schwerkraft in Roblox ist 196.2 Studs/s^2.
--
-- Beschleunigungen werden im Code mit der Masse des Wagens multipliziert. Dadurch
-- bleibt das Fahrgefuehl gleich, auch wenn sich das Gewicht des Wagens aendert.

local Config = {}

-- Aussehen und Physik des Einkaufswagens (Platzhalter aus einfachen Parts).
Config.Cart = {
	Width = 4, -- Breite (X)
	Length = 6, -- Laenge (Z)
	WallHeight = 2, -- Hoehe der Korbwaende
	FloorThickness = 0.3,
	WheelDiameter = 1.2,
	WheelGap = 0.15, -- Abstand zwischen Korbboden und Radoberkante

	-- Gewicht: Der Korb ist leicht, ein unsichtbarer "Ballast" ersetzt das Gewicht des
	-- Fahrers. Je hoeher der Ballast sitzt, desto leichter kippt der Wagen.
	FloorDensity = 1,
	WheelDensity = 1,
	BallastMass = 10,
	BallastHeight = 2, -- Hoehe ueber dem Korbboden

	WheelFriction = 0.6,
	BodyFriction = 0.3, -- Reibung des Korbs (z. B. wenn er auf der Seite rutscht)
}

-- Fahrverhalten (laeuft auf dem Client des Fahrers).
Config.Drive = {
	-- W: anschieben / S: bremsen bzw. rueckwaerts
	PushAcceleration = 30,
	MaxPushSpeed = 35, -- ueber diesem Tempo bringt Anschieben nichts mehr
	BrakeAcceleration = 60,
	ReverseAcceleration = 15,
	MaxReverseSpeed = 12,

	-- Bremsen durch Luft und Rollen. AirDrag begrenzt das Tempo bergab:
	-- Endgeschwindigkeit ~ Wurzel(196 * sin(Hangwinkel) / AirDrag)
	AirDrag = 0.008,
	RollingResistance = 0.15,

	-- Seitenhalt: wie stark seitliches Rutschen abgebremst wird (pro Sekunde).
	-- MaxGripAcceleration begrenzt den Halt; darueber rutscht/driftet der Wagen.
	LateralGrip = 8,
	MaxGripAcceleration = 120,

	-- Lenkung (A/D)
	SteerRate = 1.8, -- maximale Drehgeschwindigkeit in Radiant/Sekunde
	SteerResponse = 8, -- wie schnell die Drehung der Eingabe folgt
	SteerMinFactor = 0.4, -- Lenkwirkung im Stand (0..1)
	SteerFullSpeed = 15, -- ab diesem Tempo volle Lenkwirkung
	SteerHighSpeed = 90, -- bei diesem Tempo nur noch SteerHighSpeedFactor
	SteerHighSpeedFactor = 0.55,
	RollDamping = 1.5, -- daempft Wackeln/Kippbewegungen am Boden (0 = aus)

	-- "Kaputtes Rad": zufaelliges Ziehen zur Seite, typisch Einkaufswagen. 0 = aus.
	WobbleStrength = 0.35, -- Radiant/Sekunde
	WobbleFrequency = 0.8,
	WobbleFullSpeed = 40, -- ab diesem Tempo voller Wackel-Effekt

	GroundCheckExtra = 0.6, -- wie weit unter den Raedern noch "Boden" erkannt wird
}

-- Verfolgerkamera
Config.Camera = {
	Distance = 14,
	Height = 6,
	LookAhead = 6, -- Blickpunkt vor dem Wagen
	LookHeight = 2,
	PositionSmoothing = 12, -- groesser = Kamera folgt straffer
	RotationSmoothing = 5,
	BaseFov = 70,
	MaxFov = 90,
	FovFullSpeed = 100, -- bei diesem Tempo ist MaxFov erreicht
	CollisionPadding = 0.5, -- Abstand zu Waenden, damit die Kamera nicht hindurchschaut
}

-- Crash-Erkennung (laeuft auf dem Client des Fahrers).
Config.Crash = {
	MaxTiltAngle = 75, -- Grad; staerker gekippt = umgekippt
	TiltTime = 0.35, -- so lange muss der Wagen gekippt sein
	ImpactSpeedChange = 60, -- Tempoaenderung in einem Frame = harter Aufprall
	KillY = -100, -- unter dieser Hoehe gilt der Wagen als abgestuerzt
	GracePeriod = 0.5, -- nach einem Neustart so lange keine Crashs erkennen
	RestartDelay = 0.5, -- so lange "CRASH!" zeigen, dann Neustart (gesamt < 1 s)
}

-- Rennablauf (Server)
Config.Race = {
	StartZoneTag = "StartZone",
	FinishZoneTag = "FinishZone",
	-- Blickrichtung am Start: "Downhill" = automatisch bergab (bei flachem Boden zur
	-- Vorderseite der Startzone), "ZoneFront" = immer zur Vorderseite der Startzone.
	StartFacing = "Downhill",
	DownhillMinSlope = 5, -- Grad; flacher gilt als eben
	MinRestartInterval = 0.3, -- Schutz gegen Spam der Neustart-Taste
	StartGrace = 0.3, -- nach einem Neustart so lange keine Zonen pruefen
	AutoRestartAfterFinish = 3, -- Sekunden nach dem Ziel bis zum Neustart (0 = aus)
	StartDistanceWithoutZone = 4, -- ohne Startzone: Zeit laeuft ab dieser Strecke
	RespawnTime = 1, -- Wartezeit, falls der Charakter doch einmal stirbt
}

-- Aus- und Einsteigen (Taste E / Gamepad X)
Config.Exit = {
	EnterDistance = 10, -- so nah (Studs) muss man am leeren Wagen sein, damit "Einsteigen" erscheint
	LandingDistance = 3.5, -- so weit neben dem Wagen landet die Figur beim Aussteigen
	ActionCooldown = 0.3, -- Schutz gegen Spam von E
	-- Leere Wagen bremsen von selbst ab, statt allein den Huegel hinunterzurollen.
	ParkBrake = 6, -- Staerke der Bremse (pro Sekunde), 0 = Wagen rollt frei
	ParkBrakeMaxAcceleration = 150,
}

-- Anzeige
Config.UI = {
	ResultDisplayTime = 3, -- so lange bleibt "ZIEL!" sichtbar
	ShowSpeed = true,
}

return Config
