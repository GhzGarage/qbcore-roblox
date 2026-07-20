-- Native QBCore-style menu controller for future client resources.
-- Open from another LocalScript with:
-- Players.LocalPlayer.PlayerGui.QBMenu.OpenMenu:Invoke(menuItems, options)
-- or, after this script has loaded: _G.QBMenu.OpenMenu(menuItems, options)

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local QBUITheme = require(ReplicatedStorage.QBUITheme)
local QBUIScale = require(ReplicatedStorage.QBUIScale)

local player = Players.LocalPlayer

local COLORS = QBUITheme.Palette("Utility", {
	shell = Color3.fromRGB(20, 24, 31),
	panel = Color3.fromRGB(29, 35, 44),
	strokeSoft = Color3.fromRGB(55, 67, 83),
	disabled = Color3.fromRGB(82, 91, 104),
	red = Color3.fromRGB(196, 76, 82),
})

local DEFAULT_TITLE = "Menu"
local MENU_WIDTH = 310
local MIN_MENU_WIDTH = 230
local HEADER_HEIGHT = 44
local ROW_HEIGHT = 46
local SECTION_HEIGHT = 24
local MAX_VISIBLE_ROWS = 7

local currentItems = {}
local currentOptions = {}
local currentCallbacks = {}
local menuOpen = false
local firstSelectableButton = nil
local viewportConnection = nil
local shellPosition = UDim2.new(1, -28, 0.5, 0)
local shellHiddenPosition = UDim2.new(1, -12, 0.5, 0)

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
	return QBUIScale.GetViewportSize(workspace.CurrentCamera)
end

local function toText(value, fallback)
	if value == nil then
		return fallback or ""
	end
	return tostring(value)
end

local function normalizeImage(image)
	if type(image) ~= "string" and type(image) ~= "number" then
		return ""
	end

	local value = tostring(image)
	if value == "" then
		return ""
	end
	if value:match("^%d+$") then
		return "rbxassetid://" .. value
	end
	if value:match("^rbxassetid://") or value:match("^rbxthumb://") then
		return value
	end
	return ""
end

local function isCallable(callback)
	return type(callback) == "function"
end

local function safeCall(callback, ...)
	if not isCallable(callback) then
		return true
	end

	local ok, result = pcall(callback, ...)
	if not ok then
		warn("[QBMenu] callback failed: " .. tostring(result))
	end
	return ok, result
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QBMenu"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 68
screenGui.Parent = player:WaitForChild("PlayerGui")

local openMenuFunction = Instance.new("BindableFunction")
openMenuFunction.Name = "OpenMenu"
openMenuFunction.Parent = screenGui

local refreshMenuFunction = Instance.new("BindableFunction")
refreshMenuFunction.Name = "RefreshMenu"
refreshMenuFunction.Parent = screenGui

local isOpenFunction = Instance.new("BindableFunction")
isOpenFunction.Name = "IsOpen"
isOpenFunction.Parent = screenGui

local closeMenuEvent = Instance.new("BindableEvent")
closeMenuEvent.Name = "CloseMenu"
closeMenuEvent.Parent = screenGui

local selectedEvent = Instance.new("BindableEvent")
selectedEvent.Name = "MenuSelected"
selectedEvent.Parent = screenGui

local closedEvent = Instance.new("BindableEvent")
closedEvent.Name = "MenuClosed"
closedEvent.Parent = screenGui

local transparentSelectionImage = Instance.new("ImageLabel")
transparentSelectionImage.Name = "TransparentSelectionImage"
transparentSelectionImage.BackgroundTransparency = 1
transparentSelectionImage.ImageTransparency = 1
transparentSelectionImage.Size = UDim2.fromOffset(1, 1)
transparentSelectionImage.Parent = screenGui

local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.Visible = false
overlay.Parent = screenGui

local shell = Instance.new("Frame")
shell.Name = "Shell"
shell.AnchorPoint = Vector2.new(1, 0.5)
shell.Position = shellPosition
shell.Size = UDim2.fromOffset(MENU_WIDTH, 420)
shell.BackgroundColor3 = COLORS.shell
shell.BorderSizePixel = 0
shell.Active = true
shell.Parent = overlay
addCorner(shell, 8)
addStroke(shell, COLORS.stroke, 0.12, 1)

local shellScale = Instance.new("UIScale")
shellScale.Parent = shell

local shellPadding = addPadding(shell, 12, 12, 12, 12)

