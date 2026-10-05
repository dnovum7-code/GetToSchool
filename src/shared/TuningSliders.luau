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
}

return sliders
