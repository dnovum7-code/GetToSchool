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

## Test-Place öffnen

Ein fertiger Test-Place mit einer Teststrecke, auf der **jeder Baustein einmal vorkommt**
(mit Schild und Nummer), einer flachen **Testfläche** für Lenkung und Drift und fertigen
**Vorlagen** (Steine, Auto) in `ReplicatedStorage/Templates`. Er benutzt denselben Code wie
das Spiel, du kannst also wie gewohnt live mit `rojo serve` arbeiten.

1. `git pull`
2. Test-Place bauen (im Projektordner):
   ```bash
   rojo build test.project.json -o TestPlace.rbxl
   ```
3. `TestPlace.rbxl` in Studio öffnen (Doppelklick oder *File → Open from File*).
4. Live-Sync: `rojo serve` (das normale Projekt) starten und im Rojo-Plugin **Connect**.
   Rojo aktualisiert nur die Skripte; Teststrecke und Vorlagen bleiben unberührt.
5. **Play**. Du startest oben auf der Teststrecke. Die Testfläche: **B** → *Strecken* →
   *Testflaeche (Lenkung & Drift)* → *Fahren*.

Hinweise:
- Speichern: Eine Datei, die nicht veröffentlicht ist, darf keine DataStores benutzen. Im Output
  erscheint die Warnung „nur im Arbeitsspeicher“ – das ist im Test-Place richtig so.
- Für die Abkürzungs-Tür und die Abilities ohne Einkaufen: `Config.Debug.AllUpgrades = true`.
- Für Signale: `Config.Debug.Toolkit = true`.
- `TestPlace.rbxl` wird von git ignoriert. Nach einem `git pull` mit Änderungen an der
  Teststrecke einfach Schritt 2 wiederholen (deine Änderungen im Test-Place gehen dabei verloren).
- Für mich: Die Strecke wird mit `lune run tools/build_testplace` aus Code erzeugt
  (`test/*.rbxm`, `test.project.json`).

### Checkliste Teststrecke (Reihenfolge der Strecke)

| Nr. | Station | Was tun | Was passieren sollte |
|---|---|---|---|
| – | Start | Play | Wagen in der Startzone, Blick bergab; Münzzähler, 5 Ranzen, Shop-Knopf sichtbar; keine roten Fehler |
| 1 | Münzen | Durch die Münzreihe fahren | Jede Münze „+1“, die große „+5“; Zähler steigt. T: Münzen bleiben weg (erst nach dem Ziel wieder da) |
| 2 | BoostPad | Über das grüne Feld | Spürbarer Schub nach vorne |
| 3 | JumpPad | Über das pinke Feld | Sprung nach oben (ca. 19 Studs), weiche Landung ohne Crash |
| 4 | Mud | Durch den Schlamm | Starkes Abbremsen, Drift-Funken stoppen |
| 5 | Ice | Auf dem Eis lenken | Wagen rutscht, lenkt kaum |
| 6 | Bouncy | Links gegen die pinke Wand | Federt ab, kein Crash |
| 7 | Hazard | Rechts durchs Wasser | „CRASH! Ins Wasser gefallen!“, ein Leben weg, Figur fliegt, zurück zum Start (noch kein Checkpoint) |
| 8 | Checkpoint 1 | Durchfahren, dann R | Hinweis „Checkpoint“; R setzt dich hierher zurück, Zeit läuft weiter |
| 9 | Mover | Am querfahrenden Block vorbei | Block fährt hin und her, schiebt den Wagen sauber |
| 10 | Spinner | Am drehenden Balken vorbei | Balken dreht sich, schubst bei Berührung |
| 11 | Pendulum | Unter dem Pendel durch | Pendel schwingt quer, trifft bei falschem Timing |
| 12 | Zufall | Eine Seite ist gesperrt | Nach T ist es vielleicht die andere Seite |
| 13 | Launchable | Kuh (links) bzw. Mülltonne (rechts) umfahren | „MUUH!“/„SCHEPPER!“, kurzer Stillstand, Kamera wackelt, Wagen fährt weiter, Objekt fliegt; oben „Kuh: … m“; Mülltonne verschwindet mit Stern im Himmel; ein Leben weg |
| 14 | Checkpoint 2 | Durchfahren | Hinweis „Checkpoint“ (Zwischenzeit ab dem 2. Lauf) |
| 15 | Steinschlag | Durch den roten Trigger fahren | Steine fallen vor dir auf die Straße; Treffer = „Steinschlag!“-Crash. R: Steine weg, Trigger wieder scharf |
| 16 | Auto-Strom | Zwischen den Autos durch | Autos fahren gleichmäßig quer, schubsen nur (kein Crash) |
| 17 | PathMover | Am Lieferwagen vorbei | Fährt im Rechteck, dreht sich in Fahrtrichtung, wartet kurz an den Ecken |
| 18 | Gate | Schranke | Hebt und senkt sich im Takt |
| 19 | Abkürzungs-Tür | Linke Spur | Ohne Sprungfeder: Schild „nur mit Trampolin-Sprungfeder“, Tür fest. Mit (Shop oder Debug): Tür fährt weg, Bonus-Münzen dahinter |
| 20 | Collapse | Über die Holzbrücke | Bretter wackeln und fallen nacheinander; wer zu langsam ist, fällt in die Grube (Crash). R: Brücke wieder da |
| 21 | Props | Kisten und Pylonen umfahren | Fliegen weg, kein Crash; im Ergebnis „Chaos: X“ |
| 22 | ForceZone | Durch den Wind | Wagen wird im 2-s-Takt nach rechts gedrückt |
| 23 | Chaser | Langsam am Hund vorbei | Hund rennt dir nach, bleibt knapp hinter dem Wagen, gibt nach ~6 s auf, läuft heim |
| 24 | Checkpoint 3 | Durchfahren | Hinweis „Checkpoint“ |
| 25 | Ziel | Durchs Ziel | Ergebnis mit Zeit, Note (Grenzen 50/65/80/100/130 s), Münzen, Leben, Treffer, Chaos; Münzen der Strecke sind wieder da |
| 26 | Schule | Auf die Schulwand schauen | Zwei Tafeln: Bestenliste „Der Schulweg“ und „Weitester Kuh-Wurf“ mit Top 10 und „Du: Platz …“ (nach dem ersten Lauf/Wurf) |
| – | Testfläche | B → Strecken → Testfläche | Flacher Platz: Slalom (Pylonen = Props), Drift-Kreis rechts; A/D = Drift, Shift halten = normal |

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

## Optional: Code-Qualität und automatische Tests

```bash
stylua src        # formatiert den Code
selene src        # Linter (findet typische Fehler)
lune run tests/run   # automatische Tests (ohne Studio), Lune kommt mit "rokit install"
```

Die Tests (`tests/`) prüfen die reine Spiel-Logik in `src/shared/Progression`: Speicherformat
und Migration, Münzen und Preise, Leben/Helm, Flugweiten, Freischalt-Bedingungen. Am Ende
steht „X von X Tests bestanden“; bei einem Fehler steht `FEHLER` mit Grund davor.
Unity-Vergleich: wie der Test Runner im Edit Mode – nur Logik, ohne Szene.

## Code-Überblick

