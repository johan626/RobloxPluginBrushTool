--[[
	Brush Tool Plugin for Roblox Studio
	
	Allows developers to "paint" assets onto surfaces in the workspace.
	Features:
	- 3D Brush: Paint on any surface (floors, walls, ceilings).
	- Asset Management: Add models/parts from workspace to a persistent asset list.
	- Customizable Brush: Control radius, density, scale, rotation (X, Y, Z), and spacing.
	- Per-Asset Settings: Adjust Y-offset and surface alignment for each asset.
	- Eraser Mode: Erase previously painted objects, with an optional filter for specific assets.
	- Brush Stroke Mode: Paint continuously by holding and dragging the mouse.
	- Randomize Settings: Quickly generate new brush variations.
	- Avoid Overlap: Prevent painting on top of already-created objects.
]]

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")

-- Constants
local ASSET_FOLDER_NAME = "BrushToolAssets"
local WORKSPACE_FOLDER_NAME = "BrushToolCreations"
local SETTINGS_KEY = "BrushToolAssetOffsets_v2"
local PRESETS_KEY = "BrushToolPresets_v1"

-- Ensure assets folder exists
local assetsFolder = ServerStorage:FindFirstChild(ASSET_FOLDER_NAME)
if not assetsFolder then
	assetsFolder = Instance.new("Folder")
	assetsFolder.Name = ASSET_FOLDER_NAME
	assetsFolder.Parent = ServerStorage
end

-- State Variables
local assetOffsets = {}
local presets = {}
local selectedPreset = nil
local currentMode = "Paint" -- "Paint" or "Erase"
local active = false
local mouse = nil
local moveConn, downConn, upConn
local previewPart, cyl -- Will be created on activate
local isPainting = false
local lastPaintPosition = nil
local eraseFilter = {} -- Set of asset names to filter for when erasing
local avoidOverlap = false
local previewFolder = nil
local surfaceAngleMode = "Off" -- "Off", "Floor", "Wall"

local updatePresetListUI -- Forward-declare

-- UI Creation
local toolbar = plugin:CreateToolbar("Brush Tool")
local toolbarBtn = toolbar:CreateButton("Brush", "Toggle Brush Mode (toolbar)", "")

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	false,	-- Enabled
	false,	-- Floating
	380,	-- Width
	550,	-- Height
	300,	-- MinWidth
	200		-- MinHeight
)
local widget = plugin:CreateDockWidgetPluginGui("BrushToolWidget", widgetInfo)
widget.Title = "Brush Tool"
widget.Enabled = false -- show UI on load

-- Build UI inside widget
local ui = Instance.new("Frame")
ui.Size = UDim2.new(1, 0, 1, 0)
ui.BackgroundTransparency = 1
ui.Parent = widget

-- UI Helper Functions
local function makeLabel(text, y)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0.5, -8, 0, 22)
	lbl.Position = UDim2.new(0, 8, 0, y)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Font = Enum.Font.SourceSans
	lbl.TextSize = 14
	lbl.Parent = ui
	return lbl
end

local function makeTextBox(default, x, y, width)
	local tb = Instance.new("TextBox")
	tb.Size = UDim2.new(0, width or 120, 0, 26)
	tb.Position = UDim2.new(0, x, 0, y)
	tb.Text = tostring(default)
	tb.ClearTextOnFocus = false
	tb.Font = Enum.Font.SourceSans
	tb.TextSize = 14
	tb.Parent = ui
	return tb
end

-- Controls
makeLabel("Radius:", 8)
local radiusBox = makeTextBox(10, 180, 8, 180)

makeLabel("Density (per click):", 40)
local densityBox = makeTextBox(10, 180, 40, 180)

makeLabel("Scale min:", 72)
local scaleMinBox = makeTextBox(0.8, 180, 72, 80)
makeLabel("Scale max:", 72 + 32)
local scaleMaxBox = makeTextBox(1.3, 260, 72, 80)

makeLabel("Spacing (min distance):", 120)
local spacingBox = makeTextBox(1.5, 180, 120, 180)

makeLabel("Rotasi X min/maks (°):", 152)
local rotXMinBox = makeTextBox(0, 180, 152, 80)
local rotXMaxBox = makeTextBox(0, 280, 152, 80)

makeLabel("Rotasi Z min/maks (°):", 184)
local rotZMinBox = makeTextBox(0, 180, 184, 80)
local rotZMaxBox = makeTextBox(0, 280, 184, 80)

local addBtn = Instance.new("TextButton")
addBtn.Size = UDim2.new(0, 118, 0, 28)
addBtn.Position = UDim2.new(0, 8, 0, 216)
addBtn.Text = "Add Selected"
addBtn.Font = Enum.Font.SourceSans
addBtn.TextSize = 14
addBtn.Parent = ui

local randomizeBtn = Instance.new("TextButton")
randomizeBtn.Size = UDim2.new(0, 118, 0, 28)
randomizeBtn.Position = UDim2.new(0, 130, 0, 216)
randomizeBtn.Text = "Acak Pengaturan"
randomizeBtn.Font = Enum.Font.SourceSans
randomizeBtn.TextSize = 14
randomizeBtn.Parent = ui

