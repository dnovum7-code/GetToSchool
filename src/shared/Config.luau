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
	MaxSpeed = 110, -- Hoechsttempo: darueber bremst der Wagen deutlich ab
	OverSpeedBrake = 10, -- wie hart ueber MaxSpeed gebremst wird (pro Sekunde)
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

-- Drift mit Handbremse (Shift / Gamepad B). Laeuft auf dem Client des Fahrers.
-- Mit gezogener Handbremse wird der Seitenhalt auf Vorder- und Hinterachse aufgeteilt.
-- Hinten haelt der Wagen kaum noch, also bricht das Heck aus. Die Vorderraeder zeigen im
-- Drift in Lenkrichtung: Gegenlenken stellt sie in Rutschrichtung und faengt den Wagen ab.
Config.Drift = {
	RearGrip = 0.15, -- Seitenhalt hinten mit Handbremse (Anteil von Drive.LateralGrip)
	EngageTime = 0.1, -- so schnell (s) greift die Handbremse
	GripRecoverTime = 0.2, -- so schnell (s) kommt der Halt nach dem Loslassen zurueck
	HandbrakeDeceleration = 8, -- leichtes Abbremsen durch die Handbremse
	SteerAngle = 30, -- Lenkeinschlag der Vorderraeder im Drift (Grad)
	SteerRate = 2.6, -- Drehgeschwindigkeit der Lenkhilfe im Drift (Radiant/s)
	SteerResponseFactor = 0.35, -- Staerke der Lenkhilfe im Drift (Anteil von Drive.SteerResponse)

	-- Schutz gegen ungewollte 180er: ab diesem Driftwinkel dreht eine Kraft zurueck
	RecoverAngle = 55, -- Grad zwischen Blick- und Fahrtrichtung
	RecoverStrength = 12, -- Staerke der Rueckstellkraft (0 = aus)

	-- Boost: Driftzeit zaehlt nur am Boden, ab Mindesttempo und Mindest-Driftwinkel
	MinSpeed = 25, -- Studs/s
	MinAngle = 12, -- Grad
	Level1Time = 1.0, -- Sekunden Driftzeit fuer Stufe 1
	Level2Time = 2.0, -- Sekunden Driftzeit fuer Stufe 2
	Level1Boost = 0.15, -- Schub beim Loslassen: Anteil von Drive.MaxSpeed (0.15 = +15 %)
	Level2Boost = 0.25,
	BoostDuration = 0.4, -- so lange (s) wird geschoben
	BoostFadeTime = 1.0, -- so lange (s) darf man danach noch schneller als MaxSpeed sein

	-- Effekte (nur lokal sichtbar)
	SparkColor = Color3.fromRGB(255, 240, 200), -- Funken ohne Boost-Ladung
	Level1Color = Color3.fromRGB(80, 170, 255), -- Stufe 1: blau
	Level2Color = Color3.fromRGB(255, 140, 40), -- Stufe 2: orange
	SkidMarkInterval = 0.05, -- alle x Sekunden ein Stueck Reifenspur pro Hinterrad
	SkidMarkLifetime = 3, -- so lange (s) bis eine Spur verschwunden ist
	MaxSkidMarks = 150, -- Obergrenze (Performance); die aeltesten werden wiederverwendet
	SkidMarkWidth = 0.35,
}

-- Streckenbausteine: normale Parts mit Tag (CollectionService). Werte hier sind
-- Standardwerte; einzelne Parts koennen sie per Attribut ueberschreiben (in Klammern).
Config.Track = {
	-- BoostPad: Schub in Blickrichtung (Vorderseite) des Parts (Attribut "Strength")
	BoostPadStrength = 40, -- Studs/s Tempo-Zuwachs
	-- JumpPad: schleudert nach oben, entlang der Oberseite des Parts (Attribut "Strength")
	JumpPadStrength = 70, -- Studs/s nach oben (70 = ca. 12 Studs hoch)
	PadCooldown = 0.5, -- Pads wirken nur beim Drauffahren; so lange (s) muss man weg gewesen sein
	-- Nach einem JumpPad zaehlt eine harte Landung erst ab dem x-fachen Crash.ImpactSpeedChange
	JumpLandingTolerance = 2.5,

	-- Mud: bremst stark, solange ein Rad drauf ist; Drift-Ladung pausiert (Attribut "Drag")
	MudDrag = 3, -- Bremsen pro Sekunde (Anteil des Tempos)
	-- Ice: kaum Seitenhalt, alles rutscht (Attribut "Grip")
	IceGrip = 0.1, -- Anteil des normalen Seitenhalts
	IceSteer = 0.4, -- Anteil der normalen Lenkhilfe auf Eis

	-- Bouncy: federt ab statt Crash (Attribut "Bounciness", 0..1)
	BouncyElasticity = 0.9,
	BouncyCrashGrace = 0.4, -- so lange (s) nach Kontakt keine Aufprall-Crashs

	-- Hazard: sofortiger Crash bei Beruehrung (Attribute "Message": Text, "Solid": true = fest)
	HazardMessage = "Gefahrenzone!",
	SensorPadding = 0.3, -- so viel (Studs) um den Wagen herum zaehlt schon als Beruehrung
}

