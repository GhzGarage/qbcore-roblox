--[[
    Roblox port of the "which character do you want to play" step that FiveM QBCore drives
    through qb-multicharacter's NUI. There is no NUI on Roblox, so this creates a Studio-native
    character selection surface for the join -> select/create/delete -> spawn loop.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.QBRemotes)
local QBCoreClient = require(ReplicatedStorage.QBCoreClient)
local QBShared = require(ReplicatedStorage.QBShared.Main)
local QBUITheme = require(ReplicatedStorage.QBUITheme)
local QBUIScale = require(ReplicatedStorage.QBUIScale)

local player = Players.LocalPlayer

local COLORS = QBUITheme.Palette("Core", {
	redConfirm = Color3.fromRGB(221, 83, 83),
})

local MAX_CHARACTER_SLOTS = tonumber(QBShared.Config.Player.MaxCharacterSlots) or 5
local responsive = {
	compact = false,
	tiny = false,
	scale = 1,
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QBCharacterSelect"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 50
screenGui.Parent = player:WaitForChild("PlayerGui")

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
	return QBUIScale.GetViewportSize(workspace.CurrentCamera)
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
	box.BackgroundColor3 = COLORS.input
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Gotham
	box.PlaceholderColor3 = COLORS.muted
	box.PlaceholderText = placeholder
	box.Text = ""
	box.TextColor3 = COLORS.text
	box.TextSize = 16
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = parent
	addCorner(box, 8)
	addStroke(box, Color3.fromRGB(56, 66, 82), 0)
	addPadding(box, 12, 0, 12, 0)
	return box
end

local function trim(text)
	return (text or ""):match("^%s*(.-)%s*$")
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

local background = Instance.new("Frame")
background.Name = "Background"
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = COLORS.page
background.BackgroundTransparency = 0.05
background.Parent = screenGui

local shell = Instance.new("Frame")
shell.Name = "Shell"
shell.AnchorPoint = Vector2.new(0.5, 0.5)
shell.Position = UDim2.fromScale(0.5, 0.5)
shell.Size = UDim2.new(0.86, 0, 0.72, 0)
shell.BackgroundColor3 = COLORS.shell
shell.BorderSizePixel = 0
shell.Parent = background
addCorner(shell, 8)
addStroke(shell, COLORS.stroke, 0.1)
local shellPadding = addPadding(shell, 24, 22, 24, 24)

local shellScale = Instance.new("UIScale")
shellScale.Parent = shell

local shellSize = Instance.new("UISizeConstraint")
shellSize.MinSize = Vector2.new(620, 430)
shellSize.MaxSize = Vector2.new(900, 560)
shellSize.Parent = shell

local shellLayout = Instance.new("UIListLayout")
shellLayout.FillDirection = Enum.FillDirection.Vertical
shellLayout.SortOrder = Enum.SortOrder.LayoutOrder
shellLayout.Padding = UDim.new(0, 16)
shellLayout.Parent = shell

local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, 54)
header.LayoutOrder = 1
header.Parent = shell

local titleLabel = makeLabel(header, "Title", "Character Select", 26, COLORS.text, Enum.Font.GothamBold)
titleLabel.Size = UDim2.new(0.55, 0, 1, 0)

local subtitleLabel = makeLabel(header, "Subtitle", "Choose who you want to play.", 14, COLORS.muted, Enum.Font.Gotham)
subtitleLabel.AnchorPoint = Vector2.new(1, 0)
subtitleLabel.Position = UDim2.new(1, 0, 0, 4)
subtitleLabel.Size = UDim2.new(0.45, 0, 0, 22)
subtitleLabel.TextXAlignment = Enum.TextXAlignment.Right

local statusLabel = makeLabel(header, "Status", "", 14, COLORS.muted, Enum.Font.GothamMedium)
statusLabel.AnchorPoint = Vector2.new(1, 1)
statusLabel.Position = UDim2.fromScale(1, 1)
statusLabel.Size = UDim2.new(0.55, 0, 0, 24)
statusLabel.TextXAlignment = Enum.TextXAlignment.Right

local content = Instance.new("Frame")
content.Name = "Content"
content.BackgroundTransparency = 1
content.Size = UDim2.new(1, 0, 1, -70)
content.LayoutOrder = 2
content.Parent = shell

local contentLayout = Instance.new("UIListLayout")
contentLayout.FillDirection = Enum.FillDirection.Horizontal
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding = UDim.new(0, 16)
contentLayout.Parent = content

local listPanel = Instance.new("Frame")
listPanel.Name = "CharacterListPanel"
listPanel.BackgroundColor3 = COLORS.panel
listPanel.BorderSizePixel = 0
listPanel.Size = UDim2.new(0.62, -8, 1, 0)
listPanel.LayoutOrder = 1
listPanel.Parent = content
addCorner(listPanel, 8)
addStroke(listPanel, Color3.fromRGB(60, 72, 89), 0.25)
local listPanelPadding = addPadding(listPanel, 16, 16, 16, 16)

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 12)
listLayout.Parent = listPanel

