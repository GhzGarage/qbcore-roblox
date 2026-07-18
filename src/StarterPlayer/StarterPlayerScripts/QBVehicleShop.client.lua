-- Native vehicle-shop UI styled alongside the other QBCore Roblox panels.
-- Catalog, pricing, ownership, proximity, and spawning remain server-authoritative.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local QBCoreClient = require(ReplicatedStorage.QBCoreClient)
local Remotes = require(ReplicatedStorage.QBRemotes)
local player = Players.LocalPlayer

local COLORS = {
	page = Color3.fromRGB(10, 13, 18),
	shell = Color3.fromRGB(25, 31, 39),
	panel = Color3.fromRGB(32, 39, 49),
	panelSoft = Color3.fromRGB(38, 46, 58),
	input = Color3.fromRGB(19, 24, 31),
	stroke = Color3.fromRGB(73, 87, 104),
	strokeSoft = Color3.fromRGB(57, 69, 84),
	text = Color3.fromRGB(240, 244, 248),
	muted = Color3.fromRGB(157, 170, 184),
	green = Color3.fromRGB(65, 172, 110),
	blue = Color3.fromRGB(74, 143, 216),
	blueDark = Color3.fromRGB(48, 99, 157),
	gold = Color3.fromRGB(229, 181, 77),
	red = Color3.fromRGB(202, 79, 83),
	disabled = Color3.fromRGB(79, 89, 101),
}

local snapshot = nil
local accessContext = { mode = "showroom", locationId = "" }
local activeTab = "browse"
local selectedVehicleName = nil
local selectedOwnershipId = nil
local isOpen = false
local busy = false

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
end

local function addStroke(parent, color, transparency, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or COLORS.stroke
	stroke.Transparency = transparency or 0
	stroke.Thickness = thickness or 1
	stroke.Parent = parent
end

local function addPadding(parent, left, top, right, bottom)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, left or 0)
	padding.PaddingTop = UDim.new(0, top or 0)
	padding.PaddingRight = UDim.new(0, right or left or 0)
	padding.PaddingBottom = UDim.new(0, bottom or top or 0)
	padding.Parent = parent
end

