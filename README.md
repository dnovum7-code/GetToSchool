# Get to School

Roblox-Spiel (Luau + Rojo). Spielidee, Technik und Arbeitsweise: siehe [CLAUDE.md](CLAUDE.md).

## Einrichtung (einmalig)

Du brauchst: **git**, **Rokit** (Werkzeug-Manager), darüber **Rojo**, und **Roblox Studio**.

1. **git** prüfen: `git --version`. Falls es fehlt: https://git-scm.com/downloads
2. **Rokit** installieren
   - Windows (PowerShell):
     ```powershell
     Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
     ```
   - macOS / Linux:
     ```bash
     curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
     ```
   - Danach das Terminal **neu öffnen** und `rokit --version` testen.
3. Im Projektordner die Werkzeuge aus `rokit.toml` installieren:
   ```bash
   rokit install
   rojo --version   # sollte 7.7.1 zeigen
   ```
4. Rojo-Plugin für Studio installieren: `rojo plugin install` (Studio danach neu starten).
   Alternativ: Plugin "Rojo" im Creator Store.

## Arbeiten mit Studio

1. Im Projektordner `rojo serve` starten (läuft weiter, Fenster offen lassen).
2. In Studio deinen Place öffnen → Reiter **Plugins** → **Rojo** → **Connect**.
3. Rojo spiegelt jetzt live:
   - `src/server` → `ServerScriptService/Server`
   - `src/client` → `StarterPlayer/StarterPlayerScripts/Client`
   - `src/shared` → `ReplicatedStorage/Shared`
   - plus `ReplicatedStorage/Remotes` (RemoteEvents)
4. Die **Welt** (Hügel, Dorf, Zonen) baust du direkt in Studio. Rojo fasst sie nicht an.
   Speichern: *File → Publish to Roblox* (Versionsverlauf in der Cloud). Place-Dateien
   (`*.rbxl`) im Projekt-Hauptordner werden von git ignoriert.

Unity-Vergleich: Rojo ist wie ein "Live-Import" deiner Skripte aus dem Dateisystem in die
Szene. Bearbeite Skripte nur in den Dateien, nicht in Studio, sonst überschreibt Rojo sie.

## Optional: Code-Qualität

```bash
stylua src        # formatiert den Code
selene src        # Linter (findet typische Fehler)
```

## Code-Überblick (Meilenstein M1)

| Datei | Läuft auf | Aufgabe |
|---|---|---|
| `src/shared/Config.luau` | beiden | **Alle Tuning-Werte** (Tempo, Lenkung, Kamera, Crash, Rennen) |
| `src/server/GameServer.server.luau` | Server | Einstieg: verbindet Spieler, Wagen, Rennen |
| `src/server/CartBuilder.luau` | Server | baut den Einkaufswagen aus Parts |
| `src/server/CartManager.luau` | Server | Wagen pro Spieler, hineinsetzen, Physik an Client geben, Zurücksetzen |
| `src/server/Track.luau` | Server | Start-/Zielzone finden, Startposition, „ist in Zone?“ |
| `src/server/RaceManager.luau` | Server | Rennablauf und Zeitmessung (autoritativ) |
| `src/client/CartClient.client.luau` | Client | Einstieg: Eingabe, Neustart-Taste, Ereignisse vom Server |
| `src/client/CartController.luau` | Client | Fahrphysik (Kraft + Drehmoment) |
| `src/client/ChaseCamera.luau` | Client | Verfolgerkamera |
| `src/client/CrashDetector.luau` | Client | Crash-Erkennung |
| `src/client/RaceUI.luau` | Client | Anzeige (Zeit, Tacho, CRASH!/ZIEL!) |
| `src/client/EnterPrompt.luau` | Client | Hinweis „E Einsteigen“ am eigenen leeren Wagen |
| `src/client/OwnCart.luau` | Client | Helfer: eigenen Wagen finden, Bewegung stoppen |
| `src/client/DevPanel.luau` | Client | Tuning-Panel (nur Studio, F2) |
| `src/shared/TuningSliders.luau` | beiden | Welche Werte das Tuning-Panel zeigt |
| `src/server/DevTuning.luau` | Server | Tuning-Werte, die der Server braucht (nur Studio) |

Unity-Vergleich: `*.server.luau` / `*.client.luau` sind wie MonoBehaviours, die von selbst
starten. Alle anderen `.luau`-Dateien sind ModuleScripts, also normale Klassen/Bibliotheken,
die per `require` geladen werden.

## Start- und Zielzone in Studio anlegen

1. **Part** einfügen (Reiter *Home* → *Part*), zu einem großen Quader skalieren, der die
   Straße komplett abdeckt, z. B. 20 × 10 × 16 Studs. Die Zone darf ein Stück im Boden stecken.
2. Benennen **oder** taggen (eins von beidem reicht):
   - **Name** im Explorer: `StartZone` bzw. `FinishZone`, oder
   - **Tag** setzen: Part auswählen → *Properties* → ganz unten *Tags* → `+` →
     `StartZone` bzw. `FinishZone`.
3. Empfohlen: *Transparency* `0.7`, *Anchored* an, *CanCollide* aus. (Das Skript setzt
   Anchored/CanCollide/CanTouch/CanQuery beim Start ohnehin richtig.)
4. **Richtung:** Der Wagen startet in der Mitte der Startzone und schaut automatisch
   **bergab**. Ist der Boden dort flach (unter 5°), schaut er zur **Vorderseite (Front)**
   des Parts. Startet er dann falsch herum: Stop, Zone um 90°/180° um die Hochachse drehen,
   nochmal Play. (Immer die Vorderseite nutzen: `Race.StartFacing = "ZoneFront"` in der Config.)
