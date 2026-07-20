-- Player inventory and five-slot hotbar UI.
-- Slots 1-5 are the hotbar; every platform calls the same server UseInventorySlot path.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.QBRemotes)
local QBCoreClient = require(ReplicatedStorage.QBCoreClient)
local QBShared = require(ReplicatedStorage.QBShared.Main)

local player = Players.LocalPlayer

local inventoryConfig = QBShared.Config.Inventory or {}
local SLOT_COUNT = math.max(1, math.floor(tonumber(inventoryConfig.Slots) or 30))
local HOTBAR_SLOTS = math.clamp(math.floor(tonumber(inventoryConfig.HotbarSlots) or 5), 1, SLOT_COUNT)
local MAX_WEIGHT = math.max(0, tonumber(inventoryConfig.MaxWeight) or 120000)

local COLORS = {
	page = Color3.fromRGB(12, 15, 20),
	shell = Color3.fromRGB(27, 32, 40),
	panel = Color3.fromRGB(35, 42, 52),
	panelSoft = Color3.fromRGB(42, 50, 62),
	slot = Color3.fromRGB(24, 29, 37),
	slotHotbar = Color3.fromRGB(30, 39, 44),
	selected = Color3.fromRGB(88, 172, 116),
	hotbarSelected = Color3.fromRGB(93, 153, 212),
	stroke = Color3.fromRGB(78, 91, 109),
	text = Color3.fromRGB(239, 244, 248),
	muted = Color3.fromRGB(158, 170, 184),
	red = Color3.fromRGB(196, 82, 82),
	green = Color3.fromRGB(62, 166, 105),
	blue = Color3.fromRGB(66, 132, 196),
	gold = Color3.fromRGB(185, 132, 60),
}

local currentItems = {}
local otherItems = {}
local otherInventory = nil
local currentAccess = nil
local inventoryOpen = false
local busy = false
local moveMode = false
local selectedSlot = nil
local selectedOtherSlot = nil
local purchaseAmount = 1
local focusedSlot = nil
local selectedHotbarSlot = 1
local loaded = false

local slotViews = {}
local hotbarViews = {}
local otherSlotViews = {}
local rebuildOtherSlots
local updateResponsiveLayout

local function setCoreGuiEnabled(coreGuiType, enabled)
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(coreGuiType, enabled)
			end)
			if ok then
				return
			end
			task.wait(0.25)
		end
	end)
end

local function applyCoreGuiOverrides()
	setCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	setCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end

applyCoreGuiOverrides()

player.CharacterAdded:Connect(function()
	applyCoreGuiOverrides()
end)

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

