--[[
	Brush Tool Plugin for Roblox Studio - "Cyber-Industrial" Edition (V8)
	
	Features:
	- Complete UI Overhaul: Tabbed Interface, Dark/Industrial Theme.
	- Robust Logic Restored: Physics, Path Splines, Volume Painting, Masking.
	- Enhanced UX: Hover states, clear active indicators, organized settings.
	- Fully Interactive: All buttons and inputs connected with persistence.
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
local SETTINGS_KEY = "BrushToolAssetOffsets_v5"

-- Ensure assets folder exists
local assetsFolder = ServerStorage:FindFirstChild(ASSET_FOLDER_NAME)
if not assetsFolder then
	assetsFolder = Instance.new("Folder")
	assetsFolder.Name = ASSET_FOLDER_NAME
	assetsFolder.Parent = ServerStorage
end

-- State Variables
local assetOffsets = {}
local currentMode = "Paint"
local active = false
local mouse = nil
local moveConn, downConn, upConn
local previewPart, cyl
local isPainting = false
local lastPaintPosition = nil
local lineStartPoint = nil
local linePreviewPart = nil
local pathPoints = {}
local pathPreviewFolder = nil
local pathFollowPath = false
local builderPostAsset = nil
local builderSegmentAsset = nil
local builderSlotToAssign = nil
local builderStartPoint = nil
local builderPreviewFolder = nil
local pathCloseLoop = false
local cableStartPoint = nil
local cablePreviewFolder = nil
local cableColor = Color3.fromRGB(50, 50, 50)
local cableMaterial = Enum.Material.Plastic
local partToFill = nil
local fillSelectionBox = nil
local sourceAsset = nil
local targetAsset = nil
local eraseFilter = {}
local selectedAssetInUI = nil
local avoidOverlap = false
local previewFolder = nil
local densityPreviewFolder = nil
local surfaceAngleMode = "Off"
local snapToGridEnabled = false
local gridSize = 4
local densityPreviewEnabled = true
local autoTerrainPaint = false
local terrainUndoStack = {}
local maskingMode = "Off"
local maskingValue = nil
local physicsModeEnabled = false
local physicsSettleTime = 1.5

-- Forward Declarations
local updateAssetUIList
local updateFillSelection = nil
local updateDensityPreview
local clearPath
local updatePathPreview
local updateCablePreview
local clearCable
local catmullRom
local placeAsset
local getRandomWeightedAsset
local getWorkspaceContainer
local parseNumber
local paintAlongPath
local persistOffsets
local loadOffsets
local updateBuilderPreview
local updatePreview
local createCable
local paintAt
local scaleModel
local randomizeProperties
local findSurfacePositionAndNormal
local paintTerrainUnderAsset
local anchorPhysicsGroup
local paintInVolume
local stampAt
local eraseAt
local paintAlongLine
local fillArea
local replaceAt
local calculateCatenary
local createBuilderStructure
local trim
local activate
local deactivate
local setMode
local updateModeButtonsUI
local updateAllToggles
local addSelectedAssets
local clearAssetList
local updateMaskingUI
local randomPointInCircle

--[[
    VISUAL THEME: CYBER-INDUSTRIAL
]]
local Theme = {
	Background = Color3.fromHex("121214"),
	Panel = Color3.fromHex("1E1E24"),
	Border = Color3.fromHex("383842"),
	BorderActive = Color3.fromHex("00A8FF"),
	Text = Color3.fromHex("E0E0E0"),
	TextDim = Color3.fromHex("808080"),
	Accent = Color3.fromHex("00A8FF"),
	AccentHover = Color3.fromHex("33BFFF"),
	Warning = Color3.fromHex("FFB302"),
	Destructive = Color3.fromHex("FF2A6D"),
	Success = Color3.fromHex("05FFA1"),
	FontMain = Enum.Font.GothamMedium,
	FontHeader = Enum.Font.GothamBold,
	FontTech = Enum.Font.Code,
}

-- UI Components Storage
local C = {}
local allTabs = {}

-- UI Helper Functions
local function createTechFrame(parent, size)
	local f = Instance.new("Frame")
	f.Size = size
	f.BackgroundColor3 = Theme.Panel
	f.BorderSizePixel = 0
	f.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = f
	return f, stroke
end

local function createTechButton(text, parent)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 32)
	btn.BackgroundColor3 = Theme.Panel
	btn.Text = text
	btn.TextColor3 = Theme.Text
	btn.Font = Theme.FontMain
	btn.TextSize = 14
	btn.AutoButtonColor = false
	btn.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = btn

	btn.MouseEnter:Connect(function()
		stroke.Color = Theme.Accent
		btn.TextColor3 = Theme.Accent
	end)
	btn.MouseLeave:Connect(function()
		stroke.Color = Theme.Border
		btn.TextColor3 = Theme.Text
	end)
	return btn, stroke
end

local function createTechToggle(text, parent)
	local container = Instance.new("Frame")
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 32)
	container.Parent = parent

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 24, 0, 24)
	btn.Position = UDim2.new(0, 0, 0.5, -12)
	btn.BackgroundColor3 = Theme.Background
	btn.Text = ""
	btn.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Parent = btn

	local inner = Instance.new("Frame")
	inner.Size = UDim2.new(1, -6, 1, -6)
	inner.Position = UDim2.new(0, 3, 0, 3)
	inner.BackgroundColor3 = Theme.Accent
	inner.BorderSizePixel = 0
	inner.Visible = false
	inner.Parent = btn

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -32, 1, 0)
	label.Position = UDim2.new(0, 32, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Theme.FontMain
	label.TextSize = 13
	label.TextColor3 = Theme.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = container

	return btn, inner, label
end

local function createTechInput(labelText, defaultValue, parent)
	local container = Instance.new("Frame")
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 40)
	container.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 16)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.Font = Theme.FontMain
	label.TextSize = 12
	label.TextColor3 = Theme.TextDim
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = container

	local inputBox = Instance.new("TextBox")
	inputBox.Size = UDim2.new(1, 0, 0, 22)
	inputBox.Position = UDim2.new(0, 0, 0, 18)
	inputBox.BackgroundColor3 = Theme.Background
	inputBox.Text = tostring(defaultValue)
	inputBox.TextColor3 = Theme.Accent
	inputBox.Font = Theme.FontTech
	inputBox.TextSize = 14
	inputBox.TextXAlignment = Enum.TextXAlignment.Left
	inputBox.Parent = container

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.Parent = inputBox

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Parent = inputBox

	inputBox.Focused:Connect(function() stroke.Color = Theme.Accent end)
	inputBox.FocusLost:Connect(function() stroke.Color = Theme.Border end)

	return inputBox, container
end

local function createSectionHeader(text, parent)
	local h = Instance.new("TextLabel")
	h.Size = UDim2.new(1, 0, 0, 24)
	h.BackgroundTransparency = 1
	h.Text = "// " .. string.upper(text)
	h.Font = Theme.FontTech
	h.TextSize = 12
	h.TextColor3 = Theme.Warning
	h.TextXAlignment = Enum.TextXAlignment.Left
	h.Parent = parent
	return h
end

-- Main Widget Setup
local toolbar = plugin:CreateToolbar("Brush Tool V8")
local toolbarBtn = toolbar:CreateButton("Brush", "Open Brush Tool", "rbxassetid://1507949203")

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	false, false, 400, 650, 350, 400
)
local widget = plugin:CreateDockWidgetPluginGui("BrushToolWidgetV8", widgetInfo)
widget.Title = "BRUSH TOOL // PROTOCOL"

local uiRoot = Instance.new("Frame")
uiRoot.Size = UDim2.new(1, 0, 1, 0)
uiRoot.BackgroundColor3 = Theme.Background
uiRoot.Parent = widget

-- Top Bar
local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, 0, 0, 40)
topBar.BackgroundColor3 = Theme.Panel
topBar.BorderSizePixel = 0
topBar.Parent = uiRoot

local statusIndicator = Instance.new("Frame")
statusIndicator.Size = UDim2.new(0, 8, 0, 8)
statusIndicator.Position = UDim2.new(0, 12, 0.5, -4)
statusIndicator.BackgroundColor3 = Theme.Destructive
statusIndicator.Parent = topBar
Instance.new("UICorner", statusIndicator).CornerRadius = UDim.new(1, 0)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -40, 1, 0)
titleLabel.Position = UDim2.new(0, 28, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "SYSTEM: STANDBY"
titleLabel.Font = Theme.FontTech
titleLabel.TextSize = 14
titleLabel.TextColor3 = Theme.Text
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = topBar

C.activationBtn = Instance.new("TextButton")
C.activationBtn.Size = UDim2.new(0, 100, 0, 24)
C.activationBtn.AnchorPoint = Vector2.new(1, 0.5)
C.activationBtn.Position = UDim2.new(1, -12, 0.5, 0)
C.activationBtn.BackgroundColor3 = Theme.Background
C.activationBtn.Text = "ACTIVATE"
C.activationBtn.Font = Theme.FontHeader
C.activationBtn.TextSize = 11
C.activationBtn.TextColor3 = Theme.Text
C.activationBtn.Parent = topBar
Instance.new("UIStroke", C.activationBtn).Color = Theme.Border

-- Tabs
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, 0, 0, 36)
tabBar.Position = UDim2.new(0, 0, 0, 40)
tabBar.BackgroundColor3 = Theme.Background
tabBar.BorderSizePixel = 0
tabBar.Parent = uiRoot

local tabBarLayout = Instance.new("UIListLayout")
tabBarLayout.FillDirection = Enum.FillDirection.Horizontal
tabBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabBarLayout.Parent = tabBar

local tabContent = Instance.new("Frame")
tabContent.Size = UDim2.new(1, 0, 1, -76)
tabContent.Position = UDim2.new(0, 0, 0, 76)
tabContent.BackgroundTransparency = 1
tabContent.Parent = uiRoot

local function switchTab(tabName)
	for _, t in pairs(allTabs) do
		if t.Name == tabName then
			t.Button.TextColor3 = Theme.Accent
			t.Indicator.Visible = true
			t.Frame.Visible = true
		else
			t.Button.TextColor3 = Theme.TextDim
			t.Indicator.Visible = false
			t.Frame.Visible = false
		end
	end
end

local function createTab(name, label)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.new(0.333, 0, 1, 0)
	btn.BackgroundTransparency = 1
	btn.Text = label
	btn.Font = Theme.FontHeader
	btn.TextSize = 12
	btn.TextColor3 = Theme.TextDim
	btn.Parent = tabBar
	local indicator = Instance.new("Frame")
	indicator.Size = UDim2.new(1, -4, 0, 2)
	indicator.Position = UDim2.new(0, 2, 1, -2)
	indicator.BackgroundColor3 = Theme.Accent
	indicator.BorderSizePixel = 0
	indicator.Visible = false
	indicator.Parent = btn
	local frame = Instance.new("ScrollingFrame")
	frame.Name = name .. "Frame"
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundTransparency = 1
	frame.ScrollBarThickness = 4
	frame.ScrollBarImageColor3 = Theme.Border
	frame.Visible = false
	frame.Parent = tabContent
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.Parent = frame
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = frame
	btn.MouseButton1Click:Connect(function() switchTab(name) end)
	table.insert(allTabs, {Name = name, Button = btn, Indicator = indicator, Frame = frame})
	return {frame = frame}
end

local TabTools = createTab("Tools", "OPERATIONS")
local TabAssets = createTab("Assets", "INVENTORY")
local TabTuning = createTab("Tuning", "SYSTEM")

