--!strict
-- Winziges Test-Werkzeug fuer Lune (laeuft ohne Studio): describe / it / expect.

local TestLib = {}

type Result = { name: string, ok: boolean, message: string? }

local results: { Result } = {}
local prefix: { string } = {}

function TestLib.describe(name: string, body: () -> ())
	table.insert(prefix, name)
	body()
	table.remove(prefix)
end

function TestLib.it(name: string, body: () -> ())
	local fullName = table.concat(prefix, " > ") .. " > " .. name
	local ok, err = pcall(body)
	table.insert(results, { name = fullName, ok = ok, message = if ok then nil else tostring(err) })
end

local function show(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

export type Expectation = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
	toBeNear: (expected: number, tolerance: number?) -> (),
	toBeTruthy: () -> (),
	toBeFalsy: () -> (),
	toBeNil: () -> (),
	toBeGreaterThan: (number) -> (),
	toBeLessThan: (number) -> (),
}

function TestLib.expect(actual: any): Expectation
	local function fail(message: string)
		error(message, 3)
	end
	return {
		toBe = function(expected)
			if actual ~= expected then
				fail(`erwartet {show(expected)}, war {show(actual)}`)
			end
		end,
		toEqual = function(expected)
			if not deepEqual(actual, expected) then
				fail("Tabellen sind nicht gleich")
			end
		end,
		toBeNear = function(expected, tolerance)
			if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
				fail(`erwartet ca. {show(expected)}, war {show(actual)}`)
			end
		end,
		toBeTruthy = function()
			if not actual then
				fail(`erwartet wahr, war {show(actual)}`)
			end
		end,
		toBeFalsy = function()
			if actual then
				fail(`erwartet falsch, war {show(actual)}`)
			end
		end,
		toBeNil = function()
			if actual ~= nil then
				fail(`erwartet nil, war {show(actual)}`)
			end
		end,
		toBeGreaterThan = function(limit)
			if type(actual) ~= "number" or actual <= limit then
				fail(`erwartet > {show(limit)}, war {show(actual)}`)
			end
		end,
		toBeLessThan = function(limit)
			if type(actual) ~= "number" or actual >= limit then
				fail(`erwartet < {show(limit)}, war {show(actual)}`)
			end
		end,
	}
end

-- Ergebnis ausgeben; gibt die Anzahl der Fehlschlaege zurueck
function TestLib.report(): number
	local failed = 0
	for _, result in results do
		if result.ok then
			print("  ok    " .. result.name)
		else
			failed += 1
			print("  FEHLER " .. result.name .. "\n         " .. tostring(result.message))
		end
	end
	print(`\n{#results - failed} von {#results} Tests bestanden`)
	return failed
end

return TestLib