| Datei | Läuft auf | Aufgabe |
|---|---|---|
| `src/shared/Config.luau` | beiden | **Alle Tuning-Werte** (Tempo, Lenkung, Kamera, Crash, Rennen) |
| `src/server/GameServer.server.luau` | Server | Einstieg: verbindet Spieler, Wagen, Rennen |
| `src/server/CartBuilder.luau` | Server | baut den Einkaufswagen aus Parts |
| `src/server/CartManager.luau` | Server | Wagen pro Spieler, hineinsetzen, Physik an Client geben, Zurücksetzen |
| `src/server/Track.luau` | Server | Strecken finden, Start-/Zielzone pro Strecke, Startposition, „ist in Zone?“ |
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
| `src/server/DevTuning.luau` | Server | Tuning-Werte, die der Server braucht (nur Studio) |
| `src/shared/RaceTime.luau` | beiden | Zeit-Anzeige (1:23.45), Abstand (+0.45), Schulnote |
| `src/shared/Attributes.luau` | beiden | Attribute sicher lesen (falscher Typ → Standardwert + Warnung) |
| `src/server/BestTimes.luau` | Server | Bestzeiten pro Spieler und Track (im Spielstand) |
| `src/shared/TagList.luau` | beiden | Aktuelle Liste aller Objekte pro Tag |
| `src/server/TrackPieces.luau` | Server | Stellt getaggte Bausteine ein (Anchored, Kollision, Material) |
| `src/server/RandomEvents.luau` | Server | Würfelt pro Lauf die Zufallsereignisse |
| `src/client/TrackSensors.luau` | Client | Erkennt Bausteine unter/um den Wagen (Erkennungs-Kästen) |
| `src/client/Obstacles.luau` | Client | Bewegt Mover, Spinner, Pendulum |
| `src/client/RandomEventsClient.luau` | Client | Blendet inaktive Zufallsereignisse aus |
| `src/client/SoundSystem.luau` | Client | Sounds (IDs in `Config.Sounds`) |
| `src/shared/Progression/*.luau` | beiden | Reine Logik (getestet): `SaveData` (Speicherformat), `Economy` (Münzen, Preise), `RunRules` (Leben, Helm), `LaunchMath` (Flugbahn), `Unlocks` (Strecken freischalten) |
| `src/server/Profiles.luau` | Server | Spielstand laden/speichern (DataStore, Wiederholen bei Fehlern, Ersatz im Arbeitsspeicher) |
| `src/server/ProgressSync.luau` | Server | Schickt dem Client eine Kopie des Spielstands (Anzeige) |
| `src/server/Coins.luau` | Server | Münzen prüfen und gutschreiben |
| `src/server/Launchables.luau` | Server | Treffer an Launchables prüfen, Flug planen, Rekorde, Bonus |
| `src/server/Shop.luau` | Server | Käufe prüfen (Upgrades) |
| `src/server/TrackUnlocks.luau` | Server | Strecken freischalten und wählen |
| `src/client/ProgressClient.luau` | Client | Empfängt die Spielstand-Kopie, verteilt sie an UI und Abilities |
| `src/client/ProgressUI.luau` | Client | Münzzähler, Leben (Schulranzen), Helm-Ladungen |
| `src/client/CoinsClient.luau` | Client | Münzen drehen, einsammeln, Animation |
| `src/client/LaunchablesClient.luau` | Client | Treffer-Show: Comic-Text, Flug, Flugweite, Stern-Blinken |
| `src/client/Abilities/` | Client | Ein Modul pro Ability (`SpringJump`, `Helmet`, `TurboSnack`, `Glider`), `init.luau` = Manager, `AbilityTypes` = gemeinsame Schnittstelle |
| `src/client/AbilityHud.luau` | Client | Ability-Anzeige unten links |
| `src/client/ShopUI.luau` | Client | Menü „Pausen-Kiosk“ (B): Upgrades, Strecken, Rekorde |
| `src/client/LocalHide.luau` | Client | Objekte nur für diesen Spieler aus-/einblenden |
| `src/client/Toolkit/` | Client | Erweiterter Baukasten (M2.5): ein Modul pro Baustein (`TriggerZones`, `Spawners`, `PathMovers`, `Gates`, `Collapses`, `Props`, `ForceZones`, `Chasers`), `Signals` (Signal-System), `init.luau` = Manager |
| `src/shared/Toolkit/*.luau` | beiden | Reine Logik (getestet): `Rng` (reproduzierbarer Zufall), `SpawnSchedule`, `PathMath` (Wege, Tor-Takt), `TriggerRules`, `ChaserLogic` |
| `src/client/Kinematic.luau` | Client | Verankerte Teile so bewegen, dass sie den Wagen sauber schieben |
| `src/client/LocalClone.luau` | Client | Lokale Kopien (fliegende Kühe, Steine, Props …) |
| `plugin/` | Studio | Bau-Hilfe-Plugin (Pfeile, Bereiche, Wege beim Bauen) |
| `tools/build_testplace.luau`, `test/`, `test.project.json` | – | Test-Place: Generator (Lune), erzeugte Strecke/Vorlagen, Projektdatei |
| `src/shared/Progression/GhostCodec.luau` | beiden | Reine Logik (getestet): Geist-Aufnahme platzsparend speichern und abspielen |
| `src/server/Ghosts.luau` | Server | Zeichnet Läufe auf, speichert den Geist der Bestzeit (eigener DataStore) |
| `src/client/GhostClient.luau` | Client | Spielt den Geist als halbdurchsichtigen Wagen ab |
| `src/shared/Progression/RunValidation.luau`, `LeaderboardMath.luau` | beiden | Reine Logik (getestet): Plausibilitätsprüfung für die Bestenliste, Plätze und Werte |
| `src/server/Leaderboards.luau` | Server | Bestenlisten: OrderedDataStore pro Strecke + Kuh-Wurf, Ansichten Global/Server/Freunde |
| `src/client/LeaderboardClient.luau` | Client | Reiter „Bestenliste“ im Menü, Bretter in der Welt |
| `src/shared/Progression/Homework.luau` | beiden | Reine Logik (getestet): Hausaufgaben auswürfeln, Fortschritt, Tageswechsel |
| `src/server/Homework.luau` | Server | Hausaufgaben: Ereignisse verbuchen, Belohnung, Tageswechsel |
| `src/client/HomeworkUI.luau` | Client | Reiter „Hausaufgaben“ mit Fortschrittsbalken |
| `src/client/StatReporter.luau` | Client | Meldet Werte, die nur der Client kennt (Driftzeit), der Server begrenzt sie |
| `src/shared/Progression/VehicleStats.luau` | beiden | Reine Logik (getestet): Fahrwerte pro Fahrzeug (fester Wert oder Faktor auf den Einkaufswagen) |
| `src/shared/Vehicles.luau` | beiden | Fahrzeuge aus `Config.Vehicles`, Fahrwerte eines Wagens (`Vehicles.forCart`) |
| `src/server/Garage.luau` | Server | Fahrzeuge kaufen und wählen |
| `src/client/GarageUI.luau` | Client | Reiter „Garage“ im Menü |
| `src/shared/Progression/Cosmetics.luau` | beiden | Reine Logik (getestet): Farbe pro Fahrzeug, Spur, besessen? |
| `src/server/Cosmetics.luau` | Server | Lackiererei: Farben/Spuren kaufen, wählen, am Wagen anwenden |
| `src/client/PaintShopUI.luau` | Client | Reiter „Lackiererei“ im Menü |
| `src/client/Settings.luau`, `SettingsUI.luau` | Client | Einstellungen (gespeichert über `server/PlayerSettings.luau`) und Reiter „Einstellungen“ |
| `src/client/ControlsInfo.luau` | Client | Steuerung als Text je Gerät (Tabelle, Hilfezeile, Hinweise) |
| `src/client/Onboarding.luau` | Client | Einmalige Einstiegs-Hinweise (Fahren, Drift, Neustart) |
| `src/shared/Progression/TrickMath.luau` | beiden | Reine Logik (getestet): Lufttricks zählen und Landung bewerten |
| `src/shared/Progression/Combo.luau` | beiden | Reine Logik (getestet): Kuh-Kombo zählen, Multiplikator, Bonus |
| `src/shared/Progression/DailySpin.luau` | beiden | Reine Logik (getestet): Glücksrad würfeln, Gewinne, Powerups pro Lauf verbrauchen |
| `src/server/DailySpin.luau`, `src/client/SpinUI.luau` | beide | Glücksrad: Server würfelt und schreibt gut / Reiter mit drehendem Rad |
| `src/client/ComboUI.luau` | Client | Große Anzeige „3x KOMBO!“ mit ablaufendem Zeitbalken |
| `src/client/Tricks.luau`, `src/server/Tricks.luau` | beide | Lufttricks: drehen, Anzeige, Crash bei schiefer Landung / Münzen prüfen und gutschreiben |
| `src/server/PlayerEvents.luau` | Server | Verteilt Ereignisse (Ziel, Wurf, Münzen, Drift) an Hausaufgaben und Erfolge; prüft die Drift-Meldungen |
| `src/shared/Progression/Achievements.luau` | beiden | Reine Logik (getestet): Erfolge prüfen, Fortschritt |
| `src/server/Achievements.luau` | Server | Erfolge freischalten, speichern, Popup, Roblox-Badges |
| `src/client/AchievementUI.luau` | Client | Erfolgs-Popup und Reiter „Erfolge“ |

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
| `StartZone` | Start: Wagen steht in der Mitte, schaut bergab. Zeit läuft beim Verlassen | `TrackId` (Text) – „Track1“, nur für Zonen außerhalb eines Track-Models (siehe „Zweiten Track anlegen“) |
| `FinishZone` | Ziel: beendet den Lauf, Ergebnis mit Note | `Grade6` … `Grade2` (Zahl, Sekunden) – 60 / 75 / 90 / 110 / 130; langsamer = Note 1 |
| `Checkpoint` | Durchfahren speichert Position + Richtung. R / Crash → hierher. Für die globale Bestenliste müssen alle durchfahren werden (alternative Wege: gleiche `Order`, einer reicht) | `Order` (Zahl) – keine. Mit Order zählt ein Checkpoint mit kleinerer Zahl als der letzte nicht; `Optional` (Bool) – false (= muss für die Bestenliste nicht durchfahren werden) |
| `BoostPad` | Schub in Blickrichtung (Vorderseite) des Parts, beim Drauffahren | `Strength` (Zahl, Studs/s) – 40 |
| `JumpPad` | Schleudert entlang der Oberseite des Parts nach oben | `Strength` (Zahl, Studs/s) – 86 (≈ 19 Studs hoch) |
| `Mud` | Bremst stark, Drift-Ladung pausiert | `Drag` (Zahl, pro Sekunde) – 3 |
| `Ice` | Kaum Seitenhalt und Lenkhilfe, alles rutscht | `Grip` (Zahl, 0–1) – 0.1 |
| `Bouncy` | Federt ab statt Crash | `Bounciness` (Zahl, 0–1) – 0.9 |
| `Hazard` | Sofortiger Crash bei Berührung (Wasser, Baugrube …) | `Message` (Text) – „Gefahrenzone!“; `Solid` (Bool) – false (= man fährt hinein) |
| `Mover` | Fährt zwischen Startposition und Startposition + Offset hin und her | `Offset` (Vector3, relativ zum Part, −Z = vorne) – (0, 0, −30); `Duration` (s) – 3; `Pause` (s) – 1; `Phase` (s) – 0 |
| `Spinner` | Dreht sich um die eigene Hochachse | `Speed` (Grad/s, negativ = andersrum) – 90; `Phase` (s) – 0 |
| `Pendulum` | Schwingt um die Oberkante des Parts (Modell: um den Pivot), Achse X | `Angle` (Grad) – 45; `Duration` (s, hin und zurück) – 3; `Phase` (s) – 0 |
| `RandomEvent` | Pro Lauf aktiv oder ausgeblendet | `Chance` (0–1) – 0.5; `Group` (Text) – keine. Aus jeder Gruppe ist genau eins aktiv (`Chance` = Gewicht) |
| `TriggerZone` | Fährt dein Wagen hinein, wird ein **Signal** ausgelöst (siehe „Erweiterter Baukasten“) | `Signal` (Text) – nötig; `Once` (Bool) – false (nur einmal pro Lauf); `Cooldown` (s) – 2 |
| `Spawner` | Spawn-Bereich (Part): erzeugt Objekte aus Vorlagen mit Schwung Richtung Vorderseite | siehe Tabelle „Spawner“ unten |
| `PathMover` | Modell fährt Wegpunkte ab (Ordner `Waypoints` mit Parts `1`, `2`, `3` …) | `Speed` – 16; `Loop` (Bool) – false (= hin und zurück); `WaitAtPoints` (s) – 0; `FaceDirection` (Bool) – true; `Phase` (s) – 0; `ListenSignal` – keins |
| `Gate` | Tor/Schranke/Klappbrücke: bewegt sich um den Pivot | `Offset` (Vector3) – 0; `Angle` (Grad) – 0; `Axis` („X“/„Y“/„Z“) – X; `Duration` (s) – 2; `OpenTime` – 3; `ClosedTime` – 3; `Phase` – 0; `StartOpen` (Bool) – false; `ListenSignal`; `CloseAfter` (s, 0 = bleibt offen) – 0 |
| `Collapse` | Brücke/Boden: wackelt nach dem Befahren und stürzt ab, steht bei R/T wieder | `Delay` (s) – 0.8; `Shake` (Studs) – 0.25; `FallSpin` – 1.5; `ListenSignal` (dann nur per Signal) |
| `Prop` | Loser Gegenstand (Kiste, Pylone, Stand): fliegt weg, kein Crash. Zählt als „Chaos“. Zurück nur bei T | `Density` (Zahl) – 0.4 |
| `ForceZone` | Bereich drückt den Wagen Richtung Vorderseite (Wind, Rasensprenger, Förderband) | `Strength` (Studs/s²) – 60; `Pulse` (s, 0 = immer) – 0; `PulseOn` (0–1) – 0.5; `Phase` – 0; `ListenSignal`; `ActiveTime` (s) – 3 |
| `Chaser` | Verfolger (z. B. Hund): rennt dir nach, gibt auf, läuft heim | `Radius` – 40; `MaxSpeed` – 32; `Acceleration` – 50; `GiveUpTime` (s) – 6; `ReturnSpeed` – 14; `Cooldown` (s) – 3; `Hazard` (Bool) – false; `Message`; `ListenSignal` |
| `UpgradeDoor` | Abkürzungs-Tür: geht nur für Spieler mit dem Upgrade auf (fährt nach unten weg), sonst Schild „nur mit …“ | `RequiredUpgrade` (Text: Upgrade-Id aus `Config.Upgrades`, z. B. `Spring`, `Helmet`, `Turbo`, `Glider`) – nötig; `RequiredLevel` (Zahl) – 1 |
| `Coin` | Münze: dreht sich, Durchfahren sammelt sie ein (bleibt dir auch nach Crash). Erscheint erst wieder, wenn du das Ziel dieser Strecke erreichst (nicht bei T, gegen „Farmen“) | `Value` (Zahl) – 1 |
| `Leaderboard` | Brett mit der Bestenliste (Top 10 + dein Platz), z. B. an der Schulwand. Jeder Spieler sieht seinen eigenen Platz | `Board` (Text: TrackId oder `Flight` = Weitester Kuh-Wurf) – Strecke, in der das Brett liegt; `Face` (Text: `Front`, `Back`, `Left`, `Right`, `Top`) – Front |
| `Launchable` | Kuh, Mülltonne, Gartenzwerg …: Hineinfahren kostet ein Leben, der Wagen fährt aber weiter, das Objekt fliegt absurd weit. Erscheint bei T wieder | `LaunchPower` (Zahl) – 140; `SpinPower` (Zahl) – 12; `SkyChance` (0–1) – 0.25 (fliegt in den Himmel); `Sound` (Sound-Id, z. B. „Muh“) – keiner; `DisplayName` (Text, für Rekorde) – Name des Objekts; `ComicText` (Text, z. B. „MUUH!“) – zufällig |

