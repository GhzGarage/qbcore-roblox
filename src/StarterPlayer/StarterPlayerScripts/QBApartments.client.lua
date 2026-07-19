-- Apartment entrance, doorbell, and stash panels. World prompts are created and
-- validated by ApartmentService; this client only renders snapshots and requests.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Remotes = require(ReplicatedStorage.QBRemotes)

local COLORS = {
	shade = Color3.fromRGB(6, 9, 13),
	panel = Color3.fromRGB(14, 18, 24),
	soft = Color3.fromRGB(23, 29, 38),
	line = Color3.fromRGB(54, 65, 80),
	text = Color3.fromRGB(238, 242, 247),
	muted = Color3.fromRGB(151, 163, 180),
	green = Color3.fromRGB(38, 166, 112),
	blue = Color3.fromRGB(52, 126, 190),
	red = Color3.fromRGB(184, 67, 67),
}

local function corner(parent, radius)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function stroke(parent)
	local value = Instance.new("UIStroke")
	value.Color = COLORS.line
	value.Transparency = 0.15
	value.Parent = parent
end

local function label(parent, name, text, size, color, font)
	local value = Instance.new("TextLabel")
	value.Name = name
	value.BackgroundTransparency = 1
	value.Font = font or Enum.Font.Gotham
	value.Text = text or ""
	value.TextColor3 = color or COLORS.text
	value.TextSize = size or 14
	value.TextWrapped = true
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Parent = parent
	return value
end

local function button(parent, name, text, color)
	local value = Instance.new("TextButton")
	value.Name = name
	value.AutoButtonColor = true
	value.BackgroundColor3 = color or COLORS.soft
	value.BorderSizePixel = 0
	value.Font = Enum.Font.GothamBold
	value.Text = text
	value.TextColor3 = COLORS.text
	value.TextSize = 13
	value.Parent = parent
	corner(value, 7)
	return value
end

local screen = Instance.new("ScreenGui")
screen.Name = "QBApartments"
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
screen.DisplayOrder = 105
screen.Enabled = false
screen.Parent = player:WaitForChild("PlayerGui")

local shade = Instance.new("TextButton")
shade.Name = "Shade"
shade.AutoButtonColor = false
shade.BackgroundColor3 = COLORS.shade
shade.BackgroundTransparency = 0.35
shade.BorderSizePixel = 0
shade.Size = UDim2.fromScale(1, 1)
shade.Text = ""
shade.Parent = screen

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = COLORS.panel
panel.BorderSizePixel = 0
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(680, 560)
panel.Parent = screen
corner(panel, 11)
stroke(panel)

local title = label(panel, "Title", "APARTMENTS", 22, COLORS.text, Enum.Font.GothamBold)
title.Position = UDim2.fromOffset(22, 18)
title.Size = UDim2.new(1, -84, 0, 32)

local subtitle = label(panel, "Subtitle", "", 12, COLORS.muted, Enum.Font.GothamMedium)
subtitle.Position = UDim2.fromOffset(22, 50)
subtitle.Size = UDim2.new(1, -44, 0, 32)

local close = button(panel, "Close", "×", COLORS.soft)
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -16, 0, 16)
close.Size = UDim2.fromOffset(38, 34)
close.TextSize = 21

local content = Instance.new("ScrollingFrame")
content.Name = "Content"
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.Position = UDim2.fromOffset(20, 88)
content.Size = UDim2.new(1, -40, 1, -132)
content.CanvasSize = UDim2.fromOffset(0, 0)
content.ScrollBarThickness = 5
content.ScrollBarImageColor3 = COLORS.line
content.Parent = panel

local status = label(panel, "Status", "", 12, COLORS.muted, Enum.Font.GothamMedium)
status.AnchorPoint = Vector2.new(0, 1)
status.Position = UDim2.new(0, 22, 1, -12)
status.Size = UDim2.new(1, -44, 0, 25)
status.TextXAlignment = Enum.TextXAlignment.Center

local currentView
local currentPayload
local busy = false

local function resize()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	panel.Size = UDim2.fromOffset(math.min(680, viewport.X - 24), math.min(560, viewport.Y - 24))
end

local function clearContent()
	for _, child in ipairs(content:GetChildren()) do child:Destroy() end
	content.CanvasSize = UDim2.fromOffset(0, 0)
end

local function closePanel()
	if busy then return end
	screen.Enabled = false
	currentView, currentPayload = nil, nil
end

local function call(action, payload)
	if busy then return false end
	busy = true
	status.TextColor3 = COLORS.muted
	status.Text = "Working..."
	local result = table.pack(pcall(Remotes.ApartmentAction.InvokeServer, Remotes.ApartmentAction, action, payload or {}))
	busy = false
	if not result[1] or result[2] ~= true then
		status.TextColor3 = COLORS.red
		status.Text = tostring(result[3] or "The apartment action failed.")
		return false
	end
	status.TextColor3 = COLORS.green
	status.Text = "Done."
	return true, result[3]