-- Tools Tab
createSectionHeader("MODE SELECT", TabTools.frame)
local modeGrid = Instance.new("Frame")
modeGrid.Size = UDim2.new(1, 0, 0, 100)
modeGrid.AutomaticSize = Enum.AutomaticSize.Y
modeGrid.BackgroundTransparency = 1
modeGrid.Parent = TabTools.frame
local mgLayout = Instance.new("UIGridLayout")
mgLayout.CellSize = UDim2.new(0.34, 0, 0, 36)
mgLayout.CellPadding = UDim2.new(0.03, 0, 0, 8)
mgLayout.Parent = modeGrid

C.modeButtons = {}
local modeNames = {"Paint", "Line", "Path", "Fill", "Replace", "Stamp", "Volume", "Erase", "Cable", "Builder"}
for _, m in ipairs(modeNames) do
	local b, s = createTechButton(string.upper(m), modeGrid)
	b.TextSize = 11
	C.modeButtons[m] = {Button = b, Stroke = s}
end

createSectionHeader("BRUSH PARAMETERS", TabTools.frame)
local brushParamsContainer = Instance.new("Frame")
brushParamsContainer.Size = UDim2.new(1, 0, 0, 100)
brushParamsContainer.AutomaticSize = Enum.AutomaticSize.Y
brushParamsContainer.BackgroundTransparency = 1
brushParamsContainer.Parent = TabTools.frame
local bpLayout = Instance.new("UIGridLayout")
bpLayout.CellSize = UDim2.new(0.48, 0, 0, 40)
bpLayout.CellPadding = UDim2.new(0.04, 0, 0, 8)
bpLayout.Parent = brushParamsContainer

C.radiusBox = {createTechInput("RADIUS (Studs)", "10", brushParamsContainer)}
C.densityBox = {createTechInput("DENSITY (Count)", "10", brushParamsContainer)}
C.spacingBox = {createTechInput("SPACING (Studs)", "1.5", brushParamsContainer)}

C.contextContainer = Instance.new("Frame")
C.contextContainer.Size = UDim2.new(1, 0, 0, 20)
C.contextContainer.AutomaticSize = Enum.AutomaticSize.Y
C.contextContainer.BackgroundTransparency = 1
C.contextContainer.Parent = TabTools.frame

-- Path Context
C.pathFrame = Instance.new("Frame")
C.pathFrame.AutomaticSize = Enum.AutomaticSize.Y
C.pathFrame.Size = UDim2.new(1, 0, 0, 0)
C.pathFrame.BackgroundTransparency = 1
C.pathFrame.Visible = false
C.pathFrame.Parent = C.contextContainer
Instance.new("UIListLayout", C.pathFrame).Padding = UDim.new(0, 8)
createSectionHeader("PATH SETTINGS", C.pathFrame)
local pathBtnGrid = Instance.new("Frame")
pathBtnGrid.Size = UDim2.new(1, 0, 0, 32)
pathBtnGrid.BackgroundTransparency = 1
pathBtnGrid.Parent = C.pathFrame
local pgl = Instance.new("UIGridLayout")
pgl.CellSize = UDim2.new(0.48, 0, 0, 32)
pgl.CellPadding = UDim2.new(0.04, 0, 0, 0)
pgl.Parent = pathBtnGrid
C.applyPathBtn = {createTechButton("GENERATE", pathBtnGrid)}
C.clearPathBtn = {createTechButton("CLEAR", pathBtnGrid)}
C.clearPathBtn[1].TextColor3 = Theme.Destructive
C.pathFollowPathBtn = {createTechToggle("Follow Curvature", C.pathFrame)}
C.pathCloseLoopBtn = {createTechToggle("Close Loop", C.pathFrame)}

-- Builder Context
C.builderFrame = Instance.new("Frame")
C.builderFrame.AutomaticSize = Enum.AutomaticSize.Y
C.builderFrame.Size = UDim2.new(1, 0, 0, 0)
C.builderFrame.BackgroundTransparency = 1
C.builderFrame.Visible = false
C.builderFrame.Parent = C.contextContainer
Instance.new("UIListLayout", C.builderFrame).Padding = UDim.new(0, 8)
createSectionHeader("CONSTRUCTION PROTOCOL", C.builderFrame)
C.builderPostSlot = {createTechButton("ASSIGN POST [NONE]", C.builderFrame)}
C.builderSegmentSlot = {createTechButton("ASSIGN SEGMENT [NONE]", C.builderFrame)}
local bGrid = Instance.new("Frame")
bGrid.Size = UDim2.new(1, 0, 0, 50)
bGrid.BackgroundTransparency = 1
bGrid.Parent = C.builderFrame
Instance.new("UIGridLayout", bGrid).CellSize = UDim2.new(0.48, 0, 0, 40)
C.builderDistanceBox = {createTechInput("DIST (Studs)", "8", bGrid)}
C.builderHeightBox = {createTechInput("Y-OFFSET", "0.2", bGrid)}
C.builderStretchToggle = {createTechToggle("Stretch Segment", C.builderFrame)}

-- Cable Context
C.cableFrame = Instance.new("Frame")
C.cableFrame.AutomaticSize = Enum.AutomaticSize.Y
C.cableFrame.Size = UDim2.new(1, 0, 0, 0)
C.cableFrame.BackgroundTransparency = 1
C.cableFrame.Visible = false
C.cableFrame.Parent = C.contextContainer
Instance.new("UIListLayout", C.cableFrame).Padding = UDim.new(0, 8)
createSectionHeader("CABLE PHYSICS", C.cableFrame)
local cGrid = Instance.new("Frame")
cGrid.Size = UDim2.new(1, 0, 0, 50)
cGrid.BackgroundTransparency = 1
cGrid.Parent = C.cableFrame
Instance.new("UIGridLayout", cGrid).CellSize = UDim2.new(0.3, 0, 0, 40)
C.cableSagBox = {createTechInput("SAG", "5", cGrid)}
C.cableSegmentsBox = {createTechInput("SEGMENTS", "10", cGrid)}
C.cableThicknessBox = {createTechInput("THICK", "0.2", cGrid)}
C.cableMaterialButton = {createTechButton("MAT: PLASTIC", C.cableFrame)}
C.cableColorButton = {createTechButton("COLOR SELECT", C.cableFrame)}

-- Fill Context
C.fillFrame = Instance.new("Frame")
C.fillFrame.AutomaticSize = Enum.AutomaticSize.Y
C.fillFrame.Size = UDim2.new(1, 0, 0, 0)
C.fillFrame.BackgroundTransparency = 1
C.fillFrame.Visible = false
C.fillFrame.Parent = C.contextContainer
C.fillBtn = {createTechButton("SELECT TARGET VOLUME", C.fillFrame)}

-- Assets Tab
createSectionHeader("ASSET MANAGEMENT", TabAssets.frame)
local assetActions = Instance.new("Frame")
assetActions.Size = UDim2.new(1, 0, 0, 32)
assetActions.BackgroundTransparency = 1
assetActions.Parent = TabAssets.frame
local aal = Instance.new("UIListLayout")
aal.FillDirection = Enum.FillDirection.Horizontal
aal.Padding = UDim.new(0, 8)
aal.Parent = assetActions
C.addBtn = {createTechButton("+ ADD SELECTED", assetActions)}
C.addBtn[1].Size = UDim2.new(0.5, -4, 1, 0)
C.addBtn[1].TextColor3 = Theme.Success
C.clearBtn = {createTechButton("CLEAR ALL", assetActions)}
C.clearBtn[1].Size = UDim2.new(0.5, -4, 1, 0)
C.clearBtn[1].TextColor3 = Theme.Destructive

C.assetListFrame = Instance.new("Frame")
C.assetListFrame.Size = UDim2.new(1, 0, 0, 200)
C.assetListFrame.AutomaticSize = Enum.AutomaticSize.Y
C.assetListFrame.BackgroundTransparency = 1
C.assetListFrame.Parent = TabAssets.frame
local alGrid = Instance.new("UIGridLayout")
alGrid.CellSize = UDim2.new(0.48, 0, 0, 100)
alGrid.CellPadding = UDim2.new(0.03, 0, 0, 8)
alGrid.Parent = C.assetListFrame

C.assetSettingsFrame = Instance.new("Frame")
C.assetSettingsFrame.Size = UDim2.new(1, 0, 0, 150)
C.assetSettingsFrame.BackgroundTransparency = 1
C.assetSettingsFrame.Visible = false
C.assetSettingsFrame.Parent = TabAssets.frame
Instance.new("UIListLayout", C.assetSettingsFrame).Padding = UDim.new(0, 8)
local sep = Instance.new("Frame")
sep.Size = UDim2.new(1, 0, 0, 1)
sep.BackgroundColor3 = Theme.Border
sep.BorderSizePixel = 0
sep.Parent = C.assetSettingsFrame
C.assetSettingsName = createSectionHeader("SELECTED: ???", C.assetSettingsFrame)
local asGrid = Instance.new("Frame")
asGrid.Size = UDim2.new(1, 0, 0, 80)
asGrid.BackgroundTransparency = 1
asGrid.Parent = C.assetSettingsFrame
local asgl = Instance.new("UIGridLayout")
asgl.CellSize = UDim2.new(0.48, 0, 0, 40)
asgl.CellPadding = UDim2.new(0.04, 0, 0, 8)
asgl.Parent = asGrid
C.assetSettingsOffsetY = {createTechInput("Y-OFFSET", "0", asGrid)}
C.assetSettingsWeight = {createTechInput("PROBABILITY", "1", asGrid)}
C.assetSettingsAlign = {createTechToggle("Align to Surface", C.assetSettingsFrame)}
C.assetSettingsActive = {createTechToggle("Active in Brush", C.assetSettingsFrame)}

-- Tuning Tab
createSectionHeader("TRANSFORMATION RANDOMIZER", TabTuning.frame)
local transGrid = Instance.new("Frame")
transGrid.Size = UDim2.new(1, 0, 0, 0)
transGrid.AutomaticSize = Enum.AutomaticSize.Y
transGrid.BackgroundTransparency = 1
transGrid.Parent = TabTuning.frame
local tgl = Instance.new("UIGridLayout")
tgl.CellSize = UDim2.new(0.48, 0, 0, 40)
tgl.CellPadding = UDim2.new(0.04, 0, 0, 8)
tgl.Parent = transGrid
C.scaleMinBox = {createTechInput("SCALE MIN", "0.8", transGrid)}
C.scaleMaxBox = {createTechInput("SCALE MAX", "1.2", transGrid)}
C.rotXMinBox = {createTechInput("ROT X MIN", "0", transGrid)}
C.rotXMaxBox = {createTechInput("ROT X MAX", "0", transGrid)}
C.rotZMinBox = {createTechInput("ROT Z MIN", "0", transGrid)}
C.rotZMaxBox = {createTechInput("ROT Z MAX", "0", transGrid)}
-- Added Missing Color Inputs
C.hueMinBox = {createTechInput("HUE MIN", "0", transGrid)}
C.hueMaxBox = {createTechInput("HUE MAX", "0", transGrid)}
C.satMinBox = {createTechInput("SAT MIN", "0", transGrid)}
C.satMaxBox = {createTechInput("SAT MAX", "0", transGrid)}
C.valMinBox = {createTechInput("VAL MIN", "0", transGrid)}
C.valMaxBox = {createTechInput("VAL MAX", "0", transGrid)}
C.transMinBox = {createTechInput("TRNS MIN", "0", transGrid)}
C.transMaxBox = {createTechInput("TRNS MAX", "0", transGrid)}

C.randomizeBtn = {createTechButton("RANDOMIZE VALUES", TabTuning.frame)}
C.randomizeBtn[1].Size = UDim2.new(1, 0, 0, 32)

