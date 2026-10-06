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

-- Muenzen (Baustein "Coin": Part oder Modell mit Tag "Coin", Attribut "Value" = Wert).
-- Eingesammelte Muenzen gehoeren sofort dem Spieler, auch nach Crash oder Abbruch. Die Muenze
-- selbst erscheint erst wieder, wenn der Spieler das Ziel ihrer Strecke erreicht (nicht bei T).
Config.Coins = {
	DefaultValue = 1, -- Wert einer Muenze ohne Attribut "Value"
	MaxValue = 100, -- Obergrenze fuer "Value" (Schutz vor Tippfehlern)
	PickupRadius = 3.5, -- Client: so nah (Studs, plus halbe Muenzgroesse) muss die Wagenmitte kommen
	-- Server-Pruefung: hoechstens so weit weg (Studs, plus halbe Muenzgroesse) ...
	MaxPickupDistance = 12,
	LatencyAllowance = 0.3, -- ... plus Tempo * diese Sekunden (der Server sieht den Wagen verspaetet)
	SpinSpeed = 180, -- Drehung (Grad pro Sekunde, nur Anzeige)
	BobHeight = 0.3, -- Auf und Ab (Studs)
	BobSpeed = 2.5,
	-- Belohnung im Ziel: Grundbetrag plus Bonus je nach Note (6 = beste)
	FinishBase = 10,
	GradeBonus = { [6] = 20, [5] = 12, [4] = 7, [3] = 4, [2] = 2, [1] = 0 },
}