local clearBtn = Instance.new("TextButton")
clearBtn.Size = UDim2.new(0, 118, 0, 28)
clearBtn.Position = UDim2.new(0, 252, 0, 216)
clearBtn.Text = "Clear Asset List"
clearBtn.Font = Enum.Font.SourceSans
clearBtn.TextSize = 14
clearBtn.Parent = ui

local modeToggleBtn = Instance.new("TextButton")
modeToggleBtn.Size = UDim2.new(0, 178, 0, 28)
modeToggleBtn.Position = UDim2.new(0, 8, 0, 250)
modeToggleBtn.Text = "Mode: Kuas"
modeToggleBtn.Font = Enum.Font.SourceSans
modeToggleBtn.TextSize = 14
modeToggleBtn.Parent = ui

local brushToggleBtn = Instance.new("TextButton")
brushToggleBtn.Size = UDim2.new(0, 178, 0, 28)
brushToggleBtn.Position = UDim2.new(0, 194, 0, 250)
brushToggleBtn.Text = "Brush: Off"
brushToggleBtn.Font = Enum.Font.SourceSans
brushToggleBtn.TextSize = 14
brushToggleBtn.Parent = ui

makeLabel("Hindari Tumpang Tindih:", 282)
local avoidOverlapBtn = Instance.new("TextButton")
avoidOverlapBtn.Size = UDim2.new(0, 180, 0, 28)
avoidOverlapBtn.Position = UDim2.new(0, 180, 0, 282)
avoidOverlapBtn.Font = Enum.Font.SourceSans
avoidOverlapBtn.TextSize = 14
avoidOverlapBtn.Parent = ui

makeLabel("Kunci Permukaan:", 282 + 32)
local surfaceAngleBtn = Instance.new("TextButton")
surfaceAngleBtn.Size = UDim2.new(0, 180, 0, 28)
surfaceAngleBtn.Position = UDim2.new(0, 180, 0, 282 + 32)
surfaceAngleBtn.Font = Enum.Font.SourceSans
surfaceAngleBtn.TextSize = 14
surfaceAngleBtn.Text = "Kunci Permukaan: Mati" -- Teks default
surfaceAngleBtn.Parent = ui

local assetsLabel = makeLabel("Per-Asset Settings:", 318)
assetsLabel.Size = UDim2.new(1, -16, 0, 22)

local assetListFrame = Instance.new("ScrollingFrame")
assetListFrame.Size = UDim2.new(1, -16, 1, -(346 + 150)) -- Adjust for preset frame
assetListFrame.Position = UDim2.new(0, 8, 0, 342)
assetListFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
assetListFrame.BorderSizePixel = 1
assetListFrame.ScrollBarThickness = 6
assetListFrame.Parent = ui

-- Presets UI
local presetFrame = Instance.new("Frame")
presetFrame.Size = UDim2.new(1, 0, 0, 150)
presetFrame.Position = UDim2.new(0, 0, 1, -150)
presetFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
presetFrame.BorderSizePixel = 0
presetFrame.Parent = ui

local presetLabel = makeLabel("Preset Kuas:", 0)
presetLabel.Parent = presetFrame
presetLabel.Position = UDim2.new(0, 8, 0, 5)

local presetList = Instance.new("ScrollingFrame")
presetList.Size = UDim2.new(1, -130, 1, -35)
presetList.Position = UDim2.new(0, 5, 0, 30)
presetList.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
presetList.Parent = presetFrame

local presetListLayout = Instance.new("UIListLayout")
presetListLayout.Padding = UDim.new(0, 2)
presetListLayout.SortOrder = Enum.SortOrder.Name
presetListLayout.Parent = presetList

local presetNameBox = makeTextBox("Nama Preset", 0, 0, 120)
presetNameBox.Position = UDim2.new(1, -125, 0, 30)
presetNameBox.Parent = presetFrame

local savePresetBtn = Instance.new("TextButton")
savePresetBtn.Size = UDim2.new(0, 120, 0, 28)
savePresetBtn.Position = UDim2.new(1, -125, 0, 60)
savePresetBtn.Text = "Simpan"
savePresetBtn.Font = Enum.Font.SourceSans; savePresetBtn.TextSize = 14
savePresetBtn.Parent = presetFrame

local loadPresetBtn = Instance.new("TextButton")
loadPresetBtn.Size = UDim2.new(0, 58, 0, 28)
loadPresetBtn.Position = UDim2.new(1, -125, 0, 90)
loadPresetBtn.Text = "Muat"
loadPresetBtn.Font = Enum.Font.SourceSans; loadPresetBtn.TextSize = 14
loadPresetBtn.Parent = presetFrame

local deletePresetBtn = Instance.new("TextButton")
deletePresetBtn.Size = UDim2.new(0, 58, 0, 28)
deletePresetBtn.Position = UDim2.new(1, -65, 0, 90)
deletePresetBtn.Text = "Hapus"
deletePresetBtn.Font = Enum.Font.SourceSans; deletePresetBtn.TextSize = 14
deletePresetBtn.Parent = presetFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = assetListFrame