end

local function sectionHeading(text, y)
	local value = label(content, "Heading", text, 11, COLORS.muted, Enum.Font.GothamBold)
	value.Position = UDim2.fromOffset(2, y)
	value.Size = UDim2.new(1, -4, 0, 20)
	return y + 25
end

local function actionRow(name, detail, actionText, y, color, callback)
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundColor3 = COLORS.soft
	row.BorderSizePixel = 0
	row.Position = UDim2.fromOffset(0, y)
	row.Size = UDim2.new(1, -6, 0, 68)
	row.Parent = content
	corner(row, 8)
	stroke(row)
	local nameLabel = label(row, "Name", name, 14, COLORS.text, Enum.Font.GothamBold)
	nameLabel.Position = UDim2.fromOffset(13, 9)
	nameLabel.Size = UDim2.new(1, -150, 0, 22)
	local detailLabel = label(row, "Detail", detail or "", 11, COLORS.muted, Enum.Font.Gotham)
	detailLabel.Position = UDim2.fromOffset(13, 34)
	detailLabel.Size = UDim2.new(1, -150, 0, 24)
	local actionButton = button(row, "Action", actionText, color)
	actionButton.AnchorPoint = Vector2.new(1, 0.5)
	actionButton.Position = UDim2.new(1, -10, 0.5, 0)
	actionButton.Size = UDim2.fromOffset(116, 42)
	actionButton.Activated:Connect(callback)
	return y + 76
end

local renderMenu
local renderStash

renderMenu = function(payload)
	currentView, currentPayload = "menu", payload
	clearContent()
	title.Text = string.upper(tostring(payload.label or "APARTMENTS"))
	subtitle.Text = payload.hasApartment and ("Current home: " .. tostring(payload.apartmentLabel or "Apartment"))
		or "Choose a home here or ring an occupied apartment."
	local y = sectionHeading("YOUR APARTMENT", 0)
	if payload.ownsHere then
		y = actionRow(payload.apartmentLabel or "My Apartment", "Enter your private unit.", "ENTER", y, COLORS.green, function()
			local ok = call("enter", { buildingId = payload.buildingId })
			if ok then closePanel() end
		end)
	else
		local detail = payload.hasApartment and "Move your current apartment assignment to this building."
			or "Claim an apartment in this building."
		y = actionRow(payload.label or "Apartment", detail, payload.hasApartment and "MOVE HERE" or "CLAIM", y, COLORS.blue, function()
			local ok, nextPayload = call("move_here", { buildingId = payload.buildingId })
			if ok and type(nextPayload) == "table" then renderMenu(nextPayload) end
		end)
	end
	y = sectionHeading("RING A DOORBELL", y + 4)
	local occupants = type(payload.occupants) == "table" and payload.occupants or {}
	for _, occupant in ipairs(occupants) do
		y = actionRow(tostring(occupant.name or "Resident"), tostring(occupant.label or "Occupied apartment"), "RING", y, COLORS.soft, function()
			call("ring", { buildingId = payload.buildingId, citizenId = occupant.citizenId })
		end)
	end
	if #occupants == 0 then
		local empty = label(content, "Empty", "No residents in this building are currently home.", 13, COLORS.muted, Enum.Font.GothamMedium)
		empty.Position = UDim2.fromOffset(4, y + 8)
		empty.Size = UDim2.new(1, -8, 0, 42)
		y = y + 58
	end
	content.CanvasSize = UDim2.fromOffset(0, y + 10)
end