local listHeader = Instance.new("Frame")
listHeader.Name = "ListHeader"
listHeader.BackgroundTransparency = 1
listHeader.Size = UDim2.new(1, 0, 0, 30)
listHeader.LayoutOrder = 1
listHeader.Parent = listPanel

local listTitle = makeLabel(listHeader, "Title", "Existing Characters", 18, COLORS.text, Enum.Font.GothamBold)
listTitle.Size = UDim2.new(0.7, 0, 1, 0)

local countLabel = makeLabel(listHeader, "Count", "0/5", 14, COLORS.muted, Enum.Font.GothamMedium)
countLabel.AnchorPoint = Vector2.new(1, 0)
countLabel.Position = UDim2.new(1, 0, 0, 0)
countLabel.Size = UDim2.new(0.3, 0, 1, 0)
countLabel.TextXAlignment = Enum.TextXAlignment.Right

local characterList = Instance.new("ScrollingFrame")
characterList.Name = "Characters"
characterList.BackgroundTransparency = 1
characterList.BorderSizePixel = 0
characterList.CanvasSize = UDim2.fromOffset(0, 0)
characterList.AutomaticCanvasSize = Enum.AutomaticSize.Y
characterList.ScrollBarThickness = 5
characterList.ScrollBarImageColor3 = Color3.fromRGB(91, 108, 130)
characterList.Size = UDim2.new(1, 0, 1, -42)
characterList.LayoutOrder = 2
characterList.Parent = listPanel

local characterListLayout = Instance.new("UIListLayout")
characterListLayout.FillDirection = Enum.FillDirection.Vertical
characterListLayout.SortOrder = Enum.SortOrder.LayoutOrder
characterListLayout.Padding = UDim.new(0, 10)
characterListLayout.Parent = characterList

local createPanel = Instance.new("Frame")
createPanel.Name = "CreatePanel"
createPanel.BackgroundColor3 = COLORS.panel
createPanel.BorderSizePixel = 0
createPanel.Size = UDim2.new(0.38, -8, 1, 0)
createPanel.LayoutOrder = 2
createPanel.Parent = content
addCorner(createPanel, 8)
addStroke(createPanel, Color3.fromRGB(60, 72, 89), 0.25)
local createPanelPadding = addPadding(createPanel, 16, 16, 16, 16)

local createLayout = Instance.new("UIListLayout")
createLayout.FillDirection = Enum.FillDirection.Vertical
createLayout.SortOrder = Enum.SortOrder.LayoutOrder
createLayout.Padding = UDim.new(0, 12)
createLayout.Parent = createPanel

local createTitle = makeLabel(createPanel, "Title", "New Character", 18, COLORS.text, Enum.Font.GothamBold)
createTitle.Size = UDim2.new(1, 0, 0, 30)
createTitle.LayoutOrder = 1

local firstNameBox = makeTextBox(createPanel, "FirstName", "First name")
firstNameBox.Size = UDim2.new(1, 0, 0, 44)
firstNameBox.LayoutOrder = 2

local lastNameBox = makeTextBox(createPanel, "LastName", "Last name")
lastNameBox.Size = UDim2.new(1, 0, 0, 44)
lastNameBox.LayoutOrder = 3

local createButton = makeButton(createPanel, "Create", "Create Character", COLORS.green)
createButton.Size = UDim2.new(1, 0, 0, 46)
createButton.LayoutOrder = 4

