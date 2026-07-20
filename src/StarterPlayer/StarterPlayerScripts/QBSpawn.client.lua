-- Native qb-spawn-style location selector opened after multicharacter selection.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Remotes = require(ReplicatedStorage.QBRemotes)
local QBUITheme = require(ReplicatedStorage.QBUITheme)

local COLORS = QBUITheme.Palette("Compact", {
	soft = Color3.fromRGB(23, 29, 38),
	line = Color3.fromRGB(54, 65, 80),
	muted = Color3.fromRGB(150, 162, 178),
	accent = Color3.fromRGB(52, 126, 190),
	red = Color3.fromRGB(191, 70, 70),
})

local function corner(parent, radius)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function stroke(parent, color, transparency)
	local value = Instance.new("UIStroke")
	value.Color = color
	value.Transparency = transparency or 0
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
	value.Text = text or "Button"
	value.TextColor3 = COLORS.text
	value.TextSize = 14
	value.Parent = parent
	corner(value, 7)
	return value
end

local screen = Instance.new("ScreenGui")
screen.Name = "QBSpawn"
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
screen.DisplayOrder = 120
screen.Enabled = false
screen.Parent = player:WaitForChild("PlayerGui")

local shade = Instance.new("Frame")
shade.Name = "Shade"
shade.BackgroundColor3 = COLORS.backdrop
shade.BackgroundTransparency = 0.28
shade.BorderSizePixel = 0
shade.Size = UDim2.fromScale(1, 1)
shade.Parent = screen

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 0.5)
panel.BackgroundColor3 = COLORS.panel
panel.BorderSizePixel = 0
panel.Position = UDim2.new(0, 38, 0.5, 0)
panel.Size = UDim2.fromOffset(430, 610)
panel.Parent = screen
corner(panel, 11)
stroke(panel, COLORS.line, 0.1)

local title = label(panel, "Title", "CHOOSE YOUR SPAWN", 23, COLORS.text, Enum.Font.GothamBold)
title.Position = UDim2.fromOffset(24, 20)
title.Size = UDim2.new(1, -48, 0, 32)

local subtitle = label(
	panel,
	"Subtitle",
	"Select where this character should enter the city.",
	13,
	COLORS.muted,
	Enum.Font.GothamMedium
)
subtitle.Position = UDim2.fromOffset(24, 54)
subtitle.Size = UDim2.new(1, -48, 0, 38)

local list = Instance.new("ScrollingFrame")
list.Name = "Locations"
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.fromOffset(20, 100)
list.Size = UDim2.new(1, -40, 1, -184)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.fromOffset(0, 0)
list.ScrollBarThickness = 5
list.ScrollBarImageColor3 = COLORS.line
list.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 9)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local spawnButton = button(panel, "Spawn", "SELECT A LOCATION", COLORS.green)
spawnButton.AnchorPoint = Vector2.new(0, 1)
spawnButton.Position = UDim2.new(0, 20, 1, -20)
spawnButton.Size = UDim2.new(1, -40, 0, 48)
spawnButton.Active = false
spawnButton.AutoButtonColor = false

local status = label(panel, "Status", "", 12, COLORS.muted, Enum.Font.GothamMedium)
status.AnchorPoint = Vector2.new(0, 1)
status.Position = UDim2.new(0, 22, 1, -73)
status.Size = UDim2.new(1, -44, 0, 24)
status.TextXAlignment = Enum.TextXAlignment.Center

local currentChoices = {}
local selectedId
local cards = {}
local busy = false
local previousCameraType
local previousCameraSubject

local function restoreCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = previousCameraType or Enum.CameraType.Custom
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	camera.CameraSubject = humanoid or previousCameraSubject
end

local function preview(choice)
	local position = choice and choice.position
	local x, y, z =
		position and tonumber(position.x), position and tonumber(position.y), position and tonumber(position.z)
	local camera = workspace.CurrentCamera
	if not camera or not x or not y or not z then
		return
	end
	local focus = Vector3.new(x, y + 3, z)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(focus + Vector3.new(38, 30, 42), focus)
end