-- Utility Functions
local function trim(s)
	return s:match("^%s*(.-)%s*$") or s
end

local function savePresets()
	local ok, jsonString = pcall(HttpService.JSONEncode, HttpService, presets)
	if ok then
		plugin:SetSetting(PRESETS_KEY, jsonString)
	else
		warn("Brush Tool: Gagal menyimpan preset! Error:", jsonString)
	end
end

local function loadPresets()
	local jsonString = plugin:GetSetting(PRESETS_KEY)
	if jsonString and #jsonString > 0 then
		local ok, data = pcall(HttpService.JSONDecode, HttpService, jsonString)
		if ok and type(data) == "table" then
			presets = data
		else
			presets = {}
		end
	else
		presets = {}
	end
end

local function persistOffsets()
	local ok, jsonString = pcall(HttpService.JSONEncode, HttpService, assetOffsets)
	if ok then
		plugin:SetSetting(SETTINGS_KEY, jsonString)
	else
		warn("Brush Tool: Gagal menyimpan offset aset! Error:", jsonString)
	end
end



local function deletePreset(name)
	if not name or not presets[name] then return end

	presets[name] = nil
	savePresets()

	if selectedPreset == name then
		selectedPreset = nil
		presetNameBox.Text = "Nama Preset"
	end

	updatePresetListUI()
end

local function parseNumber(txt, fallback)
	local ok, n = pcall(function()
		return tonumber(trim(txt))
	end)
	if ok and n then
		return n
	end
	return fallback
end


local function savePreset(name)
	if not name or name == "" or name == "Nama Preset" then
		warn("Brush Tool: Nama preset tidak valid.")
		return
	end

	local assetStates = {}
	for _, asset in ipairs(assetsFolder:GetChildren()) do
		local isActive = assetOffsets[asset.Name .. "_active"]
		if isActive == nil then isActive = true end
		assetStates[asset.Name] = isActive
	end

	presets[name] = {
		radius = parseNumber(radiusBox.Text, 10),
		density = parseNumber(densityBox.Text, 10),
		scaleMin = parseNumber(scaleMinBox.Text, 0.8),
		scaleMax = parseNumber(scaleMaxBox.Text, 1.3),
		spacing = parseNumber(spacingBox.Text, 1.5),
		rotXMin = parseNumber(rotXMinBox.Text, 0),
		rotXMax = parseNumber(rotXMaxBox.Text, 0),
		rotZMin = parseNumber(rotZMinBox.Text, 0),
		rotZMax = parseNumber(rotZMaxBox.Text, 0),
		avoidOverlap = avoidOverlap,
		surfaceAngleMode = surfaceAngleMode,
		assetStates = assetStates,
	}
	savePresets()
	updatePresetListUI()
end

local function loadOffsets()
	local jsonString = plugin:GetSetting(SETTINGS_KEY)
	if jsonString and #jsonString > 0 then
		local ok, data = pcall(HttpService.JSONDecode, HttpService, jsonString)
		if ok and type(data) == "table" then
			assetOffsets = data
		else
			assetOffsets = {}
		end
	else
		assetOffsets = {}
	end
end

local function randFloat(a, b)
	return a + math.random() * (b - a)
end

local function randomPointInCircle(radius)
	local r = radius * math.sqrt(math.random())
	local theta = math.random() * 2 * math.pi
	return Vector3.new(r * math.cos(theta), 0, r * math.sin(theta))
end

-- Asset and UI Management Functions
local function setupViewport(viewport, asset)
	-- Clean up previous content
	for _, child in ipairs(viewport:GetChildren()) do
		child:Destroy()
	end

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local clone = asset:Clone()

	-- Make sure all parts are anchored to prevent physics issues
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
		end
	end

	clone.Parent = worldModel

	-- Calculate camera position to frame the asset
	local ok, bboxCFrame, bboxSize = pcall(function()
		return clone:GetBoundingBox()
	end)

	if not ok or not bboxCFrame or not bboxSize then
		warn("Brush Tool: Could not get bounding box for asset preview: " .. clone.Name)
		clone:Destroy()
		return
	end

	local center = bboxCFrame.Position
	local largestDim = math.max(bboxSize.X, bboxSize.Y, bboxSize.Z)

	-- Add a small buffer so the asset isn't touching the edges
	largestDim = largestDim * 1.2
	if largestDim < 1 then
		largestDim = 1 -- Prevent assets that are too small from being too close
	end

	-- A bit of trigonometry to find the right distance for the camera
	local camDistance = (largestDim / 2) / math.tan(math.rad(camera.FieldOfView / 2))

	-- Position camera at an angle for a better, more isometric-style view
	local camOffset = Vector3.new(1, 0.8, 1).Unit * (camDistance + largestDim * 0.5)
	camera.CFrame = CFrame.new(center + camOffset, center)
end

