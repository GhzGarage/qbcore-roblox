-- Native Roblox admin panel inspired by the user's qb-admin resource.
-- All mutations go through AdminService; this LocalScript only renders and requests.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.QBRemotes)
local QBCoreClient = require(ReplicatedStorage.QBCoreClient)

local player = Players.LocalPlayer

local COLORS = {
	backdrop = Color3.fromRGB(7, 9, 12),
	shell = Color3.fromRGB(18, 21, 27),
	sidebar = Color3.fromRGB(14, 17, 23),
	panel = Color3.fromRGB(28, 33, 42),
	panelSoft = Color3.fromRGB(35, 41, 51),
	input = Color3.fromRGB(15, 18, 24),
	stroke = Color3.fromRGB(70, 80, 96),
	strokeSoft = Color3.fromRGB(48, 57, 70),
	text = Color3.fromRGB(240, 243, 246),
	muted = Color3.fromRGB(156, 167, 182),
	accent = Color3.fromRGB(235, 184, 76),
	accentDark = Color3.fromRGB(136, 98, 34),
	blue = Color3.fromRGB(67, 133, 194),
	green = Color3.fromRGB(67, 158, 102),
	red = Color3.fromRGB(191, 75, 75),
	orange = Color3.fromRGB(205, 130, 58),
	disabled = Color3.fromRGB(78, 86, 98),
}

local PAGES = {
	"Dashboard",
	"Players",
	"Items",
	"Jobs",
	"Crews",
	"Logs",
	"Reports",
	"Chat",
	"Environment",
	"Developer",
	"Vehicles",
	"Leaderboard",
}

local currentPage = "Dashboard"
local context = nil
local loaded = false
local menuOpen = false
local busy = false
local selectedUserId = nil
local leaderboardMetric = "wealth"
local leaderboardSearchQuery = ""
local responsive = {
	compact = false,
	tiny = false,
	scale = 1,
}

local tabButtons = {}
local overlay
local addVerticalLayout
local activeDropdownPopup = nil

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
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function responsiveTextSize(size)
	return round((size or 14) / (math.max(responsive.scale, 0.01) ^ 0.55))
end

local function makeLabel(parent, name, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Text = text or ""
	label.TextColor3 = color or COLORS.text
	label.TextSize = responsiveTextSize(size or 14)
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
	button.TextSize = responsiveTextSize(13)
	button.Font = Enum.Font.GothamBold
	button.TextWrapped = true
	button.Parent = parent
	addCorner(button, 6)
	return button
end

local function makeTextBox(parent, name, placeholder, defaultText)
	local box = Instance.new("TextBox")
	box.Name = name
	box.BackgroundColor3 = COLORS.input
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Gotham
	box.PlaceholderColor3 = COLORS.muted
	box.PlaceholderText = placeholder or ""
	box.Text = defaultText or ""
	box.TextColor3 = COLORS.text
	box.TextSize = responsiveTextSize(13)
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextWrapped = false
	box.Parent = parent
	addCorner(box, 6)
	addStroke(box, COLORS.strokeSoft, 0.15, 1)
	addPadding(box, 10, 0, 10, 0)
	return box
end

local function closeDropdownPopup()
	if activeDropdownPopup then
		activeDropdownPopup:Destroy()
		activeDropdownPopup = nil
	end
end

local function makeDropdown(parent, name, options, selectedValue, onSelected)
	local dropdown = {
		options = options or {},
		value = selectedValue,
	}

	local button = makeButton(parent, name, "", COLORS.input)
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.TextWrapped = false
	button.TextTruncate = Enum.TextTruncate.AtEnd
	addStroke(button, COLORS.strokeSoft, 0.15, 1)
	addPadding(button, 10, 0, 10, 0)
	dropdown.button = button

	local function findOption(value)
		for _, option in ipairs(dropdown.options) do
			if option.value == value then
				return option
			end
		end
		return dropdown.options[1]
	end

	function dropdown.setSelected(value, silent)
		local option = findOption(value)
		dropdown.value = option and option.value or nil
		button.Text = option and (option.label .. "  v") or "No options"
		button.Active = option ~= nil
		button.AutoButtonColor = option ~= nil
		if option and not silent and onSelected then
			onSelected(option.value, option)
		end
	end

	function dropdown.setOptions(nextOptions, nextValue)
		dropdown.options = nextOptions or {}
		dropdown.setSelected(nextValue or (dropdown.options[1] and dropdown.options[1].value), true)
	end

	function dropdown.getValue()
		return dropdown.value
	end

	local function openOptions()
		if #dropdown.options == 0 then
			closeDropdownPopup()
			return
		end

		closeDropdownPopup()

		local optionHeight = responsive.tiny and 28 or 32
		local visibleOptions = math.min(#dropdown.options, 6)
		local popupHeight = visibleOptions * optionHeight + 8
		local absolutePosition = button.AbsolutePosition
		local absoluteSize = button.AbsoluteSize
		local viewport = getViewportSize()
		local x = math.clamp(round(absolutePosition.X), 8, math.max(8, round(viewport.X - absoluteSize.X - 8)))
		local belowY = round(absolutePosition.Y + absoluteSize.Y + 4)
		local aboveY = round(absolutePosition.Y - popupHeight - 4)
		local y = belowY
		if y + popupHeight > viewport.Y - 8 and aboveY > 8 then
			y = aboveY
		end

		local popup = Instance.new("ScrollingFrame")
		popup.Name = name .. "Options"
		popup.BackgroundColor3 = COLORS.input
		popup.BorderSizePixel = 0
		popup.CanvasSize = UDim2.fromOffset(0, 0)
		popup.AutomaticCanvasSize = Enum.AutomaticSize.Y
		popup.ScrollBarThickness = #dropdown.options > visibleOptions and 4 or 0
		popup.ScrollBarImageColor3 = COLORS.stroke
		popup.Position = UDim2.fromOffset(x, y)
		popup.Size = UDim2.fromOffset(round(absoluteSize.X), popupHeight)
		popup.ZIndex = 200
		popup.Parent = overlay
		addCorner(popup, 6)
		addStroke(popup, COLORS.stroke, 0.05, 1)
		addPadding(popup, 4, 4, 4, 4)
		addVerticalLayout(popup, 4)

		activeDropdownPopup = popup

		for index, option in ipairs(dropdown.options) do
			local selected = option.value == dropdown.value
			local optionButton = makeButton(
				popup,
				"Option_" .. tostring(index),
				option.label,
				selected and COLORS.accentDark or COLORS.panelSoft
			)
			optionButton.Size = UDim2.new(1, -2, 0, optionHeight)
			optionButton.ZIndex = 201
			optionButton.TextXAlignment = Enum.TextXAlignment.Left
			optionButton.TextWrapped = false
			optionButton.TextTruncate = Enum.TextTruncate.AtEnd
			addPadding(optionButton, 8, 0, 8, 0)
			optionButton.Activated:Connect(function()
				dropdown.setSelected(option.value, false)
				closeDropdownPopup()
			end)
		end
	end

	button.Activated:Connect(function()
		if activeDropdownPopup and activeDropdownPopup.Name == name .. "Options" then
			closeDropdownPopup()
		else
			openOptions()
		end
	end)

	dropdown.setSelected(selectedValue or (dropdown.options[1] and dropdown.options[1].value), true)
	return dropdown
end

local function makePanel(parent, name, height)
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.BackgroundColor3 = COLORS.panel
	panel.BorderSizePixel = 0
	panel.Size = UDim2.new(1, -6, 0, height)
	panel.Parent = parent
	addCorner(panel, 8)
	addStroke(panel, COLORS.strokeSoft, 0.2, 1)
	addPadding(
		panel,
		responsive.tiny and 9 or 14,
		responsive.tiny and 9 or 12,
		responsive.tiny and 9 or 14,
		responsive.tiny and 9 or 12
	)
	return panel
end

function addVerticalLayout(parent, padding)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding or 8)
	layout.Parent = parent
	return layout
end

local function addHorizontalLayout(parent, padding)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding or 8)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = parent
	return layout
end

