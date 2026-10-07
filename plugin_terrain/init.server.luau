--!strict
-- Studio-Plugin "Terrain-Import": baut Gelaende aus einer Hoehendatei (.bin) von
-- tools/swissalti_to_terrain.py. Das Terrain wird direkt mit Terrain:WriteVoxels geschrieben,
-- mit Bruchteil-Fuellung (Occupancy) an der Oberflaeche - dadurch glatt, ohne Treppenstufen
-- (der Heightmap-Import von Roblox rundet dagegen auf Stufen).
-- Installieren/aktualisieren: siehe README, Abschnitt "Terrain-Import (Studio-Plugin)".
--
-- Vergleichsmodus: baut dieselbe Datei mehrmals nebeneinander mit verschiedenen
-- Steigungsfaktoren (Config.TerrainImport.CompareFactors), je mit Schild und SpawnLocation.
-- Im Spiel startet der Wagen an der aktiven Varianten-SpawnLocation (Config.Debug.TerrainTestSpawn).
--
-- Unity-Vergleich: wie ein Editor-Fenster (EditorWindow), das TerrainData.SetHeights aufruft.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StudioService = game:GetService("StudioService")

local TerrainMath = require(script:WaitForChild("TerrainMath"))

-- Im laufenden Spiel (Play-Test) nichts tun
if RunService:IsRunning() then
	return
end

local VOXEL = TerrainMath.VOXEL
local VARIANTS_FOLDER = "TerrainVergleich"

-- Vorgaben aus der Config des Spiels (falls lesbar)
local config: any = nil
pcall(function()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild("Config")
	if module and module:IsA("ModuleScript") then
		config = (require :: any)(module)
	end
end)

local function default(key: string, fallback: any): any
	local section = config and config.TerrainImport
	local value = if type(section) == "table" then section[key] else nil
	return if value ~= nil then value else fallback
end

local MATERIALS: { string } = default("Materials", { "Grass", "Ground", "Rock", "Sand", "Snow" })
local COMPARE_FACTORS: { number } = default("CompareFactors", { 1, 1.25, 1.5, 1.75, 2 })
local CHUNK = math.max(4, math.floor(default("ChunkVoxels", 32)))

-- Gespeicherte Eingaben (bleiben zwischen Studio-Sitzungen)
local function setting(name: string, fallback: any): any
	local value = plugin:GetSetting(name)
	return if value ~= nil then value else fallback
end

local state = {
	posX = setting("PosX", 0) :: number,
	posY = setting("PosY", 0) :: number,
	posZ = setting("PosZ", 0) :: number,
	width = setting("Width", default("Width", 2000)) :: number,
	slope = setting("Slope", default("SlopeFactor", 1)) :: number,
	material = setting("Material", default("Material", "Grass")) :: string,
	baseDepth = default("BaseDepth", 16) :: number,
	gap = default("CompareGap", 100) :: number,
}

local data: TerrainMath.Data? = nil
local fileName = ""
local busy = false
local cancelRequested = false

local function materialEnum(name: string): Enum.Material
	local ok, value = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and value then value else Enum.Material.Grass
end

-- UI ------------------------------------------------------------------------------------------

local toolbar = plugin:CreateToolbar("Get to School")
local button = toolbar:CreateButton(
	"Terrain-Import",
	"Gelaende aus swissALTI3D-Hoehendaten bauen (glatt, ohne Stufen)",
	"rbxasset://textures/ui/GuiImagePlaceholder.png"
)
button.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGui(
	"GetToSchoolTerrainImport",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 340, 620, 300, 400)
)
widget.Title = "Terrain-Import"
widget.Name = "GetToSchoolTerrainImport"
button:SetActive(widget.Enabled)
button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	button:SetActive(widget.Enabled)
end)

local theme = settings().Studio.Theme
local function color(style: Enum.StudioStyleGuideColor): Color3
	return theme:GetColor(style)
end

