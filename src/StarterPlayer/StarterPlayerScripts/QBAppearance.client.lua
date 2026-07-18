--[[
	In-game avatar editor (the qb-clothing "first spawn -> create your look" step).

	Opened by the server (OpenAppearanceEditor) on a character's first spawn and via the
	/appearance chat command afterwards. The player composes a look out of catalog items
	they already own -- AvatarEditorService prompts once for permission to read their
	inventory -- plus skin-tone swatches and body-scale sliders that need no inventory.

	Every change is streamed to the server (PreviewAppearance) which sanitizes it and
	applies it to the live character, so the character on screen IS the preview. Nothing
	persists until Save; Cancel reverts to the last saved look. The player's real
	site-wide Roblox avatar is never modified.
]]

local AvatarEditorService = game:GetService("AvatarEditorService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.QBRemotes)
local QBShared = require(ReplicatedStorage.QBShared.Main)

local player = Players.LocalPlayer
local AppearanceConfig = QBShared.Config.Appearance or {}

local MAX_ITEMS_PER_CATEGORY = 120
local PREVIEW_DEBOUNCE = 0.15

local COLORS = {
	page = Color3.fromRGB(12, 15, 20),
	shell = Color3.fromRGB(26, 31, 39),
	panel = Color3.fromRGB(32, 38, 48),
	panelSoft = Color3.fromRGB(38, 45, 56),
	stroke = Color3.fromRGB(74, 87, 103),
	text = Color3.fromRGB(239, 243, 247),
	muted = Color3.fromRGB(158, 170, 184),
	green = Color3.fromRGB(62, 166, 105),
	red = Color3.fromRGB(185, 73, 73),
	tabIdle = Color3.fromRGB(38, 45, 56),
	tabActive = Color3.fromRGB(62, 166, 105),
}

-- kind = "accessory" | "clothing" | "face" | "skin" | "body"
local CATEGORIES = {
	{ key = "Hair", label = "Hair", avatarAssetType = "HairAccessory", kind = "accessory", accessoryType = "Hair" },
	{ key = "Hats", label = "Hats", avatarAssetType = "Hat", kind = "accessory", accessoryType = "Hat" },
	{
		key = "FaceAcc",
		label = "Glasses",
		avatarAssetType = "FaceAccessory",
		kind = "accessory",
		accessoryType = "Face",
	},
	{ key = "Faces", label = "Faces", avatarAssetType = "Face", kind = "face" },
	{ key = "Shirts", label = "Shirts", avatarAssetType = "Shirt", kind = "clothing", clothingKey = "shirt" },
	{ key = "Pants", label = "Pants", avatarAssetType = "Pants", kind = "clothing", clothingKey = "pants" },
	{
		key = "TShirts",
		label = "T-Shirts",
		avatarAssetType = "TShirt",
		kind = "clothing",
		clothingKey = "graphicTShirt",
	},
	{
		key = "LayeredTShirts",
		label = "Layer Tees",
		avatarAssetType = "TShirtAccessory",
		kind = "accessory",
		accessoryType = "TShirt",
		isLayered = true,
	},
	{
		key = "LayeredShirts",
		label = "Layer Shirts",
		avatarAssetType = "ShirtAccessory",
		kind = "accessory",
		accessoryType = "Shirt",
		isLayered = true,
	},
	{
		key = "LayeredPants",
		label = "Layer Pants",
		avatarAssetType = "PantsAccessory",
		kind = "accessory",
		accessoryType = "Pants",
		isLayered = true,
	},
	{
		key = "Jackets",
		label = "Jackets",
		avatarAssetType = "JacketAccessory",
		kind = "accessory",
		accessoryType = "Jacket",
		isLayered = true,
	},
	{
		key = "Sweaters",
		label = "Sweaters",
		avatarAssetType = "SweaterAccessory",
		kind = "accessory",
		accessoryType = "Sweater",
		isLayered = true,
	},
	{
		key = "Shorts",
		label = "Shorts",
		avatarAssetType = "ShortsAccessory",
		kind = "accessory",
		accessoryType = "Shorts",
		isLayered = true,
	},
	{
		key = "Dresses",
		label = "Dresses",
		avatarAssetType = "DressSkirtAccessory",
		kind = "accessory",
		accessoryType = "DressSkirt",
		isLayered = true,
	},
	{
		key = "Shoes",
		label = "Shoes",
		avatarAssetTypes = {
			{ avatarAssetType = "LeftShoeAccessory", accessoryType = "LeftShoe" },
			{ avatarAssetType = "RightShoeAccessory", accessoryType = "RightShoe" },
		},
		kind = "accessory",
		isLayered = true,
	},
	{ key = "Neck", label = "Neck", avatarAssetType = "NeckAccessory", kind = "accessory", accessoryType = "Neck" },
	{
		key = "Shoulder",
		label = "Shoulder",
		avatarAssetType = "ShoulderAccessory",
		kind = "accessory",
		accessoryType = "Shoulder",
	},
	{ key = "Front", label = "Front", avatarAssetType = "FrontAccessory", kind = "accessory", accessoryType = "Front" },
	{ key = "Back", label = "Back", avatarAssetType = "BackAccessory", kind = "accessory", accessoryType = "Back" },
	{ key = "Waist", label = "Waist", avatarAssetType = "WaistAccessory", kind = "accessory", accessoryType = "Waist" },
	{ key = "Skin", label = "Skin", kind = "skin" },
	{ key = "Body", label = "Body", kind = "body" },
	{ key = "Outfits", label = "Outfits", kind = "outfits" },
}

local SKIN_COLOR_KEYS = { "head", "torso", "leftArm", "rightArm", "leftLeg", "rightLeg" }

local SCALE_SLIDERS = {
	{ key = "height", label = "Height" },
	{ key = "width", label = "Width" }, -- also drives the depth scale
	{ key = "head", label = "Head Size" },
	{ key = "bodyType", label = "Body Type" },
	{ key = "proportion", label = "Proportions" },
}

local FALLBACK_SKIN_TONES = {
	"F7DCC4",
	"F0C8A0",
	"E3B58B",
	"D6A077",
	"C68642",
	"A5694F",
	"8D5524",
	"6B4226",
	"4C2E1E",
	"35211A",
}

-- ─────────────────────────── state ───────────────────────────

local working = nil -- serialized appearance being edited (same schema the server uses)
local editorContext = { mode = "full", title = "Appearance", allowOutfits = false }
local activeCategories = {}
local isOpen = false
local busy = false
local currentCategory = nil
local inventoryAllowed = nil -- nil = not asked yet this session
local inventoryCache = {} -- [category.key] = { {id, name}, ... }
local previewScheduled = false
local savedCameraType = nil
local activeConnections = {} -- input connections owned by the current content view
local responsive = {
	compact = false,
	tiny = false,
	scale = 1,
	itemCell = Vector2.new(84, 106),
	skinCell = Vector2.new(48, 48),
}

-- ─────────────────────────── small helpers ───────────────────────────

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, entry in pairs(value) do
		copy[key] = deepCopy(entry)
	end
	return copy
end

local function scaleRange(key)
	local range = (AppearanceConfig.Scales or {})[key] or {}
	local min = tonumber(range.Min) or 0
	local max = tonumber(range.Max) or math.max(1, min)
	local default = math.clamp(tonumber(range.Default) or 1, min, max)
	return min, max, default
end

local function ensureWorkingDefaults(w)
	w.scales = type(w.scales) == "table" and w.scales or {}
	for _, key in ipairs({ "height", "width", "depth", "head", "bodyType", "proportion" }) do
		if type(w.scales[key]) ~= "number" then
			local _, _, default = scaleRange(key)
			w.scales[key] = default
		end
	end
	w.bodyParts = type(w.bodyParts) == "table" and w.bodyParts or {}
	w.clothing = type(w.clothing) == "table" and w.clothing or {}
	w.colors = type(w.colors) == "table" and w.colors or {}
	w.accessories = type(w.accessories) == "table" and w.accessories or {}
end

local function sendPreview()
	if not isOpen or previewScheduled then
		return
	end
	previewScheduled = true
	task.delay(PREVIEW_DEBOUNCE, function()
		previewScheduled = false
		if isOpen and working then
			Remotes.PreviewAppearance:FireServer(working)
		end
	end)
end

local function findAccessoryIndex(assetId)
	for index, entry in ipairs(working.accessories) do
		if entry.id == assetId then
			return index
		end
	end
	return nil
end

-- ─────────────────────────── UI scaffolding ───────────────────────────

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

local function addStroke(parent, color, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or COLORS.stroke
	stroke.Transparency = transparency or 0
	stroke.Thickness = 1
	stroke.Parent = parent
	return stroke
end

local function addPadding(parent, left, top, right, bottom)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, left or 0)
	padding.PaddingTop = UDim.new(0, top or 0)
	padding.PaddingRight = UDim.new(0, right or left or 0)
	padding.PaddingBottom = UDim.new(0, bottom or top or 0)
	padding.Parent = parent
	return padding
end

local function setPaddingOffsets(padding, left, top, right, bottom)
	padding.PaddingLeft = UDim.new(0, left or 0)
	padding.PaddingTop = UDim.new(0, top or 0)
	padding.PaddingRight = UDim.new(0, right or left or 0)
	padding.PaddingBottom = UDim.new(0, bottom or top or 0)
end

local function round(value)
	return math.floor(value + 0.5)
end

local function getViewportSize()
	local camera = Workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function makeLabel(parent, name, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Text = text or ""
	label.TextColor3 = color or COLORS.text
	label.TextSize = size or 16
	label.Font = font or Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextWrapped = true
	label.Parent = parent
	return label
end

local function makeButton(parent, name, text, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Text = text
	button.TextColor3 = COLORS.text
	button.TextSize = 15
	button.Font = Enum.Font.GothamBold
	button.TextWrapped = true
	button.Parent = parent
	addCorner(button, 8)
	return button
end

local function makeTextBox(parent, name, placeholder)
	local box = Instance.new("TextBox")
	box.Name = name
	box.BackgroundColor3 = Color3.fromRGB(20, 25, 32)
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Gotham
	box.PlaceholderColor3 = COLORS.muted
	box.PlaceholderText = placeholder or ""
	box.Text = ""
	box.TextColor3 = COLORS.text
	box.TextSize = 13
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = parent
	addCorner(box, 7)
	addStroke(box, Color3.fromRGB(60, 72, 89), 0.15)
	addPadding(box, 10, 0, 10, 0)
	return box
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QBAppearanceEditor"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 60
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -18, 0.5, 0)
panel.Size = UDim2.new(0, 400, 0.92, 0)
panel.BackgroundColor3 = COLORS.shell
panel.BorderSizePixel = 0
panel.Parent = screenGui
addCorner(panel, 8)
addStroke(panel, COLORS.stroke, 0.1)
local panelPadding = addPadding(panel, 16, 14, 16, 16)

local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local titleLabel = makeLabel(panel, "Title", "Appearance", 24, COLORS.text, Enum.Font.GothamBold)
titleLabel.Size = UDim2.new(1, 0, 0, 30)

local statusLabel = makeLabel(panel, "Status", "", 13, COLORS.muted, Enum.Font.GothamMedium)
statusLabel.Position = UDim2.fromOffset(0, 32)
statusLabel.Size = UDim2.new(1, 0, 0, 34)
statusLabel.TextYAlignment = Enum.TextYAlignment.Top

local tabsFrame = Instance.new("Frame")
tabsFrame.Name = "Tabs"
tabsFrame.BackgroundTransparency = 1
tabsFrame.Position = UDim2.fromOffset(0, 70)
tabsFrame.Size = UDim2.new(1, 0, 0, 128)
tabsFrame.Parent = panel

local tabsGrid = Instance.new("UIGridLayout")
tabsGrid.CellSize = UDim2.new(0.25, -6, 0, 28)
tabsGrid.CellPadding = UDim2.fromOffset(6, 5)
tabsGrid.SortOrder = Enum.SortOrder.LayoutOrder
tabsGrid.Parent = tabsFrame

local contentArea = Instance.new("Frame")
contentArea.Name = "Content"
contentArea.BackgroundColor3 = COLORS.panel
contentArea.BorderSizePixel = 0
contentArea.Position = UDim2.fromOffset(0, 206)
contentArea.Size = UDim2.new(1, 0, 1, -262)
contentArea.Parent = panel
addCorner(contentArea, 8)
addStroke(contentArea, Color3.fromRGB(60, 72, 89), 0.25)
local contentPadding = addPadding(contentArea, 10, 10, 10, 10)

local saveButton = makeButton(panel, "Save", "Save Look", COLORS.green)
saveButton.AnchorPoint = Vector2.new(0, 1)
saveButton.Position = UDim2.new(0, 0, 1, 0)
saveButton.Size = UDim2.new(0.62, -6, 0, 44)

local cancelButton = makeButton(panel, "Cancel", "Cancel", COLORS.red)
cancelButton.AnchorPoint = Vector2.new(1, 1)
cancelButton.Position = UDim2.new(1, 0, 1, 0)
cancelButton.Size = UDim2.new(0.38, -6, 0, 44)

local tabButtons = {} -- [category.key] = TextButton

local function updateResponsiveLayout()
	local viewport = getViewportSize()
	local compact = viewport.X < 760 or viewport.Y < 560
	local tiny = viewport.X < 560 or viewport.Y < 470
	local scale = compact and math.clamp(math.min(viewport.X / 960, viewport.Y / 760), 0.58, 1) or 1
	responsive.compact = compact
	responsive.tiny = tiny
	responsive.scale = scale
	responsive.itemCell = tiny and Vector2.new(60, 78) or compact and Vector2.new(70, 90) or Vector2.new(84, 106)
	responsive.skinCell = tiny and Vector2.new(36, 36) or compact and Vector2.new(42, 42) or Vector2.new(48, 48)

	local margin = tiny and 6 or compact and 10 or 18
	local panelWidth = round(compact and math.min(520, (viewport.X - margin * 2) / scale) or 400)
	local panelHeight =
		round(math.min(720, (viewport.Y - margin * 2) / scale, viewport.Y * (compact and 0.92 or 0.92) / scale))

	panelScale.Scale = scale
	panel.AnchorPoint = compact and Vector2.new(0.5, 0.5) or Vector2.new(1, 0.5)
	panel.Position = compact and UDim2.fromScale(0.5, 0.5) or UDim2.new(1, -margin, 0.5, 0)
	panel.Size = UDim2.fromOffset(math.max(300, panelWidth), math.max(300, panelHeight))

	local panelPadX = tiny and 7 or compact and 10 or 16
	local panelPadTop = tiny and 7 or compact and 10 or 14
	local panelPadBottom = tiny and 8 or compact and 10 or 16
	setPaddingOffsets(panelPadding, panelPadX, panelPadTop, panelPadX, panelPadBottom)

	local titleHeight = tiny and 24 or 30
	local statusHeight = tiny and 26 or compact and 30 or 34
	local tabsTop = titleHeight + statusHeight + (tiny and 6 or 8)
	local tabColumns = tiny and 3 or 4
	local tabHeight = tiny and 23 or compact and 26 or 28
	local tabGapX = tiny and 4 or 6
	local tabGapY = tiny and 3 or 5
	local tabRows = math.max(1, math.ceil(#activeCategories / tabColumns))
	local tabsHeight = tabRows * tabHeight + math.max(0, tabRows - 1) * tabGapY
	local buttonHeight = tiny and 34 or compact and 40 or 44
	local contentTop = tabsTop + tabsHeight + (tiny and 8 or 10)
	local contentBottomGap = buttonHeight + (tiny and 10 or 14)

	titleLabel.TextSize = tiny and 18 or compact and 21 or 24
	titleLabel.Size = UDim2.new(1, 0, 0, titleHeight)
	statusLabel.TextSize = tiny and 10 or compact and 12 or 13
	statusLabel.Position = UDim2.fromOffset(0, titleHeight + (tiny and 2 or 4))
	statusLabel.Size = UDim2.new(1, 0, 0, statusHeight)
	tabsFrame.Position = UDim2.fromOffset(0, tabsTop)
	tabsFrame.Size = UDim2.new(1, 0, 0, tabsHeight)
	tabsGrid.CellSize = UDim2.new(1 / tabColumns, -tabGapX, 0, tabHeight)
	tabsGrid.CellPadding = UDim2.fromOffset(tabGapX, tabGapY)
	contentArea.Position = UDim2.fromOffset(0, contentTop)
	contentArea.Size = UDim2.new(1, 0, 1, -(contentTop + contentBottomGap))
	setPaddingOffsets(
		contentPadding,
		tiny and 5 or compact and 8 or 10,
		tiny and 5 or compact and 8 or 10,
		tiny and 5 or compact and 8 or 10,
		tiny and 5 or compact and 8 or 10
	)

	saveButton.Size = UDim2.new(0.62, -6, 0, buttonHeight)
	cancelButton.Size = UDim2.new(0.38, -6, 0, buttonHeight)
	saveButton.TextSize = tiny and 12 or compact and 13 or 15
	cancelButton.TextSize = tiny and 12 or compact and 13 or 15

	for _, button in pairs(tabButtons) do
		button.TextSize = tiny and 10 or compact and 11 or 13
	end
end

local function setStatus(text)
	statusLabel.Text = text or ""
end

local function setBusy(nextBusy)
	busy = nextBusy
	saveButton.Active = not busy
	saveButton.AutoButtonColor = not busy
	saveButton.BackgroundColor3 = busy and Color3.fromRGB(79, 91, 105) or COLORS.green
end

-- ─────────────────────────── camera + character ───────────────────────────

local function anchorCharacter(anchored)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = anchored
	end
end

local function focusCamera()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	if not root or not camera then
		return
	end

	savedCameraType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	local focus = root.Position + Vector3.new(0, 0.5, 0)
	-- Aim slightly past the character's left shoulder so they sit left of the panel.
	camera.CFrame = CFrame.lookAt(
		focus + root.CFrame.LookVector * 7 + Vector3.new(0, 0.3, 0),
		focus - root.CFrame.RightVector * 1.4
	)
end

local function restoreCamera()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = savedCameraType or Enum.CameraType.Custom
	end
	savedCameraType = nil
end

-- ─────────────────────────── inventory access ───────────────────────────

local function requestInventoryAccess()
	if inventoryAllowed ~= nil then
		return inventoryAllowed
	end

	local result
	local ok = pcall(function()
		local done = Instance.new("BindableEvent")
		local connection
		connection = AvatarEditorService.PromptAllowInventoryReadAccessCompleted:Connect(function(promptResult)
			connection:Disconnect()
			result = promptResult
			done:Fire()
		end)
		AvatarEditorService:PromptAllowInventoryReadAccess()
		done.Event:Wait()
	end)

	inventoryAllowed = ok and result == Enum.AvatarPromptResult.Success
	return inventoryAllowed
end

local function categoryAssetEntries(category)
	if type(category.avatarAssetTypes) == "table" then
		return category.avatarAssetTypes
	end
	if category.avatarAssetType then
		return { category }
	end
	return {}
end

local function getInventoryPages(assetTypes)
	if AvatarEditorService.GetInventoryAsync then
		return AvatarEditorService:GetInventoryAsync(assetTypes)
	end
	return AvatarEditorService:GetInventory(assetTypes)
end

local function loadCategoryItems(category)
	if inventoryCache[category.key] then
		return inventoryCache[category.key]
	end

	local items = {}
	local seen = {}

	for _, entry in ipairs(categoryAssetEntries(category)) do
		if #items >= MAX_ITEMS_PER_CATEGORY then
			break
		end

		local enumOk, assetType = pcall(function()
			return Enum.AvatarAssetType[entry.avatarAssetType]
		end)

		if enumOk and assetType then
			local ok, err = pcall(function()
				local pages = getInventoryPages({ assetType })
				while true do
					for _, item in ipairs(pages:GetCurrentPage()) do
						local assetId = tonumber(item.AssetId)
						if assetId and not seen[assetId] then
							seen[assetId] = true
							items[#items + 1] = {
								id = assetId,
								name = item.Name,
								accessoryType = entry.accessoryType or category.accessoryType,
								isLayered = entry.isLayered == true or category.isLayered == true,
							}
						end
						if #items >= MAX_ITEMS_PER_CATEGORY then
							break
						end
					end
					if pages.IsFinished or #items >= MAX_ITEMS_PER_CATEGORY then
						break
					end
					pages:AdvanceToNextPageAsync()
				end
			end)
			if not ok then
				warn("[QBAppearance] GetInventory failed for " .. category.key .. ": " .. tostring(err))
			end
		end
	end

	inventoryCache[category.key] = items
	return items
end

-- ─────────────────────────── working-state mutations ───────────────────────────

local function isItemSelected(category, assetId)
	if category.kind == "accessory" then
		return findAccessoryIndex(assetId) ~= nil
	elseif category.kind == "clothing" then
		return working.clothing[category.clothingKey] == assetId
	elseif category.kind == "face" then
		return working.bodyParts.face == assetId
	end
	return false
end

local function onItemClicked(category, item)
	local assetId = type(item) == "table" and item.id or item
	if category.kind == "accessory" then
		local index = findAccessoryIndex(assetId)
		if index then
			table.remove(working.accessories, index)
		else
			local maxAccessories = tonumber(AppearanceConfig.MaxAccessories) or 15
			if #working.accessories >= maxAccessories then
				setStatus(("You can wear at most %d accessories."):format(maxAccessories))
				return
			end
			local isLayered = (type(item) == "table" and item.isLayered == true) or category.isLayered == true
			working.accessories[#working.accessories + 1] = {
				id = assetId,
				type = (type(item) == "table" and item.accessoryType) or category.accessoryType,
				isLayered = isLayered,
				order = isLayered and (#working.accessories + 1) or nil,
				puffiness = isLayered and 1 or nil,
			}
		end
	elseif category.kind == "clothing" then
		local key = category.clothingKey
		working.clothing[key] = working.clothing[key] == assetId and 0 or assetId
	elseif category.kind == "face" then
		working.bodyParts.face = working.bodyParts.face == assetId and 0 or assetId
	end
	sendPreview()
end

local function setSkinTone(hex)
	for _, key in ipairs(SKIN_COLOR_KEYS) do
		working.colors[key] = hex
	end
	sendPreview()
end

-- ─────────────────────────── content rendering ───────────────────────────

local function clearContent()
	for _, connection in ipairs(activeConnections) do
		connection:Disconnect()
	end
	table.clear(activeConnections)
	for _, child in ipairs(contentArea:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function makeEmptyLabel(text)
	local label = makeLabel(contentArea, "Empty", text, 15, COLORS.muted, Enum.Font.GothamMedium)
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	return label
end

local function makeScrollGrid(cellSize, cellPadding)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = responsive.tiny and 3 or 5
	scroll.ScrollBarImageColor3 = Color3.fromRGB(91, 108, 130)
	scroll.Parent = contentArea

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = cellSize
	grid.CellPadding = cellPadding
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll

	return scroll
end

local function updateItemHighlights(category, scroll)
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("ImageButton") then
			local stroke = child:FindFirstChildOfClass("UIStroke")
			if stroke then
				local selected = isItemSelected(category, child:GetAttribute("AssetId"))
				stroke.Color = selected and COLORS.green or Color3.fromRGB(60, 72, 89)
				stroke.Thickness = selected and 2 or 1
			end
		end
	end
end

local function renderItemGrid(category, items)
	if #items == 0 then
		makeEmptyLabel("No owned items found in this category.")
		return
	end

	local itemCell = responsive.itemCell
	local scroll = makeScrollGrid(
		UDim2.fromOffset(itemCell.X, itemCell.Y),
		UDim2.fromOffset(responsive.tiny and 6 or 8, responsive.tiny and 6 or 8)
	)

	for index, item in ipairs(items) do
		local button = Instance.new("ImageButton")
		button.Name = "Item_" .. item.id
		button:SetAttribute("AssetId", item.id)
		button.BackgroundColor3 = COLORS.panelSoft
		button.BorderSizePixel = 0
		button.Image = ("rbxthumb://type=Asset&id=%d&w=150&h=150"):format(item.id)
		button.ScaleType = Enum.ScaleType.Fit
		button.LayoutOrder = index
		button.Parent = scroll
		addCorner(button, 8)
		addStroke(button, Color3.fromRGB(60, 72, 89), 0)

		local nameLabel =
			makeLabel(button, "ItemName", item.name, responsive.tiny and 10 or 11, COLORS.muted, Enum.Font.Gotham)
		nameLabel.AnchorPoint = Vector2.new(0, 1)
		nameLabel.Position = UDim2.new(0, 4, 1, -2)
		nameLabel.Size = UDim2.new(1, -8, 0, responsive.tiny and 20 or 24)
		nameLabel.TextYAlignment = Enum.TextYAlignment.Bottom
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.TextWrapped = true

		button.Activated:Connect(function()
			if busy then
				return
			end
			onItemClicked(category, item)
			updateItemHighlights(category, scroll)
		end)
	end

	updateItemHighlights(category, scroll)
end

local function renderSkinTones()
	local tones = AppearanceConfig.SkinTones
	if type(tones) ~= "table" or #tones == 0 then
		tones = FALLBACK_SKIN_TONES
	end

	local skinCell = responsive.skinCell
	local scroll = makeScrollGrid(
		UDim2.fromOffset(skinCell.X, skinCell.Y),
		UDim2.fromOffset(responsive.tiny and 6 or 8, responsive.tiny and 6 or 8)
	)
	local swatches = {}

	local function updateSwatchHighlights()
		local currentHex = (working.colors.torso or ""):lower()
		for hex, stroke in pairs(swatches) do
			local selected = hex:lower() == currentHex
			stroke.Color = selected and COLORS.text or Color3.fromRGB(60, 72, 89)
			stroke.Thickness = selected and 2 or 1
		end
	end

	for index, tone in ipairs(tones) do
		local hex = tostring(tone):gsub("^#", ""):lower()
		local ok, color = pcall(Color3.fromHex, hex)
		if ok then
			local swatch = Instance.new("TextButton")
			swatch.Name = "Tone_" .. hex
			swatch.BackgroundColor3 = color
			swatch.BorderSizePixel = 0
			swatch.Text = ""
			swatch.AutoButtonColor = true
			swatch.LayoutOrder = index
			swatch.Parent = scroll
			addCorner(swatch, 8)
			swatches[hex] = addStroke(swatch, Color3.fromRGB(60, 72, 89), 0)

			swatch.Activated:Connect(function()
				if busy then
					return
				end
				setSkinTone(hex)
				updateSwatchHighlights()
			end)
		end
	end

	updateSwatchHighlights()
end

local function renderBodySliders()
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Sliders"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = responsive.tiny and 3 or 5
	scroll.Parent = contentArea

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, responsive.tiny and 10 or 14)
	layout.Parent = scroll

	for order, def in ipairs(SCALE_SLIDERS) do
		local min, max = scaleRange(def.key)

		local row = Instance.new("Frame")
		row.Name = "Slider_" .. def.key
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, -8, 0, responsive.tiny and 46 or 52)
		row.LayoutOrder = order
		row.Parent = scroll

		local label =
			makeLabel(row, "Label", def.label, responsive.tiny and 12 or 14, COLORS.text, Enum.Font.GothamMedium)
		label.Size = UDim2.new(0.6, 0, 0, responsive.tiny and 18 or 20)

		local valueLabel =
			makeLabel(row, "Value", "", responsive.tiny and 12 or 14, COLORS.muted, Enum.Font.GothamMedium)
		valueLabel.AnchorPoint = Vector2.new(1, 0)
		valueLabel.Position = UDim2.new(1, 0, 0, 0)
		valueLabel.Size = UDim2.new(0.4, 0, 0, responsive.tiny and 18 or 20)
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right

		local bar = Instance.new("TextButton")
		bar.Name = "Bar"
		bar.BackgroundColor3 = COLORS.panelSoft
		bar.BorderSizePixel = 0
		bar.Text = ""
		bar.AutoButtonColor = false
		bar.AnchorPoint = Vector2.new(0, 1)
		bar.Position = UDim2.new(0, 0, 1, responsive.tiny and -6 or -8)
		bar.Size = UDim2.new(1, 0, 0, responsive.tiny and 10 or 12)
		bar.Parent = row
		addCorner(bar, 6)

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BackgroundColor3 = COLORS.green
		fill.BorderSizePixel = 0
		fill.Parent = bar
		addCorner(fill, 6)

		local function refresh()
			local value = working.scales[def.key] or min
			local alpha = max > min and (value - min) / (max - min) or 0
			fill.Size = UDim2.new(math.clamp(alpha, 0, 1), 0, 1, 0)
			valueLabel.Text = ("%.2f"):format(value)
		end

		local function setFromX(x)
			local alpha = math.clamp((x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)
			local value = math.floor((min + alpha * (max - min)) * 100 + 0.5) / 100
			working.scales[def.key] = value
			if def.key == "width" then
				working.scales.depth = value
			end
			refresh()
			sendPreview()
		end

		local dragging = false
		bar.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = true
				setFromX(input.Position.X)
			end
		end)
		table.insert(
			activeConnections,
			UserInputService.InputChanged:Connect(function(input)
				if
					dragging
					and (
						input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch
					)
				then
					setFromX(input.Position.X)
				end
			end)
		)
		table.insert(
			activeConnections,
			UserInputService.InputEnded:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					dragging = false
				end
			end)
		)

		refresh()
	end
end

local renderOutfits

local function performOutfitAction(action, payload)
	if busy then
		return
	end
	setBusy(true)
	setStatus("Updating outfits...")
	local call = table.pack(pcall(Remotes.OutfitAction.InvokeServer, Remotes.OutfitAction, action, payload or {}))
	setBusy(false)
	if not call[1] then
		setStatus("The outfit server did not respond.")
		return
	end
	local ok, result = call[2], call[3]
	if not ok then
		setStatus(result or "The outfit action failed.")
		return
	end
	result = type(result) == "table" and result or {}
	editorContext.outfits = type(result.outfits) == "table" and result.outfits or editorContext.outfits
	if type(result.appearance) == "table" then
		working = deepCopy(result.appearance)
		ensureWorkingDefaults(working)
	end
	setStatus(result.message or "Outfits updated.")
	if currentCategory and currentCategory.kind == "outfits" then
		renderOutfits()
	end
end

renderOutfits = function()
	clearContent()
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "OutfitManager"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.ScrollBarThickness = responsive.tiny and 3 or 5
	scroll.ScrollBarImageColor3 = Color3.fromRGB(91, 108, 130)
	scroll.Parent = contentArea

	local nameBox = makeTextBox(scroll, "OutfitName", "Name this outfit")
	nameBox.Position = UDim2.fromOffset(0, 0)
	nameBox.Size = UDim2.new(1, -122, 0, 38)
	local saveOutfitButton = makeButton(scroll, "SaveOutfit", "Save", COLORS.green)
	saveOutfitButton.AnchorPoint = Vector2.new(1, 0)
	saveOutfitButton.Position = UDim2.new(1, 0, 0, 0)
	saveOutfitButton.Size = UDim2.fromOffset(112, 38)
	saveOutfitButton.Activated:Connect(function()
		performOutfitAction("save", { name = nameBox.Text, appearance = working })
	end)

	local codeBox = makeTextBox(scroll, "ShareCode", "Enter an outfit share code")
	codeBox.Position = UDim2.fromOffset(0, 50)
	codeBox.Size = UDim2.new(1, -122, 0, 38)
	local applyCodeButton = makeButton(scroll, "ApplyCode", "Use Code", COLORS.panelSoft)
	applyCodeButton.AnchorPoint = Vector2.new(1, 0)
	applyCodeButton.Position = UDim2.new(1, 0, 0, 50)
	applyCodeButton.Size = UDim2.fromOffset(112, 38)
	applyCodeButton.Activated:Connect(function()
		performOutfitAction("apply_code", { code = codeBox.Text })
	end)

	local heading = makeLabel(scroll, "SavedHeading", "SAVED OUTFITS", 11, COLORS.muted, Enum.Font.GothamBold)
	heading.Position = UDim2.fromOffset(0, 102)
	heading.Size = UDim2.new(1, 0, 0, 20)

	local outfits = type(editorContext.outfits) == "table" and editorContext.outfits or {}
	local y = 130
	for index, outfit in ipairs(outfits) do
		local row = Instance.new("Frame")
		row.Name = "Outfit_" .. index
		row.BackgroundColor3 = COLORS.panelSoft
		row.BorderSizePixel = 0
		row.Position = UDim2.fromOffset(0, y)
		row.Size = UDim2.new(1, -6, 0, 76)
		row.Parent = scroll
		addCorner(row, 7)
		addStroke(row, Color3.fromRGB(60, 72, 89), 0.2)

		local outfitName =
			makeLabel(row, "Name", tostring(outfit.name or "Saved Outfit"), 13, COLORS.text, Enum.Font.GothamBold)
		outfitName.Position = UDim2.fromOffset(12, 7)
		outfitName.Size = UDim2.new(1, -178, 0, 22)
		local code = makeTextBox(row, "Code", "")
		code.Position = UDim2.fromOffset(12, 36)
		code.Size = UDim2.new(1, -178, 0, 30)
		code.Text = tostring(outfit.code or "")
		code.TextSize = 12
		local apply = makeButton(row, "Apply", "Wear", COLORS.green)
		apply.Position = UDim2.new(1, -156, 0, 8)
		apply.Size = UDim2.fromOffset(68, 58)
		local remove = makeButton(row, "Delete", "Delete", COLORS.red)
		remove.Position = UDim2.new(1, -80, 0, 8)
		remove.Size = UDim2.fromOffset(68, 58)
		apply.Activated:Connect(function()
			performOutfitAction("apply", { id = outfit.id })
		end)
		remove.Activated:Connect(function()
			performOutfitAction("delete", { id = outfit.id })
		end)
		y = y + 84
	end
	if #outfits == 0 then
		local empty = makeLabel(
			scroll,
			"Empty",
			"No saved outfits yet. Name the clothing you are wearing and press Save.",
			13,
			COLORS.muted,
			Enum.Font.GothamMedium
		)
		empty.Position = UDim2.fromOffset(0, y)
		empty.Size = UDim2.new(1, -6, 0, 58)
		empty.TextXAlignment = Enum.TextXAlignment.Center
		y = y + 66
	end
	scroll.CanvasSize = UDim2.fromOffset(0, y + 8)
end

local function selectCategory(category)
	currentCategory = category
	for key, button in pairs(tabButtons) do
		button.BackgroundColor3 = key == category.key and COLORS.tabActive or COLORS.tabIdle
	end
	clearContent()

	if category.kind == "skin" then
		renderSkinTones()
		return
	elseif category.kind == "body" then
		renderBodySliders()
		return
	elseif category.kind == "outfits" then
		renderOutfits()
		return
	end

	local loadingLabel = makeEmptyLabel("Loading your items...")
	task.spawn(function()
		if not requestInventoryAccess() then
			if currentCategory == category and loadingLabel.Parent then
				loadingLabel.Text = "Inventory access was declined, so owned items can't be listed."
					.. "\n\nYou can still change your skin tone and body shape."
					.. "\nReopen the editor with /appearance to be asked again."
				inventoryAllowed = nil -- allow re-prompting next time a category loads
			end
			return
		end

		local items = loadCategoryItems(category)
		if currentCategory ~= category or not loadingLabel.Parent then
			return -- the player switched tabs while we were fetching
		end
		loadingLabel:Destroy()
		renderItemGrid(category, items)
	end)
end

local function configureCategories(context)
	table.clear(activeCategories)
	local allowed = {}
	for _, key in ipairs(type(context.categories) == "table" and context.categories or {}) do
		allowed[key] = true
	end
	for _, category in ipairs(CATEGORIES) do
		local visible
		if context.mode == "full" then
			visible = category.kind ~= "outfits"
		elseif context.outfitsOnly == true then
			visible = category.kind == "outfits" and context.allowOutfits == true
		else
			visible = allowed[category.key] == true or (category.kind == "outfits" and context.allowOutfits == true)
		end
		local button = tabButtons[category.key]
		if button then
			button.Visible = visible
		end
		if visible then
			activeCategories[#activeCategories + 1] = category
			if button then
				button.LayoutOrder = #activeCategories
			end
		end
	end
end

for order, category in ipairs(CATEGORIES) do
	local button = makeButton(tabsFrame, "Tab_" .. category.key, category.label, COLORS.tabIdle)
	button.TextSize = 13
	button.LayoutOrder = order
	tabButtons[category.key] = button
	button.Activated:Connect(function()
		if isOpen and not busy and currentCategory ~= category then
			selectCategory(category)
		end
	end)
end
configureCategories(editorContext)
updateResponsiveLayout()

-- ─────────────────────────── open / close / save ───────────────────────────

local function closeEditor()
	if not isOpen then
		return
	end
	isOpen = false
	setBusy(false)
	screenGui.Enabled = false
	clearContent()
	anchorCharacter(false)
	restoreCamera()
end

local function openEditor(initialAppearance, isNewCharacter, context)
	editorContext = type(context) == "table" and context
		or { mode = "full", title = "Appearance", allowOutfits = false }
	configureCategories(editorContext)
	working = deepCopy(initialAppearance)
	if type(working) ~= "table" then
		working = {}
	end
	ensureWorkingDefaults(working)

	isOpen = true
	setBusy(false)
	screenGui.Enabled = true
	titleLabel.Text =
		tostring(editorContext.title or (editorContext.mode == "shop" and "Clothing Shop" or "Appearance"))
	saveButton.Text = editorContext.outfitsOnly == true and "Done"
		or editorContext.mode == "shop" and "Save Clothing"
		or "Save Look"
	updateResponsiveLayout()
	setStatus(
		isNewCharacter and "Welcome! Build this character's look, then press Save."
			or editorContext.mode == "shop" and "Only this shop's clothing categories can be changed."
			or "Changes preview live on your character."
	)

	anchorCharacter(true)
	focusCamera()
	if activeCategories[1] then
		selectCategory(activeCategories[1])
	end
end

saveButton.Activated:Connect(function()
	if not isOpen or busy then
		return
	end
	setBusy(true)
	setStatus("Saving...")

	local ok, err = Remotes.SaveAppearance:InvokeServer(working)
	if ok then
		closeEditor()
	else
		setStatus(err or "Failed to save your look.")
		setBusy(false)
	end
end)

cancelButton.Activated:Connect(function()
	if not isOpen or busy then
		return
	end
	Remotes.CancelAppearanceEdit:FireServer()
	closeEditor()
end)

Remotes.OpenAppearanceEditor.OnClientEvent:Connect(function(initialAppearance, isNewCharacter, context)
	if isOpen then
		closeEditor()
	end
	openEditor(initialAppearance, isNewCharacter, context)
end)

local viewportConnection
local function bindResponsiveLayout()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end

	local camera = Workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			updateResponsiveLayout()
			if isOpen and currentCategory then
				selectCategory(currentCategory)
			end
		end)
	end

	updateResponsiveLayout()
end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindResponsiveLayout)
bindResponsiveLayout()