local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
header.Parent = shell

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.BackgroundTransparency = 1
titleLabel.Text = DEFAULT_TITLE
titleLabel.TextColor3 = COLORS.text
titleLabel.TextSize = 19
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextYAlignment = Enum.TextYAlignment.Center
titleLabel.TextWrapped = false
titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
titleLabel.Position = UDim2.fromOffset(0, 0)
titleLabel.Size = UDim2.new(1, -44, 0, 28)
titleLabel.Parent = header

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Name = "Subtitle"
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Text = ""
subtitleLabel.TextColor3 = COLORS.muted
subtitleLabel.TextSize = 12
subtitleLabel.Font = Enum.Font.GothamMedium
subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
subtitleLabel.TextYAlignment = Enum.TextYAlignment.Center
subtitleLabel.TextWrapped = false
subtitleLabel.TextTruncate = Enum.TextTruncate.AtEnd
subtitleLabel.Position = UDim2.fromOffset(0, 29)
subtitleLabel.Size = UDim2.new(1, -44, 0, 18)
subtitleLabel.Parent = header

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, 0, 0, 0)
closeButton.Size = UDim2.fromOffset(34, 34)
closeButton.BackgroundColor3 = COLORS.red
closeButton.BorderSizePixel = 0
closeButton.AutoButtonColor = true
closeButton.Selectable = true
closeButton.SelectionImageObject = transparentSelectionImage
closeButton.Text = "X"
closeButton.TextColor3 = COLORS.text
closeButton.TextSize = 13
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = header
addCorner(closeButton, 6)

local listFrame = Instance.new("ScrollingFrame")
listFrame.Name = "List"
listFrame.BackgroundTransparency = 1
listFrame.BorderSizePixel = 0
listFrame.CanvasSize = UDim2.fromOffset(0, 0)
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.ScrollBarThickness = 5
listFrame.ScrollBarImageColor3 = COLORS.stroke
listFrame.Position = UDim2.fromOffset(0, HEADER_HEIGHT)
listFrame.Size = UDim2.new(1, 0, 1, -HEADER_HEIGHT)
listFrame.Parent = shell

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = listFrame

local function clearList()
	firstSelectableButton = nil

	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function firstHeaderItem(items)
	for _, item in ipairs(items) do
		if type(item) == "table" and item.hidden ~= true and item.isMenuHeader == true then
			return item
		end
	end
	return nil
end

local function visibleItemCount(items, skipFirstHeader)
	local count = 0
	for index, item in ipairs(items) do
		if type(item) == "table" and item.hidden ~= true then
			if not (skipFirstHeader and index == 1 and item.isMenuHeader == true) then
				count += 1
			end
		end
	end
	return count
end

local function makeSectionRow(item, layoutOrder)
	local row = Instance.new("Frame")
	row.Name = "Section"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -4, 0, SECTION_HEIGHT)
	row.LayoutOrder = layoutOrder
	row.Parent = listFrame

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Text = toText(item.header or item.title, "")
	label.TextColor3 = COLORS.accent
	label.TextSize = 12
	label.Font = Enum.Font.GothamBold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextWrapped = false
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = row

	return row
end

local function setButtonEnabled(button, enabled)
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.Selectable = enabled
	button.BackgroundColor3 = enabled and COLORS.panel or COLORS.disabled
end

local function makeMenuButton(item, layoutOrder, onActivated)
	local disabled = item.disabled == true or item.isMenuHeader == true
	local button = Instance.new("TextButton")
	button.Name = "Item"
	button.BackgroundColor3 = disabled and COLORS.disabled or COLORS.panel
	button.BorderSizePixel = 0
	button.AutoButtonColor = not disabled
	button.Selectable = not disabled
	button.SelectionImageObject = transparentSelectionImage
	button.Text = ""
	button.Size = UDim2.new(1, -4, 0, ROW_HEIGHT)
	button.LayoutOrder = layoutOrder
	button.ClipsDescendants = true
	button.Parent = listFrame
	addCorner(button, 8)
	addStroke(button, COLORS.strokeSoft, disabled and 0.45 or 0.22, 1)

	local image = normalizeImage(item.icon or item.image)
	local textLeft = image ~= "" and 42 or 10

	if image ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Image = image
		icon.ImageTransparency = disabled and 0.35 or 0
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Position = UDim2.fromOffset(10, 11)
		icon.Size = UDim2.fromOffset(24, 24)
		icon.Parent = button
	end

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Text = toText(item.header or item.title or item.label, "")
	title.TextColor3 = disabled and COLORS.muted or COLORS.text
	title.TextSize = 13
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.TextWrapped = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Position = UDim2.fromOffset(textLeft, 5)
	title.Size = UDim2.new(1, -(textLeft + 34), 0, 19)
	title.Parent = button

	local description = Instance.new("TextLabel")
	description.Name = "Description"
	description.BackgroundTransparency = 1
	description.Text = toText(item.txt or item.description, "")
	description.TextColor3 = COLORS.muted
	description.TextSize = 11
	description.Font = Enum.Font.GothamMedium
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextWrapped = true
	description.TextTruncate = Enum.TextTruncate.AtEnd
	description.Position = UDim2.fromOffset(textLeft, 25)
	description.Size = UDim2.new(1, -(textLeft + 34), 0, 18)
	description.Parent = button

	local marker = Instance.new("TextLabel")
	marker.Name = "Marker"
	marker.BackgroundTransparency = 1
	marker.Text = disabled and "" or ">"
	marker.TextColor3 = COLORS.accent
	marker.TextSize = 15
	marker.Font = Enum.Font.GothamBold
	marker.TextXAlignment = Enum.TextXAlignment.Center
	marker.TextYAlignment = Enum.TextYAlignment.Center
	marker.AnchorPoint = Vector2.new(1, 0.5)
	marker.Position = UDim2.new(1, -10, 0.5, 0)
	marker.Size = UDim2.fromOffset(14, 22)
	marker.Parent = button

	setButtonEnabled(button, not disabled)

	if not disabled then
		if not firstSelectableButton then
			firstSelectableButton = button
		end

		button.Activated:Connect(onActivated)
	end

	return button