local function clearGuiObjects(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function trim(text)
	if type(text) ~= "string" then
		return ""
	end
	return text:match("^%s*(.-)%s*$") or ""
end

local function formatMoney(value)
	local formatted = tostring(math.floor(tonumber(value) or 0))
	while true do
		local nextFormatted, replacements = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = nextFormatted
		if replacements == 0 then
			break
		end
	end
	return "$" .. formatted
end

local function formatWeight(value)
	return ("%.1f kg"):format((tonumber(value) or 0) / 1000)
end

local function findCatalogRecord(records, name)
	for _, record in ipairs(records or {}) do
		if record.name == name then
			return record
		end
	end
	return records and records[1] or nil
end

local function findCatalogGrade(record, gradeLevel)
	local targetLevel = tonumber(gradeLevel)
	for _, grade in ipairs((record and record.grades) or {}) do
		if grade.grade == tostring(gradeLevel) or (targetLevel and tonumber(grade.level) == targetLevel) then
			return grade
		end
	end
	return record and record.grades and record.grades[1] or nil
end

local function makeCatalogOptions(records)
	local options = {}
	for _, record in ipairs(records or {}) do
		options[#options + 1] = {
			value = record.name,
			label = ("%s (%s)"):format(record.label or record.name, record.name),
		}
	end
	return options
end

local function makeGradeOptions(record)
	local options = {}
	for _, grade in ipairs((record and record.grades) or {}) do
		local label = ("Grade %s: %s"):format(tostring(grade.grade), tostring(grade.name))
		if tonumber(grade.payment) and tonumber(grade.payment) > 0 then
			label = ("%s | $%d"):format(label, tonumber(grade.payment))
		end
		if grade.isboss then
			label = label .. " | boss"
		end
		options[#options + 1] = {
			value = grade.grade,
			label = label,
		}
	end
	return options
end

local function firstPlayer()
	if not context or type(context.players) ~= "table" then
		return nil
	end
	return context.players[1]
end

local function findPlayer(userId)
	if not context or type(context.players) ~= "table" then
		return nil
	end
	for _, info in ipairs(context.players) do
		if info.userId == userId then
			return info
		end
	end
	return nil
end

local function selectedPlayer()
	local selected = selectedUserId and findPlayer(selectedUserId) or nil
	if not selected then
		selected = findPlayer(player.UserId) or firstPlayer()
		selectedUserId = selected and selected.userId or nil
	end
	return selected
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QBAdmin"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 62
screenGui.Parent = player:WaitForChild("PlayerGui")

overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = COLORS.backdrop
overlay.BackgroundTransparency = 0.22
overlay.Visible = false
overlay.Parent = screenGui

local shell = Instance.new("Frame")
shell.Name = "Shell"
shell.AnchorPoint = Vector2.new(0.5, 0.5)
shell.Position = UDim2.fromScale(0.5, 0.5)
shell.Size = UDim2.new(0.92, 0, 0.82, 0)
shell.BackgroundColor3 = COLORS.shell
shell.BorderSizePixel = 0
shell.Parent = overlay
addCorner(shell, 8)
addStroke(shell, COLORS.stroke, 0.08, 1)

local shellScale = Instance.new("UIScale")
shellScale.Parent = shell

local shellConstraint = Instance.new("UISizeConstraint")
shellConstraint.MinSize = Vector2.new(360, 430)
shellConstraint.MaxSize = Vector2.new(1080, 680)
shellConstraint.Parent = shell

local shellLayout = addHorizontalLayout(shell, 0)
shellLayout.VerticalAlignment = Enum.VerticalAlignment.Top

local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.BackgroundColor3 = COLORS.sidebar
sidebar.BorderSizePixel = 0
sidebar.Size = UDim2.new(0, 178, 1, 0)
sidebar.LayoutOrder = 1
sidebar.Parent = shell
addCorner(sidebar, 8)
local sidebarPadding = addPadding(sidebar, 12, 12, 12, 12)

local sidebarLayout = addVerticalLayout(sidebar, 10)

local brand = Instance.new("Frame")
brand.Name = "Brand"
brand.BackgroundTransparency = 1
brand.Size = UDim2.new(1, 0, 0, 54)
brand.LayoutOrder = 1
brand.Parent = sidebar

local brandTitle = makeLabel(brand, "Title", "Admin Panel", 18, COLORS.text, Enum.Font.GothamBold)
brandTitle.Size = UDim2.new(1, 0, 0, 28)
brandTitle.TextWrapped = false
brandTitle.TextTruncate = Enum.TextTruncate.AtEnd

local brandRank = makeLabel(brand, "Rank", "", 12, COLORS.accent, Enum.Font.GothamBold)
brandRank.Position = UDim2.fromOffset(0, 28)
brandRank.Size = UDim2.new(1, 0, 0, 20)
brandRank.TextWrapped = false
brandRank.TextTruncate = Enum.TextTruncate.AtEnd

local tabs = Instance.new("ScrollingFrame")
tabs.Name = "Tabs"
tabs.BackgroundTransparency = 1
tabs.BorderSizePixel = 0
tabs.CanvasSize = UDim2.fromOffset(0, 0)
tabs.AutomaticCanvasSize = Enum.AutomaticSize.Y
tabs.ScrollBarThickness = 4
tabs.ScrollBarImageColor3 = COLORS.stroke
tabs.Size = UDim2.new(1, 0, 1, -64)
tabs.LayoutOrder = 2
tabs.Parent = sidebar

local tabsLayout = addVerticalLayout(tabs, 6)

local main = Instance.new("Frame")
main.Name = "Main"
main.BackgroundTransparency = 1
main.Size = UDim2.new(1, -178, 1, 0)
main.LayoutOrder = 2
main.Parent = shell
local mainPadding = addPadding(main, 16, 14, 16, 16)

local mainLayout = addVerticalLayout(main, 12)

local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, 46)
header.LayoutOrder = 1
header.Parent = main

local pageTitle = makeLabel(header, "PageTitle", currentPage, 24, COLORS.text, Enum.Font.GothamBold)
pageTitle.Size = UDim2.new(0.42, 0, 1, 0)
pageTitle.TextWrapped = false
pageTitle.TextTruncate = Enum.TextTruncate.AtEnd

local statusLabel = makeLabel(header, "Status", "", 12, COLORS.muted, Enum.Font.GothamMedium)
statusLabel.AnchorPoint = Vector2.new(1, 0)
statusLabel.Position = UDim2.new(1, -88, 0, 0)
statusLabel.Size = UDim2.new(0.46, -12, 1, 0)
statusLabel.TextXAlignment = Enum.TextXAlignment.Right
statusLabel.TextWrapped = false
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd

local refreshButton = makeButton(header, "Refresh", "Refresh", COLORS.panelSoft)
refreshButton.AnchorPoint = Vector2.new(1, 0.5)
refreshButton.Position = UDim2.new(1, -42, 0.5, 0)
refreshButton.Size = UDim2.fromOffset(78, 34)

local closeButton = makeButton(header, "Close", "X", COLORS.red)
closeButton.AnchorPoint = Vector2.new(1, 0.5)
closeButton.Position = UDim2.new(1, 0, 0.5, 0)
closeButton.Size = UDim2.fromOffset(34, 34)

local body = Instance.new("ScrollingFrame")
body.Name = "Body"
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.CanvasSize = UDim2.fromOffset(0, 0)
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.ScrollBarThickness = 5
body.ScrollBarImageColor3 = COLORS.stroke
body.Size = UDim2.new(1, 0, 1, -58)
body.LayoutOrder = 2
body.Parent = main

local bodyLayout = addVerticalLayout(body, 10)

local function setStatus(text, color)
	statusLabel.Text = text or ""
	statusLabel.TextColor3 = color or COLORS.muted
end

local function cleanZero(value)
	value = tonumber(value) or 0
	return math.abs(value) < 0.005 and 0 or value
end

local function formatCoord(value)
	return ("%.2f"):format(cleanZero(value))
end

local function formatHeading(value)
	return ("%.1f"):format(cleanZero(value))
end

local function getCharacterTransform()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end

	local _, yaw = root.CFrame:ToOrientation()
	local heading = math.deg(yaw) % 360
	local position = root.Position

	return {
		x = position.X,
		y = position.Y,
		z = position.Z,
		heading = heading,
	}
end

local function selectTextBox(box, statusText)
	if not box then
		return
	end

	box:CaptureFocus()
	GuiService.SelectedObject = box
	task.defer(function()
		box.SelectionStart = 1
		box.CursorPosition = #box.Text + 1
	end)
	setStatus(statusText or "Text selected.", COLORS.green)
end

local render
local refreshContext

local function updateResponsiveLayout()
	local viewport = getViewportSize()
	local compact = viewport.X < 900 or viewport.Y < 600
	local tiny = viewport.X < 560 or viewport.Y < 470
	local scale = math.clamp(math.min(viewport.X / 960, viewport.Y / 720), 0.58, 1)
	responsive.compact = compact
	responsive.tiny = tiny
	responsive.scale = scale

	local margin = tiny and 6 or compact and 10 or 24
	local shellWidth = round(math.min(1080, math.max(320, (viewport.X - margin * 2) / scale)))
	local shellHeight = round(math.min(680, math.max(320, (viewport.Y - margin * 2) / scale)))
	local sidebarWidth = tiny and 104 or compact and 128 or 178
	local refreshWidth = tiny and 52 or compact and 64 or 78
	local closeSize = tiny and 26 or compact and 30 or 34

	shellScale.Scale = scale
	shellConstraint.MinSize = Vector2.new(math.min(300, shellWidth), math.min(300, shellHeight))
	shellConstraint.MaxSize = Vector2.new(shellWidth, shellHeight)
	shell.Size = UDim2.fromOffset(shellWidth, shellHeight)

	sidebar.Size = UDim2.new(0, sidebarWidth, 1, 0)
	main.Size = UDim2.new(1, -sidebarWidth, 1, 0)
	setPaddingOffsets(
		sidebarPadding,
		tiny and 6 or compact and 9 or 12,
		tiny and 7 or 12,
		tiny and 6 or compact and 9 or 12,
		tiny and 7 or 12
	)
	setPaddingOffsets(
		mainPadding,
		tiny and 7 or compact and 10 or 16,
		tiny and 7 or compact and 10 or 14,
		tiny and 7 or compact and 10 or 16,
		tiny and 7 or compact and 10 or 16
	)
	sidebarLayout.Padding = UDim.new(0, tiny and 5 or 10)
	mainLayout.Padding = UDim.new(0, tiny and 6 or compact and 9 or 12)

	brand.Size = UDim2.new(1, 0, 0, tiny and 40 or compact and 46 or 54)
	brandTitle.TextSize = responsiveTextSize(tiny and 13 or compact and 15 or 18)
	brandRank.TextSize = responsiveTextSize(tiny and 9 or 12)
	brandTitle.Size = UDim2.new(1, 0, 0, tiny and 21 or 28)
	brandRank.Position = UDim2.fromOffset(0, tiny and 21 or 28)
	tabs.Size = UDim2.new(1, 0, 1, -(tiny and 45 or 64))
	tabs.ScrollBarThickness = tiny and 3 or 4
	tabsLayout.Padding = UDim.new(0, tiny and 5 or 6)

	header.Size = UDim2.new(1, 0, 0, tiny and 32 or compact and 38 or 46)
	pageTitle.TextSize = responsiveTextSize(tiny and 15 or compact and 18 or 24)
	pageTitle.Size = UDim2.new(tiny and 0.36 or 0.42, 0, 1, 0)
	statusLabel.TextSize = responsiveTextSize(tiny and 9 or 12)
	statusLabel.Position = UDim2.new(1, -(refreshWidth + closeSize + 12), 0, 0)
	statusLabel.Size = UDim2.new(tiny and 0.42 or 0.46, -12, 1, 0)
	refreshButton.TextSize = responsiveTextSize(tiny and 9 or compact and 11 or 13)
	refreshButton.Position = UDim2.new(1, -(closeSize + 8), 0.5, 0)
	refreshButton.Size = UDim2.fromOffset(refreshWidth, tiny and 26 or compact and 30 or 34)
	closeButton.TextSize = responsiveTextSize(tiny and 10 or 13)
	closeButton.Size = UDim2.fromOffset(closeSize, closeSize)
	body.Size = UDim2.new(1, 0, 1, -(tiny and 38 or 58))
	body.ScrollBarThickness = tiny and 3 or 5
	bodyLayout.Padding = UDim.new(0, tiny and 6 or 10)

	for _, button in pairs(tabButtons) do
		button.TextSize = responsiveTextSize(tiny and 9 or compact and 10 or 13)
		button.Size = UDim2.new(1, -2, 0, tiny and 25 or compact and 30 or 34)
	end
