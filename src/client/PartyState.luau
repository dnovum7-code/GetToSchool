--!strict
-- Party-Modi, Zustand beim Client (wer gerade in einer Runde ist, welcher Modus, ob schon
-- ausgeschieden). Eigenes kleines Modul, damit CartClient, PartyUI und andere es lesen
-- koennen, ohne sich gegenseitig zu laden.

local PartyState = {}

PartyState.active = false -- in einer Party-Runde (Phase "Party" beim Server)
PartyState.mode = nil :: string? -- "CowBowling" / "LastCart"
PartyState.eliminated = false -- Letzter Wagen: ausgeschieden, schaut zu

function PartyState.reset()
	PartyState.active = false
	PartyState.mode = nil
	PartyState.eliminated = false
end

return PartyState
