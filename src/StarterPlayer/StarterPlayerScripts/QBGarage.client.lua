-- Native public-garage UI. The server owns proximity, ownership, vehicle state,
-- spawn occupancy, and storage validation.

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
local accessContext = { garageId = "" }
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
		warn("[QBGarage] Remote call failed: " .. tostring(results[2]))
		return nil, "The garage server did not respond."
	end
	return table.unpack(results, 2, results.n)
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QBGarage"
screenGui.DisplayOrder = 57
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
shell.Size = UDim2.fromOffset(880, 620)
shell.Parent = overlay
addCorner(shell, 10)
addStroke(shell, COLORS.stroke, 0.12, 1)

local shellScale = Instance.new("UIScale")
shellScale.Parent = shell

local header = Instance.new("Frame")
header.BackgroundTransparency = 1
header.Position = UDim2.fromOffset(24, 17)
header.Size = UDim2.new(1, -48, 0, 65)
header.Parent = shell
local eyebrow = makeLabel(header, "Eyebrow", "QBCORE PARKING", 11, COLORS.green, Enum.Font.GothamBold)
eyebrow.Size = UDim2.new(1, -60, 0, 17)
local titleLabel = makeLabel(header, "Title", "Public Garage", 25, COLORS.text, Enum.Font.GothamBold)
titleLabel.Position = UDim2.fromOffset(0, 16)
titleLabel.Size = UDim2.new(0.7, 0, 0, 31)
local subtitleLabel =
	makeLabel(header, "Subtitle", "Store and retrieve your owned vehicles.", 12, COLORS.muted, Enum.Font.GothamMedium)
subtitleLabel.Position = UDim2.fromOffset(0, 47)
subtitleLabel.Size = UDim2.new(0.76, 0, 0, 18)
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
sidebar.Size = UDim2.new(0.44, -8, 1, 0)
sidebar.Parent = body
addCorner(sidebar, 9)
addStroke(sidebar, COLORS.strokeSoft, 0.2, 1)
addPadding(sidebar, 14, 14, 14, 14)

local details = Instance.new("Frame")
details.BackgroundColor3 = COLORS.panel
details.BorderSizePixel = 0
details.Position = UDim2.new(0.44, 8, 0, 0)
details.Size = UDim2.new(0.56, -8, 1, 0)
details.Parent = body
addCorner(details, 9)
addStroke(details, COLORS.strokeSoft, 0.2, 1)
addPadding(details, 20, 18, 20, 18)

local searchBox = makeTextBox(sidebar, "Search", "Search name or plate")
searchBox.Size = UDim2.new(1, 0, 0, 40)
local countLabel = makeLabel(sidebar, "Count", "0 vehicles", 11, COLORS.muted, Enum.Font.GothamMedium)
countLabel.Position = UDim2.fromOffset(0, 46)
countLabel.Size = UDim2.new(1, 0, 0, 20)

local listFrame = Instance.new("ScrollingFrame")
listFrame.BackgroundTransparency = 1
listFrame.BorderSizePixel = 0
listFrame.Position = UDim2.fromOffset(0, 75)
listFrame.Size = UDim2.new(1, 0, 1, -75)
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.CanvasSize = UDim2.fromOffset(0, 0)
listFrame.ScrollBarImageColor3 = COLORS.stroke
listFrame.ScrollBarThickness = 5
listFrame.Parent = sidebar
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 7)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listFrame

local detailEyebrow = makeLabel(details, "Category", "OWNED VEHICLE", 11, COLORS.green, Enum.Font.GothamBold)
detailEyebrow.Size = UDim2.new(1, 0, 0, 18)
local vehicleTitle = makeLabel(details, "VehicleTitle", "Select a vehicle", 25, COLORS.text, Enum.Font.GothamBold)
vehicleTitle.Position = UDim2.fromOffset(0, 21)
vehicleTitle.Size = UDim2.new(1, 0, 0, 34)
local identityLabel = makeLabel(details, "Identity", "", 12, COLORS.muted, Enum.Font.GothamMedium)
identityLabel.Position = UDim2.fromOffset(0, 57)
identityLabel.Size = UDim2.new(1, 0, 0, 20)