Hinweise:
- **Ausrichtung:** „Vorderseite“ ist die *Front*-Seite des Parts (−Z). BoostPad und Mover
  richten sich danach. Im Zweifel ausprobieren und das Part drehen.
- **Bodenbausteine** (BoostPad, JumpPad, Mud, Ice) werden an der Aufstandsfläche der Räder
  erkannt: Sie dürfen auf der Straße liegen, bündig sein oder bis ca. 0.5 Studs eingelassen
  sein (`Track.FloorSensorBelow`). Klappt etwas nicht: `Config.Debug.TrackPieces = true`.
- **Bewegte Hindernisse** dürfen Modelle sein (z. B. ein Auto aus mehreren Parts). Bei
  Modellen bestimmt der *Pivot* (Studio: *Edit Pivot*) den Dreh- bzw. Schwingpunkt.
  Mach schnelle Hindernisse nicht zu dünn, sonst kann der Wagen hindurchrutschen.
- **Münzen** dürfen Parts oder Modelle sein. Ein graues Plastik-Part wird automatisch golden.
  Die Münze dreht sich um die Hochachse; leg sie etwa auf Wagenhöhe (ca. 2 Studs über die Straße).
- **Launchables** dürfen Modelle sein (z. B. eine Kuh aus mehreren Parts). Sie sind nicht fest:
  Der Wagen fährt hindurch, das Objekt fliegt. Gib ihnen einen `DisplayName` („Kuh“), dann
  heißt der Rekord „Weitester Kuh-Wurf“.
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
6. Zeit testen und die Noten-Grenzen (`Grade6` … `Grade2` an der FinishZone, in Sekunden)
   so setzen, dass eine sehr gute Fahrt knapp eine 6 schafft.
7. Münzen (`Coin`) auf schwierige Wege legen, damit sich Risiko lohnt, und ein paar
   `Launchable`-Objekte (Kühe!) dorthin stellen, wo man sie gerne umfährt.

## Erweiterter Baukasten (M2.5)

Du baust das **Aussehen** (Steine, Autos, Hund, Brücke …), die Tags liefern das **Verhalten**.

**Wer rechnet?** Alle Bausteine dieses Abschnitts laufen auf dem Client des jeweiligen
Spielers: Jeder hat seine eigene Version (dein Steinschlag, deine eingestürzte Brücke, deine
umgefahrenen Kisten). So passen Zusammenstöße mit deinem Wagen ohne Verzögerung, und niemand
macht einem anderen die Strecke kaputt. Dauerbetrieb (Auto-Strom, Tore im Takt, PathMover)
läuft nach der Serveruhr mit reproduzierbarem Zufall: Alle Spieler sehen ihn gleich.
Unity-Vergleich: wie lokale Effekte/Physik pro Spieler mit gemeinsamem Random-Seed.

### Vorlagen-Ordner (für Spawner)

1. In Studio im Explorer: **ReplicatedStorage** → Rechtsklick → *Insert Object* → **Folder**,
   Name **`Templates`** (genau so).
2. Deine Vorlagen hineinlegen: Modelle oder Parts, z. B. `Stein1`, `Stein2`, `Auto_Rot`.
   Tipp: Steine als einzelnes Part (Ball/MeshPart), Autos als Modell mit gesetztem *PrimaryPart*.
   Die Vorderseite (−Z bzw. Pivot) zeigt in Fahrtrichtung.
3. Am Spawner: Attribut `Template` = `Stein1, Stein2` (mehrere = zufällige Auswahl).

**Rojo und der Ordner:** Rojo verwaltet in ReplicatedStorage nur `Shared` und `Remotes`. In
`default.project.json` steht für ReplicatedStorage `"$ignoreUnknownInstances": true`: Alles,
was Rojo nicht kennt (dein `Templates`-Ordner), wird beim Sync weder gelöscht noch
überschrieben. Der Ordner wird mit deinem Place gespeichert (*File → Publish to Roblox*),
nicht in Git. Fehlt eine Vorlage, spawnt eine graue Ersatz-Kugel und im Output steht eine Warnung.

### Signale (Trigger-System)

- **TriggerZone**: unsichtbares Part mit Tag `TriggerZone` und Attribut `Signal`, z. B.
  `Steinschlag1`. Fährt dein Wagen hinein, wird das Signal ausgelöst (nur bei dir).
  `Once` = nur einmal pro Lauf, `Cooldown` = Mindestabstand in Sekunden.
- **Zuhörer**: Spawner, PathMover, Gate, Collapse, ForceZone und Chaser haben optional das
  Attribut `ListenSignal`. Ist es gesetzt, warten sie auf dieses Signal statt dauerhaft zu laufen:
  Spawner = ein Burst pro Signal, PathMover = ein Durchgang, Gate = öffnet, Collapse = stürzt ein,
  ForceZone = `ActiveTime` Sekunden an, Chaser = Jagd beginnt.
- Mehrere Bausteine dürfen auf dasselbe Signal hören (z. B. Steinschlag + Schranke).
- Fehlersuche: `Config.Debug.Toolkit = true` → Output zeigt jedes Signal und wie viele reagieren.

### Reset bei R und T

| Baustein | T (kompletter Neustart) | R / Crash (Checkpoint) |
|---|---|---|
| TriggerZone | wieder scharf | wieder scharf (Steinschlag kommt beim nächsten Versuch wieder) |
| Spawner | alle Objekte weg | alle Objekte weg, Dauerbetrieb läuft weiter |
| PathMover / Gate (Signal) | zurück an den Start / zu | zurück an den Start / zu |
| PathMover / Gate (Takt) | läuft nach Serveruhr weiter | läuft weiter |
| Collapse | steht wieder | steht wieder (sonst kämst du nicht mehr rüber) |
| Prop | zurück an den Ursprung, Chaos 0 | bleibt liegen, Chaos bleibt (dein Lauf) |
| ForceZone (Signal) | aus | aus |
| Chaser | sofort zu Hause | sofort zu Hause |

### Spawner

| Attribut | Typ | Standard | Bedeutung |
|---|---|---|---|
| `Template` | Text | – | Vorlagen-Name(n), mehrere durch Komma |
| `Interval` / `IntervalRandom` | Zahl (s) | 3 / 1 | Abstand im Dauerbetrieb, zufällig bis zu so viel später |
| `Burst` | Zahl | 1 | Objekte pro Auslösung |
| `Speed` / `SpeedRandom` | Zahl (Studs/s) | 30 / 5 | Schwung Richtung Vorderseite, ± zufällig |
| `SpreadAngle` | Zahl (Grad) | 10 | Streuung der Richtung |
| `Spin` | Zahl (rad/s) | 0 | zufällige Drehung (Steine: 3–6) |
| `ScaleRandom` | NumberRange oder Zahl | 1 | z. B. NumberRange 0.8 – 1.3 (oder Zahl 0.2 = 0.8 – 1.2) |
| `Lifetime` | Zahl (s) | 12 | danach verschwindet das Objekt |
| `DespawnY` | Zahl | −100 | darunter verschwindet es auch |
| `MaxActive` | Zahl | 12 | höchstens so viele gleichzeitig |
| `ActiveRadius` | Zahl (Studs) | 400 | Dauerbetrieb nur, wenn dein Wagen näher ist |
| `Hazard` | Bool | false | true = Berührung ist ein Crash (`Message` = Text), false = nur Schubs |
| `Kinematic` | Bool | false | true = fährt stur geradeaus, ohne Schwerkraft (Autos) |
| `ListenSignal` | Text | – | pro Signal ein Burst statt Dauerbetrieb |

