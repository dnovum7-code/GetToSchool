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

## Aktueller Meilenstein
M1.5 – Fahrgefühl ausbauen: Aus-/Einsteigen, Drift mit Boost, lustiger
Ragdoll-Crash, Tacho und Kamera-Wackeln, Tuning-Panel (nur Studio).
(Erledigt: M1 – Wagen fährt den Test-Hügel runter, steuerbar, Crash-Erkennung,
sofortiger Neustart, Ziel beendet den Lauf mit Zeit.)

## Steuerung
| Aktion | Tastatur | Gamepad | Touch |
|---|---|---|---|
| Anschieben / Bremsen, rückwärts | W / S (Pfeil hoch/runter) | – | – |
| Lenken | A / D (Pfeil links/rechts) | – | – |
| Aussteigen (im Wagen) | E | X | Button „Raus“ |
| Einsteigen (am eigenen leeren Wagen) | E | X | Hinweis antippen |
| Neustart (auch nach Crash, überspringt Wartezeit) | R | Y | Button „R“ |
| Tuning-Panel (nur Studio) | F2 | – | – |
| Drift / Handbremse (halten, loslassen = Boost) | Shift | B | Button „Drift“ |
| Sprung / Doublejump | Leertaste (reserviert, kommt später) | A | – |
