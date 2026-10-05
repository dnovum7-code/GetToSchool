--!strict
-- Baukasten (M2.5), Client-Seite: Manager fuer alle dynamischen Bausteine.
-- Alles laeuft nur auf diesem Client (jeder Spieler hat seine eigene Version), damit
-- Zusammenstoesse mit dem eigenen Wagen ohne Verzoegerung passen und niemand einem anderen
-- die Strecke kaputt macht. Dauerbetrieb (z. B. Auto-Strom) laeuft ueber die Serveruhr und
-- reproduzierbaren Zufall: Alle Spieler sehen ihn gleich.
--
-- Reset-Regeln:
--   T (kompletter Neustart): alles zurueck auf Anfang.
--   R / Crash (Checkpoint):  gespawnte Objekte weg, eingestuerzte Bruecken wieder da,
--                            Trigger scharf, Verfolger nach Hause, Signal-Tore zu.
--                            Props bleiben liegen (Chaos-Zaehler bleibt).

local ToolkitTypes = require(script:WaitForChild("ToolkitTypes"))
local TriggerZones = require(script:WaitForChild("TriggerZones"))

local Toolkit = {}

local MODULES: { ToolkitTypes.Piece } = {
	TriggerZones,
}

function Toolkit.init()
	for _, piece in MODULES do
		piece.init()
	end
end

-- Jeden Physik-Frame aus CartClient (nach der Fahrphysik)
function Toolkit.step(ctx: ToolkitTypes.Context)
	for _, piece in MODULES do
		piece.step(ctx)
	end
end

-- kind: "Full" (T) oder "Checkpoint" (R / Crash)
function Toolkit.reset(kind: string)
	for _, piece in MODULES do
		local reset = piece.reset
		if reset then
			reset(kind)
		end
	end
end

return Toolkit
