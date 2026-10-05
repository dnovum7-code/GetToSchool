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
	-- W: Motor ("anschieben"). Er schiebt nur bis MaxPushSpeed; bergab darf der Wagen durch
	-- die Schwerkraft schneller werden, ohne dass etwas bremst.
	PushAcceleration = 45, -- Motorkraft (Studs/s^2)
	MaxPushSpeed = 60, -- Motor-Hoechsttempo auf flachem Boden
	-- S: bremst kraeftig, im Stand rueckwaerts
	BrakeAcceleration = 100,
	ReverseAcceleration = 15,
	MaxReverseSpeed = 12,

	-- Ausrollen ohne Gas: Rollwiderstand (pro Sekunde, Anteil des Tempos). Mit W: kein Rollwiderstand.
	RollingResistance = 0.063,
	-- Leichter Luftwiderstand (waechst mit dem Tempo im Quadrat), wirkt immer.
	-- Endtempo bergab ~ Wurzel(196 * sin(Hangwinkel) / AirDrag), z. B. 10 Grad -> ~220 Studs/s;
	-- ab ca. 13 Grad Gefaelle begrenzt TerminalSpeed
	AirDrag = 0.00069,
	-- Sicherheitsgrenze gegen Physik-Fehler (kein Gameplay-Limit)
	TerminalSpeed = 250,

	-- Seitenhalt: wie stark seitliches Rutschen abgebremst wird (pro Sekunde).
	-- MaxGripAcceleration begrenzt den Halt; darueber rutscht/driftet der Wagen.
	LateralGrip = 8,
	MaxGripAcceleration = 120,

	-- Lenkung (A/D)
	-- Normale Lenkung nur fuer leichte Korrekturen; die Hauptarbeit macht der Drift.
	SteerRate = 1.1, -- maximale Drehgeschwindigkeit in Radiant/Sekunde
	SteerResponse = 8, -- wie schnell die Drehung der Eingabe folgt
	SteerMinFactor = 0.4, -- Lenkwirkung im Stand (0..1)
	SteerFullSpeed = 15, -- ab diesem Tempo volle Lenkwirkung
	SteerHighSpeed = 90, -- bei diesem Tempo nur noch SteerHighSpeedFactor
	SteerHighSpeedFactor = 0.55,
	RollDamping = 1.5, -- daempft Wackeln/Kippbewegungen am Boden (0 = aus)

	-- "Kaputtes Rad": zufaelliges, langsames Ziehen nach links oder rechts (der "Drall" nach
	-- ein paar Metern), typisch Einkaufswagen. 0 = aus.
	WobbleStrength = 0.15, -- Radiant/Sekunde
	WobbleFrequency = 0.8,
	WobbleMinSpeed = 12, -- darunter kein Wackeln (z. B. beim Losfahren)
	WobbleFullSpeed = 40, -- ab diesem Tempo voller Wackel-Effekt
	WobbleFadeInTime = 2, -- nach dem Einsteigen blendet das Wackeln so lange (s) weich ein

	-- Nach dem Einsteigen/Neustart so lange (s) Restdrehungen wegdaempfen, damit der Wagen
	-- beim Losfahren nicht hin und her ruckelt.
	SettleTime = 0.5,
	SettleDamping = 10,

	GroundCheckExtra = 0.6, -- wie weit unter den Raedern noch "Boden" erkannt wird
}