local function makeLabel(parent, name, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = font or Enum.Font.Gotham
	label.Text = text or ""
	label.TextColor3 = color or COLORS.text
	label.TextSize = size or 14
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	return label
end

local function makeButton(parent, name, text, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = true
	button.BackgroundColor3 = color or COLORS.panelSoft
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = text or "Button"
	button.TextColor3 = COLORS.text
	button.TextSize = 13
	button.Parent = parent
	addCorner(button, 7)
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
	box.PlaceholderText = placeholder or ""
	box.Text = ""
	box.TextColor3 = COLORS.text
	box.TextSize = 14
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = parent
	addCorner(box, 7)
	addStroke(box, COLORS.strokeSoft, 0.15, 1)
	addPadding(box, 12, 0, 12, 0)
	return box
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

local function callRemote(remote, ...)
	local results = table.pack(pcall(remote.InvokeServer, remote, ...))
	if not results[1] then
		warn("[QBVehicleShop] Remote call failed: " .. tostring(results[2]))
		return nil, "The vehicle-shop server did not respond."
	end
	return table.unpack(results, 2, results.n)
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QBVehicleShop"
screenGui.DisplayOrder = 56
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local overlay = Instance.new("Frame")
overlay.BackgroundColor3 = COLORS.page
overlay.BackgroundTransparency = 0.1
overlay.BorderSizePixel = 0
overlay.Active = true
overlay.Size = UDim2.fromScale(1, 1)
overlay.Parent = screenGui

local shell = Instance.new("Frame")
shell.AnchorPoint = Vector2.new(0.5, 0.5)
shell.BackgroundColor3 = COLORS.shell
shell.BorderSizePixel = 0
shell.Position = UDim2.fromScale(0.5, 0.5)
shell.Size = UDim2.fromOffset(960, 620)
shell.Parent = overlay
addCorner(shell, 10)
addStroke(shell, COLORS.stroke, 0.12, 1)

local shellScale = Instance.new("UIScale")
shellScale.Parent = shell

local header = Instance.new("Frame")
header.BackgroundTransparency = 1
header.Position = UDim2.fromOffset(24, 17)
header.Size = UDim2.new(1, -48, 0, 66)
header.Parent = shell

local eyebrow = makeLabel(header, "Eyebrow", "QBCORE MOTOR GROUP", 11, COLORS.green, Enum.Font.GothamBold)
eyebrow.Size = UDim2.new(1, -60, 0, 17)
local titleLabel = makeLabel(header, "Title", "Vehicle Shop", 25, COLORS.text, Enum.Font.GothamBold)
titleLabel.Position = UDim2.fromOffset(0, 16)
titleLabel.Size = UDim2.new(0.62, 0, 0, 31)
local subtitleLabel = makeLabel(
	header,
	"Subtitle",
	"Browse, test drive, purchase, and manage your vehicles.",
	12,
	COLORS.muted,
	Enum.Font.GothamMedium
)
subtitleLabel.Position = UDim2.fromOffset(0, 47)
subtitleLabel.Size = UDim2.new(0.75, 0, 0, 18)
local closeButton = makeButton(header, "Close", "×", COLORS.panelSoft)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, 0, 0, 2)
closeButton.Size = UDim2.fromOffset(42, 42)
closeButton.TextSize = 24

local divider = Instance.new("Frame")
divider.BackgroundColor3 = COLORS.strokeSoft
divider.BackgroundTransparency = 0.25
divider.BorderSizePixel = 0
divider.Position = UDim2.fromOffset(24, 94)
divider.Size = UDim2.new(1, -48, 0, 1)
divider.Parent = shell

local body = Instance.new("Frame")
body.BackgroundTransparency = 1
body.Position = UDim2.fromOffset(24, 111)
body.Size = UDim2.new(1, -48, 1, -135)
body.Parent = shell

local sidebar = Instance.new("Frame")
sidebar.BackgroundColor3 = COLORS.panel
sidebar.BorderSizePixel = 0
sidebar.Size = UDim2.new(0.39, -8, 1, 0)
sidebar.Parent = body
addCorner(sidebar, 9)
addStroke(sidebar, COLORS.strokeSoft, 0.2, 1)
addPadding(sidebar, 14, 14, 14, 14)

local details = Instance.new("Frame")
details.BackgroundColor3 = COLORS.panel
details.BorderSizePixel = 0
details.Position = UDim2.new(0.39, 8, 0, 0)
details.Size = UDim2.new(0.61, -8, 1, 0)
details.Parent = body
addCorner(details, 9)
addStroke(details, COLORS.strokeSoft, 0.2, 1)
addPadding(details, 22, 20, 22, 20)

local tabs = Instance.new("Frame")
tabs.BackgroundTransparency = 1
tabs.Size = UDim2.new(1, 0, 0, 38)
tabs.Parent = sidebar
local browseTab = makeButton(tabs, "Browse", "Browse", COLORS.blueDark)
browseTab.Size = UDim2.new(0.5, -4, 1, 0)
local ownedTab = makeButton(tabs, "Owned", "Owned (0)", COLORS.panelSoft)
ownedTab.Position = UDim2.new(0.5, 4, 0, 0)
ownedTab.Size = UDim2.new(0.5, -4, 1, 0)

local searchBox = makeTextBox(sidebar, "Search", "Search name, category, or color")
searchBox.Position = UDim2.fromOffset(0, 50)
searchBox.Size = UDim2.new(1, 0, 0, 40)

local listFrame = Instance.new("ScrollingFrame")
listFrame.BackgroundTransparency = 1
listFrame.BorderSizePixel = 0
listFrame.Position = UDim2.fromOffset(0, 102)
listFrame.Size = UDim2.new(1, 0, 1, -102)
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.CanvasSize = UDim2.fromOffset(0, 0)
listFrame.ScrollBarImageColor3 = COLORS.stroke
listFrame.ScrollBarThickness = 5
listFrame.Parent = sidebar
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 7)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listFrame

