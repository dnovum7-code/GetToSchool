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
