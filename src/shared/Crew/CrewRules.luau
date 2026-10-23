--!strict
-- Duo- und Chaos-Wagen: reine Logik (getestet in tests/CrewSpec.luau).
--   * Steuerelemente als Bits (fuer das Netz: eine Zahl pro Spieler)
--   * Chaos: Steuerelemente zufaellig (aber reproduzierbar per Seed) auf die Mitfahrer
--     verteilen
--   * Gastgeber-Client: eigene und gemeldete Eingaben zusammensetzen; wer laenger als
--     `timeout` nichts meldet, hat losgelassen
--   * laufende Nummern fuer Einmal-Aktionen, Tomaten-Munition, Tomaten-Schutz

local CrewRules = {}

CrewRules.CONTROLS = { "Gas", "Brake", "Left", "Right", "Jump", "Drift", "Boost", "Items" }

local BITS: { [string]: number } = {}
for index, control in CrewRules.CONTROLS do
	BITS[control] = 2 ^ (index - 1)
end
CrewRules.BITS = BITS

function CrewRules.has(bits: number, control: string): boolean
	local bit = BITS[control]
	return bit ~= nil and bit32.band(bits, bit) ~= 0
end

function CrewRules.toBits(held: { [string]: boolean }): number
	local bits = 0
	for control, on in held do
		if on and BITS[control] then
			bits = bit32.bor(bits, BITS[control])
		end
	end
	return bits
end

-- Reproduzierbares Mischen (alle Clients und der Server kommen aufs gleiche Ergebnis)
local function nextRandom(state: number): (number, number)
	state = (state * 1103515245 + 12345) % 2147483648
	return state, state / 2147483648
end

function CrewRules.shuffle<T>(list: { T }, seed: number): { T }
	local result = table.clone(list)
	local state = math.floor(math.abs(seed)) % 2147483648
	for i = #result, 2, -1 do
		local r
		state, r = nextRandom(state)
		local j = math.floor(r * i) + 1
		result[i], result[j] = result[j], result[i]
	end
	return result
end

-- Chaos: jedes Steuerelement bekommt genau einen Mitfahrer (UserIds), moeglichst gleich verteilt
function CrewRules.assign(members: { number }, seed: number): { [string]: number }
	local assignment: { [string]: number } = {}
	if #members == 0 then
		return assignment
	end
	local controls = CrewRules.shuffle(CrewRules.CONTROLS, seed)
	local people = CrewRules.shuffle(members, seed + 7)
	for index, control in controls do
		assignment[control] = people[(index - 1) % #people + 1]
	end
	return assignment
end

-- Steuerelemente eines Mitfahrers (in fester Reihenfolge, fuer die Anzeige)
function CrewRules.controlsOf(assignment: { [string]: number }, userId: number): { string }
	local result = {}
	for _, control in CrewRules.CONTROLS do
		if assignment[control] == userId then
			table.insert(result, control)
		end
	end
	return result
end

-- Server: nur die Bits behalten, die dem Absender gehoeren
function CrewRules.allowedBits(assignment: { [string]: number }, userId: number, bits: number): number
	local mask = 0
	for control, holder in assignment do
		if holder == userId then
			mask = bit32.bor(mask, BITS[control])
		end
	end
	return bit32.band(math.floor(bits) % 256, mask)
end

export type Remote = { bits: number, at: number }

-- Gastgeber: wer haelt welches Steuerelement gerade? Eigene Bits gelten sofort, die der
-- anderen nur, wenn ihre letzte Meldung juenger als `timeout` ist.
function CrewRules.merge(
	hostId: number,
	hostBits: number,
	remote: { [number]: Remote },
	assignment: { [string]: number },
	now: number,
	timeout: number
): { [string]: boolean }
	local held: { [string]: boolean } = {}
	for _, control in CrewRules.CONTROLS do
		local holder = assignment[control]
		local bits = 0
		if holder == hostId then
			bits = hostBits
		elseif holder then
			local state = remote[holder]
			if state and now - state.at <= timeout then
				bits = state.bits
			end
		end
		held[control] = CrewRules.has(bits, control)
	end
	return held
end

-- Gas/Bremse und Lenkung aus den gehaltenen Steuerelementen
function CrewRules.drive(held: { [string]: boolean }): (number, number)
	local throttle = (if held.Gas then 1 else 0) - (if held.Brake then 1 else 0)
	local steer = (if held.Right then 1 else 0) - (if held.Left then 1 else 0)
	return throttle, steer
end

-- Einmal-Aktion annehmen? Nur neuere laufende Nummern (doppelt/alt = nein)
function CrewRules.acceptSeq(last: number?, seq: unknown): boolean
	return type(seq) == "number" and seq == seq and (last == nil or seq > last)
end

-- Tomaten-Munition: laedt alle `interval` Sekunden eine nach (bis `max`)
function CrewRules.regen(
	ammo: number,
	max: number,
	lastRegen: number,
	now: number,
	interval: number
): (number, number)
	if ammo >= max then
		return max, now
	end
	local gained = math.floor((now - lastRegen) / math.max(interval, 0.1))
	if gained <= 0 then
		return ammo, lastRegen
	end
	return math.min(max, ammo + gained), lastRegen + gained * interval
end

-- Darf dieser Spieler von Tomaten getroffen werden? Solo-Laeufe sind geschuetzt (Schalter),
-- ausser der Spieler hat sich in den Einstellungen "bewerfbar" gemacht.
function CrewRules.canBeHit(
	inCrew: boolean,
	soloRunning: boolean,
	optIn: boolean,
	protectSolo: boolean
): boolean
	if inCrew or optIn or not protectSolo then
		return true
	end
	return not soloRunning
end

return CrewRules
