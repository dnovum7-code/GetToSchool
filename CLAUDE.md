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

## Aktueller Meilenstein
M2 – Erster Track: Baukasten aus getaggten Bausteinen (siehe README „Baukasten“),
Timer (0:00.00) mit Bestzeit pro Track (DataStore), Zwischenzeiten an Checkpoints und
Schulnote 1–6 (Grenzen in Sekunden an der FinishZone), Checkpoints (R/T),
Streckenbausteine, bewegte Hindernisse, Zufallsereignisse, Sound-Grundlage.
Bausteine lesen Parameter aus Attributen, Standardwerte aus der Config.
Nach dem ersten Test überarbeitet: Drift (Front zieht, Heck schwingt, kein Dreher),
Hopp, schwächere normale Lenkung, mehr Tempo auf flachem Boden, kein Bremsen bergab.
Geplant (M2.5): erweiterter Baukasten, wartet auf OK zum Vorschlag Client/Server.
(Erledigt: M1 – Fahrgefühl-Grundlage. M1.5 – Aus-/Einsteigen, Drift mit Boost,
Ragdoll-Crash, Tacho, Kamera-Wackeln, Tuning-Panel; M1.5 noch nicht getestet/getunt.)

## Steuerung
| Aktion | Tastatur | Gamepad | Touch |
|---|---|---|---|
| Anschieben / Bremsen, rückwärts | W / S (Pfeil hoch/runter) | – | – |
| Lenken | A / D (Pfeil links/rechts) | – | – |
| Aussteigen (im Wagen) | E | X | Button „Raus“ |
| Einsteigen (am eigenen leeren Wagen) | E | X | Hinweis antippen |
| Zurück zum letzten Checkpoint (auch nach Crash, überspringt Wartezeit; ohne Checkpoint: Start) | R | Y | Button „R“ |
| Kompletter Neustart am Start (Zeit wieder 0) | T | Steuerkreuz hoch | Button „Start“ |
| Tuning-Panel (nur Studio) | F2 | – | – |
| Hopp (antippen) / Drift (halten, loslassen = Boost) | Shift | B | Button „Drift“ |
| Sprung / Doublejump | Leertaste (reserviert, kommt später) | A | – |