Das Spawner-Part ist der Spawn-**Bereich** (Objekte erscheinen zufällig innerhalb seiner Größe)
und im Spiel unsichtbar. Seine **Vorderseite** gibt die Richtung (Bau-Hilfe zeigt einen Pfeil).

### Bau-Beispiele

- **Steinschlag** (am Hang, ausgelöst):
  1. Vorlagen `Stein1`, `Stein2` (graue Bälle, 3–5 Studs) in `ReplicatedStorage/Templates`.
  2. Flaches, breites Part oben am Hang (z. B. 30 × 2 × 6), Vorderseite bergab, Tag `Spawner`.
     Attribute: `Template` = `Stein1, Stein2`, `ListenSignal` = `Steinschlag1`, `Burst` = 6,
     `Speed` = 25, `SpreadAngle` = 15, `Spin` = 4, `ScaleRandom` = 0.3, `Hazard` = true,
     `Message` = „Steinschlag!“.
  3. Quader quer über die Straße weiter oben, Tag `TriggerZone`, `Signal` = `Steinschlag1`.
- **Auto-Strom quer über eine Straße** (Dauerbetrieb): Vorlage `Auto_Rot` (Modell, Vorderseite
  vorne). Schmales Part am Straßenrand (z. B. 2 × 4 × 8) auf Autohöhe, Vorderseite über die
  Straße, Tag `Spawner`: `Template` = `Auto_Rot`, `Kinematic` = true, `Interval` = 3,
  `IntervalRandom` = 1, `Speed` = 40, `SpeedRandom` = 0, `SpreadAngle` = 0, `Lifetime` = 4
  (so lange, bis das Auto auf der anderen Seite ist), `Hazard` = false (schubst nur).
- **Lieferwagen auf Runde** (PathMover): Modell `Lieferwagen` mit Tag `PathMover`, darin ein
  Ordner `Waypoints` mit Parts `1`, `2`, `3`, `4` entlang der Straße (auf Höhe des Pivots).
  `Loop` = true, `Speed` = 20, `WaitAtPoints` = 1. Wichtig: Im Modell ein **PrimaryPart**
  setzen (oder *Edit Pivot*), sonst liegt der Pivot in der Mitte von Auto **und** Wegpunkten.
- **Bahnschranke** (Gate im Takt): Balken-Modell, Pivot (*Edit Pivot*) ans Scharnier,
  Tag `Gate`, `Angle` = 80, `Axis` = `Z`, `OpenTime` = 4, `ClosedTime` = 3.
- **Klappbrücke per Signal**: Brücke als Gate mit `Angle` = −60, `Axis` = `X`,
  `StartOpen` = true, `ListenSignal` = `Bruecke` → das Signal schließt sie.
- **Wackelige Holzbrücke**: Bretter einzeln mit Tag `Collapse`, `Delay` = 0.5 (vorne kürzer,
  hinten länger) – sie fallen nacheinander.
- **Marktstände**: Kisten/Pylonen mit Tag `Prop`.
- **Rasensprenger**: durchsichtiges blaues Part, Tag `ForceZone`, Vorderseite seitlich,
  `Strength` = 80, `Pulse` = 2.
- **Förderband**: Das Band selbst ist ein normales Part (Boden). Darauf ein eigenes,
  unsichtbares Part mit Tag `ForceZone` (z. B. 3 Studs hoch), Vorderseite in Laufrichtung.
  Eine ForceZone ist nie fest (man fährt hindurch) – deshalb nicht das Band selbst taggen.
- **Abkürzung mit Sprungfeder**: Eine Mauer (Part) quer über einen Seitenweg, Tag `UpgradeDoor`,
  `RequiredUpgrade` = `Spring`, `RequiredLevel` = 1. Ohne Sprungfeder: Schild „Abkürzung: nur mit
  Trampolin-Sprungfeder Stufe 1“. Nach dem Kauf fährt die Mauer sofort weg. Zum Testen ohne
  Kauf: `Config.Debug.AllUpgrades = true`. (Die Tür ist wie die anderen Bausteine nur bei dir
  offen; der Server prüft sie nicht – sie öffnet nur einen Weg, verteilt keine Belohnung.)
- **Hund**: Hunde-Modell (Pivot vorne = Schnauze), Tag `Chaser`, `Radius` = 35, `MaxSpeed` = 30.
  Mit `ListenSignal` startet er nur per Signal (der Radius zählt dann nicht).

## Bau-Hilfe (Studio-Plugin)

Zeigt beim **Bauen** (nicht im Spiel) Pfeile, Bereiche und Wege: Spawner (orange, mit
Streuung und Vorlagen-Namen), BoostPad/JumpPad (grün), StartZone-Vorderseite (weiß), Mover-Weg
(lila), PathMover-Wegpunkte (türkis, nummeriert), Gate offen (gelber Kasten), ForceZone (blau),
TriggerZone mit Signal-Namen (rot), Chaser-Radius (brauner Ring), „hört: Signal“-Hinweise.

**Installieren (einmalig):**
1. Studio schließen (empfohlen beim ersten Mal).
2. Terminal im Projektordner öffnen (dort, wo `plugin.project.json` liegt).
3. Ausführen:
   ```bash
   rojo build plugin.project.json --plugin GetToSchoolBauhilfe.rbxm
   ```
   Rojo legt die Datei direkt in deinen lokalen Studio-Plugin-Ordner
   (Windows: `%LOCALAPPDATA%\Roblox\Plugins`, Mac: `~/Documents/Roblox/Plugins`).
4. Studio öffnen → Reiter **Plugins** → Gruppe **Get to School** → Knopf **Bau-Hilfe**.
   Der Knopf schaltet die Anzeige an und aus (wird gespeichert).

**Aktualisieren** (wenn ich das Plugin geändert habe):
1. `git pull`
2. Denselben Befehl nochmal: `rojo build plugin.project.json --plugin GetToSchoolBauhilfe.rbxm`
3. Studio lädt lokale Plugins normalerweise automatisch neu. Falls nicht: Studio neu starten.

**Entfernen:** Plugins → *Plugins Folder* öffnen → `GetToSchoolBauhilfe.rbxm` löschen.

## Eigene Fahrzeug-Modelle

Die Fahrzeuge (Einkaufswagen, Bürostuhl, Schultisch auf Skateboard) sind Platzhalter aus
einfachen Parts. Die **Physik** (Boden, vier Kugel-Räder, unsichtbarer Ballast) baut immer das
Skript – mit den Werten aus `Config.Vehicles`. Dein Modell ist nur das **Aussehen** und wird
an den Boden geschweißt (wie ein Kind-Objekt ohne eigenen Rigidbody in Unity).

1. In Studio ein Model bauen (Parts, MeshParts, Decals – keine Skripte nötig).
2. **Pivot** setzen (*Model → Edit Pivot*): Mitte des Fahrzeugbodens, Vorderseite zeigt
   nach −Z (blauer Pfeil nach hinten = +Z). Größe passend zu `Width`/`Length` des Fahrzeugs
   in `Config.Vehicles` (z. B. Bürostuhl 3.2 × 3.2 Studs).
3. Model so benennen wie die Fahrzeug-Id (`ShoppingCart`, `OfficeChair`, `SchoolDesk`) und
   in einen Ordner `ReplicatedStorage/VehicleModels` legen (Rojo lässt ihn in Ruhe).
4. Lackiererei: Parts mit dem Attribut `Paint` (Bool) = true bekommen die gewählte Farbe.
5. Optional als Attribute am Model: `HideWheels` (Bool) = die Kugel-Räder unsichtbar machen
   (wenn dein Modell eigene Räder hat), `HideBase` (Bool) = den Boden unsichtbar machen.
   An einzelnen Parts: `Collide` (Bool) = dieses Teil stößt mit Hindernissen zusammen
   (sonst gehen alle Teile des Modells durch alles hindurch, nur die Physik-Teile stoßen).
6. Play: Das Modell ersetzt den Platzhalter. Alle Teile werden automatisch masselos, nicht
   verankert und an den Boden geschweißt; Skripte im Modell werden entfernt.

Fahrwerte ändern: `Config.Vehicles.<Id>` – `set` = fester Wert (z. B. Größe), `scale` =
Faktor auf den Einkaufswagen-Wert (z. B. `Drive.SteerRate = 1.6` = 60 % mehr Lenkung). Weil
die Faktoren auf die Einkaufswagen-Werte wirken, bleiben die Fahrzeuge im Verhältnis gleich,
wenn du den Einkaufswagen tunst. Neues Fahrzeug: Eintrag in `Config.Vehicles` und die Id in
`Order` aufnehmen.

## Zweiten Track anlegen

Mehrere Strecken liegen im selben Place. Jede Strecke ist ein **Model** mit dem Attribut
`TrackId`; alles, was zu ihr gehört, liegt darin.

1. **Bestehenden Track einpacken** (einmalig): Alle Teile deiner ersten Strecke (StartZone,
   FinishZone, Checkpoints, Bausteine, Straße) markieren → Rechtsklick → *Group* (Strg+G).
   Das Model z. B. `Track1` nennen und das Attribut `TrackId` (Text) = `Track1` setzen.
   Das Attribut `TrackId` an der StartZone wird dann nicht mehr gebraucht. (Ohne diesen
   Schritt funktioniert der alte Track weiter als „lose“ Strecke, solange kein Model die
   gleiche TrackId hat.)
2. **Neuen Track bauen**: neues Model, z. B. `Track2`, Attribut `TrackId` = `Track2`. Darin
   eine eigene `StartZone`, `FinishZone` (mit `Grade6` … `Grade2`) und eigene `Checkpoint`s
   (Tag oder Name, wie gewohnt). Bausteine (Pads, Münzen, Kühe, Hindernisse) gehen überall.
