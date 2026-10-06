--!strict
-- Steuerung als Text: Uebersicht fuer das Einstellungsmenue, Hilfezeile unten und die Texte der
-- Einstiegs-Hinweise - jeweils passend zum Geraet (Tastatur, Gamepad, Touch).

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
		return "RT/Stick: Gas   LT: Bremse   Stick: Lenken   B: normal fahren   A: Hopp   X: Aus-/Einsteigen   Y: Checkpoint   Hoch: Neustart   Select: Menue"
	elseif device == "Touch" then
		return ""
	end
	return "W/S: Anschieben/Bremsen   A/D: Lenken   Shift: normal fahren   Leertaste: Hopp   E: Aus-/Einsteigen   R: Checkpoint   T: Neustart   B: Menue"
end

-- Einstiegs-Hinweise: Titel und Text je Geraet
local HINTS: { [string]: { title: string, Keyboard: string, Gamepad: string, Touch: string } } = {
	Drive = {
		title = "Los geht's!",
		Keyboard = "W = anschieben, S = bremsen, A/D = lenken. Bergab wird's schnell!",
		Gamepad = "RT (oder Stick nach vorne) = Gas, LT = Bremse, linker Stick = lenken.",
		Touch = "Joystick links: nach vorne = Gas, zur Seite = lenken.",
	},
	Drift = {
		title = "Driften",
		Keyboard = "In Kurven driftest du automatisch. Lang driften = Boost am Ende! Shift halten = ruhig fahren.",
		Gamepad = "In Kurven driftest du automatisch. Lang driften = Boost am Ende! B halten = ruhig fahren.",
		Touch = 'In Kurven driftest du automatisch. Lang driften = Boost am Ende! "Normal" halten = ruhig fahren.',
	},
	Restart = {
		title = "Hingefallen? Kein Problem",
		Keyboard = "R = zurueck zum letzten Checkpoint, T = ganz von vorne.",
		Gamepad = "Y = zurueck zum letzten Checkpoint, Steuerkreuz hoch = ganz von vorne.",
		Touch = '"R" = zurueck zum letzten Checkpoint, "Start" = ganz von vorne.',
	},
}

function ControlsInfo.hint(id: string, device: Device): (string, string)
	local hint = HINTS[id]
	if not hint then
		return "", ""
	end
	return hint.title, (hint :: any)[device] or hint.Keyboard
end

return ControlsInfo