-- Drift. Laeuft auf dem Client des Fahrers.
-- DriftByDefault = true: Der Wagen ist immer im Drift-Modus, Shift (Gamepad B) haelt ihn
-- im normalen Fahrmodus. false: umgekehrt, Shift = Drift (Handbremse).
-- Gefuehl: Einkaufswagen mit lenkenden Vorderraedern und "wirren" Hinterraedern. Die Front
-- zieht den Wagen durch die Kurve (die Lenkung bestimmt, wie schnell er sich dreht), der
-- Seitenhalt wird weicher, also schwingt das Heck aus. Ab MaxAngle drehen Lenkung und
-- zusaetzlicher Halt zurueck: kein Dreher, auch nicht bei langem Driften.
Config.Drift = {
	DriftByDefault = true,
	EngageTime = 0.15, -- so schnell (s) greift die Handbremse
	GripRecoverTime = 0.3, -- so schnell (s) kommt der volle Halt nach dem Loslassen zurueck
	HandbrakeDeceleration = 4, -- leichtes Abbremsen, nur solange der Wagen wirklich rutscht
	LateralGrip = 3.5, -- Seitenhalt im Drift (normal: Drive.LateralGrip = 8). Kleiner = weiter ausschwingen
	SteerRate = 2.4, -- Drehgeschwindigkeit im Drift (Radiant/s) - staerker als normal
	SteerResponseFactor = 0.6, -- wie direkt die Drehung folgt (Anteil von Drive.SteerResponse); kleiner = weicher

	-- Grenze fuer den Driftwinkel (Grad zwischen Blick- und Fahrtrichtung). Darueber dreht
	-- der Wagen zurueck und haelt seitlich staerker. Die Namen bleiben fuers Tuning-Panel.
	RecoverAngle = 30, -- maximaler Driftwinkel (Grad)
	RecoverStrength = 25, -- wie hart die Grenze zurueckdreht (0 = aus)

	-- "Wirres Heck": kleines, unregelmaessiges Pendeln im Drift (nur solange der Wagen rutscht)
	TailWobble = 0.5, -- Staerke (Radiant/s); 0 = aus
	TailWobbleFrequency = 2.5, -- wie schnell es pendelt

	-- Boost: Driftzeit zaehlt nur am Boden, ab Mindesttempo und Mindest-Driftwinkel.
	-- Der Boost kommt, sobald der Drift endet: Shift gedrueckt (bzw. losgelassen, wenn
	-- DriftByDefault = false) oder der Wagen faehrt ReleaseDelay Sekunden lang wieder gerade.
	MinSpeed = 25, -- Studs/s
	MinAngle = 12, -- Grad
	ReleaseDelay = 0.25, -- so lange (s) gerade fahren, bis der Drift als beendet gilt
	Level1Time = 1.0, -- Sekunden Driftzeit fuer Stufe 1
	Level2Time = 2.0, -- Sekunden Driftzeit fuer Stufe 2
	Level1Boost = 0.4, -- Tempo-Zuwachs: Anteil von Drive.MaxPushSpeed (0.4 = +40 % = +24 Studs/s)
	Level2Boost = 0.7,
	BoostDuration = 0.5, -- ueber so viele Sekunden wird der Zuwachs verteilt

	-- Effekte (nur lokal sichtbar)
	SparkColor = Color3.fromRGB(255, 240, 200), -- Funken ohne Boost-Ladung
	Level1Color = Color3.fromRGB(80, 170, 255), -- Stufe 1: blau
	Level2Color = Color3.fromRGB(255, 140, 40), -- Stufe 2: orange
	SkidMinAngle = 8, -- Reifenspuren und Quietschen erst ab diesem Driftwinkel (Grad), also nur in Kurven
	SkidMarkInterval = 0.05, -- alle x Sekunden ein Stueck Reifenspur pro Hinterrad
	SkidMarkLifetime = 3, -- so lange (s) bis eine Spur verschwunden ist
	MaxSkidMarks = 150, -- Obergrenze (Performance); die aeltesten werden wiederverwendet
	SkidMarkWidth = 0.35,
}

-- Hopp (wie Mario Kart): Leertaste (Gamepad A) laesst den Wagen kurz huepfen. In der Luft
-- dreht er sich in Lenkrichtung; so wechselt man z. B. schnell von einem Links- in einen
-- Rechtsdrift. Die Drift-Ladung bleibt dabei erhalten.
Config.Hop = {
	Enabled = true,
	Speed = 37.1, -- Sprung-Tempo nach oben (Studs/s); Hoehe ~ Speed^2 / 392, 37 = ca. 3.5 Studs
	Cooldown = 0.35, -- Mindestabstand zwischen zwei Hopps (s)
	TurnRate = 1.57, -- Drehgeschwindigkeit in der Luft (Radiant/s)
	TurnResponse = 12, -- wie direkt die Drehung in der Luft folgt
	MinAirTime = 0.12, -- so lange (s) gilt der Wagen nach dem Hopp sicher als "in der Luft"
	MaxAirTime = 0.6, -- spaetestens dann endet die Hopp-Drehung
}

-- Streckenbausteine: normale Parts mit Tag (CollectionService). Werte hier sind
-- Standardwerte; einzelne Parts koennen sie per Attribut ueberschreiben (in Klammern).
Config.Track = {
	-- BoostPad: Schub in Blickrichtung (Vorderseite) des Parts (Attribut "Strength")
	BoostPadStrength = 40, -- Studs/s Tempo-Zuwachs
	-- JumpPad: schleudert nach oben, entlang der Oberseite des Parts (Attribut "Strength")
	JumpPadStrength = 86, -- Studs/s nach oben (86 = ca. 19 Studs hoch, +23 %)
	PadCooldown = 0.5, -- Pads wirken nur beim Drauffahren; so lange (s) muss man weg gewesen sein
	-- Erkennung der Bodenbausteine: Kasten an der Aufstandsflaeche jedes Rads (Studs)
	FloorSensorAbove = 0.4, -- so weit ueber der Radunterseite
	FloorSensorBelow = 0.5, -- so weit darunter (fuer buendige oder leicht eingelassene Parts)
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
	Finish = { Id = "", Volume = 0.8 }, -- im Ziel
}