3. **Name und Bedingung** in `src/shared/Config.luau` unter `Config.Tracks` eintragen:
   ```lua
   { id = "Track2", name = "Die Abkuerzung", unlock = { track = "Track1", grade = 4, price = 250 } },
   ```
   - kein `unlock` = von Anfang an frei
   - `track` + `grade` = frei, sobald man auf dieser Strecke mindestens diese Note hat
   - `price` = im Menü für Münzen freischaltbar
   - beides = was zuerst erfüllt ist
   Strecken ohne Eintrag sind frei (Name: Attribut `TrackName` am Model oder die TrackId).
4. **Testen**: Play → **B** → Reiter *Strecken* → *Fahren*. Der Wagen wird an den Start des
   Tracks gesetzt. Bestzeiten, Noten und Checkpoints gelten pro Strecke.

Tipp: Die Strecken dürfen weit auseinander liegen (bei StreamingEnabled lädt der Server die
neue Startgegend vor dem Wechsel). Neue Spieler starten auf der ersten freien Strecke aus
`Config.Tracks`.

## Speichern (Spielstand)

Gespeichert wird pro Spieler in einem DataStore (`Config.Save.StoreName`): Münzen, gekaufte
Upgrades mit Stufe, Bestzeiten und beste Noten pro Strecke, freigeschaltete Strecken und
Fahrzeuge, Flug-Rekorde. Das Format hat eine Versionsnummer (`SaveData.VERSION`); alte
Spielstände werden beim Laden automatisch umgestellt (die Bestzeiten von vor M3 werden
einmalig übernommen).

- **In Studio**: Damit wirklich gespeichert wird: *Game Settings → Security → „Enable Studio
  Access to API Services“*. Ohne das (oder bei einem unveröffentlichten Place) wird
  automatisch ein Speicher im Arbeitsspeicher benutzt: Alles funktioniert, ist aber nach
  Stop weg. Im Output steht dann eine Warnung, oben erscheint ein kurzer Hinweis.
- **Fehler**: Laden und Speichern werden bei Fehlern wiederholt (`Config.Save.Retries`).
  Klappt das Laden gar nicht, wird für diesen Spieler in dieser Sitzung **nicht** gespeichert,
  damit der echte Spielstand nicht überschrieben wird.
- Gespeichert wird alle 60 s (wenn sich etwas geändert hat), nach Käufen, beim Verlassen und
  beim Herunterfahren des Servers.
- **Serverwechsel**: Der Spielstand merkt sich, welcher Server ihn gerade benutzt
  (Sitzungs-Sperre). Wechselt ein Spieler schnell den Server, wartet der neue kurz, bis der
  alte fertig gespeichert hat. So überschreibt nie ein alter Stand einen neueren.

## M1 testen

Seit M2 gilt: **R** = zurück zum letzten Checkpoint (ohne Checkpoint: zum Start), **T** =
kompletter Neustart; der Timer zeigt Minuten, Sekunden und Hundertstel.

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
| Drift | Bei Tempo lenken und **Shift** halten (Gamepad B, Touch: Button „Drift“) | Die Front zieht den Wagen durch die Kurve, das Heck schwingt aus. Reifenspuren erscheinen und verblassen nach ~3 s (Details siehe „Feedback-Runde“ unten) |
| Boost-Ladung | Lange driften (über 25 Studs/s, Driftwinkel über 12°) | Funken an den Hinterrädern: hell → nach 1 s blau (Stufe 1) → nach 2 s orange (Stufe 2) |
| Boost | Shift nach blauen/orangen Funken loslassen | Kurzer Schub nach vorne (+15 % / +25 % des Höchsttempos), am Tacho sichtbar |
| Kein Farmen | Im Stand Shift halten und lenken | Keine Funken, kein Boost |
| Ladung weg | Mit Ladung crashen, R drücken oder aussteigen | Boost-Ladung ist danach leer |
| ShiftLock | Im Wagen Shift drücken, dann aussteigen | ShiftLock wurde durch das Driften nicht umgeschaltet |
| Tacho | Fahren | Unten Mitte: km/h und Balken (grün → rot). Nur sichtbar, solange man fährt |
| Kamera-Wackeln | Schnell fahren (über ~60 Studs/s) / von einer Rampe springen | Leichtes Zittern bei Tempo, kurzes stärkeres Wackeln bei harter Landung |
| Tuning-Panel | In Studio **F2** | Panel links mit Schiebereglern; Änderungen wirken sofort. „Kipp-Ballast“ verschiebt das Gewicht im Wagen (höher = kippeliger) |
| Werte kopieren | Im Panel auf „Werte kopieren“ klicken | Im Output-Fenster stehen nur die geänderten Werte (siehe „Tuning-Ablauf“) |

## M2 testen

| Funktion | Was du tun kannst | Was passieren sollte |
|---|---|---|
| Timer | Play, losfahren | Oben steht 0:00.00, ab Verlassen der Startzone zählt er mit Hundertstelsekunden hoch |
| Ziel | In die Zielzone fahren | Ergebnis-Screen: „ZIEL!“, Zeit, Bestzeit mit Abstand, Note (6 = beste) |
| Neue Bestzeit | Schneller als bisher ins Ziel | Titel „NEUE BESTZEIT!“ in Gold, alte Bestzeit und Verbesserung; unter dem Timer steht die neue Bestzeit |
| Eigene Noten | Attribut `Grade6` = 45 (Zahl) an der FinishZone | Note 6 nur noch bis 45 s |
| Checkpoint | Durch einen `Checkpoint` fahren | Hinweis „Checkpoint!“ (beim ersten Lauf) bzw. „Checkpoint −0.45“ grün / „+1.20“ rot im Vergleich zur Bestzeit |
| Zurück zum CP | Nach dem Checkpoint crashen oder R | Wagen steht am Checkpoint in Fahrtrichtung, Zeit läuft weiter. Ergebnis: „Mit Checkpoint-Neustart“ |
| Komplett neu | T (Gamepad: Steuerkreuz hoch, Touch: „Start“) | Wagen am Start, Timer 0:00.00, neue Zufallsereignisse |
| Reihenfolge | Checkpoints mit `Order` 1 und 2; erst 2, dann 1 durchfahren | Bei 1: „Falscher Checkpoint“, R bringt dich zu 2 |
| BoostPad / JumpPad | Drüberfahren | Schub nach vorne bzw. Sprung; Landung nach JumpPad ist kein Crash (außer extrem hart) |
| Mud / Ice | Hineinfahren | Schlamm bremst stark, Drift-Funken stoppen. Eis: Wagen rutscht, lenkt kaum |
| Bouncy | Mit Tempo gegen eine Bouncy-Wand | Wagen prallt ab, kein Crash |
| Hazard | In einen Hazard fahren | Sofort „CRASH!“ mit dem Text aus `Message` |
| Mover / Spinner / Pendulum | Hinfahren und anfahren lassen | Bewegung ist flüssig, der Wagen wird weggeschoben (oder crasht bei hartem Treffer), fährt nicht hindurch |
| RandomEvent | Part mit `Chance` 0.5; mehrmals T | Mal da, mal weg (unsichtbar und durchfahrbar) |
| Gruppe | 3 Parts mit `Group` = „A“; mehrmals T | Immer genau eins sichtbar |
| Sounds | IDs in `Config.Sounds` eintragen | Rollen (Tonhöhe nach Tempo), Drift-Quietschen, Boost, Crash, Checkpoint, Ziel. Leere IDs: kein Ton, kein Fehler im Output |
| Tuning-Panel | F2 | Neue Regler: Schlamm-Bremse, Eis-Seitenhalt, BoostPad-/JumpPad-Stärke; Panel scrollt |

## Feedback-Runde testen (nach M2)

| Funktion | Was du tun kannst | Was passieren sollte |
|---|---|---|
| Lenkung | A/D ohne Shift | Nur noch leichte Korrekturen (60 % der alten Stärke) |
| Drift | Bei Tempo Shift halten und lenken | Front zieht den Wagen durch die Kurve, Heck schwingt weich aus (max. ~30°), leicht unruhig. **Kein Dreher**, auch nicht bei langem Driften |
| Drift loslassen | Shift loslassen | Heck kommt weich zurück, der Wagen fährt gerade weiter |
| Hopp | **Leertaste** (Gamepad A, Touch: Button „Hopp“) | Kleiner Sprung (ca. 1 Stud); in der Luft dreht der Wagen schnell in Lenkrichtung. Shift löst keinen Hopp mehr aus |
| Driftwechsel | Im Linksdrift Shift halten, D drücken, Leertaste | Hopp mit schneller Drehung nach rechts, Landung direkt im Rechtsdrift |
| Flach fahren | Auf ebener Strecke W halten | Deutlich schnellere Beschleunigung, Motor-Höchsttempo ca. 60 Studs/s (≈ 60 km/h) |
| Bergab mit W | Rampe hinunter, W halten | Wird schneller als 60 Studs/s, kein Abbremsen (nur leichter Luftwiderstand) |
| Ausrollen | Nichts drücken | Wagen wird langsam weniger schnell |
| Bremsen | S halten | Kräftiges Bremsen, im Stand rückwärts |
| Losfahren | Einsteigen (E) oder T, dann W | Kein Links-rechts-Wackeln mehr; das Wackelrad setzt erst ab ~12 Studs/s weich ein |
| BoostPad | Über ein BoostPad fahren | Schub nach vorne, **kein Crash** |
| Falsches Attribut | `Strength` als Text („40“) oder gar nicht setzen | Pad nutzt den Standardwert, im Output steht einmal eine Warnung mit dem Part-Namen |
| JumpPad / Drift-Boost | Drüberfahren / Boost auslösen | Kein „Harter Aufprall“ durch den eigenen Schub |
| Bestzeit speichern | Ziel erreichen, Studio stoppen, wieder Play | Bestzeit ist noch da. Voraussetzung in Studio: *Game Settings → Security → Enable Studio Access to API Services*. Sonst Warnung im Output und Bestzeit nur für die Sitzung |
| Tuning-Panel | F2 | Neue Regler: Hoechsttempo (Motor), Bremskraft, Ausrollen, Drift-Seitenhalt, Drift-Lenkung, Max. Driftwinkel, Rueckstell-Staerke, Heck-Pendeln, Hopp-Hoehe, Hopp-Drehung |

## Test nach zweitem Feedback (BoostPad, JumpPad, Tuning-Panel)