local function updateAssetUIList()
	assetListFrame.CanvasPosition = Vector2.new(0, 0)
	for _, v in ipairs(assetListFrame:GetChildren()) do
		if v:IsA("GuiObject") then
			v:Destroy()
		end
	end

	local children = assetsFolder:GetChildren()
	local rowHeight = 70
	local canvasHeight = #children * rowHeight + (#children - 1) * listLayout.Padding.Offset
	assetListFrame.CanvasSize = UDim2.new(0, 0, 0, math.max(canvasHeight, 1))

	for i, asset in ipairs(children) do
		local assetName = asset.Name

		local offsetKey = assetName
		local alignKey = assetName .. "_align"
		local activeKey = assetName .. "_active"

		local row = Instance.new("Frame")
		row.Name = assetName .. "_Row"
		row.Size = UDim2.new(1, 0, 0, rowHeight)
		row.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		row.LayoutOrder = i
		row.Parent = assetListFrame

		local border = Instance.new("UIStroke")
		border.Color = Color3.fromRGB(255, 80, 80)
		border.Thickness = 0
		border.Parent = row

		-- ================= PERBAIKAN 1: Mulai =================
		-- Click detector for the entire row for erase filtering
		-- Ini harus dibuat SEBELUM tombol/textbox lain agar berada di lapisan bawah
		local rowButton = Instance.new("TextButton")
		rowButton.Size = UDim2.new(1, 0, 1, 0)
		rowButton.Text = ""
		rowButton.BackgroundTransparency = 1
		rowButton.ZIndex = 0 -- Pastikan di lapisan bawah
		rowButton.Parent = row

		local function updateEraseFilterAppearance()
			if eraseFilter[assetName] then
				border.Thickness = 2
			else
				border.Thickness = 0
			end
		end
		-- updateEraseFilterAppearance() -- Hapus dari sini, panggil di akhir loop

		rowButton.MouseButton1Click:Connect(function()
			if currentMode == "Erase" then
				eraseFilter[assetName] = not eraseFilter[assetName]
				updateEraseFilterAppearance()
			end
		end)
		-- ================= PERBAIKAN 1: Selesai =================

		-- Viewport Frame for visual preview
		local viewport = Instance.new("ViewportFrame")
		viewport.Size = UDim2.new(0, 64, 0, 64)
		viewport.Position = UDim2.new(0, 3, 0, 3)
		viewport.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
		viewport.Ambient = Color3.fromRGB(200, 200, 200)
		viewport.LightColor = Color3.fromRGB(150, 150, 150)
		viewport.LightDirection = Vector3.new(-1, -2, -0.5)
		viewport.Parent = row
		task.spawn(setupViewport, viewport, asset)

		-- "Active" toggle button
		local activeButton = Instance.new("TextButton")
		activeButton.Size = UDim2.new(0, 20, 0, 20)
		activeButton.Position = UDim2.new(0, 70, 0, 5)
		activeButton.Font = Enum.Font.SourceSans
		activeButton.Text = ""
		activeButton.Parent = row

		local function updateActiveButtonAppearance()
			local isActive = assetOffsets[activeKey]
			if isActive == nil then
				isActive = true
			end
			if isActive then
				activeButton.BackgroundColor3 = Color3.fromRGB(80, 160, 80) -- Green
				activeButton.Text = "✓"
			else
				activeButton.BackgroundColor3 = Color3.fromRGB(160, 80, 80) -- Red
				activeButton.Text = ""
			end
		end
		updateActiveButtonAppearance()

		-- Asset Name Label
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -95, 0, 20)
		lbl.Position = UDim2.new(0, 92, 0, 4)
		lbl.BackgroundTransparency = 1
		lbl.Text = assetName
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Font = Enum.Font.SourceSans
		lbl.TextSize = 14
		lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
		lbl.Parent = row

		-- Y-Offset TextBox
		local offsetBox = Instance.new("TextBox")
		offsetBox.Size = UDim2.new(0.5, -50, 0, 24)
		offsetBox.Position = UDim2.new(0, 72, 0, 32)
		offsetBox.Text = tostring(assetOffsets[offsetKey] or 0)
		offsetBox.ClearTextOnFocus = false
		offsetBox.Font = Enum.Font.SourceSans
		offsetBox.TextSize = 14
		offsetBox.Parent = row

		-- Align Toggle Button
		local alignButton = Instance.new("TextButton")
		alignButton.Name = "AlignButton"
		alignButton.Size = UDim2.new(0.5, -40, 0, 24)
		alignButton.Position = UDim2.new(0.5, 27, 0, 32)
		alignButton.Font = Enum.Font.SourceSans
		alignButton.TextSize = 13
		alignButton.Parent = row

		local function updateAlignButtonAppearance()
			local isAligning = assetOffsets[alignKey] or false
			if isAligning then
				alignButton.Text = "Selaras: Ya"
				alignButton.BackgroundColor3 = Color3.fromRGB(70, 115, 70) -- Green
			else
				alignButton.Text = "Selaras: Tdk"
				alignButton.BackgroundColor3 = Color3.fromRGB(115, 70, 70) -- Red
			end
		end
		updateAlignButtonAppearance()

		-- Connect Events for asset row controls
		activeButton.MouseButton1Click:Connect(function()
			local currentIsActive = assetOffsets[activeKey]
			if currentIsActive == nil then
				currentIsActive = true
			end
			assetOffsets[activeKey] = not currentIsActive
			persistOffsets()
			updateActiveButtonAppearance()
		end)

		offsetBox.FocusLost:Connect(function(enterPressed)
			local newValue = parseNumber(offsetBox.Text, 0)
			assetOffsets[offsetKey] = newValue
			offsetBox.Text = tostring(newValue)
			persistOffsets()
		end)

		alignButton.MouseButton1Click:Connect(function()
			assetOffsets[alignKey] = not (assetOffsets[alignKey] or false)
			updateAlignButtonAppearance()
			persistOffsets()
		end)

		-- Panggil ini di akhir loop
		updateEraseFilterAppearance()
	end