createSectionHeader("ENVIRONMENT CONTROL", TabTuning.frame)
C.physicsModeBtn = {createTechToggle("Physics Placement", TabTuning.frame)}
C.physicsSettleTimeBox = {createTechInput("PHYSICS TIME (s)", "1.5", TabTuning.frame)}
C.snapToGridBtn = {createTechToggle("Snap to Grid", TabTuning.frame)}
C.gridSizeBox = {createTechInput("GRID SIZE", "4", TabTuning.frame)}
C.surfaceAngleBtn = {createTechToggle("Surface Lock: OFF", TabTuning.frame)}
C.avoidOverlapBtn = {createTechToggle("Avoid Overlap", TabTuning.frame)}
C.densityPreviewBtn = {createTechToggle("Show Density Dots", TabTuning.frame)}

createSectionHeader("MASKING & FILTERS", TabTuning.frame)
C.maskingModeBtn = {createTechButton("MASK: OFF", TabTuning.frame)}
C.pickMaskTargetBtn = {createTechButton("PICK FROM SELECTION", TabTuning.frame)}
C.maskingTargetLabel = Instance.new("TextLabel")
C.maskingTargetLabel.Size = UDim2.new(1, 0, 0, 20)
C.maskingTargetLabel.BackgroundTransparency = 1
C.maskingTargetLabel.Text = "TARGET: NONE"
C.maskingTargetLabel.Font = Theme.FontTech
C.maskingTargetLabel.TextColor3 = Theme.Accent
C.maskingTargetLabel.TextSize = 12
C.maskingTargetLabel.Parent = TabTuning.frame
C.autoTerrainPaintBtn = {createTechToggle("Auto-Paint Terrain", TabTuning.frame)}

-- Switch Tab
switchTab("Tools")

-- ==========================================
-- LOGIC HELPERS & IMPLEMENTATION
-- ==========================================

trim = function(s)
	return s:match("^%s*(.-)%s*$") or s
end

parseNumber = function(txt, fallback)
	local ok, n = pcall(function() return tonumber(trim(txt)) end)
	if ok and n then return n end
	return fallback
end

loadOffsets = function()
	local jsonString = plugin:GetSetting(SETTINGS_KEY)
	if jsonString and #jsonString > 0 then
		local ok, data = pcall(HttpService.JSONDecode, HttpService, jsonString)
		if ok and type(data) == "table" then assetOffsets = data else assetOffsets = {} end
	else assetOffsets = {} end
end

persistOffsets = function()
	local ok, jsonString = pcall(HttpService.JSONEncode, HttpService, assetOffsets)
	if ok then plugin:SetSetting(SETTINGS_KEY, jsonString) end
end

local function randFloat(a, b)
	return a + math.random() * (b - a)
end

randomPointInCircle = function(radius)
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
	return Vector3.new(r * math.sin(phi) * math.cos(theta), r * math.sin(phi) * math.sin(theta), r * math.cos(phi))
end

