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

## Code-Überblick

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
| `src/client/DriftEffects.luau` | Client | Funken und Reifenspuren beim Drift (nur lokal) |
| `src/shared/TuningSliders.luau` | beiden | Welche Werte das Tuning-Panel zeigt |
| `src/server/DevTuning.luau` | Server | Tuning-Werte, die der Server braucht (nur Studio) |
| `src/shared/SchoolClock.luau` | beiden | Spielzeit (7:45 → 8:00), Uhrzeiten, Schulnote |
| `src/shared/TagList.luau` | beiden | Aktuelle Liste aller Objekte pro Tag |
| `src/server/TrackPieces.luau` | Server | Stellt getaggte Bausteine ein (Anchored, Kollision, Material) |
| `src/server/RandomEvents.luau` | Server | Würfelt pro Lauf die Zufallsereignisse |
| `src/client/TrackSensors.luau` | Client | Erkennt Bausteine unter/um den Wagen (Raycast, Overlap) |
| `src/client/Obstacles.luau` | Client | Bewegt Mover, Spinner, Pendulum |
| `src/client/RandomEventsClient.luau` | Client | Blendet inaktive Zufallsereignisse aus |
| `src/client/SoundSystem.luau` | Client | Sounds (IDs in `Config.Sounds`) |

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

## Baukasten: Track bauen

Du baust die Strecke aus normalen Parts (oder Modellen) und gibst ihnen einen **Tag**.
Die Skripte stellen Anchored, CanCollide usw. selbst richtig ein. Einzelne Werte setzt du
als **Attribut** am Part (*Properties* → ganz unten *Attributes* → `+`). Fehlt ein Attribut,
gilt der Standardwert aus `src/shared/Config.luau`.

**Tag setzen:** Part auswählen → *Properties* → *Tags* → `+` → Name eintippen (genau so
geschrieben wie in der Tabelle). Mehrere Tags pro Part sind erlaubt (z. B. `Mover` + `Hazard`).

| Tag | Wirkung | Attribute (Typ) – Standardwert |
|---|---|---|
| `StartZone` | Start: Wagen steht in der Mitte, schaut bergab. Zeit läuft beim Verlassen | `TimeScale` (Zahl) – `Clock.TimeScale` = 15 Spielsekunden pro Sekunde |
| `FinishZone` | Ziel: beendet den Lauf, Ergebnis mit Note | `Grade6` … `Grade2` (Text „7:53“) – 7:53 / 7:56 / 8:00 / 8:02 / 8:05; später = Note 1 |
| `Checkpoint` | Durchfahren speichert Position + Richtung. R / Crash → hierher | `Order` (Zahl) – keine. Mit Order zählt ein Checkpoint mit kleinerer Zahl als der letzte nicht |
| `BoostPad` | Schub in Blickrichtung (Vorderseite) des Parts, beim Drauffahren | `Strength` (Zahl, Studs/s) – 40 |
| `JumpPad` | Schleudert entlang der Oberseite des Parts nach oben | `Strength` (Zahl, Studs/s) – 70 (≈ 12 Studs hoch) |
| `Mud` | Bremst stark, Drift-Ladung pausiert | `Drag` (Zahl, pro Sekunde) – 3 |
| `Ice` | Kaum Seitenhalt und Lenkhilfe, alles rutscht | `Grip` (Zahl, 0–1) – 0.1 |
| `Bouncy` | Federt ab statt Crash | `Bounciness` (Zahl, 0–1) – 0.9 |
| `Hazard` | Sofortiger Crash bei Berührung (Wasser, Baugrube …) | `Message` (Text) – „Gefahrenzone!“; `Solid` (Bool) – false (= man fährt hinein) |
| `Mover` | Fährt zwischen Startposition und Startposition + Offset hin und her | `Offset` (Vector3, relativ zum Part, −Z = vorne) – (0, 0, −30); `Duration` (s) – 3; `Pause` (s) – 1; `Phase` (s) – 0 |
| `Spinner` | Dreht sich um die eigene Hochachse | `Speed` (Grad/s, negativ = andersrum) – 90; `Phase` (s) – 0 |
| `Pendulum` | Schwingt um die Oberkante des Parts (Modell: um den Pivot), Achse X | `Angle` (Grad) – 45; `Duration` (s, hin und zurück) – 3; `Phase` (s) – 0 |
| `RandomEvent` | Pro Lauf aktiv oder ausgeblendet | `Chance` (0–1) – 0.5; `Group` (Text) – keine. Aus jeder Gruppe ist genau eins aktiv (`Chance` = Gewicht) |