end

local function loadPreset(name)
	local data = presets[name]
	if not data then return end

	radiusBox.Text = tostring(data.radius)
	densityBox.Text = tostring(data.density)
	scaleMinBox.Text = tostring(data.scaleMin)
	scaleMaxBox.Text = tostring(data.scaleMax)
	spacingBox.Text = tostring(data.spacing)
	rotXMinBox.Text = tostring(data.rotXMin)
	rotXMaxBox.Text = tostring(data.rotXMax)
	rotZMinBox.Text = tostring(data.rotZMin)
	rotZMaxBox.Text = tostring(data.rotZMax)
	avoidOverlap = data.avoidOverlap
	avoidOverlapBtn.Text = avoidOverlap and "Ya" or "Tidak"

	surfaceAngleMode = data.surfaceAngleMode or "Off"
	if surfaceAngleMode == "Off" then
		surfaceAngleBtn.Text = "Kunci Permukaan: Mati"
	elseif surfaceAngleMode == "Floor" then
		surfaceAngleBtn.Text = "Kunci Permukaan: Lantai"
	else
		surfaceAngleBtn.Text = "Kunci Permukaan: Dinding"
	end

	if data.assetStates then
		for assetName, isActive in pairs(data.assetStates) do
			assetOffsets[assetName .. "_active"] = isActive
		end
	end

	updateAssetUIList()
	persistOffsets()
end

-- Core Logic Functions
local function getWorkspaceContainer()
	local container = workspace:FindFirstChild(WORKSPACE_FOLDER_NAME)
	if not container or not container:IsA("Folder") then
		container = Instance.new("Folder")
		container.Name = WORKSPACE_FOLDER_NAME
		container.Parent = workspace
	end
	return container
end

local function scaleModel(model, scale)
	local ok, bboxCFrame, bboxSize = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok then
		return
	end
	local center = bboxCFrame.Position
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = d.Position - center
			d.Size = d.Size * scale
			d.CFrame = CFrame.new(center + rel * scale) * (d.CFrame - d.CFrame.Position)
		elseif d:IsA("SpecialMesh") then
			d.Scale = d.Scale * scale
		elseif d:IsA("MeshPart") then
			pcall(function()
				d.Mesh.Scale = d.Mesh.Scale * scale
			end)
		end
	end
end

local function findSurfacePositionAndNormal()
	if not mouse then
		return nil, nil, nil
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil, nil
	end

	-- Create a ray from the camera to the mouse's position in 3D space
	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { previewFolder, getWorkspaceContainer() }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000, params)
	if result then
		return result.Position, result.Normal, result.Instance
	end
	return nil, nil, nil
end

