--!strict
-- Regeln fuer TriggerZones (reine Logik, getestet in tests/ToolkitSpec.luau):
-- Ein Signal wird ausgeloest, wenn der eigene Wagen in die Zone HINEINfaehrt (nicht jeden
-- Frame, solange er drin ist). Once = nur einmal pro Lauf, Cooldown = Mindestabstand (s).

local TriggerRules = {}

export type State = {
	inside: boolean, -- war der Wagen im letzten Frame drin?
	used: boolean, -- schon ausgeloest (fuer Once)
	lastFired: number?, -- Zeitpunkt der letzten Ausloesung
}

function TriggerRules.new(): State
	return { inside = false, used = false, lastFired = nil }
end

-- Jeden Frame aufrufen. Gibt true zurueck, wenn jetzt ausgeloest wird.
function TriggerRules.update(
	state: State,
	inside: boolean,
	now: number,
	once: boolean,
	cooldown: number
): boolean
	local entered = inside and not state.inside
	state.inside = inside
	if not entered then
		return false
	end
	if once and state.used then
		return false
	end
	local last = state.lastFired
	if last and now - last < cooldown then
		return false
	end
	state.used = true
	state.lastFired = now
	return true
end

-- Neustart (R oder T): wieder scharf
function TriggerRules.rearm(state: State)
	state.inside = false
	state.used = false
	state.lastFired = nil
end

return TriggerRules