local createHint = makeLabel(
	createPanel,
	"Hint",
	"Starting job: Civilian\nStarting cash: $500\nStarting bank: $5,000",
	13,
	COLORS.muted,
	Enum.Font.Gotham
)
createHint.Size = UDim2.new(1, 0, 0, 66)
createHint.LayoutOrder = 5
createHint.TextYAlignment = Enum.TextYAlignment.Top

local function updateResponsiveLayout()
	local viewport = getViewportSize()
	local compact = viewport.X < 820 or viewport.Y < 600
	local tiny = viewport.X < 560 or viewport.Y < 470
	local scale = compact and QBUIScale.FromViewport(viewport, QBUIScale.Profiles.Panel) or 1
	responsive.compact = compact
	responsive.tiny = tiny
	responsive.scale = scale

	local margin = tiny and 6 or compact and 10 or 28
	local shellWidth = round(math.min(900, math.max(300, (viewport.X - margin * 2) / scale)))
	local shellHeight = round(math.min(560, math.max(300, (viewport.Y - margin * 2) / scale)))

	shellScale.Scale = scale
	shellSize.MinSize = Vector2.new(math.min(300, shellWidth), math.min(300, shellHeight))
	shellSize.MaxSize = Vector2.new(shellWidth, shellHeight)
	shell.Size = UDim2.fromOffset(shellWidth, shellHeight)

	local shellPadX = tiny and 8 or compact and 12 or 24
	local shellPadTop = tiny and 8 or compact and 12 or 22
	local shellPadBottom = tiny and 9 or compact and 12 or 24
	setPaddingOffsets(shellPadding, shellPadX, shellPadTop, shellPadX, shellPadBottom)
	shellLayout.Padding = UDim.new(0, tiny and 8 or compact and 10 or 16)

	header.Size = UDim2.new(1, 0, 0, tiny and 48 or compact and 56 or 54)
	titleLabel.TextSize = tiny and 18 or compact and 21 or 26
	titleLabel.Size = UDim2.new(compact and 1 or 0.55, 0, compact and 0.5 or 1, 0)
	subtitleLabel.TextSize = tiny and 10 or compact and 12 or 14
	subtitleLabel.AnchorPoint = compact and Vector2.new(0, 0) or Vector2.new(1, 0)
	subtitleLabel.Position = compact and UDim2.new(0, 0, 0, 30) or UDim2.new(1, 0, 0, 4)
	subtitleLabel.Size = compact and UDim2.new(1, 0, 0, 18) or UDim2.new(0.45, 0, 0, 22)
	subtitleLabel.TextXAlignment = compact and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
	statusLabel.TextSize = tiny and 10 or compact and 12 or 14
	statusLabel.AnchorPoint = compact and Vector2.new(0, 1) or Vector2.new(1, 1)
	statusLabel.Position = compact and UDim2.fromScale(0, 1) or UDim2.fromScale(1, 1)
	statusLabel.Size = compact and UDim2.new(1, 0, 0, 22) or UDim2.new(0.55, 0, 0, 24)
	statusLabel.TextXAlignment = compact and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right

	if compact then
		contentLayout.FillDirection = Enum.FillDirection.Vertical
		contentLayout.Padding = UDim.new(0, tiny and 8 or 10)
		listPanel.Size = UDim2.new(1, 0, 0.58, -5)
		createPanel.Size = UDim2.new(1, 0, 0.42, -5)
	else
		contentLayout.FillDirection = Enum.FillDirection.Horizontal
		contentLayout.Padding = UDim.new(0, 16)
		listPanel.Size = UDim2.new(0.62, -8, 1, 0)
		createPanel.Size = UDim2.new(0.38, -8, 1, 0)
	end

	local panelPad = tiny and 10 or compact and 12 or 16
	setPaddingOffsets(listPanelPadding, panelPad, panelPad, panelPad, panelPad)
	setPaddingOffsets(createPanelPadding, panelPad, panelPad, panelPad, panelPad)
	listLayout.Padding = UDim.new(0, tiny and 8 or 12)
	createLayout.Padding = UDim.new(0, tiny and 8 or 12)
	listTitle.TextSize = tiny and 14 or compact and 16 or 18
	countLabel.TextSize = tiny and 10 or compact and 12 or 14
	characterList.ScrollBarThickness = tiny and 3 or 5
	createTitle.TextSize = tiny and 14 or compact and 16 or 18
	firstNameBox.TextSize = tiny and 12 or compact and 14 or 16
	lastNameBox.TextSize = tiny and 12 or compact and 14 or 16
	createButton.TextSize = tiny and 12 or compact and 13 or 15
	createHint.TextSize = tiny and 10 or compact and 11 or 13
	firstNameBox.Size = UDim2.new(1, 0, 0, tiny and 32 or compact and 38 or 44)
	lastNameBox.Size = UDim2.new(1, 0, 0, tiny and 32 or compact and 38 or 44)
	createButton.Size = UDim2.new(1, 0, 0, tiny and 34 or compact and 40 or 46)
	createHint.Size = UDim2.new(1, 0, 0, tiny and 48 or compact and 56 or 66)