local stateCard = Instance.new("Frame")
stateCard.BackgroundColor3 = COLORS.blueDark
stateCard.BorderSizePixel = 0
stateCard.Position = UDim2.fromOffset(0, 92)
stateCard.Size = UDim2.new(0.5, -5, 0, 88)
stateCard.Parent = details
addCorner(stateCard, 8)
addStroke(stateCard, COLORS.blue, 0.38, 1)
addPadding(stateCard, 14, 11, 14, 11)
local stateCaption =
	makeLabel(stateCard, "Caption", "VEHICLE STATE", 10, Color3.fromRGB(190, 217, 245), Enum.Font.GothamBold)
stateCaption.Size = UDim2.new(1, 0, 0, 17)
local stateLabel = makeLabel(stateCard, "State", "—", 22, COLORS.text, Enum.Font.GothamBold)
stateLabel.Position = UDim2.fromOffset(0, 24)
stateLabel.Size = UDim2.new(1, 0, 0, 30)
local garageLabel = makeLabel(stateCard, "Garage", "", 10, Color3.fromRGB(196, 214, 234), Enum.Font.GothamMedium)
garageLabel.Position = UDim2.fromOffset(0, 59)
garageLabel.Size = UDim2.new(1, 0, 0, 15)

local financeCard = Instance.new("Frame")
financeCard.BackgroundColor3 = COLORS.panelSoft
financeCard.BorderSizePixel = 0
financeCard.Position = UDim2.new(0.5, 5, 0, 92)
financeCard.Size = UDim2.new(0.5, -5, 0, 88)
financeCard.Parent = details
addCorner(financeCard, 8)
addStroke(financeCard, COLORS.strokeSoft, 0.3, 1)
addPadding(financeCard, 14, 11, 14, 11)
local balanceCaption = makeLabel(financeCard, "Caption", "FINANCE BALANCE", 10, COLORS.muted, Enum.Font.GothamBold)
balanceCaption.Size = UDim2.new(1, 0, 0, 17)
local balanceLabel = makeLabel(financeCard, "Balance", "$0", 22, COLORS.gold, Enum.Font.GothamBold)
balanceLabel.Position = UDim2.fromOffset(0, 24)
balanceLabel.Size = UDim2.new(1, 0, 0, 30)
local installedLabel = makeLabel(financeCard, "Installed", "", 10, COLORS.muted, Enum.Font.GothamMedium)
installedLabel.Position = UDim2.fromOffset(0, 59)
installedLabel.Size = UDim2.new(1, 0, 0, 15)

local statsTitle = makeLabel(details, "StatsTitle", "Stored condition", 15, COLORS.text, Enum.Font.GothamBold)
statsTitle.Position = UDim2.fromOffset(0, 200)
statsTitle.Size = UDim2.new(1, 0, 0, 23)
local statsLabel =
	makeLabel(details, "Stats", "Fuel —   Engine —   Body —", 12, COLORS.muted, Enum.Font.GothamMedium)
statsLabel.Position = UDim2.fromOffset(0, 228)
statsLabel.Size = UDim2.new(1, 0, 0, 24)

local retrieveButton = makeButton(details, "Retrieve", "Retrieve vehicle", COLORS.green)
retrieveButton.Position = UDim2.fromOffset(0, 274)
retrieveButton.Size = UDim2.new(1, 0, 0, 45)
local storeButton = makeButton(details, "Store", "Store nearby owned vehicle", COLORS.blue)
storeButton.Position = UDim2.fromOffset(0, 330)
storeButton.Size = UDim2.new(1, 0, 0, 43)
local refreshButton = makeButton(details, "Refresh", "Refresh garage", COLORS.panelSoft)
refreshButton.Position = UDim2.fromOffset(0, 384)
refreshButton.Size = UDim2.new(1, 0, 0, 39)

local actionStatus = makeLabel(details, "Status", "", 11, COLORS.muted, Enum.Font.GothamMedium)
actionStatus.Position = UDim2.fromOffset(0, 430)
actionStatus.Size = UDim2.new(1, 0, 0, 30)
actionStatus.TextWrapped = true
actionStatus.TextXAlignment = Enum.TextXAlignment.Center
actionStatus.TextYAlignment = Enum.TextYAlignment.Top

