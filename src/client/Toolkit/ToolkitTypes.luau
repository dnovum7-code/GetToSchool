--!strict
-- Gemeinsame Schnittstelle der Baukasten-Bausteine (ein Modul pro Baustein-Art).
-- Neuer Baustein: Modul hier anlegen und in Toolkit/init.luau in MODULES eintragen.

export type Context = {
	dt: number,
	cart: Model?, -- eigener Wagen, solange man faehrt (sonst nil)
	base: BasePart?, -- dessen Boden (Position, Tempo)
	controller: any?, -- Fahrphysik (fuer ForceZone), nur waehrend der Fahrt
}

export type Piece = {
	init: () -> (),
	-- Jeden Physik-Frame (auch ohne Wagen, z. B. fuer Dauerbetrieb)
	step: (ctx: Context) -> (),
	-- "Full" = kompletter Neustart (T), "Checkpoint" = R / Crash
	reset: ((kind: string) -> ())?,
}

return nil