end

local function callGetContext()
	local ok, result = pcall(function()
		return Remotes.GetAdminContext:InvokeServer()
	end)
	if not ok then
		return nil, tostring(result)
	end
	return result, nil
end

local function runAction(action, payload)
	if busy then
		return
	end
	busy = true
	setStatus("Working...", COLORS.muted)

	local ok, success, result = pcall(function()
		return Remotes.AdminAction:InvokeServer(action, payload or {})
	end)

	busy = false
	if not ok then
		setStatus(tostring(success), COLORS.red)
		return
	end
	if not success then
		setStatus(result or "Action failed.", COLORS.red)
		return
	end

	if type(result) == "table" and result.context then
		context = result.context
	end
	setStatus(type(result) == "table" and result.message or "Done.", COLORS.green)
	render()
end

refreshContext = function(silent)
	if busy then
		return
	end
	if not silent then
		setStatus("Refreshing...", COLORS.muted)
	end

	local result, err = callGetContext()
	if not result then
		setStatus(err or "Admin context failed.", COLORS.red)
		return false
	end
	if result.allowed ~= true then
		setStatus(result.message or "", COLORS.red)
		return false
	end

	context = result

	if selectedUserId and not findPlayer(selectedUserId) then
		selectedUserId = nil
	end

	if not silent then
		setStatus("Refreshed.", COLORS.green)
	end
	render()
	return true
end

local function setMenuOpen(nextOpen)
	if nextOpen and not loaded then
		return
	end

	if nextOpen then
		local ok = refreshContext(true)
		if not ok then
			return
		end
	end

	menuOpen = nextOpen
	overlay.Visible = menuOpen
	if not menuOpen then
		GuiService.SelectedObject = nil
	end
	render()
end

local function makeStat(parent, title, value, tint)
	local stat = Instance.new("Frame")
	stat.Name = title .. "Stat"
	stat.BackgroundColor3 = COLORS.panelSoft
	stat.BorderSizePixel = 0
	stat.Size = UDim2.new(0.25, -8, 0, 76)
	stat.Parent = parent
	addCorner(stat, 7)
	addStroke(stat, tint or COLORS.strokeSoft, 0.25, 1)
	addPadding(stat, 10, 8, 10, 8)

	local titleLabel = makeLabel(stat, "Title", title, 12, COLORS.muted, Enum.Font.GothamBold)
	titleLabel.Size = UDim2.new(1, 0, 0, 20)
	titleLabel.TextWrapped = false
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local valueLabel = makeLabel(stat, "Value", value, 21, tint or COLORS.text, Enum.Font.GothamBold)
	valueLabel.Position = UDim2.fromOffset(0, 24)
	valueLabel.Size = UDim2.new(1, 0, 0, 34)
	valueLabel.TextWrapped = false
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
	return stat
end

local function makeCompactStat(parent, title, value, tint)
	local stat = Instance.new("Frame")
	stat.Name = title .. "Stat"
	stat.BackgroundColor3 = COLORS.panelSoft
	stat.BorderSizePixel = 0
	stat.Size = UDim2.new(0.25, -6, 0, responsive.tiny and 42 or 50)
	stat.Parent = parent
	addCorner(stat, 6)
	addStroke(stat, tint or COLORS.strokeSoft, 0.28, 1)
	addPadding(stat, 8, 5, 8, 5)

	local titleLabel = makeLabel(stat, "Title", title, 10, COLORS.muted, Enum.Font.GothamBold)
	titleLabel.Size = UDim2.new(1, 0, 0, 15)
	titleLabel.TextWrapped = false
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local valueLabel =
		makeLabel(stat, "Value", value, responsive.tiny and 13 or 16, tint or COLORS.text, Enum.Font.GothamBold)
	valueLabel.Position = UDim2.fromOffset(0, 17)
	valueLabel.Size = UDim2.new(1, 0, 0, responsive.tiny and 18 or 24)
	valueLabel.TextWrapped = false
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
	return stat
end

local function makeFieldRow(parent, height)
	local row = Instance.new("Frame")
	row.Name = "FieldRow"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, height or 38)
	row.Parent = parent
	addHorizontalLayout(row, 8)
	return row
end

local function renderDashboard()
	local server = context and context.server or {}

	local statsPanel = makePanel(body, "Stats", 100)
	local statsLayout = addHorizontalLayout(statsPanel, 8)
	statsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	makeStat(statsPanel, "Online", ("%d/%d"):format(server.onlinePlayers or 0, server.maxPlayers or 0), COLORS.accent)
	makeStat(statsPanel, "Characters", tostring(server.loadedCharacters or 0), COLORS.blue)
	makeStat(statsPanel, "Rank", tostring(context and context.rank or "admin"), COLORS.green)
	makeStat(
		statsPanel,
		"Time",
		("%s%s"):format(server.timeText or "--:--", server.timeFrozen and " frozen" or ""),
		COLORS.text
	)

	local actions = makePanel(body, "Actions", responsive.tiny and 190 or 204)
	addVerticalLayout(actions, 10)

	local topRow = makeFieldRow(actions, responsive.tiny and 38 or 42)
	local selfHeal = makeButton(topRow, "SelfHeal", "Self Heal", COLORS.green)
	selfHeal.Size = responsive.tiny and UDim2.new(0.2, -6, 1, 0) or UDim2.new(0, 112, 1, 0)
	selfHeal.Activated:Connect(function()
		runAction("selfHeal")
	end)

	local freeze = makeButton(
		topRow,
		"Freeze",
		server.timeFrozen and "Resume Time" or "Freeze Time",
		server.timeFrozen and COLORS.orange or COLORS.blue
	)
	freeze.Size = responsive.tiny and UDim2.new(0.26, -6, 1, 0) or UDim2.new(0, 128, 1, 0)
	freeze.Activated:Connect(function()
		runAction("toggleFreezeTime")
	end)

	local hourBox = makeTextBox(topRow, "Hour", "Hour", tostring(server.timeHour or 12))
	hourBox.Size = responsive.tiny and UDim2.new(0.13, -4, 1, 0) or UDim2.new(0, 64, 1, 0)
	local minuteBox = makeTextBox(topRow, "Minute", "Min", tostring(server.timeMinute or 0))
	minuteBox.Size = responsive.tiny and UDim2.new(0.13, -4, 1, 0) or UDim2.new(0, 64, 1, 0)
	local setTimeButton = makeButton(topRow, "SetTime", "Set Time", COLORS.accentDark)
	setTimeButton.Size = responsive.tiny and UDim2.new(0.2, -6, 1, 0) or UDim2.new(0, 96, 1, 0)
	setTimeButton.Activated:Connect(function()
		runAction("setTime", {
			hour = hourBox.Text,
			minute = minuteBox.Text,
		})
	end)

	local announceRow = makeFieldRow(actions, responsive.tiny and 38 or 44)
	local announcement = makeTextBox(announceRow, "Announcement", "Announcement", "")
	announcement.Size = UDim2.new(1, responsive.tiny and -92 or -120, 1, 0)
	local announceButton = makeButton(announceRow, "Announce", "Announce", COLORS.accentDark)
	announceButton.Size = UDim2.new(0, responsive.tiny and 84 or 112, 1, 0)
	announceButton.Activated:Connect(function()
		runAction("announce", {
			message = announcement.Text,
		})
	end)

	local playerPanel = makePanel(body, "RecentPlayers", 190)
	addVerticalLayout(playerPanel, 8)
	local title = makeLabel(playerPanel, "Title", "Loaded Players", 16, COLORS.text, Enum.Font.GothamBold)
	title.Size = UDim2.new(1, 0, 0, 24)

	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, 0, 1, -32)
	list.Parent = playerPanel
	addVerticalLayout(list, 6)

	local count = 0
	for _, info in ipairs(context.players or {}) do
		count += 1
		if count > 3 then
			break
		end
		local row = Instance.new("Frame")
		row.Name = "PlayerRow"
		row.BackgroundColor3 = COLORS.panelSoft
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 32)
		row.Parent = list
		addCorner(row, 6)
		addPadding(row, 9, 0, 9, 0)
		local label = makeLabel(
			row,
			"Name",
			("%s  |  %s  |  %s"):format(info.displayName, info.character, info.job.label),
			12,
			COLORS.text,
			Enum.Font.GothamMedium
		)
		label.Size = UDim2.fromScale(1, 1)
		label.TextWrapped = false
		label.TextTruncate = Enum.TextTruncate.AtEnd
	end
end