| Funktion | Was du tun kannst | Was passieren sollte |
|---|---|---|
| BoostPad | Über ein flaches, bündiges BoostPad fahren | Spürbarer Schub nach vorne (+40 Studs/s Standard) |
| Debug-Modus | `Config.Debug.TrackPieces = true`, Play, über Pads fahren | Output: „Bodenbausteine in der Welt: BoostPad 1, …“, „Rad WheelFL erkennt: BoostPad "…"“ und „BoostPad "…" ausgeloest: +40 Studs/s (Standardwert), Richtung passt zur Fahrtrichtung“ |
| Falsche Richtung | Pad um 180° drehen, drüberfahren (Debug an) | Wagen wird gebremst/zurückgeschoben; Output warnt „Pad zeigt nicht in Fahrtrichtung“ |
| Mud / Ice bündig | Schlamm- oder Eis-Part bündig in die Straße legen | Wird erkannt (bremst bzw. rutscht) |
| JumpPad | Über ein JumpPad fahren | Höherer Sprung als vorher (ca. 19 statt 12 Studs) |
| Regler-Mitte | F2 | Jeder Regler steht in der Mitte (weißer Strich), rechts daneben der Wert aus der Config |
| Schieben | Regler ziehen | Zahl ändert sich live (gelb = geändert), Wirkung sofort |
| Eingabe | In das Feld „Wert“ eine Zahl tippen (auch außerhalb des Bereichs, Komma oder Punkt), Enter | Wert wird übernommen, Regler steht am Rand, wenn außerhalb |
| Zurücksetzen | Knopf „R“ neben einem Regler | Wert zurück auf den Config-Wert, Regler wieder in der Mitte |
| Werte kopieren | Ein paar Werte ändern, „Werte kopieren“ | Output zeigt nur die geänderten, z. B. `Drift.LateralGrip: 3.5 -> 4.2`; ohne Änderung „Keine Aenderungen.“ |

## Test nach drittem Feedback (Drift als Standard, Boost, Drall)

| Funktion | Was du tun kannst | Was passieren sollte |
|---|---|---|
| Drift als Standard | Ohne Shift bei Tempo lenken | Wagen driftet: Front zieht, Heck schwingt aus |
| Normal fahren | **Shift** halten und lenken (Gamepad B, Touch: Button „Normal“) | Fester Seitenhalt, schwächere Lenkung wie früher ohne Shift |
| Geradeaus | Ohne Lenken bergab rollen | Keine Reifenspuren, kein Quietschen, kein zusätzliches Bremsen |
| Reifenspuren | Im Drift durch eine Kurve fahren | Schwarze Spuren nur, solange der Wagen seitlich rutscht (ab 8°) |
| Boost auslösen | Lange driften (Funken blau/orange), dann geradeaus lenken **oder** Shift drücken | Nach ca. 0.25 s gerade: deutlicher Schub (+24 / +42 Studs/s), Sichtfeld zieht kurz auf |
| Driftwechsel | Im Linksdrift D drücken und Leertaste | Hopp, Landung im Rechtsdrift, Ladung (Funkenfarbe) bleibt erhalten |
| Drall | 20 s geradeaus fahren | Nur noch leichtes Ziehen nach links/rechts; mit Regler „Wackelrad (Drall)“ = 0 ganz weg |
| Panel | F2 | Neue Regler: Drift-Boost Stufe 1/2, Drift-Boost Dauer, Drift-Ende, Wackelrad (Drall) |
| Hopp | Leertaste | Höher als vorher (ca. 3.5 Studs), langsamere Luft-Drehung (Werte aus dem Screenshot) |

Zurück zum alten Verhalten (Shift = Drift, Loslassen = Boost): `Config.Drift.DriftByDefault = false`.

## M3 testen (Progression)

**Schnelltest ohne Shop:** `Config.Debug.AllUpgrades = true` gibt dir alle Upgrades auf
höchster Stufe. Debug-Schalter wirken nur in Studio; im veröffentlichten Spiel schaltet
`Config.luau` sie automatisch aus. Für den echten Ablauf trotzdem wieder auf `false`.

| Funktion | Was du tun kannst | Was passieren sollte |
|---|---|---|
| Münze | Part mit Tag `Coin` auf die Straße, durchfahren | Münze dreht/wippt, verschwindet mit kleinem Aufsteigen, oben rechts „+1“ und der Zähler hüpft |
| Münzen bleiben | Münze einsammeln, dann crashen bzw. R | Zähler bleibt, Münze bleibt weg |
| Keine Münzen bei T | Münze sammeln, T | Münze bleibt weg (kein „Farmen“ am Start) |
| Münzen zurück | Ins Ziel fahren | Die eingesammelten Münzen dieser Strecke sind wieder da, Zähler bleibt |
| Zielbelohnung | Ins Ziel fahren | Ergebnis: „Münzen: +X im Ziel (10 + Notenbonus)“, Zähler zählt hoch |
| Speichern | Studio-API-Zugriff an, Münzen sammeln, Stop, Play | Münzen sind noch da |
| Ohne API-Zugriff | API-Zugriff aus, Play | Warnung im Output „nur im Arbeitsspeicher“, kurzer Hinweis oben; alles funktioniert |
| Leben | Oben rechts | 5 rote Schulranzen |
| Crash kostet Leben | Umkippen/Hazard | Ein Ranzen wird grau und wackelt, „-1 Leben“, Figur fliegt weit mit Luftspur |
| Game Over | 5x crashen | „NACHSITZEN!“ o. ä. wackelt, lustiger Text, Zahlen; nach ~4.5 s Neustart, T sofort; R tut nichts |
| Leben auffüllen | T | Wieder 5 Ranzen |
| Ohne Checkpoint | Vor dem ersten Checkpoint crashen | Zurück zum Start, Zeit und Leben laufen weiter (kein kompletter Neustart) |
| Launchable | Kuh (Tag `Launchable`) umfahren | „BONK!“ am Treffpunkt, kurzer Stillstand (~0.15 s), Kamera wackelt, Wagen fährt weiter, Kuh fliegt drehend mit Luftspur, oben „Kuh: … m“ zählt hoch, ein Leben weg |
| Himmelsflug | `SkyChance` = 1 an der Kuh | Kuh schießt nach oben, verschwindet mit Stern-Blinken, „Ab ins All!“ |
| Rekord | Gleiche Kuh weiter wegschleudern | „NEUER REKORD!“, Menü B → Rekorde zeigt den Wert |
| Ergebnis | Mit Treffern ins Ziel | Leben übrig, getroffene Objekte, weitester Flug |
| Shop | Am Start **B** | Menü „Pausen-Kiosk“, Upgrades mit Stufe, Beschreibung, Preis |
| Shop gesperrt | Losfahren, dann B | Hinweis „nur vor oder nach einem Lauf“; das Menü schließt beim Losfahren |
| Kaufen | Genug Münzen, *Kaufen* | „Gekauft: …“, Münzen weniger, Stufe +1; bei zu wenig Münzen Hinweis |
| Sprungfeder 1 | Leertaste | Deutlich höherer Sprung (ca. 9 Studs) statt Hopp |
| Sprungfeder 2 | In der Luft nochmal Leertaste | Doppelsprung mit Ring-Effekt, einmal pro Sprung |
| Fahrradhelm | Mit Helm crashen | „HELM!“, kein Leben weg, Helm-Symbol wird grau. Umgekippt: Wagen steht wieder; Aufprall: weiterfahren; Hazard: zum Checkpoint |
| Helm laden | Nach Rettung durch einen neuen Checkpoint | Helm-Symbol wieder blau |
| Turbo | **F** (Gamepad RB) | Schub, Krümel-Wolke, Sichtfeld zieht auf; unten links Abklingzeit, erneut F: „noch nicht verdaut“ |
| Fallschirm | Springen, Leertaste halten | Schirm über dem Wagen, langsames Fallen, gleitet weiter, A/D lenkt |
| Ability-Anzeige | Unten links | Pro gekaufter Ability: Name, Taste, Zustand, Balken |
| Zweiter Track | Siehe „Zweiten Track anlegen“; B → Strecken | Gesperrte Strecke zeigt Bedingung; nach Note 4 auf Track1: Meldung „Neue Strecke freigeschaltet“; *Fahren* setzt dich an deren Start |
| Tests | `lune run tests/run` | alle Tests bestanden |

## M2.5 testen (erweiterter Baukasten)

Vorher: Plugin installieren (siehe „Bau-Hilfe“), `ReplicatedStorage/Templates` mit ein, zwei
Vorlagen anlegen. Für Signale hilft `Config.Debug.Toolkit = true`.

| Funktion | Was du tun kannst | Was passieren sollte |
|---|---|---|
| Rojo | `rojo serve`, verbinden, Templates-Ordner anlegen, etwas in `src` ändern | Templates-Ordner bleibt erhalten |
| Bau-Hilfe | Plugin an, Spawner/TriggerZone/PathMover setzen | Pfeile, Kästen, Wegpunkt-Nummern; im Play-Test nichts davon |
| TriggerZone | Zone mit `Signal` = „Test“, durchfahren (Debug an) | Output: „Signal "Test" ausgelöst … N Baustein(e) reagieren“ |
| Once / Cooldown | `Once` = true, zweimal durchfahren | Nur beim ersten Mal; nach R oder T wieder |
| Steinschlag | Beispiel oben bauen, Trigger durchfahren | Steine kommen den Hang herunter, Treffer = „Steinschlag!“-Crash, ein Leben weg |
| Auto-Strom | Beispiel oben | Autos fahren gleichmäßig quer, schubsen den Wagen (kein Crash durch harten Stoß) |
| Gleiche Sicht | 2 Spieler (*Test → 2 Players*), Auto-Strom | Beide sehen die Autos an derselben Stelle |
| Fehlende Vorlage | Falschen Namen bei `Template` | Graue Kugel + Warnung im Output |
| R / T | Während Steine fallen R drücken | Alle gespawnten Objekte verschwinden |
| PathMover | Modell mit `Waypoints` 1–4 | Fährt die Punkte ab, dreht sich in Fahrtrichtung, schiebt den Wagen weg |
| Gate (Takt) | Schranke mit `Angle` | Öffnet/schließt im Takt, schiebt/blockiert den Wagen |
| Gate (Signal) | `ListenSignal` + TriggerZone | Öffnet beim Durchfahren; nach R/T wieder zu |
| Collapse | Brücke befahren | Wackelt, stürzt ab; nach R steht sie wieder |
| Prop | Kisten umfahren | Fliegen weg, kein Crash; Ergebnis: „Chaos: X“; R: liegen noch, T: wieder ordentlich |
| ForceZone | Wind-Zone durchfahren | Wagen wird seitlich gedrückt; mit `Pulse` im Takt |
| Chaser | In den Radius des Hundes fahren | Hund rennt hinterher, gibt nach ~6 s auf, läuft heim; R/T: sofort zu Hause |
| UpgradeDoor | Tür mit `RequiredUpgrade` = `Spring` | Ohne Upgrade: Schild „nur mit Trampolin-Sprungfeder“, Tür fest. Sprungfeder kaufen (B): Tür fährt weg |
| Tests | `lune run tests/run` | alle Tests bestanden (aktuell 143) |