end

local busy = false
local pendingDeleteCitizenId = nil
local deleteButtonsByCitizenId = {}
local refreshGeneration = 0
local characterSelectDestroyed = false
local viewportConnection
local refreshList

local function setStatus(text)
	statusLabel.Text = text or ""
end

local function setBusy(nextBusy)
	busy = nextBusy
	createButton.Active = not busy
	createButton.AutoButtonColor = not busy
	createButton.BackgroundColor3 = busy and Color3.fromRGB(79, 91, 105) or COLORS.green
end

local function clearCharacterCards()
	deleteButtonsByCitizenId = {}
	for _, child in ipairs(characterList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function destroyCharacterSelect()
	if characterSelectDestroyed then
		return
	end
	characterSelectDestroyed = true
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	screenGui:Destroy()
end

local function selectCharacter(citizenId)
	if busy then
		return
	end
	setBusy(true)
	setStatus("Loading...")
	local ok, err = Remotes.SelectCharacter:InvokeServer(citizenId)
	if not ok then
		setStatus(err or "Failed to load character.")
		setBusy(false)
		return
	end
	-- Selection only hands control to QBSpawn. No Roblox character exists yet;
	-- PlayerLoaded fires later after a spawn destination is confirmed.
	destroyCharacterSelect()
end

local function makeCharacterCard(info, layoutOrder)
	local compact = responsive.compact
	local tiny = responsive.tiny
	local cardHeight = tiny and 122 or compact and 132 or 152
	local buttonHeight = tiny and 32 or 36

	local card = Instance.new("Frame")
	card.Name = "Character_" .. tostring(info.citizenId)
	card.BackgroundColor3 = COLORS.panelSoft
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, -2, 0, cardHeight)
	card.LayoutOrder = layoutOrder
	card.Parent = characterList
	addCorner(card, 8)
	addStroke(card, Color3.fromRGB(67, 80, 98), 0.2)
	addPadding(card, tiny and 10 or 14, tiny and 9 or 12, tiny and 10 or 14, tiny and 9 or 12)

	local nameLabel = makeLabel(
		card,
		"Name",
		("%s %s"):format(info.firstname, info.lastname),
		tiny and 16 or compact and 18 or 20,
		COLORS.text,
		Enum.Font.GothamBold
	)
	nameLabel.Position = UDim2.fromOffset(0, 0)
	nameLabel.Size = UDim2.new(1, -8, 0, tiny and 22 or 26)
	nameLabel.TextWrapped = false
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local metaLabel = makeLabel(
		card,
		"Meta",
		("CID %s  |  %s"):format(tostring(info.cid), tostring(info.job)),
		tiny and 12 or 14,
		COLORS.muted,
		Enum.Font.GothamMedium
	)
	metaLabel.Position = UDim2.fromOffset(0, tiny and 27 or 32)
	metaLabel.Size = UDim2.new(1, -8, 0, 22)
	metaLabel.TextWrapped = false
	metaLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local moneyLabel = makeLabel(
		card,
		"Money",
		("Cash %s   Bank %s"):format(formatMoney(info.cash), formatMoney(info.bank)),
		tiny and 12 or 14,
		COLORS.muted,
		Enum.Font.Gotham
	)
	moneyLabel.Position = UDim2.fromOffset(0, tiny and 50 or 58)
	moneyLabel.Size = UDim2.new(1, -8, 0, 22)
	moneyLabel.TextWrapped = false
	moneyLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local deleteButton = makeButton(card, "Delete", "Delete", COLORS.red)
	deleteButton.AnchorPoint = Vector2.new(0, 1)
	deleteButton.Position = UDim2.new(0, 0, 1, 0)
	deleteButton.Size = UDim2.new(0.38, -6, 0, buttonHeight)
	deleteButton.TextSize = tiny and 12 or 15
	deleteButtonsByCitizenId[info.citizenId] = deleteButton

	local playButton = makeButton(card, "Play", "Play", COLORS.green)
	playButton.AnchorPoint = Vector2.new(1, 1)
	playButton.Position = UDim2.new(1, 0, 1, 0)
	playButton.Size = UDim2.new(0.62, -6, 0, buttonHeight)
	playButton.TextSize = tiny and 12 or 15

	playButton.Activated:Connect(function()
		pendingDeleteCitizenId = nil
		selectCharacter(info.citizenId)
	end)

	deleteButton.Activated:Connect(function()
		if busy then
			return
		end

		if pendingDeleteCitizenId ~= info.citizenId then
			pendingDeleteCitizenId = info.citizenId
			for _, button in pairs(deleteButtonsByCitizenId) do
				button.Text = "Delete"
				button.BackgroundColor3 = COLORS.red
			end
			deleteButton.Text = "Confirm"
			deleteButton.BackgroundColor3 = COLORS.redConfirm
			setStatus(("Press Confirm to delete %s %s."):format(info.firstname, info.lastname))
			return
		end

		setBusy(true)
		setStatus(("Deleting %s %s..."):format(info.firstname, info.lastname))

		local ok, err = Remotes.DeleteCharacter:InvokeServer(info.citizenId)
		if not ok then
			setStatus(err or "Failed to delete character.")
			setBusy(false)
			return
		end

		pendingDeleteCitizenId = nil
		setStatus("Character deleted.")
		setBusy(false)
		task.defer(function()
			refreshList()
		end)
	end)

	return card