local root = Instance.new("ScrollingFrame")
root.Size = UDim2.fromScale(1, 1)
root.CanvasSize = UDim2.new()
root.AutomaticCanvasSize = Enum.AutomaticSize.Y
root.ScrollBarThickness = 6
root.BorderSizePixel = 0
root.BackgroundColor3 = color(Enum.StudioStyleGuideColor.MainBackground)
root.Parent = widget

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingRight = UDim.new(0, 12)
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.Parent = root

local list = Instance.new("UIListLayout")
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 6)
list.Parent = root

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function label(text: string, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.LayoutOrder = nextOrder()
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.BackgroundTransparency = 1
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Font = if bold then Enum.Font.SourceSansBold else Enum.Font.SourceSans
	l.TextSize = if bold then 17 else 15
	l.TextColor3 = color(Enum.StudioStyleGuideColor.MainText)
	l.Text = text
	l.Parent = root
	return l
end

local function makeButton(text: string, onClick: () -> (), parent: Instance?, accent: boolean?): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 28)
	b.Font = Enum.Font.SourceSansBold
	b.TextSize = 15
	b.Text = text
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.BackgroundColor3 = if accent
		then color(Enum.StudioStyleGuideColor.DialogMainButton)
		else color(Enum.StudioStyleGuideColor.Button)
	b.TextColor3 = if accent
		then color(Enum.StudioStyleGuideColor.DialogMainButtonText)
		else color(Enum.StudioStyleGuideColor.ButtonText)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = b
	if parent then
		b.Parent = parent
	else
		b.LayoutOrder = nextOrder()
		b.Parent = root
	end
	b.Activated:Connect(onClick)
	return b
end

-- Eingabefeld fuer eine Zahl: Beschriftung links, Feld rechts
local function numberInput(caption: string, initial: number, onChanged: (number) -> ()): TextBox
	local row = Instance.new("Frame")
	row.LayoutOrder = nextOrder()
	row.Size = UDim2.new(1, 0, 0, 26)
	row.BackgroundTransparency = 1
	row.Parent = root

	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(0.55, 0, 1, 0)
	l.BackgroundTransparency = 1
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Font = Enum.Font.SourceSans
	l.TextSize = 15
	l.TextColor3 = color(Enum.StudioStyleGuideColor.MainText)
	l.Text = caption
	l.Parent = row

	local box = Instance.new("TextBox")
	box.Position = UDim2.fromScale(0.55, 0)
	box.Size = UDim2.new(0.45, 0, 1, 0)
	box.Font = Enum.Font.SourceSans
	box.TextSize = 15
	box.ClearTextOnFocus = false
	box.BorderSizePixel = 0
	box.BackgroundColor3 = color(Enum.StudioStyleGuideColor.InputFieldBackground)
	box.TextColor3 = color(Enum.StudioStyleGuideColor.MainText)
	box.Text = tostring(initial)
	box.Parent = row
	box.FocusLost:Connect(function()
		local value = tonumber((string.gsub(box.Text, ",", ".")))
		if value then
			onChanged(value)
		end
	end)
	return box
end

label("Terrain-Import (swissALTI3D)", true)
local fileLabel = label("Keine Datei geladen. Datei mit tools/swissalti_to_terrain.py erzeugen.")

local summaryLabel: TextLabel
local function updateSummary()
	if not data then
		summaryLabel.Text = ""
		return
	end
	local widthM, depthM = TerrainMath.sizeMeters(data)
	local spm = state.width / widthM
	local height = (data.maxH - data.minH) * spm * state.slope
	summaryLabel.Text = string.format(
		"Ergebnis: %.0f x %.0f Studs (Ost-West x Nord-Sued), Hoehe %.0f Studs. 1 Stud = %.2f m.",
		state.width,
		depthM * spm,
		height,
		1 / spm
	)
end

