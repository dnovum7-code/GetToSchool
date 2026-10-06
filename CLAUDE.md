# Get to School (Arbeitstitel)

## Spielidee
Roblox-Spiel: Der Spieler ist zu spät für die Schule und fährt in einem
dummen Fahrzeug (Start: Einkaufswagen) einen Hügel hinunter ins Dorf zur Schule.
Hindernisse, mehrere Wege, Zufallsereignisse. Schwer, aber mit Upgrades und
Abilities (Doublejump, Schild, Boost, Wurf-Items) gut schaffbar.

## Design-Prinzipien
- Fahrgefühl hat oberste Priorität: witzig, wackelig, aber kontrollierbar.
- Kein Frust beim Wiederholen: sofortiger Neustart (< 1 s), Checkpoints,
  jeder Versuch bringt Münzen.
- Upgrades öffnen neue Wege, nicht nur bessere Zahlen.
- Lenkung (so gewollt, nicht zurückbauen): Drift ist der Standard-Fahrmodus – A/D lenkt
  direkt im Drift (Front zieht, Heck schwingt aus, Boost am Drift-Ende). Shift gehalten =
  normale, ruhigere Lenkung (ca. 60 %, fester Seitenhalt). Config.Drift.DriftByDefault = true.

## Technik
- Sprache: Luau (strict mode wo sinnvoll)
- Sync: Rojo, Projektdatei default.project.json
- Struktur:
  - src/server  -> ServerScriptService
  - src/client  -> StarterPlayer/StarterPlayerScripts
  - src/shared  -> ReplicatedStorage/Shared
- Server ist autoritativ für Fortschritt, Münzen und Upgrades.
  Client für Eingabe, Kamera und UI. Kommunikation über RemoteEvents,
  Eingaben vom Client immer auf dem Server prüfen.
- Werte zum Tunen (Tempo, Lenkung, Sprungkraft) in einer zentralen
  Config-Datei in src/shared, nicht im Code verstreut.

## Arbeitsweise
- Ich baue Welt und Strecken selbst in Roblox Studio und teste dort.
- Du schreibst die Skripte. Kleine, testbare Schritte.
- Nach jeder Änderung kurz erklären, was ich in Studio testen soll.
- Keine Gratis-Modelle aus der Toolbox voraussetzen.
- Commits nach jedem funktionierenden Schritt.
- Git: Nur der Branch main. Keine eigenen Branches, direkt auf main
  committen und pushen. Vor jeder Aufgabe git pull.
- Tuning: Ich stelle Werte im Tuning-Panel ein (Studio, F2; Mitte = Config-Wert,
  Bereich 0 bis doppelt) und schicke dir die Ausgabe von „Werte kopieren“
  (Zeilen „Abschnitt.Name: alt -> neu“). Du trägst die neuen Werte in
  src/shared/Config.luau ein, committest und pushst. Welche Regler es gibt:
  Config.TuningPanel. Fehlersuche bei Bodenbausteinen: Config.Debug.TrackPieces.

## Aktueller Meilenstein
M5 – Spaß-Extras (in Arbeit; Reihenfolge: Lufttricks, Kuh-Kombo, tägliches Glücksrad,
visuelle Extras; noch nicht in Studio getestet):
- Lufttricks: Q/E in der Luft (Gamepad LB, Touch „Trick“) drehen um die Hochachse;
  Logik Progression/TrickMath, Client src/client/Tricks (Drehmoment nach der Fahrphysik,
  Landung bewerten, Landehilfe), Server src/server/Tricks (Münzen, Spam-Schutz),
  Crash-Grund BadLanding. Werte: Config.Tricks.
- Kuh-Kombo: Treffer innerhalb Config.Combo.Window erhöhen den Multiplikator (Server in
  server/Launchables, Logik Progression/Combo), Bonus = Flugbonus × Multiplikator +
  StepBonus pro Stufe; Anzeige src/client/ComboUI. Erfolge „Kuh-Lawine“, „Wirbelwind“.