local function addStroke(parent, color, transparency, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or COLORS.stroke
	stroke.Transparency = transparency or 0
	stroke.Thickness = thickness or 1
	stroke.Parent = parent
	return stroke
end

local function makeInsetBorder(parent, name, inset, thickness, color, transparency)
	local border = {
		Top = Instance.new("Frame"),
		Bottom = Instance.new("Frame"),
		Left = Instance.new("Frame"),
		Right = Instance.new("Frame"),
	}

	for partName, frame in pairs(border) do
		frame.Name = name .. partName
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = transparency or 0
		frame.BorderSizePixel = 0
		frame.Parent = parent
	end

	border.Top.Position = UDim2.fromOffset(inset, inset)
	border.Top.Size = UDim2.new(1, -inset * 2, 0, thickness)

	border.Bottom.AnchorPoint = Vector2.new(0, 1)
	border.Bottom.Position = UDim2.new(0, inset, 1, -inset)
	border.Bottom.Size = UDim2.new(1, -inset * 2, 0, thickness)

	border.Left.Position = UDim2.fromOffset(inset, inset)
	border.Left.Size = UDim2.new(0, thickness, 1, -inset * 2)

	border.Right.AnchorPoint = Vector2.new(1, 0)
	border.Right.Position = UDim2.new(1, -inset, 0, inset)
	border.Right.Size = UDim2.new(0, thickness, 1, -inset * 2)

	return border
end

local function setInsetBorder(border, color, transparency, thickness)
	for _, frame in pairs(border) do
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = transparency
	end

	border.Top.Size = UDim2.new(1, -6, 0, thickness)
	border.Bottom.Size = UDim2.new(1, -6, 0, thickness)
	border.Left.Size = UDim2.new(0, thickness, 1, -6)
	border.Right.Size = UDim2.new(0, thickness, 1, -6)
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

local function makeLabel(parent, name, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Text = text or ""
	label.TextColor3 = color or COLORS.text
	label.TextSize = size or 14
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
	button.BackgroundColor3 = color or COLORS.panelSoft
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Selectable = true
	button.Text = text or ""
	button.TextColor3 = COLORS.text
	button.TextSize = 14
	button.Font = Enum.Font.GothamBold
	button.TextWrapped = true
	button.Parent = parent
	addCorner(button, 8)
	return button
end

local function normalizeSlot(slot)
	slot = tonumber(slot)
	if not slot then
		return nil
	end
	slot = math.floor(slot)
	if slot < 1 or slot > SLOT_COUNT then
		return nil
	end
	return slot
end

local function getDefinition(itemName)
	if type(itemName) ~= "string" then
		return nil
	end
	return QBShared.Items[itemName:lower()]
end

local function normalizeImage(image)
	if type(image) ~= "string" or image == "" then
		return ""
	end
	if image:match("^%d+$") then
		return "rbxassetid://" .. image
	end
	return image
end

local function hydrateItem(rawItem, fallbackSlot)
	if type(rawItem) ~= "table" then
		return nil
	end

	local slot = normalizeSlot(rawItem.slot or fallbackSlot)
	local definition = getDefinition(rawItem.name)
	if not slot or not definition then
		return nil
	end

	return {
		name = definition.name,
		label = rawItem.label or definition.label or definition.name,
		amount = math.max(1, math.floor(tonumber(rawItem.amount) or 1)),
		slot = slot,
		info = type(rawItem.info) == "table" and rawItem.info or {},
		weight = tonumber(rawItem.weight) or tonumber(definition.weight) or 0,
		image = normalizeImage(rawItem.image or definition.image),
		unique = rawItem.unique == true or definition.unique == true,
		useable = rawItem.useable == true or definition.useable == true,
		shouldClose = rawItem.shouldClose ~= false and definition.shouldClose ~= false,
		description = rawItem.description or definition.description or "",
	}
end

local function hydrateOtherItem(rawItem, fallbackSlot, slotCount)
	if type(rawItem) ~= "table" then
		return nil
	end
	local slot = math.floor(tonumber(rawItem.slot or fallbackSlot) or 0)
	local definition = getDefinition(rawItem.name)
	if slot < 1 or slot > math.max(1, slotCount) or not definition then
		return nil
	end
	return {
		name = definition.name,
		label = rawItem.label or definition.label or definition.name,
		amount = math.max(0, math.floor(tonumber(rawItem.amount) or 0)),
		stock = math.max(0, math.floor(tonumber(rawItem.stock or rawItem.amount) or 0)),
		price = math.max(0, math.floor(tonumber(rawItem.price) or 0)),
		slot = slot,
		info = type(rawItem.info) == "table" and rawItem.info or {},
		weight = tonumber(rawItem.weight) or tonumber(definition.weight) or 0,
		image = normalizeImage(rawItem.image or definition.image),
		unique = rawItem.unique == true or definition.unique == true,
		useable = false,
		shouldClose = false,
		description = rawItem.description or definition.description or "",
	}
end

local function setStatus(text, color)
	-- assigned after UI creation
end

local function calculateTotalWeight()
	local total = 0
	for _, item in pairs(currentItems) do
		total += (tonumber(item.weight) or 0) * (tonumber(item.amount) or 1)
	end
	return total
end

local function formatWeight(value)
	return ("%.1f kg"):format((tonumber(value) or 0) / 1000)
end

local function round(value)
	return math.floor(value + 0.5)
end

local function getViewportSize()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function setPaddingOffsets(padding, left, top, right, bottom)
	padding.PaddingLeft = UDim.new(0, left or 0)
	padding.PaddingTop = UDim.new(0, top or 0)
	padding.PaddingRight = UDim.new(0, right or left or 0)
	padding.PaddingBottom = UDim.new(0, bottom or top or 0)
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QBInventory"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 45
screenGui.Parent = player:WaitForChild("PlayerGui")

local transparentSelectionImage = Instance.new("ImageLabel")
transparentSelectionImage.Name = "TransparentSelectionImage"
transparentSelectionImage.BackgroundTransparency = 1
transparentSelectionImage.ImageTransparency = 1
transparentSelectionImage.Size = UDim2.fromOffset(1, 1)
transparentSelectionImage.Parent = screenGui

local hotbar = Instance.new("Frame")
hotbar.Name = "Hotbar"
hotbar.AnchorPoint = Vector2.new(1, 1)
hotbar.Position = UDim2.new(1, -88, 1, -11)
hotbar.Size = UDim2.fromOffset(356, 64)
hotbar.BackgroundTransparency = 1
hotbar.Visible = false
hotbar.Parent = screenGui

local hotbarLayout = Instance.new("UIListLayout")
hotbarLayout.FillDirection = Enum.FillDirection.Horizontal
hotbarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
hotbarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
hotbarLayout.SortOrder = Enum.SortOrder.LayoutOrder
hotbarLayout.Padding = UDim.new(0, 8)
hotbarLayout.Parent = hotbar

local toggleButton = makeButton(screenGui, "InventoryToggle", "Bag", COLORS.blue)
toggleButton.AnchorPoint = Vector2.new(1, 1)
toggleButton.Position = UDim2.new(1, -18, 1, -22)
toggleButton.Size = UDim2.fromOffset(58, 42)
toggleButton.Visible = false
addStroke(toggleButton, Color3.fromRGB(108, 159, 210), 0.2, 1)

local inventoryPanel = Instance.new("Frame")
inventoryPanel.Name = "InventoryPanel"
inventoryPanel.AnchorPoint = Vector2.new(0.5, 0.5)
inventoryPanel.Position = UDim2.fromScale(0.5, 0.48)
inventoryPanel.Size = UDim2.new(0.92, 0, 0.78, 0)
inventoryPanel.BackgroundColor3 = COLORS.shell
inventoryPanel.BorderSizePixel = 0
inventoryPanel.Visible = false
inventoryPanel.Parent = screenGui
addCorner(inventoryPanel, 8)
addStroke(inventoryPanel, COLORS.stroke, 0.08, 1)
local panelPadding = addPadding(inventoryPanel, 16, 14, 16, 16)

local panelConstraint = Instance.new("UISizeConstraint")
panelConstraint.MinSize = Vector2.new(320, 360)
panelConstraint.MaxSize = Vector2.new(640, 560)
panelConstraint.Parent = inventoryPanel

local panelLayout = Instance.new("UIListLayout")
panelLayout.FillDirection = Enum.FillDirection.Vertical
panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
panelLayout.Padding = UDim.new(0, 12)
panelLayout.Parent = inventoryPanel

local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, 38)
header.LayoutOrder = 1
header.Parent = inventoryPanel

local titleLabel = makeLabel(header, "Title", "Inventory", 22, COLORS.text, Enum.Font.GothamBold)
titleLabel.Size = UDim2.new(0.42, 0, 1, 0)
titleLabel.TextWrapped = false

local weightLabel = makeLabel(header, "Weight", "", 13, COLORS.muted, Enum.Font.GothamMedium)
weightLabel.AnchorPoint = Vector2.new(1, 0)
weightLabel.Position = UDim2.new(1, -44, 0, 0)
weightLabel.Size = UDim2.new(0.48, -8, 1, 0)
weightLabel.TextXAlignment = Enum.TextXAlignment.Right
weightLabel.TextWrapped = false
weightLabel.TextTruncate = Enum.TextTruncate.AtEnd

local closeButton = makeButton(header, "Close", "X", COLORS.red)
closeButton.AnchorPoint = Vector2.new(1, 0.5)
closeButton.Position = UDim2.new(1, 0, 0.5, 0)
closeButton.Size = UDim2.fromOffset(34, 34)

local gridShell = Instance.new("Frame")
gridShell.Name = "GridShell"
gridShell.BackgroundColor3 = COLORS.panel
gridShell.BorderSizePixel = 0
gridShell.Size = UDim2.new(1, 0, 1, -124)
gridShell.LayoutOrder = 2
gridShell.Parent = inventoryPanel
addCorner(gridShell, 8)
addStroke(gridShell, Color3.fromRGB(65, 78, 96), 0.25, 1)
local gridPadding = addPadding(gridShell, 10, 10, 10, 10)

local slotsFrame = Instance.new("ScrollingFrame")
slotsFrame.Name = "Slots"
slotsFrame.BackgroundTransparency = 1
slotsFrame.BorderSizePixel = 0
slotsFrame.CanvasSize = UDim2.fromOffset(0, 0)
slotsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
slotsFrame.ScrollBarThickness = 5
slotsFrame.ScrollBarImageColor3 = Color3.fromRGB(91, 108, 130)
slotsFrame.Size = UDim2.fromScale(1, 1)
slotsFrame.Parent = gridShell

local slotsGrid = Instance.new("UIGridLayout")
slotsGrid.CellSize = UDim2.new(0.188, 0, 0, 82)
slotsGrid.CellPadding = UDim2.new(0.01, 0, 0, 6)
slotsGrid.FillDirectionMaxCells = HOTBAR_SLOTS
slotsGrid.SortOrder = Enum.SortOrder.LayoutOrder
slotsGrid.Parent = slotsFrame

local actionBar = Instance.new("Frame")
actionBar.Name = "ActionBar"
actionBar.BackgroundColor3 = COLORS.panel
actionBar.BorderSizePixel = 0
actionBar.Size = UDim2.new(1, 0, 0, 74)
actionBar.LayoutOrder = 3
actionBar.Parent = inventoryPanel
addCorner(actionBar, 8)
addStroke(actionBar, Color3.fromRGB(65, 78, 96), 0.25, 1)
local actionPadding = addPadding(actionBar, 12, 10, 12, 10)

local selectedNameLabel =
	makeLabel(actionBar, "SelectedName", "No item selected", 15, COLORS.text, Enum.Font.GothamBold)
selectedNameLabel.Position = UDim2.fromOffset(0, 0)
selectedNameLabel.Size = UDim2.new(1, -230, 0, 24)
selectedNameLabel.TextWrapped = false
selectedNameLabel.TextTruncate = Enum.TextTruncate.AtEnd

local selectedDescLabel = makeLabel(actionBar, "SelectedDescription", "", 12, COLORS.muted, Enum.Font.Gotham)
selectedDescLabel.Position = UDim2.fromOffset(0, 25)
selectedDescLabel.Size = UDim2.new(1, -230, 0, 28)
selectedDescLabel.TextWrapped = true
selectedDescLabel.TextYAlignment = Enum.TextYAlignment.Top

local moveButton = makeButton(actionBar, "Move", "Move", COLORS.blue)
moveButton.AnchorPoint = Vector2.new(1, 0.5)
moveButton.Position = UDim2.new(1, -144, 0.5, 0)
moveButton.Size = UDim2.fromOffset(70, 44)

local giveButton = makeButton(actionBar, "Give", "Give", COLORS.gold)
giveButton.AnchorPoint = Vector2.new(1, 0.5)
giveButton.Position = UDim2.new(1, -72, 0.5, 0)
giveButton.Size = UDim2.fromOffset(64, 44)

local useButton = makeButton(actionBar, "Use", "Use", COLORS.green)
useButton.AnchorPoint = Vector2.new(1, 0.5)
useButton.Position = UDim2.new(1, 0, 0.5, 0)
useButton.Size = UDim2.fromOffset(64, 44)

local statusLabel = makeLabel(inventoryPanel, "Status", "", 13, COLORS.muted, Enum.Font.GothamMedium)
statusLabel.Size = UDim2.new(1, 0, 0, 18)
statusLabel.LayoutOrder = 4
statusLabel.TextXAlignment = Enum.TextXAlignment.Center
statusLabel.TextWrapped = false
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd

local otherPanel = Instance.new("Frame")
otherPanel.Name = "OtherInventoryPanel"
otherPanel.AnchorPoint = Vector2.new(0.5, 0.5)
otherPanel.Position = UDim2.fromScale(0.73, 0.48)
otherPanel.Size = UDim2.new(0.44, 0, 0.78, 0)
otherPanel.BackgroundColor3 = COLORS.shell
otherPanel.BorderSizePixel = 0
otherPanel.Visible = false
otherPanel.Parent = screenGui
addCorner(otherPanel, 8)
addStroke(otherPanel, COLORS.stroke, 0.08, 1)
local otherPanelPadding = addPadding(otherPanel, 16, 14, 16, 16)

local otherPanelConstraint = Instance.new("UISizeConstraint")
otherPanelConstraint.MinSize = Vector2.new(250, 360)
otherPanelConstraint.MaxSize = Vector2.new(600, 560)
otherPanelConstraint.Parent = otherPanel

local otherPanelLayout = Instance.new("UIListLayout")
otherPanelLayout.FillDirection = Enum.FillDirection.Vertical
otherPanelLayout.SortOrder = Enum.SortOrder.LayoutOrder
otherPanelLayout.Padding = UDim.new(0, 12)
otherPanelLayout.Parent = otherPanel

local otherHeader = Instance.new("Frame")
otherHeader.Name = "Header"
otherHeader.BackgroundTransparency = 1
otherHeader.Size = UDim2.new(1, 0, 0, 38)
otherHeader.LayoutOrder = 1
otherHeader.Parent = otherPanel

local otherTitleLabel = makeLabel(otherHeader, "Title", "External Inventory", 22, COLORS.text, Enum.Font.GothamBold)
otherTitleLabel.Size = UDim2.new(0.7, 0, 1, 0)
otherTitleLabel.TextWrapped = false
otherTitleLabel.TextTruncate = Enum.TextTruncate.AtEnd

local otherTypeLabel = makeLabel(otherHeader, "Type", "", 13, COLORS.muted, Enum.Font.GothamMedium)
otherTypeLabel.AnchorPoint = Vector2.new(1, 0)
otherTypeLabel.Position = UDim2.fromScale(1, 0)
otherTypeLabel.Size = UDim2.new(0.28, 0, 1, 0)
otherTypeLabel.TextXAlignment = Enum.TextXAlignment.Right
otherTypeLabel.TextWrapped = false

local otherGridShell = Instance.new("Frame")
otherGridShell.Name = "GridShell"
otherGridShell.BackgroundColor3 = COLORS.panel
otherGridShell.BorderSizePixel = 0
otherGridShell.Size = UDim2.new(1, 0, 1, -124)
otherGridShell.LayoutOrder = 2
otherGridShell.Parent = otherPanel
addCorner(otherGridShell, 8)
addStroke(otherGridShell, Color3.fromRGB(65, 78, 96), 0.25, 1)
local otherGridPadding = addPadding(otherGridShell, 10, 10, 10, 10)

local otherSlotsFrame = Instance.new("ScrollingFrame")
otherSlotsFrame.Name = "Slots"
otherSlotsFrame.BackgroundTransparency = 1
otherSlotsFrame.BorderSizePixel = 0
otherSlotsFrame.CanvasSize = UDim2.fromOffset(0, 0)
otherSlotsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
otherSlotsFrame.ScrollBarThickness = 5
otherSlotsFrame.ScrollBarImageColor3 = Color3.fromRGB(91, 108, 130)
otherSlotsFrame.Size = UDim2.fromScale(1, 1)
otherSlotsFrame.Parent = otherGridShell

local otherSlotsGrid = Instance.new("UIGridLayout")
otherSlotsGrid.CellSize = UDim2.new(0.188, 0, 0, 82)
otherSlotsGrid.CellPadding = UDim2.new(0.01, 0, 0, 6)
otherSlotsGrid.FillDirectionMaxCells = HOTBAR_SLOTS
otherSlotsGrid.SortOrder = Enum.SortOrder.LayoutOrder
otherSlotsGrid.Parent = otherSlotsFrame

local otherActionBar = Instance.new("Frame")
otherActionBar.Name = "ActionBar"
otherActionBar.BackgroundColor3 = COLORS.panel
otherActionBar.BorderSizePixel = 0
otherActionBar.Size = UDim2.new(1, 0, 0, 74)
otherActionBar.LayoutOrder = 3
otherActionBar.Parent = otherPanel
addCorner(otherActionBar, 8)
addStroke(otherActionBar, Color3.fromRGB(65, 78, 96), 0.25, 1)
local otherActionPadding = addPadding(otherActionBar, 12, 10, 12, 10)

local otherSelectedNameLabel =
	makeLabel(otherActionBar, "SelectedName", "Select a product", 15, COLORS.text, Enum.Font.GothamBold)
otherSelectedNameLabel.Size = UDim2.new(1, -218, 0, 24)
otherSelectedNameLabel.TextWrapped = false
otherSelectedNameLabel.TextTruncate = Enum.TextTruncate.AtEnd

local otherSelectedDescLabel = makeLabel(otherActionBar, "SelectedDescription", "", 12, COLORS.muted, Enum.Font.Gotham)
otherSelectedDescLabel.Position = UDim2.fromOffset(0, 25)
otherSelectedDescLabel.Size = UDim2.new(1, -218, 0, 28)
otherSelectedDescLabel.TextYAlignment = Enum.TextYAlignment.Top

local decreaseButton = makeButton(otherActionBar, "Decrease", "-", COLORS.panelSoft)
decreaseButton.AnchorPoint = Vector2.new(1, 0.5)
decreaseButton.Position = UDim2.new(1, -172, 0.5, 0)
decreaseButton.Size = UDim2.fromOffset(36, 44)

local purchaseAmountLabel = makeLabel(otherActionBar, "PurchaseAmount", "1", 14, COLORS.text, Enum.Font.GothamBold)
purchaseAmountLabel.AnchorPoint = Vector2.new(1, 0.5)
purchaseAmountLabel.Position = UDim2.new(1, -126, 0.5, 0)
purchaseAmountLabel.Size = UDim2.fromOffset(42, 44)
purchaseAmountLabel.TextXAlignment = Enum.TextXAlignment.Center
purchaseAmountLabel.TextWrapped = false

local increaseButton = makeButton(otherActionBar, "Increase", "+", COLORS.panelSoft)
increaseButton.AnchorPoint = Vector2.new(1, 0.5)
increaseButton.Position = UDim2.new(1, -84, 0.5, 0)
increaseButton.Size = UDim2.fromOffset(36, 44)

local buyButton = makeButton(otherActionBar, "Buy", "Buy", COLORS.green)
buyButton.AnchorPoint = Vector2.new(1, 0.5)
buyButton.Position = UDim2.new(1, 0, 0.5, 0)
buyButton.Size = UDim2.fromOffset(76, 44)

local otherStatusLabel = makeLabel(otherPanel, "Status", "", 13, COLORS.muted, Enum.Font.GothamMedium)
otherStatusLabel.Size = UDim2.new(1, 0, 0, 18)
otherStatusLabel.LayoutOrder = 4
otherStatusLabel.TextXAlignment = Enum.TextXAlignment.Center
otherStatusLabel.TextWrapped = false
otherStatusLabel.TextTruncate = Enum.TextTruncate.AtEnd

setStatus = function(text, color)
	statusLabel.Text = text or ""
	statusLabel.TextColor3 = color or COLORS.muted
	otherStatusLabel.Text = text or ""
	otherStatusLabel.TextColor3 = color or COLORS.muted
end

local function firstOccupiedSlot()
	for slot = 1, SLOT_COUNT do
		if currentItems[slot] then
			return slot
		end
	end
	return nil
end

local function updateWeightLabel()
	weightLabel.Text = ("%s / %s"):format(formatWeight(calculateTotalWeight()), formatWeight(MAX_WEIGHT))
end

local function renderSlotView(view, slot, isHotbar)
	local item = currentItems[slot]
	local isSelected = selectedSlot == slot
	local isFocused = inventoryOpen and focusedSlot == slot
	local isHotbarSelected = isHotbar and selectedHotbarSlot == slot

	view.button.BackgroundColor3 = slot <= HOTBAR_SLOTS and COLORS.slotHotbar or COLORS.slot
	setInsetBorder(view.baseBorder, COLORS.stroke, 0.35, 1)
	setInsetBorder(
		view.selectionBorder,
		isSelected and COLORS.selected or COLORS.hotbarSelected,
		(isSelected or isHotbarSelected or isFocused) and 0 or 1,
		isSelected and 2 or 1
	)

	view.number.Text = tostring(slot)
	view.name.Text = item and item.label or ""
	view.amount.Text = item and item.amount > 1 and ("x%d"):format(item.amount) or ""
	view.empty.Visible = item == nil
	view.icon.Visible = item ~= nil and type(item.image) == "string" and item.image ~= ""
	view.icon.Image = view.icon.Visible and item.image or ""
end

local function renderOtherSlotView(view, slot)
	local item = otherItems[slot]
	local isSelected = selectedOtherSlot == slot
	local isFocused = inventoryOpen and focusedSlot == -slot
	view.button.BackgroundColor3 = COLORS.slot
	setInsetBorder(view.baseBorder, COLORS.stroke, 0.35, 1)
	setInsetBorder(view.selectionBorder, COLORS.selected, (isSelected or isFocused) and 0 or 1, isSelected and 2 or 1)
	view.number.Text = tostring(slot)
	view.name.Text = item and item.label or ""
	view.amount.Text = item
			and (otherInventory and otherInventory.type == "shop" and (("$%d · x%d"):format(item.price, item.stock)) or ("x%d"):format(
				item.stock
			))
		or ""
	view.empty.Visible = item == nil
	view.icon.Visible = item ~= nil and type(item.image) == "string" and item.image ~= ""
	view.icon.Image = view.icon.Visible and item.image or ""
end

local function renderOtherInventory()
	otherPanel.Visible = inventoryOpen and otherInventory ~= nil
	if not otherInventory then
		return
	end
	otherTitleLabel.Text = otherInventory.label or "External Inventory"
	otherTypeLabel.Text = otherInventory.type == "shop" and "SHOP" or "CONTAINER"
	for slot, view in pairs(otherSlotViews) do
		renderOtherSlotView(view, slot)
	end

	local selectedItem = selectedOtherSlot and otherItems[selectedOtherSlot] or nil
	local selectedPlayerItem = selectedSlot and currentItems[selectedSlot] or nil
	local actions = otherInventory.actions or {}
	local isPurchase = selectedItem and actions.purchase == true
	local isWithdraw = selectedItem and actions.withdraw == true
	local isDeposit = not selectedItem and selectedPlayerItem and actions.deposit == true
	local actionItem = selectedItem or (isDeposit and selectedPlayerItem) or nil
	local available = selectedItem and selectedItem.stock or selectedPlayerItem and selectedPlayerItem.amount or 0
	local canAct = actionItem and available > 0 and not busy and (isPurchase or isWithdraw or isDeposit)
	if selectedItem then
		purchaseAmount = math.clamp(purchaseAmount, 1, math.max(1, selectedItem.stock))
		otherSelectedNameLabel.Text = otherInventory.type == "shop"
				and ("%s · $%d each"):format(selectedItem.label, selectedItem.price)
			or ("%s x%d"):format(selectedItem.label, selectedItem.stock)
		otherSelectedDescLabel.Text = selectedItem.stock > 0 and selectedItem.description or "Empty"
	elseif isDeposit then
		purchaseAmount = math.clamp(purchaseAmount, 1, math.max(1, selectedPlayerItem.amount))
		otherSelectedNameLabel.Text = ("Deposit %s x%d"):format(selectedPlayerItem.label, selectedPlayerItem.amount)
		otherSelectedDescLabel.Text = "Move this item into the selected container"
	else
		purchaseAmount = 1
		otherSelectedNameLabel.Text = otherInventory.type == "shop" and "Select a product" or "Select an item"
		otherSelectedDescLabel.Text = otherInventory.type == "shop" and ""
			or "Choose a container item to withdraw or a player item to deposit"
	end
	purchaseAmountLabel.Text = tostring(purchaseAmount)
	decreaseButton.Active = canAct and purchaseAmount > 1 or false
	decreaseButton.AutoButtonColor = decreaseButton.Active
	increaseButton.Active = canAct and purchaseAmount < available or false
	increaseButton.AutoButtonColor = increaseButton.Active
	buyButton.Active = canAct or false
	buyButton.AutoButtonColor = buyButton.Active
	buyButton.BackgroundColor3 = buyButton.Active and COLORS.green or Color3.fromRGB(83, 93, 105)
	buyButton.Text = isPurchase and ("Buy $%d"):format(selectedItem.price * purchaseAmount)
		or isWithdraw and "Withdraw"
		or isDeposit and "Deposit"
		or (otherInventory.type == "shop" and "Buy" or "Transfer")
end

local function render()
	for slot, view in pairs(slotViews) do
		renderSlotView(view, slot, false)
	end
	for slot, view in pairs(hotbarViews) do
		renderSlotView(view, slot, true)
	end

	local selectedItem = selectedSlot and currentItems[selectedSlot] or nil
	if selectedItem then
		selectedNameLabel.Text = ("%s%s"):format(
			selectedItem.label,
			selectedItem.amount > 1 and (" x" .. selectedItem.amount) or ""
		)
		selectedDescLabel.Text = selectedItem.description or ""
		moveButton.Active = not busy
		moveButton.AutoButtonColor = not busy
		moveButton.Text = moveMode and "Cancel" or "Move"
		moveButton.BackgroundColor3 = moveMode and COLORS.red or COLORS.blue
		giveButton.Active = not busy and not moveMode
		giveButton.AutoButtonColor = not busy and not moveMode
		giveButton.BackgroundColor3 = not moveMode and COLORS.gold or Color3.fromRGB(83, 93, 105)
		useButton.Active = selectedItem.useable and not busy and not moveMode
		useButton.AutoButtonColor = selectedItem.useable and not busy and not moveMode
		useButton.BackgroundColor3 = selectedItem.useable and not moveMode and COLORS.green
			or Color3.fromRGB(83, 93, 105)
	else
		moveMode = false
		selectedNameLabel.Text = "No item selected"
		selectedDescLabel.Text = ""
		moveButton.Active = false
		moveButton.AutoButtonColor = false
		moveButton.Text = "Move"
		moveButton.BackgroundColor3 = Color3.fromRGB(83, 93, 105)
		giveButton.Active = false
		giveButton.AutoButtonColor = false
		giveButton.BackgroundColor3 = Color3.fromRGB(83, 93, 105)
		useButton.Active = false
		useButton.AutoButtonColor = false
		useButton.BackgroundColor3 = Color3.fromRGB(83, 93, 105)
	end

	updateWeightLabel()
	renderOtherInventory()
end

local function normalizeItems(rawItems)
	local normalized = {}
	if type(rawItems) ~= "table" then
		return normalized
	end

	for key, rawItem in pairs(rawItems) do
		local item = hydrateItem(rawItem, key)
		if item then
			normalized[item.slot] = item
		end
	end
	return normalized
end

local function normalizeOtherItems(rawItems, slotCount)
	local normalized = {}
	if type(rawItems) ~= "table" then
		return normalized
	end
	for key, rawItem in pairs(rawItems) do
		local item = hydrateOtherItem(rawItem, key, slotCount)
		if item then
			normalized[item.slot] = item
		end
	end
	return normalized
end

local function applyItems(rawItems)
	currentItems = normalizeItems(rawItems)
	if selectedSlot and not currentItems[selectedSlot] then
		selectedSlot = nil
		moveMode = false
	end
	render()
end

local function applyPlayerData(playerData)
	if not playerData then
		return
	end
	applyItems(playerData.items)
end

local function clearOtherInventory()
	otherItems = {}
	otherInventory = nil
	selectedOtherSlot = nil
	purchaseAmount = 1
	if rebuildOtherSlots then
		rebuildOtherSlots(0)
	end
end

local function applyInventorySnapshot(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	applyItems(snapshot.items)
	if type(snapshot.other) == "table" then
		otherInventory = snapshot.other
		otherInventory.slots = math.max(1, math.floor(tonumber(otherInventory.slots) or 1))
		otherInventory.actions = type(otherInventory.actions) == "table" and otherInventory.actions or {}
		otherItems = normalizeOtherItems(otherInventory.items, otherInventory.slots)
		currentAccess = type(snapshot.access) == "table" and snapshot.access or currentAccess
		if selectedOtherSlot and not otherItems[selectedOtherSlot] then
			selectedOtherSlot = nil
			purchaseAmount = 1
		end
		if rebuildOtherSlots then
			rebuildOtherSlots(otherInventory.slots)
		end
	else
		clearOtherInventory()
	end
	if updateResponsiveLayout then
		updateResponsiveLayout()
	else
		render()
	end
end

local function callRemote(remote, ...)
	local args = table.pack(...)
	local ok, result, err = pcall(function()
		return remote:InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok then
		return false, tostring(result)
	end
	return result, err
end

local function fetchInventory()
	local snapshot, err = callRemote(Remotes.GetInventory, currentAccess)
	if not snapshot then
		if err then
			setStatus(err, COLORS.red)
		end
		return
	end

	applyInventorySnapshot(snapshot)
end

local function setInventoryOpen(nextOpen, access)
	if not loaded then
		return
	end

	if nextOpen and access ~= nil then
		currentAccess = access
	end
	inventoryOpen = nextOpen
	inventoryPanel.Visible = inventoryOpen
	toggleButton.BackgroundColor3 = inventoryOpen and COLORS.green or COLORS.blue

	if inventoryOpen then
		fetchInventory()
		selectedSlot = selectedSlot or firstOccupiedSlot()
		setStatus("")
		local focusSlot = selectedSlot or 1
		focusedSlot = focusSlot
		if slotViews[focusSlot] then
			GuiService.SelectedObject = slotViews[focusSlot].button
		end
	else
		local closingAccess = currentAccess
		moveMode = false
		focusedSlot = nil
		GuiService.SelectedObject = nil
		currentAccess = nil
		clearOtherInventory()
		if closingAccess then
			Remotes.CloseInventory:FireServer(closingAccess)
		end
	end

	render()
end

local function toggleInventory()
	if inventoryOpen then
		setInventoryOpen(false)
	else
		currentAccess = nil
		setInventoryOpen(true)
	end
end

local function useSlot(slot)
	if busy or not loaded then
		return
	end

	slot = normalizeSlot(slot)
	if not slot then
		return
	end

	local item = currentItems[slot]
	if not item then
		setStatus("That slot is empty.", COLORS.red)
		return
	end

	busy = true
	moveMode = false
	render()
	setStatus("")

	local ok, err = callRemote(Remotes.UseInventorySlot, slot)
	busy = false

	if not ok then
		setStatus(err or "Item could not be used.", COLORS.red)
		render()
		return
	end

	if inventoryOpen and item.shouldClose then
		setInventoryOpen(false)
	else
		fetchInventory()
	end
end

local function moveSelectedItem(toSlot)
	if busy or not selectedSlot or selectedSlot == toSlot then
		return
	end

	busy = true
	render()
	setStatus("")

	local ok, err = callRemote(Remotes.MoveInventoryItem, selectedSlot, toSlot)
	busy = false

	if not ok then
		setStatus(err or "Item could not be moved.", COLORS.red)
		render()
		return
	end

	selectedSlot = toSlot
	moveMode = false
	fetchInventory()
end

local function giveSelectedItem()
	if busy or not loaded or moveMode or not selectedSlot then
		return
	end

	local item = currentItems[selectedSlot]
	if not item then
		setStatus("Select an item to give.", COLORS.red)
		return
	end

	busy = true
	moveMode = false
	render()
	setStatus("")

	local ok, err = callRemote(Remotes.GiveInventoryItem, selectedSlot)
	busy = false

	if not ok then
		setStatus(err or "Item could not be given.", COLORS.red)
		render()
		return
	end

	setStatus(("Gave %s."):format(item.label), COLORS.green)
	fetchInventory()
end

local function handleOtherSlot(slot)
	if busy then
		return
	end
	local item = otherItems[slot]
	selectedOtherSlot = item and slot or nil
	if selectedOtherSlot then
		selectedSlot = nil
		moveMode = false
	end
	purchaseAmount = 1
	setStatus("")
	render()
end

local function adjustPurchaseAmount(delta)
	local item = selectedOtherSlot and otherItems[selectedOtherSlot] or nil
	local playerItem = selectedSlot and currentItems[selectedSlot] or nil
	local available = item and item.stock or playerItem and playerItem.amount or 0
	if busy or available <= 0 then
		return
	end
	purchaseAmount = math.clamp(purchaseAmount + delta, 1, available)
	render()
end

local function purchaseSelectedItem()
	local item = selectedOtherSlot and otherItems[selectedOtherSlot] or nil
	local playerItem = selectedSlot and currentItems[selectedSlot] or nil
	if busy or not currentAccess or not otherInventory then
		return
	end
	local actions = otherInventory.actions or {}
	local action = item and actions.purchase == true and "purchase"
		or item and actions.withdraw == true and "withdraw"
		or not item and playerItem and actions.deposit == true and "deposit"
	if not action then
		setStatus("Select an item that this external inventory can transfer.", COLORS.red)
		return
	end
	local available = item and item.stock or playerItem.amount
	if available <= 0 then
		setStatus("That item is unavailable.", COLORS.red)
		return
	end

	busy = true
	setStatus("")
	render()
	local ok, snapshotOrErr = callRemote(Remotes.InventoryAction, action, {
		access = currentAccess,
		slot = selectedOtherSlot,
		playerSlot = selectedSlot,
		amount = purchaseAmount,
	})
	busy = false
	if not ok then
		setStatus(snapshotOrErr or "The transfer could not be completed.", COLORS.red)
		render()
		return
	end
	setStatus(
		("%s %dx %s."):format(
			action == "purchase" and "Purchased" or action == "withdraw" and "Withdrew" or "Deposited",
			purchaseAmount,
			(item or playerItem).label
		),
		COLORS.green
	)
	purchaseAmount = 1
	if type(snapshotOrErr) == "table" then
		applyInventorySnapshot(snapshotOrErr)
	else
		fetchInventory()
	end
end

local function handleInventorySlot(slot)
	if busy then
		return
	end

	local item = currentItems[slot]
	if moveMode then
		if selectedSlot and selectedSlot ~= slot then
			moveSelectedItem(slot)
			return
		end
		moveMode = false
		setStatus("")
		render()
		return
	end

	selectedSlot = item and slot or nil
	if selectedSlot and otherInventory and otherInventory.actions and otherInventory.actions.deposit == true then
		selectedOtherSlot = nil
		purchaseAmount = 1
	end
	setStatus("")
	render()
end

local function toggleMoveMode()
	if busy or not selectedSlot or not currentItems[selectedSlot] then
		return
	end

	moveMode = not moveMode
	if moveMode then
		setStatus("Select a destination slot.", COLORS.muted)
	else
		setStatus("")
	end
	render()
end

local function setSelectedHotbarSlot(slot)
	selectedHotbarSlot = math.clamp(slot, 1, HOTBAR_SLOTS)
	render()
end

local function makeSlotButton(parent, slot, isHotbar, isOther)
	local button = Instance.new("TextButton")
	button.Name = "Slot_" .. slot
	button.BackgroundColor3 = slot <= HOTBAR_SLOTS and COLORS.slotHotbar or COLORS.slot
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Selectable = true
	button.SelectionImageObject = transparentSelectionImage
	button.Text = ""
	button.LayoutOrder = slot
	button.ClipsDescendants = true
	button.Parent = parent
	addCorner(button, 8)

	if isHotbar then
		button.Size = UDim2.fromOffset(64, 62)
	end

	local baseBorder = makeInsetBorder(button, "BaseBorder", 3, 1, COLORS.stroke, 0.35)
	local selectionBorder = makeInsetBorder(button, "SelectionBorder", 3, 2, COLORS.selected, 1)

	local number = makeLabel(button, "Number", tostring(slot), 12, COLORS.muted, Enum.Font.GothamBold)
	number.Position = UDim2.fromOffset(7, 4)
	number.Size = UDim2.new(0, 24, 0, 18)
	number.TextWrapped = false

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.47)
	icon.Size = UDim2.fromScale(0.56, 0.56)
	icon.BackgroundTransparency = 1
	icon.Image = ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Visible = false
	icon.Parent = button

	local empty = makeLabel(button, "Empty", "", 13, Color3.fromRGB(91, 105, 122), Enum.Font.GothamBold)
	empty.AnchorPoint = Vector2.new(0.5, 0.5)
	empty.Position = UDim2.fromScale(0.5, 0.5)
	empty.Size = UDim2.new(1, -10, 0, 20)
	empty.TextXAlignment = Enum.TextXAlignment.Center
	empty.TextWrapped = false

	local name = makeLabel(button, "ItemName", "", isHotbar and 11 or 12, COLORS.text, Enum.Font.GothamBold)
	name.AnchorPoint = Vector2.new(0.5, 0.5)
	name.Position = UDim2.fromScale(0.5, 0.78)
	name.Size = UDim2.new(1, -10, 0, isHotbar and 20 or 22)
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextWrapped = true
	name.TextTruncate = Enum.TextTruncate.AtEnd

	local amount = makeLabel(button, "Amount", "", 12, COLORS.muted, Enum.Font.GothamBold)
	amount.AnchorPoint = Vector2.new(1, 1)
	amount.Position = UDim2.new(1, -7, 1, -4)
	amount.Size = UDim2.new(0.55, 0, 0, 18)
	amount.TextXAlignment = Enum.TextXAlignment.Right
	amount.TextWrapped = false

	button.Activated:Connect(function()
		if inventoryOpen and isOther then
			handleOtherSlot(slot)
		elseif inventoryOpen then
			handleInventorySlot(slot)
		elseif isHotbar then
			setSelectedHotbarSlot(slot)
			useSlot(slot)
		end
	end)

	button.SelectionGained:Connect(function()
		if inventoryOpen then
			focusedSlot = isOther and -slot or slot
			render()
		end
	end)

	button.SelectionLost:Connect(function()
		local focusKey = isOther and -slot or slot
		if focusedSlot == focusKey then
			focusedSlot = nil
			render()
		end
	end)

	return {
		button = button,
		baseBorder = baseBorder,
		selectionBorder = selectionBorder,
		number = number,
		icon = icon,
		empty = empty,
		name = name,
		amount = amount,
	}
end

rebuildOtherSlots = function(slotCount)
	for _, view in pairs(otherSlotViews) do
		view.button:Destroy()
	end
	otherSlotViews = {}
	for slot = 1, math.max(0, math.floor(tonumber(slotCount) or 0)) do
		otherSlotViews[slot] = makeSlotButton(otherSlotsFrame, slot, false, true)
	end
end

for slot = 1, HOTBAR_SLOTS do
	hotbarViews[slot] = makeSlotButton(hotbar, slot, true)
end

for slot = 1, SLOT_COUNT do
	slotViews[slot] = makeSlotButton(slotsFrame, slot, false)
end

local function applySlotTextScale(view, textSize, labelHeight, inset)
	view.number.TextSize = textSize
	view.number.Position = UDim2.fromOffset(inset, math.max(3, inset - 3))
	view.number.Size = UDim2.new(0, 24, 0, labelHeight)
	view.empty.TextSize = textSize
	view.empty.Size = UDim2.new(1, -inset * 2, 0, labelHeight)
	view.name.TextSize = textSize
	view.name.Size = UDim2.new(1, -inset * 2, 0, labelHeight + 2)
	view.amount.TextSize = textSize
	view.amount.Position = UDim2.new(1, -inset, 1, -math.max(3, inset - 3))
	view.amount.Size = UDim2.new(0.58, 0, 0, labelHeight)
end

updateResponsiveLayout = function()
	local viewport = getViewportSize()
	local compact = viewport.X < 760 or viewport.Y < 560
	local tiny = viewport.X < 520 or viewport.Y < 470
	local hasOther = otherInventory ~= nil

	local panelMargin = tiny and 8 or compact and 12 or 24
	local minPanelSize = tiny and 250 or compact and 280 or 300
	local paneGap = tiny and 5 or compact and 8 or 14
	local maxPanelWidth = hasOther and math.max(140, (viewport.X - panelMargin * 2 - paneGap) / 2)
		or math.max(minPanelSize, viewport.X - panelMargin * 2)
	local maxPanelHeight = math.max(minPanelSize, viewport.Y - panelMargin * 2)
	local desiredPanelWidth = hasOther and viewport.X * 0.45 or viewport.X * (tiny and 0.9 or compact and 0.92 or 0.92)
	local desiredPanelHeight = viewport.Y * (tiny and 0.78 or compact and 0.84 or 0.78)
	local panelWidth = round(
		math.min(hasOther and 600 or 640, maxPanelWidth, math.max(hasOther and 140 or minPanelSize, desiredPanelWidth))
	)
	local panelHeight = round(math.min(560, maxPanelHeight, math.max(minPanelSize, desiredPanelHeight)))

	local constrainedMinWidth = math.min(hasOther and 140 or minPanelSize, panelWidth)
	panelConstraint.MinSize = Vector2.new(constrainedMinWidth, math.min(minPanelSize, panelHeight))
	panelConstraint.MaxSize = Vector2.new(panelWidth, panelHeight)
	otherPanelConstraint.MinSize = Vector2.new(constrainedMinWidth, math.min(minPanelSize, panelHeight))
	otherPanelConstraint.MaxSize = Vector2.new(panelWidth, panelHeight)
	inventoryPanel.Size = UDim2.fromOffset(panelWidth, panelHeight)
	otherPanel.Size = UDim2.fromOffset(panelWidth, panelHeight)
	local centerY = compact and 0.49 or 0.48
	if hasOther then
		local centerOffset = (panelWidth + paneGap) / 2
		inventoryPanel.Position = UDim2.new(0.5, -centerOffset, centerY, 0)
		otherPanel.Position = UDim2.new(0.5, centerOffset, centerY, 0)
	else
		inventoryPanel.Position = UDim2.fromScale(0.5, centerY)
	end

	local panelPadX = tiny and 6 or compact and 9 or 16
	local panelPadTop = tiny and 6 or compact and 9 or 14
	local panelPadBottom = tiny and 7 or compact and 10 or 16
	setPaddingOffsets(panelPadding, panelPadX, panelPadTop, panelPadX, panelPadBottom)
	setPaddingOffsets(otherPanelPadding, panelPadX, panelPadTop, panelPadX, panelPadBottom)

	local layoutGap = tiny and 5 or compact and 7 or 12
	local headerHeight = tiny and 26 or compact and 31 or 38
	local actionHeight = tiny and 48 or compact and 58 or 74
	local statusHeight = tiny and 14 or 18
	local contentHeight = panelHeight - panelPadTop - panelPadBottom
	local gridHeight = math.max(
		tiny and 82 or compact and 112 or 170,
		contentHeight - headerHeight - actionHeight - statusHeight - layoutGap * 3
	)

	panelLayout.Padding = UDim.new(0, layoutGap)
	otherPanelLayout.Padding = UDim.new(0, layoutGap)
	header.Size = UDim2.new(1, 0, 0, headerHeight)
	otherHeader.Size = UDim2.new(1, 0, 0, headerHeight)
	gridShell.Size = UDim2.new(1, 0, 0, gridHeight)
	otherGridShell.Size = UDim2.new(1, 0, 0, gridHeight)
	actionBar.Size = UDim2.new(1, 0, 0, actionHeight)
	otherActionBar.Size = UDim2.new(1, 0, 0, actionHeight)
	statusLabel.Size = UDim2.new(1, 0, 0, statusHeight)
	otherStatusLabel.Size = UDim2.new(1, 0, 0, statusHeight)

	local closeSize = tiny and 26 or compact and 30 or 34
	titleLabel.TextSize = tiny and 16 or compact and 18 or 22
	titleLabel.Size = UDim2.new(tiny and 0.38 or 0.42, 0, 1, 0)
	weightLabel.TextSize = tiny and 10 or compact and 11 or 13
	weightLabel.Position = UDim2.new(1, -(closeSize + 8), 0, 0)
	weightLabel.Size = UDim2.new(tiny and 0.56 or 0.48, -8, 1, 0)
	closeButton.Size = UDim2.fromOffset(closeSize, closeSize)
	otherTitleLabel.TextSize = tiny and 14 or compact and 17 or 22
	otherTypeLabel.TextSize = tiny and 9 or compact and 11 or 13

	local gridPad = tiny and 5 or compact and 7 or 10
	setPaddingOffsets(gridPadding, gridPad, gridPad, gridPad, gridPad)
	setPaddingOffsets(otherGridPadding, gridPad, gridPad, gridPad, gridPad)
	slotsFrame.ScrollBarThickness = tiny and 3 or 5
	otherSlotsFrame.ScrollBarThickness = tiny and 3 or 5
	local gridColumns = tiny and math.min(4, HOTBAR_SLOTS) or HOTBAR_SLOTS
	local gridGapScale = tiny and 0.012 or 0.01
	local cellScale = (1 - gridGapScale * math.max(0, gridColumns - 1)) / gridColumns
	slotsGrid.FillDirectionMaxCells = gridColumns
	slotsGrid.CellSize = UDim2.new(cellScale, 0, 0, tiny and 54 or compact and 66 or 82)
	slotsGrid.CellPadding = UDim2.new(gridGapScale, 0, 0, tiny and 4 or 6)
	otherSlotsGrid.FillDirectionMaxCells = gridColumns
	otherSlotsGrid.CellSize = slotsGrid.CellSize
	otherSlotsGrid.CellPadding = slotsGrid.CellPadding

	local actionPadX = tiny and 6 or compact and 8 or 12
	local actionPadY = tiny and 6 or 10
	setPaddingOffsets(actionPadding, actionPadX, actionPadY, actionPadX, actionPadY)
	setPaddingOffsets(otherActionPadding, actionPadX, actionPadY, actionPadX, actionPadY)
	local actionButtonHeight = tiny and 31 or compact and 36 or 44
	local moveWidth = tiny and 46 or compact and 54 or 70
	local giveWidth = tiny and 46 or compact and 54 or 64
	local useWidth = tiny and 42 or compact and 50 or 64
	local buttonGap = tiny and 4 or 8
	local actionControlsWidth = moveWidth + giveWidth + useWidth + buttonGap * 2 + (tiny and 8 or 14)

	selectedNameLabel.TextSize = tiny and 11 or compact and 13 or 15
	selectedNameLabel.Size = UDim2.new(1, -actionControlsWidth, 0, tiny and 18 or 24)
	selectedDescLabel.TextSize = tiny and 9 or compact and 10 or 12
	selectedDescLabel.Position = UDim2.fromOffset(0, tiny and 18 or 25)
	selectedDescLabel.Size = UDim2.new(1, -actionControlsWidth, 0, tiny and 20 or 28)
	moveButton.TextSize = tiny and 10 or compact and 12 or 14
	moveButton.Position = UDim2.new(1, -(useWidth + giveWidth + buttonGap * 2), 0.5, 0)
	moveButton.Size = UDim2.fromOffset(moveWidth, actionButtonHeight)
	giveButton.TextSize = tiny and 10 or compact and 12 or 14
	giveButton.Position = UDim2.new(1, -(useWidth + buttonGap), 0.5, 0)
	giveButton.Size = UDim2.fromOffset(giveWidth, actionButtonHeight)
	useButton.TextSize = tiny and 10 or compact and 12 or 14
	useButton.Size = UDim2.fromOffset(useWidth, actionButtonHeight)
	statusLabel.TextSize = tiny and 10 or 13
	otherStatusLabel.TextSize = tiny and 10 or 13

	local externalControlWidth = tiny and 132 or compact and 170 or 218
	local externalButtonHeight = actionButtonHeight
	local stepWidth = tiny and 27 or compact and 32 or 36
	local amountWidth = tiny and 28 or compact and 34 or 42
	local buyWidth = tiny and 60 or compact and 68 or 76
	local controlGap = tiny and 3 or compact and 5 or 8
	otherSelectedNameLabel.TextSize = tiny and 10 or compact and 13 or 15
	otherSelectedNameLabel.Size = UDim2.new(1, -externalControlWidth, 0, tiny and 18 or 24)
	otherSelectedDescLabel.TextSize = tiny and 8 or compact and 10 or 12
	otherSelectedDescLabel.Position = UDim2.fromOffset(0, tiny and 18 or 25)
	otherSelectedDescLabel.Size = UDim2.new(1, -externalControlWidth, 0, tiny and 20 or 28)
	buyButton.Size = UDim2.fromOffset(buyWidth, externalButtonHeight)
	increaseButton.Size = UDim2.fromOffset(stepWidth, externalButtonHeight)
	increaseButton.Position = UDim2.new(1, -(buyWidth + controlGap), 0.5, 0)
	purchaseAmountLabel.Size = UDim2.fromOffset(amountWidth, externalButtonHeight)
	purchaseAmountLabel.Position = UDim2.new(1, -(buyWidth + stepWidth + controlGap * 2), 0.5, 0)
	decreaseButton.Size = UDim2.fromOffset(stepWidth, externalButtonHeight)
	decreaseButton.Position = UDim2.new(1, -(buyWidth + stepWidth + amountWidth + controlGap * 3), 0.5, 0)
	buyButton.TextSize = tiny and 9 or compact and 11 or 14

	local sideMargin = tiny and 8 or compact and 12 or 18
	local bottomMargin = tiny and 8 or compact and 12 or 22
	local toggleWidth = tiny and 42 or compact and 48 or 58
	local toggleHeight = tiny and 31 or compact and 35 or 42
	toggleButton.TextSize = tiny and 10 or compact and 12 or 14
	toggleButton.Position = UDim2.new(1, -sideMargin, 1, -bottomMargin)
	toggleButton.Size = UDim2.fromOffset(toggleWidth, toggleHeight)

	local hotbarGap = tiny and 4 or compact and 5 or 8
	local gapCount = math.max(0, HOTBAR_SLOTS - 1)
	local minSlotSize = 32
	local maxSlotSize = tiny and 42 or compact and 50 or 64
	local maxHotbarWidth =
		math.max(HOTBAR_SLOTS * minSlotSize + gapCount * 3, viewport.X - sideMargin * 2 - toggleWidth - hotbarGap)
	local hotbarSlotSize =
		math.clamp(math.floor((maxHotbarWidth - hotbarGap * gapCount) / HOTBAR_SLOTS), minSlotSize, maxSlotSize)
	local hotbarWidth = hotbarSlotSize * HOTBAR_SLOTS + hotbarGap * gapCount

	hotbar.Position = UDim2.new(1, -(sideMargin + toggleWidth + hotbarGap), 1, -bottomMargin)
	hotbar.Size = UDim2.fromOffset(hotbarWidth, hotbarSlotSize)
	hotbarLayout.Padding = UDim.new(0, hotbarGap)

	local inventoryTextSize = tiny and 9 or compact and 10 or 12
	for _, view in pairs(slotViews) do
		applySlotTextScale(view, inventoryTextSize, tiny and 14 or 18, tiny and 5 or 7)
	end
	for _, view in pairs(otherSlotViews) do
		applySlotTextScale(view, inventoryTextSize, tiny and 14 or 18, tiny and 5 or 7)
	end

	local hotbarTextSize = hotbarSlotSize < 44 and 9 or hotbarSlotSize < 54 and 10 or 12
	for _, view in pairs(hotbarViews) do
		view.button.Size = UDim2.fromOffset(hotbarSlotSize, hotbarSlotSize)
		applySlotTextScale(view, hotbarTextSize, hotbarSlotSize < 44 and 13 or 16, hotbarSlotSize < 44 and 4 or 6)
	end

	render()
end

local viewportConnection
local function bindResponsiveLayout()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end

	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveLayout)
	end

	updateResponsiveLayout()
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindResponsiveLayout)
bindResponsiveLayout()

