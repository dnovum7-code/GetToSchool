--!strict
-- Abilities-Manager: haelt die Liste aller Abilities, kennt die gekauften Stufen (vom Server),
-- liest die Ability-Tasten und ruft jede Ability pro Physik-Frame auf.
-- Die einzelnen Abilities liegen als eigene Module in diesem Ordner (siehe AbilityTypes).

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Economy =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"):WaitForChild("Economy"))
local AbilityTypes = require(script:WaitForChild("AbilityTypes"))
local Glider = require(script:WaitForChild("Glider"))
local Helmet = require(script:WaitForChild("Helmet"))
local SpringJump = require(script:WaitForChild("SpringJump"))
local TurboSnack = require(script:WaitForChild("TurboSnack"))

local Abilities = {}

-- Reihenfolge = Reihenfolge in der Anzeige. Neue Ability: hier eintragen.
local MODULES: { AbilityTypes.Ability } = {
	SpringJump,
	Helmet :: any,
	TurboSnack,
	Glider,
}

local TURBO_ACTION = "GetToSchoolTurbo"

local upgrades: { [string]: number } = {}
local turboRequested = false
local active = false

-- Stufe einer Ability (Upgrade-Id). Config.Debug.AllUpgrades: in Studio alles maximal.
function Abilities.getLevel(id: string): number
	local def = Economy.findUpgrade(Config.Upgrades, id)
	if not def then
		return 0
	end
	local allMax = Config.Debug.AllUpgrades and RunService:IsStudio()
	return Economy.effectiveLevel(upgrades, def, allMax)
end

local function bindTurbo()
	ContextActionService:UnbindAction(TURBO_ACTION)
	if not active or Abilities.getLevel("Turbo") < 1 then
		return
	end
	-- Touch-Button erscheint nur, wenn das Pausenbrot gekauft ist
	ContextActionService:BindAction(TURBO_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			turboRequested = true
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonR1)
	ContextActionService:SetTitle(TURBO_ACTION, "Turbo")
end

-- Gekaufte Stufen vom Server (Spielstand-Kopie)
function Abilities.setLevels(newUpgrades: { [string]: number })
	upgrades = table.clone(newUpgrades)
	bindTurbo()
end

-- Einsteigen / Aussteigen: Tasten binden bzw. loesen
function Abilities.activate()
	active = true
	turboRequested = false
	bindTurbo()
end

function Abilities.deactivate()
	active = false
	ContextActionService:UnbindAction(TURBO_ACTION)
	Abilities.reset("Exit")
end

-- Helm-Ladungen (vom Server bzw. vorhergesagt)
function Abilities.setShield(shield: number, maxShield: number)
	Helmet.setShield(shield, maxShield)
end

export type StepContext = {
	controller: any,
	telemetry: any,
	character: Model?,
	jumpPressed: boolean,
	jumpHeld: boolean,
	dt: number,
	expectImpulse: (delta: Vector3) -> (),
	effects: AbilityTypes.Effects,
}

local function makeContext(
	base: StepContext,
	ability: AbilityTypes.Ability,
	turbo: boolean
): AbilityTypes.Context
	return {
		controller = base.controller,
		telemetry = base.telemetry,
		character = base.character,
		level = Abilities.getLevel(ability.id),
		input = { jumpPressed = base.jumpPressed, jumpHeld = base.jumpHeld, turboPressed = turbo },
		dt = base.dt,
		expectImpulse = base.expectImpulse,
		effects = base.effects,
	}
end

-- Vor der Fahrphysik (CartController.step)
function Abilities.beforeStep(base: StepContext)
	for _, ability in MODULES do
		local before = ability.beforeStep
		if before then
			before(makeContext(base, ability, false))
		end
	end
end

-- Nach der Fahrphysik; `base.telemetry` ist gesetzt
function Abilities.afterStep(base: StepContext)
	local turbo = turboRequested
	turboRequested = false
	for _, ability in MODULES do
		local after = ability.afterStep
		if after then
			after(makeContext(base, ability, turbo))
		end
	end
end

-- kind: "Full" (T), "Checkpoint" (R/Crash), "Exit" (ausgestiegen)
function Abilities.reset(kind: string)
	for _, ability in MODULES do
		local reset = ability.reset
		if reset then
			reset(kind)
		end
	end
end

-- Zeilen fuer die Anzeige unten links (nur gekaufte Abilities)
function Abilities.hudRows(): { AbilityTypes.HudInfo }
	local rows = {}
	for _, ability in MODULES do
		local info = ability.hud(Abilities.getLevel(ability.id))
		if info then
			table.insert(rows, info)
		end
	end
	return rows
end

return Abilities