-- Bewegte Hindernisse (Standardwerte; Attribute am Part/Modell gehen vor).
-- Alle Zeiten in Sekunden, Winkel in Grad. Attribut "Phase" (Sekunden) verschiebt den Takt,
-- damit nicht alle Hindernisse gleichzeitig loslegen.
Config.Movers = {
	-- Mover: faehrt von der Startposition zu Startposition + Offset und zurueck
	MoverOffset = Vector3.new(0, 0, -30), -- Attribut "Offset" (Vector3), relativ zum Part (-Z = vorne)
	MoverDuration = 3, -- Attribut "Duration": Fahrzeit fuer eine Richtung
	MoverPause = 1, -- Attribut "Pause": Wartezeit an jedem Ende
	-- Spinner: dreht sich um die eigene Hochachse
	SpinnerSpeed = 90, -- Attribut "Speed": Grad pro Sekunde (negativ = andersherum)
	-- Pendulum: schwingt um die Oberkante des Parts (bei Modellen um den Pivot), Achse = X
	PendulumAngle = 45, -- Attribut "Angle": maximaler Ausschlag zu jeder Seite
	PendulumDuration = 3, -- Attribut "Duration": Zeit fuer einmal hin und zurueck
}

-- Zufallsereignisse: Parts/Modelle mit Tag "RandomEvent" sind pro Lauf aktiv oder nicht.
-- Attribut "Chance" (0..1): Wahrscheinlichkeit, dass es aktiv ist.
-- Attribut "Group" (Text): aus jeder Gruppe ist pro Lauf genau ein Element aktiv
-- (dann wirkt "Chance" als Gewicht: 2 = doppelt so oft wie 1).
Config.Events = {
	DefaultChance = 0.5,
	DefaultGroupWeight = 1,
}

-- Sounds (nur lokal). Id leer lassen = kein Sound, kein Fehler.
-- Id aus dem Creator Store eintragen, z. B. 1234567 oder "rbxassetid://1234567".
Config.Sounds = {
	-- Rollgeraeusch, laeuft dauernd; Tonhoehe und Lautstaerke steigen mit dem Tempo
	Engine = { Id = "", Volume = 0.4, MinPitch = 0.6, MaxPitch = 1.6, FullSpeed = 100 },
	Drift = { Id = "", Volume = 0.5 }, -- Quietschen, laeuft waehrend des Drifts
	Boost = { Id = "", Volume = 0.7 }, -- Drift-Boost und BoostPad
	Crash = { Id = "", Volume = 0.8 },
	Checkpoint = { Id = "", Volume = 0.6 },
	Bell = { Id = "", Volume = 0.8 }, -- Schulglocke um 8:00
	Finish = { Id = "", Volume = 0.8 }, -- im Ziel
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

	-- Kamera-Wackeln (Winkel in Grad)
	ShakeSpeedStart = 60, -- ab diesem Tempo beginnt das Wackeln ...
	ShakeAtFullSpeed = 0.6, -- ... und ist bei FovFullSpeed so stark
	LandingShakeMinSpeed = 25, -- harte Landung: ab dieser Fallgeschwindigkeit (Studs/s) wackelt es
	LandingShakePerSpeed = 0.06, -- Wackeln pro Studs/s ueber LandingShakeMinSpeed
	ShakeMaxAngle = 3, -- Obergrenze, damit niemandem schlecht wird
	ShakeFrequency = 18, -- wie schnell es zittert
	ShakeDecay = 4, -- wie schnell das Landungs-Wackeln abklingt (pro Sekunde)
}