local detailEyebrow = makeLabel(details, "Category", "SELECT A VEHICLE", 11, COLORS.green, Enum.Font.GothamBold)
detailEyebrow.Size = UDim2.new(1, 0, 0, 18)
local vehicleTitle = makeLabel(details, "VehicleTitle", "Vehicle catalog", 27, COLORS.text, Enum.Font.GothamBold)
vehicleTitle.Position = UDim2.fromOffset(0, 22)
vehicleTitle.Size = UDim2.new(1, 0, 0, 36)
local brandLabel = makeLabel(details, "Brand", "", 13, COLORS.muted, Enum.Font.GothamMedium)
brandLabel.Position = UDim2.fromOffset(0, 61)
brandLabel.Size = UDim2.new(1, 0, 0, 20)

local priceCard = Instance.new("Frame")
priceCard.BackgroundColor3 = COLORS.blueDark
priceCard.BorderSizePixel = 0
priceCard.Position = UDim2.fromOffset(0, 96)
priceCard.Size = UDim2.new(0.48, -5, 0, 92)
priceCard.Parent = details
addCorner(priceCard, 8)
addStroke(priceCard, COLORS.blue, 0.38, 1)
addPadding(priceCard, 15, 12, 15, 12)
local priceCaption =
	makeLabel(priceCard, "Caption", "PURCHASE PRICE", 10, Color3.fromRGB(190, 217, 245), Enum.Font.GothamBold)
priceCaption.Size = UDim2.new(1, 0, 0, 17)
local priceLabel = makeLabel(priceCard, "Price", "$0", 27, COLORS.text, Enum.Font.GothamBold)
priceLabel.Position = UDim2.fromOffset(0, 24)
priceLabel.Size = UDim2.new(1, 0, 0, 35)
local priceNote =
	makeLabel(priceCard, "Note", "Outright purchase", 10, Color3.fromRGB(196, 214, 234), Enum.Font.GothamMedium)
priceNote.Position = UDim2.fromOffset(0, 61)
priceNote.Size = UDim2.new(1, 0, 0, 15)

local statusCard = Instance.new("Frame")
statusCard.BackgroundColor3 = COLORS.panelSoft
statusCard.BorderSizePixel = 0
statusCard.Position = UDim2.new(0.48, 5, 0, 96)
statusCard.Size = UDim2.new(0.52, -5, 0, 92)
statusCard.Parent = details
addCorner(statusCard, 8)
addStroke(statusCard, COLORS.strokeSoft, 0.3, 1)
addPadding(statusCard, 15, 12, 15, 12)
local statusCaption = makeLabel(statusCard, "Caption", "AVAILABILITY", 10, COLORS.muted, Enum.Font.GothamBold)
statusCaption.Size = UDim2.new(1, 0, 0, 17)
local availabilityLabel = makeLabel(statusCard, "Availability", "Ready", 20, COLORS.green, Enum.Font.GothamBold)
availabilityLabel.Position = UDim2.fromOffset(0, 25)
availabilityLabel.Size = UDim2.new(1, 0, 0, 28)
local plateLabel = makeLabel(statusCard, "Plate", "Template installed", 10, COLORS.muted, Enum.Font.GothamMedium)
plateLabel.Position = UDim2.fromOffset(0, 61)
plateLabel.Size = UDim2.new(1, 0, 0, 15)

local descriptionLabel = makeLabel(
	details,
	"Description",
	"Choose a vehicle from the list to view its details.",
	13,
	COLORS.muted,
	Enum.Font.Gotham
)
descriptionLabel.Position = UDim2.fromOffset(0, 208)
descriptionLabel.Size = UDim2.new(1, 0, 0, 58)
descriptionLabel.TextWrapped = true
descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top