- Glücksrad: einmal pro Tag (Tageswechsel wie Hausaufgaben), Config.DailySpin (Felder,
  Gewichte, Items), Server würfelt (server/DailySpin, Shop-Anfrage "Spin"), Reiter
  „Gluecksrad“ (src/client/SpinUI). Powerups (Extra-Leben, Ersatz-Helm, Start-Turbo) werden
  beim Start des nächsten Laufs verbraucht (PlayerEvents "RunStarted",
  RaceManager.addRunBonus). Spielstand: spinDay, items. Debug.FreeSpins zum Testen.
- Visuelle Extras: src/client/VisualFX (Speed-Linien, Landestaub, Boost-Flammen, Konfetti),
  Werte Config.Effects, Einstellung „Extra-Effekte“ (settings.VisualEffects).
M4 – Wiederspielwert (gebaut, noch nicht in Studio getestet; Testliste im README
„Wichtigste Studio-Tests M4“):
- Geist vom besten Lauf: Server zeichnet jeden Lauf auf (src/server/Ghosts, kompakt mit
  src/shared/Progression/GhostCodec), speichert bei neuer Bestzeit (eigener DataStore
  Config.Ghost.StoreName, Schlüssel pro Spieler und Strecke), Client spielt ihn ab dem Start
  halbdurchsichtig ab (src/client/GhostClient). Abschaltbar über src/client/Settings ("Ghost").
- Bestenlisten: OrderedDataStore pro Strecke + „Weitester Kuh-Wurf“ (src/server/Leaderboards,
  Config.Leaderboard; in Studio eigene Listen mit Suffix, ohne API im Arbeitsspeicher).
  Ansichten Global / Server / Freunde, Reiter „Bestenliste“ im Menü, Bretter in der Welt
  (Tag Leaderboard). Plausibilität vor dem globalen Eintrag (src/shared/Progression/
  RunValidation): Mindestzeit (Config.Tracks minTime), alle Checkpoints (gleiche Order =
  alternative Wege, Optional = true, in RandomEvent = optional), Reihenfolge, Mindestzeit
  zwischen Checkpoints, Höchsttempo pro Abschnitt (Luftlinie). Unplausibel = nur persönlich.
- Menü: Reiter melden sich mit ShopUI.addTab an (eigene Module zeichnen mit ShopUI.card ...).
- Hausaufgaben: 3 tägliche Aufgaben (Config.Homework, Wechsel ResetHourUtc), Logik in
  src/shared/Progression/Homework (fest ausgewürfelt nach Tag + Spieler), Server verbucht
  Launch/Coins/Finish/Drift (Drift meldet der Client über ReportStat, Server begrenzt auf die
  echte Zeit), Belohnung sofort + Bonus für alle. Spielstand Version 2 (Feld homework).
- Fahrzeuge: Config.Vehicles (Einkaufswagen, Bürostuhl, Schultisch auf Skateboard), Werte
  = Einkaufswagen + `set` (fest) / `scale` (Faktor), siehe src/shared/Vehicles und
  Progression/VehicleStats. Wagen trägt Attribut VehicleId; Fahrwerte immer über
  Vehicles.forCart(cart) bzw. controller.stats lesen, nicht direkt Config.Drive.
  Garage (Reiter, server/Garage), eigene Modelle in ReplicatedStorage/VehicleModels/<Id>.
- Kosmetik: Config.Cosmetics (Farben pro Fahrzeug, Spuren), Reiter „Lackiererei“,
  server/Cosmetics wendet sie per CartBuilder.applyLook an (Parts mit Attribut Paint).
- Ereignisse: server/PlayerEvents verteilt Finish/Launch/Coins/Drift/HomeworkDone/
  VehicleBought an Hausaufgaben und Erfolge (neue Abnehmer mit PlayerEvents.on).
