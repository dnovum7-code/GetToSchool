--!strict
-- Alle automatischen Tests ausfuehren:  lune run tests/run
-- Getestet wird die reine Logik aus src/shared/Progression (ohne Studio).

local process = require("@lune/process")
local TestLib = require("./TestLib")

local SPECS = {
	"./SaveDataSpec",
	"./EconomySpec",
	"./RunRulesSpec",
}

for _, path in SPECS do
	print("== " .. path)
	require(path)
end

local failed = TestLib.report()
process.exit(if failed > 0 then 1 else 0)