local function renderSelectedPlayerDetails(parent, info)
	if not info then
		local empty = makeLabel(parent, "Empty", "", 14, COLORS.muted, Enum.Font.GothamMedium)
		empty.Size = UDim2.new(1, 0, 0, 40)
		return
	end

	local title = makeLabel(parent, "PlayerTitle", info.displayName, 20, COLORS.text, Enum.Font.GothamBold)
	title.Size = UDim2.new(1, 0, 0, 28)
	title.TextWrapped = false
	title.TextTruncate = Enum.TextTruncate.AtEnd

	local meta = makeLabel(
		parent,
		"Meta",
		("%s  |  UserId %s  |  %s"):format(info.character, tostring(info.userId), tostring(info.citizenId or "No CID")),
		12,
		COLORS.muted,
		Enum.Font.GothamMedium
	)
	meta.Size = UDim2.new(1, 0, 0, 24)
	meta.TextWrapped = false
	meta.TextTruncate = Enum.TextTruncate.AtEnd

	local playerStatsHeight = responsive.tiny and 62 or 78
	local summary = makePanel(parent, "Summary", playerStatsHeight)
	summary.BackgroundColor3 = COLORS.panelSoft
	local summaryLayout = addHorizontalLayout(summary, 6)
	summaryLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	makeCompactStat(summary, "Cash", formatMoney(info.money.cash), COLORS.green)
	makeCompactStat(summary, "Bank", formatMoney(info.money.bank), COLORS.blue)
	makeCompactStat(summary, "Job", ("%s %d"):format(info.job.name, info.job.gradeLevel), COLORS.accent)
	makeCompactStat(summary, "Crew", ("%s %d"):format(info.crew.name, info.crew.gradeLevel), COLORS.orange)

	local vitals = makePanel(parent, "Vitals", playerStatsHeight)
	vitals.BackgroundColor3 = COLORS.panelSoft
	addHorizontalLayout(vitals, 6)
	makeCompactStat(vitals, "Hunger", tostring(info.metadata.hunger), COLORS.green)
	makeCompactStat(vitals, "Thirst", tostring(info.metadata.thirst), COLORS.blue)
	makeCompactStat(vitals, "Armor", tostring(info.metadata.armor), COLORS.accent)
	makeCompactStat(vitals, "Stress", tostring(info.metadata.stress), COLORS.orange)

	local actionPanel = makePanel(parent, "PlayerActions", 126)
	addVerticalLayout(actionPanel, 8)
	local actionRow = makeFieldRow(actionPanel, 38)
	local gotoButton = makeButton(actionRow, "Goto", "Goto", COLORS.blue)
	gotoButton.Size = responsive.tiny and UDim2.new(0.2, -6, 1, 0) or UDim2.new(0, 76, 1, 0)
	gotoButton.Activated:Connect(function()
		runAction("gotoPlayer", { userId = info.userId })
	end)
	local bringButton = makeButton(actionRow, "Bring", "Bring", COLORS.blue)
	bringButton.Size = responsive.tiny and UDim2.new(0.2, -6, 1, 0) or UDim2.new(0, 76, 1, 0)
	bringButton.Activated:Connect(function()
		runAction("bringPlayer", { userId = info.userId })
	end)
	local healButton = makeButton(actionRow, "Heal", "Heal", COLORS.green)
	healButton.Size = responsive.tiny and UDim2.new(0.2, -6, 1, 0) or UDim2.new(0, 76, 1, 0)
	healButton.Activated:Connect(function()
		runAction("healPlayer", { userId = info.userId })
	end)
	local kickButton = makeButton(actionRow, "Kick", "Kick", COLORS.orange)
	kickButton.Size = responsive.tiny and UDim2.new(0.2, -6, 1, 0) or UDim2.new(0, 76, 1, 0)
	local banButton = makeButton(actionRow, "Ban", "Ban", COLORS.red)
	banButton.Size = responsive.tiny and UDim2.new(0.2, -6, 1, 0) or UDim2.new(0, 76, 1, 0)

	local reasonRow = makeFieldRow(actionPanel, 36)
	local reasonBox = makeTextBox(reasonRow, "Reason", "Reason", "")
	reasonBox.Size = UDim2.new(1, responsive.tiny and -72 or -86, 1, 0)
	local durationBox = makeTextBox(reasonRow, "Duration", "Ban hrs", "")
	durationBox.Size = UDim2.new(0, responsive.tiny and 64 or 78, 1, 0)
	kickButton.Activated:Connect(function()
		runAction("kickPlayer", { userId = info.userId, reason = reasonBox.Text })
	end)
	banButton.Activated:Connect(function()
		runAction("banPlayer", {
			userId = info.userId,
			reason = reasonBox.Text,
			durationHours = durationBox.Text,
		})
	end)

	local compactInputPanelHeight = responsive.tiny and 84 or 90
	local rolePanelHeight = responsive.tiny and 126 or 132

	local moneyPanel = makePanel(parent, "MoneyActions", compactInputPanelHeight)
	addVerticalLayout(moneyPanel, 8)
	local moneyTitle = makeLabel(moneyPanel, "Title", "Money", 14, COLORS.text, Enum.Font.GothamBold)
	moneyTitle.Size = UDim2.new(1, 0, 0, 20)
	local moneyRow = makeFieldRow(moneyPanel, 38)
	local moneyType = makeTextBox(moneyRow, "MoneyType", "cash/bank/crypto", "cash")
	moneyType.Size = responsive.tiny and UDim2.new(0.26, -4, 1, 0) or UDim2.new(0, 120, 1, 0)
	local moneyAmount = makeTextBox(moneyRow, "MoneyAmount", "Amount", "")
	moneyAmount.Size = responsive.tiny and UDim2.new(0.34, -4, 1, 0) or UDim2.new(1, -300, 1, 0)
	local addMoney = makeButton(moneyRow, "AddMoney", "Add", COLORS.green)
	addMoney.Size = responsive.tiny and UDim2.new(0.18, -4, 1, 0) or UDim2.new(0, 78, 1, 0)
	addMoney.Activated:Connect(function()
		runAction("addMoney", {
			userId = info.userId,
			moneyType = moneyType.Text,
			amount = moneyAmount.Text,
		})
	end)
	local setMoney = makeButton(moneyRow, "SetMoney", "Set", COLORS.blue)
	setMoney.Size = responsive.tiny and UDim2.new(0.18, -4, 1, 0) or UDim2.new(0, 78, 1, 0)
	setMoney.Activated:Connect(function()
		runAction("setMoney", {
			userId = info.userId,
			moneyType = moneyType.Text,
			amount = moneyAmount.Text,
		})
	end)

	local rolePanel = makePanel(parent, "Roles", rolePanelHeight)
	addVerticalLayout(rolePanel, 8)
	local roleTitle = makeLabel(rolePanel, "Title", "Job / Crew", 14, COLORS.text, Enum.Font.GothamBold)
	roleTitle.Size = UDim2.new(1, 0, 0, 20)

	local jobs = context.jobs or {}
	local jobRecord = findCatalogRecord(jobs, info.job.name)
	local jobGradeRecord = findCatalogGrade(jobRecord, info.job.gradeLevel)
	local selectedJobName = jobRecord and jobRecord.name or nil
	local selectedJobGrade = jobGradeRecord and jobGradeRecord.grade or nil
	local jobGradeDropdown

	local jobRow = makeFieldRow(rolePanel, 36)
	local jobDropdown = makeDropdown(jobRow, "JobName", makeCatalogOptions(jobs), selectedJobName, function(value)
		selectedJobName = value
		jobRecord = findCatalogRecord(jobs, selectedJobName)
		jobGradeRecord = findCatalogGrade(jobRecord, nil)
		selectedJobGrade = jobGradeRecord and jobGradeRecord.grade or nil
		if jobGradeDropdown then
			jobGradeDropdown.setOptions(makeGradeOptions(jobRecord), selectedJobGrade)
		end
	end)
	jobDropdown.button.Size = responsive.tiny and UDim2.new(0.42, -4, 1, 0) or UDim2.new(1, -292, 1, 0)
	jobGradeDropdown = makeDropdown(jobRow, "JobGrade", makeGradeOptions(jobRecord), selectedJobGrade, function(value)
		selectedJobGrade = value
	end)
	jobGradeDropdown.button.Size = responsive.tiny and UDim2.new(0.28, -4, 1, 0) or UDim2.new(0, 168, 1, 0)
	local setJob = makeButton(jobRow, "SetJob", "Set Job", COLORS.accentDark)
	setJob.Size = responsive.tiny and UDim2.new(0.24, -4, 1, 0) or UDim2.new(0, 108, 1, 0)
	setJob.Activated:Connect(function()
		local jobName = jobDropdown.getValue()
		local grade = jobGradeDropdown.getValue()
		if not jobName or not grade then
			setStatus("Choose a job and grade.", COLORS.red)
			return
		end
		runAction("setJob", {
			userId = info.userId,
			jobName = jobName,
			grade = grade,
		})
	end)

	local crews = context.crews or {}
	local crewRecord = findCatalogRecord(crews, info.crew.name)
	local crewGradeRecord = findCatalogGrade(crewRecord, info.crew.gradeLevel)
	local selectedCrewName = crewRecord and crewRecord.name or nil
	local selectedCrewGrade = crewGradeRecord and crewGradeRecord.grade or nil
	local crewGradeDropdown

	local crewRow = makeFieldRow(rolePanel, 36)
	local crewDropdown = makeDropdown(crewRow, "CrewName", makeCatalogOptions(crews), selectedCrewName, function(value)
		selectedCrewName = value
		crewRecord = findCatalogRecord(crews, selectedCrewName)
		crewGradeRecord = findCatalogGrade(crewRecord, nil)
		selectedCrewGrade = crewGradeRecord and crewGradeRecord.grade or nil
		if crewGradeDropdown then
			crewGradeDropdown.setOptions(makeGradeOptions(crewRecord), selectedCrewGrade)
		end
	end)
	crewDropdown.button.Size = responsive.tiny and UDim2.new(0.42, -4, 1, 0) or UDim2.new(1, -292, 1, 0)
	crewGradeDropdown = makeDropdown(
		crewRow,
		"CrewGrade",
		makeGradeOptions(crewRecord),
		selectedCrewGrade,
		function(value)
			selectedCrewGrade = value
		end
	)
	crewGradeDropdown.button.Size = responsive.tiny and UDim2.new(0.28, -4, 1, 0) or UDim2.new(0, 168, 1, 0)
	local setCrew = makeButton(crewRow, "SetCrew", "Set Crew", COLORS.accentDark)
	setCrew.Size = responsive.tiny and UDim2.new(0.24, -4, 1, 0) or UDim2.new(0, 108, 1, 0)
	setCrew.Activated:Connect(function()
		local crewName = crewDropdown.getValue()
		local grade = crewGradeDropdown.getValue()
		if not crewName or not grade then
			setStatus("Choose a crew and grade.", COLORS.red)
			return
		end
		runAction("setCrew", {
			userId = info.userId,
			crewName = crewName,
			grade = grade,
		})
	end)

	local itemPanel = makePanel(parent, "Items", compactInputPanelHeight)
	addVerticalLayout(itemPanel, 8)
	local itemTitle = makeLabel(itemPanel, "Title", "Give Item", 14, COLORS.text, Enum.Font.GothamBold)
	itemTitle.Size = UDim2.new(1, 0, 0, 20)
	local itemRow = makeFieldRow(itemPanel, 38)
	local itemName = makeTextBox(itemRow, "ItemName", "Item name", "")
	itemName.Size = responsive.tiny and UDim2.new(0.5, -4, 1, 0) or UDim2.new(1, -190, 1, 0)
	local itemAmount = makeTextBox(itemRow, "ItemAmount", "Qty", "1")
	itemAmount.Size = responsive.tiny and UDim2.new(0.18, -4, 1, 0) or UDim2.new(0, 68, 1, 0)
	local giveItem = makeButton(itemRow, "GiveItem", "Give", COLORS.green)
	giveItem.Size = responsive.tiny and UDim2.new(0.26, -4, 1, 0) or UDim2.new(0, 106, 1, 0)
	giveItem.Activated:Connect(function()
		runAction("giveItem", {
			userId = info.userId,
			itemName = itemName.Text,
			amount = itemAmount.Text,
		})
	end)