Hinweise:
- **Ausrichtung:** „Vorderseite“ ist die *Front*-Seite des Parts (−Z). BoostPad und Mover
  richten sich danach. Im Zweifel ausprobieren und das Part drehen.
- **Bodenbausteine** (BoostPad, JumpPad, Mud, Ice) werden per Raycast unter den Rädern
  erkannt: Sie müssen befahrbar sein, also die Oberfläche der Straße bilden (oder knapp
  darüber liegen).
- **Bewegte Hindernisse** dürfen Modelle sein (z. B. ein Auto aus mehreren Parts). Bei
  Modellen bestimmt der *Pivot* (Studio: *Edit Pivot*) den Dreh- bzw. Schwingpunkt.
  Mach schnelle Hindernisse nicht zu dünn, sonst kann der Wagen hindurchrutschen.
- **Zufallsereignisse:** Ausgeblendete Objekte sind für dich unsichtbar und ohne Wirkung.
  Lege **keine Checkpoints** in ein RandomEvent (der Server sieht die Auswahl der Spieler
  nicht). Jeder Spieler bekommt seine eigene Auswahl.

**So baust du einen Track:**
1. Hügel und Straße bauen. `StartZone` oben, `FinishZone` vor der Schule (große, durchsichtige
   Quader über die ganze Straße).
2. Alle paar Abschnitte einen `Checkpoint`-Quader über die Straße legen, bei Abzweigungen mit
   `Order` (1, 2, 3 …; alternative Wege bekommen dieselbe Zahl).
3. Bausteine verteilen: BoostPads auf Geraden, JumpPads vor Lücken, Schlamm/Eis in Kurven,
   Hazards in Gruben/Wasser, Bouncy an Wänden, wo man nicht crashen soll.
4. Hindernisse (Mover/Spinner/Pendulum) setzen, mit `Phase` gegeneinander versetzen.
5. Abkürzungen mit `RandomEvent` mal offen, mal versperrt bauen (z. B. eine Sperre mit
   `Chance` 0.5, oder drei Baustellen mit `Group` = „Baustelle“).
6. Zeit testen und `TimeScale` (StartZone) sowie die Noten-Grenzen (FinishZone) so setzen,
   dass eine gute Fahrt knapp vor 8:00 ankommt.

## M1 testen

Seit M2 gilt: **R** = zurück zum letzten Checkpoint (ohne Checkpoint: zum Start), **T** =
kompletter Neustart; die Zeit wird als Schuluhr angezeigt.

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
| Drift | Bei Tempo lenken und **Shift** halten (Gamepad B, Touch: Button „Drift“) | Das Heck bricht aus, der Wagen rutscht quer. Reifenspuren erscheinen und verblassen nach ~3 s |
| Abfangen | Im Drift gegenlenken (Heck rutscht nach rechts → nach rechts lenken) | Der Wagen richtet sich wieder aus. Ohne Gegenlenken dreht er sich nicht um 180°, sondern wird ab ~55° zurückgedreht |
| Boost-Ladung | Lange driften (über 25 Studs/s, Driftwinkel über 12°) | Funken an den Hinterrädern: hell → nach 1 s blau (Stufe 1) → nach 2 s orange (Stufe 2) |
| Boost | Shift nach blauen/orangen Funken loslassen | Kurzer Schub nach vorne (+15 % / +25 % des Höchsttempos), am Tacho sichtbar |
| Kein Farmen | Im Stand Shift halten und lenken | Keine Funken, kein Boost |
| Ladung weg | Mit Ladung crashen, R drücken oder aussteigen | Boost-Ladung ist danach leer |
| ShiftLock | Im Wagen Shift drücken, dann aussteigen | ShiftLock wurde durch das Driften nicht umgeschaltet |
| Tacho | Fahren | Unten Mitte: km/h und Balken (grün → rot). Nur sichtbar, solange man fährt |
| Kamera-Wackeln | Schnell fahren (über ~60 Studs/s) / von einer Rampe springen | Leichtes Zittern bei Tempo, kurzes stärkeres Wackeln bei harter Landung |
| Tuning-Panel | In Studio **F2** | Panel links mit Schiebereglern; Änderungen wirken sofort. „Kipp-Ballast“ verschiebt das Gewicht im Wagen (höher = kippeliger). Drift-Regler: Seitenhalt hinten, Rückstell-Winkel/-Stärke, Boost-Schwellen |
| Werte kopieren | Im Panel auf „Werte kopieren“ klicken | Im Output-Fenster stehen die Werte als Config-Code zum Übernehmen |

