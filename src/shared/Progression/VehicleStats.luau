--!strict
-- Fahrwerte pro Fahrzeug - reine Logik ohne Roblox-Dienste (getestet in tests/VehicleSpec.luau).
--
-- Jedes Fahrzeug (Config.Vehicles) nimmt die Werte des Einkaufswagens (Config.Cart, Drive,
-- Drift, Hop) und aendert einzelne davon:
--   set   = { Cart = { Width = 3 } }          fester Wert
--   scale = { Drive = { SteerRate = 1.5 } }   Faktor auf den Einkaufswagen-Wert
-- Das Ergebnis liest die Grundwerte immer frisch nach. Wer im Tuning-Panel z. B. die Lenkung
-- des Einkaufswagens aendert, aendert sie fuer alle Fahrzeuge mit (im selben Verhaeltnis).

local VehicleStats = {}

VehicleStats.SECTIONS = { "Cart", "Drive", "Drift", "Hop" }

export type Overrides = {
	set: { [string]: { [string]: any } }?,
	scale: { [string]: { [string]: number } }?,
}

-- Liefert pro Abschnitt eine Tabelle zum Lesen (nur lesen, nicht schreiben).
-- `base` = { Cart = ..., Drive = ..., ... } (normalerweise die Config).
function VehicleStats.resolve(base: { [string]: any }, overrides: Overrides?): { [string]: any }
	local result = {}
	local set = overrides and overrides.set or {}
	local scale = overrides and overrides.scale or {}
	for _, section in VehicleStats.SECTIONS do
		result[section] = setmetatable({}, {
			__index = function(_, key)
				local fixed = set[section]
				if fixed and fixed[key] ~= nil then
					return fixed[key]
				end
				local value = (base[section] or {})[key]
				local factors = scale[section]
				local factor = factors and factors[key]
				if type(value) == "number" and type(factor) == "number" then
					return value * factor
				end
				return value
			end,
			__newindex = function()
				error("Fahrzeugwerte sind nur zum Lesen (Config aendern)", 2)
			end,
		})
	end
	return result
end

-- Faktor eines Werts gegenueber dem Einkaufswagen (fuer Anzeigen), 1 = gleich
function VehicleStats.ratio(
	base: { [string]: any },
	stats: { [string]: any },
	section: string,
	key: string
): number
	local original = (base[section] or {})[key]
	local value = stats[section][key]
	if type(original) ~= "number" or type(value) ~= "number" or original == 0 then
		return 1
	end
	return value / original
end

return VehicleStats