local function itemRows(items)
	local result = {}
	for key, item in pairs(type(items) == "table" and items or {}) do
		if type(item) == "table" then
			item._slot = tonumber(item.slot or key) or 0
			result[#result + 1] = item
		end
	end
	table.sort(result, function(a, b) return a._slot < b._slot end)
	return result
end

renderStash = function(payload)
	currentView, currentPayload = "stash", payload
	clearContent()
	title.Text = string.upper(tostring(payload.label or "APARTMENT STASH"))
	subtitle.Text = ("Stored weight: %.1f / %.1f kg"):format((tonumber(payload.weight) or 0) / 1000, (tonumber(payload.maxWeight) or 0) / 1000)
	local width = content.AbsoluteSize.X
	local compact = width < 560
	local columnWidth = compact and width - 8 or (width - 18) / 2
	local function makeColumn(name, x, entries, actionText, actionName, color)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.BackgroundTransparency = 1
		frame.Position = UDim2.fromOffset(x, 0)
		frame.Size = UDim2.fromOffset(columnWidth, 10)
		frame.Parent = content
		local heading = label(frame, "Heading", string.upper(name), 11, COLORS.muted, Enum.Font.GothamBold)
		heading.Size = UDim2.new(1, 0, 0, 22)
		local y = 28
		for _, item in ipairs(entries) do
			local row = Instance.new("Frame")
			row.BackgroundColor3 = COLORS.soft
			row.BorderSizePixel = 0
			row.Position = UDim2.fromOffset(0, y)
			row.Size = UDim2.new(1, 0, 0, 60)
			row.Parent = frame
			corner(row, 7)
			stroke(row)
			local itemLabel = label(row, "Label", tostring(item.label or item.name), 13, COLORS.text, Enum.Font.GothamBold)
			itemLabel.Position = UDim2.fromOffset(10, 7)
			itemLabel.Size = UDim2.new(1, -108, 0, 20)
			local amount = label(row, "Amount", ("Amount: %d"):format(tonumber(item.amount) or 1), 11, COLORS.muted, Enum.Font.Gotham)
			amount.Position = UDim2.fromOffset(10, 31)
			amount.Size = UDim2.new(1, -108, 0, 18)
			local actionButton = button(row, "Action", actionText, color)
			actionButton.AnchorPoint = Vector2.new(1, 0.5)
			actionButton.Position = UDim2.new(1, -8, 0.5, 0)
			actionButton.Size = UDim2.fromOffset(84, 40)
			actionButton.Activated:Connect(function()
				local ok, nextPayload = call(actionName, { slot = item._slot, amount = 1 })
				if ok and type(nextPayload) == "table" then renderStash(nextPayload) end
			end)
			y = y + 68
		end
		if #entries == 0 then
			local empty = label(frame, "Empty", "No items.", 12, COLORS.muted, Enum.Font.GothamMedium)
			empty.Position = UDim2.fromOffset(0, y)
			empty.Size = UDim2.new(1, 0, 0, 34)
			y = y + 40
		end
		frame.Size = UDim2.fromOffset(columnWidth, y)
		return y
	end
	local inventoryHeight = makeColumn("Your Inventory", 0, itemRows(payload.inventory), "STORE 1", "stash_store", COLORS.blue)
	local stashX = compact and 0 or columnWidth + 12
	local stashY = compact and inventoryHeight + 16 or 0
	if compact then
		-- Reposition the second generated column after creation.
	end
	local stashHeight = makeColumn("Stored Items", stashX, itemRows(payload.stash), "TAKE 1", "stash_take", COLORS.green)
	local storedFrame = content:FindFirstChild("Stored Items")
	if compact and storedFrame then storedFrame.Position = UDim2.fromOffset(0, stashY) end
	content.CanvasSize = UDim2.fromOffset(0, compact and (stashY + stashHeight + 8) or (math.max(inventoryHeight, stashHeight) + 8))
end

local function renderDoorbell(payload)
	currentView, currentPayload = "doorbell", payload
	clearContent()
	title.Text = "DOORBELL"
	subtitle.Text = "Someone is waiting at the building entrance."
	local message = label(content, "Message", tostring(payload.visitorName or "A visitor") .. " rang your apartment doorbell.", 17, COLORS.text, Enum.Font.GothamBold)
	message.Position = UDim2.fromOffset(12, 24)
	message.Size = UDim2.new(1, -24, 0, 70)
	message.TextXAlignment = Enum.TextXAlignment.Center
	local accept = button(content, "Accept", "LET THEM IN", COLORS.green)
	accept.Position = UDim2.new(0.5, -180, 0, 120)
	accept.Size = UDim2.fromOffset(170, 48)
	local decline = button(content, "Decline", "DECLINE", COLORS.red)
	decline.Position = UDim2.new(0.5, 10, 0, 120)
	decline.Size = UDim2.fromOffset(170, 48)
	accept.Activated:Connect(function()
		local ok = call("answer", { requestId = payload.requestId, accept = true })
		if ok then closePanel() end
	end)
	decline.Activated:Connect(function()
		local ok = call("answer", { requestId = payload.requestId, accept = false })
		if ok then closePanel() end
	end)
	content.CanvasSize = UDim2.fromOffset(0, 190)
end

local function open(view, payload)
	busy = false
	status.Text = ""
	status.TextColor3 = COLORS.muted
	resize()
	screen.Enabled = true
	payload = type(payload) == "table" and payload or {}
	if view == "menu" then renderMenu(payload)
	elseif view == "stash" then renderStash(payload)
	elseif view == "doorbell" then renderDoorbell(payload)
	else closePanel() end
end

close.Activated:Connect(closePanel)
shade.Activated:Connect(closePanel)
Remotes.OpenApartment.OnClientEvent:Connect(open)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(resize)