local function paintAt(center, surfaceNormal)
	local radius = math.max(0.1, parseNumber(radiusBox.Text, 10))
	local smin = parseNumber(scaleMinBox.Text, 0.8)
	local smax = parseNumber(scaleMaxBox.Text, 1.2)
	local spacing = math.max(0.1, parseNumber(spacingBox.Text, 1.0))
	if smin <= 0 then
		smin = 0.1
	end
	if smax < smin then
		smax = smin
	end

	if avoidOverlap then
		local camera = workspace.CurrentCamera
		local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { previewFolder }
		params.FilterType = Enum.RaycastFilterType.Exclude
		local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000, params)
		if result and result.Instance:IsDescendantOf(getWorkspaceContainer()) then
			return -- Stop if we're trying to paint on an existing object
		end
	end

	ChangeHistoryService:SetWaypoint("Brush - Before Paint")

	local container = getWorkspaceContainer()
	local groupFolder = Instance.new("Folder")
	groupFolder.Name = "BrushGroup_" .. tostring(math.floor(os.time()))
	groupFolder.Parent = container

	local placed = {}

	-- Filter for only active assets
	local allAssets = assetsFolder:GetChildren()
	local activeAssets = {}
	for _, asset in ipairs(allAssets) do
		local isActive = assetOffsets[asset.Name .. "_active"]
		if isActive == nil then
			isActive = true -- Default to true if not set
		end
		if isActive then
			table.insert(activeAssets, asset)
		end
	end

	if #activeAssets == 0 then
		warn("Brush Tool: Tidak ada aset aktif yang dipilih untuk dilukis.")
		groupFolder:Destroy()
		ChangeHistoryService:SetWaypoint("Brush - Batal (Tidak ada aset aktif)")
		return
	end

	-- Create a CFrame aligned to the surface for placing objects
	local up = surfaceNormal
	local look = Vector3.new(1, 0, 0)
	if math.abs(up:Dot(look)) > 0.99 then
		look = Vector3.new(0, 0, 1)
	end
	local right = look:Cross(up).Unit
	local look_actual = up:Cross(right).Unit
	local planeCFrame = CFrame.fromMatrix(center, right, up, -look_actual)

	for i = 1, #activeAssets do
		local assetToClone = activeAssets[i]
		if not assetToClone then
			break
		end
		local clone = assetToClone:Clone()

		if clone:IsA("Model") and not clone.PrimaryPart then
			for _, v in ipairs(clone:GetDescendants()) do
				if v:IsA("BasePart") then
					clone.PrimaryPart = v
					break
				end
			end
		end

		local found = false
		local candidatePos = nil
		local candidateNormal = surfaceNormal
		local attempts = 0

		while not found and attempts < 12 do
			attempts = attempts + 1
			local offset2D = randomPointInCircle(radius)
			-- Transform the 2D offset to be relative to the surface plane
			local spawnPos = planeCFrame:PointToWorldSpace(Vector3.new(offset2D.X, 0, offset2D.Z))

			-- Raycast down to the surface from this point to handle non-flat surfaces
			local rayOrigin = spawnPos + surfaceNormal * 5
			local rayDir = -surfaceNormal * 10

			local params = RaycastParams.new()
			params.FilterDescendantsInstances = { previewFolder, container }
			params.FilterType = Enum.RaycastFilterType.Exclude
			local result = workspace:Raycast(rayOrigin, rayDir, params)

			if result then
				local posOnSurface = result.Position
				local ok = true
				for _, p in ipairs(placed) do
					if (p - posOnSurface).Magnitude < spacing then
						ok = false
						break
					end
				end
				if ok then
					found = true
					candidatePos = posOnSurface
					candidateNormal = result.Normal -- Use the normal from the specific point
				end
			end
		end

		if not candidatePos then
			clone:Destroy()
		else
			local s = randFloat(smin, smax)
			local rotXMin = math.rad(parseNumber(rotXMinBox.Text, 0))
			local rotXMax = math.rad(parseNumber(rotXMaxBox.Text, 0))
			local rotZMin = math.rad(parseNumber(rotZMinBox.Text, 0))
			local rotZMax = math.rad(parseNumber(rotZMaxBox.Text, 0))
			local xrot = randFloat(rotXMin, rotXMax)
			local yrot = math.rad(math.random() * 360)
			local zrot = randFloat(rotZMin, rotZMax)
			local randomRotation = CFrame.Angles(xrot, yrot, zrot)
			local assetName = assetToClone.Name -- Use original asset name for settings
			local customOffset = assetOffsets[assetName] or 0
			local shouldAlign = assetOffsets[assetName .. "_align"] or false

			if clone:IsA("Model") and clone.PrimaryPart then
				clone:SetPrimaryPartCFrame(CFrame.new(candidatePos))

				if math.abs(s - 1) > 0.0001 then
					scaleModel(clone, s)
				end

				local ok, bboxCFrame, bboxSize = pcall(function()
					return clone:GetBoundingBox()
				end)
				local finalPosition

				if ok then
					local pivotOffset = clone.PrimaryPart.Position - bboxCFrame.Position
					local worldPivot = CFrame.new(candidatePos) * pivotOffset
					local currentBottomY_inWorld = worldPivot.Y - (bboxSize.Y / 2)
					local shiftY_vector = candidateNormal * ((candidatePos.Y - currentBottomY_inWorld) + customOffset)
					finalPosition = clone:GetPrimaryPartCFrame().Position + shiftY_vector
				else
					warn("Tidak bisa mendapatkan bounding box untuk " .. clone.Name .. ", penempatan mungkin tidak akurat.")
					finalPosition = clone:GetPrimaryPartCFrame().Position + (candidateNormal * customOffset) -- Fallback
				end

				local finalCFrame
				if shouldAlign and candidateNormal then
					local rotatedCFrame = CFrame.new() * randomRotation
					local look = rotatedCFrame.LookVector
					local rightVec = look:Cross(candidateNormal).Unit
					local lookActual = candidateNormal:Cross(rightVec).Unit
					if rightVec.Magnitude < 0.9 then
						look = rotatedCFrame.RightVector
						rightVec = look:Cross(candidateNormal).Unit
						lookActual = candidateNormal:Cross(rightVec).Unit
					end
					finalCFrame = CFrame.fromMatrix(finalPosition, rightVec, candidateNormal, -lookActual)
				else
					finalCFrame = CFrame.new(finalPosition) * randomRotation
				end
				clone:SetPrimaryPartCFrame(finalCFrame)

			elseif clone:IsA("BasePart") then
				clone.Size = clone.Size * s
				local finalYOffset = (clone.Size.Y / 2) + customOffset
				local finalPos = candidatePos + (candidateNormal * finalYOffset)
				local finalCFrame
				if shouldAlign and candidateNormal then
					local rotatedCFrame = CFrame.new() * randomRotation
					local look = rotatedCFrame.LookVector
					local rightVec = look:Cross(candidateNormal).Unit
					local lookActual = candidateNormal:Cross(rightVec).Unit
					if rightVec.Magnitude < 0.9 then
						look = rotatedCFrame.RightVector
						rightVec = look:Cross(candidateNormal).Unit
						lookActual = candidateNormal:Cross(rightVec).Unit
					end
					finalCFrame = CFrame.fromMatrix(finalPos, rightVec, candidateNormal, -lookActual)
				else
					finalCFrame = CFrame.new(finalPos) * randomRotation
				end
				clone.CFrame = finalCFrame
			end

			clone.Parent = groupFolder
			table.insert(placed, candidatePos)
		end
	end

	if #groupFolder:GetChildren() == 0 then
		groupFolder:Destroy()
	end

	ChangeHistoryService:SetWaypoint("Brush - After Paint")
