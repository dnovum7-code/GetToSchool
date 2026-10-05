--!strict
-- Welche Config-Werte das Tuning-Panel (nur in Studio, Taste F2) als Schieberegler zeigt.
-- Wird vom Client (Panel) und vom Server (Pruefung) gemeinsam benutzt.
--
-- section/key: Config[section][key]
-- server = true: Der Wert betrifft Dinge, die der Server baut (z. B. Ballast im Wagen),
--                deshalb wird er zusaetzlich an den Server geschickt.

export type Slider = {
	label: string,
	section: string,
	key: string,
	min: number,
	max: number,
	step: number,
	server: boolean?,
}

local sliders: { Slider } = {
	{ label = "Motorkraft", section = "Drive", key = "PushAcceleration", min = 0, max = 100, step = 1 },
	{ label = "Hoechsttempo", section = "Drive", key = "MaxSpeed", min = 30, max = 250, step = 5 },
	{ label = "Lenkung", section = "Drive", key = "SteerRate", min = 0.5, max = 4, step = 0.05 },
	{ label = "Seitenhalt", section = "Drive", key = "LateralGrip", min = 0, max = 20, step = 0.5 },
	{
		label = "Kipp-Ballast (Hoehe)",
		section = "Cart",
		key = "BallastHeight",
		min = 0,
		max = 5,
		step = 0.1,
		server = true,
	},
	{ label = "Luftwiderstand", section = "Drive", key = "AirDrag", min = 0, max = 0.03, step = 0.0005 },
	{
		label = "Drift-Seitenhalt (hinten)",
		section = "Drift",
		key = "RearGrip",
		min = 0,
		max = 1,
		step = 0.01,
	},
	{
		label = "Rueckstell-Winkel (Grad)",
		section = "Drift",
		key = "RecoverAngle",
		min = 20,
		max = 120,
		step = 1,
	},
	{
		label = "Rueckstell-Staerke",
		section = "Drift",
		key = "RecoverStrength",
		min = 0,
		max = 40,
		step = 0.5,
	},
	{ label = "Boost-Schwelle 1 (s)", section = "Drift", key = "Level1Time", min = 0.2, max = 3, step = 0.1 },
	{ label = "Boost-Schwelle 2 (s)", section = "Drift", key = "Level2Time", min = 0.5, max = 5, step = 0.1 },
	-- Streckenbausteine (Standardwerte; Attribute an einzelnen Parts gehen vor)
	{ label = "Schlamm-Bremse", section = "Track", key = "MudDrag", min = 0, max = 10, step = 0.1 },
	{ label = "Eis-Seitenhalt", section = "Track", key = "IceGrip", min = 0, max = 1, step = 0.01 },
	{ label = "BoostPad-Staerke", section = "Track", key = "BoostPadStrength", min = 0, max = 150, step = 1 },
	{ label = "JumpPad-Staerke", section = "Track", key = "JumpPadStrength", min = 0, max = 200, step = 1 },
	-- Spielzeit: Spielsekunden pro echter Sekunde (gilt ab dem naechsten Start)
	{
		label = "Spielzeit-Tempo",
		section = "Clock",
		key = "TimeScale",
		min = 1,
		max = 60,
		step = 1,
		server = true,
	},
}

return sliders