- Erfolge: Config.Achievements (Liste, Badge-Ids, 0 = kein Badge), Logik in
  Progression/Achievements, server/Achievements (Popup über Progress-Remote "Achievement"),
  Reiter „Erfolge“. Spielstand: achievements, stats.driftSeconds.
- Einstellungen: Reiter „Einstellungen“ (Musik/Effekte über SoundGroups, Kamera-Wackeln,
  Geist, Steuerungstabelle), gespeichert im Spielstand (settings, server/PlayerSettings,
  Remote "Settings"). Einstieg: einmalige Hinweise (src/client/Onboarding, hintsSeen,
  Config.Onboarding, Debug.ShowHintsAlways). Steuerungstexte je Gerät: src/client/ControlsInfo.
- Eingabe: Gamepad (RT/LT, Stick) und Touch-Joystick über das Roblox-Steuermodul
  (CartClient readInput, Config.Input). Vorher ging Fahren nur mit Tastatur.
M3 – Progression (gebaut, noch nicht in Studio getestet):
- Münzen: Baustein `Coin`, Server prüft das Einsammeln (Abstand), Zielbelohnung
  (Grundbetrag + Notenbonus), Münzen bleiben nach Crash/Abbruch. Eingesammelte Münzen erscheinen
  erst wieder, wenn das Ziel der Strecke erreicht ist (nicht bei T, gegen Farmen).
- Debug-Schalter (Config.Debug) wirken nur in Studio, live automatisch aus.
- Speichern: versionierter Spielstand (src/shared/Progression/SaveData), Retry, kein
  Überschreiben nach Ladefehler, Ersatz im Arbeitsspeicher in Studio ohne API-Zugriff.
- Leben: 5 pro Lauf (Schulranzen), Crash/Treffer kostet eins, Game Over → Neustart.
  R/Crash ohne Checkpoint: zurück zum Start, Lauf (Zeit, Leben) läuft weiter.
- Launchables (Kuh & Co.): Treffer kostet Leben, Wagen fährt weiter, Objekt fliegt
  (Server plant den Flug), Comic-Text, Hit-Stop, Flugweite, Rekorde, kleiner Bonus.
- Abilities (src/client/Abilities, ein Modul pro Ability): Trampolin-Sprungfeder (Sprung,
  Doppelsprung), Fahrradhelm (Ladungen, lädt am Checkpoint), Turbo-Pausenbrot (F),
  Rucksack-Fallschirm (Leertaste in der Luft halten).
- Shop „Pausen-Kiosk“ (B): Upgrades mit Stufen (Config.Upgrades), Strecken, Rekorde.
- Mehrere Tracks: Model mit Attribut TrackId, Bedingungen in Config.Tracks.
- Automatische Tests mit Lune: `lune run tests/run` (reine Logik in src/shared/Progression).
M2.5 – Erweiterter Baukasten (gebaut, noch nicht in Studio getestet):
- Neue Tags: TriggerZone, Spawner, PathMover, Gate, Collapse, Prop, ForceZone, Chaser,
  UpgradeDoor (Abkürzungs-Tür, öffnet nur mit RequiredUpgrade/RequiredLevel)
  (Attribute und Beispiele im README „Erweiterter Baukasten“).
- Alle laufen auf dem Client des jeweiligen Spielers (src/client/Toolkit, eigene Version pro
  Spieler); Dauerbetrieb über Serveruhr + reproduzierbaren Zufall (PieceId vom Server), damit
  alle dasselbe sehen. Reine Logik in src/shared/Toolkit mit Lune-Tests.
- Trigger-System: TriggerZone (Attribut Signal, Once, Cooldown) löst ein Signal aus, wenn der
  eigene Wagen hineinfährt. Bausteine mit Attribut ListenSignal reagieren nur darauf (Spawner =
  Burst, PathMover = ein Durchgang, Gate = öffnet, Collapse = stürzt ein, ForceZone = an,
  Chaser = jagt). Signale gelten nur beim jeweiligen Spieler.
