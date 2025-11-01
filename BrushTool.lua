-- Brush Tool Plugin for Roblox Studio

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")

-- Ensure assets folder exists
local ASSET_FOLDER_NAME = "BrushToolAssets"
local assetsFolder = ServerStorage:FindFirstChild(ASSET_FOLDER_NAME)
if not assetsFolder then
	assetsFolder = Instance.new("Folder")
	assetsFolder.Name = ASSET_FOLDER_NAME
	assetsFolder.Parent = ServerStorage
end

--- Menentukan nama folder induk di Workspace
local WORKSPACE_FOLDER_NAME = "BrushToolCreations"

local assetOffsets = {}
local SETTINGS_KEY = "BrushToolAssetOffsets_v2" 

-- Toolbar & UI
local toolbar = plugin:CreateToolbar("Brush Tool")
local toolbarBtn = toolbar:CreateButton("Brush", "Toggle Brush Mode (toolbar)", "")

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	true,
	false,
	380,
	550,
	300,
	200
)
local widget = plugin:CreateDockWidgetPluginGui("BrushToolWidget", widgetInfo)
widget.Title = "Brush Tool"
widget.Enabled = true -- show UI on load

-- Build UI inside widget
local ui = Instance.new("Frame")
ui.Size = UDim2.new(1,0,1,0)
ui.BackgroundTransparency = 1
ui.Parent = widget

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
makeLabel("Scale max:", 72+32)
local scaleMaxBox = makeTextBox(1.3, 260, 72, 80)

makeLabel("Spacing (min distance):", 120)
local spacingBox = makeTextBox(1.5, 180, 120, 180)

local addBtn = Instance.new("TextButton")
addBtn.Size = UDim2.new(0, 180, 0, 28)
addBtn.Position = UDim2.new(0, 8, 0, 152)
addBtn.Text = "Add Selected to Assets"
addBtn.Font = Enum.Font.SourceSans
addBtn.TextSize = 14
addBtn.Parent = ui

local clearBtn = Instance.new("TextButton")
clearBtn.Size = UDim2.new(0, 180, 0, 28)
clearBtn.Position = UDim2.new(0, 200, 0, 152)
clearBtn.Text = "Clear Asset List"
clearBtn.Font = Enum.Font.SourceSans
clearBtn.TextSize = 14
clearBtn.Parent = ui

local brushToggleBtn = Instance.new("TextButton")
brushToggleBtn.Size = UDim2.new(0, 364, 0, 36)
brushToggleBtn.Position = UDim2.new(0, 8, 0, 188)
brushToggleBtn.Text = "Brush: Off"
brushToggleBtn.Font = Enum.Font.SourceSans
brushToggleBtn.TextSize = 16
brushToggleBtn.Parent = ui

local assetsLabel = makeLabel("Per-Asset Y-Offsets (0 = auto-ground):", 232)
assetsLabel.Size = UDim2.new(1, -16, 0, 22)

local assetListFrame = Instance.new("ScrollingFrame")
assetListFrame.Size = UDim2.new(1, -16, 1, -262)
assetListFrame.Position = UDim2.new(0, 8, 0, 258)
assetListFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
assetListFrame.BorderSizePixel = 1
assetListFrame.ScrollBarThickness = 6
assetListFrame.Parent = ui

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = assetListFrame

-- Util helpers
local function trim(s)
	return s:match("^%s*(.-)%s*$") or s
end

local function parseNumber(txt, fallback)
	local ok, n = pcall(function() return tonumber(trim(txt)) end)
	if ok and n then return n end
	return fallback
end

local function persistOffsets()
	local ok, jsonString = pcall(HttpService.JSONEncode, HttpService, assetOffsets)
	if ok then
		plugin:SetSetting(SETTINGS_KEY, jsonString)
	else
		warn("Brush Tool: Gagal menyimpan offset aset! Error:", jsonString)
	end
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