### Wichtigste Studio-Tests M3/M2.5 (nach Wichtigkeit)

1. **Spiel startet ohne Fehler**: Play, Output auf rote Fehler prüfen; Wagen steht am Start,
   Münzzähler, 5 Schulranzen, Shop-Knopf sind sichtbar.
2. **Fahren wie vorher**: Drift, Hopp, Crash, R/T funktionieren unverändert.
3. **Crash und Leben**: Crash kostet genau ein Leben, Ragdoll fliegt, danach Checkpoint;
   bei 0 Leben Game Over und Neustart.
4. **Münzen**: einsammeln, nach Crash behalten, bei T weiter weg, nach dem Ziel wieder da,
   Ziel-Belohnung.
5. **Speichern**: mit API-Zugriff Münzen sammeln → Stop → Play → noch da. Ohne API-Zugriff:
   Warnung, aber keine Fehler.
6. **Launchable**: Kuh umfahren – Wagen fährt weiter (kein Crash!), Kuh fliegt, Leben weg.
7. **Shop**: kaufen, Münzen werden abgezogen, nur außerhalb eines Laufs.
8. **Abilities** (mit `Debug.AllUpgrades`): Sprung, Doppelsprung, Helm-Rettung (alle vier
   Crash-Arten), Turbo, Fallschirm.
9. **Zweiter Track**: anlegen, freischalten, wählen, Checkpoints und Ziel funktionieren dort.
10. **Zwei Spieler** (*Test → 2 Players*): Münzen und Kühe verschwinden nur beim Sammler.

## M4 testen (Wiederspielwert)

| Funktion | Was du tun kannst | Was passieren sollte |
|---|---|---|
| Geist (erster Lauf) | Strecke einmal bis ins Ziel fahren | Noch kein Geist zu sehen (es gibt noch keine Bestzeit) |
| Geist (Bestzeit) | Nach der ersten Zielankunft T drücken und losfahren | Halbdurchsichtiger blauer Wagen mit „Geist 0:52.10“ fährt deinen besten Lauf nach |
| Geist (schneller) | Schneller als der Geist fahren, Ziel | Ab dem nächsten Lauf fährt der neue, schnellere Geist |
| Geist (langsamer) | Langsamer fahren, Ziel | Geist bleibt der alte |
| Geist (Abbruch) | Während des Laufs T, E (Aussteigen) oder Game Over | Geist verschwindet sofort, startet beim nächsten Lauf neu |
| Geist (Speichern) | Mit API-Zugriff: Bestzeit fahren, Stop, Play, losfahren | Geist ist wieder da (aus dem DataStore) |
| Geist (2 Spieler) | *Test → 2 Players* | Jeder sieht nur seinen eigenen Geist |
| Geist (Durchsicht) | F2 → „Geist-Durchsicht“ | Wagen wird beim nächsten Start durchsichtiger/fester |
| Bestenliste (Menü) | B → „Bestenliste“ | Knöpfe für jede Strecke und „Weitester Kuh-Wurf“, darunter Global / Server / Freunde. Liste Top 10, unten „Dein Platz“ |
| Bestenliste (Eintrag) | Strecke ganz fahren, B → Bestenliste | Deine Zeit steht drin (grün hinterlegt). In Studio landen Tests in eigenen Listen (`…_Studio`), ohne API-Zugriff nur im Arbeitsspeicher |
| Bestenliste (Kuh-Wurf) | Kuh umfahren, B → Bestenliste → Weitester Kuh-Wurf | Deine Weite steht drin |
| Plausibilität (Checkpoint) | Im Play-Test (Server-Ansicht) Checkpoint 2 im Explorer neben die Straße schieben, dann ins Ziel fahren | Ergebnis: „Nicht in der Bestenliste: Checkpoint ausgelassen“, persönliche Bestzeit zählt trotzdem |
| Plausibilität (Mindestzeit) | `Config.Tracks` → Track1 `minTime = 200`, Lauf beenden | „Nicht in der Bestenliste: Zu schnell für diese Strecke“ |
| Server / Freunde | *Test → 2 Players*, beide fahren ins Ziel | „Server“ zeigt beide; „Freunde“ in Studio: „Keine Freunde gefunden“ |
| Brett in der Welt | Teststrecke, Schulwand (Station 26) | Tafeln zeigen Top 10, „Du: Platz …“; nach einem neuen Eintrag spätestens nach 60 s aktuell |
| Hausaufgaben (Menü) | B → „Hausaufgaben“ | 3 Aufgaben mit Text, Balken, „0 / 5“, Belohnung; unten Bonus und „Neue Hausaufgaben in … Std“ |
| Hausaufgaben (Fortschritt) | Passend zur Aufgabe fahren (Kuh umfahren, driften, Münzen sammeln, Lauf beenden) | Balken füllt sich; bei „erledigt“ grüner Hinweis „Hausaufgabe erledigt: … +60“, Münzen steigen |
| Hausaufgaben (Bonus) | Alle drei erledigen | Hinweis „Alle Hausaufgaben erledigt! Bonus +50“ |
| Hausaufgaben (Tageswechsel) | `Config.Homework.ResetHourUtc` auf die nächste volle UTC-Stunde stellen, Play, bis dahin im Spiel bleiben | Nach dem Wechsel neue Aufgaben (innerhalb von 30 s), Hinweis „Neue Hausaufgaben!“ |
| Hausaufgaben (Drift) | Aufgabe „Drifte 30 Sekunden“ (ggf. im Pool `weight` der anderen auf 0) | Balken steigt während Kurven-Drifts im Lauf, alle 5 s |
| Garage | B → „Garage“ | Drei Fahrzeuge mit Beschreibung und Balken (Tempo, Wendigkeit, Stabilität); Einkaufswagen „Gewählt“ |
| Fahrzeug kaufen | Mit genug Münzen „Kaufen 400“ beim Bürostuhl (oder `Debug.AllUpgrades`) | Münzen weg, Hinweis „Gekauft“, neuer Wagen steht am Start |
| Bürostuhl | Fahren | Dreht sehr schnell, wendig, kippt in scharfen Kurven/bei Sprüngen leichter um |
| Schultisch | Fahren | Deutlich schneller auf Geraden, lenkt träge, kippt kaum |
| Fahrzeug wechseln | Garage → „Wählen“ beim Einkaufswagen | Zurück im Einkaufswagen am Start |
| Speichern | Fahrzeug wählen, Stop, Play | Startet im zuletzt gewählten Fahrzeug |
| Geist mit Fahrzeug | Mit dem Schultisch Bestzeit fahren, T | Geist hat die Größe des Schultischs |
| Fahrzeug-Tuning | F2 → „Buerostuhl: Lenkung x“ usw. | Wirkt sofort auf den gefahrenen Wagen |
| Lackiererei | B → „Lackiererei“ | Farbkacheln (Original, Rot, Blau gratis; andere mit Preis), darunter Spuren |
| Farbe | „Feuerwehrrot“ klicken | Korb des Wagens wird rot (sieht man hinter dem Menü), Kachel hat Rahmen |
| Farbe pro Fahrzeug | Garage → Bürostuhl, Lackiererei → Blau; zurück zum Einkaufswagen | Einkaufswagen bleibt rot, Bürostuhl ist blau |
| Spur | Mit genug Münzen „Kreidestaub“ kaufen, fahren | Weißes Band hinter dem Wagen; andere Spieler sehen es auch. „Keine“ schaltet ab |
| Speichern | Farbe/Spur wählen, Stop, Play | Wagen hat wieder Farbe und Spur |
| Erfolg (Popup) | Ersten Lauf beenden | Oben fährt ein goldenes Popup herein: „Erfolg freigeschaltet! Pünktlich!“, bleibt 4 s |
| Mehrere Erfolge | Erster Lauf ohne Lebensverlust | Zwei Popups nacheinander („Pünktlich!“, „Ohne Kratzer“) |
| Kuh im Weltall | Mülltonne auf der Teststrecke (fliegt ins All, Station 13) | „Erste Kuh im Weltall“ |
| Erfolge (Menü) | B → „Erfolge“ | „X von 12 Erfolgen“, erreichte golden mit 🏆, andere mit 🔒 und Fortschritt „3 / 25“ |
| Speichern | Stop, Play | Erreichte Erfolge bleiben, kein zweites Popup |
| Badges | Badge im Creator Dashboard anlegen, Id in `Config.Achievements.List` (`badge`) eintragen, im veröffentlichten Spiel freischalten | Roblox-Badge wird vergeben (in Studio nur mit echtem Spieler, Testspieler werden übersprungen) |
| Einstellungen | B → „Einstellungen“ | Musik/Effekte mit −/+ (10-%-Schritte), Kamera-Wackeln und Geist An/Aus, „Hinweise nochmal zeigen“, Steuerungstabelle (Spalte deines Geräts gelb) |
| Lautstärke | Effekte auf 0 % | Keine Geräusche mehr (Musik bleibt); Musik braucht eine Id in `Config.Sounds.Music` |
| Kamera-Wackeln aus | Aus, dann schnell fahren / hart landen | Kamera bleibt ruhig |
| Geist aus | Aus, T, losfahren | Kein Geist; wieder an: beim nächsten Start da |
| Einstellungen speichern | Etwas umstellen, Stop, Play | Einstellungen sind wieder so |
| Einstiegs-Hinweise | Neuer Spielstand (oder „Nochmal zeigen“, oder `Debug.ShowHintsAlways`), losfahren | Unten „💡 Los geht's!“ (Gas/Lenken), nach ~7 s „Driften“, beim ersten Crash „Hingefallen? …“; je nur einmal |
| Hinweise je Gerät | Mit Gamepad losfahren | Texte nennen RT/LT/Stick/Y statt W/S/R |
| Gamepad fahren | Gamepad anschließen: RT Gas, LT Bremse, linker Stick lenken (oder nach vorne = Gas) | Wagen fährt und lenkt analog; B = normal fahren, A = Hopp, Y = Checkpoint, Steuerkreuz hoch = Neustart, Select = Menü |
| Touch fahren | Studio: *Test → Device* (Handy) | Joystick links: Gas/Lenken; Knöpfe Hopp, Normal, R, Start, Raus, Turbo, Shop; Hilfezeile unten ausgeblendet. Prüfen: Knöpfe überlappen nicht |
| Menü mit Gamepad | Select, dann Steuerkreuz/Stick | Knöpfe lassen sich auswählen, A drückt; Reiter oben scrollen mit |

