--!strict
-- Reine Rechenlogik fuer das Plugin "Terrain-Import" (ohne Roblox-Objekte, mit Lune getestet):
-- Hoehendatei lesen, Lage der Voxel berechnen, Hoehe pro Voxel-Saeule abtasten und den
-- Fuellgrad (Occupancy) der Voxel an der Oberflaeche bestimmen.
--
-- Dateiformat: siehe tools/swissalti_to_terrain.py. Hoehen in Metern, Zeile 0 = Norden.
-- In Roblox: Osten = +X, Norden = -Z (Zeilen laufen also in +Z-Richtung).

local TerrainMath = {}

TerrainMath.VOXEL = 4 -- Roblox-Terrain: 1 Voxel = 4 x 4 x 4 Studs
TerrainMath.STUDS_PER_METER = 1 / 0.28

local HEADER_SIZE = 48

export type Data = {
	cols: number,
	rows: number,
	cellX: number, -- Meter pro Wert (Ost-West)
	cellZ: number, -- Meter pro Wert (Nord-Sued)
	minH: number,
	maxH: number,
	originE: number,
	originN: number,
	heights: buffer,
}

export type Layout = {
	x0: number, -- Welt-X der Westkante (Vielfaches von 4)
	z0: number, -- Welt-Z der Nordkante (Vielfaches von 4)
	nx: number, -- Voxel Ost-West
	nz: number, -- Voxel Nord-Sued
	studsPerMeter: number, -- waagerecht
	verticalScale: number, -- Studs pro Hoehenmeter (= studsPerMeter * Steigungsfaktor)
	baseY: number, -- Welt-Y des tiefsten Punkts
	yBottom: number, -- Unterkante des Unterbaus (Vielfaches von 4)
	yTop: number, -- Oberkante ueber dem hoechsten Punkt (Vielfaches von 4)
	samples: number, -- Abtastpunkte pro Voxel-Seite (Mittelwert, gegen Flimmern)
}

-- Liest die Datei. Gibt Data oder nil + Fehlertext zurueck.
function TerrainMath.parse(content: string): (Data?, string?)
	if #content < HEADER_SIZE then
		return nil, "Datei zu kurz - ist das eine .bin von swissalti_to_terrain.py?"
	end
	local b = buffer.fromstring(content)
	if buffer.readstring(b, 0, 4) ~= "GTST" then
		return nil, "Falsches Format (Kennung GTST fehlt) - Datei mit swissalti_to_terrain.py erzeugen."
	end
	local version = buffer.readu16(b, 4)
	if version ~= 1 then
		return nil, `Unbekannte Version {version} - Plugin aktualisieren.`
	end
	local cols = buffer.readu32(b, 8)
	local rows = buffer.readu32(b, 12)
	if cols < 2 or rows < 2 then
		return nil, "Zu wenige Werte (mindestens 2 x 2)."
	end
	local expected = HEADER_SIZE + cols * rows * 4
	if buffer.len(b) < expected then
		return nil, `Datei unvollstaendig ({buffer.len(b)} statt {expected} Bytes).`
	end
	local cellX = buffer.readf32(b, 16)
	local cellZ = buffer.readf32(b, 20)
	if not (cellX > 0 and cellZ > 0) then
		return nil, "Ungueltige Zellgroesse."
	end
	local heights = buffer.create(cols * rows * 4)
	buffer.copy(heights, 0, b, HEADER_SIZE, cols * rows * 4)
	return {
		cols = cols,
		rows = rows,
		cellX = cellX,
		cellZ = cellZ,
		minH = buffer.readf32(b, 24),
		maxH = buffer.readf32(b, 28),
		originE = buffer.readf64(b, 32),
		originN = buffer.readf64(b, 40),
		heights = heights,
	},
		nil
end

-- Groesse in Metern
function TerrainMath.sizeMeters(data: Data): (number, number)
	return data.cols * data.cellX, data.rows * data.cellZ
end

local function value(data: Data, col: number, row: number): number
	return buffer.readf32(data.heights, (row * data.cols + col) * 4)
end