- Reset: T = alles auf Anfang; R/Crash = gespawnte Objekte weg, Collapse steht wieder,
  Trigger scharf, Signal-Tore zu, Hunde zu Hause; Props und Chaos-Zähler bleiben.
- Vorlagen: ReplicatedStorage/Templates (in Studio angelegt, Rojo ignoriert ihn).
- Bau-Hilfe: Studio-Plugin (plugin/), Installation im README.
- Test-Place: `rojo build test.project.json -o TestPlace.rbxl` (Teststrecke mit allen
  Bausteinen, Testfläche, Vorlagen). Erzeugt mit `lune run tools/build_testplace` – nach
  Änderungen am Projekt (z. B. neue Remotes) neu erzeugen; tests/ProjectSpec prüft das.
(Erledigt: M1 – Fahrgefühl. M1.5 – Aus-/Einsteigen, Drift mit Boost, Ragdoll, Tacho,
Kamera-Wackeln, Tuning-Panel. M2 – Erster Track: Baukasten, Timer mit Bestzeit, Noten,
Checkpoints, Hindernisse, Zufallsereignisse, Sound; drei Feedback-Runden: Drift ist der
Standard-Fahrmodus (Shift = normal), Hopp, Boost beim Drift-Ende.)

## Später
- M5 – Spaß-Extras (nach M4): Lufttricks (Q/E in der Luft drehen, Münzen bei sauberer
  Landung, Crash bei schiefer Landung; E am Boden bleibt Aussteigen), Kuh-Kombo
  (Multiplikator für Bonus-Münzen, große Anzeige „3x KOMBO!“), tägliches Glücksrad
  (Items/Powerups), weitere visuelle Effekte. Alle Werte in die Config, wichtige ins
  Tuning-Panel.

## Steuerung
| Aktion | Tastatur | Gamepad | Touch |
|---|---|---|---|
| Anschieben / Bremsen, rückwärts | W / S (Pfeil hoch/runter) | RT / LT (oder linker Stick vor/zurück) | Joystick vor/zurück |
| Lenken | A / D (Pfeil links/rechts) | Linker Stick | Joystick links/rechts |
| Aussteigen (im Wagen) | E | X | Button „Raus“ |
| Einsteigen (am eigenen leeren Wagen) | E | X | Hinweis antippen |
| Zurück zum letzten Checkpoint (auch nach Crash, überspringt Wartezeit; ohne Checkpoint: Start, Lauf läuft weiter) | R | Y | Button „R“ |
| Kompletter Neustart am Start (Zeit 0, Leben voll, Objekte wieder da – Münzen erst nach dem Ziel; auch während Game Over) | T | Steuerkreuz hoch | Button „Start“ |
| Tuning-Panel (nur Studio) | F2 | – | – |
| Normal fahren (halten; Standard ist Drift, Boost kommt am Drift-Ende oder beim Drücken) | Shift | B | Button „Normal“ |
| Hopp (kleiner Sprung, schneller Richtungswechsel); mit Sprungfeder: Sprung, in der Luft nochmal = Doppelsprung | Leertaste | A | Button „Hopp“ |
| Fallschirm (Upgrade): in der Luft halten | Leertaste halten | A halten | Button „Hopp“ halten |
| Turbo-Pausenbrot (Upgrade) | F | RB | Button „Turbo“ |
| Lufttrick: in der Luft drehen (sauber landen = Münzen, schief = Crash) | Q / E (E nur in der Luft, am Boden Aussteigen) | LB (Richtung vom Stick) | Button „Trick“ |
| Menü „Pausen-Kiosk“ (Shop, Strecken, Rekorde, Bestenliste, Hausaufgaben, Garage, Lackiererei, Erfolge, Einstellungen; nur außerhalb eines Laufs) | B | Select | Button „Shop“ |