catmullRom = function(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
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

getRandomWeightedAsset = function(assetList)
	local totalWeight = 0
	for _, asset in ipairs(assetList) do
		local weight = assetOffsets[asset.Name .. "_weight"] or 1
		totalWeight = totalWeight + weight
	end
	if totalWeight == 0 then return assetList[math.random(1, #assetList)] end
	local randomNum = math.random() * totalWeight
	local currentWeight = 0
	for _, asset in ipairs(assetList) do
		local weight = assetOffsets[asset.Name .. "_weight"] or 1
		currentWeight = currentWeight + weight
		if randomNum <= currentWeight then return asset end
	end
	return assetList[#assetList]
end

scaleModel = function(model, scale)
	local ok, bboxCFrame, bboxSize = pcall(function() return model:GetBoundingBox() end)
	if not ok then return end
	local center = bboxCFrame.Position
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = d.Position - center
			d.Size = d.Size * scale
			d.CFrame = CFrame.new(center + rel * scale) * (d.CFrame - d.CFrame.Position)
		elseif d:IsA("SpecialMesh") then
			d.Scale = d.Scale * scale
		elseif d:IsA("MeshPart") then
			pcall(function() d.Mesh.Scale = d.Mesh.Scale * scale end)
		end
	end
end

randomizeProperties = function(target)
	local hmin = parseNumber(C.hueMinBox[1].Text, 0)
	local hmax = parseNumber(C.hueMaxBox[1].Text, 0)
	local smin = parseNumber(C.satMinBox[1].Text, 0)
	local smax = parseNumber(C.satMaxBox[1].Text, 0)
	local vmin = parseNumber(C.valMinBox[1].Text, 0)
	local vmax = parseNumber(C.valMaxBox[1].Text, 0)
	local tmin = parseNumber(C.transMinBox[1].Text, 0)
	local tmax = parseNumber(C.transMaxBox[1].Text, 0)

	local hasColorShift = (hmin ~= 0 or hmax ~= 0 or smin ~= 0 or smax ~= 0 or vmin ~= 0 or vmax ~= 0)
	local hasTransShift = (tmin ~= 0 or tmax ~= 0)
	if not hasColorShift and not hasTransShift then return end

	local parts = {}
	if target:IsA("BasePart") then table.insert(parts, target) else
		for _, descendant in ipairs(target:GetDescendants()) do
			if descendant:IsA("BasePart") then table.insert(parts, descendant) end
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

local function snapPositionToGrid(position, size)
	if size <= 0 then return position end
	local x = math.floor(position.X / size + 0.5) * size
	local y = math.floor(position.Y / size + 0.5) * size
	local z = math.floor(position.Z / size + 0.5) * size
	return Vector3.new(x, y, z)
end

findSurfacePositionAndNormal = function()
	if not mouse then return nil, nil, nil end
	local camera = workspace.CurrentCamera
	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { previewFolder, getWorkspaceContainer(), densityPreviewFolder, pathPreviewFolder, cablePreviewFolder }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000, params)
	if result then
		if surfaceAngleMode == "Floor" and result.Normal.Y < 0.7 then return nil, nil, nil
		elseif surfaceAngleMode == "Wall" and math.abs(result.Normal.Y) > 0.3 then return nil, nil, nil end
		return result.Position, result.Normal, result.Instance
	end
	return nil, nil, nil
end

paintTerrainUnderAsset = function(asset, materialName)
	local material = Enum.Material[materialName]
	if not material then return end
	local size, position
	if asset:IsA("Model") and asset.PrimaryPart then
		size = asset:GetExtentsSize()
		position = asset.PrimaryPart.Position
	elseif asset:IsA("BasePart") then
		size = asset.Size
		position = asset.Position
	else return end
	local paintRadius = math.max(size.X, size.Z) / 2 + 2
	local paintPosition = position
	local regionMin = Vector3.new(paintPosition.X - paintRadius, -50, paintPosition.Z - paintRadius)
	local regionMax = Vector3.new(paintPosition.X + paintRadius, 50, paintPosition.Z + paintRadius)
	local region = Region3.new(regionMin, regionMax):ExpandToGrid(4)
	local terrainData = workspace.Terrain:CopyRegion(region)
	table.insert(terrainUndoStack, { Region = region, Data = terrainData })
	workspace.Terrain:FillBall(CFrame.new(paintPosition), paintRadius, material)
end

anchorPhysicsGroup = function(group, parentFolder)
	task.spawn(function()
		task.wait(physicsSettleTime)
		for _, model in ipairs(group) do
			if model and model.Parent then
				model.Parent = parentFolder
				for _, desc in ipairs(model:GetDescendants()) do
					if desc:IsA("BasePart") then desc.Anchored = true end
				end
			end
		end
	end)
end

placeAsset = function(assetToClone, position, normal)
	local smin = parseNumber(C.scaleMinBox[1].Text, 0.8)
	local smax = parseNumber(C.scaleMaxBox[1].Text, 1.2)
	if smin <= 0 then smin = 0.1 end; if smax < smin then smax = smin end

	local clone = assetToClone:Clone()
	randomizeProperties(clone)
	if clone:IsA("Model") and not clone.PrimaryPart then
		for _, v in ipairs(clone:GetDescendants()) do if v:IsA("BasePart") then clone.PrimaryPart = v; break end end
	end
	local s = randFloat(smin, smax)
	local xrot, yrot, zrot
	local effectiveNormal = normal or Vector3.new(0, 1, 0)

	if normal and surfaceAngleMode == "Floor" then
		xrot = 0; zrot = 0; yrot = math.rad(math.random() * 360); effectiveNormal = Vector3.new(0, 1, 0)
	else
		local rotXMin = math.rad(parseNumber(C.rotXMinBox[1].Text, 0))
		local rotXMax = math.rad(parseNumber(C.rotXMaxBox[1].Text, 0))
		local rotZMin = math.rad(parseNumber(C.rotZMinBox[1].Text, 0))
		local rotZMax = math.rad(parseNumber(C.rotZMaxBox[1].Text, 0))
		xrot = randFloat(rotXMin, rotXMax); yrot = math.rad(math.random() * 360); zrot = randFloat(rotZMin, rotZMax)
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
			local shiftY_vector = effectiveNormal * ((position.Y - currentBottomY_inWorld) + customOffset)
			finalPosition = clone:GetPrimaryPartCFrame().Position + shiftY_vector
		else
			finalPosition = clone:GetPrimaryPartCFrame().Position + (effectiveNormal * customOffset)
		end
		if snapToGridEnabled then finalPosition = snapPositionToGrid(finalPosition, gridSize) end

		local finalCFrame
		local forceAlign = (surfaceAngleMode == "Wall")
		if (forceAlign or (shouldAlign and surfaceAngleMode == "Off")) and normal then
			local rotatedCFrame = CFrame.new() * randomRotation
			local look = rotatedCFrame.LookVector
			local rightVec = look:Cross(effectiveNormal).Unit
			local lookActual = effectiveNormal:Cross(rightVec).Unit
			if rightVec.Magnitude < 0.9 then
				look = rotatedCFrame.RightVector; rightVec = look:Cross(effectiveNormal).Unit; lookActual = effectiveNormal:Cross(rightVec).Unit
			end
			finalCFrame = CFrame.fromMatrix(finalPosition, rightVec, effectiveNormal, -lookActual)
		else
			finalCFrame = CFrame.new(finalPosition) * randomRotation
		end
		clone:SetPrimaryPartCFrame(finalCFrame)
	elseif clone:IsA("BasePart") then
		clone.Size = clone.Size * s
		local finalYOffset = (clone.Size.Y / 2) + customOffset
		local finalPos = position + (effectiveNormal * finalYOffset)
		if snapToGridEnabled then finalPos = snapPositionToGrid(finalPos, gridSize) end
		local finalCFrame
		local forceAlign = (surfaceAngleMode == "Wall")
		if (forceAlign or (shouldAlign and surfaceAngleMode == "Off")) and normal then
			local rotatedCFrame = CFrame.new() * randomRotation
			local look = rotatedCFrame.LookVector
			local rightVec = look:Cross(effectiveNormal).Unit
			local lookActual = effectiveNormal:Cross(rightVec).Unit
			if rightVec.Magnitude < 0.9 then
				look = rotatedCFrame.RightVector; rightVec = look:Cross(effectiveNormal).Unit; lookActual = effectiveNormal:Cross(rightVec).Unit
			end
			finalCFrame = CFrame.fromMatrix(finalPos, rightVec, effectiveNormal, -lookActual)
		else
			finalCFrame = CFrame.new(finalPos) * randomRotation
		end
		clone.CFrame = finalCFrame
	end

	if physicsModeEnabled and currentMode == "Paint" then
		clone.Parent = getWorkspaceContainer()
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") then desc.Anchored = false; desc.CanCollide = true end
		end
		clone:TranslateBy(Vector3.new(0, 2, 0))
	end
	if autoTerrainPaint then
		local terrainMaterial = assetOffsets[assetName .. "_terrainMaterial"]
		if terrainMaterial then paintTerrainUnderAsset(clone, terrainMaterial) end
	end
	return clone
end

paintAt = function(center, surfaceNormal)
	local radius = math.max(0.1, parseNumber(C.radiusBox[1].Text, 10))
	local density = math.max(1, math.floor(parseNumber(C.densityBox[1].Text, 10)))
	local spacing = math.max(0.1, parseNumber(C.spacingBox[1].Text, 1.0))

	if avoidOverlap then
		local unitRay = workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new(); params.FilterDescendantsInstances = { previewFolder }; params.FilterType = Enum.RaycastFilterType.Exclude
		local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000, params)
		if result and result.Instance:IsDescendantOf(getWorkspaceContainer()) then return end
	end

	ChangeHistoryService:SetWaypoint("Brush - Before Paint")
	local container = getWorkspaceContainer()
	local groupFolder = Instance.new("Folder")
	groupFolder.Name = "BrushGroup_" .. tostring(math.floor(os.time()))
	groupFolder.Parent = container
	local placed = {}
	local allAssets = assetsFolder:GetChildren()
	local activeAssets = {}
	for _, asset in ipairs(allAssets) do
		local isActive = assetOffsets[asset.Name .. "_active"]
		if isActive == nil then isActive = true end
		if isActive then table.insert(activeAssets, asset) end
	end
	if #activeAssets == 0 then groupFolder:Destroy(); return end

	local up = surfaceNormal
	local look = Vector3.new(1, 0, 0)
	if math.abs(up:Dot(look)) > 0.99 then look = Vector3.new(0, 0, 1) end
	local right = look:Cross(up).Unit
	local look_actual = up:Cross(right).Unit
	local planeCFrame = CFrame.fromMatrix(center, right, up, -look_actual)
	local physicsGroup = {}

	for i = 1, density do
		local assetToClone = getRandomWeightedAsset(activeAssets)
		if not assetToClone then break end
		local found = false; local candidatePos = nil; local candidateNormal = surfaceNormal; local attempts = 0
		while not found and attempts < 12 do
			attempts = attempts + 1
			local offset2D = randomPointInCircle(radius)
			local spawnPos = planeCFrame:PointToWorldSpace(Vector3.new(offset2D.X, 0, offset2D.Z))
			local rayOrigin = spawnPos + surfaceNormal * 5; local rayDir = -surfaceNormal * 10
			local params = RaycastParams.new()
			params.FilterDescendantsInstances = { previewFolder, container }; params.FilterType = Enum.RaycastFilterType.Exclude
			local result = workspace:Raycast(rayOrigin, rayDir, params)
			if result and result.Instance then
				local isValidTarget = true
				if maskingMode ~= "Off" and maskingValue then
					local targetPart = result.Instance
					if maskingMode == "Material" then isValidTarget = (targetPart.Material == maskingValue)
					elseif maskingMode == "Color" then isValidTarget = (targetPart.Color == maskingValue)
					elseif maskingMode == "Tag" then isValidTarget = CollectionService:HasTag(targetPart, maskingValue) end
				end
				if isValidTarget then
					local posOnSurface = result.Position
					local ok = true
					for _, p in ipairs(placed) do if (p - posOnSurface).Magnitude < spacing then ok = false; break end end
					if ok then found = true; candidatePos = posOnSurface; candidateNormal = result.Normal end
				end
			end
		end
		if candidatePos then
			local placedAsset = placeAsset(assetToClone, candidatePos, candidateNormal)
			if not physicsModeEnabled or currentMode ~= "Paint" then placedAsset.Parent = groupFolder else table.insert(physicsGroup, placedAsset) end
			table.insert(placed, candidatePos)
		end
	end
	if physicsModeEnabled and currentMode == "Paint" and #physicsGroup > 0 then anchorPhysicsGroup(physicsGroup, groupFolder) end
	if #groupFolder:GetChildren() == 0 then groupFolder:Destroy() end
	ChangeHistoryService:SetWaypoint("Brush - After Paint")
end

updateDensityPreview = function(center, surfaceNormal)
	densityPreviewFolder:ClearAllChildren()
	if not center or not surfaceNormal or currentMode ~= "Paint" or not densityPreviewEnabled then return end

	local radius = math.max(0.1, parseNumber(C.radiusBox[1].Text, 10))
	local density = math.max(1, math.floor(parseNumber(C.densityBox[1].Text, 10)))
	local spacing = math.max(0.1, parseNumber(C.spacingBox[1].Text, 1.0))

	local up = surfaceNormal
	local look = Vector3.new(1, 0, 0)
	if math.abs(up:Dot(look)) > 0.99 then look = Vector3.new(0, 0, 1) end
	local right = look:Cross(up).Unit
	local look_actual = up:Cross(right).Unit
	local planeCFrame = CFrame.fromMatrix(center, right, up, -look_actual)
	local placed = {}
	local container = getWorkspaceContainer()

	for i = 1, density do
		local found = false; local candidatePos = nil; local attempts = 0
		while not found and attempts < 12 do
			attempts = attempts + 1
			local offset2D = randomPointInCircle(radius)
			local spawnPos = planeCFrame:PointToWorldSpace(Vector3.new(offset2D.X, 0, offset2D.Z))
			local rayOrigin = spawnPos + surfaceNormal * 5; local rayDir = -surfaceNormal * 10
			local params = RaycastParams.new()
			params.FilterDescendantsInstances = { previewFolder, container, densityPreviewFolder }; params.FilterType = Enum.RaycastFilterType.Exclude
			local result = workspace:Raycast(rayOrigin, rayDir, params)
			if result and result.Instance then
				local isValidTarget = true
				if maskingMode ~= "Off" and maskingValue then
					local targetPart = result.Instance
					if maskingMode == "Material" then isValidTarget = (targetPart.Material == maskingValue)
					elseif maskingMode == "Color" then isValidTarget = (targetPart.Color == maskingValue)
					elseif maskingMode == "Tag" then isValidTarget = CollectionService:HasTag(targetPart, maskingValue) end
				end
				if isValidTarget then
					local posOnSurface = result.Position
					local ok = true
					for _, p in ipairs(placed) do if (p - posOnSurface).Magnitude < spacing then ok = false; break end end
					if ok then found = true; candidatePos = posOnSurface end
				end
			end
		end
		if candidatePos then
			local m = Instance.new("Part")
			m.Shape = Enum.PartType.Ball; m.Size = Vector3.new(0.5,0.5,0.5); m.Anchored = true; m.CanCollide = false
			m.Color = Theme.Warning; m.Material = Enum.Material.Neon; m.Transparency = 0.4
			m.Position = candidatePos; m.Parent = densityPreviewFolder
			table.insert(placed, candidatePos)
		end
	end
end

paintInVolume = function(center)
	local radius = math.max(0.1, parseNumber(C.radiusBox[1].Text, 10))
	local density = math.max(1, math.floor(parseNumber(C.densityBox[1].Text, 10)))
	ChangeHistoryService:SetWaypoint("Brush - Before VolumePaint")
	local container = getWorkspaceContainer()
	local groupFolder = Instance.new("Folder"); groupFolder.Name = "BrushVolume_" .. tostring(math.floor(os.time())); groupFolder.Parent = container
	local allAssets = assetsFolder:GetChildren()
	local activeAssets = {}
	for _, asset in ipairs(allAssets) do
		local isActive = assetOffsets[asset.Name .. "_active"]
		if isActive == nil then isActive = true end
		if isActive then table.insert(activeAssets, asset) end
	end
	if #activeAssets == 0 then groupFolder:Destroy(); return end
	for i = 1, density do
		local assetToPlace = getRandomWeightedAsset(activeAssets)
		if assetToPlace then
			local randomPoint = center + getRandomPointInSphere(radius)
			local placedAsset = placeAsset(assetToPlace, randomPoint, nil)
			if placedAsset then placedAsset.Parent = groupFolder end
		end
	end
	if #groupFolder:GetChildren() == 0 then groupFolder:Destroy() end
	ChangeHistoryService:SetWaypoint("Brush - After VolumePaint")
end

stampAt = function(center, surfaceNormal)
	ChangeHistoryService:SetWaypoint("Brush - Before Stamp")
	local container = getWorkspaceContainer()
	local groupFolder = Instance.new("Folder"); groupFolder.Name = "BrushStamp_" .. tostring(math.floor(os.time())); groupFolder.Parent = container
	local allAssets = assetsFolder:GetChildren()
	local activeAssets = {}
	for _, asset in ipairs(allAssets) do
		local isActive = assetOffsets[asset.Name .. "_active"]
		if isActive == nil then isActive = true end
		if isActive then table.insert(activeAssets, asset) end
	end
	if #activeAssets == 0 then groupFolder:Destroy(); return end
	local assetToPlace = getRandomWeightedAsset(activeAssets)
	if assetToPlace then
		local placedAsset = placeAsset(assetToPlace, center, surfaceNormal)
		if placedAsset then placedAsset.Parent = groupFolder end
	end
	if #groupFolder:GetChildren() == 0 then groupFolder:Destroy() end
	ChangeHistoryService:SetWaypoint("Brush - After Stamp")
end

eraseAt = function(center)
	local radius = math.max(0.1, parseNumber(C.radiusBox[1].Text, 10))
	local container = workspace:FindFirstChild(WORKSPACE_FOLDER_NAME)
	if not container then return end
	local itemsToDestroy = {}
	local allChildren = container:GetDescendants()
	for _, child in ipairs(allChildren) do
		if child:IsA("BasePart") or child:IsA("Model") then
			local part = child
			if child:IsA("Model") then part = child.PrimaryPart end
			if part and part.Parent and (part.Position - center).Magnitude <= radius then
				local ancestorToDestroy = child
				while ancestorToDestroy and ancestorToDestroy.Parent ~= container and ancestorToDestroy.Parent ~= workspace do ancestorToDestroy = ancestorToDestroy.Parent end
				if ancestorToDestroy and ancestorToDestroy.Parent == container then
					local filterActive = next(eraseFilter) ~= nil
					if not filterActive or eraseFilter[ancestorToDestroy.Name] then itemsToDestroy[ancestorToDestroy] = true end
				end
			end
		end
	end
	if next(itemsToDestroy) ~= nil then
		ChangeHistoryService:SetWaypoint("Brush - Before Erase")
		for item, _ in pairs(itemsToDestroy) do item:Destroy() end
		if #container:GetChildren() == 0 then container:Destroy() end
		ChangeHistoryService:SetWaypoint("Brush - After Erase")
	end
end

fillArea = function(part)
	if not part then return end
	local density = math.max(1, math.floor(parseNumber(C.densityBox[1].Text, 10)))
	local spacing = math.max(0.1, parseNumber(C.spacingBox[1].Text, 1.0))
	local allAssets = assetsFolder:GetChildren()
	local activeAssets = {}
	for _, asset in ipairs(allAssets) do
		local isActive = assetOffsets[asset.Name .. "_active"]
		if isActive == nil then isActive = true end
		if isActive then table.insert(activeAssets, asset) end
	end
	if #activeAssets == 0 then return end
	ChangeHistoryService:SetWaypoint("Brush - Before Fill")
	local container = getWorkspaceContainer()
	local groupFolder = Instance.new("Folder"); groupFolder.Name = "BrushFill_" .. tostring(math.floor(os.time())); groupFolder.Parent = container
	local placedPoints = {}
	local partCF = part.CFrame; local partSize = part.Size
	for i = 1, density do
		local assetToPlace = getRandomWeightedAsset(activeAssets)
		local foundPoint = false; local attempts = 0
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
			params.FilterDescendantsInstances = {part}
			local result = workspace:Raycast(rayOrigin, rayDir, params)
			if result then
				local isSpaced = true
				for _, p in ipairs(placedPoints) do if (result.Position - p).Magnitude < spacing then isSpaced = false; break end end
				if isSpaced then
					local placedAsset = placeAsset(assetToPlace, result.Position, result.Normal)
					if placedAsset then placedAsset.Parent = groupFolder; table.insert(placedPoints, result.Position) end
					foundPoint = true
				end
			end
		end
	end
	if #groupFolder:GetChildren() == 0 then groupFolder:Destroy() end
	ChangeHistoryService:SetWaypoint("Brush - After Fill")
end

replaceAt = function(center)
	if not sourceAsset or not targetAsset then return end
	local radius = math.max(0.1, parseNumber(C.radiusBox[1].Text, 10))
	local container = workspace:FindFirstChild(WORKSPACE_FOLDER_NAME)
	if not container then return end
	local sourceModel = assetsFolder:FindFirstChild(sourceAsset)
	local targetModel = assetsFolder:FindFirstChild(targetAsset)
	if not sourceModel or not targetModel then return end
	local itemsToReplace = {}
	local allPartsInRadius = workspace:GetPartBoundsInRadius(center, radius)
	for _, part in ipairs(allPartsInRadius) do
		if part:IsDescendantOf(container) then
			local ancestorToReplace = part
			while ancestorToReplace and ancestorToReplace.Parent ~= container do ancestorToReplace = ancestorToReplace.Parent end
			if ancestorToReplace and ancestorToReplace.Name == sourceAsset then itemsToReplace[ancestorToReplace] = true end
		end
	end
	if next(itemsToReplace) ~= nil then
		ChangeHistoryService:SetWaypoint("Brush - Before Replace")
		local groupFolder = Instance.new("Folder"); groupFolder.Name = "BrushReplace_" .. tostring(math.floor(os.time())); groupFolder.Parent = container
		for item, _ in pairs(itemsToReplace) do
			local oldCFrame, oldSize
			if item:IsA("Model") and item.PrimaryPart then oldCFrame = item.PrimaryPart.CFrame; oldSize = item:GetExtentsSize()
			elseif item:IsA("BasePart") then oldCFrame = item.CFrame; oldSize = item.Size end
			if oldCFrame and oldSize then
				item:Destroy()
				local newAsset = targetModel:Clone()
				if newAsset:IsA("Model") and newAsset.PrimaryPart then
					local _, newSize = newAsset:GetBoundingBox()
					local scaleFactor = oldSize.Magnitude / newSize.Magnitude
					scaleModel(newAsset, scaleFactor)
					newAsset:SetPrimaryPartCFrame(oldCFrame)
				elseif newAsset:IsA("BasePart") then
					newAsset.Size = oldSize; newAsset.CFrame = oldCFrame
				end
				newAsset.Parent = groupFolder
			end
		end
		if #groupFolder:GetChildren() == 0 then groupFolder:Destroy() end
		ChangeHistoryService:SetWaypoint("Brush - After Replace")
	end
end

paintAlongPath = function()
	if #pathPoints < 2 then return end
	ChangeHistoryService:SetWaypoint("Brush - Before Path Paint")
	local container = getWorkspaceContainer()
	local groupFolder = Instance.new("Folder"); groupFolder.Name = "BrushPath_" .. tostring(math.floor(os.time())); groupFolder.Parent = container
	local allAssets = assetsFolder:GetChildren()
	local activeAssets = {}
	for _, asset in ipairs(allAssets) do
		local isActive = assetOffsets[asset.Name .. "_active"]
		if isActive == nil then isActive = true end
		if isActive then table.insert(activeAssets, asset) end
	end
	if #activeAssets == 0 then groupFolder:Destroy(); clearPath(); return end
	local spacing = math.max(0.1, parseNumber(C.spacingBox[1].Text, 1.0))
	local distanceSinceLastPaint = 0
	local pointsToDraw = pathPoints
	if pathCloseLoop and #pointsToDraw > 2 then pointsToDraw = {pointsToDraw[#pointsToDraw], unpack(pointsToDraw), pointsToDraw[1], pointsToDraw[2]} end
	for i = 1, #pointsToDraw - 1 do
		local p1 = pointsToDraw[i]; local p2 = pointsToDraw[i+1]
		local p0 = pointsToDraw[i-1] or (p1 + (p1 - p2)); local p3 = pointsToDraw[i+2] or (p2 + (p2 - p1))
		local lastPoint = p1
		local segments = 100
		for t_step = 1, segments do
			local t = t_step / segments
			local pointOnCurve = catmullRom(p0, p1, p2, p3, t)
			local segmentLength = (pointOnCurve - lastPoint).Magnitude
			distanceSinceLastPaint = distanceSinceLastPaint + segmentLength
			if distanceSinceLastPaint >= spacing then
				local assetToPlace = getRandomWeightedAsset(activeAssets)
				local rayOrigin = pointOnCurve + Vector3.new(0, 10, 0); local rayDir = Vector3.new(0, -20, 0)
				local params = RaycastParams.new()
				params.FilterDescendantsInstances = { previewFolder, container, pathPreviewFolder }; params.FilterType = Enum.RaycastFilterType.Exclude
				local result = workspace:Raycast(rayOrigin, rayDir, params)
				if result then
					local placedAsset = placeAsset(assetToPlace, result.Position, result.Normal)
					if placedAsset and pathFollowPath then
						local tangent = (catmullRom(p0, p1, p2, p3, t + 0.01) - pointOnCurve).Unit
						local upVector = result.Normal
						local rightVector = tangent:Cross(upVector).Unit
						if rightVector.Magnitude < 0.9 then rightVector = (tangent + Vector3.new(0.1, 0, 0.1)):Cross(upVector).Unit end
						local lookVector = upVector:Cross(rightVector).Unit
						local pathRotation = CFrame.fromMatrix(Vector3.new(), rightVector, upVector, -lookVector)
						if placedAsset:IsA("Model") and placedAsset.PrimaryPart then
							local pos = placedAsset:GetPrimaryPartCFrame().Position
							local _, rotX, _, _, rotZ, _ = (placedAsset:GetPrimaryPartCFrame() - pos):ToEulerAnglesXYZ()
							placedAsset:SetPrimaryPartCFrame(CFrame.new(pos) * pathRotation * CFrame.Angles(rotX, 0, rotZ))
						elseif placedAsset:IsA("BasePart") then
							local pos = placedAsset.CFrame.Position
							local _, rotX, _, _, rotZ, _ = (placedAsset.CFrame - pos):ToEulerAnglesXYZ()
							placedAsset.CFrame = CFrame.new(pos) * pathRotation * CFrame.Angles(rotX, 0, rotZ)
						end
					end
					if placedAsset then placedAsset.Parent = groupFolder end
				end
				distanceSinceLastPaint = 0
			end
			lastPoint = pointOnCurve
		end
	end
	if #groupFolder:GetChildren() == 0 then groupFolder:Destroy() end
	ChangeHistoryService:SetWaypoint("Brush - After Path Paint")
	clearPath()
end

clearPath = function() pathPoints = {}; pathPreviewFolder:ClearAllChildren() end
updatePathPreview = function()
	pathPreviewFolder:ClearAllChildren()
	for _, point in ipairs(pathPoints) do
		local marker = Instance.new("Part")
		marker.Shape = Enum.PartType.Ball; marker.Size = Vector3.new(0.8, 0.8, 0.8)
		marker.Anchored = true; marker.CanCollide = false; marker.Color = Theme.Accent; marker.Material = Enum.Material.Neon
		marker.Position = point; marker.Parent = pathPreviewFolder
	end
	local pointsToDraw = pathPoints
	if pathCloseLoop and #pointsToDraw > 2 then pointsToDraw = {pointsToDraw[#pointsToDraw], unpack(pointsToDraw), pointsToDraw[1], pointsToDraw[2]} end
	if #pointsToDraw < 2 then return end
	local segments = 20
	for i = 1, #pointsToDraw - 1 do
		local p1 = pointsToDraw[i]; local p2 = pointsToDraw[i+1]
		local p0 = pointsToDraw[i-1] or (p1 + (p1 - p2)); local p3 = pointsToDraw[i+2] or (p2 + (p2 - p1))
		local lastPoint = p1
		for t_step = 1, segments do
			local t = t_step / segments
			local pointOnCurve = catmullRom(p0, p1, p2, p3, t)
			local part = Instance.new("Part")
			part.Anchored = true; part.CanCollide = false; part.Size = Vector3.new(0.4, 0.4, (pointOnCurve - lastPoint).Magnitude)
			part.CFrame = CFrame.new(lastPoint, pointOnCurve) * CFrame.new(0, 0, -(pointOnCurve-lastPoint).Magnitude / 2)
			part.Color = Theme.Accent; part.Material = Enum.Material.Neon; part.Parent = pathPreviewFolder
			lastPoint = pointOnCurve
		end
	end
end

calculateCatenary = function(p1, p2, sag, segments)
	local points = {}; local halfDist = (p1 - p2).Magnitude / 2
	if halfDist < 0.01 then return {p1, p2} end
	local a = sag / (halfDist * halfDist)
	for i = 0, segments do
		local t = i / segments; local x = (t - 0.5) * (halfDist * 2); local y = a * x * x
		local fraction = (p2 - p1) * t; local point = p1 + fraction + Vector3.new(0, -y, 0)
		table.insert(points, point)
	end
	return points
end

createCable = function(startPos, endPos)
	ChangeHistoryService:SetWaypoint("Brush - Before Cable")
	local container = getWorkspaceContainer()
	local groupFolder = Instance.new("Folder"); groupFolder.Name = "BrushCable_" .. tostring(math.floor(os.time())); groupFolder.Parent = container
	local sag = math.max(0, parseNumber(C.cableSagBox[1].Text, 5))
	local segments = math.max(2, math.floor(parseNumber(C.cableSegmentsBox[1].Text, 10)))
	local thickness = math.max(0.1, parseNumber(C.cableThicknessBox[1].Text, 0.2))
	local points = calculateCatenary(startPos, endPos, sag, segments)
	for i = 1, #points - 1 do
		local p1 = points[i]; local p2 = points[i+1]; local mag = (p2 - p1).Magnitude
		local part = Instance.new("Part"); part.Shape = Enum.PartType.Cylinder; part.Size = Vector3.new(mag, thickness, thickness)
		part.CFrame = CFrame.new(p1, p2) * CFrame.Angles(0, math.rad(90), 0) * CFrame.new(mag / 2, 0, 0)
		part.Anchored = true; part.CanCollide = true; part.Material = cableMaterial; part.Color = cableColor; part.Parent = groupFolder
	end
	ChangeHistoryService:SetWaypoint("Brush - After Cable")
	clearCable()
end
clearCable = function() cableStartPoint = nil; if cablePreviewFolder then cablePreviewFolder:ClearAllChildren() end end
updateCablePreview = function(startPos, endPos)
	if not cablePreviewFolder then return end
	cablePreviewFolder:ClearAllChildren()
	local sag = math.max(0, parseNumber(C.cableSagBox[1].Text, 5))
	local segments = math.max(2, math.floor(parseNumber(C.cableSegmentsBox[1].Text, 10)))
	local thickness = math.max(0.1, parseNumber(C.cableThicknessBox[1].Text, 0.2))
	local points = calculateCatenary(startPos, endPos, sag, segments)
	for i = 1, #points - 1 do
		local p1 = points[i]; local p2 = points[i+1]; local mag = (p2 - p1).Magnitude
		local part = Instance.new("Part"); part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(mag, thickness, thickness)
		part.CFrame = CFrame.new(p1, p2) * CFrame.Angles(0, math.rad(90), 0) * CFrame.new(mag / 2, 0, 0)
		part.Anchored = true; part.CanCollide = false; part.Material = cableMaterial; part.Color = cableColor; part.Transparency = 0.5; part.Parent = cablePreviewFolder
	end
end

createBuilderStructure = function(startPos, endPos)
	if not builderPostAsset or not builderSegmentAsset then return end
	ChangeHistoryService:SetWaypoint("Brush - Before Build")
	local container = getWorkspaceContainer()
	local groupFolder = Instance.new("Folder"); groupFolder.Name = "BrushBuild_" .. tostring(math.floor(os.time())); groupFolder.Parent = container
	local distance = parseNumber(C.builderDistanceBox[1].Text, 8)
	if distance <= 0 then distance = 8 end
	local heightOffset = parseNumber(C.builderHeightBox[1].Text, 0.2)
	local stretch = (C.builderStretchToggle[1].Text == "Stretch Segment")
	local lineVector = endPos - startPos; local lineLength = lineVector.Magnitude
	local numPosts = math.floor(lineLength / distance) + 1
	for i = 0, numPosts - 1 do
		local t = i / (numPosts - 1); if numPosts == 1 then t = 0 end
		local pointOnLine = startPos + lineVector * t
		local rayOrigin = pointOnLine + Vector3.new(0, 10, 0); local rayDir = Vector3.new(0, -20, 0)
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { previewFolder, container, builderPreviewFolder }; params.FilterType = Enum.RaycastFilterType.Exclude
		local result = workspace:Raycast(rayOrigin, rayDir, params)
		if result then
			local groundPos = result.Position + result.Normal * heightOffset
			local postClone = builderPostAsset:Clone()
			local upVector = result.Normal; local rightVector = lineVector.Unit
			local lookVector = upVector:Cross(rightVector).Unit; rightVector = lookVector:Cross(upVector).Unit
			postClone:SetPrimaryPartCFrame(CFrame.fromMatrix(groundPos, rightVector, upVector, -lookVector))
			postClone.Parent = groupFolder
			if i < numPosts -1 then
				local next_t = (i + 1) / (numPosts - 1)
				local nextPointOnLine = startPos + lineVector * next_t
				local nextRayOrigin = nextPointOnLine + Vector3.new(0, 10, 0)
				local nextResult = workspace:Raycast(nextRayOrigin, rayDir, params)
				if nextResult then
					local nextGroundPos = nextResult.Position + nextResult.Normal * heightOffset
					local segmentClone = builderSegmentAsset:Clone()
					local segmentStartPos = postClone:GetPrimaryPartCFrame().Position
					local segmentEndPos = nextGroundPos
					local segmentDistance = (segmentEndPos - segmentStartPos).Magnitude
					local segmentCFrame = CFrame.new(segmentStartPos, segmentEndPos) * CFrame.new(0, 0, -segmentDistance / 2)
					segmentClone:SetPrimaryPartCFrame(segmentCFrame)
					if stretch then
						local size = segmentClone:GetExtentsSize()
						if size.Z > 0.01 then scaleModel(segmentClone, segmentDistance / size.Z) end
					end
					segmentClone.Parent = groupFolder
				end
			end
		end
	end
	if #groupFolder:GetChildren() == 0 then groupFolder:Destroy() end
	ChangeHistoryService:SetWaypoint("Brush - After Build")
end

updateBuilderPreview = function(startPos, endPos)
	builderPreviewFolder:ClearAllChildren()
	if not builderPostAsset or not builderSegmentAsset then return end
	local distance = parseNumber(C.builderDistanceBox[1].Text, 8)
	if distance <= 0 then distance = 8 end
	local heightOffset = parseNumber(C.builderHeightBox[1].Text, 0.2)
	local stretch = (C.builderStretchToggle[1].Text == "Stretch Segment")
	local lineVector = endPos - startPos; local lineLength = lineVector.Magnitude
	local numPosts = math.floor(lineLength / distance) + 1
	for i = 0, numPosts - 1 do
		local t = i / (numPosts - 1); if numPosts == 1 then t = 0 end
		local pointOnLine = startPos + lineVector * t
		local rayOrigin = pointOnLine + Vector3.new(0, 10, 0); local rayDir = Vector3.new(0, -20, 0)
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { previewFolder, getWorkspaceContainer(), builderPreviewFolder }; params.FilterType = Enum.RaycastFilterType.Exclude
		local result = workspace:Raycast(rayOrigin, rayDir, params)
		if result then
			local groundPos = result.Position + result.Normal * heightOffset
			local postClone = builderPostAsset:Clone()
			for _, d in ipairs(postClone:GetDescendants()) do if d:IsA("BasePart") then d.Transparency = 0.7; d.CanCollide = false end end
			local upVector = result.Normal; local rightVector = lineVector.Unit
			local lookVector = upVector:Cross(rightVector).Unit; rightVector = lookVector:Cross(upVector).Unit
			postClone:SetPrimaryPartCFrame(CFrame.fromMatrix(groundPos, rightVector, upVector, -lookVector))
			postClone.Parent = builderPreviewFolder
			if i < numPosts - 1 then
				local next_t = (i + 1) / (numPosts - 1)
				local nextPointOnLine = startPos + lineVector * next_t
				local nextRayOrigin = nextPointOnLine + Vector3.new(0, 10, 0)
				local nextResult = workspace:Raycast(nextRayOrigin, rayDir, params)
				if nextResult then
					local nextGroundPos = nextResult.Position + nextResult.Normal * heightOffset
					local segmentClone = builderSegmentAsset:Clone()
					for _, d in ipairs(segmentClone:GetDescendants()) do if d:IsA("BasePart") then d.Transparency = 0.7; d.CanCollide = false end end
					local segmentStartPos = postClone:GetPrimaryPartCFrame().Position
					local segmentEndPos = nextGroundPos
					local segmentDistance = (segmentEndPos - segmentStartPos).Magnitude
					local segmentCFrame = CFrame.new(segmentStartPos, segmentEndPos) * CFrame.new(0, 0, -segmentDistance / 2)
					segmentClone:SetPrimaryPartCFrame(segmentCFrame)
					if stretch then
						local size = segmentClone:GetExtentsSize()
						scaleModel(segmentClone, segmentDistance / size.Z)
					end
					segmentClone.Parent = builderPreviewFolder
				end
			end
		end
	end
end

updatePreview = function()
	if not mouse or not previewPart then return end
	if currentMode == "Line" and lineStartPoint then previewPart.Parent = nil
	elseif currentMode == "Volume" then
		previewPart.Parent = previewFolder
		local radius = math.max(0.1, parseNumber(C.radiusBox[1].Text, 10))
		local unitRay = workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y)
		local positionInSpace = unitRay.Origin + unitRay.Direction * 100
		previewPart.Shape = Enum.PartType.Ball
		previewPart.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
		previewPart.CFrame = CFrame.new(positionInSpace)
		previewPart.Color = Color3.fromRGB(150, 150, 255)
		cyl.Parent = nil
	else
		if currentMode == "Paint" or currentMode == "Line" then previewPart.Color = Color3.fromRGB(80, 255, 80)
		elseif currentMode == "Replace" then previewPart.Color = Color3.fromRGB(80, 180, 255)
		else previewPart.Color = Color3.fromRGB(255, 80, 80) end
		previewPart.Shape = Enum.PartType.Cylinder
		local radius = math.max(0.1, parseNumber(C.radiusBox[1].Text, 10))
		local surfacePos, normal = findSurfacePositionAndNormal()
		if not surfacePos or not normal or currentMode == "Line" or currentMode == "Cable" then
			previewPart.Parent = nil
		else
			previewPart.Parent = previewFolder
			local pos = surfacePos
			local look = Vector3.new(1, 0, 0)
			if math.abs(look:Dot(normal)) > 0.99 then look = Vector3.new(0, 0, 1) end
			local right = look:Cross(normal).Unit
			local lookActual = normal:Cross(right).Unit
			previewPart.CFrame = CFrame.fromMatrix(pos + normal * 0.05, normal, right, lookActual)
			previewPart.Size = Vector3.new(0.02, radius*2, radius*2)
			updateDensityPreview(pos, normal)
		end
	end
	if currentMode == "Line" and lineStartPoint and linePreviewPart then
		local endPoint, _ = findSurfacePositionAndNormal()
		if endPoint then
			linePreviewPart.Parent = previewFolder
			local mag = (endPoint - lineStartPoint).Magnitude
			linePreviewPart.Size = Vector3.new(0.2, 0.2, mag)
			linePreviewPart.CFrame = CFrame.new(lineStartPoint, endPoint) * CFrame.new(0, 0, -mag/2)
		else linePreviewPart.Parent = nil end
	elseif linePreviewPart then linePreviewPart.Parent = nil end
	if currentMode == "Cable" and cableStartPoint then
		local endPoint, _ = findSurfacePositionAndNormal()
		if endPoint then updateCablePreview(cableStartPoint, endPoint) end
	elseif cablePreviewFolder then clearCable() end
end

local function paintAlongLine(startPos, endPos)
	local spacing = math.max(0.1, parseNumber(C.spacingBox[1].Text, 1.0))
	local lineVector = endPos - startPos; local lineLength = lineVector.Magnitude
	if lineLength < spacing then return end
	ChangeHistoryService:SetWaypoint("Brush - Before Line")
	local container = getWorkspaceContainer()
	local groupFolder = Instance.new("Folder"); groupFolder.Name = "BrushLine_" .. tostring(math.floor(os.time())); groupFolder.Parent = container
	local allAssets = assetsFolder:GetChildren()
	local activeAssets = {}
	for _, asset in ipairs(allAssets) do
		local isActive = assetOffsets[asset.Name .. "_active"]
		if isActive == nil then isActive = true end
		if isActive then table.insert(activeAssets, asset) end
	end
	if #activeAssets == 0 then groupFolder:Destroy(); return end
	local numSteps = math.floor(lineLength / spacing)
	for i = 0, numSteps do
		local t = i / numSteps
		local pointOnLine = startPos + lineVector * t
		local rayOrigin = pointOnLine + Vector3.new(0, 10, 0); local rayDir = Vector3.new(0, -20, 0)
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { previewFolder, container }; params.FilterType = Enum.RaycastFilterType.Exclude
		local result = workspace:Raycast(rayOrigin, rayDir, params)
		if result then
			local skip = false
			if surfaceAngleMode == "Floor" and result.Normal.Y < 0.7 then skip = true
			elseif surfaceAngleMode == "Wall" and math.abs(result.Normal.Y) > 0.3 then skip = true end
			if not skip then
				local assetToPlace = getRandomWeightedAsset(activeAssets)
				local placedAsset = placeAsset(assetToPlace, result.Position, result.Normal)
				if placedAsset then placedAsset.Parent = groupFolder end
			end
		end
	end
	if #groupFolder:GetChildren() == 0 then groupFolder:Destroy() end
	ChangeHistoryService:SetWaypoint("Brush - After Line")
end

-- Main Connection Logic

C.applyPathBtn[1].MouseButton1Click:Connect(paintAlongPath)
C.clearPathBtn[1].MouseButton1Click:Connect(clearPath)
C.fillBtn[1].MouseButton1Click:Connect(function() if C.fillBtn[1].Text ~= "SELECT TARGET VOLUME" then fillArea(partToFill) end end)
C.randomizeBtn[1].MouseButton1Click:Connect(function()
	C.scaleMinBox[1].Text = string.format("%.2f", randFloat(0.5, 1.0)); C.scaleMaxBox[1].Text = string.format("%.2f", randFloat(1.1, 2.5))
	C.rotXMinBox[1].Text = tostring(math.random(0, 45)); C.rotXMaxBox[1].Text = tostring(math.random(45, 90))
	C.rotZMinBox[1].Text = tostring(math.random(0, 45)); C.rotZMaxBox[1].Text = tostring(math.random(45, 90))
end)

-- Helper for UI Updates
updateModeButtonsUI = function()
	for mode, controls in pairs(C.modeButtons) do
		if mode == currentMode then
			controls.Stroke.Color = Theme.Accent
			controls.Button.TextColor3 = Theme.Accent
			controls.Stroke.Thickness = 2
		else
			controls.Stroke.Color = Theme.Border
			controls.Button.TextColor3 = Theme.Text
			controls.Stroke.Thickness = 1
		end
	end

	-- Context visibility
	C.pathFrame.Visible = (currentMode == "Path")
	C.builderFrame.Visible = (currentMode == "Builder")
	C.cableFrame.Visible = (currentMode == "Cable")
	C.fillFrame.Visible = (currentMode == "Fill")

	-- Input visibility
	local showBrush = (currentMode == "Paint" or currentMode == "Erase" or currentMode == "Replace" or currentMode == "Volume" or currentMode == "Fill")
	local showDensity = (currentMode == "Paint" or currentMode == "Volume" or currentMode == "Fill")
	local showSpacing = (currentMode == "Paint" or currentMode == "Line" or currentMode == "Path")

	C.radiusBox[2].Visible = showBrush
	C.densityBox[2].Visible = showDensity
	C.spacingBox[2].Visible = showSpacing
end

updateToggle = function(btn, inner, label, state, activeText, inactiveText)
	inner.Visible = state
	if state then
		inner.BackgroundColor3 = Theme.Accent
		if activeText then label.Text = activeText end
	else
		if inactiveText then label.Text = inactiveText end
	end
end

updateAllToggles = function()
	updateToggle(C.pathFollowPathBtn[1], C.pathFollowPathBtn[2], C.pathFollowPathBtn[3], pathFollowPath)
	updateToggle(C.pathCloseLoopBtn[1], C.pathCloseLoopBtn[2], C.pathCloseLoopBtn[3], pathCloseLoop)
	updateToggle(C.builderStretchToggle[1], C.builderStretchToggle[2], C.builderStretchToggle[3], C.builderStretchToggle[1].Text == "Stretch Segment") -- Logic simplified

	local alignState = false
	local activeState = false
	if selectedAssetInUI then
		alignState = assetOffsets[selectedAssetInUI .. "_align"]
		activeState = assetOffsets[selectedAssetInUI .. "_active"] ~= false
	end

	updateToggle(C.assetSettingsAlign[1], C.assetSettingsAlign[2], C.assetSettingsAlign[3], alignState)
	updateToggle(C.assetSettingsActive[1], C.assetSettingsActive[2], C.assetSettingsActive[3], activeState)

	updateToggle(C.physicsModeBtn[1], C.physicsModeBtn[2], C.physicsModeBtn[3], physicsModeEnabled)
	updateToggle(C.snapToGridBtn[1], C.snapToGridBtn[2], C.snapToGridBtn[3], snapToGridEnabled)
	updateToggle(C.avoidOverlapBtn[1], C.avoidOverlapBtn[2], C.avoidOverlapBtn[3], avoidOverlap)
	updateToggle(C.densityPreviewBtn[1], C.densityPreviewBtn[2], C.densityPreviewBtn[3], densityPreviewEnabled)
	updateToggle(C.autoTerrainPaintBtn[1], C.autoTerrainPaintBtn[2], C.autoTerrainPaintBtn[3], autoTerrainPaint)

	local saText = "Surface Lock: OFF"
	if surfaceAngleMode == "Floor" then saText = "Surface Lock: FLOOR"
	elseif surfaceAngleMode == "Wall" then saText = "Surface Lock: WALL" end
	updateToggle(C.surfaceAngleBtn[1], C.surfaceAngleBtn[2], C.surfaceAngleBtn[3], surfaceAngleMode ~= "Off", saText, saText)
end

updateMaskingUI = function()
	C.maskingModeBtn[1].Text = "MASK: " .. string.upper(maskingMode)
	if maskingMode == "Off" then
		C.maskingTargetLabel.Text = "TARGET: NONE"
		C.maskingTargetLabel.TextColor3 = Theme.TextDim
		C.pickMaskTargetBtn[1].Visible = false
	else
		C.pickMaskTargetBtn[1].Visible = true
		if maskingValue then
			C.maskingTargetLabel.TextColor3 = Theme.Success
			if maskingMode == "Material" then C.maskingTargetLabel.Text = "TARGET: " .. maskingValue.Name
			elseif maskingMode == "Tag" then C.maskingTargetLabel.Text = "TARGET: " .. tostring(maskingValue)
			elseif maskingMode == "Color" then
				local c = maskingValue
				C.maskingTargetLabel.Text = string.format("TARGET: %.2f, %.2f, %.2f", c.r, c.g, c.b)
			end
		else
			C.maskingTargetLabel.Text = "TARGET: NONE"
			C.maskingTargetLabel.TextColor3 = Theme.Warning
		end
	end
end

addSelectedAssets = function()
	local selection = Selection:Get()
	for _, v in ipairs(selection) do
		if (v:IsA("Model") or v:IsA("BasePart")) and not assetsFolder:FindFirstChild(v.Name) then
			local clone = v:Clone()
			clone.Parent = assetsFolder
		end
	end
	updateAssetUIList()
end

clearAssetList = function()
	assetsFolder:ClearAllChildren()
	assetOffsets = {}
	updateAssetUIList()
end

-- Asset UI Logic
local function setupViewport(viewport, asset, zoomScale)
	zoomScale = zoomScale or 1.0
	for _, c in ipairs(viewport:GetChildren()) do c:Destroy() end
	local cam = Instance.new("Camera"); cam.Parent = viewport; viewport.CurrentCamera = cam
	local worldModel = Instance.new("WorldModel"); worldModel.Parent = viewport
	local c = asset:Clone(); c.Parent = worldModel
	local cf, size = c:GetBoundingBox()
	local maxDim = math.max(size.X, size.Y, size.Z)
	local dist = (maxDim / 2) / math.tan(math.rad(35))
	dist = (dist * 1.2) / zoomScale
	cam.CFrame = CFrame.new(cf.Position + Vector3.new(dist, dist*0.8, dist), cf.Position)
end

updateAssetUIList = function()
	for _, v in pairs(C.assetListFrame:GetChildren()) do if v:IsA("GuiObject") then v:Destroy() end end
	local children = assetsFolder:GetChildren()

	for _, asset in ipairs(children) do
		local btn = Instance.new("TextButton")
		btn.BackgroundColor3 = Theme.Panel
		btn.Text = ""
		btn.Parent = C.assetListFrame
		local stroke = Instance.new("UIStroke"); stroke.Color = Theme.Border; stroke.Parent = btn

		local vp = Instance.new("ViewportFrame")
		vp.Size = UDim2.new(1, -8, 0, 60)
		vp.Position = UDim2.new(0, 4, 0, 4)
		vp.BackgroundTransparency = 1
		vp.Parent = btn

		-- Zoom Controls
		local zoomKey = asset.Name .. "_previewZoom"
		local zoom = assetOffsets[zoomKey] or 1.0

		pcall(function() setupViewport(vp, asset, zoom) end)

		local function updateZoom(delta)
			zoom = math.clamp(zoom + delta, 0.5, 5.0)
			assetOffsets[zoomKey] = zoom
			persistOffsets()
			pcall(function() setupViewport(vp, asset, zoom) end)
		end

		local plusBtn = Instance.new("TextButton")
		plusBtn.Size = UDim2.new(0, 20, 0, 20)
		plusBtn.Position = UDim2.new(1, -24, 0, 4)
		plusBtn.Text = "+"
		plusBtn.BackgroundColor3 = Theme.Background
		plusBtn.TextColor3 = Theme.Text
		plusBtn.Parent = btn
		plusBtn.MouseButton1Click:Connect(function() updateZoom(0.1) end)

		local minusBtn = Instance.new("TextButton")
		minusBtn.Size = UDim2.new(0, 20, 0, 20)
		minusBtn.Position = UDim2.new(1, -24, 0, 28)
		minusBtn.Text = "-"
		minusBtn.BackgroundColor3 = Theme.Background
		minusBtn.TextColor3 = Theme.Text
		minusBtn.Parent = btn
		minusBtn.MouseButton1Click:Connect(function() updateZoom(-0.1) end)

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -8, 0, 20)
		lbl.Position = UDim2.new(0, 4, 1, -24)
		lbl.BackgroundTransparency = 1
		lbl.Text = asset.Name
		lbl.Font = Theme.FontTech
		lbl.TextSize = 11
		lbl.TextColor3 = Theme.Text
		lbl.TextTruncate = Enum.TextTruncate.AtEnd
		lbl.Parent = btn

		btn.MouseButton1Click:Connect(function()
			if currentMode == "Builder" and builderSlotToAssign then
				if builderSlotToAssign == "Post" then builderPostAsset = asset; C.builderPostSlot[1].Text = "POST: "..asset.Name
				elseif builderSlotToAssign == "Segment" then builderSegmentAsset = asset; C.builderSegmentSlot[1].Text = "SEG: "..asset.Name end
				builderSlotToAssign = nil
			else
				selectedAssetInUI = asset.Name
				C.assetSettingsFrame.Visible = true
				C.assetSettingsName.Text = "SELECTED: " .. string.upper(asset.Name)
				C.assetSettingsOffsetY[1].Text = tostring(assetOffsets[asset.Name] or 0)
				C.assetSettingsWeight[1].Text = tostring(assetOffsets[asset.Name.."_weight"] or 1)
				updateAllToggles()
				updateAssetUIList() -- Redraw for highlight
			end
		end)

		if selectedAssetInUI == asset.Name then stroke.Color = Theme.Accent; stroke.Thickness = 2 end
	end