end

local function getMenuTitle(items, options, skipFirstHeader)
	if type(options) == "table" and options.title ~= nil then
		return toText(options.title, DEFAULT_TITLE)
	end

	if skipFirstHeader and type(items[1]) == "table" then
		return toText(items[1].header or items[1].title, DEFAULT_TITLE)
	end

	local headerItem = firstHeaderItem(items)
	if headerItem then
		return toText(headerItem.header or headerItem.title, DEFAULT_TITLE)
	end

	return DEFAULT_TITLE
end

local function shouldCloseAfterSelect(item)
	if item.shouldClose == false or item.keepOpen == true then
		return false
	end

	local params = type(item.params) == "table" and item.params or {}
	if params.shouldClose == false or params.keepOpen == true then
		return false
	end

	return true
end

local function fireRemoteOrBindable(target, args)
	if typeof(target) ~= "Instance" then
		return false
	end

	if target:IsA("RemoteEvent") then
		target:FireServer(args)
		return true
	elseif target:IsA("BindableEvent") then
		target:Fire(args)
		return true
	elseif target:IsA("BindableFunction") then
		target:Invoke(args)
		return true
	end

	return false
end

local function findReplicatedRemote(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end

	local direct = ReplicatedStorage:FindFirstChild(name)
	if direct and direct:IsA("RemoteEvent") then
		return direct
	end

	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	local nested = remotesFolder and remotesFolder:FindFirstChild(name)
	if nested and nested:IsA("RemoteEvent") then
		return nested
	end

	local qbRemotesFolder = ReplicatedStorage:FindFirstChild("QBRemoteInstances")
	local qbNested = qbRemotesFolder and qbRemotesFolder:FindFirstChild(name)
	if qbNested and qbNested:IsA("RemoteEvent") then
		return qbNested
	end

	return nil
end

local function runMenuAction(item)
	local params = type(item.params) == "table" and item.params or {}
	local args = params.args
	if args == nil then
		args = item.args
	end

	selectedEvent:Fire(params.event, args, item)

	local action = params.action or params.callback or item.action or item.callback
	if isCallable(action) then
		safeCall(action, args, item)
	end

	if fireRemoteOrBindable(params.target or params.remote, args) then
		return
	end

	if params.isServer == true then
		local remote = findReplicatedRemote(params.event)
		if remote then
			remote:FireServer(args)
			return
		end
	end
end

local function updateResponsiveLayout()
	local viewport = getViewportSize()
	local compact = viewport.X < 560 or viewport.Y < 500
	local scale = QBUIScale.FromViewport(viewport, QBUIScale.Profiles.Dialog)
	local margin = compact and 8 or 22
	local rightMargin = compact and 10 or 30
	local availableWidth = math.max(MIN_MENU_WIDTH, (viewport.X - margin * 2) / scale)
	local width = round(math.clamp(MENU_WIDTH, MIN_MENU_WIDTH, availableWidth))
	local visibleRows =
		math.clamp(visibleItemCount(currentItems, currentOptions.skipFirstHeader) + 0.5, 2, MAX_VISIBLE_ROWS)
	local maxHeight = math.max(188, (viewport.Y - margin * 2) / scale)
	local desiredHeight = HEADER_HEIGHT + 10 + visibleRows * (ROW_HEIGHT + 6)
	local height = round(math.min(maxHeight, math.max(174, desiredHeight)))
	local pad = compact and 8 or 10
	local headerHeight = compact and 38 or HEADER_HEIGHT
	local hiddenOffset = compact and 12 or 18

	shellPosition = UDim2.new(1, -rightMargin, 0.5, 0)
	shellHiddenPosition = UDim2.new(1, -(rightMargin - hiddenOffset), 0.5, 0)

	shellScale.Scale = scale
	shell.Size = UDim2.fromOffset(width, height)
	shell.Position = shellPosition
	setPaddingOffsets(shellPadding, pad, pad, pad, pad)
	header.Size = UDim2.new(1, 0, 0, headerHeight)
	listFrame.Position = UDim2.fromOffset(0, headerHeight)
	listFrame.Size = UDim2.new(1, 0, 1, -headerHeight)
	listFrame.ScrollBarThickness = compact and 3 or 5
	listLayout.Padding = UDim.new(0, compact and 5 or 6)
	titleLabel.TextSize = compact and 14 or 16
	titleLabel.Size = UDim2.new(1, -(compact and 34 or 38), 0, compact and 22 or 24)
	subtitleLabel.TextSize = compact and 10 or 11
	subtitleLabel.Position = UDim2.fromOffset(0, compact and 22 or 25)
	subtitleLabel.Size = UDim2.new(1, -(compact and 34 or 38), 0, compact and 14 or 16)
	closeButton.TextSize = compact and 11 or 12
	closeButton.Size = UDim2.fromOffset(compact and 26 or 30, compact and 26 or 30)
end

local function renderMenu()
	clearList()

	local skipFirstHeader = currentOptions.skipFirstHeader == true
	titleLabel.Text = getMenuTitle(currentItems, currentOptions, skipFirstHeader)
	subtitleLabel.Text = toText(currentOptions.subtitle or currentOptions.txt or currentOptions.description, "")
	subtitleLabel.Visible = subtitleLabel.Text ~= ""

	local layoutOrder = 0
	for index, item in ipairs(currentItems) do
		if type(item) == "table" and item.hidden ~= true then
			if not (skipFirstHeader and index == 1 and item.isMenuHeader == true) then
				layoutOrder += 1
				if item.isMenuHeader == true then
					makeSectionRow(item, layoutOrder)
				else
					makeMenuButton(item, layoutOrder, function()
						runMenuAction(item)
						if shouldCloseAfterSelect(item) then
							_G.QBMenu.CloseMenu()
						end
					end)
				end
			end
		end
	end

	updateResponsiveLayout()

	GuiService.SelectedObject = nil
end

local function setMenuOpen(nextOpen, skipCallback)
	if menuOpen == nextOpen then
		return true
	end

	menuOpen = nextOpen
	overlay.Visible = menuOpen

	if menuOpen then
		updateResponsiveLayout()
		overlay.BackgroundTransparency = 1
		shell.Position = shellHiddenPosition
		TweenService:Create(shell, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = shellPosition,
		}):Play()
		GuiService.SelectedObject = nil
	else
		GuiService.SelectedObject = nil
		if not skipCallback then
			safeCall(currentCallbacks.onClose)
		end
		closedEvent:Fire()
	end

	return true
