--!strict
-- Lufttricks - reine Logik ohne Roblox-Dienste (getestet in tests/TricksSpec.luau).
-- Werte in Config.Tricks.
--
-- In der Luft dreht sich der Wagen mit Q/E (Gamepad LB, Touch "Trick") um die Hochachse.
-- Gezaehlt wird die Drehung waehrend des Flugs. Bei der Landung entscheidet der Winkel
-- zwischen Blickrichtung und Fahrtrichtung:
--   Clean  (<= CleanAngle)  saubere Landung: Muenzen pro halber Drehung
--   Wobbly (<= CrashAngle)  wackelig: keine Muenzen, kein Crash
--   Crash  (>  CrashAngle)  schief gelandet: Crash (kostet ein Leben, Helm hilft)

local TrickMath = {}

export type Config = {
	MinTrickDegrees: number, -- erst ab dieser Drehung zaehlt es als Trick (sonst normaler Sprung)
	SpinTolerance: number, -- so viele Grad duerfen zur naechsten halben Drehung fehlen
	CleanAngle: number,
	CrashAngle: number,
	CoinsPerHalfSpin: number,
	MaxHalfSpins: number, -- mehr wird nicht belohnt
}

export type Result = {
	kind: string, -- "None", "Clean", "Wobbly", "Crash"
	halfSpins: number, -- geschaffte halbe Drehungen (180 Grad)
	coins: number,
}

-- Winkel auf -180..180
function TrickMath.wrap(degrees: number): number
	return (degrees + 180) % 360 - 180
end

-- Halbe Drehungen aus der Gesamtdrehung (Vorzeichen egal)
function TrickMath.halfSpins(totalDegrees: number, tolerance: number): number
	return math.floor((math.abs(totalDegrees) + tolerance) / 180)
end

-- Muenzen fuer halbe Drehungen (begrenzt)
function TrickMath.coins(halfSpins: number, cfg: Config): number
	return math.max(0, math.min(halfSpins, cfg.MaxHalfSpins)) * cfg.CoinsPerHalfSpin
end

-- Landung bewerten. `landingAngle` = Winkel zwischen Blick- und Fahrtrichtung (Grad).
-- Nach einer halben Drehung (180) faehrt man rueckwaerts - das zaehlt auch als sauber,
-- wenn der Wagen genau rueckwaerts steht (Winkel nahe 180).
function TrickMath.evaluate(totalDegrees: number, landingAngle: number, cfg: Config): Result
	if math.abs(totalDegrees) < cfg.MinTrickDegrees then
		return { kind = "None", halfSpins = 0, coins = 0 }
	end
	local halfSpins = TrickMath.halfSpins(totalDegrees, cfg.SpinTolerance)
	local angle = math.abs(TrickMath.wrap(landingAngle))
	local offAxis = math.min(angle, 180 - angle) -- vorwaerts oder genau rueckwaerts gelandet
	if offAxis > cfg.CrashAngle then
		return { kind = "Crash", halfSpins = halfSpins, coins = 0 }
	elseif offAxis > cfg.CleanAngle then
		return { kind = "Wobbly", halfSpins = halfSpins, coins = 0 }
	end
	return { kind = "Clean", halfSpins = halfSpins, coins = TrickMath.coins(halfSpins, cfg) }
end

-- Anzeige: 3 halbe Drehungen -> "540"
function TrickMath.label(halfSpins: number): string
	return `{halfSpins * 180}°`
end

return TrickMath
