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
local CollectionService = game:GetService("CollectionService")

-- Constants
local ASSET_FOLDER_NAME = "BrushToolAssets"
local WORKSPACE_FOLDER_NAME = "BrushToolCreations"
local SETTINGS_KEY = "BrushToolAssetOffsets_v2"
local PRESETS_KEY = "BrushToolPresets_v1"
local PALETTES_KEY = "BrushToolPalettes_v1"

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
local assetPalettes = {}
local selectedPalette = nil
local currentMode = "Paint" -- "Paint", "Line", or "Erase"
local active = false
local mouse = nil
local moveConn, downConn, upConn
local previewPart, cyl -- Will be created on activate
local isPainting = false
local lastPaintPosition = nil
local lineStartPoint = nil -- For Line tool
local linePreviewPart = nil -- Visual for line tool
local curvePoints = {} -- For Curve tool
local curvePreviewFolder = nil -- Visual for curve tool
local splinePoints = {} -- For Spline tool
local splinePreviewFolder = nil -- Visual for spline tool
local splineFollowPath = false
local splineCloseLoop = false
local cableStartPoint = nil -- For Cable tool
local cablePreviewFolder = nil -- Visual for cable tool
local createCable -- Forward-declare
local cableColor = Color3.fromRGB(50, 50, 50)
local cableMaterial = Enum.Material.Plastic
local partToFill = nil -- For Fill tool
local fillSelectionBox = nil -- Visual for Fill tool
local sourceAsset = nil -- For Replace tool
local physicsModeEnabled = false
local physicsSettleTime = 1.5
local targetAsset = nil -- For Replace tool
local eraseFilter = {} -- Set of asset names to filter for when erasing
local selectedAssetInUI = nil
local avoidOverlap = false
local previewFolder = nil
local densityPreviewFolder = nil
local surfaceAngleMode = "Off" -- "Off", "Floor", "Wall"
local snapToGridEnabled = false
local gridSize = 4
local densityPreviewEnabled = true
local maskingMode = "Off" -- Off, Material, Color, Tag
local maskingValue = nil

local updatePresetListUI -- Forward-declare
local updatePaletteListUI -- Forward-declare
local updateAssetUIList -- Forward-declare
local updateFillSelection -- Forward-declare
local updateDensityPreview -- Forward-declare
local clearCurve -- Forward-declare
local clearSpline -- Forward-declare
local updateSplinePreview -- Forward-declare
local updateCablePreview -- Forward-declare
local clearCable -- Forward-declare
local catmullRom -- Forward-declare
local placeAsset -- Forward-declare
local getRandomWeightedAsset -- Forward-declare
local getWorkspaceContainer -- Forward-declare
local parseNumber -- Forward-declare
local paintAlongSpline -- Forward-declare
local paintAlongCurve -- Forward-declare
local persistOffsets -- Forward-declare

--[[
    UI Revamp: "Eco-Digital" Theme & Helper Functions
]]
local Theme = {
	Background = Color3.fromHex("282c34"),
	Section = Color3.fromHex("3a3f4b"),
	Accent = Color3.fromHex("20c997"),
	Text = Color3.fromHex("F0F0F0"),
	TextDisabled = Color3.fromHex("a0a0a0"),
	Border = Color3.fromHex("20232a"),
	Red = Color3.fromHex("e06c75"),
	Green = Color3.fromHex("98c379"),
	Blue = Color3.fromHex("61afef"),
}

local allSections = {}

local function createSection(title, parent)
	local sectionFrame = Instance.new("Frame")
	sectionFrame.Name = title .. "Section"
	sectionFrame.Size = UDim2.new(1, 0, 0, 32) -- Start with header height
	sectionFrame.AutomaticSize = Enum.AutomaticSize.Y
	sectionFrame.BackgroundColor3 = Theme.Section
	sectionFrame.BorderSizePixel = 0
	sectionFrame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = sectionFrame

	local header = Instance.new("TextButton")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 32)
	header.BackgroundColor3 = Theme.Section
	header.BorderSizePixel = 0
	header.Text = "  ▼ " .. title
	header.TextColor3 = Theme.Text
	header.Font = Enum.Font.SourceSansBold
	header.TextSize = 16
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = sectionFrame
	header.ZIndex = 2

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 4)
	headerCorner.Parent = header

	local contentFrame = Instance.new("Frame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.new(1, 0, 1, -32)
	contentFrame.Position = UDim2.new(0, 0, 0, 32)
	contentFrame.BackgroundTransparency = 1
	contentFrame.BorderSizePixel = 0
	contentFrame.ClipsDescendants = true
	contentFrame.Parent = sectionFrame
	contentFrame.Visible = true -- Default to open

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, 8)
	contentLayout.Parent = contentFrame

	local contentPadding = Instance.new("UIPadding")
	contentPadding.PaddingTop = UDim.new(0, 8)
	contentPadding.PaddingBottom = UDim.new(0, 8)
	contentPadding.PaddingLeft = UDim.new(0, 8)
	contentPadding.PaddingRight = UDim.new(0, 8)
	contentPadding.Parent = contentFrame

	local function setOpen(isOpen)
		contentFrame.Visible = isOpen
		if isOpen then
			header.Text = "  ▼ " .. title
		else
			header.Text = "  ▶ " .. title
		end
	end

	header.MouseButton1Click:Connect(function()
		local currentlyOpen = contentFrame.Visible
		-- Tutup semua section
		for _, section in ipairs(allSections) do
			section.setOpen(false)
		end
		-- Buka section ini jika sebelumnya tertutup
		setOpen(not currentlyOpen)
	end)

	local sectionController = {
		frame = sectionFrame,
		setOpen = setOpen,
	}
	table.insert(allSections, sectionController)

	return contentFrame, sectionFrame
end

local function createStyledButton(text, parent)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 28)
	btn.Text = text
	btn.Font = Enum.Font.SourceSansBold
	btn.TextSize = 14
	btn.TextColor3 = Theme.Text
	btn.BackgroundColor3 = Theme.Accent
	btn.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = btn

	return btn
end

local function createStyledTextBox(defaultText, parent)
	local tb = Instance.new("TextBox")
	tb.Size = UDim2.new(0.5, 0, 0, 28)
	tb.Text = tostring(defaultText)
	tb.ClearTextOnFocus = false
	tb.Font = Enum.Font.SourceSans
	tb.TextSize = 14
	tb.TextColor3 = Theme.Text
	tb.BackgroundColor3 = Theme.Background
	tb.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = tb

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1.5
	stroke.Parent = tb

	return tb
end

local function createStyledLabel(text, parent)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0.5, -8, 0, 28)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Font = Enum.Font.SourceSans
	lbl.TextSize = 14
	lbl.TextColor3 = Theme.Text
	lbl.Parent = parent
	return lbl
end


-- UI Creation
local toolbar = plugin:CreateToolbar("Brush Tool")
local toolbarBtn = toolbar:CreateButton("Brush", "Toggle Brush Mode (toolbar)", "")

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	false, -- Enabled
	false, -- Floating
	380, -- Width
	550, -- Height
	300, -- MinWidth
	200 -- MinHeight
)
local widget = plugin:CreateDockWidgetPluginGui("BrushToolWidget", widgetInfo)
widget.Title = "Brush Tool"
widget.Enabled = false -- show UI on load

-- Build UI inside widget
local C = {}

