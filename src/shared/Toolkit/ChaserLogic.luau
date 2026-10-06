--!strict
-- Verhalten eines Verfolgers (Hund) als einfache Zustandsmaschine (reine Logik, getestet in
-- tests/ToolkitSpec.luau):
--   "Idle"   wartet zu Hause. Kommt der Wagen naeher als Radius: "Chase". Wartet er auf ein
--            Signal (ListenSignal), startet er nur beim Signal.
--   "Chase"  rennt dem Wagen nach, wird bis MaxSpeed schneller. Nach GiveUpTime: "Return".
--   "Return" laeuft mit ReturnSpeed nach Hause, dann "Idle" mit kurzer Pause (Cooldown).

local ChaserLogic = {}

export type Settings = {
	waitsForSignal: boolean?, -- true = startet nur per Signal (nicht ueber den Radius)
	radius: number,
	maxSpeed: number,
	acceleration: number,
	giveUpTime: number,
	returnSpeed: number,
	cooldown: number,
}

export type State = {
	mode: string, -- "Idle", "Chase", "Return"
	timer: number, -- Chase: Zeit seit Start; Idle: Rest-Pause
	speed: number, -- aktuelles Tempo
}

function ChaserLogic.new(): State
	return { mode = "Idle", timer = 0, speed = 0 }
end

-- Einen Schritt weiter. `targetDistance`: Abstand zum Wagen (nil = kein Wagen),
-- `homeDistance`: Abstand nach Hause, `signaled`: Signal in diesem Frame.
-- Gibt das Tempo zurueck, mit dem in diesem Frame gelaufen wird.
function ChaserLogic.step(
	state: State,
	dt: number,
	targetDistance: number?,
	homeDistance: number,
	signaled: boolean,
	settings: Settings
): number
	if state.mode == "Idle" then
		state.timer = math.max(0, state.timer - dt)
		state.speed = 0
		local start = if settings.waitsForSignal
			then signaled
			else targetDistance ~= nil and targetDistance <= settings.radius
		if targetDistance ~= nil and state.timer <= 0 and start then
			state.mode = "Chase"
			state.timer = 0
		end
	elseif state.mode == "Chase" then
		state.timer += dt
		state.speed = math.min(settings.maxSpeed, state.speed + settings.acceleration * dt)
		if state.timer >= settings.giveUpTime or targetDistance == nil then
			state.mode = "Return"
			state.timer = 0
		end
	elseif state.mode == "Return" then
		state.speed = settings.returnSpeed
		if homeDistance <= 1 then
			state.mode = "Idle"
			state.timer = settings.cooldown
			state.speed = 0
		end
	end
	return state.speed
end

-- R und T: sofort zu Hause, ohne Pause
function ChaserLogic.reset(state: State)
	state.mode = "Idle"
	state.timer = 0
	state.speed = 0
end

return ChaserLogic