end

updateFillSelection = function()
	if currentMode ~= "Fill" then
		partToFill = nil
		if fillSelectionBox then fillSelectionBox.Adornee = nil end
		C.fillBtn[1].Text = "SELECT TARGET VOLUME"
		C.fillBtn[1].TextColor3 = Theme.Text
		return
	end
	local selection = Selection:Get()
	if #selection == 1 and selection[1]:IsA("BasePart") then
		partToFill = selection[1]
		if not fillSelectionBox then
			fillSelectionBox = Instance.new("SelectionBox")
			fillSelectionBox.Color3 = Theme.Accent
			fillSelectionBox.LineThickness = 0.1
			fillSelectionBox.Parent = previewFolder
		end
		fillSelectionBox.Adornee = partToFill
		C.fillBtn[1].Text = "FILL: " .. partToFill.Name
		C.fillBtn[1].TextColor3 = Theme.Success
	else
		partToFill = nil
		if fillSelectionBox then fillSelectionBox.Adornee = nil end
		C.fillBtn[1].Text = "SELECT TARGET VOLUME"
		C.fillBtn[1].TextColor3 = Theme.Text
	end
end

setMode = function(newMode)
	if currentMode == newMode then return end

	if currentMode == "Replace" then sourceAsset = nil; targetAsset = nil end
	if currentMode == "Erase" and newMode ~= "Erase" then eraseFilter = {} end
	lineStartPoint = nil
	if linePreviewPart then linePreviewPart.Parent = nil end
	if newMode ~= "Path" then clearPath() end
	if newMode ~= "Cable" then clearCable() end
	if newMode ~= "Builder" then builderStartPoint = nil; builderPreviewFolder:ClearAllChildren() end

	currentMode = newMode
	updateModeButtonsUI()
	updatePreview()
	updateFillSelection()