end

local function openMenu(items, options)
	if type(items) ~= "table" then
		warn("[QBMenu] OpenMenu expected a table of menu items.")
		return false
	end

	currentItems = items
	currentOptions = type(options) == "table" and options or {}
	currentOptions.skipFirstHeader = currentOptions.skipFirstHeader ~= false
	currentCallbacks = {
		onClose = currentOptions.onClose,
	}

	renderMenu()
	return setMenuOpen(true, true)
end

local function refreshMenu(items, options)
	if type(items) == "table" then
		currentItems = items
	end
	if type(options) == "table" then
		for key, value in pairs(options) do
			currentOptions[key] = value
		end
	end

	renderMenu()
	return true
end

local function closeMenu()
	return setMenuOpen(false, false)
end

local QBMenuApi = {
	OpenMenu = openMenu,
	RefreshMenu = refreshMenu,
	CloseMenu = closeMenu,
	IsOpen = function()
		return menuOpen
	end,
	Selected = selectedEvent,
	Closed = closedEvent,
}

_G.QBMenu = QBMenuApi

openMenuFunction.OnInvoke = function(items, options)
	return openMenu(items, options)
end

refreshMenuFunction.OnInvoke = function(items, options)
	return refreshMenu(items, options)
end

isOpenFunction.OnInvoke = function()
	return menuOpen
end

closeMenuEvent.Event:Connect(closeMenu)

closeButton.Activated:Connect(closeMenu)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not menuOpen then
		return
	end

	if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Escape then
		closeMenu()
	elseif input.UserInputType == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonB then
		closeMenu()
	end
end)

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