## M2 testen

| Funktion | Was du tun kannst | Was passieren sollte |
|---|---|---|
| Schuluhr | Play, losfahren | Oben steht 7:45, ab Verlassen der Startzone läuft sie (15 Spielminuten in 60 s). Ab 7:57 gelb → rot und pulsierend, ab 8:00 rot mit „zu spät!“ |
| Pünktlich | Vor 8:00 in die Zielzone | Ergebnis-Screen: „PUENKTLICH!“, Ankunftszeit, Bestzeit, Fahrzeit, Note (6 = beste) |
| Zu spät | Nach 8:00 ankommen (oder `TimeScale` an der StartZone auf 60 setzen) | Zufälliger Titel wie „Ab zum Rektor!“, Verspätung in Min:Sek, schlechtere Note |
| Eigene Noten | Attribut `Grade6` = „7:50“ an der FinishZone | Note 6 nur noch bis 7:50 |
| Checkpoint | Durch einen `Checkpoint` fahren | Hinweis „Checkpoint!“ unter der Uhr |
| Zurück zum CP | Nach dem Checkpoint crashen oder R | Wagen steht am Checkpoint in Fahrtrichtung, Uhr läuft weiter. Ergebnis: „Mit Checkpoint-Neustart“ |
| Komplett neu | T (Gamepad: Steuerkreuz hoch, Touch: „Start“) | Wagen am Start, Uhr 7:45, neue Zufallsereignisse |
| Reihenfolge | Checkpoints mit `Order` 1 und 2; erst 2, dann 1 durchfahren | Bei 1: „Falscher Checkpoint“, R bringt dich zu 2 |
| BoostPad / JumpPad | Drüberfahren | Schub nach vorne bzw. Sprung; Landung nach JumpPad ist kein Crash (außer extrem hart) |
| Mud / Ice | Hineinfahren | Schlamm bremst stark, Drift-Funken stoppen. Eis: Wagen rutscht, lenkt kaum |
| Bouncy | Mit Tempo gegen eine Bouncy-Wand | Wagen prallt ab, kein Crash |
| Hazard | In einen Hazard fahren | Sofort „CRASH!“ mit dem Text aus `Message` |
| Mover / Spinner / Pendulum | Hinfahren und anfahren lassen | Bewegung ist flüssig, der Wagen wird weggeschoben (oder crasht bei hartem Treffer), fährt nicht hindurch |
| RandomEvent | Part mit `Chance` 0.5; mehrmals T | Mal da, mal weg (unsichtbar und durchfahrbar) |
| Gruppe | 3 Parts mit `Group` = „A“; mehrmals T | Immer genau eins sichtbar |
| Sounds | IDs in `Config.Sounds` eintragen | Rollen (Tonhöhe nach Tempo), Drift-Quietschen, Boost, Crash, Checkpoint, Glocke um 8:00, Ziel. Leere IDs: kein Ton, kein Fehler im Output |
| Tuning-Panel | F2 | Neue Regler: Schlamm-Bremse, Eis-Seitenhalt, BoostPad-/JumpPad-Stärke, Spielzeit-Tempo (gilt ab dem nächsten Start); Panel scrollt |

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
- Drift zu schwer/zu leicht auszulösen → `Drift.RearGrip` (kleiner = rutschiger).
- Drift schwer abzufangen → `Drift.SteerAngle` erhöhen; dreht zu weit ein → `Drift.RecoverAngle` senken oder `Drift.RecoverStrength` erhöhen.
- Boost zu stark → `Drift.Level1Boost` / `Drift.Level2Boost` (Anteil von `Drive.MaxSpeed`).
- Ragdoll zu wild/zu lahm → `Crash.RagdollUpSpeed`, `Crash.RagdollCarry`, `Crash.RagdollSpin`.
- Kamera wackelt zu viel → `Camera.ShakeAtFullSpeed`, `Camera.LandingShakePerSpeed`, `Camera.ShakeMaxAngle`.
- Hügel liegt tiefer als −100 → `Crash.KillY` anpassen.

Mit mehreren Spielern testen: *Test → Clients and Servers → 2 Players → Start*.
Wagen verschiedener Spieler fahren durcheinander hindurch.