do
	local ui = Instance.new("Frame")
	ui.Size = UDim2.new(1, 0, 1, 0)
	ui.BackgroundTransparency = 1
	ui.Parent = widget

	-- Main container setup
	ui.BackgroundColor3 = Theme.Background
	local mainScrollFrame = Instance.new("ScrollingFrame")
	mainScrollFrame.Size = UDim2.new(1, 0, 1, 0)
	mainScrollFrame.BackgroundColor3 = Theme.Background
	mainScrollFrame.BorderSizePixel = 0
	mainScrollFrame.ScrollBarThickness = 6
	mainScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	mainScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	mainScrollFrame.Parent = ui

	local mainLayout = Instance.new("UIListLayout")
	mainLayout.Padding = UDim.new(0, 8)
	mainLayout.SortOrder = Enum.SortOrder.LayoutOrder
	mainLayout.Parent = mainScrollFrame

	local mainPadding = Instance.new("UIPadding")
	mainPadding.PaddingLeft = UDim.new(0, 8)
	mainPadding.PaddingRight = UDim.new(0, 8)
	mainPadding.PaddingTop = UDim.new(0, 8)
	mainPadding.PaddingBottom = UDim.new(0, 8)
	mainPadding.Parent = mainScrollFrame

	-- On/Off Toggle Bar
	local onOffBar = Instance.new("Frame")
	onOffBar.Name = "OnOffBar"
	onOffBar.Size = UDim2.new(1, 0, 0, 32)
	onOffBar.BackgroundTransparency = 1
	onOffBar.Parent = mainScrollFrame
	onOffBar.LayoutOrder = 1 -- Explicitly first
	C.onOffBtn = createStyledButton("Kuas: Mati", onOffBar)
	C.onOffBtn.BackgroundColor3 = Theme.Red

	-- Main Action Bar
	local mainActionBar = Instance.new("Frame")
	mainActionBar.Name = "MainActionBar"
	mainActionBar.Size = UDim2.new(1, 0, 0, 108) -- Adjusted height for 3 rows
	mainActionBar.BackgroundTransparency = 1
	mainActionBar.Parent = mainScrollFrame
	mainActionBar.LayoutOrder = 2 -- Explicitly second
	local mainActionBarLayout = Instance.new("UIGridLayout")
	mainActionBarLayout.CellSize = UDim2.new(0.333, -4, 0.333, -4)
	mainActionBarLayout.FillDirection = Enum.FillDirection.Horizontal
	mainActionBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
	mainActionBarLayout.Parent = mainActionBar

	local mainActionBarPadding = Instance.new("UIPadding")
	mainActionBarPadding.PaddingLeft = UDim.new(0, 4)
	mainActionBarPadding.PaddingRight = UDim.new(0, 4)
	mainActionBarPadding.PaddingTop = UDim.new(0, 4)
	mainActionBarPadding.PaddingBottom = UDim.new(0, 4)
	mainActionBarPadding.Parent = mainActionBar

	C.modeButtons = {}
	local modeNames = {"Paint", "Line", "Curve", "Spline", "Fill", "Replace", "Stamp", "Volume", "Erase", "Cable"}
	local modeDisplayNames = {
		Paint = "Kuas",
		Line = "Garis",
		Curve = "Kurva",
		Spline = "Spline",
		Fill = "Isi",
		Replace = "Ganti",
		Stamp = "Stempel",
		Volume = "Volume",
		Erase = "Penghapus",
		Cable = "Kabel"
	}

	for _, modeName in ipairs(modeNames) do
		local btn = createStyledButton(modeDisplayNames[modeName], mainActionBar)
		C.modeButtons[modeName] = btn
	end

	-- Mode Settings Section (Contextual)
	local modeSettingsContent, modeSettingsSection = createSection("Pengaturan Mode", mainScrollFrame)
	modeSettingsSection.LayoutOrder = 5
	C.modeSettingsContent = modeSettingsContent -- Store for easy access

	-- Brush Settings Section
	local brushSettingsContent, brushSettingsSection = createSection("Pengaturan Kuas", mainScrollFrame)
	brushSettingsSection.LayoutOrder = 3

	local function createControlRow(parent, labelText, defaultValue)
		local rowFrame = Instance.new("Frame")
		rowFrame.AutomaticSize = Enum.AutomaticSize.Y
		rowFrame.Size = UDim2.new(1, 0, 0, 54)
		rowFrame.BackgroundTransparency = 1
		rowFrame.Parent = parent

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.Padding = UDim.new(0, 2)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = rowFrame

		local label = createStyledLabel(labelText, rowFrame)
		label.Size = UDim2.new(1, 0, 0, 18)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.LayoutOrder = 1

		local textBox = createStyledTextBox(defaultValue, rowFrame)
		textBox.Size = UDim2.new(1, 0, 0, 28)
		textBox.LayoutOrder = 2

		return textBox, rowFrame
	end
	C.radiusBox, C.radiusRow = createControlRow(brushSettingsContent, "Radius", 10)
	C.densityBox, C.densityRow = createControlRow(brushSettingsContent, "Density", 10)
	C.spacingBox, C.spacingRow = createControlRow(brushSettingsContent, "Spacing", 1.5)

	local curveActionsFrame = Instance.new("Frame")
	curveActionsFrame.Name = "CurveActions"
	curveActionsFrame.Size = UDim2.new(1, 0, 0, 32)
	curveActionsFrame.BackgroundTransparency = 1
	curveActionsFrame.Parent = brushSettingsContent
	curveActionsFrame.Visible = false -- Sembunyikan secara default
	local curveActionsLayout = Instance.new("UIListLayout")
	curveActionsLayout.FillDirection = Enum.FillDirection.Horizontal
	curveActionsLayout.Padding = UDim.new(0, 8)
	curveActionsLayout.Parent = curveActionsFrame
	C.applyCurveBtn = createStyledButton("Terapkan Kurva", curveActionsFrame)
	C.clearCurveBtn = createStyledButton("Hapus Kurva", curveActionsFrame)
	C.curveActionsFrame = curveActionsFrame

	local splineActionsFrame = Instance.new("Frame")
	splineActionsFrame.Name = "SplineActions"
	splineActionsFrame.Size = UDim2.new(1, 0, 0, 32)
	splineActionsFrame.BackgroundTransparency = 1
	splineActionsFrame.Parent = brushSettingsContent
	splineActionsFrame.Visible = false -- Sembunyikan secara default
	local splineActionsLayout = Instance.new("UIListLayout")
	splineActionsLayout.FillDirection = Enum.FillDirection.Horizontal
	splineActionsLayout.Padding = UDim.new(0, 8)
	splineActionsLayout.Parent = splineActionsFrame
	C.applySplineBtn = createStyledButton("Generate Spline", splineActionsFrame)
	C.clearSplineBtn = createStyledButton("Clear Spline", splineActionsFrame)
	C.splineActionsFrame = splineActionsFrame

	C.cableSagBox, C.cableSagRow = createControlRow(modeSettingsContent, "Sag (Kendur)", 5)
	C.cableSegmentsBox, C.cableSegmentsRow = createControlRow(modeSettingsContent, "Segments (Kehalusan)", 10)
	C.cableThicknessBox, C.cableThicknessRow = createControlRow(modeSettingsContent, "Thickness (Ketebalan)", 0.2)

	-- Color Picker for Cable
	local cableColorRow = Instance.new("Frame")
	cableColorRow.AutomaticSize = Enum.AutomaticSize.Y
	cableColorRow.Size = UDim2.new(1, 0, 0, 28)
	cableColorRow.BackgroundTransparency = 1
	cableColorRow.Parent = modeSettingsContent
	local cableColorLayout = Instance.new("UIListLayout")
	cableColorLayout.FillDirection = Enum.FillDirection.Horizontal
	cableColorLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	cableColorLayout.Padding = UDim.new(0, 4)
	cableColorLayout.Parent = cableColorRow
	C.cableColorRow = cableColorRow

	local cableColorLabel = createStyledLabel("Warna Kabel:", cableColorRow)
	cableColorLabel.Size = UDim2.new(0.4, 0, 1, 0)
	C.cableColorButton = createStyledButton("", cableColorRow)
	C.cableColorButton.Size = UDim2.new(0.6, 0, 1, 0)
	C.cableColorButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50) -- Default dark grey

	-- Material Picker for Cable
	local cableMaterialRow = Instance.new("Frame")
	cableMaterialRow.AutomaticSize = Enum.AutomaticSize.Y
	cableMaterialRow.Size = UDim2.new(1, 0, 0, 32)
	cableMaterialRow.BackgroundTransparency = 1
	cableMaterialRow.Parent = modeSettingsContent
	local cableMaterialLayout = Instance.new("UIListLayout")
	cableMaterialLayout.FillDirection = Enum.FillDirection.Horizontal
	cableMaterialLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	cableMaterialLayout.Padding = UDim.new(0, 4)
	cableMaterialLayout.Parent = cableMaterialRow
	C.cableMaterialRow = cableMaterialRow

	local cableMaterialLabel = createStyledLabel("Material Kabel:", cableMaterialRow)
	cableMaterialLabel.Size = UDim2.new(0.4, 0, 1, 0)
	C.cableMaterialButton = createStyledButton("Plastic", cableMaterialRow)
	C.cableMaterialButton.Size = UDim2.new(0.6, 0, 1, 0)

	paintAlongSpline = function()
		if #splinePoints < 2 then return end

		ChangeHistoryService:SetWaypoint("Brush - Before Spline")
		local container = getWorkspaceContainer()
		local groupFolder = Instance.new("Folder")
		groupFolder.Name = "BrushSpline_" .. tostring(math.floor(os.time()))
		groupFolder.Parent = container

		-- Filter for only active assets
		local allAssets = assetsFolder:GetChildren()
		local activeAssets = {}
		for _, asset in ipairs(allAssets) do
			local isActive = assetOffsets[asset.Name .. "_active"]
			if isActive == nil then isActive = true end
			if isActive then table.insert(activeAssets, asset) end
		end

		if #activeAssets == 0 then
			warn("Brush Tool: No active assets to paint.")
			groupFolder:Destroy()
			clearSpline()
			return
		end

		local spacing = math.max(0.1, parseNumber(C.spacingBox.Text, 1.0))
		local distanceSinceLastPaint = 0

		local pointsToDraw = splinePoints
		if splineCloseLoop and #pointsToDraw > 2 then
			pointsToDraw = {pointsToDraw[#pointsToDraw], unpack(pointsToDraw), pointsToDraw[1], pointsToDraw[2]}
		end

		for i = 1, #pointsToDraw - 1 do
			local p1 = pointsToDraw[i]
			local p2 = pointsToDraw[i+1]
			local p0 = pointsToDraw[i-1] or (p1 + (p1 - p2))
			local p3 = pointsToDraw[i+2] or (p2 + (p2 - p1))

			local lastPoint = p1
			local segments = 100 -- Use higher resolution for placement
			for t_step = 1, segments do
				local t = t_step / segments
				local pointOnCurve = catmullRom(p0, p1, p2, p3, t)

				local segmentLength = (pointOnCurve - lastPoint).Magnitude
				distanceSinceLastPaint = distanceSinceLastPaint + segmentLength

				if distanceSinceLastPaint >= spacing then
					-- Place an asset here
					local assetToPlace = getRandomWeightedAsset(activeAssets)

					-- Raycast down to find the ground normal
					local rayOrigin = pointOnCurve + Vector3.new(0, 10, 0)
					local rayDir = Vector3.new(0, -20, 0)
					local params = RaycastParams.new()
					params.FilterDescendantsInstances = { previewFolder, container, curvePreviewFolder, splinePreviewFolder }
					params.FilterType = Enum.RaycastFilterType.Exclude
					local result = workspace:Raycast(rayOrigin, rayDir, params)

					if result then
						-- Use the placeAsset function, which handles scale, offsets, etc.
						local placedAsset = placeAsset(assetToPlace, result.Position, result.Normal)

						if placedAsset and splineFollowPath then
							-- Calculate the spline alignment rotation
							local tangent = (catmullRom(p0, p1, p2, p3, t + 0.01) - pointOnCurve).Unit
							local upVector = result.Normal
							local rightVector = tangent:Cross(upVector).Unit
							if rightVector.Magnitude < 0.9 then -- Handle cases where tangent is parallel to upVector
								rightVector = (tangent + Vector3.new(0.1, 0, 0.1)):Cross(upVector).Unit
							end
							local lookVector = upVector:Cross(rightVector).Unit
							local splineRotation = CFrame.fromMatrix(Vector3.new(), rightVector, upVector, -lookVector)

							-- Combine the spline alignment with the asset's existing random rotation
							if placedAsset:IsA("Model") and placedAsset.PrimaryPart then
								local pos = placedAsset:GetPrimaryPartCFrame().Position
								-- Extract the random X and Z rotations that were applied by placeAsset
								local _, rotX, _, _, rotZ, _ = (placedAsset:GetPrimaryPartCFrame() - pos):ToEulerAnglesXYZ()
								-- Create a new CFrame from the spline's rotation, then apply the original random X/Z tilts
								local finalRot = splineRotation * CFrame.Angles(rotX, 0, rotZ)
								placedAsset:SetPrimaryPartCFrame(CFrame.new(pos) * finalRot)

							elseif placedAsset:IsA("BasePart") then
								local pos = placedAsset.CFrame.Position
								local _, rotX, _, _, rotZ, _ = (placedAsset.CFrame - pos):ToEulerAnglesXYZ()
								local finalRot = splineRotation * CFrame.Angles(rotX, 0, rotZ)
								placedAsset.CFrame = CFrame.new(pos) * finalRot
							end
						end

						if placedAsset then
							placedAsset.Parent = groupFolder
						end
					end
					distanceSinceLastPaint = 0 -- Reset distance
				end
				lastPoint = pointOnCurve
			end
		end

		if #groupFolder:GetChildren() == 0 then
			groupFolder:Destroy()
		end

		ChangeHistoryService:SetWaypoint("Brush - After Spline")
		clearSpline()
	end

	paintAlongCurve = function()
		if #curvePoints < 2 then return end

		ChangeHistoryService:SetWaypoint("Brush - Before Curve")
		local container = getWorkspaceContainer()
		local groupFolder = Instance.new("Folder")
		groupFolder.Name = "BrushCurve_" .. tostring(math.floor(os.time()))
		groupFolder.Parent = container

		-- Filter for only active assets
		local allAssets = assetsFolder:GetChildren()
		local activeAssets = {}
		for _, asset in ipairs(allAssets) do
			local isActive = assetOffsets[asset.Name .. "_active"]
			if isActive == nil then isActive = true end
			if isActive then table.insert(activeAssets, asset) end
		end

		if #activeAssets == 0 then
			warn("Brush Tool: No active assets to paint.")
			groupFolder:Destroy()
			clearCurve()
			return
		end

		local spacing = math.max(0.1, parseNumber(C.spacingBox.Text, 1.0))
		local distanceSinceLastPaint = 0

		for i = 1, #curvePoints - 1 do
			local p1 = curvePoints[i]
			local p2 = curvePoints[i+1]
			local p0 = curvePoints[i-1] or (p1 + (p1 - p2))
			local p3 = curvePoints[i+2] or (p2 + (p2 - p1))

			local lastPoint = p1
			local segments = 100 -- Use higher resolution for placement
			for t_step = 1, segments do
				local t = t_step / segments
				local pointOnCurve = catmullRom(p0, p1, p2, p3, t)

				local segmentLength = (pointOnCurve - lastPoint).Magnitude
				distanceSinceLastPaint = distanceSinceLastPaint + segmentLength

				if distanceSinceLastPaint >= spacing then
					-- Place an asset here
					local assetToPlace = getRandomWeightedAsset(activeAssets)

					-- Raycast down to find the ground normal
					local rayOrigin = pointOnCurve + Vector3.new(0, 10, 0)
					local rayDir = Vector3.new(0, -20, 0)
					local params = RaycastParams.new()
					params.FilterDescendantsInstances = { previewFolder, container, curvePreviewFolder }
					params.FilterType = Enum.RaycastFilterType.Exclude
					local result = workspace:Raycast(rayOrigin, rayDir, params)

					if result then
						-- Calculate tangent for rotation
						local nextPointOnCurve = catmullRom(p0, p1, p2, p3, t + 0.01)
						local tangent = (nextPointOnCurve - pointOnCurve).Unit

						-- Use the placeAsset function, which handles scale, offsets, etc.
						local placedAsset = placeAsset(assetToPlace, result.Position, result.Normal)
						if placedAsset then
							-- Now, calculate the curve alignment rotation
							local tangent = (catmullRom(p0, p1, p2, p3, t + 0.01) - pointOnCurve).Unit
							local upVector = result.Normal
							local rightVector = tangent:Cross(upVector).Unit
							if rightVector.Magnitude < 0.9 then -- Handle cases where tangent is parallel to upVector
								rightVector = (tangent + Vector3.new(0.1, 0, 0.1)):Cross(upVector).Unit
							end
							local lookVector = upVector:Cross(rightVector).Unit
							local curveRotation = CFrame.fromMatrix(Vector3.new(), rightVector, upVector, -lookVector)

							-- Combine the curve alignment with the asset's existing random rotation
							if placedAsset:IsA("Model") and placedAsset.PrimaryPart then
								local pos = placedAsset:GetPrimaryPartCFrame().Position
								local rot = (placedAsset:GetPrimaryPartCFrame() - pos) * curveRotation
								placedAsset:SetPrimaryPartCFrame(CFrame.new(pos) * rot)
							elseif placedAsset:IsA("BasePart") then
								local pos = placedAsset.CFrame.Position
								local rot = (placedAsset.CFrame - pos) * curveRotation
								placedAsset.CFrame = CFrame.new(pos) * rot
							end

							placedAsset.Parent = groupFolder
						end
					end

					distanceSinceLastPaint = 0 -- Reset distance
				end

				lastPoint = pointOnCurve
			end
		end

		if #groupFolder:GetChildren() == 0 then
			groupFolder:Destroy()
		end

		ChangeHistoryService:SetWaypoint("Brush - After Curve")
		clearCurve()
	end

	C.fillBtn = createStyledButton("Pilih 1 Part untuk Diisi", brushSettingsContent)
	C.fillBtn.BackgroundColor3 = Theme.Red
	C.fillBtn.Active = false
	C.fillBtn.Visible = false -- Sembunyikan secara default

	-- Transform Settings Section
	local transformSettingsContent, transformSettingsSection = createSection("Pengaturan Transformasi", mainScrollFrame)
	transformSettingsSection.LayoutOrder = 6
	local function createMinMaxRow(parent, labelText, defaultMin, defaultMax)
		local rowFrame = Instance.new("Frame")
		rowFrame.AutomaticSize = Enum.AutomaticSize.Y
		rowFrame.Size = UDim2.new(1, 0, 0, 54)
		rowFrame.BackgroundTransparency = 1
		rowFrame.Parent = parent

		local verticalLayout = Instance.new("UIListLayout")
		verticalLayout.FillDirection = Enum.FillDirection.Vertical
		verticalLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		verticalLayout.Padding = UDim.new(0, 2)
		verticalLayout.SortOrder = Enum.SortOrder.LayoutOrder
		verticalLayout.Parent = rowFrame

		local label = createStyledLabel(labelText, rowFrame)
		label.Size = UDim2.new(1, 0, 0, 18)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.LayoutOrder = 1

		local inputsFrame = Instance.new("Frame")
		inputsFrame.Size = UDim2.new(1, 0, 0, 28)
		inputsFrame.LayoutOrder = 2
		inputsFrame.BackgroundTransparency = 1
		inputsFrame.Parent = rowFrame

		local horizontalLayout = Instance.new("UIListLayout")
		horizontalLayout.FillDirection = Enum.FillDirection.Horizontal
		horizontalLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		horizontalLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		horizontalLayout.Padding = UDim.new(0, 8)
		horizontalLayout.Parent = inputsFrame

		local minBox = createStyledTextBox(defaultMin, inputsFrame)
		minBox.Size = UDim2.new(0.5, -4, 1, 0)

		local maxBox = createStyledTextBox(defaultMax, inputsFrame)
		maxBox.Size = UDim2.new(0.5, -4, 1, 0)

		return minBox, maxBox, rowFrame
	end
	C.scaleMinBox, C.scaleMaxBox, _ = createMinMaxRow(transformSettingsContent, "Scale", 0.8, 1.3)
	C.rotXMinBox, C.rotXMaxBox, _ = createMinMaxRow(transformSettingsContent, "Rotasi X (°)", 0, 0)
	C.rotZMinBox, C.rotZMaxBox, _ = createMinMaxRow(transformSettingsContent, "Rotasi Z (°)", 0, 0)

	local colorHeader = createStyledLabel("Acak Warna (Rentang H, S, V)", transformSettingsContent)
	colorHeader.TextXAlignment = Enum.TextXAlignment.Center
	colorHeader.Size = UDim2.new(1, 0, 0, 20)
	C.hueMinBox, C.hueMaxBox, _ = createMinMaxRow(transformSettingsContent, "Hue", 0, 0)
	C.satMinBox, C.satMaxBox, _ = createMinMaxRow(transformSettingsContent, "Saturation", 0, 0)
	C.valMinBox, C.valMaxBox, _ = createMinMaxRow(transformSettingsContent, "Value", 0, 0)
	C.transMinBox, C.transMaxBox, _ = createMinMaxRow(transformSettingsContent, "Acak Transparansi", 0, 0)

	C.randomizeBtn = createStyledButton("Acak Pengaturan", transformSettingsContent)

	-- Advanced Settings Section
	local advancedSettingsContent, advancedSettingsSection = createSection("Pengaturan Lanjutan", mainScrollFrame)
	advancedSettingsSection.LayoutOrder = 7
	local advancedLayout = Instance.new("UIGridLayout")
	advancedLayout.CellSize = UDim2.new(0.5, -4, 0, 60)
	advancedLayout.FillDirection = Enum.FillDirection.Horizontal
	advancedLayout.SortOrder = Enum.SortOrder.LayoutOrder
	advancedLayout.Parent = advancedSettingsContent
	advancedSettingsContent:FindFirstChild("UIListLayout"):Destroy() -- Hapus list layout lama
	advancedSettingsSection.AutomaticSize = Enum.AutomaticSize.Y

	-- Asset Management Bar
	C.assetActionBar = Instance.new("Frame")
	C.assetActionBar.Name = "AssetActionBar"
	C.assetActionBar.Size = UDim2.new(1, 0, 0, 32)
	C.assetActionBar.BackgroundTransparency = 1
	C.assetActionBar.Parent = mainScrollFrame
	local assetActionBarLayout = Instance.new("UIListLayout")
	assetActionBarLayout.FillDirection = Enum.FillDirection.Horizontal
	assetActionBarLayout.Padding = UDim.new(0, 8)
	assetActionBarLayout.Parent = C.assetActionBar
	C.addBtn = createStyledButton("Add Selected", C.assetActionBar)
	C.clearBtn = createStyledButton("Clear Asset List", C.assetActionBar)


	-- Asset List Frame (akan diisi oleh updateAssetUIList)
	local assetListFrame = Instance.new("ScrollingFrame")
	assetListFrame.Size = UDim2.new(1, 0, 0, 300)
	assetListFrame.BackgroundColor3 = Theme.Section
	assetListFrame.BorderSizePixel = 0
	assetListFrame.ScrollBarThickness = 6
	assetListFrame.Parent = mainScrollFrame
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
	gridLayout.CellSize = UDim2.new(0.5, -4, 0, 180)
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = assetListFrame
	C.assetListFrame = assetListFrame

	-- Panel Pengaturan Aset (muncul saat item grid dipilih)
	local assetSettingsContent, assetSettingsSection = createSection("Pengaturan Aset Terpilih", mainScrollFrame)
	assetSettingsSection.Visible = false -- Sembunyikan seluruh section secara default
	C.assetSettingsPanel = assetSettingsSection -- Store the whole section
	C.assetSettingsContent = assetSettingsContent -- Store the content frame

	C.assetSettingsName = createStyledLabel("Pilih sebuah aset...", assetSettingsContent)
	C.assetSettingsName.TextXAlignment = Enum.TextXAlignment.Center
	C.assetSettingsName.Size = UDim2.new(1, 0, 0, 20)
	C.assetSettingsName.Font = Enum.Font.SourceSansBold

	local settingsControlsFrame = Instance.new("Frame")
	settingsControlsFrame.AutomaticSize = Enum.AutomaticSize.Y
	settingsControlsFrame.Size = UDim2.new(1, 0, 0, 60)
	settingsControlsFrame.BackgroundTransparency = 1
	settingsControlsFrame.Parent = assetSettingsContent
	local settingsControlsLayout = Instance.new("UIGridLayout")
	settingsControlsLayout.CellSize = UDim2.new(0.5, -4, 0, 28)
	settingsControlsLayout.CellPadding = UDim2.new(0, 8, 0, 4)
	settingsControlsLayout.FillDirection = Enum.FillDirection.Horizontal
	settingsControlsLayout.Parent = settingsControlsFrame

	local function createSettingsControlRow(parent, labelText)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 1, 0)
		row.BackgroundTransparency = 1
		row.Parent = parent
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 4)
		layout.Parent = row
		local label = createStyledLabel(labelText, row)
		label.Size = UDim2.new(0.4, 0, 1, 0)
		return row, label
	end

	local offsetRow, _ = createSettingsControlRow(settingsControlsFrame, "Y-Off:")
	C.assetSettingsOffsetY = createStyledTextBox("0", offsetRow)
	C.assetSettingsOffsetY.Size = UDim2.new(0.6, 0, 1, 0)

	local weightRow, _ = createSettingsControlRow(settingsControlsFrame, "Bobot:")
	C.assetSettingsWeight = createStyledTextBox("1", weightRow)
	C.assetSettingsWeight.Size = UDim2.new(0.6, 0, 1, 0)

	local alignRow, _ = createSettingsControlRow(settingsControlsFrame, "Selaras:")
	C.assetSettingsAlign = createStyledButton("Ya", alignRow)
	C.assetSettingsAlign.Size = UDim2.new(0.6, 0, 1, 0)

	local activeRow, _ = createSettingsControlRow(settingsControlsFrame, "Aktif:")
	C.assetSettingsActive = createStyledButton("✓", activeRow)
	C.assetSettingsActive.Size = UDim2.new(0.6, 0, 1, 0)

	persistOffsets = function()
		local ok, jsonString = pcall(HttpService.JSONEncode, HttpService, assetOffsets)
		if ok then
			plugin:SetSetting(SETTINGS_KEY, jsonString)
		else
			warn("Brush Tool: Gagal menyimpan offset aset! Error:", jsonString)
		end
	end

	C.assetSettingsOffsetY.FocusLost:Connect(function(enterPressed)
		if not selectedAssetInUI then return end
		local v = parseNumber(C.assetSettingsOffsetY.Text, 0)
		assetOffsets[selectedAssetInUI] = v
		C.assetSettingsOffsetY.Text = tostring(v)
		persistOffsets()
	end)

	C.assetSettingsWeight.FocusLost:Connect(function(enterPressed)
		if not selectedAssetInUI then return end
		local v = math.max(0, parseNumber(C.assetSettingsWeight.Text, 1))
		assetOffsets[selectedAssetInUI .. "_weight"] = v
		C.assetSettingsWeight.Text = tostring(v)
		persistOffsets()
	end)

	C.assetSettingsAlign.MouseButton1Click:Connect(function()
		if not selectedAssetInUI then return end
		local key = selectedAssetInUI .. "_align"
		assetOffsets[key] = not (assetOffsets[key] or false)
		persistOffsets()
		updateAssetSettingsPanel()
	end)

	C.assetSettingsActive.MouseButton1Click:Connect(function()
		if not selectedAssetInUI then return end
		local key = selectedAssetInUI .. "_active"
		local current = assetOffsets[key] == nil or assetOffsets[key]
		assetOffsets[key] = not current
		persistOffsets()
		updateAssetSettingsPanel()
	end)

	-- Palettes & Presets Section
	local palettesPresetsContent, palettesPresetsSection = createSection("Palet & Preset", mainScrollFrame)
	palettesPresetsSection.LayoutOrder = 8

	-- Palettes UI
	local paletteFrame = Instance.new("Frame")
	paletteFrame.Size = UDim2.new(1, 0, 0, 120)
	paletteFrame.BackgroundTransparency = 1
	paletteFrame.Parent = palettesPresetsContent
	createStyledLabel("Palet Aset", paletteFrame).Size = UDim2.new(1, 0, 0, 20)

	C.paletteList = Instance.new("ScrollingFrame")
	C.paletteList.Size = UDim2.new(1, -130, 1, -35)
	C.paletteList.Position = UDim2.new(0, 0, 0, 30)
	C.paletteList.BackgroundColor3 = Theme.Background
	C.paletteList.Parent = paletteFrame
	local paletteListLayout = Instance.new("UIListLayout")
	paletteListLayout.Padding = UDim.new(0, 2)
	paletteListLayout.SortOrder = Enum.SortOrder.Name
	paletteListLayout.Parent = C.paletteList

	C.paletteNameBox = createStyledTextBox("Nama Palet", paletteFrame)
	C.paletteNameBox.Position = UDim2.new(1, -125, 0, 30)
	C.paletteNameBox.Size = UDim2.new(0, 120, 0, 28)

	C.savePaletteBtn = createStyledButton("Simpan", paletteFrame)
	C.savePaletteBtn.Position = UDim2.new(1, -125, 0, 60)
	C.savePaletteBtn.Size = UDim2.new(0, 120, 0, 28)

	local paletteActionRow = Instance.new("Frame")
	paletteActionRow.Size = UDim2.new(0, 120, 0, 28)
	paletteActionRow.Position = UDim2.new(1, -125, 0, 90)
	paletteActionRow.BackgroundTransparency = 1
	paletteActionRow.Parent = paletteFrame
	local paletteActionLayout = Instance.new("UIListLayout")
	paletteActionLayout.FillDirection = Enum.FillDirection.Horizontal
	paletteActionLayout.Padding = UDim.new(0, 4)
	paletteActionLayout.Parent = paletteActionRow
	C.loadPaletteBtn = createStyledButton("Muat", paletteActionRow)
	C.deletePaletteBtn = createStyledButton("Hapus", paletteActionRow)

	-- Presets UI
	local presetFrame = Instance.new("Frame")
	presetFrame.Size = UDim2.new(1, 0, 0, 150)
	presetFrame.BackgroundTransparency = 1
	presetFrame.Parent = palettesPresetsContent
	createStyledLabel("Preset Kuas", presetFrame).Size = UDim2.new(1, 0, 0, 20)
	presetFrame:FindFirstChild("TextLabel").LayoutOrder = 2

	paletteFrame.LayoutOrder = 1
	presetFrame.LayoutOrder = 2

	C.presetList = Instance.new("ScrollingFrame")
	C.presetList.Size = UDim2.new(1, -130, 1, -35)
	C.presetList.Position = UDim2.new(0, 5, 0, 30)
	C.presetList.BackgroundColor3 = Theme.Background
	C.presetList.Parent = presetFrame
	local presetListLayout = Instance.new("UIListLayout")
	presetListLayout.Padding = UDim.new(0, 2)
	presetListLayout.SortOrder = Enum.SortOrder.Name
	presetListLayout.Parent = C.presetList

	C.presetNameBox = createStyledTextBox("Nama Preset", presetFrame)
	C.presetNameBox.Position = UDim2.new(1, -125, 0, 30)
	C.presetNameBox.Size = UDim2.new(0, 120, 0, 28)

	C.savePresetBtn = createStyledButton("Simpan", presetFrame)
	C.savePresetBtn.Position = UDim2.new(1, -125, 0, 60)
	C.savePresetBtn.Size = UDim2.new(0, 120, 0, 28)

	local presetActionRow = Instance.new("Frame")
	presetActionRow.Size = UDim2.new(0, 120, 0, 28)
	presetActionRow.Position = UDim2.new(1, -125, 0, 90)
	presetActionRow.BackgroundTransparency = 1
	presetActionRow.Parent = presetFrame
	local presetActionLayout = Instance.new("UIListLayout")
	presetActionLayout.FillDirection = Enum.FillDirection.Horizontal
	presetActionLayout.Padding = UDim.new(0, 4)
	presetActionLayout.Parent = presetActionRow
	C.loadPresetBtn = createStyledButton("Muat", presetActionRow)
	C.deletePresetBtn = createStyledButton("Hapus", presetActionRow)


	local function createToggleRow(parent, labelText)
		local rowFrame = Instance.new("Frame")
		rowFrame.AutomaticSize = Enum.AutomaticSize.Y
		rowFrame.Size = UDim2.new(1, 0, 0, 54)
		rowFrame.BackgroundTransparency = 1
		rowFrame.Parent = parent

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.Padding = UDim.new(0, 2)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = rowFrame

		local label = createStyledLabel(labelText, rowFrame)
		label.Size = UDim2.new(1, 0, 0, 18)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.LayoutOrder = 1

		local btn = createStyledButton("", rowFrame)
		btn.Size = UDim2.new(1, 0, 0, 28)
		btn.LayoutOrder = 2

		return btn, rowFrame
	end

	local avoidOverlapContainer = Instance.new("Frame")
	avoidOverlapContainer.BackgroundTransparency = 1
	avoidOverlapContainer.Parent = advancedSettingsContent
	C.avoidOverlapBtn, _ = createToggleRow(avoidOverlapContainer, "Hindari Tumpang Tindih")

	local surfaceAngleContainer = Instance.new("Frame")
	surfaceAngleContainer.BackgroundTransparency = 1
	surfaceAngleContainer.Parent = advancedSettingsContent
	C.surfaceAngleBtn, _ = createToggleRow(surfaceAngleContainer, "Kunci Permukaan")

	local physicsModeContainer = Instance.new("Frame")
	physicsModeContainer.BackgroundTransparency = 1
	physicsModeContainer.Parent = advancedSettingsContent
	C.physicsModeBtn, _ = createToggleRow(physicsModeContainer, "Mode Fisika")

	local physicsSettleTimeContainer = Instance.new("Frame")
	physicsSettleTimeContainer.BackgroundTransparency = 1
	physicsSettleTimeContainer.Parent = advancedSettingsContent

	local physicsSettleTimeRow = Instance.new("Frame")
	physicsSettleTimeRow.Size = UDim2.new(1, 0, 0, 28)
	physicsSettleTimeRow.BackgroundTransparency = 1
	physicsSettleTimeRow.Parent = physicsSettleTimeContainer
	local physicsLayout = Instance.new("UIListLayout")
	physicsLayout.FillDirection = Enum.FillDirection.Vertical
	physicsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	physicsLayout.Padding = UDim.new(0, 2)
	physicsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	physicsLayout.Parent = physicsSettleTimeRow
	local physicsLabel = createStyledLabel("Waktu Tunggu Fisika", physicsSettleTimeRow)
	physicsLabel.Size = UDim2.new(1, 0, 0, 18)
	physicsLabel.TextXAlignment = Enum.TextXAlignment.Center
	physicsLabel.LayoutOrder = 1
	C.physicsSettleTimeBox = createStyledTextBox(physicsSettleTime, physicsSettleTimeRow)
	C.physicsSettleTimeBox.Size = UDim2.new(1, 0, 0, 28)
	C.physicsSettleTimeBox.LayoutOrder = 2

	local snapToGridContainer = Instance.new("Frame")
	snapToGridContainer.BackgroundTransparency = 1
	snapToGridContainer.Parent = advancedSettingsContent
	C.snapToGridBtn, _ = createToggleRow(snapToGridContainer, "Tempel ke Grid")

	local gridSizeContainer = Instance.new("Frame")
	gridSizeContainer.BackgroundTransparency = 1
	gridSizeContainer.Parent = advancedSettingsContent

	local densityPreviewContainer = Instance.new("Frame")
	densityPreviewContainer.BackgroundTransparency = 1
	densityPreviewContainer.Parent = advancedSettingsContent
	C.densityPreviewBtn, _ = createToggleRow(densityPreviewContainer, "Pratinjau Kepadatan")

	local splineFollowPathContainer = Instance.new("Frame")
	splineFollowPathContainer.BackgroundTransparency = 1
	splineFollowPathContainer.Parent = advancedSettingsContent
	C.splineFollowPathBtn, _ = createToggleRow(splineFollowPathContainer, "Spline: Follow Path")

	local splineCloseLoopContainer = Instance.new("Frame")
	splineCloseLoopContainer.BackgroundTransparency = 1
	splineCloseLoopContainer.Parent = advancedSettingsContent
	C.splineCloseLoopBtn, _ = createToggleRow(splineCloseLoopContainer, "Spline: Close Loop")

	local maskingContainer = Instance.new("Frame")
	maskingContainer.BackgroundTransparency = 1
	maskingContainer.Parent = advancedSettingsContent
	local maskingBtn, maskingRowFrame = createToggleRow(maskingContainer, "Masking")
	C.maskingModeBtn = maskingBtn
	C.maskingModeBtn.Text = "Mode: Off"
	C.maskingModeBtn.LayoutOrder = 2

	C.maskingTargetLabel = createStyledLabel("Target: None", maskingRowFrame)
	C.maskingTargetLabel.Size = UDim2.new(1, 0, 0, 18)
	C.maskingTargetLabel.TextXAlignment = Enum.TextXAlignment.Center
	C.maskingTargetLabel.LayoutOrder = 3

	C.pickMaskTargetBtn = createStyledButton("Ambil dari Seleksi", maskingRowFrame)
	C.pickMaskTargetBtn.Size = UDim2.new(1, 0, 0, 28)
	C.pickMaskTargetBtn.LayoutOrder = 4

	C.maskingInputFrame = Instance.new("Frame")
	C.maskingInputFrame.AutomaticSize = Enum.AutomaticSize.Y
	C.maskingInputFrame.BackgroundTransparency = 1
	C.maskingInputFrame.LayoutOrder = 5
	C.maskingInputFrame.Parent = maskingRowFrame
	C.maskingInputFrame.Visible = false -- Hide by default

	local inputLayout = Instance.new("UIListLayout")
	inputLayout.Parent = C.maskingInputFrame
	inputLayout.SortOrder = Enum.SortOrder.LayoutOrder
	inputLayout.Padding = UDim.new(0, 4)

	C.maskingTextBox = createStyledTextBox("", C.maskingInputFrame)
	C.maskingTextBox.Size = UDim2.new(1, 0, 0, 28)
	C.maskingTextBox.PlaceholderText = "Enter Tag or R,G,B color..."

	C.materialGridFrame = Instance.new("ScrollingFrame")
	C.materialGridFrame.Size = UDim2.new(1, 0, 0, 150)
	C.materialGridFrame.BackgroundColor3 = Theme.Background
	C.materialGridFrame.BorderSizePixel = 1
	C.materialGridFrame.BorderColor3 = Theme.Border
	C.materialGridFrame.ScrollBarThickness = 6
	C.materialGridFrame.Parent = C.maskingInputFrame
	C.materialGridFrame.Visible = false

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 56, 0, 56)
	gridLayout.CellPadding = UDim2.new(0, 4, 0, 4)
	gridLayout.SortOrder = Enum.SortOrder.Name
	gridLayout.Parent = C.materialGridFrame

	local gridSizeRow = Instance.new("Frame")
	gridSizeRow.Size = UDim2.new(1, 0, 0, 28)
	gridSizeRow.BackgroundTransparency = 1
	gridSizeRow.Parent = gridSizeContainer
	local gridLayout = Instance.new("UIListLayout")
	gridLayout.FillDirection = Enum.FillDirection.Vertical
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.Padding = UDim.new(0, 2)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = gridSizeRow
	local gridLabel = createStyledLabel("Ukuran Grid", gridSizeRow)
	gridLabel.Size = UDim2.new(1, 0, 0, 18)
	gridLabel.TextXAlignment = Enum.TextXAlignment.Center
	gridLabel.LayoutOrder = 1
	C.gridSizeBox = createStyledTextBox(gridSize, gridSizeRow)
	C.gridSizeBox.Size = UDim2.new(1, 0, 0, 28)
	C.gridSizeBox.LayoutOrder = 2

	C.assetListFrame.LayoutOrder = 3
	C.assetSettingsPanel.LayoutOrder = 4
	C.assetActionBar.LayoutOrder = 5

	-- Connect Cable UI Events
	C.cableColorButton.MouseButton1Click:Connect(function()
		plugin:ShowColorPicker(cableColor, function(newColor)
			cableColor = newColor
			C.cableColorButton.BackgroundColor3 = newColor
		end)
	end)

	local materials = Enum.Material:GetEnumItems()
	local currentMaterialIndex = table.find(materials, Enum.Material.Plastic) or 1

	C.cableMaterialButton.MouseButton1Click:Connect(function()
		currentMaterialIndex = (currentMaterialIndex % #materials) + 1
		cableMaterial = materials[currentMaterialIndex]
		C.cableMaterialButton.Text = cableMaterial.Name
	end)
end

-- Utility Functions
local function updateModeButtonsUI()
	for modeName, button in pairs(C.modeButtons) do
		if modeName == currentMode then
			button.BackgroundColor3 = Theme.Accent
		else
			button.BackgroundColor3 = Theme.Section
		end
	end
end

local function updateOnOffButtonUI()
	if active then
		C.onOffBtn.Text = "Kuas: Aktif"
		C.onOffBtn.BackgroundColor3 = Theme.Green
	else
		C.onOffBtn.Text = "Kuas: Mati"
		C.onOffBtn.BackgroundColor3 = Theme.Red
	end
end

local function updateToggleButtonsUI()
	-- Avoid Overlap
	C.avoidOverlapBtn.Text = avoidOverlap and "Ya" or "Tidak"
	C.avoidOverlapBtn.BackgroundColor3 = avoidOverlap and Theme.Green or Theme.Red

	-- Surface Angle
	if surfaceAngleMode == "Off" then
		C.surfaceAngleBtn.Text = "Kunci Permukaan: Mati"
	elseif surfaceAngleMode == "Floor" then
		C.surfaceAngleBtn.Text = "Kunci Permukaan: Lantai"
	else -- Pasti "Wall"
		C.surfaceAngleBtn.Text = "Kunci Permukaan: Dinding"
	end

	-- Physics Mode
	if physicsModeEnabled then
		C.physicsModeBtn.Text = "Aktif"
		C.physicsModeBtn.BackgroundColor3 = Theme.Green
	else
		C.physicsModeBtn.Text = "Mati"
		C.physicsModeBtn.BackgroundColor3 = Theme.Red
	end

	-- Snap to Grid
	C.snapToGridBtn.Text = snapToGridEnabled and "Ya" or "Tidak"
	C.snapToGridBtn.BackgroundColor3 = snapToGridEnabled and Theme.Green or Theme.Red

	-- Density Preview
	C.densityPreviewBtn.Text = densityPreviewEnabled and "Ya" or "Tidak"
	C.densityPreviewBtn.BackgroundColor3 = densityPreviewEnabled and Theme.Green or Theme.Red

	-- Spline Buttons
	C.splineFollowPathBtn.Text = splineFollowPath and "Ya" or "Tidak"
	C.splineFollowPathBtn.BackgroundColor3 = splineFollowPath and Theme.Green or Theme.Red
	C.splineCloseLoopBtn.Text = splineCloseLoop and "Ya" or "Tidak"
	C.splineCloseLoopBtn.BackgroundColor3 = splineCloseLoop and Theme.Green or Theme.Red
end

local function updateMaskingUI()
	C.maskingModeBtn.Text = "Mode: " .. maskingMode

	local isMaskingOn = maskingMode ~= "Off"
	C.pickMaskTargetBtn.Visible = isMaskingOn
	C.maskingTargetLabel.Visible = isMaskingOn
	C.maskingInputFrame.Visible = isMaskingOn

	if not isMaskingOn then
		C.maskingTargetLabel.Text = "Target: None"
		return
	end

	C.maskingTextBox.Visible = (maskingMode == "Color" or maskingMode == "Tag")
	C.materialGridFrame.Visible = (maskingMode == "Material")

	if maskingMode == "Color" then
		C.maskingTextBox.PlaceholderText = "Enter R,G,B (e.g., 255,0,0)"
	elseif maskingMode == "Tag" then
		C.maskingTextBox.PlaceholderText = "Enter Tag name..."
	end

	-- Update selection stroke
	for _, btn in ipairs(C.materialGridFrame:GetChildren()) do
		if btn:IsA("ImageButton") then
			local stroke = btn:FindFirstChildOfClass("UIStroke")
			if maskingValue and maskingMode == "Material" and btn.Name == maskingValue.Name then
				stroke.Enabled = true
				stroke.Color = Theme.Accent
			else
				stroke.Enabled = false
			end
		end
	end

	if maskingValue then
		if maskingMode == "Color" then
			local c = maskingValue
			C.maskingTargetLabel.Text = string.format("Target: %.2f, %.2f, %.2f", c.r, c.g, c.b)
			C.maskingTextBox.Text = string.format("%d, %d, %d", c.r * 255, c.g * 255, c.b * 255)
		elseif maskingMode == "Tag" then
			C.maskingTargetLabel.Text = "Target: " .. tostring(maskingValue)
			C.maskingTextBox.Text = tostring(maskingValue)
		elseif maskingMode == "Material" then
			C.maskingTargetLabel.Text = "Target: " .. maskingValue.Name
		end
	else
		C.maskingTargetLabel.Text = "Target: None"
		C.maskingTextBox.Text = ""
	end
end

local function trim(s)
	return s:match("^%s*(.-)%s*$") or s
end

local function populateMaterialPicker()
	for _, material in ipairs(Enum.Material:GetEnumItems()) do
		local btn = Instance.new("ImageButton")
		btn.Name = material.Name
		btn.Size = UDim2.new(0, 56, 0, 56)
		btn.BackgroundColor3 = Theme.Section
		btn.Image = "rbxasset://textures/terrain/materials/v2/" .. material.Name .. ".png"
		btn.Parent = C.materialGridFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = btn

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Theme.Border
		stroke.Enabled = false
		stroke.Parent = btn

		btn.MouseButton1Click:Connect(function()
			maskingValue = material
			updateMaskingUI()
		end)
	end
end

local function snapPositionToGrid(position, size)
	if size <= 0 then return position end
	local x = math.floor(position.X / size + 0.5) * size
	local y = math.floor(position.Y / size + 0.5) * size
	local z = math.floor(position.Z / size + 0.5) * size
	return Vector3.new(x, y, z)
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



local function persistPalettes()
	local ok, jsonString = pcall(HttpService.JSONEncode, HttpService, assetPalettes)
	if ok then
		plugin:SetSetting(PALETTES_KEY, jsonString)
	else
		warn("Brush Tool: Gagal menyimpan palet aset! Error:", jsonString)
	end
end

local function loadPalettes()
	local jsonString = plugin:GetSetting(PALETTES_KEY)
	if jsonString and #jsonString > 0 then
		local ok, data = pcall(HttpService.JSONDecode, HttpService, jsonString)
		if ok and type(data) == "table" then
			assetPalettes = data
		else
			assetPalettes = {}
		end
	else
		assetPalettes = {}
	end
end

local function saveAssetPalette(name)
	if not name or name == "" or name == "Nama Palet" then
		warn("Brush Tool: Nama palet tidak valid.")
		return
	end

	local activeAssets = {}
	for _, asset in ipairs(assetsFolder:GetChildren()) do
		local isActive = assetOffsets[asset.Name .. "_active"]
		if isActive == nil then isActive = true end
		if isActive then
			table.insert(activeAssets, asset.Name)
		end
	end

	assetPalettes[name] = activeAssets
	persistPalettes()
	updatePaletteListUI()
end



local function deleteAssetPalette(name)
	if not name or not assetPalettes[name] then return end

	assetPalettes[name] = nil
	persistPalettes()

	if selectedPalette == name then
		selectedPalette = nil
		C.paletteNameBox.Text = "Nama Palet"
	end

	updatePaletteListUI()
end


local function deletePreset(name)
	if not name or not presets[name] then return end

	presets[name] = nil
	savePresets()

	if selectedPreset == name then
		selectedPreset = nil
		C.presetNameBox.Text = "Nama Preset"
	end

	updatePresetListUI()
end

parseNumber = function(txt, fallback)
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
		local assetName = asset.Name
		local isActive = assetOffsets[assetName .. "_active"]
		if isActive == nil then isActive = true end

		local weight = assetOffsets[assetName .. "_weight"] or 1

		assetStates[assetName] = {
			active = isActive,
			weight = weight
		}
	end

	presets[name] = {
		radius = parseNumber(C.radiusBox.Text, 10),
		density = parseNumber(C.densityBox.Text, 10),
		scaleMin = parseNumber(C.scaleMinBox.Text, 0.8),
		scaleMax = parseNumber(C.scaleMaxBox.Text, 1.3),
		spacing = parseNumber(C.spacingBox.Text, 1.5),
		rotXMin = parseNumber(C.rotXMinBox.Text, 0),
		rotXMax = parseNumber(C.rotXMaxBox.Text, 0),
		rotZMin = parseNumber(C.rotZMinBox.Text, 0),
		rotZMax = parseNumber(C.rotZMaxBox.Text, 0),
		avoidOverlap = avoidOverlap,
		surfaceAngleMode = surfaceAngleMode,
		snapToGridEnabled = snapToGridEnabled,
		gridSize = parseNumber(C.gridSizeBox.Text, 4),
		densityPreviewEnabled = densityPreviewEnabled,
		maskingMode = maskingMode,
		maskingValue = (maskingMode == "Color" and {R=maskingValue.r, G=maskingValue.g, B=maskingValue.b}) or (maskingMode == "Material" and maskingValue.Name) or maskingValue,
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

local function getRandomPointInSphere(radius)
	local u = math.random()
	local v = math.random()
	local theta = u * 2 * math.pi
	local phi = math.acos(2 * v - 1)
	local r = math.cbrt(math.random()) * radius
	local sinPhi = math.sin(phi)
	local cosPhi = math.cos(phi)
	local sinTheta = math.sin(theta)
	local cosTheta = math.cos(theta)
	return Vector3.new(r * sinPhi * cosTheta, r * sinPhi * sinTheta, r * cosPhi)
end


-- Function to calculate a point on a Catmull-Rom spline
catmullRom = function(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t

	local out = 0.5 * (
		(2 * p1) +
			(-p0 + p2) * t +
			(2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
			(-p0 + 3 * p1 - 3 * p2 + p3) * t3
	)
	return out
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

updateAssetSettingsPanel = function()
	if not selectedAssetInUI then
		C.assetSettingsPanel.Visible = false
		return
	end

	C.assetSettingsPanel.Visible = true
	if C.assetSettingsPanel:FindFirstChild("Content") then
		C.assetSettingsPanel:FindFirstChild("Content").Visible = true
	end
	C.assetSettingsName.Text = selectedAssetInUI

	local assetName = selectedAssetInUI
	local offsetKey, alignKey, activeKey, weightKey = assetName, assetName .. "_align", assetName .. "_active", assetName .. "_weight"

	-- Populate controls
	C.assetSettingsOffsetY.Text = tostring(assetOffsets[offsetKey] or 0)
	C.assetSettingsWeight.Text = tostring(assetOffsets[weightKey] or 1)

	local isAligning = assetOffsets[alignKey] or false
	C.assetSettingsAlign.Text = isAligning and "Ya" or "Tidak"
	C.assetSettingsAlign.BackgroundColor3 = isAligning and Theme.Green or Theme.Red

	local isActive = assetOffsets[activeKey] == nil or assetOffsets[activeKey]
	C.assetSettingsActive.Text = isActive and "✓" or ""
	C.assetSettingsActive.BackgroundColor3 = isActive and Theme.Green or Theme.Red
end

updateAssetUIList = function()
	C.assetListFrame.CanvasPosition = Vector2.new(0, 0)
	for _, v in ipairs(C.assetListFrame:GetChildren()) do
		if v:IsA("GuiObject") and not v:IsA("UIGridLayout") then
			v:Destroy()
		end
	end

	local children = assetsFolder:GetChildren()

	for i, asset in ipairs(children) do
		local assetName = asset.Name

		-- Main card button
		local card = Instance.new("TextButton")
		card.Name = assetName .. "_Card"
		card.Size = UDim2.new(1, 0, 1, 0) -- Use the size from GridLayout
		card.BackgroundColor3 = Theme.Background
		card.Text = ""
		card.LayoutOrder = i
		card.Parent = C.assetListFrame

		local corner = Instance.new("UICorner", card)
		corner.CornerRadius = UDim.new(0, 4)

		local cardLayout = Instance.new("UIListLayout", card)
		cardLayout.Padding = UDim.new(0, 4)
		cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
		cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

		local border = Instance.new("UIStroke")
		border.Thickness = 2
		border.Color = Theme.Border
		border.Parent = card

		-- Viewport
		local viewport = Instance.new("ViewportFrame")
		viewport.Size = UDim2.new(1, -8, 0, 140)
		viewport.BackgroundColor3 = Theme.Section
		viewport.Ambient = Color3.fromRGB(200, 200, 200)
		viewport.LightColor = Color3.fromRGB(150, 150, 150)
		viewport.LightDirection = Vector3.new(-1, -2, -0.5)
		viewport.LayoutOrder = 1
		viewport.Parent = card
		Instance.new("UICorner", viewport).CornerRadius = UDim.new(0, 4)
		task.spawn(setupViewport, viewport, asset)

		-- Name Label
		local lbl = createStyledLabel(assetName, card)
		lbl.Size = UDim2.new(1, -8, 0, 16)
		lbl.TextXAlignment = Enum.TextXAlignment.Center
		lbl.TextTruncate = Enum.TextTruncate.AtEnd
		lbl.LayoutOrder = 2
		lbl.Parent = card

		-- Selection Logic
		card.MouseButton1Click:Connect(function()
			if selectedAssetInUI == assetName then
				-- Deselect if clicking the same asset again
				selectedAssetInUI = nil
				C.assetSettingsPanel.Visible = false
			else
				selectedAssetInUI = assetName
				updateAssetSettingsPanel() -- Update and show the panel
			end
			updateAssetUIList() -- Redraw to update selection highlights
		end)

		-- Right click for special modes
		card.MouseButton2Click:Connect(function()
			if currentMode == "Erase" then
				eraseFilter[assetName] = not eraseFilter[assetName]
			elseif currentMode == "Replace" then
				if sourceAsset == assetName then sourceAsset = nil
				elseif targetAsset == assetName then targetAsset = nil
				elseif not sourceAsset then sourceAsset = assetName
				elseif not targetAsset then targetAsset = assetName
				else targetAsset = assetName end
			end
			updateAssetUIList()
		end)

		-- Update appearance based on state
		if selectedAssetInUI == assetName then
			border.Color = Theme.Accent
			border.Enabled = true
		elseif currentMode == "Erase" and eraseFilter[assetName] then
			border.Color = Theme.Red
			border.Enabled = true
		elseif currentMode == "Replace" and sourceAsset == assetName then
			border.Color = Theme.Blue
			border.Enabled = true
		elseif currentMode == "Replace" and targetAsset == assetName then
			border.Color = Theme.Green
			border.Enabled = true
		else
			border.Enabled = false
		end
	end
end

local function loadPreset(name)
	local data = presets[name]
	if not data then return end

	C.radiusBox.Text = tostring(data.radius)
	C.densityBox.Text = tostring(data.density)
	C.scaleMinBox.Text = tostring(data.scaleMin)
	C.scaleMaxBox.Text = tostring(data.scaleMax)
	C.spacingBox.Text = tostring(data.spacing)
	C.rotXMinBox.Text = tostring(data.rotXMin)
	C.rotXMaxBox.Text = tostring(data.rotXMax)
	C.rotZMinBox.Text = tostring(data.rotZMin)
	C.rotZMaxBox.Text = tostring(data.rotZMax)

	avoidOverlap = data.avoidOverlap
	C.avoidOverlapBtn.Text = avoidOverlap and "Ya" or "Tidak"
	C.avoidOverlapBtn.BackgroundColor3 = avoidOverlap and Theme.Green or Theme.Red

	surfaceAngleMode = data.surfaceAngleMode or "Off"
	if surfaceAngleMode == "Off" then
		C.surfaceAngleBtn.Text = "Kunci Permukaan: Mati"
	elseif surfaceAngleMode == "Floor" then
		C.surfaceAngleBtn.Text = "Kunci Permukaan: Lantai"
	else
		C.surfaceAngleBtn.Text = "Kunci Permukaan: Dinding"
	end

	snapToGridEnabled = data.snapToGridEnabled or false
	gridSize = data.gridSize or 4
	C.gridSizeBox.Text = tostring(gridSize)

	densityPreviewEnabled = data.densityPreviewEnabled
	if densityPreviewEnabled == nil then densityPreviewEnabled = true end

	maskingMode = data.maskingMode or "Off"
	if data.maskingValue then
		if maskingMode == "Color" then
			maskingValue = Color3.new(data.maskingValue.R, data.maskingValue.G, data.maskingValue.B)
		elseif maskingMode == "Material" then
			maskingValue = Enum.Material[data.maskingValue]
		else -- Tag or Off
			maskingValue = data.maskingValue
		end
	else
		maskingValue = nil
	end

	updateToggleButtonsUI()
	updateMaskingUI()

	if data.assetStates then
		for assetName, state in pairs(data.assetStates) do
			if type(state) == "table" then
				-- Format baru dengan bobot
				assetOffsets[assetName .. "_active"] = state.active
				assetOffsets[assetName .. "_weight"] = state.weight
			else
				-- Format lama untuk kompatibilitas mundur
				assetOffsets[assetName .. "_active"] = state
				assetOffsets[assetName .. "_weight"] = 1 -- Beri default 1
			end
		end
	end

	updateAssetUIList()
	persistOffsets()
end

-- Core Logic Functions

getRandomWeightedAsset = function(assetList)
	local totalWeight = 0
	for _, asset in ipairs(assetList) do
		local weight = assetOffsets[asset.Name .. "_weight"] or 1
		totalWeight = totalWeight + weight
	end

	if totalWeight == 0 then
		-- Jika semua bobot adalah 0, kembalikan secara acak untuk menghindari error
		return assetList[math.random(1, #assetList)]
	end

	local randomNum = math.random() * totalWeight
	local currentWeight = 0
	for _, asset in ipairs(assetList) do
		local weight = assetOffsets[asset.Name .. "_weight"] or 1
		currentWeight = currentWeight + weight
		if randomNum <= currentWeight then
			return asset
		end
	end

	-- Fallback jika terjadi kesalahan floating point
	return assetList[#assetList]
end

getWorkspaceContainer = function()
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

local function randomizeProperties(target)
	local hmin = parseNumber(C.hueMinBox.Text, 0)
	local hmax = parseNumber(C.hueMaxBox.Text, 0)
	local smin = parseNumber(C.satMinBox.Text, 0)
	local smax = parseNumber(C.satMaxBox.Text, 0)
	local vmin = parseNumber(C.valMinBox.Text, 0)
	local vmax = parseNumber(C.valMaxBox.Text, 0)
	local tmin = parseNumber(C.transMinBox.Text, 0)
	local tmax = parseNumber(C.transMaxBox.Text, 0)

	local hasColorShift = (hmin ~= 0 or hmax ~= 0 or smin ~= 0 or smax ~= 0 or vmin ~= 0 or vmax ~= 0)
	local hasTransShift = (tmin ~= 0 or tmax ~= 0)

	if not hasColorShift and not hasTransShift then
		return
	end

	local parts = {}
	if target:IsA("BasePart") then
		table.insert(parts, target)
	else -- It's a Model
		for _, descendant in ipairs(target:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
	end

	for _, part in ipairs(parts) do
		if hasColorShift then
			local h, s, v = part.Color:ToHSV()
			h = (h + randFloat(hmin, hmax)) % 1
			s = math.clamp(s + randFloat(smin, smax), 0, 1)
			v = math.clamp(v + randFloat(vmin, vmax), 0, 1)
			part.Color = Color3.fromHSV(h, s, v)
		end

		if hasTransShift then
			part.Transparency = math.clamp(part.Transparency + randFloat(tmin, tmax), 0, 1)
		end
	end
end

local function loadAssetPalette(name)
	local palette = assetPalettes[name]
	if not palette then return end

	local paletteSet = {}
	for _, assetName in ipairs(palette) do
		paletteSet[assetName] = true
	end

	for _, asset in ipairs(assetsFolder:GetChildren()) do
		assetOffsets[asset.Name .. "_active"] = paletteSet[asset.Name] or false
	end

	persistOffsets()
	updateAssetUIList()
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
	params.FilterDescendantsInstances = { previewFolder, getWorkspaceContainer(), densityPreviewFolder, curvePreviewFolder, cablePreviewFolder }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000, params)

	if result then
		-- Terapkan filter Kunci Permukaan
		if surfaceAngleMode == "Floor" and result.Normal.Y < 0.7 then
			-- Dalam mode Lantai, jangan melukis di dinding/lereng curam
			return nil, nil, nil
		elseif surfaceAngleMode == "Wall" and math.abs(result.Normal.Y) > 0.3 then
			-- Dalam mode Dinding, jangan melukis di lantai/langit-langit
			return nil, nil, nil
		end

		return result.Position, result.Normal, result.Instance
	end
	return nil, nil, nil
end

placeAsset = function(assetToClone, position, normal)
	local smin = parseNumber(C.scaleMinBox.Text, 0.8)
	local smax = parseNumber(C.scaleMaxBox.Text, 1.2)
	if smin <= 0 then smin = 0.1 end
	if smax < smin then smax = smin end

	local clone = assetToClone:Clone()
	randomizeProperties(clone)

	if clone:IsA("Model") and not clone.PrimaryPart then
		for _, v in ipairs(clone:GetDescendants()) do
			if v:IsA("BasePart") then
				clone.PrimaryPart = v
				break
			end
		end
	end

	local s = randFloat(smin, smax)

	local xrot, yrot, zrot
	local effectiveNormal = normal or Vector3.new(0, 1, 0)

	if normal and surfaceAngleMode == "Floor" then
		xrot = 0
		zrot = 0
		yrot = math.rad(math.random() * 360) -- Hanya rotasi Y
		effectiveNormal = Vector3.new(0, 1, 0) -- Paksa vektor 'up'
	else
		-- Mode "Off", "Wall", atau Volume (normal == nil)
		local rotXMin = math.rad(parseNumber(C.rotXMinBox.Text, 0))
		local rotXMax = math.rad(parseNumber(C.rotXMaxBox.Text, 0))
		local rotZMin = math.rad(parseNumber(C.rotZMinBox.Text, 0))
		local rotZMax = math.rad(parseNumber(C.rotZMaxBox.Text, 0))
		xrot = randFloat(rotXMin, rotXMax)
		yrot = math.rad(math.random() * 360)
		zrot = randFloat(rotZMin, rotZMax)
	end
	local randomRotation = CFrame.Angles(xrot, yrot, zrot)

	local assetName = assetToClone.Name
	local customOffset = assetOffsets[assetName] or 0
	local shouldAlign = assetOffsets[assetName .. "_align"] or false

	if clone:IsA("Model") and clone.PrimaryPart then
		clone:SetPrimaryPartCFrame(CFrame.new(position))
		if math.abs(s - 1) > 0.0001 then scaleModel(clone, s) end

		local ok, bboxCFrame, bboxSize = pcall(function() return clone:GetBoundingBox() end)
		local finalPosition
		if ok then
			local pivotOffset = clone.PrimaryPart.Position - bboxCFrame.Position
			local worldPivot = CFrame.new(position) * pivotOffset
			local currentBottomY_inWorld = worldPivot.Y - (bboxSize.Y / 2)
			-- Gunakan effectiveNormal untuk perhitungan offset
			local shiftY_vector = effectiveNormal * ((position.Y - currentBottomY_inWorld) + customOffset)
			finalPosition = clone:GetPrimaryPartCFrame().Position + shiftY_vector
		else
			warn("Tidak bisa mendapatkan bounding box untuk " .. clone.Name .. ", penempatan mungkin tidak akurat.")
			finalPosition = clone:GetPrimaryPartCFrame().Position + (effectiveNormal * customOffset) -- Fallback
		end

		if snapToGridEnabled then
			finalPosition = snapPositionToGrid(finalPosition, gridSize)
		end

		local finalCFrame
		local forceAlign = (surfaceAngleMode == "Wall") -- Selalu selaraskan dalam mode Dinding
		-- Selaraskan jika dipaksa (Dinding) ATAU (jika diaktifkan (Selaras: Ya) DAN mode Mati)
		if (forceAlign or (shouldAlign and surfaceAngleMode == "Off")) and normal then
			local rotatedCFrame = CFrame.new() * randomRotation
			local look = rotatedCFrame.LookVector
			local rightVec = look:Cross(effectiveNormal).Unit
			local lookActual = effectiveNormal:Cross(rightVec).Unit
			if rightVec.Magnitude < 0.9 then
				look = rotatedCFrame.RightVector
				rightVec = look:Cross(effectiveNormal).Unit
				lookActual = effectiveNormal:Cross(rightVec).Unit
			end
			finalCFrame = CFrame.fromMatrix(finalPosition, rightVec, effectiveNormal, -lookActual)
		else
			-- Mode lantai, atau mode Mati dengan Selaras: Tdk
			finalCFrame = CFrame.new(finalPosition) * randomRotation
		end
		clone:SetPrimaryPartCFrame(finalCFrame)

	elseif clone:IsA("BasePart") then
		clone.Size = clone.Size * s
		local finalYOffset = (clone.Size.Y / 2) + customOffset
		-- Gunakan effectiveNormal untuk perhitungan offset
		local finalPos = position + (effectiveNormal * finalYOffset)
		if snapToGridEnabled then
			finalPos = snapPositionToGrid(finalPos, gridSize)
		end
		local finalCFrame
		local forceAlign = (surfaceAngleMode == "Wall") -- Selalu selaraskan dalam mode Dinding
		if (forceAlign or (shouldAlign and surfaceAngleMode == "Off")) and normal then
			local rotatedCFrame = CFrame.new() * randomRotation
			local look = rotatedCFrame.LookVector
			local rightVec = look:Cross(effectiveNormal).Unit
			local lookActual = effectiveNormal:Cross(rightVec).Unit
			if rightVec.Magnitude < 0.9 then
				look = rotatedCFrame.RightVector
				rightVec = look:Cross(effectiveNormal).Unit
				lookActual = effectiveNormal:Cross(rightVec).Unit
			end
			finalCFrame = CFrame.fromMatrix(finalPos, rightVec, effectiveNormal, -lookActual)
		else
			finalCFrame = CFrame.new(finalPos) * randomRotation
		end
		clone.CFrame = finalCFrame
	end

	-- Handle physics drop
	if physicsModeEnabled and currentMode == "Paint" then
		clone.Parent = getWorkspaceContainer() -- Parent to workspace temporarily for physics
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Anchored = false
				desc.CanCollide = true
			end
		end
		-- Move it up slightly to ensure it drops
		clone:TranslateBy(Vector3.new(0, 2, 0))
	end

	return clone
end

local function anchorPhysicsGroup(group, parentFolder)
	task.spawn(function()
		task.wait(physicsSettleTime)

		for _, model in ipairs(group) do
			if model and model.Parent then -- Pastikan model belum dihancurkan
				model.Parent = parentFolder
				for _, desc in ipairs(model:GetDescendants()) do
					if desc:IsA("BasePart") then
						desc.Anchored = true
					end
				end
			end
		end
	end)
end

local function paintInVolume(center)
	local radius = math.max(0.1, parseNumber(C.radiusBox.Text, 10))
	local density = math.max(1, math.floor(parseNumber(C.densityBox.Text, 10)))

	ChangeHistoryService:SetWaypoint("Brush - Before VolumePaint")
	local container = getWorkspaceContainer()
	local groupFolder = Instance.new("Folder")
	groupFolder.Name = "BrushVolume_" .. tostring(math.floor(os.time()))
	groupFolder.Parent = container

	-- Filter for only active assets
	local allAssets = assetsFolder:GetChildren()
	local activeAssets = {}
	for _, asset in ipairs(allAssets) do
		local isActive = assetOffsets[asset.Name .. "_active"]
		if isActive == nil then isActive = true end
		if isActive then table.insert(activeAssets, asset) end
	end

	if #activeAssets == 0 then
		warn("Brush Tool: No active assets to paint in volume.")
		groupFolder:Destroy()
		return
	end

	for i = 1, density do
		local assetToPlace = getRandomWeightedAsset(activeAssets)
		if assetToPlace then
			local randomPoint = center + getRandomPointInSphere(radius)
			-- Pass nil for normal to indicate no surface alignment
			local placedAsset = placeAsset(assetToPlace, randomPoint, nil) 
			if placedAsset then
				placedAsset.Parent = groupFolder
			end
		end
	end

	if #groupFolder:GetChildren() == 0 then
		groupFolder:Destroy()
	end

	ChangeHistoryService:SetWaypoint("Brush - After VolumePaint")
end

local function stampAt(center, surfaceNormal)
	ChangeHistoryService:SetWaypoint("Brush - Before Stamp")
	local container = getWorkspaceContainer()
	local groupFolder = Instance.new("Folder")
	groupFolder.Name = "BrushStamp_" .. tostring(math.floor(os.time()))
	groupFolder.Parent = container

	-- Filter for only active assets
	local allAssets = assetsFolder:GetChildren()
	local activeAssets = {}
	for _, asset in ipairs(allAssets) do
		local isActive = assetOffsets[asset.Name .. "_active"]
		if isActive == nil then isActive = true end
		if isActive then table.insert(activeAssets, asset) end
	end

	if #activeAssets == 0 then
		warn("Brush Tool: No active assets to stamp.")
		groupFolder:Destroy()
		ChangeHistoryService:SetWaypoint("Brush - Canceled (No active assets)")
		return
	end

	local assetToPlace = getRandomWeightedAsset(activeAssets)
	if assetToPlace then
		local placedAsset = placeAsset(assetToPlace, center, surfaceNormal)
		if placedAsset then
			placedAsset.Parent = groupFolder
		end
	end

	if #groupFolder:GetChildren() == 0 then
		groupFolder:Destroy()
	end

	ChangeHistoryService:SetWaypoint("Brush - After Stamp")
end

local function paintAt(center, surfaceNormal)
	local radius = math.max(0.1, parseNumber(C.radiusBox.Text, 10))
	local physicsGroup = {} -- Deklarasikan sebagai tabel lokal
	-- Baca nilai density
	local density = math.max(1, math.floor(parseNumber(C.densityBox.Text, 10)))

	local smin = parseNumber(C.scaleMinBox.Text, 0.8)
	local smax = parseNumber(C.scaleMaxBox.Text, 1.2)
	local spacing = math.max(0.1, parseNumber(C.spacingBox.Text, 1.0))
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

	-- Loop berdasarkan density, bukan jumlah aset
	for i = 1, density do
		-- Pilih aset acak dari yang aktif menggunakan seleksi berbobot
		local assetToClone = getRandomWeightedAsset(activeAssets)
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

			if result and result.Instance then
				local isValidTarget = true
				if maskingMode ~= "Off" and maskingValue then
					local targetPart = result.Instance
					if maskingMode == "Material" then
						isValidTarget = (targetPart.Material == maskingValue)
					elseif maskingMode == "Color" then
						isValidTarget = (targetPart.Color == maskingValue)
					elseif maskingMode == "Tag" then
						isValidTarget = CollectionService:HasTag(targetPart, maskingValue)
					end
				end

				if isValidTarget then
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
		end

		if not candidatePos then
			clone:Destroy()
		else
			-- Lakukan penempatan menggunakan fungsi helper yang sudah direfactor
			local placedAsset = placeAsset(assetToClone, candidatePos, candidateNormal)
			if not physicsModeEnabled or currentMode ~= "Paint" then
				placedAsset.Parent = groupFolder
			else
				table.insert(physicsGroup, placedAsset)
			end
			table.insert(placed, candidatePos)
		end
	end

	-- Jika mode fisika, mulai proses penjangkaran
	if physicsModeEnabled and currentMode == "Paint" and #physicsGroup > 0 then
		anchorPhysicsGroup(physicsGroup, groupFolder)
	end

	if #groupFolder:GetChildren() == 0 then
		groupFolder:Destroy()
	end

	ChangeHistoryService:SetWaypoint("Brush - After Paint")
end

local function eraseAt(center)
	local radius = math.max(0.1, parseNumber(C.radiusBox.Text, 10))
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



local function paintAlongLine(startPos, endPos)
	local spacing = math.max(0.1, parseNumber(C.spacingBox.Text, 1.0))
	local lineVector = endPos - startPos
	local lineLength = lineVector.Magnitude
	if lineLength < spacing then return end

	ChangeHistoryService:SetWaypoint("Brush - Before Line")
	local container = getWorkspaceContainer()

	-- Buat folder grup untuk undo
	local groupFolder = Instance.new("Folder")
	groupFolder.Name = "BrushLine_" .. tostring(math.floor(os.time()))
	groupFolder.Parent = container

	-- Filter for only active assets
	local allAssets = assetsFolder:GetChildren()
	local activeAssets = {}
	for _, asset in ipairs(allAssets) do
		local isActive = assetOffsets[asset.Name .. "_active"]
		if isActive == nil then isActive = true end
		if isActive then
			table.insert(activeAssets, asset)
		end
	end

	if #activeAssets == 0 then
		warn("Brush Tool: Tidak ada aset aktif yang dipilih untuk digambar.")
		groupFolder:Destroy() -- Hapus folder grup kosong
		return
	end

	local numSteps = math.floor(lineLength / spacing)

	for i = 0, numSteps do
		local t = i / numSteps
		local pointOnLine = startPos + lineVector * t

		-- Raycast down from this point to find the actual surface
		local rayOrigin = pointOnLine + Vector3.new(0, 10, 0) -- Start raycast from above
		local rayDir = Vector3.new(0, -20, 0) -- Raycast downwards

		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { previewFolder, container }
		params.FilterType = Enum.RaycastFilterType.Exclude
		local result = workspace:Raycast(rayOrigin, rayDir, params)

		if result then
			-- Cek filter permukaan
			local skip = false
			if surfaceAngleMode == "Floor" and result.Normal.Y < 0.7 then
				skip = true
			elseif surfaceAngleMode == "Wall" and math.abs(result.Normal.Y) > 0.3 then
				skip = true
			end

			if not skip then
				local assetToPlace = getRandomWeightedAsset(activeAssets)
				local placedAsset = placeAsset(assetToPlace, result.Position, result.Normal)
				if placedAsset then
					placedAsset.Parent = groupFolder
				end
			end
		end
	end

	-- Hapus folder grup jika tidak ada yang ditempatkan
	if #groupFolder:GetChildren() == 0 then
		groupFolder:Destroy()
	end

	ChangeHistoryService:SetWaypoint("Brush - After Line")
end

local function fillArea(part)
	if not part then return end

	local density = math.max(1, math.floor(parseNumber(C.densityBox.Text, 10)))
	local spacing = math.max(0.1, parseNumber(C.spacingBox.Text, 1.0))

	-- Filter for only active assets
	local allAssets = assetsFolder:GetChildren()
	local activeAssets = {}
	for _, asset in ipairs(allAssets) do
		local isActive = assetOffsets[asset.Name .. "_active"]
		if isActive == nil then isActive = true end
		if isActive then table.insert(activeAssets, asset) end
	end

	if #activeAssets == 0 then
		warn("Brush Tool: Tidak ada aset aktif yang dipilih untuk mengisi.")
		return
	end

	ChangeHistoryService:SetWaypoint("Brush - Before Fill")
	local container = getWorkspaceContainer()
	local groupFolder = Instance.new("Folder")
	groupFolder.Name = "BrushFill_" .. tostring(math.floor(os.time()))
	groupFolder.Parent = container

	local placedPoints = {}
	local partCF = part.CFrame
	local partSize = part.Size

	for i = 1, density do
		local assetToPlace = getRandomWeightedAsset(activeAssets)

		local foundPoint = false
		local attempts = 0

		while not foundPoint and attempts < 20 do
			attempts = attempts + 1

			local randomX = (math.random() - 0.5) * partSize.X
			local randomZ = (math.random() - 0.5) * partSize.Z
			local topY = partSize.Y / 2

			local pointInPartSpace = Vector3.new(randomX, topY, randomZ)
			local worldPoint = partCF * pointInPartSpace

			local rayOrigin = worldPoint + part.CFrame.UpVector * 5
			local rayDir = -part.CFrame.UpVector * (partSize.Y + 10)

			local params = RaycastParams.new()
			params.FilterDescendantsInstances = { previewFolder, container }
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = {part} -- Hanya raycast ke part target

			local result = workspace:Raycast(rayOrigin, rayDir, params)

			if result then
				local isSpaced = true
				for _, p in ipairs(placedPoints) do
					if (result.Position - p).Magnitude < spacing then
						isSpaced = false
						break
					end
				end

				if isSpaced then
					local placedAsset = placeAsset(assetToPlace, result.Position, result.Normal)
					if placedAsset then
						placedAsset.Parent = groupFolder
						table.insert(placedPoints, result.Position)
					end
					foundPoint = true
				end
			end
		end
	end

	if #groupFolder:GetChildren() == 0 then
		groupFolder:Destroy()
	end

	ChangeHistoryService:SetWaypoint("Brush - After Fill")
end

local function replaceAt(center)
	if not sourceAsset or not targetAsset then return end

	local radius = math.max(0.1, parseNumber(C.radiusBox.Text, 10))
	local container = workspace:FindFirstChild(WORKSPACE_FOLDER_NAME)
	if not container then return end

	local sourceModel = assetsFolder:FindFirstChild(sourceAsset)
	local targetModel = assetsFolder:FindFirstChild(targetAsset)
	if not sourceModel or not targetModel then
		warn("Brush Tool: Aset sumber atau target tidak ditemukan.")
		return
	end

	local itemsToReplace = {}
	local allPartsInRadius = workspace:GetPartBoundsInRadius(center, radius)

	for _, part in ipairs(allPartsInRadius) do
		if part:IsDescendantOf(container) then
			local ancestorToReplace = part
			while ancestorToReplace and ancestorToReplace.Parent ~= container do
				ancestorToReplace = ancestorToReplace.Parent
			end
			if ancestorToReplace and ancestorToReplace.Name == sourceAsset then
				itemsToReplace[ancestorToReplace] = true
			end
		end
	end

	if next(itemsToReplace) ~= nil then
		ChangeHistoryService:SetWaypoint("Brush - Before Replace")
		local groupFolder = Instance.new("Folder")
		groupFolder.Name = "BrushReplace_" .. tostring(math.floor(os.time()))
		groupFolder.Parent = container

		for item, _ in pairs(itemsToReplace) do
			local oldCFrame, oldSize
			if item:IsA("Model") and item.PrimaryPart then
				oldCFrame = item.PrimaryPart.CFrame
				oldSize = item:GetExtentsSize()
			elseif item:IsA("BasePart") then
				oldCFrame = item.CFrame
				oldSize = item.Size
			end

			if oldCFrame and oldSize then
				item:Destroy()
				local newAsset = targetModel:Clone()

				if newAsset:IsA("Model") and newAsset.PrimaryPart then
					local _, newSize = newAsset:GetBoundingBox()
					local scaleFactor = oldSize.Magnitude / newSize.Magnitude
					scaleModel(newAsset, scaleFactor)
					newAsset:SetPrimaryPartCFrame(oldCFrame)
				elseif newAsset:IsA("BasePart") then
					newAsset.Size = oldSize
					newAsset.CFrame = oldCFrame
				end

				newAsset.Parent = groupFolder
			end
		end

		if #groupFolder:GetChildren() == 0 then
			groupFolder:Destroy()
		end

		ChangeHistoryService:SetWaypoint("Brush - After Replace")
	end
end

local function updateCurvePreview()
	curvePreviewFolder:ClearAllChildren()

	if #curvePoints < 2 then return end

	local segments = 10 -- Number of preview parts per curve segment

	for i = 1, #curvePoints - 1 do
		local p1 = curvePoints[i]
		local p2 = curvePoints[i+1]

		-- Extrapolate control points for the start and end of the spline
		local p0 = curvePoints[i-1] or (p1 + (p1 - p2))
		local p3 = curvePoints[i+2] or (p2 + (p2 - p1))

		local lastPoint = p1
		for t_step = 1, segments do
			local t = t_step / segments
			local pointOnCurve = catmullRom(p0, p1, p2, p3, t)

			local part = Instance.new("Part")
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Size = Vector3.new(0.4, 0.4, (pointOnCurve - lastPoint).Magnitude)
			part.CFrame = CFrame.new(lastPoint, pointOnCurve) * CFrame.new(0, 0, -(pointOnCurve-lastPoint).Magnitude / 2)
			part.Color = Color3.fromRGB(255, 255, 0) -- Yellow preview
			part.Material = Enum.Material.Neon
			part.Parent = curvePreviewFolder

			lastPoint = pointOnCurve
		end
	end
end

clearCurve = function()
	curvePoints = {}
	curvePreviewFolder:ClearAllChildren()
end

updateSplinePreview = function()
	splinePreviewFolder:ClearAllChildren()

	-- Draw points
	for _, point in ipairs(splinePoints) do
		local marker = Instance.new("Part")
		marker.Shape = Enum.PartType.Ball
		marker.Size = Vector3.new(0.8, 0.8, 0.8)
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanQuery = false
		marker.CanTouch = false
		marker.Color = Theme.Accent
		marker.Material = Enum.Material.Neon
		marker.Position = point
		marker.Parent = splinePreviewFolder
	end

	local pointsToDraw = splinePoints
	if splineCloseLoop and #pointsToDraw > 2 then
		pointsToDraw = {pointsToDraw[#pointsToDraw], unpack(pointsToDraw), pointsToDraw[1], pointsToDraw[2]}
	end

	if #pointsToDraw < 2 then return end

	local segments = 20 -- Number of preview parts per curve segment

	for i = 1, #pointsToDraw - 1 do
		local p1 = pointsToDraw[i]
		local p2 = pointsToDraw[i+1]
		local p0 = pointsToDraw[i-1] or (p1 + (p1 - p2))
		local p3 = pointsToDraw[i+2] or (p2 + (p2 - p1))

		local lastPoint = p1
		for t_step = 1, segments do
			local t = t_step / segments
			local pointOnCurve = catmullRom(p0, p1, p2, p3, t)

			local part = Instance.new("Part")
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Size = Vector3.new(0.4, 0.4, (pointOnCurve - lastPoint).Magnitude)
			part.CFrame = CFrame.new(lastPoint, pointOnCurve) * CFrame.new(0, 0, -(pointOnCurve-lastPoint).Magnitude / 2)
			part.Color = Theme.Blue
			part.Material = Enum.Material.Neon
			part.Parent = splinePreviewFolder

			lastPoint = pointOnCurve
		end
	end
end

clearSpline = function()
	splinePoints = {}
	splinePreviewFolder:ClearAllChildren()
end

clearCable = function()
	cableStartPoint = nil
	if cablePreviewFolder then
		cablePreviewFolder:ClearAllChildren()
	end
end

local function calculateCatenary(p1, p2, sag, segments)
	local points = {}
	local halfDist = (p1 - p2).Magnitude / 2
	if halfDist < 0.01 then return {p1, p2} end

	local a = sag / (halfDist * halfDist) -- Parabolic approximation

	for i = 0, segments do
		local t = i / segments
		local x = (t - 0.5) * (halfDist * 2)
		local y = a * x * x

		local fraction = (p2 - p1) * t
		local point = p1 + fraction + Vector3.new(0, -y, 0)
		table.insert(points, point)
	end
	return points
end

updateCablePreview = function(startPos, endPos)
	if not cablePreviewFolder then return end
	cablePreviewFolder:ClearAllChildren()

	local sag = math.max(0, parseNumber(C.cableSagBox.Text, 5))
	local segments = math.max(2, math.floor(parseNumber(C.cableSegmentsBox.Text, 10)))
	local thickness = math.max(0.1, parseNumber(C.cableThicknessBox.Text, 0.2))

	local points = calculateCatenary(startPos, endPos, sag, segments)

	for i = 1, #points - 1 do
		local p1 = points[i]
		local p2 = points[i+1]
		local mag = (p2 - p1).Magnitude

		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(mag, thickness, thickness)
		part.CFrame = CFrame.new(p1, p2) * CFrame.Angles(0, math.rad(90), 0) * CFrame.new(mag / 2, 0, 0)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Material = cableMaterial
		part.Color = cableColor
		part.Transparency = 0.5
		part.Parent = cablePreviewFolder
	end
end

createCable = function(startPos, endPos)
	ChangeHistoryService:SetWaypoint("Brush - Before Cable")
	local container = getWorkspaceContainer()
	local groupFolder = Instance.new("Folder")
	groupFolder.Name = "BrushCable_" .. tostring(math.floor(os.time()))
	groupFolder.Parent = container

	local sag = math.max(0, parseNumber(C.cableSagBox.Text, 5))
	local segments = math.max(2, math.floor(parseNumber(C.cableSegmentsBox.Text, 10)))
	local thickness = math.max(0.1, parseNumber(C.cableThicknessBox.Text, 0.2))

	local points = calculateCatenary(startPos, endPos, sag, segments)

	for i = 1, #points - 1 do
		local p1 = points[i]
		local p2 = points[i+1]
		local mag = (p2 - p1).Magnitude

		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(mag, thickness, thickness)
		part.CFrame = CFrame.new(p1, p2) * CFrame.Angles(0, math.rad(90), 0) * CFrame.new(mag / 2, 0, 0)
		part.Anchored = true
		part.CanCollide = true -- Cables should be collidable
		part.Material = cableMaterial
		part.Color = cableColor
		part.Parent = groupFolder
	end

	ChangeHistoryService:SetWaypoint("Brush - After Cable")
	clearCable()
end

-- Mouse and Tool Activation Logic
updateDensityPreview = function(center, surfaceNormal)
	densityPreviewFolder:ClearAllChildren()

	if not center or not surfaceNormal or currentMode ~= "Paint" or not densityPreviewEnabled then
		return
	end

	local radius = math.max(0.1, parseNumber(C.radiusBox.Text, 10))
	local density = math.max(1, math.floor(parseNumber(C.densityBox.Text, 10)))
	local spacing = math.max(0.1, parseNumber(C.spacingBox.Text, 1.0))

	local placed = {}

	local up = surfaceNormal
	local look = Vector3.new(1, 0, 0)
	if math.abs(up:Dot(look)) > 0.99 then
		look = Vector3.new(0, 0, 1)
	end
	local right = look:Cross(up).Unit
	local look_actual = up:Cross(right).Unit
	local planeCFrame = CFrame.fromMatrix(center, right, up, -look_actual)

	local container = getWorkspaceContainer()

	for i = 1, density do
		local found = false
		local candidatePos = nil
		local attempts = 0

		while not found and attempts < 12 do
			attempts = attempts + 1
			local offset2D = randomPointInCircle(radius)
			local spawnPos = planeCFrame:PointToWorldSpace(Vector3.new(offset2D.X, 0, offset2D.Z))

			local rayOrigin = spawnPos + surfaceNormal * 5
			local rayDir = -surfaceNormal * 10

			local params = RaycastParams.new()
			params.FilterDescendantsInstances = { previewFolder, container, densityPreviewFolder, curvePreviewFolder }
			params.FilterType = Enum.RaycastFilterType.Exclude
			local result = workspace:Raycast(rayOrigin, rayDir, params)

			if result and result.Instance then
				local isValidTarget = true
				if maskingMode ~= "Off" and maskingValue then
					local targetPart = result.Instance
					if maskingMode == "Material" then
						isValidTarget = (targetPart.Material == maskingValue)
					elseif maskingMode == "Color" then
						isValidTarget = (targetPart.Color == maskingValue)
					elseif maskingMode == "Tag" then
						isValidTarget = CollectionService:HasTag(targetPart, maskingValue)
					end
				end

				if isValidTarget then
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
					end
				end
			end
		end

		if candidatePos then
			local marker = Instance.new("Part")
			marker.Shape = Enum.PartType.Ball
			marker.Size = Vector3.new(0.5, 0.5, 0.5)
			marker.Anchored = true
			marker.CanCollide = false
			marker.CanQuery = false
			marker.CanTouch = false
			marker.Color = Color3.fromRGB(255, 255, 0)
			marker.Material = Enum.Material.Neon
			marker.Transparency = 0.6
			marker.Position = candidatePos
			marker.Parent = densityPreviewFolder
			table.insert(placed, candidatePos)
		end
	end
end

local function updatePreview()
	if not mouse or not previewPart then
		return
	end

	-- Sembunyikan pratinjau kuas jika kita sedang dalam proses menggambar garis
	if currentMode == "Line" and lineStartPoint then
		previewPart.Parent = nil
	elseif currentMode == "Volume" then
		previewPart.Parent = previewFolder
		local radius = math.max(0.1, parseNumber(C.radiusBox.Text, 10))
		local unitRay = workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y)
		local positionInSpace = unitRay.Origin + unitRay.Direction * 100 -- Default distance

		previewPart.Shape = Enum.PartType.Ball
		previewPart.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
		previewPart.CFrame = CFrame.new(positionInSpace)
		previewPart.Color = Color3.fromRGB(150, 150, 255) -- Purple for Volume
		cyl.Parent = nil -- Sembunyikan silinder
	else
		if currentMode == "Paint" or currentMode == "Line" then
			previewPart.Color = Color3.fromRGB(80, 255, 80) -- Green for Paint/Line
		elseif currentMode == "Replace" then
			previewPart.Color = Color3.fromRGB(80, 180, 255) -- Blue for Replace
		else -- Erase
			previewPart.Color = Color3.fromRGB(255, 80, 80) -- Red for Erase
		end

		previewPart.Shape = Enum.PartType.Cylinder
		if cyl.Parent ~= previewPart then cyl.Parent = previewPart end


		local radius = math.max(0.1, parseNumber(C.radiusBox.Text, 10))
		local surfacePos, normal = findSurfacePositionAndNormal()

		if not surfacePos or not normal or currentMode == "Line" or currentMode == "Cable" then
			previewPart.Parent = nil -- Sembunyikan untuk mode Garis (sebelum titik pertama) dan Isi
			updateDensityPreview(nil, nil)
		else
			previewPart.Parent = previewFolder
			local pos = surfacePos
			local look = Vector3.new(1, 0, 0)
			if math.abs(look:Dot(normal)) > 0.99 then look = Vector3.new(0, 0, 1) end
			local right = look:Cross(normal).Unit
			local lookActual = normal:Cross(right).Unit
			previewPart.CFrame = CFrame.fromMatrix(pos + normal * 0.05, right, normal, -lookActual)
			previewPart.Size = Vector3.new(0.02, radius*2, radius*2)
			--cyl.Scale = Vector3.new(radius * 2, 0.02, radius * 2)
			updateDensityPreview(pos, normal)
		end
	end

	-- Update pratinjau garis
	if currentMode == "Line" and lineStartPoint and linePreviewPart then
		local endPoint, _ = findSurfacePositionAndNormal()
		if endPoint then
			linePreviewPart.Parent = previewFolder
			local mag = (endPoint - lineStartPoint).Magnitude
			linePreviewPart.Size = Vector3.new(0.2, 0.2, mag)
			linePreviewPart.CFrame = CFrame.new(lineStartPoint, endPoint) * CFrame.new(0, 0, -mag/2)
		else
			linePreviewPart.Parent = nil
		end
	elseif linePreviewPart then
		linePreviewPart.Parent = nil -- Sembunyikan jika tidak dalam mode garis
	end

	-- Update cable preview
	if currentMode == "Cable" and cableStartPoint then
		local endPoint, _ = findSurfacePositionAndNormal()
		if endPoint then
			updateCablePreview(cableStartPoint, endPoint)
		end
	elseif cablePreviewFolder then
		clearCable()
	end
end

local function handlePaint(center, normal)
	if currentMode == "Paint" then
		paintAt(center, normal)
	elseif currentMode == "Stamp" then
		stampAt(center, normal)
	elseif currentMode == "Volume" then
		local unitRay = workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y)
		local positionInSpace = unitRay.Origin + unitRay.Direction * 100 -- Default distance
		paintInVolume(positionInSpace)
	elseif currentMode == "Erase" then
		eraseAt(center)
	elseif currentMode == "Replace" then
		replaceAt(center)
	end
	lastPaintPosition = center
end

local function onMove()
	if not active then
		return
	end

	updatePreview()

	if isPainting and (currentMode == "Paint" or currentMode == "Erase" or currentMode == "Replace") then
		local center, normal = findSurfacePositionAndNormal()
		if center and normal and lastPaintPosition then
			local spacing = math.max(0.1, parseNumber(C.spacingBox.Text, 1.0))
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

	local center, normal = findSurfacePositionAndNormal()
	if not center or not normal then return end

	if currentMode == "Line" then
		if not lineStartPoint then
			lineStartPoint = center
		else
			paintAlongLine(lineStartPoint, center)
			lineStartPoint = nil -- Reset for the next line
		end
	elseif currentMode == "Curve" then
		table.insert(curvePoints, center)
		updateCurvePreview()
	elseif currentMode == "Spline" then
		table.insert(splinePoints, center)
		updateSplinePreview()
	elseif currentMode == "Cable" then
		if not cableStartPoint then
			cableStartPoint = center
		else
			createCable(cableStartPoint, center)
			cableStartPoint = nil -- Reset for the next cable
		end
	else -- Paint, Erase, Replace, or Stamp
		if currentMode == "Paint" or currentMode == "Erase" or currentMode == "Replace" then
			isPainting = true
		end
		handlePaint(center, normal)
	end
end

local function onUp()
	if currentMode == "Paint" or currentMode == "Erase" or currentMode == "Replace" then
		isPainting = false
		lastPaintPosition = nil
	end
end

updateFillSelection = function()
	if currentMode ~= "Fill" then
		partToFill = nil
		fillSelectionBox.Adornee = nil
		C.fillBtn.Active = false
		C.fillBtn.Text = "Pilih 1 Part untuk Diisi"
		C.fillBtn.BackgroundColor3 = Theme.Red
		return
	end

	local selection = Selection:Get()
	if #selection == 1 and selection[1]:IsA("BasePart") then
		partToFill = selection[1]
		fillSelectionBox.Adornee = partToFill
		C.fillBtn.Active = true
		C.fillBtn.Text = "Isi Part: " .. partToFill.Name
		C.fillBtn.BackgroundColor3 = Theme.Green
	else
		partToFill = nil
		fillSelectionBox.Adornee = nil
		C.fillBtn.Active = false
		C.fillBtn.Text = "Pilih 1 Part untuk Diisi"
		C.fillBtn.BackgroundColor3 = Theme.Red
	end
end

local function randomizeSettings()
	C.scaleMinBox.Text = string.format("%.2f", randFloat(0.5, 1.0))
	C.scaleMaxBox.Text = string.format("%.2f", randFloat(1.1, 2.5))
	C.rotXMinBox.Text = tostring(math.random(0, 45))
	C.rotXMaxBox.Text = tostring(math.random(45, 90))
	C.rotZMinBox.Text = tostring(math.random(0, 45))
	C.rotZMaxBox.Text = tostring(math.random(45, 90))
end

local function addSelectedAssets()
	local selection = Selection:Get()
	for _, v in ipairs(selection) do
		if (v:IsA("Model") or v:IsA("BasePart")) and not assetsFolder:FindFirstChild(v.Name) then
			local clone = v:Clone()
			clone.Parent = assetsFolder
		end
	end
	updateAssetUIList()
end

local function clearAssetList()
	assetsFolder:ClearAllChildren()
	assetOffsets = {}
	persistOffsets()
	updateAssetUIList()
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

	-- Create line preview part
	linePreviewPart = Instance.new("Part")
	linePreviewPart.Name = "BrushLinePreview"
	linePreviewPart.Anchored = true
	linePreviewPart.CanCollide = false
	linePreviewPart.CanQuery = false
	linePreviewPart.CanTouch = false
	linePreviewPart.Transparency = 0.5
	linePreviewPart.BrickColor = BrickColor.new("Institutional white")
	linePreviewPart.Material = Enum.Material.Neon
	linePreviewPart.Size = Vector3.new(0.2, 0.2, 1) -- Length will be set by CFrame

	plugin:Activate(true)
	mouse = plugin:GetMouse()
	moveConn = mouse.Move:Connect(onMove)
	downConn = mouse.Button1Down:Connect(onDown)
	upConn = mouse.Button1Up:Connect(onUp)
	updatePreview()
	updateFillSelection() -- Sync fill selection state
	toolbarBtn:SetActive(true)
	updateOnOffButtonUI()
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
	lineStartPoint = nil
	clearCurve()
	clearCable()
	mouse = nil

	if previewPart then
		previewPart:Destroy()
		previewPart = nil
		cyl = nil
	end

	if linePreviewPart then
		linePreviewPart:Destroy()
		linePreviewPart = nil
	end

	if fillSelectionBox then
		fillSelectionBox.Adornee = nil
	end

	toolbarBtn:SetActive(false)
	updateOnOffButtonUI()
end

local function toggle()
	if active then
		deactivate()
	else
		activate()
	end
end


-- Connect Global Button Events
toolbarBtn.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget.Enabled = false

plugin.Unloading:Connect(function()
	if previewFolder and previewFolder.Parent then
		previewFolder:Destroy()
	end
	if curvePreviewFolder and curvePreviewFolder.Parent then
		curvePreviewFolder:Destroy()
	end
	if splinePreviewFolder and splinePreviewFolder.Parent then
		splinePreviewFolder:Destroy()
	end
	if densityPreviewFolder and densityPreviewFolder.Parent then
		densityPreviewFolder:Destroy()
	end
	if linePreviewPart then
		linePreviewPart:Destroy()
	end
	if fillSelectionBox then
		fillSelectionBox:Destroy()
	end
end)

Selection.SelectionChanged:Connect(updateFillSelection)

function updatePaletteListUI()
	for _, v in ipairs(C.paletteList:GetChildren()) do
		if v:IsA("GuiObject") and not v:IsA("UIListLayout") then v:Destroy() end
	end

	local paletteNames = {}
	for name, _ in pairs(assetPalettes) do
		table.insert(paletteNames, name)
	end
	table.sort(paletteNames)

	for _, name in ipairs(paletteNames) do
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.Text = name
		btn.Size = UDim2.new(1, 0, 0, 24)
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.Font = Enum.Font.SourceSans; btn.TextSize = 14
		btn.Parent = C.paletteList

		if name == selectedPalette then
			btn.BackgroundColor3 = Color3.fromRGB(80, 180, 255)
		end

		btn.MouseButton1Click:Connect(function()
			selectedPalette = name
			C.paletteNameBox.Text = name
			updatePaletteListUI()
		end)
	end
end

function updatePresetListUI()
	for _, v in ipairs(C.presetList:GetChildren()) do
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
		btn.Parent = C.presetList

		if name == selectedPreset then
			btn.BackgroundColor3 = Color3.fromRGB(80, 180, 255)
		end

		btn.MouseButton1Click:Connect(function()
			selectedPreset = name
			C.presetNameBox.Text = name
			updatePresetListUI()
		end)
	end
end

-- Initial Load and Print
loadOffsets()
loadPresets()
loadPalettes()
updateAssetUIList()
updatePresetListUI()
updatePaletteListUI()
updateModeButtonsUI()
updateToggleButtonsUI()
updateMaskingUI()
populateMaterialPicker()

local function setMode(newMode)
	if currentMode == newMode then return end

	-- Reset state dari mode sebelumnya
	if currentMode == "Replace" then
		sourceAsset = nil
		targetAsset = nil
	end
	if currentMode == "Erase" and newMode ~= "Erase" then
		eraseFilter = {}
	end

	lineStartPoint = nil -- Reset line tool on mode change
	if linePreviewPart then linePreviewPart.Parent = nil end

	if newMode ~= "Curve" then
		clearCurve()
	end
	if newMode ~= "Spline" then
		clearSpline()
	end
	if newMode ~= "Cable" then
		clearCable()
	end

	currentMode = newMode

	-- Update UI
	updateModeButtonsUI()
	updateAssetSettingsPanel()
	updateAssetUIList()
	updatePreview()
	updateFillSelection()

	-- Handle visibility of mode-specific controls
	-- Hide all contextual controls first
	for _, child in ipairs(C.modeSettingsContent:GetChildren()) do
		if child:IsA("GuiObject") then
			child.Visible = false
		end
	end

	-- Show controls based on the new mode
	if newMode == "Paint" or newMode == "Erase" or newMode == "Replace" or newMode == "Volume" then
		C.radiusRow.Visible = true
	end
	if newMode == "Paint" or newMode == "Fill" or newMode == "Volume" then
		C.densityRow.Visible = true
	end
	if newMode == "Paint" or newMode == "Line" or newMode == "Curve" or newMode == "Spline" then
		C.spacingRow.Visible = true
	end
	if newMode == "Fill" then
		C.fillBtn.Visible = true
	end
	if newMode == "Curve" then
		C.curveActionsFrame.Visible = true
	end
	if newMode == "Spline" then
		C.splineActionsFrame.Visible = true
	end
	if newMode == "Cable" then
		C.cableSagRow.Visible = true
		C.cableSegmentsRow.Visible = true
		C.cableThicknessRow.Visible = true
		C.cableColorRow.Visible = true
		C.cableMaterialRow.Visible = true
	end
end

-- Final UI Connections
C.onOffBtn.MouseButton1Click:Connect(toggle)

for modeName, button in pairs(C.modeButtons) do
	button.MouseButton1Click:Connect(function()
		setMode(modeName)
	end)
end

C.randomizeBtn.MouseButton1Click:Connect(randomizeSettings)
C.addBtn.MouseButton1Click:Connect(addSelectedAssets)
C.clearBtn.MouseButton1Click:Connect(clearAssetList)

-- Curve Buttons
C.applyCurveBtn.MouseButton1Click:Connect(paintAlongCurve)
C.clearCurveBtn.MouseButton1Click:Connect(clearCurve)

-- Spline Buttons
C.applySplineBtn.MouseButton1Click:Connect(paintAlongSpline)
C.clearSplineBtn.MouseButton1Click:Connect(clearSpline)


-- Palette Buttons
C.savePaletteBtn.MouseButton1Click:Connect(function()
	saveAssetPalette(C.paletteNameBox.Text)
end)

C.loadPaletteBtn.MouseButton1Click:Connect(function()
	if selectedPalette then
		loadAssetPalette(selectedPalette)
	end
end)

C.deletePaletteBtn.MouseButton1Click:Connect(function()
	if selectedPalette then
		deleteAssetPalette(selectedPalette)
	end
end)

-- Preset Buttons
C.savePresetBtn.MouseButton1Click:Connect(function()
	savePreset(C.presetNameBox.Text)
end)

C.loadPresetBtn.MouseButton1Click:Connect(function()
	if selectedPreset then
		loadPreset(selectedPreset)
	end
end)

C.deletePresetBtn.MouseButton1Click:Connect(function()
	if selectedPreset then
		deletePreset(selectedPreset)
	end
end)

C.avoidOverlapBtn.MouseButton1Click:Connect(function()
	avoidOverlap = not avoidOverlap
	updateToggleButtonsUI()
end)

C.surfaceAngleBtn.MouseButton1Click:Connect(function()
	if surfaceAngleMode == "Off" then
		surfaceAngleMode = "Floor"
	elseif surfaceAngleMode == "Floor" then
		surfaceAngleMode = "Wall"
	else -- Pasti "Wall"
		surfaceAngleMode = "Off"
	end
	updateToggleButtonsUI()
end)

C.physicsModeBtn.MouseButton1Click:Connect(function()
	physicsModeEnabled = not physicsModeEnabled
	updateToggleButtonsUI()
end)

C.physicsSettleTimeBox.FocusLost:Connect(function(enterPressed)
	local newValue = parseNumber(C.physicsSettleTimeBox.Text, 1.5)
	if newValue < 0.1 then newValue = 0.1 end -- Waktu minimal
	physicsSettleTime = newValue
	C.physicsSettleTimeBox.Text = tostring(newValue)
end)

C.snapToGridBtn.MouseButton1Click:Connect(function()
	snapToGridEnabled = not snapToGridEnabled
	updateToggleButtonsUI()
end)

C.gridSizeBox.FocusLost:Connect(function(enterPressed)
	local newValue = parseNumber(C.gridSizeBox.Text, 4)
	if newValue <= 0 then newValue = 1 end -- Ukuran minimal
	gridSize = newValue
	C.gridSizeBox.Text = tostring(newValue)
end)

C.densityPreviewBtn.MouseButton1Click:Connect(function()
	densityPreviewEnabled = not densityPreviewEnabled
	updateToggleButtonsUI()
end)

C.splineFollowPathBtn.MouseButton1Click:Connect(function()
	splineFollowPath = not splineFollowPath
	updateToggleButtonsUI()
end)

C.splineCloseLoopBtn.MouseButton1Click:Connect(function()
	splineCloseLoop = not splineCloseLoop
	updateSplinePreview() -- Redraw preview to show the loop
	updateToggleButtonsUI()
end)

C.maskingModeBtn.MouseButton1Click:Connect(function()
	if maskingMode == "Off" then
		maskingMode = "Material"
	elseif maskingMode == "Material" then
		maskingMode = "Color"
	elseif maskingMode == "Color" then
		maskingMode = "Tag"
	else -- Tag
		maskingMode = "Off"
	end
	maskingValue = nil
	updateMaskingUI()
end)

C.pickMaskTargetBtn.MouseButton1Click:Connect(function()
	local selection = Selection:Get()
	if #selection > 0 and selection[1]:IsA("BasePart") then
		local targetPart = selection[1]
		if maskingMode == "Material" then
			maskingValue = targetPart.Material
		elseif maskingMode == "Color" then
			maskingValue = targetPart.Color
		elseif maskingMode == "Tag" then
			local tags = CollectionService:GetTags(targetPart)
			if #tags > 0 then
				maskingValue = tags[1]
			else
				maskingValue = nil
			end
		end
		updateMaskingUI()
	end
end)

local function parseColor(str)
	local r, g, b = str:match("^(%d+),%s*(%d+),%s*(%d+)$")
	if r and g and b then
		local rNum, gNum, bNum = tonumber(r), tonumber(g), tonumber(b)
		if rNum and gNum and bNum and rNum <= 255 and gNum <= 255 and bNum <= 255 then
			return Color3.fromRGB(rNum, gNum, bNum)
		end
	end
	return nil
end

C.maskingTextBox.FocusLost:Connect(function(enterPressed)
	if not enterPressed then return end
	local text = C.maskingTextBox.Text
	if text == "" then
		maskingValue = nil
	elseif maskingMode == "Tag" then
		maskingValue = text
	elseif maskingMode == "Color" then
		local color = parseColor(text)
		if color then
			maskingValue = color
		else
			warn("Brush Tool: Invalid color format. Please use R, G, B (e.g., 255, 128, 0).")
		end
	elseif maskingMode == "Material" then
		local success, materialEnum = pcall(function() return Enum.Material[text] end)
		if success and materialEnum then
			maskingValue = materialEnum
		else
			warn("Brush Tool: Invalid material name: " .. text)
		end
	end
	updateMaskingUI()
end)


-- Initialize Preview Folder at a global scope
previewFolder = workspace:FindFirstChild("_BrushPreview")
if previewFolder then
	previewFolder:Destroy()
end
previewFolder = Instance.new("Folder")
previewFolder.Name = "_BrushPreview"
previewFolder.Parent = workspace


-- Initialize Density Preview Folder
densityPreviewFolder = workspace:FindFirstChild("_DensityPreview")
if densityPreviewFolder then
	densityPreviewFolder:Destroy()
end
densityPreviewFolder = Instance.new("Folder")
densityPreviewFolder.Name = "_DensityPreview"
densityPreviewFolder.Parent = workspace


-- Initialize Curve Preview Folder
curvePreviewFolder = workspace:FindFirstChild("_CurvePreview")
if curvePreviewFolder then
	curvePreviewFolder:Destroy()
end
curvePreviewFolder = Instance.new("Folder")
curvePreviewFolder.Name = "_CurvePreview"
curvePreviewFolder.Parent = workspace

-- Initialize Spline Preview Folder
splinePreviewFolder = workspace:FindFirstChild("_SplinePreview")
if splinePreviewFolder then
	splinePreviewFolder:Destroy()
end
splinePreviewFolder = Instance.new("Folder")
splinePreviewFolder.Name = "_SplinePreview"
splinePreviewFolder.Parent = workspace

-- Initialize Cable Preview Folder
cablePreviewFolder = workspace:FindFirstChild("_CablePreview")
if cablePreviewFolder then
	cablePreviewFolder:Destroy()
end
cablePreviewFolder = Instance.new("Folder")
cablePreviewFolder.Name = "_CablePreview"
cablePreviewFolder.Parent = workspace

-- Initialize SelectionBox for Fill tool
fillSelectionBox = Instance.new("SelectionBox")
fillSelectionBox.Color3 = Color3.fromRGB(0, 255, 127) -- Spring Green
fillSelectionBox.LineThickness = 0.2
fillSelectionBox.Parent = previewFolder -- Store it here to keep workspace clean

C.fillBtn.MouseButton1Click:Connect(function()
	if C.fillBtn.Active and partToFill then
		fillArea(partToFill)
	end
end)

print("Brush Tool plugin loaded.")