local downBox = makeTextBox(details, "DownPayment", "Down payment")
downBox.Position = UDim2.fromOffset(0, 278)
downBox.Size = UDim2.new(0.5, -5, 0, 40)
local paymentsBox = makeTextBox(details, "Payments", "Number of payments")
paymentsBox.Position = UDim2.new(0.5, 5, 0, 278)
paymentsBox.Size = UDim2.new(0.5, -5, 0, 40)

local primaryButton = makeButton(details, "Primary", "Purchase", COLORS.green)
primaryButton.Position = UDim2.fromOffset(0, 333)
primaryButton.Size = UDim2.new(1, 0, 0, 45)
local secondaryButton = makeButton(details, "Secondary", "Test drive", COLORS.blue)
secondaryButton.Position = UDim2.fromOffset(0, 389)
secondaryButton.Size = UDim2.new(0.5, -5, 0, 43)
local financeButton = makeButton(details, "Finance", "Finance", COLORS.gold)
financeButton.Position = UDim2.new(0.5, 5, 0, 389)
financeButton.Size = UDim2.new(0.5, -5, 0, 43)

local actionStatus = makeLabel(details, "ActionStatus", "", 12, COLORS.muted, Enum.Font.GothamMedium)
actionStatus.Position = UDim2.fromOffset(0, 445)
actionStatus.Size = UDim2.new(1, 0, 0, 38)
actionStatus.TextWrapped = true
actionStatus.TextXAlignment = Enum.TextXAlignment.Center
actionStatus.TextYAlignment = Enum.TextYAlignment.Top

local footer = makeLabel(
	details,
	"Footer",
	"All transactions and spawn checks are validated by the server.",
	10,
	COLORS.muted,
	Enum.Font.GothamMedium
)
footer.AnchorPoint = Vector2.new(0, 1)
footer.Position = UDim2.new(0, 0, 1, 0)
footer.Size = UDim2.new(1, 0, 0, 17)
footer.TextXAlignment = Enum.TextXAlignment.Center

local function setStatus(text, color)
	actionStatus.Text = text or ""
	actionStatus.TextColor3 = color or COLORS.muted
end

local function setButtonEnabled(button, enabled, color)
	button.Active = enabled and not busy
	button.AutoButtonColor = enabled and not busy
	button.BackgroundColor3 = enabled and not busy and color or COLORS.disabled
end

local function findCatalog(name)
	for _, entry in ipairs(snapshot and snapshot.catalog or {}) do
		if entry.name == name then
			return entry
		end
	end
	return nil
end

local function findOwned(id)
	for _, entry in ipairs(snapshot and snapshot.owned or {}) do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

local function clearList()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child ~= listLayout then
			child:Destroy()
		end
	end
end

local render

local function selectCatalog(name)
	selectedVehicleName = name
	render()
end

local function selectOwned(id)
	selectedOwnershipId = id
	render()
end