### Wichtigste Studio-Tests M4 (nach Wichtigkeit)

1. **Spiel startet ohne Fehler**: Play, Output auf rote Fehler prüfen (viele neue Module).
   Menü (B) hat die Reiter Upgrades, Strecken, Rekorde, Bestenliste, Hausaufgaben, Garage,
   Lackiererei, Erfolge, Einstellungen.
2. **Fahren wie vorher** (Einkaufswagen): Drift, Hopp, Boost, Crash, R/T – die Fahrphysik
   liest jetzt Werte pro Fahrzeug, muss sich aber gleich anfühlen.
3. **Gamepad und Touch fahren** (neu, vorher ging das gar nicht): RT/LT/Stick bzw. Joystick.
4. **Spielstand**: Stop/Play – Münzen, Fahrzeug, Farbe, Einstellungen, Erfolge bleiben;
   alte Spielstände (Version 1) laden ohne Fehler (werden zu Version 2).
5. **Fahrzeuge**: Bürostuhl und Schultisch kaufen/wählen (oder `Debug.AllUpgrades`),
   fahren sich deutlich anders, steigen sauber ein, Ausstieg landet daneben.
6. **Geist**: nach einer Bestzeit fährt er beim nächsten Lauf mit; aus in den Einstellungen.
7. **Bestenliste**: Zeit erscheint (Studio: Liste `…_Studio` bzw. Arbeitsspeicher); Tafel an
   der Schulwand; unplausibler Lauf zeigt den Grund im Ergebnis.
8. **Hausaufgaben**: Fortschritt steigt, Belohnung und Bonus kommen.
9. **Erfolge**: Popup beim ersten Lauf, Liste im Menü.
10. **Lackiererei**: Farbe pro Fahrzeug, Spur sichtbar (auch für einen zweiten Spieler).
11. **Einstiegs-Hinweise**: erscheinen einmal, „Nochmal zeigen“ funktioniert.

## M5 testen (Spaß-Extras)

| Funktion | Was du tun kannst | Was passieren sollte |
|---|---|---|
| Lufttrick | Teststrecke Station 3 (JumpPad) oder Testfläche → Trick-Schanze links; in der Luft E halten | Wagen dreht sich nach rechts (Q = links), Taste los = Drehung hört auf |
| Saubere Landung | Nach ~360° loslassen, gerade landen | Groß „360° SAUBER! +6“, Münzen steigen (nur während eines Laufs) |
| Wackelig | Mit ~45° Schräglage landen | „360° ... wackelig!“, keine Münzen, kein Crash |
| Schief gelandet | Quer (90°) landen | „SCHIEF GELANDET!“ + Crash, ein Leben weg; mit Helm: „HELM!“, Wagen dreht in Fahrtrichtung |
| E am Boden | Am Boden E | Aussteigen wie immer |
| Normaler Sprung | JumpPad ohne Q/E | Keine Trick-Anzeige, normale Landung |
| Gamepad / Touch | LB bzw. Knopf „Trick“ in der Luft | Dreht in Lenkrichtung (ohne Lenkung: rechts) |
| Spam-Schutz | Viele Tricks schnell hintereinander | Höchstens 90 Trick-Münzen pro Minute (`Config.Tricks.MaxCoinsPerMinute`) |
| Tuning | F2 → „Trick-Drehtempo“, „Trick: sauber bis“, „Trick: Crash ab“ | Wirkt sofort |
| Kuh-Kombo | Testfläche → Kuh-Reihe (4 Kühe), alle in einem Rutsch umfahren | Ab der 2. Kuh groß „2x KOMBO! +…“, dann 3x, 4x (Farbe wird wärmer), Zeitbalken läuft ab; Kamera wackelt stärker |
| Kombo-Bonus | Münzzähler beobachten | Pro Treffer: Flugbonus × Multiplikator + 4 pro Stufe (`Config.Combo`) |
| Kombo vorbei | 3 s Pause, nächste Kuh | Wieder ohne Kombo (1x) |
| Erfolge | 3x Kombo / 720er sauber | „Kuh-Lawine“ bzw. „Wirbelwind“ |
| Glücksrad | B → „Gluecksrad“ → „Drehen! (gratis)“ | Rad dreht sich ~4 s (Klick-Geräusch mit Id), bleibt unter dem Zeiger stehen, „Gewonnen: …“; Knopf zeigt danach „Nächstes Drehen in … Std“ |
| Einmal pro Tag | Nochmal drehen | Geht nicht („Heute schon gedreht“); zum Testen `Config.Debug.FreeSpins = true` |
| Powerups | Extra-Leben / Helm / Start-Turbo gewinnen, losfahren | Beim Verlassen der Startzone „Powerup: 🎒 Extra-Schulranzen“; 6 Ranzen bzw. ein Helm mehr; Start-Turbo gibt Schub. Im Reiter steht, was noch übrig ist |
| Speichern | Gewinnen, Stop, Play | Powerups und „heute schon gedreht“ bleiben |

## Tuning-Ablauf

1. In Studio Play, **F2** öffnet das Panel. Jeder Regler startet in der Mitte = aktueller
   Wert aus `Config.luau`, der Bereich geht von 0 bis zum Doppelten.
2. Regler schieben oder genaue Werte eintippen und ausprobieren. Mit „R“ zurück.
3. Zufrieden? „Werte kopieren“ klicken, die Zeilen aus dem Output (`Abschnitt.Name: alt -> neu`)
   an Claude schicken. Claude trägt sie in `Config.luau` ein und pusht.
4. Nach `git pull` und neuem Play stehen alle Regler wieder in der Mitte, die Mitte ist jetzt
   der neue Wert. So kann man sich schrittweise herantasten.

Welche Werte im Panel erscheinen und Sonder-Bereiche (z. B. für Winkel) stehen in
`Config.TuningPanel`. Das Tuning-Panel gibt es nur in Studio (`RunService:IsStudio()`). Im
veröffentlichten Spiel erscheint es nicht, und der Server ignoriert dort Tuning-Anfragen.

**Tuning:** Werte in `src/shared/Config.luau` ändern, speichern, in Studio Stop + Play.
Typische Stellschrauben:

- Zu schnell bergab → `Drive.AirDrag` erhöhen. Zu langsam → senken.
- Auf flachen Stücken zu langsam → `Drive.PushAcceleration` / `Drive.MaxPushSpeed` erhöhen.
- Rollt zu lange aus → `Drive.RollingResistance` erhöhen; S bremst zu schwach → `Drive.BrakeAcceleration`.
- Lenkt zu träge → `Drive.SteerRate` / `Drive.SteerResponse` erhöhen.
- Rutscht zu viel in Kurven → `Drive.LateralGrip` / `Drive.MaxGripAcceleration` erhöhen.
- Kippt zu leicht → `Cart.BallastHeight` senken, `Drive.RollDamping` erhöhen.
- Zu viele/zu wenige Crashs → `Crash.ImpactSpeedChange`, `Crash.MaxTiltAngle`.
- Wagen zieht nach ein paar Metern nach links/rechts („Drall“) → das ist das Wackelrad:
  `Drive.WobbleStrength` senken oder 0.
- Heck schwingt zu wenig/zu viel aus → `Drift.LateralGrip` (kleiner = weiter); Grenze: `Drift.RecoverAngle`.
- Drift lenkt zu schwach/zu stark → `Drift.SteerRate`; zu unruhig → `Drift.TailWobble` senken.
- Hopp zu hoch/zu flach → `Hop.Speed`; dreht in der Luft zu wenig → `Hop.TurnRate`.
- Boost zu stark/zu schwach → `Drift.Level1Boost` / `Drift.Level2Boost` (Anteil von
  `Drive.MaxPushSpeed`), `Drift.BoostDuration`; Kamera-Effekt: `Camera.BoostFovKick`.
- Boost kommt zu früh/zu spät nach dem Drift → `Drift.ReleaseDelay`.
- Ragdoll fliegt zu wenig/zu viel → `Crash.RagdollUpSpeed`, `Crash.RagdollForwardBoost`,
  `Crash.RagdollFloat` (Schwerkraft beim Flug).
- Kühe fliegen zu weit/zu kurz → `Launch.Power`, `Launch.Gravity`; Himmel zu oft →
  `Launch.SkyChance`; Hit-Stop zu lang → `Launch.HitStop`.
- Zu viele/wenige Münzen → `Coins.FinishBase`, `Coins.GradeBonus`, `Launch.BonusPerMeter`;
  Preise in `Config.Upgrades`.
- Leben → `Lives.PerRun`. Abilities → `Config.Abilities` (alle im Tuning-Panel).
- Ragdoll zu wild/zu lahm → `Crash.RagdollUpSpeed`, `Crash.RagdollCarry`, `Crash.RagdollSpin`.
- Kamera wackelt zu viel → `Camera.ShakeAtFullSpeed`, `Camera.LandingShakePerSpeed`, `Camera.ShakeMaxAngle`.
- Hügel liegt tiefer als −100 → `Crash.KillY` anpassen.

Mit mehreren Spielern testen: *Test → Clients and Servers → 2 Players → Start*.
Wagen verschiedener Spieler fahren durcheinander hindurch.