toggleButton.Activated:Connect(toggleInventory)
closeButton.Activated:Connect(function()
	setInventoryOpen(false)
end)
moveButton.Activated:Connect(toggleMoveMode)
giveButton.Activated:Connect(giveSelectedItem)
useButton.Activated:Connect(function()
	if selectedSlot and not moveMode then
		useSlot(selectedSlot)
	end
end)
decreaseButton.Activated:Connect(function()
	adjustPurchaseAmount(-1)
end)
increaseButton.Activated:Connect(function()
	adjustPurchaseAmount(1)
end)
buyButton.Activated:Connect(purchaseSelectedItem)

Remotes.OpenInventory.OnClientEvent:Connect(function(access)
	if not loaded or type(access) ~= "table" then
		return
	end
	setInventoryOpen(true, access)
end)

local keyboardSlots = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.KeypadFour] = 4,
	[Enum.KeyCode.KeypadFive] = 5,
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if not loaded then
		return
	end

	if input.UserInputType == Enum.UserInputType.Keyboard then
		if input.KeyCode == Enum.KeyCode.Tab then
			toggleInventory()
			return
		elseif inventoryOpen and input.KeyCode == Enum.KeyCode.M then
			toggleMoveMode()
			return
		end

		local slot = keyboardSlots[input.KeyCode]
		if slot and slot <= HOTBAR_SLOTS then
			setSelectedHotbarSlot(slot)
			useSlot(slot)
		end
	elseif input.UserInputType == Enum.UserInputType.Gamepad1 then
		if input.KeyCode == Enum.KeyCode.ButtonY then
			toggleInventory()
		elseif not inventoryOpen and input.KeyCode == Enum.KeyCode.DPadLeft then
			setSelectedHotbarSlot(selectedHotbarSlot - 1)
		elseif not inventoryOpen and input.KeyCode == Enum.KeyCode.DPadRight then
			setSelectedHotbarSlot(selectedHotbarSlot + 1)
		elseif not inventoryOpen and input.KeyCode == Enum.KeyCode.DPadDown then
			useSlot(selectedHotbarSlot)
		end
	end
end)

QBCoreClient.OnPlayerLoaded.Event:Connect(function()
	loaded = true
	applyCoreGuiOverrides()
	hotbar.Visible = true
	toggleButton.Visible = true
	applyPlayerData(QBCoreClient.GetPlayerData())
	fetchInventory()
end)

QBCoreClient.OnPlayerDataUpdated.Event:Connect(function(key, value)
	if key == "all" then
		applyPlayerData(value)
	elseif key == "items" then
		applyItems(value)
	end
end)

if QBCoreClient.GetPlayerData() then
	loaded = true
	applyCoreGuiOverrides()
	hotbar.Visible = true
	toggleButton.Visible = true
	applyPlayerData(QBCoreClient.GetPlayerData())
	task.defer(fetchInventory)
end

render()