-- Tuning-Panel (nur in Studio, Taste F2): welche Werte als Regler erscheinen.
-- path: "Abschnitt.Name" in dieser Config. Jeder Regler startet in der MITTE, die Mitte ist
-- der Wert beim Spielstart. Bereich: 0 bis doppelter Wert. Sonderfaelle:
--   span = halbe Breite (Bereich = Wert - span .. Wert + span), z. B. fuer Winkel. Ist der
--          Wert 0, gilt min .. min + span (Standard 1), weil "Mitte" dann nicht geht.
--   min  = untere Grenze (Standard 0); der Bereich bleibt symmetrisch um den Wert
-- server = true: Der Wert wird zusaetzlich an den Server geschickt (er baut z. B. den Ballast).
Config.TuningPanel = {
	{ label = "Motorkraft", path = "Drive.PushAcceleration" },
	{ label = "Hoechsttempo (Motor)", path = "Drive.MaxPushSpeed" },
	{ label = "Bremskraft (S)", path = "Drive.BrakeAcceleration" },
	{ label = "Ausrollen", path = "Drive.RollingResistance" },
	{ label = "Luftwiderstand", path = "Drive.AirDrag" },
	{ label = "Lenkung", path = "Drive.SteerRate" },
	{ label = "Seitenhalt", path = "Drive.LateralGrip" },
	{ label = "Kipp-Ballast (Hoehe)", path = "Cart.BallastHeight", server = true },
	{ label = "Drift-Seitenhalt", path = "Drift.LateralGrip" },
	{ label = "Drift-Lenkung", path = "Drift.SteerRate" },
	{ label = "Max. Driftwinkel (Grad)", path = "Drift.RecoverAngle", span = 25, min = 5 }, -- Winkel: 5 .. 55
	{ label = "Rueckstell-Staerke", path = "Drift.RecoverStrength" },
	{ label = "Heck-Pendeln", path = "Drift.TailWobble", span = 1 }, -- span: falls auf 0 gesetzt
	{ label = "Hopp-Hoehe (Tempo)", path = "Hop.Speed" },
	{ label = "Hopp-Drehung", path = "Hop.TurnRate" },
	{ label = "Boost-Schwelle 1 (s)", path = "Drift.Level1Time" },
	{ label = "Boost-Schwelle 2 (s)", path = "Drift.Level2Time" },
	{ label = "Drift-Boost Stufe 1", path = "Drift.Level1Boost" }, -- Anteil vom Motor-Hoechsttempo
	{ label = "Drift-Boost Stufe 2", path = "Drift.Level2Boost" },
	{ label = "Drift-Boost Dauer (s)", path = "Drift.BoostDuration" },
	{ label = "Drift-Ende (s gerade)", path = "Drift.ReleaseDelay" },
	{ label = "Wackelrad (Drall)", path = "Drive.WobbleStrength", span = 0.5 }, -- span: falls auf 0 gesetzt
	{ label = "Schlamm-Bremse", path = "Track.MudDrag" },
	{ label = "Eis-Seitenhalt", path = "Track.IceGrip" },
	{ label = "BoostPad-Staerke", path = "Track.BoostPadStrength" },
	{ label = "JumpPad-Staerke", path = "Track.JumpPadStrength" },
}

-- Fehlersuche (nur in Studio wirksam)
Config.Debug = {
	-- true = im Output melden, wenn ein Rad einen Bodenbaustein erkennt und welcher
	-- Effekt (BoostPad, JumpPad) ausgeloest wird
	TrackPieces = false,
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

	-- Boost (Drift-Boost, BoostPad): Sichtfeld kurz weiter, damit man den Schub spuert
	BoostFovKick = 10, -- Grad
	BoostFovDecay = 2.5, -- wie schnell es zurueckgeht (pro Sekunde)
}

-- Crash-Erkennung (laeuft auf dem Client des Fahrers).
Config.Crash = {
	MaxTiltAngle = 75, -- Grad; staerker gekippt = umgekippt
	TiltTime = 0.35, -- so lange muss der Wagen gekippt sein
	ImpactSpeedChange = 60, -- Tempoaenderung in einem Frame = harter Aufprall
	KillY = -100, -- unter dieser Hoehe gilt der Wagen als abgestuerzt
	GracePeriod = 0.5, -- nach einem Neustart so lange keine Crashs erkennen
	RestartDelay = 1.2, -- so lange den Crash zeigen, dann Neustart (R ueberspringt das)
	-- Selbst verursachte Tempo-Spruenge (BoostPad, JumpPad, Drift-Boost, Hopp) sind kein Aufprall.
	-- Danach ist die Aufprall-Erkennung so lange (s) um diesen Faktor toleranter:
	SelfImpulseGrace = 0.3,
	SelfImpulseTolerance = 2,

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

	-- Schulnoten (Schweizer System, 6 = beste): Fahrzeit in Sekunden, die man hoechstens
	-- brauchen darf. Pro Track ueberschreibbar: Attribute "Grade6" ... "Grade2" (Zahl) an
	-- der FinishZone. Langsamer als Grade2 = Note 1.
	GradeLimits = {
		[6] = 60,
		[5] = 75,
		[4] = 90,
		[3] = 110,
		[2] = 130,
	},

	-- Bestzeiten: pro Spieler und Track dauerhaft gespeichert (DataStore).
	-- Welcher Track: Attribut "TrackId" (Text) an der StartZone, sonst DefaultTrackId.
	DefaultTrackId = "Track1",
	BestTimesStore = "BestTimes_v1", -- Name des DataStores (aendern = alle Bestzeiten neu)
	SaveBestTimes = true, -- false = Bestzeiten nur fuer die laufende Sitzung
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
	SpeedometerMaxKmh = 150, -- bei diesem Tempo ist der Tacho-Balken voll
}

return Config