-- Crash-Erkennung (laeuft auf dem Client des Fahrers).
Config.Crash = {
	MaxTiltAngle = 75, -- Grad; staerker gekippt = umgekippt
	TiltTime = 0.35, -- so lange muss der Wagen gekippt sein
	ImpactSpeedChange = 60, -- Tempoaenderung in einem Frame = harter Aufprall
	KillY = -100, -- unter dieser Hoehe gilt der Wagen als abgestuerzt
	GracePeriod = 0.5, -- nach einem Neustart so lange keine Crashs erkennen
	RestartDelay = 1.2, -- so lange den Crash zeigen, dann Neustart (R ueberspringt das)

	-- Ragdoll: Bei einem Crash fliegt die Figur schlaff aus dem Wagen.
	Ragdoll = true, -- false = Figur bleibt im Wagen sitzen
	RagdollCarry = 0.8, -- Anteil des Wagen-Tempos, den die Figur mitnimmt
	RagdollForwardBoost = 10, -- zusaetzlicher Schwung in Fahrtrichtung (Studs/s)
	RagdollUpSpeed = 25, -- Schwung nach oben (Studs/s)
	RagdollSpin = 6, -- zufaelliges Drehen (Radiant/s), fuer mehr Slapstick
	RagdollJointAngle = 60, -- wie weit Arme, Beine und Kopf schlackern duerfen (Grad)
	ServerRestartTimeout = 4, -- Sicherheitsnetz: so lange (s) nach dem Crash startet der Server selbst neu
}

-- Rennablauf (Server)
Config.Race = {
	StartZoneTag = "StartZone",
	FinishZoneTag = "FinishZone",
	-- Blickrichtung am Start: "Downhill" = automatisch bergab (bei flachem Boden zur
	-- Vorderseite der Startzone), "ZoneFront" = immer zur Vorderseite der Startzone.
	StartFacing = "Downhill",
	DownhillMinSlope = 5, -- Grad; flacher gilt als eben
	MinRestartInterval = 0.3, -- Schutz gegen Spam der Neustart-Tasten (R / T)
	StartGrace = 0.3, -- nach einem Neustart so lange keine Zonen pruefen
	AutoRestartAfterFinish = 5, -- Sekunden nach dem Ziel bis zum Neustart (0 = aus)
	StartDistanceWithoutZone = 4, -- ohne Startzone: Zeit laeuft ab dieser Strecke
	RespawnTime = 1, -- Wartezeit, falls der Charakter doch einmal stirbt
}

-- Schulglocke: Spielzeit statt Stoppuhr. Jeder Lauf startet um StartTime, die Schule
-- beginnt um SchoolTime. Uhrzeiten als Text "H:MM" oder "H:MM:SS".
Config.Clock = {
	StartTime = "7:45",
	SchoolTime = "8:00",
	-- Spielsekunden pro echter Sekunde. 15 = die 15 Minuten bis 8:00 dauern 60 echte Sekunden.
	-- Pro Track ueberschreibbar: Attribut "TimeScale" (Zahl) an der StartZone.
	TimeScale = 15,
	NervousShare = 0.2, -- in den letzten 20 % vor SchoolTime tickt die Uhr nervoes
	-- Schulnoten (Schweizer System, 6 = beste): spaetestens um diese Uhrzeit ankommen.
	-- Pro Track ueberschreibbar: Attribute "Grade6" ... "Grade2" (Text) an der FinishZone.
	-- Spaeter als Grade2 = Note 1.
	GradeLimits = {
		[6] = "7:53",
		[5] = "7:56",
		[4] = "8:00", -- 4 = genuegend: puenktlich
		[3] = "8:02",
		[2] = "8:05",
	},
	OnTimeTitle = "PUENKTLICH!",
	-- Zufaellige Titel, wenn man zu spaet kommt
	LateMessages = {
		"Ab zum Rektor!",
		"Nachsitzen!",
		"Der Hund hat die Hausaufgaben gefressen?",
		"Eintrag ins Klassenbuch!",
		"Die Lehrerin schaut schon auf die Uhr...",
		"Schon wieder du?!",
	},
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
	ResultDisplayTime = 5, -- so lange bleibt der Ergebnis-Screen sichtbar
	ShowSpeed = true, -- kleine Anzeige in Studs/s (fuers Tunen)
	-- Tacho: 1 Stud entspricht in Roblox etwa 0.28 m, also km/h = Studs/s * 0.28 * 3.6
	StudsToMeters = 0.28,
	SpeedometerMaxKmh = 120, -- bei diesem Tempo ist der Tacho-Balken voll
}

return Config
