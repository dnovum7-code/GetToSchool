--!strict
-- Verfolger (Baustein "Pursuer"): Gummiband-Logik, reine Rechnung (getestet in
-- tests/PursuerSpec.luau). Alles in "Strecke entlang der Wegpunkte" (Studs ab Punkt 1):
--   s      = wo der Verfolger ist
--   player = wo der Spieler ist (auf den Weg projiziert)
--   gap    = player - s (Vorsprung des Spielers)
-- Tempo: BaseSpeed, je groesser der Abstand, desto mehr CatchUpSpeed dazu (ab MaxGap voll).
-- Faehrt der Spieler langsam oder crasht, holt er auf; faehrt er gut, waechst der Abstand
-- bis MaxGap - weiter weg kommt er nie (dann wird der Verfolger nachgezogen).

local PursuerLogic = {}

export type Params = {
	baseSpeed: number,
	catchUpSpeed: number,
	minGap: number,
	maxGap: number,
}

-- Laufende Summe der Abschnittslaengen: cum[1] = 0, cum[i] = Strecke bis Punkt i
function PursuerLogic.cumulative(lengths: { number }): { number }
	local cum = { 0 }
	local total = 0
	for _, length in lengths do
		total += math.max(length, 0)
		table.insert(cum, total)
	end
	return cum
end

-- Strecke s -> Abschnitt (von Punkt i nach i + 1) und Anteil 0..1 darauf
function PursuerLogic.locate(cum: { number }, s: number): (number, number)
	local count = #cum
	if count < 2 then
		return 1, 0
	end
	local clamped = math.clamp(s, 0, cum[count])
	for i = 1, count - 1 do
		if clamped <= cum[i + 1] or i == count - 1 then
			local length = cum[i + 1] - cum[i]
			return i, if length > 0 then math.clamp((clamped - cum[i]) / length, 0, 1) else 0
		end
	end
	return count - 1, 1
end

function PursuerLogic.speed(gap: number, params: Params): number
	local span = math.max(params.maxGap - params.minGap, 1)
	local t = math.clamp((gap - params.minGap) / span, 0, 1)
	return params.baseSpeed + params.catchUpSpeed * t
end

-- Einen Schritt weiter: nie ueber das Ende hinaus, nie weiter als maxGap hinter dem Spieler
function PursuerLogic.advance(s: number, player: number, dt: number, params: Params, length: number): number
	local nextS = s + PursuerLogic.speed(player - s, params) * dt
	nextS = math.max(nextS, player - params.maxGap)
	return math.clamp(nextS, 0, length)
end

-- Startlage: beim Losfahren (maxGap hinter dem Spieler) bzw. nach R / Erwischen (minGap)
function PursuerLogic.behind(player: number, gap: number): number
	return math.max(0, player - gap)
end

-- Bedrohung 0..1 fuer die Anzeige (rote Raender): 1 = gleich erwischt, 0 = ab warnGap
function PursuerLogic.danger(distance: number, catchRadius: number, warnGap: number): number
	local span = math.max(warnGap - catchRadius, 1)
	return math.clamp(1 - (distance - catchRadius) / span, 0, 1)
end

return PursuerLogic
