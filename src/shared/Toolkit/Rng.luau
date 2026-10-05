--!strict
-- Reproduzierbarer Zufall: gleiche Eingabe -> gleiche Zahl, auf jedem Client und in Tests.
-- Damit sehen alle Spieler dieselben Steine zur selben Zeit (Spawner im Dauerbetrieb),
-- obwohl jeder Client sie selbst erzeugt. Reine Logik ohne Roblox-Dienste.
-- Unity-Vergleich: wie Random.InitState(seed), nur ohne gemeinsamen Zustand.

local Rng = {}

local TWO_32 = 4294967296

-- a * b modulo 2^32, ohne Genauigkeit zu verlieren (Luau rechnet mit double)
local function mulMod32(a: number, b: number): number
	local aHigh = a // 65536
	local aLow = a % 65536
	return ((aHigh * b % TWO_32) * 65536 + aLow * b) % TWO_32
end

-- Mischt eine ganze Zahl (0 .. 2^32-1) gruendlich durch
local function mix(value: number): number
	local x = value % TWO_32
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = mulMod32(x, 0x45D9F3B)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = mulMod32(x, 0x45D9F3B)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	return x
end

-- Zahl 0 <= r < 1 fuer (seed, index, salt). `salt` unterscheidet mehrere Zufallswerte
-- desselben Ereignisses (z. B. 1 = Position X, 2 = Tempo ...).
function Rng.at(seed: number, index: number, salt: number?): number
	local h = mix(math.floor(seed) % TWO_32)
	h = mix(bit32.bxor(h, math.floor(index) % TWO_32))
	h = mix(bit32.bxor(h, math.floor(salt or 0) % TWO_32))
	return h / TWO_32
end

-- Zahl zwischen min und max
function Rng.range(seed: number, index: number, salt: number, min: number, max: number): number
	return min + (max - min) * Rng.at(seed, index, salt)
end

-- Text -> Zahl (z. B. Name oder Id eines Bausteins als Seed)
function Rng.seedFromString(text: string): number
	local h = 2166136261
	for i = 1, #text do
		h = bit32.bxor(h, string.byte(text, i))
		h = mulMod32(h, 16777619)
	end
	return h
end

return Rng