end

-- Event Handling & Activation

local function onMove()
	if not active then return end
	updatePreview()
	if currentMode == "Builder" and builderStartPoint then
		local unitRay = workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {previewFolder, getWorkspaceContainer(), builderPreviewFolder}
		local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, params)
		if result then updateBuilderPreview(builderStartPoint, result.Position) end
	elseif isPainting then
		local unitRay = workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {previewFolder, getWorkspaceContainer(), densityPreviewFolder, pathPreviewFolder, cablePreviewFolder}
		local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, params)
		if result and lastPaintPosition then
			local spacing = math.max(0.1, parseNumber(C.spacingBox[1].Text, 1.0))
			if (result.Position - lastPaintPosition).Magnitude >= spacing then
				if currentMode == "Paint" then paintAt(result.Position, result.Normal)
				elseif currentMode == "Erase" then eraseAt(result.Position)
				elseif currentMode == "Replace" then replaceAt(result.Position)
				end
				lastPaintPosition = result.Position
			end
		end
	end
end

local function onDown()
	if not active or not mouse then return end
	local center, normal, _ = findSurfacePositionAndNormal()

	-- For Volume Mode, we don't need a surface
	if currentMode == "Volume" then
		local unitRay = workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y)
		local pos = unitRay.Origin + unitRay.Direction * 100
		paintInVolume(pos)
		return
	end

	if not center then return end

	if currentMode == "Line" then
		if not lineStartPoint then lineStartPoint = center
		else paintAlongLine(lineStartPoint, center); lineStartPoint = nil end
	elseif currentMode == "Builder" then
		if not builderStartPoint then builderStartPoint = center
		else createBuilderStructure(builderStartPoint, center); builderStartPoint = nil; builderPreviewFolder:ClearAllChildren() end
	elseif currentMode == "Path" then
		table.insert(pathPoints, center); updatePathPreview()
	elseif currentMode == "Cable" then
		if not cableStartPoint then cableStartPoint = center
		else createCable(cableStartPoint, center); cableStartPoint = nil end
	elseif currentMode == "Paint" or currentMode == "Stamp" or currentMode == "Erase" or currentMode == "Replace" then
		if currentMode == "Paint" then paintAt(center, normal)
		elseif currentMode == "Stamp" then stampAt(center, normal)
		elseif currentMode == "Erase" then eraseAt(center)
		elseif currentMode == "Replace" then replaceAt(center)
		end

		if currentMode ~= "Stamp" then
			isPainting = true
			lastPaintPosition = center
		end
	end
