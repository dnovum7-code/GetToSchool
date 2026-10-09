--!strict
-- Steuerung als Text: Uebersicht fuer das Einstellungsmenue und Hilfezeile unten - jeweils
-- passend zum Geraet (Tastatur, Gamepad, Touch).

local UserInputService = game:GetService("UserInputService")

local ControlsInfo = {}

export type Device = "Keyboard" | "Gamepad" | "Touch"

-- Aktion, Tastatur, Gamepad, Touch (wie die Tabelle in CLAUDE.md)
ControlsInfo.ROWS = {
	{ "Gas / Bremse, rueckwaerts", "W / S", "RT / LT oder Stick", "Joystick" },
	{ "Lenken (Standard: Drift)", "A / D", "Linker Stick", "Joystick" },
	{ "Normal fahren (halten)", "Shift", "B", "Normal" },
	{ "Hopp / Sprung, Fallschirm (halten)", "Leertaste", "A", "Hopp" },
	{ "Turbo-Pausenbrot", "F", "RB", "Turbo" },
	{ "Lufttrick: drehen (in der Luft)", "Q / E", "LB (+ Stick)", "Trick" },
	{ "Zurueck zum Checkpoint", "R", "Y", "R" },
	{ "Kompletter Neustart", "T", "Steuerkreuz hoch", "Start" },
	{ "Aus- / Einsteigen", "E", "X", "Raus" },
	{ "Menue (Shop, Garage ...)", "B", "Select", "Shop" },
}

-- Welches Geraet benutzt der Spieler gerade?
function ControlsInfo.device(): Device
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Touch"
	elseif string.find(last.Name, "Gamepad") then
		return "Gamepad"
	elseif last == Enum.UserInputType.Keyboard or string.find(last.Name, "Mouse") then
		return "Keyboard"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
		then "Gamepad"
		else "Keyboard"
end

-- Hilfezeile unten im Bild (Touch: leer, die Knoepfe sind beschriftet)
function ControlsInfo.helpLine(device: Device): string
	if device == "Gamepad" then
		return "RT/Stick: Gas   LT: Bremse   Stick: Lenken   B: normal fahren   A: Hopp   LB: Trick   X: Aus-/Einsteigen   Y: Checkpoint   Hoch: Neustart   Select: Menue"
	elseif device == "Touch" then
		return ""
	end
	return "W/S: Anschieben/Bremsen   A/D: Lenken   Shift: normal fahren   Leertaste: Hopp   Q/E in der Luft: Trick   E: Aus-/Einsteigen   R: Checkpoint   T: Neustart   B: Menue"
end

return ControlsInfo