end

local function renderPlayers()
	local bodyHeight = round(body.AbsoluteSize.Y)
	local fallbackHeight = responsive.tiny and 560 or 520
	local pageHeight = math.max(responsive.tiny and 420 or 360, bodyHeight > 0 and bodyHeight or fallbackHeight)
	local listHeight = responsive.tiny and math.clamp(round(pageHeight * 0.34), 160, 220) or 0

	local page = Instance.new("Frame")
	page.Name = "PlayersPage"
	page.BackgroundTransparency = 1
	page.Size = UDim2.new(1, -6, 0, pageHeight)
	page.Parent = body
	if responsive.tiny then
		addVerticalLayout(page, 10)
	else
		addHorizontalLayout(page, 12)
	end

	local listPanel = Instance.new("ScrollingFrame")
	listPanel.Name = "PlayerList"
	listPanel.BackgroundColor3 = COLORS.panel
	listPanel.BorderSizePixel = 0
	listPanel.CanvasSize = UDim2.fromOffset(0, 0)
	listPanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listPanel.ScrollBarThickness = 4
	listPanel.ScrollBarImageColor3 = COLORS.stroke
	listPanel.Size = responsive.tiny and UDim2.new(1, 0, 0, listHeight) or UDim2.new(0.36, -6, 1, 0)
	listPanel.Parent = page
	addCorner(listPanel, 8)
	addStroke(listPanel, COLORS.strokeSoft, 0.2, 1)
	addPadding(listPanel, 12, 12, 12, 12)
	addVerticalLayout(listPanel, 8)

	local listTitle = makeLabel(listPanel, "Title", "Players", 16, COLORS.text, Enum.Font.GothamBold)
	listTitle.Size = UDim2.new(1, 0, 0, 24)

	local selected = selectedPlayer()
	for _, info in ipairs(context.players or {}) do
		local active = selected and selected.userId == info.userId
		local button = makeButton(
			listPanel,
			"Player_" .. tostring(info.userId),
			info.displayName,
			active and COLORS.accentDark or COLORS.panelSoft
		)
		button.Size = UDim2.new(1, 0, 0, 50)
		button.TextXAlignment = Enum.TextXAlignment.Left
		addPadding(button, 10, 0, 10, 0)
		button.Text = ("%s\n%s"):format(info.displayName, info.job.label)
		button.Activated:Connect(function()
			selectedUserId = info.userId
			render()
		end)
	end

	local detailScroll = Instance.new("ScrollingFrame")
	detailScroll.Name = "Details"
	detailScroll.BackgroundTransparency = 1
	detailScroll.BorderSizePixel = 0
	detailScroll.CanvasSize = UDim2.fromOffset(0, 0)
	detailScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	detailScroll.ScrollBarThickness = 5
	detailScroll.ScrollBarImageColor3 = COLORS.stroke
	detailScroll.Size = responsive.tiny and UDim2.new(1, 0, 1, -(listHeight + 10)) or UDim2.new(0.64, -6, 1, 0)
	detailScroll.Parent = page
	addVerticalLayout(detailScroll, 10)

	renderSelectedPlayerDetails(detailScroll, selected)
end