local function renderList()
	clearList()
	local query = searchBox.Text:lower():gsub("^%s+", ""):gsub("%s+$", "")
	local source = activeTab == "browse" and (snapshot and snapshot.catalog or {})
		or (snapshot and snapshot.owned or {})
	local visibleCount = 0
	for index, entry in ipairs(source) do
		local haystack = (
			tostring(entry.label)
			.. " "
			.. tostring(entry.brand)
			.. " "
			.. tostring(entry.category)
			.. " "
			.. tostring(entry.color or "")
			.. " "
			.. tostring(entry.plate or "")
		):lower()
		if query == "" or haystack:find(query, 1, true) then
			visibleCount += 1
			local selected = activeTab == "browse" and entry.name == selectedVehicleName
				or activeTab == "owned" and entry.id == selectedOwnershipId
			local button =
				makeButton(listFrame, "Entry_" .. tostring(index), "", selected and COLORS.blueDark or COLORS.panelSoft)
			button.LayoutOrder = index
			button.Size = UDim2.new(1, -6, 0, 62)
			button.Text = ""
			local name = makeLabel(button, "Name", tostring(entry.label), 13, COLORS.text, Enum.Font.GothamBold)
			name.Position = UDim2.fromOffset(12, 7)
			name.Size = UDim2.new(0.7, -12, 0, 21)
			local detail = activeTab == "browse"
					and (string.upper(tostring(entry.category)) .. "  ·  " .. formatMoney(entry.price))
				or (tostring(entry.plate) .. "  ·  " .. (entry.spawned and "OUT" or "READY"))
			local detailLabel = makeLabel(button, "Detail", detail, 10, COLORS.muted, Enum.Font.GothamMedium)
			detailLabel.Position = UDim2.fromOffset(12, 32)
			detailLabel.Size = UDim2.new(0.76, -12, 0, 18)
			local tagText = activeTab == "browse"
					and (entry.owned and "OWNED" or (entry.installed and "SALE" or "MISSING"))
				or (entry.balance > 0 and "FINANCED" or "OWNED")
			local tag = makeLabel(
				button,
				"Tag",
				tagText,
				9,
				entry.installed == false and COLORS.red or COLORS.green,
				Enum.Font.GothamBold
			)
			tag.AnchorPoint = Vector2.new(1, 0)
			tag.Position = UDim2.new(1, -11, 0, 9)
			tag.Size = UDim2.new(0.3, 0, 0, 18)
			tag.TextXAlignment = Enum.TextXAlignment.Right
			button.Activated:Connect(function()
				if busy then
					return
				end
				if activeTab == "browse" then
					selectCatalog(entry.name)
				else
					selectOwned(entry.id)
				end
			end)
		end
	end
	if visibleCount == 0 then
		local empty = makeLabel(
			listFrame,
			"Empty",
			activeTab == "browse" and "No vehicles match your search." or "No owned vehicles yet.",
			12,
			COLORS.muted,
			Enum.Font.Gotham
		)
		empty.Size = UDim2.new(1, -6, 0, 70)
		empty.TextWrapped = true
		empty.TextXAlignment = Enum.TextXAlignment.Center
	end
end

local function renderBrowse()
	local entry = findCatalog(selectedVehicleName) or (snapshot and snapshot.catalog and snapshot.catalog[1])
	if entry then
		selectedVehicleName = entry.name
	end
	detailEyebrow.Text = entry and string.upper(entry.category) or "VEHICLE CATALOG"
	vehicleTitle.Text = entry and entry.label or "No vehicles available"
	brandLabel.Text = entry and (entry.brand .. (entry.color ~= "" and ("  ·  " .. entry.color) or "")) or ""
	priceLabel.Text = formatMoney(entry and entry.price or 0)
	priceCaption.Text = "PURCHASE PRICE"
	priceNote.Text = entry and entry.owned and "Already in your collection" or "Outright purchase"
	availabilityLabel.Text = not entry and "Unavailable" or entry.installed and "Ready" or "Template missing"
	availabilityLabel.TextColor3 = entry and entry.installed and COLORS.green or COLORS.red
	plateLabel.Text = entry and entry.installed and "Template installed" or "Install model in QBVehicleModels"
	descriptionLabel.Text = entry and entry.description or "No sellable vehicles are configured."
	local price = entry and entry.price or 0
	local financeAvailable = entry ~= nil and price > 0 and not entry.owned
	downBox.Visible = financeAvailable
	paymentsBox.Visible = financeAvailable
	primaryButton.Text = entry and entry.owned and "Already owned" or ("Purchase for " .. formatMoney(price))
	secondaryButton.Text = "Start test drive"
	financeButton.Text = financeAvailable and "Finance vehicle"
		or (price <= 0 and "No financing needed" or "Finance unavailable")
	setButtonEnabled(primaryButton, entry ~= nil and not entry.owned, COLORS.green)
	setButtonEnabled(secondaryButton, entry ~= nil and entry.installed, COLORS.blue)
	setButtonEnabled(financeButton, financeAvailable, COLORS.gold)
end