-- Hoehe (m) an einer Stelle in Metern ab der Nordwest-Ecke, bilinear zwischen den Werten.
-- Werte gelten fuer die Mitte ihrer Zelle; am Rand wird der Randwert fortgesetzt.
function TerrainMath.heightAt(data: Data, east: number, south: number): number
	local u = math.clamp(east / data.cellX - 0.5, 0, data.cols - 1)
	local v = math.clamp(south / data.cellZ - 0.5, 0, data.rows - 1)
	local c0 = math.min(math.floor(u), data.cols - 2)
	local r0 = math.min(math.floor(v), data.rows - 2)
	local fu, fv = u - c0, v - r0
	local top = value(data, c0, r0) * (1 - fu) + value(data, c0 + 1, r0) * fu
	local bottom = value(data, c0, r0 + 1) * (1 - fu) + value(data, c0 + 1, r0 + 1) * fu
	return top * (1 - fv) + bottom * fv
end

local function snapDown(x: number): number
	return math.floor(x / TerrainMath.VOXEL) * TerrainMath.VOXEL
end

local function snapUp(x: number): number
	return math.ceil(x / TerrainMath.VOXEL) * TerrainMath.VOXEL
end

-- Lage des Gelaendes in der Welt. center = Mitte (X, Z), baseY = Hoehe des tiefsten Punkts.
function TerrainMath.layout(
	data: Data,
	width: number,
	slope: number,
	centerX: number,
	centerZ: number,
	baseY: number,
	baseDepth: number
): Layout
	local V = TerrainMath.VOXEL
	local widthM, depthM = TerrainMath.sizeMeters(data)
	local studsPerMeter = width / widthM
	local depth = depthM * studsPerMeter
	local verticalScale = studsPerMeter * slope
	local nx = math.max(1, math.ceil(width / V))
	local nz = math.max(1, math.ceil(depth / V))
	-- Wie viele Datenwerte fallen auf eine Voxel-Seite? Bei vielen wird gemittelt (bis 4 x 4).
	local cellStuds = math.min(data.cellX, data.cellZ) * studsPerMeter
	local samples = math.clamp(math.ceil(V / math.max(cellStuds, 0.001) - 0.01), 1, 4)
	return {
		x0 = snapDown(centerX - nx * V / 2),
		z0 = snapDown(centerZ - nz * V / 2),
		nx = nx,
		nz = nz,
		studsPerMeter = studsPerMeter,
		verticalScale = verticalScale,
		baseY = baseY,
		yBottom = snapDown(baseY - math.max(baseDepth, V)),
		yTop = snapUp(baseY + (data.maxH - data.minH) * verticalScale) + V,
		samples = samples,
	}
end

-- Hoehe der Oberflaeche (Welt-Y) fuer die Voxel-Saeule (i, k), 0-basiert.
-- Mittelwert ueber samples x samples Punkte im Voxel, damit feine Daten nicht flimmern.
function TerrainMath.surfaceY(data: Data, layout: Layout, i: number, k: number): number
	local V = TerrainMath.VOXEL
	local n = layout.samples
	local sum = 0
	for a = 0, n - 1 do
		for c = 0, n - 1 do
			local xStuds = (i + (a + 0.5) / n) * V
			local zStuds = (k + (c + 0.5) / n) * V
			sum += TerrainMath.heightAt(data, xStuds / layout.studsPerMeter, zStuds / layout.studsPerMeter)
		end
	end
	local meters = sum / (n * n)
	return layout.baseY + (meters - data.minH) * layout.verticalScale
end

-- Fuellgrad (0..1) eines Voxels mit Unterkante `voxelBottom` bei Oberflaeche `surface`.
-- Bruchteile an der Oberflaeche machen sie glatt (keine Stufen).
function TerrainMath.occupancy(surface: number, voxelBottom: number): number
	return math.clamp((surface - voxelBottom) / TerrainMath.VOXEL, 0, 1)
end

-- Spalte/Zeile des hoechsten Werts (fuer Schild und SpawnLocation am Start der Abfahrt)
function TerrainMath.highestCell(data: Data): (number, number)
	local best, bestCol, bestRow = -math.huge, 0, 0
	for row = 0, data.rows - 1 do
		for col = 0, data.cols - 1 do
			local h = value(data, col, row)
			if h > best then
				best, bestCol, bestRow = h, col, row
			end
		end
	end
	return bestCol, bestRow
end

-- Welt-X/Z der Mitte einer Datenzelle
function TerrainMath.cellToWorld(data: Data, layout: Layout, col: number, row: number): (number, number)
	return layout.x0 + (col + 0.5) * data.cellX * layout.studsPerMeter,
		layout.z0 + (row + 0.5) * data.cellZ * layout.studsPerMeter
end

return TerrainMath