local function chooseFile()
	if busy then
		return
	end
	-- Erst nur .bin anbieten; falls Studio das ablehnt, alle Dateien
	local ok, file = pcall(function()
		return StudioService:PromptImportFile({ "bin" })
	end)
	if not ok then
		ok, file = pcall(function()
			return StudioService:PromptImportFile()
		end)
	end
	if not ok or not file then
		return
	end
	local contentOk, content = pcall(function()
		return (file :: any):GetBinaryContents()
	end)
	if not contentOk then
		fileLabel.Text = "Datei konnte nicht gelesen werden: " .. tostring(content)
		return
	end
	local parsed, err = TerrainMath.parse(content)
	if not parsed then
		data = nil
		fileLabel.Text = "Fehler: " .. tostring(err)
		updateSummary()
		return
	end
	data = parsed
	fileName = (file :: any).Name
	local widthM, depthM = TerrainMath.sizeMeters(parsed)
	fileLabel.Text = string.format(
		"%s\n%d x %d Werte, %.0f x %.0f m, Hoehe %.1f bis %.1f m ü. M.",
		fileName,
		parsed.cols,
		parsed.rows,
		widthM,
		depthM,
		parsed.minH,
		parsed.maxH
	)
	updateSummary()
end

makeButton("Datei wählen (.bin)", chooseFile, nil, true)

label("Lage: Mitte (X, Z) und Höhe des tiefsten Punkts (Y). Norden = -Z.")
local posXBox = numberInput("Position X", state.posX, function(v)
	state.posX = v
	plugin:SetSetting("PosX", v)
end)
numberInput("Position Y (tiefster Punkt)", state.posY, function(v)
	state.posY = v
	plugin:SetSetting("PosY", v)
end)
local posZBox = numberInput("Position Z", state.posZ, function(v)
	state.posZ = v
	plugin:SetSetting("PosZ", v)
end)
makeButton("X/Z = Kamera-Mitte", function()
	local focus = workspace.CurrentCamera.Focus.Position
	state.posX = math.floor(focus.X / VOXEL + 0.5) * VOXEL
	state.posZ = math.floor(focus.Z / VOXEL + 0.5) * VOXEL
	posXBox.Text = tostring(state.posX)
	posZBox.Text = tostring(state.posZ)
	plugin:SetSetting("PosX", state.posX)
	plugin:SetSetting("PosZ", state.posZ)
end)
numberInput("Zielbreite (Studs)", state.width, function(v)
	state.width = math.max(v, 16)
	plugin:SetSetting("Width", state.width)
	updateSummary()
end)
numberInput("Steigungsfaktor", state.slope, function(v)
	state.slope = math.max(v, 0.05)
	plugin:SetSetting("Slope", state.slope)
	updateSummary()
end)