local function selectChoice(choice)
	selectedId = choice.id
	for id, card in pairs(cards) do
		card.BackgroundColor3 = id == selectedId and Color3.fromRGB(31, 73, 93) or COLORS.soft
		local border = card:FindFirstChildOfClass("UIStroke")
		if border then
			border.Color = id == selectedId and COLORS.accent or COLORS.line
		end
	end
	spawnButton.Text = choice.kind == "apartment" and "CLAIM APARTMENT" or "SPAWN HERE"
	spawnButton.Active = true
	spawnButton.AutoButtonColor = true
	preview(choice)
end

local function clearCards()
	table.clear(cards)
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function makeCard(choice, order)
	local card = Instance.new("TextButton")
	card.Name = "Location_" .. tostring(order)
	card.AutoButtonColor = false
	card.BackgroundColor3 = COLORS.soft
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	card.Size = UDim2.new(1, -6, 0, 82)
	card.Text = ""
	card.Parent = list
	corner(card, 8)
	stroke(card, COLORS.line, 0.15)
	local kindText = choice.kind == "apartment" and "STARTER APARTMENT"
		or choice.kind == "owned_apartment" and "MY APARTMENT"
		or "SPAWN LOCATION"
	local kind = label(
		card,
		"Kind",
		kindText,
		10,
		choice.kind == "apartment" and COLORS.green or COLORS.muted,
		Enum.Font.GothamBold
	)
	kind.Position = UDim2.fromOffset(14, 9)
	kind.Size = UDim2.new(1, -28, 0, 14)
	local name = label(card, "Label", tostring(choice.label or "Location"), 16, COLORS.text, Enum.Font.GothamBold)
	name.Position = UDim2.fromOffset(14, 25)
	name.Size = UDim2.new(1, -28, 0, 23)
	local description =
		label(card, "Description", tostring(choice.description or ""), 12, COLORS.muted, Enum.Font.Gotham)
	description.Position = UDim2.fromOffset(14, 50)
	description.Size = UDim2.new(1, -28, 0, 24)
	card.Activated:Connect(function()
		if not busy then
			selectChoice(choice)
		end
	end)
	cards[choice.id] = card
end

local function resize()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local compact = viewport.X < 720
	panel.AnchorPoint = compact and Vector2.new(0.5, 0.5) or Vector2.new(0, 0.5)
	panel.Position = compact and UDim2.fromScale(0.5, 0.5) or UDim2.new(0, 38, 0.5, 0)
	panel.Size = UDim2.fromOffset(math.min(430, viewport.X - 24), math.min(610, viewport.Y - 24))
end

local function open(snapshot)
	currentChoices = type(snapshot) == "table" and type(snapshot.choices) == "table" and snapshot.choices or {}
	selectedId = nil
	busy = false
	status.Text = ""
	spawnButton.Text = "SELECT A LOCATION"
	spawnButton.Active = false
	spawnButton.AutoButtonColor = false
	clearCards()
	for index, choice in ipairs(currentChoices) do
		makeCard(choice, index)
	end
	local camera = workspace.CurrentCamera
	if camera then
		previousCameraType = camera.CameraType
		previousCameraSubject = camera.CameraSubject
	end
	resize()
	screen.Enabled = true
	if currentChoices[1] then
		selectChoice(currentChoices[1])
	end
end

spawnButton.Activated:Connect(function()
	if busy or not selectedId then
		return
	end
	busy = true
	spawnButton.Active = false
	spawnButton.AutoButtonColor = false
	spawnButton.Text = "SPAWNING..."
	status.Text = "Preparing your character..."
	local call = table.pack(pcall(Remotes.SelectSpawn.InvokeServer, Remotes.SelectSpawn, selectedId))
	if not call[1] or call[2] ~= true then
		busy = false
		spawnButton.Active = true
		spawnButton.AutoButtonColor = true
		spawnButton.Text = "TRY AGAIN"
		status.TextColor3 = COLORS.red
		status.Text = tostring(call[3] or "The spawn could not be completed.")
		return
	end
	screen.Enabled = false
	status.TextColor3 = COLORS.muted
	restoreCamera()
end)

Remotes.OpenSpawnSelector.OnClientEvent:Connect(open)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(resize)
UserInputService.LastInputTypeChanged:Connect(resize)
