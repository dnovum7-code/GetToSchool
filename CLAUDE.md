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
In Arbeit (M2.5, OK erhalten): erweiterter Baukasten. Alle dynamischen Bausteine laufen
auf dem Client des jeweiligen Spielers (eigene Version pro Spieler, Dauerbetrieb über die
Serveruhr synchron), Vorlagen in ReplicatedStorage/Templates, Bau-Hilfe als Studio-Plugin.
(Erledigt: M1 – Fahrgefühl. M1.5 – Aus-/Einsteigen, Drift mit Boost, Ragdoll, Tacho,
Kamera-Wackeln, Tuning-Panel. M2 – Erster Track: Baukasten, Timer mit Bestzeit, Noten,
Checkpoints, Hindernisse, Zufallsereignisse, Sound; drei Feedback-Runden: Drift ist der
Standard-Fahrmodus (Shift = normal), Hopp, Boost beim Drift-Ende.)

## Später
- M4 – Wiederspielwert (nach M2.5, Reihenfolge einhalten): Geist vom besten Lauf, globale
  Bestenlisten, Hausaufgaben (tägliche Aufgaben), Fahrzeuge (Garage), Kosmetik, Erfolge
  (Badge-IDs vorbereiten), Einstellungen und Einstieg. Jeweils Lune-Tests für die Logik.
- Globale Bestenlisten: Weil Hindernisse auf dem Client laufen, prüft der Server jede Zeit,
  bevor sie in die globale Bestenliste kommt: alle Checkpoints in der richtigen Reihenfolge
  durchfahren, Mindestzeit pro Track, Mindestzeit zwischen Checkpoints (Werte in der Config).
  Unplausible Zeiten zählen nur persönlich, nicht global.

## Steuerung
| Aktion | Tastatur | Gamepad | Touch |
|---|---|---|---|
| Anschieben / Bremsen, rückwärts | W / S (Pfeil hoch/runter) | – | – |
| Lenken | A / D (Pfeil links/rechts) | – | – |
| Aussteigen (im Wagen) | E | X | Button „Raus“ |
| Einsteigen (am eigenen leeren Wagen) | E | X | Hinweis antippen |
| Zurück zum letzten Checkpoint (auch nach Crash, überspringt Wartezeit; ohne Checkpoint: Start, Lauf läuft weiter) | R | Y | Button „R“ |
| Kompletter Neustart am Start (Zeit 0, Leben voll, Objekte wieder da – Münzen erst nach dem Ziel; auch während Game Over) | T | Steuerkreuz hoch | Button „Start“ |
| Tuning-Panel (nur Studio) | F2 | – | – |
| Normal fahren (halten; Standard ist Drift, Boost kommt am Drift-Ende oder beim Drücken) | Shift | B | Button „Normal“ |
| Hopp (kleiner Sprung, schneller Richtungswechsel); mit Sprungfeder: Sprung, in der Luft nochmal = Doppelsprung | Leertaste | A | Button „Hopp“ |
| Fallschirm (Upgrade): in der Luft halten | Leertaste halten | A halten | Button „Hopp“ halten |
| Turbo-Pausenbrot (Upgrade) | F | RB | Button „Turbo“ |
| Menü „Pausen-Kiosk“ (Shop, Strecken, Rekorde; nur außerhalb eines Laufs) | B | Select | Button „Shop“ |