local function renderOwned()
	local entry = findOwned(selectedOwnershipId) or (snapshot and snapshot.owned and snapshot.owned[1])
	if entry then
		selectedOwnershipId = entry.id
	end
	detailEyebrow.Text = "OWNED VEHICLE"
	vehicleTitle.Text = entry and entry.label or "No owned vehicles"
	brandLabel.Text = entry and (entry.brand .. "  ·  " .. string.upper(entry.category))
		or "Purchase a vehicle from the Browse tab."
	priceCaption.Text = "FINANCE BALANCE"
	priceLabel.Text = formatMoney(entry and entry.balance or 0)
	priceNote.Text = entry and entry.balance > 0 and (("%d payments remaining"):format(entry.paymentsLeft))
		or "Paid in full"
	availabilityLabel.Text = not entry and "Unavailable"
		or entry.spawned and "Already out"
		or entry.installed and "Ready to spawn"
		or "Template missing"
	availabilityLabel.TextColor3 = entry and not entry.spawned and entry.installed and COLORS.green
		or (entry and entry.spawned and COLORS.gold or COLORS.red)
	plateLabel.Text = entry and ("Plate " .. entry.plate) or ""
	descriptionLabel.Text = entry
			and entry.balance > 0
			and ("Minimum payment " .. formatMoney(entry.paymentAmount) .. ". Pay off the remaining balance from this finance desk.")
		or "Release this vehicle at the dealership exit. Active vehicles must be cleared before spawning another at that point."
	downBox.Visible = false
	paymentsBox.Visible = false
	primaryButton.Text = "Spawn owned vehicle"
	secondaryButton.Text = entry and entry.balance > 0 and ("Pay off " .. formatMoney(entry.balance)) or "Paid in full"
	financeButton.Text = "Browse catalog"
	setButtonEnabled(
		primaryButton,
		entry ~= nil and entry.installed and not entry.spawned and accessContext.mode == "finance",
		COLORS.green
	)
	setButtonEnabled(
		secondaryButton,
		entry ~= nil and entry.balance > 0 and accessContext.mode == "finance",
		COLORS.gold
	)
	setButtonEnabled(financeButton, true, COLORS.blue)
end