end

local function onUp()
	isPainting = false
	lastPaintPosition = nil
end

local function updateOnOffButtonUI()
	if active then
		C.activationBtn.Text = "SYSTEM: ONLINE"
		C.activationBtn.TextColor3 = Theme.Background
		C.activationBtn.BackgroundColor3 = Theme.Success
		statusIndicator.BackgroundColor3 = Theme.Success
		titleLabel.Text = "SYSTEM: ONLINE // READY"
		titleLabel.TextColor3 = Theme.Success
	else
		C.activationBtn.Text = "ACTIVATE"
		C.activationBtn.TextColor3 = Theme.Text
		C.activationBtn.BackgroundColor3 = Theme.Background
		statusIndicator.BackgroundColor3 = Theme.Destructive
		titleLabel.Text = "SYSTEM: STANDBY"
		titleLabel.TextColor3 = Theme.Text
	end
end

activate = function()
	if active then return end
	active = true
	previewPart = Instance.new("Part")
	previewPart.Name = "BrushRadiusPreview"
	previewPart.Anchored = true; previewPart.CanCollide = false; previewPart.Transparency = 0.6; previewPart.Material = Enum.Material.Neon
	linePreviewPart = Instance.new("Part")
	linePreviewPart.Name = "BrushLinePreview"
	linePreviewPart.Anchored = true; linePreviewPart.CanCollide = false; linePreviewPart.Transparency = 0.5; linePreviewPart.Material = Enum.Material.Neon

	plugin:Activate(true)
	mouse = plugin:GetMouse()
	moveConn = mouse.Move:Connect(onMove)
	downConn = mouse.Button1Down:Connect(onDown)
	upConn = mouse.Button1Up:Connect(onUp)

	updatePreview()
	updateFillSelection()
	toolbarBtn:SetActive(true)
	updateOnOffButtonUI()