-- PERUBAHAN: Fungsi untuk membangun UI daftar aset dinamis
local function updateAssetUIList()
	assetListFrame.CanvasPosition = Vector2.new(0, 0)
	for _,v in ipairs(assetListFrame:GetChildren()) do
		if v:IsA("GuiObject") then
			v:Destroy()
		end
	end

	local children = assetsFolder:GetChildren()
	local canvasHeight = #children * 30 + (#children - 1) * 4
	assetListFrame.CanvasSize = UDim2.new(0, 0, 0, math.max(canvasHeight, 1))

	for i, asset in ipairs(children) do
		local assetName = asset.Name

		local offsetKey = assetName 
		local alignKey = assetName .. "_align" 

		local row = Instance.new("Frame")
		row.Name = assetName .. "_Row"
		row.Size = UDim2.new(1, 0, 0, 30)
		row.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		row.LayoutOrder = i
		row.Parent = assetListFrame

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(0.5, -5, 1, 0) 
		lbl.Position = UDim2.new(0, 0, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = " " .. assetName
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Font = Enum.Font.SourceSans
		lbl.TextSize = 14
		lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
		lbl.Parent = row

		local offsetBox = Instance.new("TextBox")
		offsetBox.Size = UDim2.new(0.25, -5, 1, -4) 
		offsetBox.Position = UDim2.new(0.5, 0, 0, 2)
		offsetBox.Text = tostring(assetOffsets[offsetKey] or 0)
		offsetBox.ClearTextOnFocus = false
		offsetBox.Font = Enum.Font.SourceSans
		offsetBox.TextSize = 14
		offsetBox.Parent = row

		-- PERBAIKAN: Menggunakan TextButton sebagai sakelar (toggle)
		local alignButton = Instance.new("TextButton")
		alignButton.Name = "AlignButton"
		alignButton.Size = UDim2.new(0.25, 0, 1, -4)
		alignButton.Position = UDim2.new(0.75, 5, 0, 2)
		alignButton.Font = Enum.Font.SourceSans
		alignButton.TextSize = 13
		alignButton.Parent = row

		-- Fungsi untuk mengatur tampilan tombol berdasarkan status
		local function updateButtonAppearance()
			local isAligning = assetOffsets[alignKey] or false
			if isAligning then
				alignButton.Text = "Selaras: Ya"
				alignButton.BackgroundColor3 = Color3.fromRGB(70, 115, 70) -- Hijau
			else
				alignButton.Text = "Selaras: Tdk"
				alignButton.BackgroundColor3 = Color3.fromRGB(115, 70, 70) -- Merah
			end
		end

		-- Atur tampilan awal
		updateButtonAppearance()

		-- Saat pengguna selesai mengedit offset, simpan nilainya
		offsetBox.FocusLost:Connect(function(enterPressed)
			local newValue = parseNumber(offsetBox.Text, 0)
			assetOffsets[offsetKey] = newValue
			offsetBox.Text = tostring(newValue) 
			persistOffsets() 
		end)

		-- PERBAIKAN: Gunakan MouseButton1Click untuk tombol sakelar
		alignButton.MouseButton1Click:Connect(function()
			-- Balikkan nilainya
			assetOffsets[alignKey] = not (assetOffsets[alignKey] or false)
			-- Perbarui tampilan tombol
			updateButtonAppearance()
			-- Simpan pengaturan
			persistOffsets()
		end)
	end
end


-- Panggil fungsi-fungsi baru saat plugin dimuat
loadOffsets()
updateAssetUIList()


-- Add selected assets to ServerStorage folder (cloned)
addBtn.MouseButton1Click:Connect(function()
	local sel = Selection:Get()
	if #sel == 0 then
		warn("Select at least one model/instance to add as brush asset.")
		return
	end
	for _,inst in ipairs(sel) do
		if inst:IsA("Model") or inst:IsA("Folder") then
			local copy = inst:Clone()
			-- ensure unique name
			local name = copy.Name
			local suffix = 1
			while assetsFolder:FindFirstChild(name) do
				name = copy.Name .. "_" .. tostring(suffix)
				suffix = suffix + 1
			end
			copy.Name = name
			copy.Parent = assetsFolder
		elseif inst:IsA("BasePart") then
			-- wrap in model
			local m = Instance.new("Model")
			m.Name = inst.Name.."_Model"
			local clone = inst:Clone()
			clone.Parent = m
			m.PrimaryPart = clone
			m.Parent = assetsFolder
		else
			warn("Skipping selection: "..inst:GetFullName())
		end
	end
	updateAssetUIList()
end)

clearBtn.MouseButton1Click:Connect(function()
	for _,c in ipairs(assetsFolder:GetChildren()) do
		c:Destroy()
	end
	-- Juga bersihkan offset yang disimpan
	assetOffsets = {}
	persistOffsets()
	updateAssetUIList()
end)

-- Preview visual (a flat disk part)
local previewFolder = workspace:FindFirstChild("_BrushPreview")
if previewFolder then previewFolder:Destroy() end
previewFolder = Instance.new("Folder")
previewFolder.Name = "_BrushPreview"
previewFolder.Parent = workspace

local previewPart = Instance.new("Part")
previewPart.Name = "BrushRadiusPreview"
previewPart.Anchored = true
previewPart.CanCollide = false
previewPart.CanQuery = false
previewPart.CanTouch = false
previewPart.Transparency = 0.6
previewPart.Size = Vector3.new(1,1,1)
previewPart.Material = Enum.Material.Neon
previewPart.Parent = previewFolder

local cyl = Instance.new("CylinderMesh")
cyl.Parent = previewPart
cyl.Scale = Vector3.new(1, 0.02, 1)

-- State
local active = false
local mouse = nil
local moveConn, downConn

-- Random helpers
local function randFloat(a,b)
	return a + math.random()*(b-a)
end

local function randomPointInCircle(radius)
	local r = radius * math.sqrt(math.random())
	local theta = math.random() * 2 * math.pi
	return Vector3.new(r * math.cos(theta), 0, r * math.sin(theta))
end

-- Scale a model about its bounding box center
local function scaleModel(model, scale)
	local ok, bboxCFrame, bboxSize = pcall(function() return model:GetBoundingBox() end)
	if not ok then return end
	local center = bboxCFrame.p
	for _,d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = d.Position - center
			d.Size = d.Size * scale
			d.CFrame = CFrame.new(center + rel * scale) * (d.CFrame - d.CFrame.p)
		elseif d:IsA("SpecialMesh") then
			d.Scale = d.Scale * scale
		elseif d:IsA("MeshPart") then
			pcall(function() d.Mesh.Scale = d.Mesh.Scale * scale end)
		end
	end
end

-- Raycast to find ground from high above (returns position and normal)
local function findSurfacePositionAndNormal(pos)
	local origin = pos + Vector3.new(0, 200, 0)
	local dir = Vector3.new(0, -400, 0)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {previewFolder}
	params.FilterType = Enum.RaycastFilterType.Exclude
	local result = workspace:Raycast(origin, dir, params)
	if result then
		return result.Position, result.Normal, result.Instance
	end
	return nil
end

--- Fungsi untuk mendapatkan/membuat folder induk
local function getWorkspaceContainer()
	local container = workspace:FindFirstChild(WORKSPACE_FOLDER_NAME)
	if not container or not container:IsA("Folder") then
		container = Instance.new("Folder")
		container.Name = WORKSPACE_FOLDER_NAME
		container.Parent = workspace
	end
	return container
end

-- Fungsi paintAt() (Tidak perlu diubah, sudah benar)
local function paintAt(center)
	local radius = math.max(0.1, parseNumber(radiusBox.Text, 10))
	local smin = parseNumber(scaleMinBox.Text, 0.8)
	local smax = parseNumber(scaleMaxBox.Text, 1.2)
	local spacing = math.max(0.1, parseNumber(spacingBox.Text, 1.0))
	if smin <= 0 then smin = 0.1 end
	if smax < smin then smax = smin end

	ChangeHistoryService:SetWaypoint("Brush - Before")

	local container = getWorkspaceContainer()
	local groupFolder = Instance.new("Folder")
	groupFolder.Name = "BrushGroup_" .. tostring(math.floor(os.time())) 
	groupFolder.Parent = container

	local placed = {} 

	local assetList = assetsFolder:GetChildren()
	if #assetList == 0 then
		warn("Brush Tool: Tidak ada aset di folder " .. ASSET_FOLDER_NAME)
		groupFolder:Destroy()
		ChangeHistoryService:SetWaypoint("Brush - Batal (Tidak ada aset)")
		return
	end

	for i=1, #assetList do
		local assetToClone = assetList[i]

		if not assetToClone then break end

		local clone = assetToClone:Clone()

		if clone:IsA("Model") and not clone.PrimaryPart then
			for _,v in ipairs(clone:GetDescendants()) do
				if v:IsA("BasePart") then
					clone.PrimaryPart = v
					break
				end
			end
		end

		local found = false
		local candidatePos = nil 
		local candidateNormal = Vector3.new(0, 1, 0) 
		local attempts = 0

		while not found and attempts < 12 do
			attempts = attempts + 1
			local offset = randomPointInCircle(radius)
			local spawnPosGuess = Vector3.new(center.X + offset.X, center.Y + 5, center.Z + offset.Z)
			local surfacePos, normal = findSurfacePositionAndNormal(spawnPosGuess)

			if surfacePos then 
				local ok = true
				for _,p in ipairs(placed) do
					if (p - surfacePos).Magnitude < spacing then
						ok = false
						break
					end
				end
				if ok then
					found = true
					candidatePos = surfacePos 
					candidateNormal = normal or Vector3.new(0, 1, 0) 
				end
			end
		end

		if not candidatePos then
			local centerSurface, centerNormal = findSurfacePositionAndNormal(center)
			if centerSurface then
				candidatePos = centerSurface
				candidateNormal = centerNormal or Vector3.new(0, 1, 0)
			else
				candidatePos = center 
				candidateNormal = Vector3.new(0, 1, 0) 
			end
		end

		local s = randFloat(smin, smax)
		local yrot = math.rad(math.random() * 360)

		local assetName = clone.Name
		local customOffset = assetOffsets[assetName] or 0
		local shouldAlign = assetOffsets[assetName .. "_align"] or false

		if clone:IsA("Model") and clone.PrimaryPart then
			clone:SetPrimaryPartCFrame(CFrame.new(candidatePos) * CFrame.Angles(0, yrot, 0))

			if math.abs(s - 1) > 0.0001 then
				scaleModel(clone, s)
			end

			local ok, bboxCFrame, bboxSize = pcall(function() return clone:GetBoundingBox() end)
			local finalPosition

			if ok then
				local currentBottomY = bboxCFrame.Position.Y - (bboxSize.Y / 2)
				local targetBottomY = candidatePos.Y
				local shiftY = (targetBottomY - currentBottomY) + customOffset
				finalPosition = clone:GetPrimaryPartCFrame().Position + Vector3.new(0, shiftY, 0)
			else
				warn("Tidak bisa mendapatkan bounding box untuk " .. clone.Name .. ", penempatan mungkin tidak akurat.")
				finalPosition = clone:GetPrimaryPartCFrame().Position + Vector3.new(0, customOffset, 0) -- Fallback
			end

			local finalCFrame
			if shouldAlign and candidateNormal then
				local yRotCFrame = CFrame.Angles(0, yrot, 0)
				local look = yRotCFrame.LookVector
				local right = look:Cross(candidateNormal).Unit
				local lookActual = candidateNormal:Cross(right).Unit

				if right.Magnitude < 0.9 then
					look = yRotCFrame.RightVector
					right = look:Cross(candidateNormal).Unit
					lookActual = candidateNormal:Cross(right).Unit
				end

				finalCFrame = CFrame.fromMatrix(finalPosition, right, candidateNormal, -lookActual)
			else
				finalCFrame = CFrame.new(finalPosition) * CFrame.Angles(0, yrot, 0)
			end

			clone:SetPrimaryPartCFrame(finalCFrame)

		elseif clone:IsA("BasePart") then
			clone.Size = clone.Size * s

			local finalYOffset = (clone.Size.Y / 2) + customOffset
			local finalPos = candidatePos + Vector3.new(0, finalYOffset, 0)

			local finalCFrame
			if shouldAlign and candidateNormal then
				local yRotCFrame = CFrame.Angles(0, yrot, 0)
				local look = yRotCFrame.LookVector
				local right = look:Cross(candidateNormal).Unit
				local lookActual = candidateNormal:Cross(right).Unit

				if right.Magnitude < 0.9 then
					look = yRotCFrame.RightVector
					right = look:Cross(candidateNormal).Unit
					lookActual = candidateNormal:Cross(right).Unit
				end

				finalCFrame = CFrame.fromMatrix(finalPos, right, candidateNormal, -lookActual)
			else
				finalCFrame = CFrame.new(finalPos) * CFrame.Angles(0, yrot, 0)
			end

			clone.CFrame = finalCFrame
		end

		clone.Parent = groupFolder
		table.insert(placed, candidatePos)
	end

	if #groupFolder:GetChildren() == 0 then
		groupFolder:Destroy()
	end

	ChangeHistoryService:SetWaypoint("Brush - After")
end


-- Mouse events
local function updatePreview()
	if not mouse or not mouse.Hit then
		previewPart.Parent = previewFolder
		return
	end
	local radius = math.max(0.1, parseNumber(radiusBox.Text, 10))
	local hitPos = mouse.Hit.Position
	local surfacePos, normal = findSurfacePositionAndNormal(hitPos)
	local pos = surfacePos or hitPos

	if normal then
		local look = Vector3.new(1,0,0)
		if math.abs(look:Dot(normal)) > 0.99 then look = Vector3.new(0,0,1) end
		local right = look:Cross(normal).Unit
		local lookActual = normal:Cross(right).Unit
		previewPart.CFrame = CFrame.fromMatrix(pos + normal * 0.05, right, normal, -lookActual)
	else
		previewPart.CFrame = CFrame.new(pos + Vector3.new(0, 0.05, 0))
	end

	previewPart.Size = Vector3.new(1,1,1)
	cyl.Scale = Vector3.new(radius*2, 0.02, radius*2)
	previewPart.Parent = previewFolder
end

local function onMove()
	if active then
		updatePreview()
	end
end

local function onDown()
	if not active or not mouse or not mouse.Hit then return end
	local center = mouse.Hit.Position
	paintAt(center)
end

local function activate()
	if active then return end
	active = true
	plugin:Activate(true)
	mouse = plugin:GetMouse()
	moveConn = mouse.Move:Connect(onMove)
	downConn = mouse.Button1Down:Connect(onDown)
	updatePreview()
	brushToggleBtn.Text = "Brush: On"
	toolbarBtn:SetActive(true)
end

local function deactivate()
	if not active then return end
	active = false
	if moveConn then moveConn:Disconnect() moveConn = nil end
	if downConn then downConn:Disconnect() downConn = nil end
	mouse = nil
	previewPart.Parent = previewFolder -- hide
	brushToggleBtn.Text = "Brush: Off"
	toolbarBtn:SetActive(false)
end

local function toggle()
	if active then deactivate() else activate() end
end

toolbarBtn.Click:Connect(toggle)
brushToggleBtn.MouseButton1Click:Connect(toggle)
widget.Enabled = true

plugin.Unloading:Connect(function()
	if previewFolder and previewFolder.Parent then
		previewFolder:Destroy()
	end
end)

print("Brush Tool plugin loaded (UI visible). 'Align-to-Normal' feature enabled using TextButton fix.")