local function renderItems()
	local top = makePanel(body, "ItemTop", 84)
	addHorizontalLayout(top, 8)
	local selected = selectedPlayer()
	local targetText = selected and selected.displayName or player.DisplayName
	local target = makeLabel(top, "Target", "Target: " .. targetText, 14, COLORS.text, Enum.Font.GothamBold)
	target.Size = responsive.tiny and UDim2.new(1, -72, 1, 0) or UDim2.new(0, 220, 1, 0)
	target.TextWrapped = false
	target.TextTruncate = Enum.TextTruncate.AtEnd
	local amountBox = makeTextBox(top, "Amount", "Qty", "1")
	amountBox.Size = UDim2.new(0, responsive.tiny and 64 or 74, 0, responsive.tiny and 34 or 38)

	local list = Instance.new("Frame")
	list.Name = "ItemList"
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, -6, 0, math.max(80, #(context.items or {}) * 68))
	list.Parent = body
	addVerticalLayout(list, 8)

	for _, item in ipairs(context.items or {}) do
		local row = makePanel(list, "Item_" .. item.name, 60)
		row.BackgroundColor3 = COLORS.panelSoft
		local label = makeLabel(
			row,
			"Label",
			("%s  |  %s  |  %s"):format(item.label, item.name, formatWeight(item.weight)),
			13,
			COLORS.text,
			Enum.Font.GothamBold
		)
		label.Size = UDim2.new(1, -102, 1, 0)
		label.TextWrapped = false
		label.TextTruncate = Enum.TextTruncate.AtEnd
		local give = makeButton(row, "Give", "Give", COLORS.green)
		give.AnchorPoint = Vector2.new(1, 0.5)
		give.Position = UDim2.new(1, 0, 0.5, 0)
		give.Size = UDim2.fromOffset(84, 36)
		give.Activated:Connect(function()
			local targetUserId = selectedUserId or player.UserId
			runAction("giveItem", {
				userId = targetUserId,
				itemName = item.name,
				amount = amountBox.Text,
			})
		end)
	end
end

local function catalogRecordHeight(kind, record)
	local gradeCount = math.max(1, #(record.grades or {}))
	local gradeRowHeight = responsive.tiny and 30 or 34
	local gradeGap = responsive.tiny and 5 or 6
	local paddingY = responsive.tiny and 18 or 24
	local detailHeight = kind == "Crews" and (responsive.tiny and 30 or 34) or 20
	return paddingY + 24 + 6 + detailHeight + 6 + gradeCount * gradeRowHeight + math.max(0, gradeCount - 1) * gradeGap
end

local function renderCatalog(kind, records)
	local target = selectedPlayer()
	local targetUserId = target and target.userId or player.UserId
	local currentAssignment = ""
	if target then
		if kind == "Jobs" then
			currentAssignment = (" | Current: %s %s"):format(target.job.label, target.job.gradeName)
		else
			currentAssignment = (" | Current: %s %s"):format(target.crew.label, target.crew.gradeName)
		end
	end

	local targetPanel = makePanel(body, kind .. "Target", responsive.tiny and 66 or 62)
	targetPanel.BackgroundColor3 = COLORS.panelSoft
	addHorizontalLayout(targetPanel, 8)

	local targetLabel = makeLabel(
		targetPanel,
		"Target",
		("Target: %s%s"):format(target and target.displayName or player.DisplayName, currentAssignment),
		13,
		COLORS.text,
		Enum.Font.GothamBold
	)
	targetLabel.Size = UDim2.new(1, responsive.tiny and -72 or -92, 1, 0)
	targetLabel.TextWrapped = false
	targetLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local selfButton = makeButton(targetPanel, "Self", "Self", COLORS.blue)
	selfButton.Size = UDim2.new(0, responsive.tiny and 64 or 84, 0, responsive.tiny and 30 or 34)
	selfButton.Activated:Connect(function()
		selectedUserId = player.UserId
		render()
	end)

	local totalHeight = 0
	for _, record in ipairs(records) do
		totalHeight += catalogRecordHeight(kind, record) + 8
	end

	local list = Instance.new("Frame")
	list.Name = kind .. "Catalog"
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, -6, 0, math.max(90, totalHeight))
	list.Parent = body
	addVerticalLayout(list, 8)

	for _, record in ipairs(records) do
		local rowHeight = catalogRecordHeight(kind, record)
		local row = makePanel(list, kind .. "_" .. record.name, rowHeight)
		row.BackgroundColor3 = COLORS.panelSoft
		addVerticalLayout(row, responsive.tiny and 5 or 6)

		local title = makeLabel(
			row,
			"Title",
			("%s  |  %s"):format(record.label, record.name),
			15,
			COLORS.text,
			Enum.Font.GothamBold
		)
		title.Size = UDim2.new(1, 0, 0, 24)
		title.TextWrapped = false
		title.TextTruncate = Enum.TextTruncate.AtEnd

		local detailsText = ""
		local detailsHeight = kind == "Crews" and (responsive.tiny and 30 or 34) or 20
		if kind == "Crews" then
			local colors = type(record.colors) == "table" and record.colors or {}
			local colorText = ""
			if colors.primary and colors.accent then
				colorText = ("Colors: %s / %s"):format(colors.primary, colors.accent)
			end

			detailsText = record.description or ""
			if colorText ~= "" then
				detailsText = detailsText ~= "" and (detailsText .. "  |  " .. colorText) or colorText
			end
			if detailsText == "" then
				detailsText = "No description"
			end
		else
			detailsText = ("Type: %s | %s"):format(
				record.type or "none",
				record.defaultDuty and "default duty" or "off duty"
			)
		end

		local details = makeLabel(row, "Details", detailsText, 12, COLORS.muted, Enum.Font.GothamMedium)
		details.Size = UDim2.new(1, 0, 0, detailsHeight)
		details.TextWrapped = kind == "Crews"
		if kind ~= "Crews" then
			details.TextTruncate = Enum.TextTruncate.AtEnd
		end

		local grades = record.grades or {}
		if #grades == 0 then
			local empty = makeLabel(row, "NoGrades", "No ranks configured", 12, COLORS.muted, Enum.Font.GothamMedium)
			empty.Size = UDim2.new(1, 0, 0, responsive.tiny and 30 or 34)
			empty.TextWrapped = false
			empty.TextTruncate = Enum.TextTruncate.AtEnd
		else
			for _, grade in ipairs(grades) do
				local gradeRow = Instance.new("Frame")
				gradeRow.Name = "Rank_" .. tostring(grade.grade)
				gradeRow.BackgroundColor3 = COLORS.panel
				gradeRow.BorderSizePixel = 0
				gradeRow.Size = UDim2.new(1, 0, 0, responsive.tiny and 30 or 34)
				gradeRow.Parent = row
				addCorner(gradeRow, 6)
				addPadding(gradeRow, 8, 0, 8, 0)
				addHorizontalLayout(gradeRow, 8)

				local gradeText = ("Rank %s | %s"):format(tostring(grade.grade), tostring(grade.name))
				if kind == "Jobs" and tonumber(grade.payment) and tonumber(grade.payment) > 0 then
					gradeText = ("%s | $%d"):format(gradeText, tonumber(grade.payment))
				end
				if grade.isboss then
					gradeText = gradeText .. " | boss"
				end

				local gradeLabel = makeLabel(gradeRow, "Label", gradeText, 12, COLORS.text, Enum.Font.GothamMedium)
				gradeLabel.Size = UDim2.new(1, responsive.tiny and -78 or -98, 1, 0)
				gradeLabel.TextWrapped = false
				gradeLabel.TextTruncate = Enum.TextTruncate.AtEnd

				local gradeLevel = tonumber(grade.level) or tonumber(grade.grade) or 0
				local currentName
				local currentGrade
				if target then
					if kind == "Jobs" then
						currentName = target.job.name
						currentGrade = target.job.gradeLevel
					else
						currentName = target.crew.name
						currentGrade = target.crew.gradeLevel
					end
				end

				local isCurrent = target and currentName == record.name and tonumber(currentGrade) == gradeLevel
				local assign = makeButton(
					gradeRow,
					"Assign",
					isCurrent and "Current" or "Assign",
					isCurrent and COLORS.disabled or COLORS.green
				)
				assign.Size = UDim2.new(0, responsive.tiny and 70 or 88, 0, responsive.tiny and 26 or 30)
				if isCurrent then
					assign.Active = false
					assign.AutoButtonColor = false
				else
					assign.Activated:Connect(function()
						if kind == "Jobs" then
							runAction("setJob", {
								userId = targetUserId,
								jobName = record.name,
								grade = grade.grade,
							})
						else
							runAction("setCrew", {
								userId = targetUserId,
								crewName = record.name,
								grade = grade.grade,
							})
						end
					end)
				end
			end
		end
	end
end

local function renderVehicles()
	local records = context.vehicles or {}
	local list = Instance.new("Frame")
	list.Name = "VehicleCatalog"
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, -6, 0, math.max(90, #records * 118))
	list.Parent = body
	addVerticalLayout(list, 8)

	for _, vehicle in ipairs(records) do
		local row = makePanel(list, "Vehicle_" .. vehicle.name, 110)
		row.BackgroundColor3 = COLORS.panelSoft

		local title = makeLabel(
			row,
			"Title",
			("%s  |  %s"):format(vehicle.label, vehicle.name),
			15,
			COLORS.text,
			Enum.Font.GothamBold
		)
		title.Size = UDim2.new(1, -112, 0, 24)
		title.TextWrapped = false
		title.TextTruncate = Enum.TextTruncate.AtEnd

		local meta = makeLabel(
			row,
			"Meta",
			("Model: %s  |  Category: %s"):format(vehicle.modelName or vehicle.name, vehicle.category or "vehicle"),
			12,
			COLORS.muted,
			Enum.Font.GothamMedium
		)
		meta.Position = UDim2.fromOffset(0, 30)
		meta.Size = UDim2.new(1, -112, 0, 24)
		meta.TextWrapped = false
		meta.TextTruncate = Enum.TextTruncate.AtEnd

		local storage = makeLabel(
			row,
			"Storage",
			("Fuel: %d  |  Trunk: %d slots"):format(vehicle.fuel or 100, vehicle.trunkSlots or 0),
			12,
			COLORS.muted,
			Enum.Font.GothamMedium
		)
		storage.Position = UDim2.fromOffset(0, 56)
		storage.Size = UDim2.new(1, -112, 0, 22)
		storage.TextWrapped = false
		storage.TextTruncate = Enum.TextTruncate.AtEnd

		local spawn = makeButton(row, "Spawn", "Spawn", COLORS.green)
		spawn.AnchorPoint = Vector2.new(1, 0)
		spawn.Position = UDim2.new(1, 0, 0, 2)
		spawn.Size = UDim2.fromOffset(92, 36)
		spawn.Activated:Connect(function()
			runAction("spawnVehicle", {
				vehicleName = vehicle.name,
			})
		end)
	end
end

local function renderLogs()
	local list = Instance.new("Frame")
	list.Name = "LogsList"
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, -6, 0, math.max(90, #(context.logs or {}) * 58))
	list.Parent = body
	addVerticalLayout(list, 8)

	for _, entry in ipairs(context.logs or {}) do
		local row = makePanel(list, "Log_" .. tostring(entry.id), 50)
		row.BackgroundColor3 = COLORS.panelSoft
		local label = makeLabel(
			row,
			"LogText",
			("[%s] %s -> %s  %s"):format(
				entry.timeText or "--:--",
				entry.actor or "Admin",
				entry.action or "",
				entry.target or ""
			),
			13,
			COLORS.text,
			Enum.Font.GothamBold
		)
		label.Size = UDim2.new(1, 0, 0, 22)
		label.TextWrapped = false
		label.TextTruncate = Enum.TextTruncate.AtEnd

		local details = makeLabel(row, "Details", entry.details or "", 12, COLORS.muted, Enum.Font.Gotham)
		details.Position = UDim2.fromOffset(0, 22)
		details.Size = UDim2.new(1, 0, 0, 20)
		details.TextWrapped = false
		details.TextTruncate = Enum.TextTruncate.AtEnd
	end
end

local function renderEnvironment()
	local server = context and context.server or {}
	local weather = context and context.weather or {}
	local panel = makePanel(body, "Environment", responsive.tiny and 214 or 202)
	addVerticalLayout(panel, 10)

	local timeRow = makeFieldRow(panel, 42)
	local hourBox = makeTextBox(timeRow, "Hour", "Hour", tostring(server.timeHour or 12))
	hourBox.Size = responsive.tiny and UDim2.new(0.17, -4, 1, 0) or UDim2.new(0, 74, 1, 0)
	local minuteBox = makeTextBox(timeRow, "Minute", "Min", tostring(server.timeMinute or 0))
	minuteBox.Size = responsive.tiny and UDim2.new(0.17, -4, 1, 0) or UDim2.new(0, 74, 1, 0)
	local setTimeButton = makeButton(timeRow, "SetTime", "Set Time", COLORS.accentDark)
	setTimeButton.Size = responsive.tiny and UDim2.new(0.28, -4, 1, 0) or UDim2.new(0, 104, 1, 0)
	setTimeButton.Activated:Connect(function()
		runAction("setTime", {
			hour = hourBox.Text,
			minute = minuteBox.Text,
		})
	end)
	local freeze = makeButton(timeRow, "Freeze", server.timeFrozen and "Resume Time" or "Freeze Time", COLORS.blue)
	freeze.Size = responsive.tiny and UDim2.new(0.32, -4, 1, 0) or UDim2.new(0, 124, 1, 0)
	freeze.Activated:Connect(function()
		runAction("toggleFreezeTime")
	end)

	local currentWeather = tostring(weather.nextWeather or weather.currentWeather or "CLEAR")
	local weatherStatus = makeLabel(
		panel,
		"WeatherStatus",
		("Weather: %s%s  |  Blackout: %s"):format(
			currentWeather:lower(),
			weather.frozen and " frozen" or "",
			weather.blackout and "on" or "off"
		),
		13,
		COLORS.muted,
		Enum.Font.GothamBold
	)
	weatherStatus.Size = UDim2.new(1, 0, 0, 22)
	weatherStatus.TextWrapped = false
	weatherStatus.TextTruncate = Enum.TextTruncate.AtEnd

	local weatherOptions = {}
	for _, preset in ipairs(weather.presets or {}) do
		weatherOptions[#weatherOptions + 1] = {
			value = preset.name,
			label = preset.label or preset.name,
		}
	end
	if #weatherOptions == 0 then
		weatherOptions[1] = { value = currentWeather, label = currentWeather }
	end

	local selectedWeather = currentWeather:upper()
	local weatherRow = makeFieldRow(panel, 42)
	local weatherDropdown = makeDropdown(weatherRow, "Weather", weatherOptions, selectedWeather, function(value)
		selectedWeather = tostring(value or selectedWeather)
	end)
	weatherDropdown.button.Size = responsive.tiny and UDim2.new(0.38, -4, 1, 0) or UDim2.new(0, 180, 1, 0)

	local setWeather = makeButton(weatherRow, "SetWeather", "Set Weather", COLORS.accentDark)
	setWeather.Size = responsive.tiny and UDim2.new(0.28, -4, 1, 0) or UDim2.new(0, 122, 1, 0)
	setWeather.Activated:Connect(function()
		runAction("setWeather", {
			weatherName = selectedWeather,
		})
	end)

	local freezeWeather =
		makeButton(weatherRow, "FreezeWeather", weather.frozen and "Resume Weather" or "Freeze Weather", COLORS.blue)
	freezeWeather.Size = responsive.tiny and UDim2.new(0.34, -4, 1, 0) or UDim2.new(0, 144, 1, 0)
	freezeWeather.Activated:Connect(function()
		runAction("toggleFreezeWeather")
	end)

	local blackoutRow = makeFieldRow(panel, 38)
	local blackout =
		makeButton(blackoutRow, "Blackout", weather.blackout and "Disable Blackout" or "Enable Blackout", COLORS.red)
	blackout.Size = responsive.tiny and UDim2.new(0.5, -4, 1, 0) or UDim2.new(0, 156, 1, 0)
	blackout.Activated:Connect(function()
		runAction("toggleBlackout")
	end)
end

local function renderDeveloper()
	local transform = getCharacterTransform()
	local coordsText = "Character not spawned"
	local headingText = "Character not spawned"
	local configText = "Character not spawned"

	if transform then
		coordsText = ("%s, %s, %s"):format(formatCoord(transform.x), formatCoord(transform.y), formatCoord(transform.z))
		headingText = formatHeading(transform.heading)
		configText = ("{ x = %s, y = %s, z = %s, ry = %s }"):format(
			formatCoord(transform.x),
			formatCoord(transform.y),
			formatCoord(transform.z),
			formatHeading(transform.heading)
		)
	end

	local panel = makePanel(body, "DeveloperTools", responsive.tiny and 300 or 278)
	addVerticalLayout(panel, responsive.tiny and 7 or 10)

	local title = makeLabel(panel, "Title", "Position", 16, COLORS.text, Enum.Font.GothamBold)
	title.Size = UDim2.new(1, 0, 0, responsive.tiny and 22 or 24)
	title.TextWrapped = false
	title.TextTruncate = Enum.TextTruncate.AtEnd

	local labelWidth = responsive.tiny and 52 or 72
	local buttonWidth = responsive.tiny and 74 or 96
	local fieldWidth = UDim2.new(1, -(labelWidth + buttonWidth + 16), 1, 0)

	local coordRow = makeFieldRow(panel, responsive.tiny and 36 or 40)
	local coordsLabel = makeLabel(coordRow, "CoordinatesLabel", "Coords", 12, COLORS.muted, Enum.Font.GothamBold)
	coordsLabel.Size = UDim2.new(0, labelWidth, 1, 0)
	coordsLabel.TextWrapped = false
	local coordsBox = makeTextBox(coordRow, "Coordinates", "Coordinates", coordsText)
	coordsBox.Size = fieldWidth
	local selectCoords = makeButton(coordRow, "SelectCoordinates", "Select", COLORS.blue)
	selectCoords.Size = UDim2.new(0, buttonWidth, 1, 0)
	selectCoords.Activated:Connect(function()
		selectTextBox(coordsBox, "Coordinates selected.")
	end)

	local headingRow = makeFieldRow(panel, responsive.tiny and 36 or 40)
	local headingLabel = makeLabel(headingRow, "HeadingLabel", "Heading", 12, COLORS.muted, Enum.Font.GothamBold)
	headingLabel.Size = UDim2.new(0, labelWidth, 1, 0)
	headingLabel.TextWrapped = false
	local headingBox = makeTextBox(headingRow, "Heading", "Heading", headingText)
	headingBox.Size = fieldWidth
	local selectHeading = makeButton(headingRow, "SelectHeading", "Select", COLORS.blue)
	selectHeading.Size = UDim2.new(0, buttonWidth, 1, 0)
	selectHeading.Activated:Connect(function()
		selectTextBox(headingBox, "Heading selected.")
	end)

	local configRow = makeFieldRow(panel, responsive.tiny and 36 or 40)
	local configLabel = makeLabel(configRow, "ConfigLabel", "Config", 12, COLORS.muted, Enum.Font.GothamBold)
	configLabel.Size = UDim2.new(0, labelWidth, 1, 0)
	configLabel.TextWrapped = false
	local configBox = makeTextBox(configRow, "ConfigPosition", "Config position", configText)
	configBox.Size = fieldWidth
	local selectConfig = makeButton(configRow, "SelectConfigPosition", "Select", COLORS.accentDark)
	selectConfig.Size = UDim2.new(0, buttonWidth, 1, 0)
	selectConfig.Activated:Connect(function()
		selectTextBox(configBox, "Config position selected.")
	end)

	local teleportRow = makeFieldRow(panel, responsive.tiny and 36 or 40)
	local teleportLabel = makeLabel(teleportRow, "TeleportLabel", "Teleport", 12, COLORS.muted, Enum.Font.GothamBold)
	teleportLabel.Size = UDim2.new(0, labelWidth, 1, 0)
	teleportLabel.TextWrapped = false
	local teleportBox = makeTextBox(teleportRow, "TeleportCoordinates", "100,100,100", "")
	teleportBox.Size = fieldWidth
	local teleportButton = makeButton(teleportRow, "TeleportToCoordinates", "Teleport", COLORS.green)
	teleportButton.Size = UDim2.new(0, buttonWidth, 1, 0)
	teleportButton.Activated:Connect(function()
		runAction("teleportToCoords", {
			coords = teleportBox.Text,
		})
	end)

	local actionRow = makeFieldRow(panel, responsive.tiny and 34 or 38)
	local refreshValues = makeButton(actionRow, "RefreshValues", "Refresh Values", COLORS.green)
	refreshValues.Size = responsive.tiny and UDim2.new(0.48, -4, 1, 0) or UDim2.new(0, 140, 1, 0)
	refreshValues.Activated:Connect(function()
		render()
		setStatus("Position refreshed.", COLORS.green)
	end)
end

local LEADERBOARD_METRICS = {
	{ key = "wealth", label = "Total Wealth" },
	{ key = "cash", label = "Cash" },
	{ key = "bank", label = "Bank" },
	{ key = "crypto", label = "Crypto" },
}

local function leaderboardMetricLabel(metric)
	for _, option in ipairs(LEADERBOARD_METRICS) do
		if option.key == metric then
			return option.label
		end
	end
	return "Total Wealth"
end

local function leaderboardMoney(info)
	local money = type(info.money) == "table" and info.money or {}
	local cash = math.floor(tonumber(money.cash) or 0)
	local bank = math.floor(tonumber(money.bank) or 0)
	local crypto = math.floor(tonumber(money.crypto) or 0)
	return cash, bank, crypto, cash + bank + crypto
end

local function leaderboardEntries()
	local entries = {}
	local query = trim(leaderboardSearchQuery):lower()
	for _, info in ipairs(context.players or {}) do
		local job = type(info.job) == "table" and info.job or {}
		local crew = type(info.crew) == "table" and info.crew or {}
		local haystack = table
			.concat({
				tostring(info.character or ""),
				tostring(info.displayName or ""),
				tostring(info.name or ""),
				tostring(info.citizenId or ""),
				tostring(job.label or job.name or ""),
				tostring(crew.label or crew.name or ""),
			}, " ")
			:lower()

		if query == "" or haystack:find(query, 1, true) then
			local cash, bank, crypto, wealth = leaderboardMoney(info)
			entries[#entries + 1] = {
				info = info,
				cash = cash,
				bank = bank,
				crypto = crypto,
				wealth = wealth,
			}
		end
	end

	table.sort(entries, function(a, b)
		local aValue = tonumber(a[leaderboardMetric]) or 0
		local bValue = tonumber(b[leaderboardMetric]) or 0
		if aValue ~= bValue then
			return aValue > bValue
		end
		local aName = tostring(a.info.character or a.info.displayName or ""):lower()
		local bName = tostring(b.info.character or b.info.displayName or ""):lower()
		if aName ~= bName then
			return aName < bName
		end
		return (tonumber(a.info.userId) or 0) < (tonumber(b.info.userId) or 0)
	end)

	return entries
end

local function makeLeaderboardRank(parent, rank)
	local tint = rank == 1 and COLORS.accent
		or rank == 2 and COLORS.muted
		or rank == 3 and COLORS.orange
		or COLORS.stroke
	local badge = Instance.new("Frame")
	badge.Name = "Rank"
	badge.BackgroundColor3 = rank <= 3 and COLORS.input or COLORS.panel
	badge.BorderSizePixel = 0
	badge.Position = UDim2.fromOffset(0, responsive.tiny and 8 or 10)
	badge.Size = UDim2.fromOffset(responsive.tiny and 30 or 34, responsive.tiny and 30 or 34)
	badge.Parent = parent
	addCorner(badge, 999)
	addStroke(badge, tint, rank <= 3 and 0.05 or 0.4, 1)

	local label = makeLabel(badge, "Value", tostring(rank), responsive.tiny and 11 or 13, tint, Enum.Font.GothamBold)
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextWrapped = false
	return badge
end

local function makeLeaderboardValue(parent, name, text, xScale, widthScale, color)
	local value = makeLabel(parent, name, text, 12, color, Enum.Font.GothamBold)
	value.Position = UDim2.new(xScale, 0, 0, 0)
	value.Size = UDim2.new(widthScale, 0, 1, 0)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextWrapped = false
	value.TextTruncate = Enum.TextTruncate.AtEnd
	return value
end

local function renderLeaderboard()
	local entries = leaderboardEntries()
	local metricLabel = leaderboardMetricLabel(leaderboardMetric)

	local controls = makePanel(body, "LeaderboardControls", 104)
	addVerticalLayout(controls, 8)

	local searchRow = makeFieldRow(controls, 36)
	local searchBox =
		makeTextBox(searchRow, "Search", "Search player, citizen ID, job, or crew", leaderboardSearchQuery)
	local fixedWidth = responsive.tiny and 128 or 184
	searchBox.Size = UDim2.new(1, -fixedWidth, 1, 0)
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		leaderboardSearchQuery = searchBox.Text
	end)
	searchBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			leaderboardSearchQuery = trim(searchBox.Text)
			render()
		end
	end)

	local searchButton = makeButton(searchRow, "ApplySearch", responsive.tiny and "Find" or "Search", COLORS.blue)
	searchButton.Size = UDim2.fromOffset(responsive.tiny and 52 or 76, 36)
	searchButton.Activated:Connect(function()
		leaderboardSearchQuery = trim(searchBox.Text)
		render()
	end)

	local pageRefresh = makeButton(searchRow, "RefreshLeaderboard", "Refresh", COLORS.green)
	pageRefresh.Size = UDim2.fromOffset(responsive.tiny and 60 or 92, 36)
	pageRefresh.Activated:Connect(function()
		refreshContext(false)
	end)

	local metricRow = makeFieldRow(controls, 34)
	for _, option in ipairs(LEADERBOARD_METRICS) do
		local active = leaderboardMetric == option.key
		local metricButton = makeButton(
			metricRow,
			"Metric_" .. option.key,
			responsive.tiny and (option.key == "wealth" and "Wealth" or option.label) or option.label,
			active and COLORS.accentDark or COLORS.panelSoft
		)
		metricButton.Size = UDim2.new(0.25, -6, 1, 0)
		metricButton.TextColor3 = active and COLORS.text or COLORS.muted
		metricButton.Activated:Connect(function()
			leaderboardMetric = option.key
			render()
		end)
	end

	local totalWealth = 0
	for _, entry in ipairs(entries) do
		totalWealth += entry.wealth
	end
	local averageWealth = #entries > 0 and math.floor(totalWealth / #entries + 0.5) or 0
	local topMetric = entries[1] and entries[1][leaderboardMetric] or 0

	local summary = makePanel(body, "LeaderboardSummary", responsive.tiny and 62 or 78)
	addHorizontalLayout(summary, 8)
	makeCompactStat(summary, "Players", tostring(#entries), COLORS.accent)
	makeCompactStat(summary, "Total Wealth", formatMoney(totalWealth), COLORS.green)
	makeCompactStat(summary, "Avg Wealth", formatMoney(averageWealth), COLORS.blue)
	makeCompactStat(summary, "Top " .. metricLabel, formatMoney(topMetric), COLORS.orange)

	local headerHeight = responsive.tiny and 0 or 28
	local rowHeight = responsive.tiny and 68 or 58
	local listHeight = headerHeight + math.max(1, #entries) * (rowHeight + 8)
	local list = Instance.new("Frame")
	list.Name = "LeaderboardList"
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, -6, 0, listHeight)
	list.Parent = body
	local listLayout = addVerticalLayout(list, 8)

	if not responsive.tiny then
		local header = Instance.new("Frame")
		header.Name = "Header"
		header.BackgroundTransparency = 1
		header.Size = UDim2.new(1, -6, 0, headerHeight)
		header.LayoutOrder = 1
		header.Parent = list
		local rankHeader = makeLabel(header, "Rank", "#", 10, COLORS.muted, Enum.Font.GothamBold)
		rankHeader.Size = UDim2.new(0.08, 0, 1, 0)
		local playerHeader = makeLabel(header, "Player", "PLAYER", 10, COLORS.muted, Enum.Font.GothamBold)
		playerHeader.Position = UDim2.new(0.08, 0, 0, 0)
		playerHeader.Size = UDim2.new(0.35, 0, 1, 0)
		makeLeaderboardValue(
			header,
			"Cash",
			"CASH",
			0.43,
			0.18,
			leaderboardMetric == "cash" and COLORS.accent or COLORS.muted
		)
		makeLeaderboardValue(
			header,
			"Bank",
			"BANK",
			0.61,
			0.2,
			leaderboardMetric == "bank" and COLORS.accent or COLORS.muted
		)
		makeLeaderboardValue(
			header,
			"Crypto",
			"CRYPTO",
			0.81,
			0.19,
			leaderboardMetric == "crypto" and COLORS.accent or COLORS.muted
		)
	end

	for index, entry in ipairs(entries) do
		local info = entry.info
		local row = makePanel(list, "Leaderboard_" .. tostring(info.userId or index), rowHeight)
		row.LayoutOrder = index + 1
		row.BackgroundColor3 = index <= 3 and COLORS.panelSoft or COLORS.panel
		makeLeaderboardRank(row, index)

		local characterName = tostring(info.character or info.displayName or info.name or "Unknown")
		local accountName = tostring(info.name or info.displayName or info.userId or "Unknown")
		local job = type(info.job) == "table" and info.job or {}
		local detailText = ("@%s  |  %s"):format(accountName, tostring(job.label or job.name or "Unemployed"))

		if responsive.tiny then
			local name = makeLabel(row, "Player", characterName, 12, COLORS.text, Enum.Font.GothamBold)
			name.Position = UDim2.fromOffset(40, 2)
			name.Size = UDim2.new(1, -152, 0, 23)
			name.TextWrapped = false
			name.TextTruncate = Enum.TextTruncate.AtEnd
			local detail = makeLabel(row, "Detail", detailText, 9, COLORS.muted, Enum.Font.GothamMedium)
			detail.Position = UDim2.fromOffset(40, 27)
			detail.Size = UDim2.new(1, -152, 0, 18)
			detail.TextWrapped = false
			detail.TextTruncate = Enum.TextTruncate.AtEnd
			local metric = makeLabel(row, "Metric", metricLabel:upper(), 8, COLORS.muted, Enum.Font.GothamBold)
			metric.AnchorPoint = Vector2.new(1, 0)
			metric.Position = UDim2.new(1, 0, 0, 5)
			metric.Size = UDim2.fromOffset(102, 16)
			metric.TextXAlignment = Enum.TextXAlignment.Right
			metric.TextWrapped = false
			local metricValue = makeLabel(
				row,
				"MetricValue",
				formatMoney(entry[leaderboardMetric]),
				12,
				COLORS.green,
				Enum.Font.GothamBold
			)
			metricValue.AnchorPoint = Vector2.new(1, 0)
			metricValue.Position = UDim2.new(1, 0, 0, 23)
			metricValue.Size = UDim2.fromOffset(102, 22)
			metricValue.TextXAlignment = Enum.TextXAlignment.Right
			metricValue.TextWrapped = false
			metricValue.TextTruncate = Enum.TextTruncate.AtEnd
		else
			local name = makeLabel(row, "Player", characterName, 12, COLORS.text, Enum.Font.GothamBold)
			name.Position = UDim2.new(0.08, 0, 0, 1)
			name.Size = UDim2.new(0.35, -8, 0, 22)
			name.TextWrapped = false
			name.TextTruncate = Enum.TextTruncate.AtEnd
			local detail = makeLabel(row, "Detail", detailText, 9, COLORS.muted, Enum.Font.GothamMedium)
			detail.Position = UDim2.new(0.08, 0, 0, 23)
			detail.Size = UDim2.new(0.35, -8, 0, 17)
			detail.TextWrapped = false
			detail.TextTruncate = Enum.TextTruncate.AtEnd
			makeLeaderboardValue(row, "Cash", formatMoney(entry.cash), 0.43, 0.18, COLORS.green)
			makeLeaderboardValue(row, "Bank", formatMoney(entry.bank), 0.61, 0.2, COLORS.blue)
			makeLeaderboardValue(row, "Crypto", formatMoney(entry.crypto), 0.81, 0.19, COLORS.accent)
		end
	end

	if #entries == 0 then
		local empty = makePanel(list, "Empty", rowHeight)
		empty.LayoutOrder = 2
		local message = makeLabel(
			empty,
			"Message",
			leaderboardSearchQuery ~= "" and "No loaded players match that search." or "No characters are loaded.",
			12,
			COLORS.muted,
			Enum.Font.GothamMedium
		)
		message.Size = UDim2.fromScale(1, 1)
		message.TextXAlignment = Enum.TextXAlignment.Center
	end

	listLayout.Padding = UDim.new(0, 8)
end

local function renderBlank()
	local spacer = Instance.new("Frame")
	spacer.Name = "Blank"
	spacer.BackgroundTransparency = 1
	spacer.Size = UDim2.new(1, -6, 0, 420)
	spacer.Parent = body
end

render = function()
	updateResponsiveLayout()
	closeDropdownPopup()
	pageTitle.Text = currentPage
	brandRank.Text = context and context.rank and ("Rank: " .. context.rank) or ""

	local useBodyScroll = currentPage ~= "Players"
	body.ScrollingEnabled = useBodyScroll
	body.ScrollBarThickness = useBodyScroll and (responsive.tiny and 3 or 5) or 0
	if not useBodyScroll then
		body.CanvasPosition = Vector2.new(0, 0)
	end

	for pageName, button in pairs(tabButtons) do
		local active = pageName == currentPage
		button.BackgroundColor3 = active and COLORS.accentDark or COLORS.panel
		button.TextColor3 = active and COLORS.text or COLORS.muted
	end

	if not menuOpen then
		return
	end

	clearGuiObjects(body)

	if not context then
		renderBlank()
		return
	end

	if currentPage == "Dashboard" then
		renderDashboard()
	elseif currentPage == "Players" then
		renderPlayers()
	elseif currentPage == "Items" then
		renderItems()
	elseif currentPage == "Jobs" then
		renderCatalog("Jobs", context.jobs or {})
	elseif currentPage == "Crews" then
		renderCatalog("Crews", context.crews or {})
	elseif currentPage == "Vehicles" then
		renderVehicles()
	elseif currentPage == "Logs" then
		renderLogs()
	elseif currentPage == "Environment" then
		renderEnvironment()
	elseif currentPage == "Developer" then
		renderDeveloper()
	elseif currentPage == "Leaderboard" then
		renderLeaderboard()
	else
		renderBlank()
	end
end

for index, pageName in ipairs(PAGES) do
	local button = makeButton(tabs, pageName, pageName, COLORS.panel)
	button.Size = UDim2.new(1, -2, 0, 34)
	button.LayoutOrder = index
	button.TextXAlignment = Enum.TextXAlignment.Left
	addPadding(button, 10, 0, 8, 0)
	button.Activated:Connect(function()
		currentPage = pageName
		render()
	end)
	tabButtons[pageName] = button
end

closeButton.Activated:Connect(function()
	setMenuOpen(false)
end)
refreshButton.Activated:Connect(function()
	refreshContext(false)
end)

Remotes.OpenAdminMenu.OnClientEvent:Connect(function()
	setMenuOpen(true)
end)

QBCoreClient.OnPlayerLoaded.Event:Connect(function()
	loaded = true
	task.defer(function()
		refreshContext(true)
	end)
end)

QBCoreClient.OnPlayerDataUpdated.Event:Connect(function(key)
	if key == "all" and not loaded then
		loaded = true
		task.defer(function()
			refreshContext(true)
		end)
	end
end)

if QBCoreClient.GetPlayerData() then
	loaded = true
	task.defer(function()
		refreshContext(true)
	end)
end

local viewportConnection
local function bindResponsiveLayout()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end

	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if render then
				render()
			else
				updateResponsiveLayout()
			end
		end)
	end

	updateResponsiveLayout()
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindResponsiveLayout)
bindResponsiveLayout()

render()