-- Launchables (Baustein "Launchable": Kuh, Muelltonne, Gartenzwerg, Briefkasten ...).
-- Faehrt man hinein, kostet das ein Leben, aber der Wagen faehrt weiter (kurz abgebremst).
-- Das Objekt fliegt absurd weit weg; ein Teil bis in den Himmel. Erscheint beim kompletten
-- Neustart (T) wieder. Attribute am Objekt (alle optional):
--   LaunchPower (Zahl), SpinPower (Zahl), SkyChance (0..1), Sound (Sound-Id),
--   DisplayName (Text, z. B. "Kuh"; sonst der Name des Objekts), ComicText (z. B. "MUUH!")
Config.Launch = {
	Power = 140, -- Schleuderkraft (Studs/s), Attribut "LaunchPower"
	SpinPower = 12, -- wilde Drehung (Radiant/s), Attribut "SpinPower"
	SkyChance = 0.25, -- Anteil, der bis in den Himmel fliegt, Attribut "SkyChance"
	SpeedCarry = 1, -- Anteil des Wagen-Tempos, den das Objekt mitnimmt
	UpRatio = 0.8, -- Schwung nach oben = Power * UpRatio
	Gravity = 50, -- Schwerkraft beim Flug (normal 196; kleiner = fliegt weiter)
	SkyUpRatio = 1.5, -- Himmelsflug: Schwung nach oben = Power * SkyUpRatio ...
	SkyAcceleration = 300, -- ... und wird so stark schneller (Studs/s^2)
	SkyTime = 2.5, -- nach so vielen Sekunden verschwindet es mit einem Stern-Blinken
	MaxFlightTime = 10, -- laengster normaler Flug (s)
	LandedTime = 2, -- so lange liegt es nach der Landung noch da (s)
	-- Treffer-Show
	HitStop = 0.15, -- Hit-Stop: so lange (s) steht alles kurz still
	HitSpeedKeep = 0.85, -- mit diesem Anteil des Tempos faehrt der Wagen weiter
	HitShake = 2.5, -- Kamera-Wackeln (Grad)
	ComicTexts = { "BONK!", "KAWUMM!", "ZONK!", "PLONK!", "WUMMS!", "KLONK!", "BOING!", "KRACH!" },
	-- Server-Pruefung: so weit (Studs) darf der Wagen weg sein (plus Groesse des Objekts) ...
	HitTolerance = 8,
	LatencyAllowance = 0.3, -- ... plus Tempo * diese Sekunden
	-- Kleiner Muenzbonus je nach Flugweite
	BonusPerMeter = 0.02, -- 100 m = 2 Muenzen
	MaxBonus = 10,
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

-- Erweiterter Baukasten (M2.5): Alle Bausteine darunter laufen auf dem Client des jeweiligen
-- Spielers (jeder hat seine eigene Version). Dauerbetrieb laeuft ueber die Serveruhr, damit
-- alle Spieler dasselbe sehen. Vorlagen (Steine, Autos ...) liegen in
-- ReplicatedStorage/<TemplatesFolder>; Rojo laesst diesen Ordner in Ruhe.
Config.Toolkit = {
	TemplatesFolder = "Templates",
	-- TriggerZone (Tag "TriggerZone", Attribut "Signal" = Name): Faehrt der eigene Wagen hinein,
	-- wird das Signal ausgeloest. Bausteine mit Attribut "ListenSignal" reagieren darauf.
	TriggerOnce = false, -- Standard fuer Attribut "Once" (nur einmal pro Lauf)
	TriggerCooldown = 2, -- Standard fuer Attribut "Cooldown" (s)
	TriggerMargin = 0.5, -- so viel (Studs) um die Zone herum zaehlt schon als "drin"
	-- Objekte ohne Hazard (Steine, Autos, Props, Hund) schubsen nur: so lange (s) nach der
	-- Beruehrung zaehlt ein harter Stoss nicht als Crash
	SoftHitGrace = 0.3,
}

-- Spawner (Tag "Spawner", Part): Objekte erscheinen an zufaelligen Stellen innerhalb des
-- Parts und bekommen Schwung in Richtung seiner Vorderseite. Standardwerte der Attribute:
Config.Spawner = {
	Template = "", -- Name der Vorlage in ReplicatedStorage/Templates, mehrere durch Komma
	Interval = 3, -- Sekunden zwischen zwei Ausloesungen (Dauerbetrieb)
	IntervalRandom = 1, -- zufaellig bis zu so viel spaeter
	Burst = 1, -- Anzahl Objekte pro Ausloesung
	Speed = 30, -- Schwung (Studs/s) in Richtung der Vorderseite
	SpeedRandom = 5, -- +/- so viel
	SpreadAngle = 10, -- Streuung der Richtung (Grad)
	Spin = 0, -- zufaellige Drehung (Radiant/s), z. B. 4 fuer Steine
	ScaleMin = 1, -- Attribut "ScaleRandom" (NumberRange, z. B. 0.8 - 1.3) ...
	ScaleMax = 1, -- ... oder Zahl x = 1-x .. 1+x
	Lifetime = 12, -- Sekunden, dann verschwindet das Objekt
	DespawnY = -100, -- unter dieser Hoehe verschwindet es auch
	MaxActive = 12, -- hoechstens so viele gleichzeitig (pro Spawner)
	ActiveRadius = 400, -- laeuft nur, wenn dein Wagen naeher ist (Dauerbetrieb)
	Hazard = false, -- true = Beruehrung ist ein Crash, false = nur Schubs
	HazardMessage = "Getroffen!", -- Attribut "Message"
	Kinematic = false, -- true = faehrt stur geradeaus, ohne Schwerkraft (z. B. Auto-Strom)
	PlaceholderSize = 3, -- Ersatz-Kugel, wenn die Vorlage fehlt
}

-- PathMover (Tag "PathMover", Modell oder Part): faehrt Wegpunkte ab. Die Wegpunkte sind
-- Parts "1", "2", "3" ... in einem Ordner "Waypoints" im Modell (im Spiel unsichtbar).
-- Der Pivot des Modells faehrt durch die Wegpunkte.
Config.PathMover = {
	Speed = 16, -- Studs/s
	Loop = false, -- true = Kreis (letzter Punkt -> erster), false = hin und zurueck
	WaitAtPoints = 0, -- Sekunden Pause an jedem Wegpunkt
	FaceDirection = true, -- Vorderseite (Pivot) zeigt in Fahrtrichtung (Autos, Hunde)
	TurnSpeed = 6, -- wie schnell es sich in die neue Richtung dreht
	-- Mit ListenSignal: wartet am ersten Punkt und faehrt pro Signal einen Durchgang
}

-- Gate (Tag "Gate", Modell oder Part): Schiebetor, Schranke, Klappbruecke. Bewegt sich um
-- seinen Pivot (Studio: Edit Pivot = Scharnier) um Offset und/oder Angle.
Config.Gate = {
	Offset = Vector3.new(0, 0, 0), -- Verschiebung im geoeffneten Zustand (relativ zum Pivot)
	Angle = 0, -- Drehung (Grad) im geoeffneten Zustand ...
	Axis = "X", -- ... um diese Achse des Pivots ("X", "Y" oder "Z")
	Duration = 2, -- Sekunden zum Oeffnen bzw. Schliessen
	OpenTime = 3, -- Taktbetrieb: so lange offen ...
	ClosedTime = 3, -- ... und so lange zu
	StartOpen = false, -- true = Grundzustand offen (oeffnen heisst dann schliessen)
	CloseAfter = 0, -- mit ListenSignal: nach so vielen Sekunden wieder zu (0 = bleibt offen)
}

-- Collapse (Tag "Collapse", Part oder Modell): Bruecke/Boden gibt kurz nach dem Befahren nach,
-- wackelt und stuerzt ab. Kommt bei R und T wieder.
Config.Collapse = {
	Delay = 0.8, -- Sekunden vom Befahren bis zum Absturz (in der Zeit wackelt es)
	Shake = 0.25, -- Wackeln (Studs), 0 = aus
	ShakeSpeed = 35, -- wie schnell es wackelt
	FallTime = 4, -- so lange (s) faellt das Stueck sichtbar, dann ist es weg
	FallSpin = 1.5, -- leichtes Drehen beim Fallen (Radiant/s)
}

-- Prop (Tag "Prop", Part oder Modell): lose Gegenstaende (Kisten, Pylonen, Marktstaende), die
-- der Wagen wegschiesst, ohne selbst zu crashen. Jeder Spieler hat seine eigenen (lokale
-- Kopien). Zurueck an den Ursprung nur bei T; bei R bleiben sie liegen.
Config.Props = {
	Density = 0.4, -- leicht, damit sie schoen fliegen (Attribut "Density"; Wasser = 1)
	KickBoost = 0.9, -- beim ersten Treffer: Anteil des Wagen-Tempos, den der Prop bekommt ...
	KickUp = 18, -- ... plus so viel nach oben (Studs/s)
}

-- ForceZone (Tag "ForceZone", Part = Bereich): drueckt den Wagen in Richtung der Vorderseite
-- (Wind, Wasserstrahl, Foerderband). Mit Pulse an/aus im Takt (Serveruhr, fuer alle gleich).
Config.ForceZone = {
	Strength = 60, -- Beschleunigung (Studs/s^2); zum Vergleich: Motor = Drive.PushAcceleration
	Pulse = 0, -- Takt in Sekunden (0 = immer an)
	PulseOn = 0.5, -- Anteil des Takts, in dem sie an ist (0..1)
	ActiveTime = 3, -- mit ListenSignal: so lange (s) an nach dem Signal
}

-- UpgradeDoor (Tag "UpgradeDoor", Part oder Modell): Abkuerzungs-Tuer. Oeffnet sich nur fuer
-- Spieler mit einem bestimmten Upgrade (Attribut "RequiredUpgrade" = Upgrade-Id aus
-- Config.Upgrades, z. B. "Spring"; "RequiredLevel" = Stufe). Sonst bleibt sie zu und ein
-- Schild sagt, welches Upgrade fehlt. Jeder Spieler sieht seinen eigenen Zustand.
Config.UpgradeDoor = {
	RequiredLevel = 1,
	OpenTime = 0.8, -- so lange (s) faehrt die Tuer nach unten weg
	SignDistance = 90, -- Schild ist bis zu diesem Abstand (Studs) sichtbar
}

-- Chaser (Tag "Chaser", Modell oder Part, z. B. ein Hund): rennt dir am Boden nach, sobald du
-- naeher als Radius kommst, gibt nach GiveUpTime auf und laeuft nach Hause. Jeder Spieler hat
-- seinen eigenen Hund. Pivot-Vorderseite = Laufrichtung.
Config.Chaser = {
	Radius = 40, -- ab diesem Abstand (Studs) geht die Jagd los
	MaxSpeed = 32, -- Hoechsttempo (Studs/s)
	Acceleration = 50, -- wie schnell er losrennt
	GiveUpTime = 6, -- Sekunden Jagd, dann gibt er auf
	ReturnSpeed = 14, -- Tempo auf dem Heimweg
	Cooldown = 3, -- Pause zu Hause, bevor er wieder jagt
	TurnSpeed = 8, -- wie schnell er sich in Laufrichtung dreht
	StopGap = 0.8, -- so viel Luft (Studs) laesst er zwischen sich und dem Wagen
	Hazard = false, -- true = Beruehrung ist ein Crash, false = nur Schubs
	HazardMessage = "Vom Hund erwischt!", -- Attribut "Message"
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
	Coin = { Id = "", Volume = 0.5 }, -- Muenze eingesammelt
	Ragdoll = { Id = "", Volume = 0.8 }, -- Figur fliegt aus dem Wagen (z. B. lustiger Schrei)
	GameOver = { Id = "", Volume = 0.8 },
	LifeLost = { Id = "", Volume = 0.6 },
	Shield = { Id = "", Volume = 0.7 }, -- Fahrradhelm faengt einen Crash ab
	Turbo = { Id = "", Volume = 0.7 }, -- Turbo-Pausenbrot (z. B. Mampf-Geraeusch)
	DoubleJump = { Id = "", Volume = 0.6 },
	Glide = { Id = "", Volume = 0.4 }, -- Fallschirm geht auf
	Purchase = { Id = "", Volume = 0.7 }, -- Kauf im Shop
	Launch = { Id = "", Volume = 0.8 }, -- Treffer (wenn das Objekt kein eigenes Attribut "Sound" hat)
	SkyStar = { Id = "", Volume = 0.6 }, -- Stern-Blinken, wenn ein Objekt im Himmel verschwindet
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
	{ label = "Leben pro Lauf", path = "Lives.PerRun", server = true }, -- gilt ab dem naechsten T
	{ label = "Geist-Durchsicht", path = "Ghost.Transparency", span = 0.4 }, -- 0.2 .. 1, ab dem naechsten Start
	{ label = "Schleuderkraft", path = "Launch.Power", server = true },
	{ label = "Schleuder-Drehung", path = "Launch.SpinPower", server = true },
	{ label = "Himmel-Chance (0..1)", path = "Launch.SkyChance", server = true, span = 0.25 },
	{ label = "Flug-Schwerkraft", path = "Launch.Gravity", server = true, min = 5 },
	{ label = "Hit-Stop (s)", path = "Launch.HitStop" },
	{ label = "Tempo nach Treffer", path = "Launch.HitSpeedKeep", span = 0.15 },
	{ label = "Flug-Bonus pro Meter", path = "Launch.BonusPerMeter", server = true },
	{ label = "Sprungfeder 1 (Tempo)", path = "Abilities.JumpSpeed1" },
	{ label = "Sprungfeder 2 (Tempo)", path = "Abilities.JumpSpeed2" },
	{ label = "Doppelsprung (Tempo)", path = "Abilities.DoubleJumpSpeed" },
	{ label = "Helm-Ladungen Stufe 1", path = "Abilities.HelmetCharges1", server = true },
	{ label = "Helm-Ladungen Stufe 2", path = "Abilities.HelmetCharges2", server = true },
	{ label = "Helm-Ladungen Stufe 3", path = "Abilities.HelmetCharges3", server = true },
	{ label = "Helm-Schutzzeit (s)", path = "Abilities.HelmetGrace" },
	{ label = "Turbo-Schub", path = "Abilities.TurboGain" },
	{ label = "Turbo-Dauer (s)", path = "Abilities.TurboDuration" },
	{ label = "Turbo-Abklingzeit 1 (s)", path = "Abilities.TurboCooldown1" },
	{ label = "Turbo-Abklingzeit 2 (s)", path = "Abilities.TurboCooldown2" },
	{ label = "Turbo-Abklingzeit 3 (s)", path = "Abilities.TurboCooldown3" },
	{ label = "Fallschirm: Falltempo", path = "Abilities.GlideFallSpeed" },
	{ label = "Fallschirm: Bremsen", path = "Abilities.GlideResponse" },
	{ label = "Fallschirm: Schub", path = "Abilities.GlideForwardAccel" },
	{ label = "Fallschirm: Lenken", path = "Abilities.GlideSteerRate" },
	{ label = "Ragdoll-Flug hoch", path = "Crash.RagdollUpSpeed" },
	{ label = "Ragdoll-Flug vorne", path = "Crash.RagdollForwardBoost" },
	{ label = "Ragdoll schwebt (0..1)", path = "Crash.RagdollFloat", span = 0.45 },
}

-- Fehlersuche (nur in Studio wirksam; im veroeffentlichten Spiel automatisch aus, siehe unten)
Config.Debug = {
	-- true = im Output melden, wenn ein Rad einen Bodenbaustein erkennt und welcher
	-- Effekt (BoostPad, JumpPad) ausgeloest wird
	TrackPieces = false,
	-- true = alle Upgrades auf hoechster Stufe (nur in Studio), zum Testen ohne Shop
	AllUpgrades = false,
	-- true = Baukasten meldet im Output, welche Signale ausgeloest werden und wer reagiert
	Toolkit = false,
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
	RestartDelay = 2.2, -- so lange den Crash zeigen (Figur fliegt), dann Neustart (R ueberspringt das)
	-- Selbst verursachte Tempo-Spruenge (BoostPad, JumpPad, Drift-Boost, Hopp) sind kein Aufprall.
	-- Danach ist die Aufprall-Erkennung so lange (s) um diesen Faktor toleranter:
	SelfImpulseGrace = 0.3,
	SelfImpulseTolerance = 2,

	-- Ragdoll: Bei einem Crash fliegt die Figur schlaff und voellig uebertrieben aus dem Wagen.
	Ragdoll = true, -- false = Figur bleibt im Wagen sitzen
	RagdollCarry = 1.2, -- Anteil des Wagen-Tempos, den die Figur mitnimmt
	RagdollForwardBoost = 45, -- zusaetzlicher Schwung in Fahrtrichtung (Studs/s)
	RagdollUpSpeed = 80, -- Schwung nach oben (Studs/s)
	RagdollSpin = 14, -- zufaelliges Drehen (Radiant/s), fuer mehr Slapstick
	RagdollFloat = 0.45, -- so viel der Schwerkraft wird beim Flug aufgehoben (0..1): fliegt weiter
	RagdollTrail = true, -- Luftspur hinter der fliegenden Figur
	RagdollJointAngle = 60, -- wie weit Arme, Beine und Kopf schlackern duerfen (Grad)
	ServerRestartTimeout = 4, -- Sicherheitsnetz: so lange (s) nach dem Crash startet der Server selbst neu
}

-- Leben ("Crashen macht Spass"): pro Lauf, Anzeige als kleine Schulranzen.
-- Jeder Crash und jeder Treffer (Launchable) kostet eins; der Fahrradhelm faengt eins ab.
-- Kompletter Neustart (T) fuellt die Leben wieder auf.
Config.Lives = {
	PerRun = 5,
	GameOverTime = 4.5, -- so lange (s) den Game-Over-Screen zeigen, dann kompletter Neustart (T: sofort)
	-- Zufaellig gewaehlte Texte fuer den Game-Over-Screen
	GameOverTitles = { "NACHSITZEN!", "ZU SPAET!", "DER BUS IST WEG!", "AB INS SEKRETARIAT!" },
	GameOverTexts = {
		"Der Hausmeister hat dich mit der Schubkarre eingesammelt.",
		"Die Lehrerin schreibt schon einen Brief an deine Eltern.",
		"Dein Einkaufswagen braucht jetzt erst mal Urlaub.",
		"Morgen einfach eine Stunde frueher aufstehen?",
		"Die Kuh hat sich beim Rektor beschwert.",
	},
}

-- Abilities (ueber Upgrades im Shop freischaltbar). Werte pro Stufe heissen Name1, Name2 ...
-- Neue Ability: Modul in src/client/Abilities (siehe AbilityTypes), Eintrag in
-- Config.Upgrades und ihre Werte hier.
Config.Abilities = {
	-- Trampolin-Sprungfeder (Upgrade "Spring"): Leertaste / Gamepad A.
	-- Ohne Upgrade gibt es den kleinen Hopp (Config.Hop.Speed).
	JumpSpeed1 = 60, -- Stufe 1: Sprung-Tempo nach oben (Studs/s); Hoehe ~ Tempo^2 / 392 -> ca. 9 Studs
	JumpSpeed2 = 60, -- Stufe 2: gleicher Sprung ...
	DoubleJumpSpeed = 55, -- ... plus Doppelsprung: Leertaste in der Luft (Tempo nach oben)

	-- Fahrradhelm (Upgrade "Helmet"): so viele Ladungen pro Stufe (jede faengt einen
	-- Crash/Treffer ab, laedt sich am naechsten Checkpoint wieder auf)
	HelmetCharges1 = 1,
	HelmetCharges2 = 2,
	HelmetCharges3 = 3,
	HelmetGrace = 1.0, -- nach einer Helm-Rettung so lange (s) keine neuen Crashs

	-- Turbo-Pausenbrot (Upgrade "Turbo"): Taste F / Gamepad RB
	TurboGain = 40, -- Tempo-Zuwachs (Studs/s)
	TurboDuration = 0.7, -- ueber so viele Sekunden verteilt
	TurboCooldown1 = 12, -- Abklingzeit (s) pro Stufe
	TurboCooldown2 = 8,
	TurboCooldown3 = 5,

	-- Rucksack-Fallschirm (Upgrade "Glider"): Leertaste in der Luft halten
	GlideFallSpeed = 10, -- so schnell (Studs/s) faellt man hoechstens
	GlideResponse = 6, -- wie schnell das Fallen auf GlideFallSpeed gebremst wird
	GlideForwardAccel = 15, -- leichter Schub nach vorne (Studs/s^2) ...
	GlideMaxSpeed = 110, -- ... bis zu diesem Tempo
	GlideSteerRate = 1.2, -- Lenken in der Luft (Radiant/s)
}

-- Upgrades im Shop (Taste B). Pro Stufe: Preis und Beschreibung. In Beschreibungen werden
-- Platzhalter wie {Abilities.TurboCooldown2} durch den Config-Wert ersetzt.
Config.Upgrades = {
	{
		id = "Spring",
		name = "Trampolin-Sprungfeder",
		levels = {
			{
				price = 60,
				description = "Leertaste macht einen richtigen Sprung statt nur einen Hopp - ueber Hindernisse und auf neue Wege.",
			},
			{ price = 180, description = "Doppelsprung: in der Luft nochmal Leertaste druecken." },
		},
	},
	{
		id = "Helmet",
		name = "Fahrradhelm",
		levels = {
			{
				price = 50,
				description = "Faengt {Abilities.HelmetCharges1} Crash ab (kein Leben weg). Laedt sich am naechsten Checkpoint wieder auf.",
			},
			{ price = 150, description = "{Abilities.HelmetCharges2} Ladungen pro Checkpoint." },
			{ price = 350, description = "{Abilities.HelmetCharges3} Ladungen pro Checkpoint." },
		},
	},
	{
		id = "Turbo",
		name = "Turbo-Pausenbrot",
		levels = {
			{
				price = 80,
				description = "Taste F (Gamepad RB): kurzer Schub nach vorne. Abklingzeit {Abilities.TurboCooldown1} s.",
			},
			{ price = 200, description = "Abklingzeit nur noch {Abilities.TurboCooldown2} s." },
			{ price = 400, description = "Abklingzeit nur noch {Abilities.TurboCooldown3} s." },
		},
	},
	{
		id = "Glider",
		name = "Rucksack-Fallschirm",
		levels = {
			{
				price = 150,
				description = "Leertaste in der Luft halten: langsamer fallen und weiter fliegen.",
			},
		},
	},
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

	-- Bestzeiten: pro Spieler und Track im Spielstand (siehe Config.Save).
	-- Welcher Track: Attribut "TrackId" (Text) an der StartZone, sonst DefaultTrackId.
	DefaultTrackId = "Track1",
}

-- Strecken. Jede Strecke ist in Studio ein Model mit Attribut "TrackId" (Text); StartZone,
-- FinishZone und Checkpoints liegen darin. Hier stehen Name und Freischalt-Bedingung:
--   unlock = nil:                          von Anfang an frei
--   unlock = { track = "Track1", grade = 4 }: Note 4 oder besser auf Track1
--   unlock = { price = 300 }:               im Menue fuer Muenzen freischalten
--   beides zusammen:                        was zuerst erfuellt ist
-- Strecken, die hier fehlen, sind frei (Name: Attribut "TrackName" am Model oder die Id).
-- Strecken, die es in der Welt nicht gibt, erscheinen nicht im Menue.
Config.Tracks = {
	{ id = "Track1", name = "Der Schulweg" },
	{ id = "Track2", name = "Die Abkuerzung", unlock = { track = "Track1", grade = 4, price = 250 } },
	{ id = "Track3", name = "Ueber den Berg", unlock = { track = "Track2", grade = 5 } },
}

-- Geist vom besten Lauf: Der Server zeichnet jeden Lauf auf. Ist er eine neue Bestzeit, wird
-- er gespeichert (eigener DataStore) und beim naechsten Lauf als halbdurchsichtiger Wagen
-- abgespielt. In den Einstellungen abschaltbar.
Config.Ghost = {
	Enabled = true, -- Standard fuer die Einstellung "Geist"
	SampleInterval = 0.1, -- alle x Sekunden eine Aufnahme (kleiner = genauer, groesser = weniger Daten)
	MaxDuration = 600, -- laengere Laeufe (s) werden nicht als Geist gespeichert
	StoreName = "Ghosts_v1", -- DataStore fuer die Geister (aendern = alle Geister neu)
	Transparency = 0.6,
	Color = Color3.fromRGB(150, 220, 255),
}

-- Spielstand (DataStore): Muenzen, Upgrades, Bestzeiten, freigeschaltete Tracks ...
Config.Save = {
	Enabled = true, -- false = nur im Arbeitsspeicher (nichts wird dauerhaft gespeichert)
	StoreName = "PlayerData_v1", -- Name des DataStores (aendern = alle Spielstaende neu)
	LegacyBestTimesStore = "BestTimes_v1", -- alte Bestzeiten (vor M3) werden einmalig uebernommen
	Retries = 4, -- so oft wird Laden/Speichern bei Fehlern versucht
	RetryDelay = 1, -- Wartezeit (s) vor dem 2. Versuch, verdoppelt sich jedes Mal
	AutosaveInterval = 60, -- alle x Sekunden speichern, was sich geaendert hat
	-- Sitzungs-Sperre (schneller Serverwechsel): so lange (s) gilt eine Sperre ohne Speichern
	-- als aktiv; ein neuer Server versucht es so oft, mit dieser Pause (s), dann uebernimmt er
	LockTimeout = 150,
	LockAttempts = 6,
	LockRetryDelay = 4,
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

-- Sicherheit: Debug-Schalter wirken nur in Studio. Im veroeffentlichten Spiel werden sie hier
-- automatisch ausgeschaltet, egal was oben steht - so geht nichts versehentlich live.
-- ((game :: any) ~= nil: ausserhalb von Roblox, z. B. in automatischen Tests, gibt es kein game)
if (game :: any) ~= nil and not game:GetService("RunService"):IsStudio() then
	local debugFlags: any = Config.Debug
	for key in debugFlags do
		debugFlags[key] = false
	end
end

return Config