local function setStatus(text, color)
	actionStatus.Text = text or ""
	actionStatus.TextColor3 = color or COLORS.muted
end

local function setButtonEnabled(button, enabled, color)
	button.Active = enabled and not busy
	button.AutoButtonColor = enabled and not busy
	button.BackgroundColor3 = enabled and not busy and color or COLORS.disabled
end

local function selectedVehicle()
	for _, entry in ipairs(snapshot and snapshot.vehicles or {}) do
		if entry.id == selectedOwnershipId then
			return entry
		end
	end
	local first = snapshot and snapshot.vehicles and snapshot.vehicles[1]
	selectedOwnershipId = first and first.id or nil
	return first
end

local function clearList()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child ~= listLayout then
			child:Destroy()
		end
	end
end

local render

local function renderList()
	clearList()
	local vehicles = snapshot and snapshot.vehicles or {}
	countLabel.Text = ("%d vehicle%s"):format(#vehicles, #vehicles == 1 and "" or "s")
	local query = searchBox.Text:lower():gsub("^%s+", ""):gsub("%s+$", "")
	local shown = 0
	for index, entry in ipairs(vehicles) do
		local haystack = (entry.label .. " " .. entry.brand .. " " .. entry.plate .. " " .. entry.stateLabel):lower()
		if query == "" or haystack:find(query, 1, true) then
			shown += 1
			local button = makeButton(
				listFrame,
				"Vehicle_" .. index,
				"",
				entry.id == selectedOwnershipId and COLORS.blueDark or COLORS.panelSoft
			)
			button.LayoutOrder = index
			button.Size = UDim2.new(1, -6, 0, 64)
			button.Text = ""
			local name = makeLabel(button, "Name", entry.label, 13, COLORS.text, Enum.Font.GothamBold)
			name.Position = UDim2.fromOffset(12, 8)
			name.Size = UDim2.new(0.68, -12, 0, 21)
			local plate = makeLabel(
				button,
				"Plate",
				entry.plate .. "  ·  " .. entry.stateLabel,
				10,
				COLORS.muted,
				Enum.Font.GothamMedium
			)
			plate.Position = UDim2.fromOffset(12, 34)
			plate.Size = UDim2.new(0.76, -12, 0, 18)
			local tint = entry.state == 1 and COLORS.green or entry.state == 2 and COLORS.red or COLORS.gold
			local tag = makeLabel(button, "Tag", entry.stateLabel:upper(), 9, tint, Enum.Font.GothamBold)
			tag.AnchorPoint = Vector2.new(1, 0)
			tag.Position = UDim2.new(1, -11, 0, 10)
			tag.Size = UDim2.new(0.31, 0, 0, 18)
			tag.TextXAlignment = Enum.TextXAlignment.Right
			button.Activated:Connect(function()
				if busy then
					return
				end
				selectedOwnershipId = entry.id
				setStatus("")
				render()
			end)
		end
	end
	if shown == 0 then
		local empty = makeLabel(
			listFrame,
			"Empty",
			#vehicles == 0 and "No vehicles are assigned to this garage." or "No vehicles match your search.",
			12,
			COLORS.muted,
			Enum.Font.Gotham
		)
		empty.Size = UDim2.new(1, -6, 0, 72)
		empty.TextWrapped = true
		empty.TextXAlignment = Enum.TextXAlignment.Center
	end
end

render = function()
	local garage = snapshot and snapshot.garage or {}
	titleLabel.Text = tostring(garage.label or "Public Garage")
	subtitleLabel.Text = snapshot
			and snapshot.sharedGarages
			and "Shared public storage — retrieve owned vehicles from any garage."
		or "Vehicles are retrieved from the garage where they were stored."
	local entry = selectedVehicle()
	detailEyebrow.Text = entry and string.upper(entry.category) or "OWNED VEHICLE"
	vehicleTitle.Text = entry and entry.label or "Select a vehicle"
	identityLabel.Text = entry and (entry.brand .. "  ·  Plate " .. entry.plate) or "No vehicle selected."
	stateLabel.Text = entry and entry.stateLabel or "—"
	stateLabel.TextColor3 = entry
			and (entry.state == 1 and COLORS.text or entry.state == 2 and COLORS.red or COLORS.gold)
		or COLORS.text
	garageLabel.Text = entry and ("Stored at " .. entry.garage) or ""
	balanceLabel.Text = formatMoney(entry and entry.balance or 0)
	installedLabel.Text = entry and (entry.installed and "Template installed" or "Template missing") or ""
	installedLabel.TextColor3 = entry and entry.installed and COLORS.muted or COLORS.red
	statsLabel.Text = entry
			and ("Fuel %d%%   ·   Engine %d%%   ·   Body %d%%"):format(
				entry.fuel,
				math.floor(entry.engine / 10),
				math.floor(entry.body / 10)
			)
		or "Fuel —   Engine —   Body —"
	setButtonEnabled(retrieveButton, entry ~= nil and entry.state == 1 and entry.installed, COLORS.green)
	local nearby = snapshot and snapshot.nearby
	storeButton.Text = nearby and ("Store " .. nearby.label .. "  ·  " .. nearby.plate) or "Store nearby owned vehicle"
	setButtonEnabled(storeButton, nearby ~= nil, COLORS.blue)
	setButtonEnabled(refreshButton, true, COLORS.panelSoft)
	renderList()
end

local function setBusy(nextBusy)
	busy = nextBusy
	closeButton.Active = not busy
	searchBox.TextEditable = not busy
	if snapshot then
		render()
	end
end

local function updateResponsiveLayout()
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	shellScale.Scale = math.clamp(math.min(viewport.X / 930, viewport.Y / 670), 0.54, 1)
end

local function closeGarage(force)
	if not isOpen or (busy and force ~= true) then
		return
	end
	isOpen = false
	screenGui.Enabled = false
	GuiService.SelectedObject = nil
	searchBox:ReleaseFocus()
	setStatus("")
end

local function fetchSnapshot(silent)
	if not isOpen or busy then
		return false
	end
	setBusy(true)
	if not silent then
		setStatus("Loading garage...", COLORS.muted)
	end
	local nextSnapshot, err = callRemote(Remotes.GetGarage, accessContext)
	setBusy(false)
	if not nextSnapshot then
		setStatus(err or "The garage could not be loaded.", COLORS.red)
		return false
	end
	snapshot = nextSnapshot
	if not selectedVehicle() then
		selectedOwnershipId = nil
	end
	if not silent then
		setStatus("Garage ready.", COLORS.green)
	end
	render()
	return true
end

local function openGarage(context)
	context = type(context) == "table" and context or {}
	accessContext = { garageId = tostring(context.garageId or "") }
	selectedOwnershipId = nil
	snapshot = nil
	isOpen = true
	screenGui.Enabled = true
	searchBox.Text = ""
	updateResponsiveLayout()
	if not fetchSnapshot(false) then
		task.delay(3, function()
			if isOpen and not snapshot then
				closeGarage()
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
	setStatus("Processing garage request...", COLORS.muted)
	local ok, result = callRemote(Remotes.GarageAction, action, payload)
	setBusy(false)
	if ok ~= true then
		setStatus(result or "The garage request was declined.", COLORS.red)
		return
	end
	snapshot = result.snapshot or snapshot
	setStatus(result.message or "Garage request complete.", COLORS.green)
	render()
	if closeOnSuccess then
		closeGarage()
	end
end

retrieveButton.Activated:Connect(function()
	local entry = selectedVehicle()
	if entry and entry.state == 1 then
		runAction("retrieve", { ownershipId = entry.id }, true)
	end
end)

storeButton.Activated:Connect(function()
	if snapshot and snapshot.nearby then
		runAction("store", {}, true)
	end
end)

refreshButton.Activated:Connect(function()
	fetchSnapshot(false)
end)
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	if isOpen and snapshot and not busy then
		renderList()
	end
end)
closeButton.Activated:Connect(closeGarage)
Remotes.OpenGarage.OnClientEvent:Connect(openGarage)

QBCoreClient.OnPlayerLoaded.Event:Connect(function()
	if isOpen then
		closeGarage(true)
	end
end)
player.CharacterRemoving:Connect(function()
	if isOpen then
		closeGarage(true)
	end
end)
UserInputService.InputBegan:Connect(function(input)
	if isOpen and not busy and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then
		closeGarage()
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
