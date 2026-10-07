--!strict
-- Taegliche Login-Belohnung (7-Tage-Serie) - reine Logik ohne Roblox-Dienste
-- (getestet in tests/LoginStreakSpec.luau). Belohnungen: Config.LoginRewards.
--
-- Jeden Tag (UTC, gleicher Tageswechsel wie die Hausaufgaben) kann man einmal abholen.
-- Gestern abgeholt -> heute der naechste Tag der Serie; nach Tag 7 wieder Tag 1.
-- Einen Tag verpasst (oder noch nie) -> Tag 1.

local LoginStreak = {}

export type State = { lastDay: number, streak: number }

export type Reward = {
	kind: string, -- "Coins", "MeterBoost", "Skin"
	amount: number?, -- Coins: Muenzen
	runs: number?, -- MeterBoost: so viele Laeufe x2
	skin: string?, -- Skin: Farb-Id aus Config.Cosmetics.Colors
	fallbackCoins: number?, -- Skin schon vorhanden: stattdessen so viele Muenzen
}

LoginStreak.LENGTH = 7

-- Kann man heute abholen, und welcher Serien-Tag ist es (bzw. war es heute)?
function LoginStreak.status(state: State, today: number): (boolean, number)
	if state.lastDay == today then
		return false, math.max(state.streak, 1)
	end
	if state.lastDay == today - 1 and state.streak >= 1 then
		return true, state.streak % LoginStreak.LENGTH + 1
	end
	return true, 1
end

-- Abholen: gibt den Serien-Tag zurueck, oder nil, wenn heute schon abgeholt
function LoginStreak.claim(state: State, today: number): number?
	local canClaim, day = LoginStreak.status(state, today)
	if not canClaim then
		return nil
	end
	state.lastDay = today
	state.streak = day
	return day
end

-- Text fuer den Kalender
function LoginStreak.describe(reward: Reward, skinName: string?): string
	if reward.kind == "Coins" then
		return `{reward.amount or 0} Muenzen`
	elseif reward.kind == "MeterBoost" then
		local runs = reward.runs or 1
		return `x2 Meter ({runs} {if runs == 1 then "Lauf" else "Laeufe"})`
	elseif reward.kind == "Skin" then
		return skinName or "Wagen-Skin"
	end
	return "?"
end

return LoginStreak
