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

local Chasers = require(script:WaitForChild("Chasers"))
local Collapses = require(script:WaitForChild("Collapses"))
local ForceZones = require(script:WaitForChild("ForceZones"))
local Gates = require(script:WaitForChild("Gates"))
local PathMovers = require(script:WaitForChild("PathMovers"))
local Props = require(script:WaitForChild("Props"))
local Spawners = require(script:WaitForChild("Spawners"))
local ToolkitTypes = require(script:WaitForChild("ToolkitTypes"))
local TriggerZones = require(script:WaitForChild("TriggerZones"))

local Toolkit = {}

local MODULES: { ToolkitTypes.Piece } = {
	TriggerZones,
	Spawners,
	PathMovers,
	Gates,
	Collapses,
	Props :: any,
	ForceZones,
	Chasers,
}

function Toolkit.init()
	for _, piece in MODULES do
		piece.init()
	end
end

local warnedErrors: { [string]: boolean } = {}

-- Jeden Physik-Frame aus CartClient (nach der Fahrphysik). Ein Fehler in einem Baustein darf
-- das Fahren (Muenzen, Crash-Erkennung ...) nicht lahmlegen: abfangen, einmal melden.
function Toolkit.step(ctx: ToolkitTypes.Context)
	for _, piece in MODULES do
		xpcall(piece.step, function(err)
			local text = tostring(err)
			if not warnedErrors[text] then
				warnedErrors[text] = true
				warn("[Baukasten] Fehler: " .. text .. "\n" .. debug.traceback())
			end
		end, ctx)
	end
end

-- Getroffene Props in diesem Lauf (Ergebnis-Screen)
function Toolkit.getChaos(): number
	return Props.getChaos()
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