end

deactivate = function()
	if not active then return end
	active = false
	if moveConn then moveConn:Disconnect(); moveConn = nil end
	if downConn then downConn:Disconnect(); downConn = nil end
	if upConn then upConn:Disconnect(); upConn = nil end
	isPainting = false; lastPaintPosition = nil; lineStartPoint = nil
	clearPath(); clearCable(); mouse = nil
	if previewPart then previewPart:Destroy(); previewPart = nil; cyl = nil end
	if linePreviewPart then linePreviewPart:Destroy(); linePreviewPart = nil end
	if fillSelectionBox then fillSelectionBox.Adornee = nil end
	toolbarBtn:SetActive(false)
	updateOnOffButtonUI()
end

-- Final UI Connections

C.activationBtn.MouseButton1Click:Connect(function()
	if active then deactivate() else activate() end
end)

for mode, controls in pairs(C.modeButtons) do
	controls.Button.MouseButton1Click:Connect(function() setMode(mode) end)
end

C.addBtn[1].MouseButton1Click:Connect(addSelectedAssets)
C.clearBtn[1].MouseButton1Click:Connect(clearAssetList)

C.maskingModeBtn[1].MouseButton1Click:Connect(function()
	if maskingMode == "Off" then maskingMode = "Material"
	elseif maskingMode == "Material" then maskingMode = "Color"
	elseif maskingMode == "Color" then maskingMode = "Tag"
	else maskingMode = "Off" end
	maskingValue = nil
	updateMaskingUI()
end)

C.pickMaskTargetBtn[1].MouseButton1Click:Connect(function()
	local sel = Selection:Get()
	if #sel > 0 and sel[1]:IsA("BasePart") then
		if maskingMode == "Material" then maskingValue = sel[1].Material
		elseif maskingMode == "Color" then maskingValue = sel[1].Color
		elseif maskingMode == "Tag" then
			local t = CollectionService:GetTags(sel[1])
			if #t > 0 then maskingValue = t[1] end
		end
		updateMaskingUI()
	end
end)

C.cableColorButton[1].MouseButton1Click:Connect(function()
	plugin:ShowColorPicker(cableColor, function(c) cableColor = c; C.cableColorButton[1].BackgroundColor3 = c end)
end)
C.cableMaterialButton[1].MouseButton1Click:Connect(function()
	-- Simple toggle for demo
	if cableMaterial == Enum.Material.Plastic then cableMaterial = Enum.Material.Neon
	else cableMaterial = Enum.Material.Plastic end
	C.cableMaterialButton[1].Text = "MAT: " .. cableMaterial.Name
end)

-- Input Connections (Persistence)
C.assetSettingsOffsetY[1].FocusLost:Connect(function()
	if selectedAssetInUI then
		assetOffsets[selectedAssetInUI] = parseNumber(C.assetSettingsOffsetY[1].Text, 0)
		persistOffsets()
	end
end)
C.assetSettingsWeight[1].FocusLost:Connect(function()
	if selectedAssetInUI then
		assetOffsets[selectedAssetInUI.."_weight"] = parseNumber(C.assetSettingsWeight[1].Text, 1)
		persistOffsets()
	end
end)
C.assetSettingsAlign[1].MouseButton1Click:Connect(function()
	if selectedAssetInUI then
		assetOffsets[selectedAssetInUI.."_align"] = not assetOffsets[selectedAssetInUI.."_align"]
		persistOffsets()
		updateAllToggles()
	end
end)
C.assetSettingsActive[1].MouseButton1Click:Connect(function()
	if selectedAssetInUI then
		local key = selectedAssetInUI.."_active"
		assetOffsets[key] = not (assetOffsets[key] ~= false)
		persistOffsets()
		updateAllToggles()
	end
end)

-- Global Settings Toggles
C.pathFollowPathBtn[1].MouseButton1Click:Connect(function() pathFollowPath = not pathFollowPath; updateAllToggles() end)
C.pathCloseLoopBtn[1].MouseButton1Click:Connect(function() pathCloseLoop = not pathCloseLoop; updateAllToggles(); updatePathPreview() end)
C.builderStretchToggle[1].MouseButton1Click:Connect(function() C.builderStretchToggle[1].Text = (C.builderStretchToggle[1].Text == "Stretch Segment") and "Don't Stretch" or "Stretch Segment"; updateAllToggles() end)

C.physicsModeBtn[1].MouseButton1Click:Connect(function() physicsModeEnabled = not physicsModeEnabled; updateAllToggles() end)
C.snapToGridBtn[1].MouseButton1Click:Connect(function() snapToGridEnabled = not snapToGridEnabled; updateAllToggles() end)
C.densityPreviewBtn[1].MouseButton1Click:Connect(function() densityPreviewEnabled = not densityPreviewEnabled; updateAllToggles() end)
C.avoidOverlapBtn[1].MouseButton1Click:Connect(function() avoidOverlap = not avoidOverlap; updateAllToggles() end)
C.autoTerrainPaintBtn[1].MouseButton1Click:Connect(function() autoTerrainPaint = not autoTerrainPaint; updateAllToggles() end)
C.surfaceAngleBtn[1].MouseButton1Click:Connect(function()
	if surfaceAngleMode == "Off" then surfaceAngleMode = "Floor"
	elseif surfaceAngleMode == "Floor" then surfaceAngleMode = "Wall"
	else surfaceAngleMode = "Off" end
	updateAllToggles()
end)

C.physicsSettleTimeBox[1].FocusLost:Connect(function() physicsSettleTime = parseNumber(C.physicsSettleTimeBox[1].Text, 1.5) end)
C.gridSizeBox[1].FocusLost:Connect(function() gridSize = parseNumber(C.gridSizeBox[1].Text, 4) end)

toolbarBtn.Click:Connect(function() widget.Enabled = not widget.Enabled end)

-- Init
loadOffsets()
Selection.SelectionChanged:Connect(updateFillSelection)
updateAssetUIList()
updateModeButtonsUI()
updateAllToggles()
updateMaskingUI()

-- Cleanup
plugin.Unloading:Connect(function()
	deactivate()
	if previewFolder then previewFolder:Destroy() end
	if densityPreviewFolder then densityPreviewFolder:Destroy() end
	if pathPreviewFolder then pathPreviewFolder:Destroy() end
	if cablePreviewFolder then cablePreviewFolder:Destroy() end
	if builderPreviewFolder then builderPreviewFolder:Destroy() end
end)

-- Global Preview Folders
previewFolder = workspace:FindFirstChild("_BrushPreview") or Instance.new("Folder", workspace); previewFolder.Name = "_BrushPreview"
densityPreviewFolder = workspace:FindFirstChild("_DensityPreview") or Instance.new("Folder", workspace); densityPreviewFolder.Name = "_DensityPreview"
pathPreviewFolder = workspace:FindFirstChild("_PathPreview") or Instance.new("Folder", workspace); pathPreviewFolder.Name = "_PathPreview"
cablePreviewFolder = workspace:FindFirstChild("_CablePreview") or Instance.new("Folder", workspace); cablePreviewFolder.Name = "_CablePreview"
builderPreviewFolder = workspace:FindFirstChild("_BuilderPreview") or Instance.new("Folder", workspace); builderPreviewFolder.Name = "_BuilderPreview"

-- Print Status
print("Brush Tool V8 // Cyber-Industrial UI Loaded.")
print("System Status: ONLINE")