end

local function eraseAt(center)
	local radius = math.max(0.1, parseNumber(radiusBox.Text, 10))
	local container = workspace:FindFirstChild(WORKSPACE_FOLDER_NAME)
	if not container then
		return -- Nothing to erase
	end

	local itemsToDestroy = {} -- Use a set to prevent duplicates
	local allChildren = container:GetDescendants()

	for _, child in ipairs(allChildren) do
		if child:IsA("BasePart") or child:IsA("Model") then
			local part = child
			if child:IsA("Model") then
				part = child.PrimaryPart
			end

			if part and part.Parent then -- Check if part is not already destroyed
				-- A simplified distance check is sufficient and more robust for 3D erase
				if (part.Position - center).Magnitude <= radius then
					-- For models, we want to destroy the top-level ancestor inside the container
					local ancestorToDestroy = child
					while ancestorToDestroy and ancestorToDestroy.Parent ~= container and ancestorToDestroy.Parent ~= workspace do
						ancestorToDestroy = ancestorToDestroy.Parent
					end
					if ancestorToDestroy and ancestorToDestroy.Parent == container then
						-- Apply erase filter if it's not empty
						local filterActive = next(eraseFilter) ~= nil
						if not filterActive or eraseFilter[ancestorToDestroy.Name] then
							itemsToDestroy[ancestorToDestroy] = true -- Add to set
						end
					end
				end
			end
		end
	end

	-- Only create a waypoint if there is something to destroy
	if next(itemsToDestroy) ~= nil then
		ChangeHistoryService:SetWaypoint("Brush - Before Erase")
		for item, _ in pairs(itemsToDestroy) do
			item:Destroy()
		end

		-- Check if the container is now empty
		if #container:GetChildren() == 0 then
			container:Destroy()
		end

		ChangeHistoryService:SetWaypoint("Brush - After Erase")
	end
end

-- Mouse and Tool Activation Logic
local function updatePreview()
	if not mouse or not previewPart then
		return
	end

	if currentMode == "Paint" then
		previewPart.Color = Color3.fromRGB(80, 255, 80) -- Green for Paint
	else
		previewPart.Color = Color3.fromRGB(255, 80, 80) -- Red for Erase
	end

	local radius = math.max(0.1, parseNumber(radiusBox.Text, 10))
	local surfacePos, normal = findSurfacePositionAndNormal()

	if not surfacePos or not normal then
		previewPart.Parent = nil -- Hide
		return
	end

	previewPart.Parent = previewFolder

	local pos = surfacePos
	local look = Vector3.new(1, 0, 0)
	if math.abs(look:Dot(normal)) > 0.99 then
		look = Vector3.new(0, 0, 1)
	end
	local right = look:Cross(normal).Unit
	local lookActual = normal:Cross(right).Unit
	previewPart.CFrame = CFrame.fromMatrix(pos + normal * 0.05, right, normal, -lookActual)

	previewPart.Size = Vector3.new(1, 1, 1)
	cyl.Scale = Vector3.new(radius * 2, 0.02, radius * 2)
end

local function handlePaint(center, normal)
	if currentMode == "Paint" then
		paintAt(center, normal)
	else -- Erase mode
		eraseAt(center)
	end
	lastPaintPosition = center
end

local function onMove()
	if not active then
		return
	end

	updatePreview()

	if isPainting then
		local center, normal = findSurfacePositionAndNormal()
		if center and normal and lastPaintPosition then
			local spacing = math.max(0.1, parseNumber(spacingBox.Text, 1.0))
			if (center - lastPaintPosition).Magnitude >= spacing then
				handlePaint(center, normal)
			end
		end
	end
end

local function onDown()
	if not active or not mouse then
		return
	end
	isPainting = true
	local center, normal = findSurfacePositionAndNormal()
	if center and normal then
		handlePaint(center, normal)
	end