end

refreshList = function()
	refreshGeneration += 1
	local generation = refreshGeneration

	updateResponsiveLayout()
	pendingDeleteCitizenId = nil
	clearCharacterCards()
	setStatus("Loading characters...")

	local characters = Remotes.GetCharacters:InvokeServer()
	if generation ~= refreshGeneration or characterSelectDestroyed then
		return
	end

	countLabel.Text = ("%d/%d"):format(#characters, MAX_CHARACTER_SLOTS)

	if #characters == 0 then
		local emptyLabel =
			makeLabel(characterList, "Empty", "No characters yet.", 16, COLORS.muted, Enum.Font.GothamMedium)
		emptyLabel.Size = UDim2.new(1, -2, 0, 70)
		emptyLabel.TextXAlignment = Enum.TextXAlignment.Center
		emptyLabel.TextYAlignment = Enum.TextYAlignment.Center
	else
		for index, info in ipairs(characters) do
			makeCharacterCard(info, index)
		end
	end

	setStatus("")
end

createButton.Activated:Connect(function()
	if busy then
		return
	end

	local firstname = trim(firstNameBox.Text)
	local lastname = trim(lastNameBox.Text)

	if firstname == "" or lastname == "" then
		setStatus("Enter a first and last name.")
		return
	end

	setBusy(true)
	setStatus("Creating character...")

	local citizenId, err = Remotes.CreateCharacter:InvokeServer(firstname, lastname)
	if not citizenId then
		setStatus(err or "Failed to create character.")
		setBusy(false)
		return
	end

	firstNameBox.Text = ""
	lastNameBox.Text = ""
	setBusy(false)
	selectCharacter(citizenId)
end)

QBCoreClient.OnPlayerLoaded.Event:Connect(function()
	destroyCharacterSelect()
end)

local function bindResponsiveLayout()
	if characterSelectDestroyed then
		return
	end

	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end

	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if not characterSelectDestroyed then
				refreshList()
			end
		end)
	end

	updateResponsiveLayout()
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindResponsiveLayout)
bindResponsiveLayout()
refreshList()