render = function()
	titleLabel.Text = snapshot and snapshot.label or "Vehicle Shop"
	ownedTab.Text = ("Owned (%d)"):format(snapshot and #(snapshot.owned or {}) or 0)
	browseTab.BackgroundColor3 = activeTab == "browse" and COLORS.blueDark or COLORS.panelSoft
	ownedTab.BackgroundColor3 = activeTab == "owned" and COLORS.blueDark or COLORS.panelSoft
	if activeTab == "browse" then
		renderBrowse()
	else
		renderOwned()
	end
	renderList()
end

local function setBusy(nextBusy)
	busy = nextBusy
	closeButton.Active = not busy
	browseTab.Active = not busy
	ownedTab.Active = not busy
	searchBox.TextEditable = not busy
	if snapshot then
		render()
	end
end

local function updateResponsiveLayout()
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	shellScale.Scale = math.clamp(math.min(viewport.X / 1010, viewport.Y / 670), 0.52, 1)
end

local function closeShop(force)
	if not isOpen or (busy and force ~= true) then
		return
	end
	isOpen = false
	screenGui.Enabled = false
	GuiService.SelectedObject = nil
	searchBox:ReleaseFocus()
	downBox:ReleaseFocus()
	paymentsBox:ReleaseFocus()
	setStatus("")
end

local function fetchSnapshot()
	if not isOpen or busy then
		return false
	end
	setBusy(true)
	setStatus("Loading vehicle catalog...", COLORS.muted)
	local nextSnapshot, err = callRemote(Remotes.GetVehicleShop, accessContext)
	setBusy(false)
	if not nextSnapshot then
		setStatus(err or "The vehicle shop could not be loaded.", COLORS.red)
		return false
	end
	snapshot = nextSnapshot
	if selectedVehicleName == nil or not findCatalog(selectedVehicleName) then
		selectedVehicleName = snapshot.selectedVehicle
	end
	if accessContext.mode == "finance" and #(snapshot.owned or {}) > 0 then
		activeTab = "owned"
	else
		activeTab = "browse"
	end
	setStatus("Catalog ready.", COLORS.green)
	render()
	return true
end

local function openShop(context)
	context = type(context) == "table" and context or {}
	accessContext = {
		mode = context.mode == "finance" and "finance" or "showroom",
		locationId = tostring(context.locationId or ""),
		vehicleName = tostring(context.vehicleName or ""),
	}
	selectedVehicleName = accessContext.vehicleName ~= "" and accessContext.vehicleName or nil
	selectedOwnershipId = nil
	activeTab = accessContext.mode == "finance" and "owned" or "browse"
	snapshot = nil
	isOpen = true
	screenGui.Enabled = true
	searchBox.Text, downBox.Text, paymentsBox.Text = "", "", ""
	updateResponsiveLayout()
	if not fetchSnapshot() then
		task.delay(3, function()
			if isOpen and not snapshot then
				closeShop()
			end
		end)
	end
end

local function runAction(action, payload, closeOnSuccess)
	if busy or not isOpen then
		return
	end
	payload = type(payload) == "table" and payload or {}
	payload.access = accessContext
	setBusy(true)
	setStatus("Processing request...", COLORS.muted)
	local ok, result = callRemote(Remotes.VehicleShopAction, action, payload)
	setBusy(false)
	if ok ~= true then
		setStatus(result or "The request was declined.", COLORS.red)
		return
	end
	snapshot = result.snapshot or snapshot
	setStatus(result.message or "Request complete.", COLORS.green)
	render()
	if closeOnSuccess then
		closeShop()
	end
end

browseTab.Activated:Connect(function()
	if busy then
		return
	end
	activeTab = "browse"
	setStatus("")
	render()
end)

ownedTab.Activated:Connect(function()
	if busy then
		return
	end
	activeTab = "owned"
	setStatus(
		accessContext.mode == "finance" and "Select an owned vehicle."
			or "Use the finance desk to spawn owned vehicles.",
		COLORS.muted
	)
	render()
end)

primaryButton.Activated:Connect(function()
	if activeTab == "browse" then
		local entry = findCatalog(selectedVehicleName)
		if entry and not entry.owned then
			runAction("purchase", { vehicleName = entry.name }, true)
		end
	else
		local entry = findOwned(selectedOwnershipId)
		if entry then
			runAction("spawn_owned", { ownershipId = entry.id }, true)
		end
	end
end)

secondaryButton.Activated:Connect(function()
	if activeTab == "browse" then
		local entry = findCatalog(selectedVehicleName)
		if entry then
			runAction("test_drive", { vehicleName = entry.name }, true)
		end
	else
		local entry = findOwned(selectedOwnershipId)
		if entry and entry.balance > 0 then
			runAction("finance_payment", { ownershipId = entry.id, payoff = true }, false)
		end
	end
end)

financeButton.Activated:Connect(function()
	if activeTab == "owned" then
		activeTab = "browse"
		setStatus("")
		render()
		return
	end
	local entry = findCatalog(selectedVehicleName)
	if entry and entry.price > 0 and not entry.owned then
		runAction(
			"finance",
			{ vehicleName = entry.name, downPayment = downBox.Text, payments = paymentsBox.Text },
			true
		)
	end
end)

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	if isOpen and snapshot and not busy then
		renderList()
	end
end)

closeButton.Activated:Connect(closeShop)
Remotes.OpenVehicleShop.OnClientEvent:Connect(openShop)

QBCoreClient.OnPlayerLoaded.Event:Connect(function()
	if isOpen then
		closeShop(true)
	end
end)

player.CharacterRemoving:Connect(function()
	if isOpen then
		closeShop(true)
	end
end)

UserInputService.InputBegan:Connect(function(input)
	if isOpen and not busy and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then
		closeShop()
	end
end)

local viewportConnection = nil
local function bindResponsiveLayout()
	if viewportConnection then
		viewportConnection:Disconnect()
	end
	local camera = Workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveLayout)
	end
	updateResponsiveLayout()
end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindResponsiveLayout)
bindResponsiveLayout()