end

local function onUp()
	isPainting = false
	lastPaintPosition = nil
end

local function activate()
	if active then
		return
	end
	active = true

	-- Create preview part
	previewPart = Instance.new("Part")
	previewPart.Name = "BrushRadiusPreview"
	previewPart.Anchored = true
	previewPart.CanCollide = false
	previewPart.CanQuery = false
	previewPart.CanTouch = false
	previewPart.Transparency = 0.6
	previewPart.Size = Vector3.new(1, 1, 1)
	previewPart.Material = Enum.Material.Neon

	cyl = Instance.new("CylinderMesh")
	cyl.Scale = Vector3.new(1, 0.02, 1)
	cyl.Parent = previewPart

	plugin:Activate(true)
	mouse = plugin:GetMouse()
	moveConn = mouse.Move:Connect(onMove)
	downConn = mouse.Button1Down:Connect(onDown)
	upConn = mouse.Button1Up:Connect(onUp)
	updatePreview()
	brushToggleBtn.Text = "Brush: On"
	toolbarBtn:SetActive(true)
end

local function deactivate()
	if not active then
		return
	end
	active = false

	if moveConn then moveConn:Disconnect() moveConn = nil end
	if downConn then downConn:Disconnect() downConn = nil end
	if upConn then upConn:Disconnect() upConn = nil end

	isPainting = false -- Reset state on deactivate
	lastPaintPosition = nil
	mouse = nil

	if previewPart then
		previewPart:Destroy()
		previewPart = nil
		cyl = nil
	end

	brushToggleBtn.Text = "Brush: Off"
	toolbarBtn:SetActive(false)
end

local function toggle()
	if active then
		deactivate()
	else
		activate()
	end
end

-- Connect Global Button Events
toolbarBtn.Click:Connect(toggle)
brushToggleBtn.MouseButton1Click:Connect(toggle)
widget.Enabled = false

plugin.Unloading:Connect(function()
	if previewFolder and previewFolder.Parent then
		previewFolder:Destroy()
	end
end)

modeToggleBtn.MouseButton1Click:Connect(function()
	if currentMode == "Paint" then
		currentMode = "Erase"
		modeToggleBtn.Text = "Mode: Penghapus"
	else
		currentMode = "Paint"
		modeToggleBtn.Text = "Mode: Kuas"
		-- Clear filter when switching back to paint mode
		eraseFilter = {}
		updateAssetUIList()
	end
	updatePreview() -- Update preview color

	-- ================= PERBAIKAN 2: Mulai =================
	-- Event listener 'surfaceAngleBtn' dipindahkan ke luar dari fungsi ini
	-- ================= PERBAIKAN 2: Selesai ================
end)

function updatePresetListUI()
	for _, v in ipairs(presetList:GetChildren()) do
		if v:IsA("GuiObject") and not v:IsA("UIListLayout") then v:Destroy() end
	end

	local presetNames = {}
	for name, _ in pairs(presets) do
		table.insert(presetNames, name)
	end
	table.sort(presetNames)

	for _, name in ipairs(presetNames) do
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.Text = name
		btn.Size = UDim2.new(1, 0, 0, 24)
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.Font = Enum.Font.SourceSans; btn.TextSize = 14
		btn.Parent = presetList

		if name == selectedPreset then
			btn.BackgroundColor3 = Color3.fromRGB(80, 180, 255)
		end

		btn.MouseButton1Click:Connect(function()
			selectedPreset = name
			presetNameBox.Text = name
			updatePresetListUI()
		end)
	end
end

-- Initial Load and Print
loadOffsets()
loadPresets()
updateAssetUIList()
updatePresetListUI()

-- Final UI Connections
savePresetBtn.MouseButton1Click:Connect(function()
	savePreset(presetNameBox.Text)
end)

loadPresetBtn.MouseButton1Click:Connect(function()
	if selectedPreset then
		loadPreset(selectedPreset)
	end
end)

deletePresetBtn.MouseButton1Click:Connect(function()
	if selectedPreset then
		deletePreset(selectedPreset)
	end
end)

-- ================= PERBAIKAN 2: Ditempel di sini =================
surfaceAngleBtn.MouseButton1Click:Connect(function()
	if surfaceAngleMode == "Off" then
		surfaceAngleMode = "Floor"
		surfaceAngleBtn.Text = "Kunci Permukaan: Lantai"
	elseif surfaceAngleMode == "Floor" then
		surfaceAngleMode = "Wall"
		surfaceAngleBtn.Text = "Kunci Permukaan: Dinding"
	else -- Pasti "Wall"
		surfaceAngleMode = "Off"
		surfaceAngleBtn.Text = "Kunci Permukaan: Mati"
	end
end)
-- =================================================================

-- Initialize Preview Folder at a global scope
previewFolder = workspace:FindFirstChild("_BrushPreview")
if previewFolder then
	previewFolder:Destroy()
end
previewFolder = Instance.new("Folder")
previewFolder.Name = "_BrushPreview"
previewFolder.Parent = workspace

print("Brush Tool plugin loaded.")
