--!strict
-- Taegliches Gluecksrad - reine Logik ohne Roblox-Dienste (getestet in tests/DailySpinSpec.luau).
-- Einmal pro Tag (gleicher Tageswechsel wie die Hausaufgaben) gratis drehen. Gewinne:
-- Muenzen oder Powerups (Items), die beim naechsten Lauf automatisch wirken.
-- Felder und Gewichte: Config.DailySpin.

local DailySpin = {}

export type Segment = {
	id: string,
	text: string, -- Beschriftung auf dem Rad
	kind: string, -- "Coins" oder "Item"
	amount: number, -- Muenzen bzw. Anzahl Items
	item: string?, -- bei "Item": Id aus Config.DailySpin.Items
	weight: number, -- Wahrscheinlichkeit (relativ)
}

export type Data = {
	coins: number,
	spinDay: number,
	items: { [string]: number },
}

function DailySpin.canSpin(spinDay: number, today: number): boolean
	return spinDay < today
end

-- Feld auswuerfeln. `roll`: Zufallszahl 0..1. Gibt den Index zurueck.
function DailySpin.pick(segments: { Segment }, roll: number): number
	local total = 0
	for _, segment in segments do
		total += math.max(segment.weight, 0)
	end
	if total <= 0 then
		return 1
	end
	local remaining = math.clamp(roll, 0, 0.999999) * total
	for index, segment in segments do
		remaining -= math.max(segment.weight, 0)
		if remaining < 0 then
			return index
		end
	end
	return #segments
end

-- Gewinn gutschreiben und den Tag merken. Gibt false zurueck, wenn heute schon gedreht.
function DailySpin.apply(data: Data, segment: Segment, today: number, maxItems: number): boolean
	if not DailySpin.canSpin(data.spinDay, today) then
		return false
	end
	data.spinDay = today
	if segment.kind == "Coins" then
		data.coins += math.max(0, math.floor(segment.amount))
	elseif segment.kind == "Item" and segment.item then
		local current = data.items[segment.item] or 0
		data.items[segment.item] = math.min(current + math.max(1, math.floor(segment.amount)), maxItems)
	end
	return true
end

-- Beim Start eines Laufs: von jedem Item eins verbrauchen. Gibt die Ids zurueck.
function DailySpin.consumeForRun(items: { [string]: number }, usable: { string }): { string }
	local used = {}
	for _, id in usable do
		local count = items[id] or 0
		if count > 0 then
			if count > 1 then
				items[id] = count - 1
			else
				(items :: any)[id] = nil -- letztes verbraucht: Eintrag weg
			end
			table.insert(used, id)
		end
	end
	return used
end

return DailySpin