5. Tipp: Das *SpawnLocation* in die Nähe der Startzone stellen. Dort erscheint die Figur
   kurz, bevor sie in den Wagen gesetzt wird.
6. Die Zeit läuft los, sobald der Wagen die Startzone verlässt, und stoppt, sobald er in die
   Zielzone fährt. Ohne Startzone startet der Wagen 10 Studs vor dem *SpawnLocation*.

## M1 testen

`rojo serve` läuft, Studio ist verbunden. Dann **Play** (F5) drücken. Die *Output*-Ansicht
(*View → Output*) zeigt Warnungen und Fehler.

| Schritt | Was du tun kannst | Was passieren sollte |
|---|---|---|
| b) Wagen | Play | Ein grauer Einkaufswagen mit rotem Griff und vier schwarzen Kugel-Rädern erscheint. Im Explorer: `Workspace/Carts/Cart_<Name>` |
| c) Fahren | W / S / A / D (oder Pfeiltasten) | Die Figur sitzt im Wagen. W schiebt an, S bremst/fährt rückwärts, A/D lenken. Leertaste wirft dich **nicht** raus. Die Kamera hängt hinter dem Wagen, das Sichtfeld wird bei Tempo weiter. Unten rechts: Tempo |
| d) Crash | Wagen umkippen lassen, gegen eine Wand rasen, über eine Kante fallen | „CRASH!“ mit Grund (Umgekippt / Harter Aufprall / Abgestürzt) |
| e) Neustart | R drücken, oder crashen | Wagen steht sofort (unter 1 s) wieder am Start, Tempo 0, Kamera dahinter |
| f) Zeit | Durch die Startzone hinaus und in die Zielzone fahren | Oben läuft die Zeit; im Ziel „ZIEL!“ mit Zeit und ggf. „Neue Bestzeit!“, nach 3 s automatischer Neustart |

## M1.5 testen

| Funktion | Was du tun kannst | Was passieren sollte |
|---|---|---|
| Aussteigen | Im Wagen **E** drücken (Gamepad X, Touch: Button „Raus“) | Figur steht neben dem Wagen (rechts, sonst links/hinten/vorne), fliegt nicht weg. Normale Kamera, laufen und springen geht. Der leere Wagen rollt nicht den Hügel hinunter (Parkbremse) |
| Lauf abbrechen | Während die Zeit läuft aussteigen | „Lauf abgebrochen“, Zeit zeigt `--.-- s`. Wieder einsteigen startet keine neue Zeit, erst R |
| Einsteigen | Zu Fuß zum eigenen Wagen gehen (unter 10 Studs) | Hinweis „E Einsteigen“ erscheint; E (Gamepad X, Touch: antippen) setzt dich hinein, Verfolgerkamera ist zurück |
| Fremder Wagen | Mit 2 Spielern: zum leeren Wagen des anderen gehen | Kein Hinweis, Einsteigen nur in den eigenen Wagen |
| R zu Fuß | Ausgestiegen R drücken | Figur sitzt sofort wieder im Wagen am Start |
| Ragdoll-Crash | Gegen eine Wand fahren / umkippen | „CRASH!“, Figur fliegt schlaff mit Schwung nach vorne/oben aus dem Wagen, der Wagen überschlägt sich weiter. Nach 1,2 s Neustart |
| R überspringt | Direkt nach dem Crash R drücken | Sofortiger Neustart, Figur sitzt wieder normal im Wagen |
| Tacho | Fahren | Unten Mitte: km/h und Balken (grün → rot). Nur sichtbar, solange man fährt |
| Kamera-Wackeln | Schnell fahren (über ~60 Studs/s) / von einer Rampe springen | Leichtes Zittern bei Tempo, kurzes stärkeres Wackeln bei harter Landung |
| Tuning-Panel | In Studio **F2** | Panel links mit Schiebereglern; Änderungen wirken sofort. „Kipp-Ballast“ verschiebt das Gewicht im Wagen (höher = kippeliger) |
| Werte kopieren | Im Panel auf „Werte kopieren“ klicken | Im Output-Fenster stehen die Werte als Config-Code zum Übernehmen |

Das Tuning-Panel gibt es nur in Studio (`RunService:IsStudio()`). Im veröffentlichten Spiel
erscheint es nicht, und der Server ignoriert dort Tuning-Anfragen.

**Tuning:** Werte in `src/shared/Config.luau` ändern, speichern, in Studio Stop + Play.
Typische Stellschrauben:

- Zu schnell bergab → `Drive.AirDrag` erhöhen. Zu langsam → senken.
- Lenkt zu träge → `Drive.SteerRate` / `Drive.SteerResponse` erhöhen.
- Rutscht zu viel in Kurven → `Drive.LateralGrip` / `Drive.MaxGripAcceleration` erhöhen.
- Kippt zu leicht → `Cart.BallastHeight` senken, `Drive.RollDamping` erhöhen.
- Zu viele/zu wenige Crashs → `Crash.ImpactSpeedChange`, `Crash.MaxTiltAngle`.
- Wackelrad nervt → `Drive.WobbleStrength = 0`.
- Ragdoll zu wild/zu lahm → `Crash.RagdollUpSpeed`, `Crash.RagdollCarry`, `Crash.RagdollSpin`.
- Kamera wackelt zu viel → `Camera.ShakeAtFullSpeed`, `Camera.LandingShakePerSpeed`, `Camera.ShakeMaxAngle`.
- Hügel liegt tiefer als −100 → `Crash.KillY` anpassen.

Mit mehreren Spielern testen: *Test → Clients and Servers → 2 Players → Start*.
Wagen verschiedener Spieler fahren durcheinander hindurch.
