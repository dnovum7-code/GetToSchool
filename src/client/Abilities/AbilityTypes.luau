--!strict
-- Gemeinsame Schnittstelle aller Abilities. Jede Ability ist ein eigenes Modul in diesem
-- Ordner und liefert eine Tabelle vom Typ `Ability`. Neue Ability hinzufuegen:
--   1. Modul hier anlegen (z. B. von TurboSnack.luau abschauen)
--   2. in Abilities/init.luau in die Liste MODULES eintragen
--   3. Upgrade (Preis, Stufen) in Config.Upgrades und Werte in Config.Abilities
--
-- Ablauf pro Physik-Frame (nur waehrend man faehrt):
--   beforeStep(ctx)  vor der Fahrphysik (z. B. Sprung-Tempo einstellen)
--   afterStep(ctx)   nach der Fahrphysik; ctx.telemetry ist gesetzt (z. B. Schub, Gleiten)
-- Unity-Vergleich: wie mehrere kleine MonoBehaviours, die ein Manager der Reihe nach aufruft.

local CartController = require(script.Parent.Parent:WaitForChild("CartController"))

export type Input = {
	jumpPressed: boolean, -- Leertaste / Gamepad A in diesem Frame gedrueckt
	jumpHeld: boolean, -- ... wird gehalten
	turboPressed: boolean, -- F / Gamepad RB in diesem Frame gedrueckt
}

-- Rueckmeldungen ans Spiel (Kamera, Text, Sound)
export type Effects = {
	fovKick: (degrees: number) -> (),
	shake: (degrees: number) -> (),
	toast: (text: string, color: Color3?) -> (),
	sound: (name: string) -> (),
}

export type Context = {
	controller: CartController.Controller,
	telemetry: CartController.Telemetry?, -- nil in beforeStep
	character: Model?,
	level: number, -- gekaufte Stufe dieser Ability (0 = nicht gekauft)
	input: Input,
	dt: number,
	-- Selbst verursachten Tempo-Sprung melden (zaehlt nicht als Crash)
	expectImpulse: (delta: Vector3) -> (),
	effects: Effects,
}

-- Eine Zeile in der Ability-Anzeige unten links
export type HudInfo = {
	name: string,
	key: string?, -- Tastenhinweis, z. B. "F"
	status: string, -- z. B. "bereit", "3.2 s", "2/3"
	fill: number?, -- Balken 0..1 (Ladung/Abklingzeit), nil = kein Balken
	active: boolean?, -- gerade aktiv (hervorgehoben)
	color: Color3?,
}

export type Ability = {
	id: string, -- = Upgrade-Id in Config.Upgrades
	beforeStep: ((ctx: Context) -> ())?,
	afterStep: ((ctx: Context) -> ())?,
	-- "Full" (kompletter Neustart), "Checkpoint", "Exit" (ausgestiegen/Crash)
	reset: ((kind: string) -> ())?,
	hud: (level: number) -> HudInfo?,
}

return nil