local materialButton: TextButton
materialButton = makeButton("Material: " .. state.material, function()
	local index = table.find(MATERIALS, state.material) or 0
	state.material = MATERIALS[index % #MATERIALS + 1]
	plugin:SetSetting("Material", state.material)
	materialButton.Text = "Material: " .. state.material
end)

summaryLabel = label("")

-- Fortschritt
local progressBack = Instance.new("Frame")
progressBack.LayoutOrder = nextOrder()
progressBack.Size = UDim2.new(1, 0, 0, 10)
progressBack.BorderSizePixel = 0
progressBack.BackgroundColor3 = color(Enum.StudioStyleGuideColor.InputFieldBackground)
progressBack.Parent = root
local progressBar = Instance.new("Frame")
progressBar.Size = UDim2.fromScale(0, 1)
progressBar.BorderSizePixel = 0
progressBar.BackgroundColor3 = Color3.fromRGB(80, 200, 110)
progressBar.Parent = progressBack
local statusLabel = label("Bereit.")

local function setProgress(fraction: number, text: string)
	progressBar.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	statusLabel.Text = text
end

-- Terrain schreiben -------------------------------------------------------------------------

-- Bereich (Voxel-Raster) einer Lage in Welt-Studs
local function regionOf(layout: TerrainMath.Layout): (Vector3, Vector3)
	return Vector3.new(layout.x0, layout.yBottom, layout.z0),
		Vector3.new(layout.x0 + layout.nx * VOXEL, layout.yTop, layout.z0 + layout.nz * VOXEL)
end

-- Schreibt eine Lage in Abschnitten (CHUNK x CHUNK Saeulen), damit Studio nicht einfriert.
-- report(fertigeAbschnitte, alleAbschnitte). Gibt false zurueck, wenn abgebrochen.
local function writeLayout(
	source: TerrainMath.Data,
	layout: TerrainMath.Layout,
	material: Enum.Material,
	report: (number, number) -> ()
): boolean
	local terrain = workspace.Terrain
	local ny = math.floor((layout.yTop - layout.yBottom) / VOXEL + 0.5)
	local chunksX = math.ceil(layout.nx / CHUNK)
	local chunksZ = math.ceil(layout.nz / CHUNK)
	local total = chunksX * chunksZ
	local done = 0
	for cz = 0, chunksZ - 1 do
		for cx = 0, chunksX - 1 do
			if cancelRequested then
				return false
			end
			local i0, k0 = cx * CHUNK, cz * CHUNK
			local sx = math.min(CHUNK, layout.nx - i0)
			local sz = math.min(CHUNK, layout.nz - k0)

			-- Oberflaeche jeder Saeule in diesem Abschnitt
			local surface: { { number } } = table.create(sx)
			for a = 1, sx do
				local column = table.create(sz)
				for c = 1, sz do
					column[c] = TerrainMath.surfaceY(source, layout, i0 + a - 1, k0 + c - 1)
				end
				surface[a] = column
			end

			-- Arrays [x][y][z] fuer WriteVoxels; ueber der Oberflaeche Luft (raeumt alte Reste weg)
			local materials = table.create(sx)
			local occupancies = table.create(sx)
			for a = 1, sx do
				local matX = table.create(ny)
				local occX = table.create(ny)
				local column = surface[a]
				for b = 1, ny do
					local bottom = layout.yBottom + (b - 1) * VOXEL
					local matY = table.create(sz)
					local occY = table.create(sz)
					for c = 1, sz do
						local occ = TerrainMath.occupancy(column[c], bottom)
						occY[c] = occ
						matY[c] = if occ > 0 then material else Enum.Material.Air
					end
					matX[b] = matY
					occX[b] = occY
				end
				materials[a] = matX
				occupancies[a] = occX
			end

			local min = Vector3.new(layout.x0 + i0 * VOXEL, layout.yBottom, layout.z0 + k0 * VOXEL)
			local max = min + Vector3.new(sx * VOXEL, ny * VOXEL, sz * VOXEL)
			terrain:WriteVoxels(Region3.new(min, max), VOXEL, materials, occupancies)

			done += 1
			report(done, total)
			task.wait() -- Studio kurz Luft lassen (Fortschritt zeichnen, Eingaben)
		end
	end
	return true
end

-- Leert einen Bereich (Luft), ebenfalls in Abschnitten
local function clearRegion(min: Vector3, max: Vector3)
	local terrain = workspace.Terrain
	local step = CHUNK * VOXEL
	local x = min.X
	while x < max.X do
		local z = min.Z
		while z < max.Z do
			local a = Vector3.new(x, min.Y, z)
			local b = Vector3.new(math.min(x + step, max.X), max.Y, math.min(z + step, max.Z))
			terrain:FillRegion(Region3.new(a, b):ExpandToGrid(VOXEL), VOXEL, Enum.Material.Air)
			z += step
		end
		x += step
		task.wait()
	end
end

-- Arbeit mit Rueckgaengig-Eintrag (Strg+Z) und Fehlerbehandlung ausfuehren
local function runJob(name: string, job: () -> string)
	if busy then
		return
	end
	busy = true
	cancelRequested = false
	local recording = ChangeHistoryService:TryBeginRecording(name)
	local ok, result = xpcall(job, debug.traceback)
	if recording then
		ChangeHistoryService:FinishRecording(
			recording,
			if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
	end
	busy = false
	if ok then
		setProgress(1, result)
	else
		setProgress(0, "Fehler: " .. tostring(result))
		warn("[Terrain-Import] " .. tostring(result))
	end
end

local function buildSingle()
	local source = data
	if not source then
		setProgress(0, "Erst eine Datei wählen.")
		return
	end
	runJob("Terrain-Import", function()
		local layout = TerrainMath.layout(
			source,
			state.width,
			state.slope,
			state.posX,
			state.posZ,
			state.posY,
			state.baseDepth
		)
		local started = os.clock()
		local finished = writeLayout(source, layout, materialEnum(state.material), function(done, total)
			setProgress(done / total, string.format("Schreibe Abschnitt %d von %d ...", done, total))
		end)
		if not finished then
			return "Abgebrochen (bisher Geschriebenes bleibt; Strg+Z macht es rückgängig)."
		end
		return string.format("Fertig in %.1f s. Strg+Z macht es rückgängig.", os.clock() - started)
	end)
end

-- Vergleichsmodus -------------------------------------------------------------------------------

local spawnRow: Frame

local function variantsFolder(create: boolean): Folder?
	local folder = workspace:FindFirstChild(VARIANTS_FOLDER)
	if folder and folder:IsA("Folder") then
		return folder
	end
	if not create then
		return nil
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = VARIANTS_FOLDER
	newFolder.Parent = workspace
	return newFolder
end

local function variantModels(): { Model }
	local result = {}
	local folder = variantsFolder(false)
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") and type(child:GetAttribute("Factor")) == "number" then
				table.insert(result, child)
			end
		end
	end
	table.sort(result, function(a, b)
		return (a:GetAttribute("Factor") :: number) < (b:GetAttribute("Factor") :: number)
	end)
	return result
end

-- Nur die SpawnLocation dieser Variante ist aktiv (dort startet die Figur und der Wagen)
local refreshSpawnButtons: () -> ()
local function activateVariant(model: Model)
	for _, other in variantModels() do
		local spawn = other:FindFirstChildWhichIsA("SpawnLocation")
		if spawn then
			spawn.Enabled = other == model
		end
	end
	ChangeHistoryService:SetWaypoint("Terrain-Variante aktivieren")
	refreshSpawnButtons()
	statusLabel.Text = `Aktiv: {model.Name}. Play drücken zum Testen.`
end

refreshSpawnButtons = function()
	for _, child in spawnRow:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local models = variantModels()
	spawnRow.Visible = #models > 0
	for _, model in models do
		local spawn = model:FindFirstChildWhichIsA("SpawnLocation")
		local active = spawn ~= nil and spawn.Enabled
		local factor = model:GetAttribute("Factor") :: number
		local b = makeButton((if active then "● " else "") .. string.format("%g", factor), function()
			activateVariant(model)
		end, spawnRow, active)
		b.Size = UDim2.new(0, 56, 0, 26)
	end
end

-- Schild (Pfosten mit Schrift, von allen Seiten lesbar) und SpawnLocation am hoechsten Punkt
local function addMarkers(
	model: Model,
	source: TerrainMath.Data,
	layout: TerrainMath.Layout,
	index: number,
	factor: number
)
	local col, row = TerrainMath.highestCell(source)
	local x, z = TerrainMath.cellToWorld(source, layout, col, row)
	-- Oberflaeche genau treffen (Raycast aufs gerade gebaute Terrain)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local top = Vector3.new(x, layout.yTop + 8, z)
	local hit = workspace:Raycast(top, Vector3.new(0, -(layout.yTop - layout.yBottom + 16), 0), params)
	local groundY = if hit
		then hit.Position.Y
		else layout.baseY + (source.maxH - source.minH) * layout.verticalScale

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Enabled = index == 1
	spawn.CFrame = CFrame.new(x, groundY + 0.5, z)
	spawn:SetAttribute("TerrainTest", true)
	spawn.Parent = model

	local post = Instance.new("Part")
	post.Name = "Schild"
	post.Anchored = true
	post.Size = Vector3.new(0.6, 8, 0.6)
	post.CFrame = CFrame.new(x + 6, groundY + 4, z)
	post.Color = Color3.fromRGB(120, 90, 60)
	post.Material = Enum.Material.Wood
	post.Parent = model

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(14, 0, 4, 0) -- in Studs
	gui.StudsOffset = Vector3.new(0, 6, 0)
	gui.LightInfluence = 0
	gui.Parent = post
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundColor3 = Color3.fromRGB(30, 90, 50)
	text.BackgroundTransparency = 0.1
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.Text = string.format("Variante %d\nSteigung ×%g", index, factor)
	text.Parent = gui
end

local function buildCompare()
	local source = data
	if not source then
		setProgress(0, "Erst eine Datei wählen.")
		return
	end
	runJob("Terrain-Vergleich", function()
		-- Alte Varianten zuerst wegraeumen (sie koennten an anderer Stelle liegen)
		for _, old in variantModels() do
			local min = old:GetAttribute("RegionMin")
			local max = old:GetAttribute("RegionMax")
			if typeof(min) == "Vector3" and typeof(max) == "Vector3" then
				setProgress(0, "Räume alte Varianten weg ...")
				clearRegion(min, max)
			end
			old:Destroy()
		end
		local folder = variantsFolder(true) :: Folder
		local material = materialEnum(state.material)
		local count = #COMPARE_FACTORS
		local started = os.clock()
		for index, factor in COMPARE_FACTORS do
			local centerX = state.posX + (index - 1) * (state.width + state.gap)
			local layout = TerrainMath.layout(
				source,
				state.width,
				factor,
				centerX,
				state.posZ,
				state.posY,
				state.baseDepth
			)
			local name = string.format("Steigung %g", factor)
			local finished = writeLayout(source, layout, material, function(done, total)
				setProgress(
					((index - 1) + done / total) / count,
					string.format(
						"Variante %d von %d (×%g): Abschnitt %d von %d",
						index,
						count,
						factor,
						done,
						total
					)
				)
			end)
			if not finished then
				refreshSpawnButtons()
				return "Abgebrochen."
			end
			local model = Instance.new("Model")
			model.Name = name
			local min, max = regionOf(layout)
			model:SetAttribute("Factor", factor)
			model:SetAttribute("RegionMin", min)
			model:SetAttribute("RegionMax", max)
			model.Parent = folder
			addMarkers(model, source, layout, index, factor)
		end
		refreshSpawnButtons()
		return string.format(
			"%d Varianten fertig in %.0f s. Aktive Variante unten wählen, dann Play.",
			count,
			os.clock() - started
		)
	end)
end

local function deleteVariants()
	runJob("Terrain-Vergleich löschen", function()
		local models = variantModels()
		for index, model in models do
			if cancelRequested then
				refreshSpawnButtons()
				return "Abgebrochen."
			end
			setProgress((index - 1) / #models, string.format("Lösche %s ...", model.Name))
			local min = model:GetAttribute("RegionMin")
			local max = model:GetAttribute("RegionMax")
			if typeof(min) == "Vector3" and typeof(max) == "Vector3" then
				clearRegion(min, max)
			end
			model:Destroy()
		end
		local folder = variantsFolder(false)
		if folder and #folder:GetChildren() == 0 then
			folder:Destroy()
		end
		refreshSpawnButtons()
		return string.format("%d Varianten gelöscht.", #models)
	end)
end

makeButton("Terrain bauen", buildSingle, nil, true)
local factorTexts = {}
for _, f in COMPARE_FACTORS do
	table.insert(factorTexts, string.format("%g", f))
end
label(
	"Vergleich: baut die Datei nebeneinander (+X) mit Steigung "
		.. table.concat(factorTexts, ", ")
		.. " - je mit Schild und SpawnLocation."
)
makeButton("Vergleich bauen", buildCompare)
label("Aktive Variante (dort startest du im Spiel):")
spawnRow = Instance.new("Frame")
spawnRow.LayoutOrder = nextOrder()
spawnRow.Size = UDim2.new(1, 0, 0, 26)
spawnRow.BackgroundTransparency = 1
spawnRow.Parent = root
local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.Padding = UDim.new(0, 4)
rowLayout.Parent = spawnRow
makeButton("Varianten löschen", deleteVariants)
makeButton("Abbrechen", function()
	if busy then
		cancelRequested = true
		statusLabel.Text = "Breche ab ..."
	end
end)
label(
	"Quellenangabe im Spiel nicht vergessen: "
		.. tostring(default("Attribution", "Höhendaten: © swisstopo"))
)

updateSummary()
refreshSpawnButtons()
