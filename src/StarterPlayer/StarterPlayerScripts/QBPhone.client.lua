-- StudOS smartphone UI. It has no keyboard open binding: the server opens it only
-- after the inventory's phone item successfully runs through UseInventorySlot.

local CaptureService = game:GetService("CaptureService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.QBRemotes)
local QBCoreClient = require(ReplicatedStorage.QBCoreClient)
local QBUITheme = require(ReplicatedStorage.QBUITheme)
local QBUIScale = require(ReplicatedStorage.QBUIScale)

local player = Players.LocalPlayer

local COLORS = QBUITheme.Palette("Utility", {
	ink = Color3.fromRGB(239, 244, 255),
	muted = Color3.fromRGB(151, 163, 184),
	bg = Color3.fromRGB(7, 10, 18),
	panel = Color3.fromRGB(18, 24, 38),
	panel2 = Color3.fromRGB(29, 38, 57),
	line = Color3.fromRGB(55, 69, 94),
	blue = Color3.fromRGB(63, 131, 248),
	green = Color3.fromRGB(40, 190, 119),
	red = Color3.fromRGB(225, 76, 92),
	purple = Color3.fromRGB(151, 91, 235),
	orange = Color3.fromRGB(237, 145, 54),
})

local snapshot = nil
local contacts = {}
local settings = { dnd = false, sounds = true }
local conversations = {} -- [UserId] = { contact, messages }
local channelContacts = {} -- [channel name] = contact
local connectedChannels = {}
local socialPosts = {}
local captures = {}
local currentContact = nil
local currentScreen = "home"
local currentCall = nil
local phoneOpen = false
local captureBusy = false

local function addCorner(object, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 10)
	corner.Parent = object
	return corner
end

local function addStroke(object, color, transparency, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or COLORS.line
	stroke.Transparency = transparency or 0
	stroke.Thickness = thickness or 1
	stroke.Parent = object
	return stroke
end

local function label(parent, name, text, size, color, font)
	local object = Instance.new("TextLabel")
	object.Name = name
	object.BackgroundTransparency = 1
	object.Text = text or ""
	object.TextColor3 = color or COLORS.ink
	object.TextSize = size or 14
	object.Font = font or Enum.Font.Gotham
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.TextYAlignment = Enum.TextYAlignment.Center
	object.Parent = parent
	return object
end

local function button(parent, name, text, color)
	local object = Instance.new("TextButton")
	object.Name = name
	object.AutoButtonColor = true
	object.BackgroundColor3 = color or COLORS.panel2
	object.BorderSizePixel = 0
	object.Text = text or ""
	object.TextColor3 = COLORS.ink
	object.TextSize = 14
	object.Font = Enum.Font.GothamBold
	object.Parent = parent
	addCorner(object, 10)
	return object
end

local function listLayout(parent, padding)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding or 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QBPhone"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 80
screenGui.Enabled = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

local shell = Instance.new("Frame")
shell.Name = "PhoneShell"
shell.AnchorPoint = Vector2.new(1, 1)
shell.Position = UDim2.new(1, -24, 1, -18)
shell.Size = UDim2.fromOffset(390, 720)
shell.BackgroundColor3 = Color3.fromRGB(5, 7, 12)
shell.BorderSizePixel = 0
shell.ClipsDescendants = true
shell.Parent = screenGui
addCorner(shell, 34)
addStroke(shell, Color3.fromRGB(88, 98, 120), 0.05, 3)

local scale = Instance.new("UIScale")
scale.Parent = shell

local wallpaper = Instance.new("UIGradient")
wallpaper.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(17, 25, 48)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(10, 15, 29)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 17, 53)),
})
wallpaper.Rotation = 120
wallpaper.Parent = shell

local statusBar = Instance.new("Frame")
statusBar.Name = "StatusBar"
statusBar.BackgroundTransparency = 1
statusBar.Position = UDim2.fromOffset(22, 10)
statusBar.Size = UDim2.new(1, -44, 0, 30)
statusBar.ZIndex = 20
statusBar.Parent = shell

local timeLabel = label(statusBar, "Time", "", 13, COLORS.ink, Enum.Font.GothamBold)
timeLabel.Size = UDim2.fromOffset(90, 30)
local networkLabel = label(statusBar, "Network", "STUD  100%", 12, COLORS.ink, Enum.Font.GothamMedium)
networkLabel.AnchorPoint = Vector2.new(1, 0)
networkLabel.Position = UDim2.new(1, 0, 0, 0)
networkLabel.Size = UDim2.fromOffset(120, 30)
networkLabel.TextXAlignment = Enum.TextXAlignment.Right

local content = Instance.new("Frame")
content.Name = "Content"
content.BackgroundTransparency = 1
content.Position = UDim2.fromOffset(14, 43)
content.Size = UDim2.new(1, -28, 1, -92)
content.ZIndex = 10
content.Parent = shell

local homeBar = button(shell, "HomeBar", "", Color3.fromRGB(225, 229, 240))
homeBar.AutoButtonColor = false
homeBar.AnchorPoint = Vector2.new(0.5, 1)
homeBar.Position = UDim2.new(0.5, 0, 1, -13)
homeBar.Size = UDim2.fromOffset(126, 5)
homeBar.ZIndex = 25
addCorner(homeBar, 4)

local closeButton = button(shell, "Close", "×", Color3.fromRGB(25, 31, 45))
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -12, 0, 45)
closeButton.Size = UDim2.fromOffset(34, 34)
closeButton.TextSize = 20
closeButton.ZIndex = 30

local screens = {}
local function createScreen(name)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Visible = false
	frame.Parent = content
	screens[name] = frame
	return frame
end

local home = createScreen("home")
local contactsScreen = createScreen("contacts")
local messagesScreen = createScreen("messages")
local cameraScreen = createScreen("camera")
local photosScreen = createScreen("photos")
local socialScreen = createScreen("social")
local toolsScreen = createScreen("tools")
local settingsScreen = createScreen("settings")

local profileCard = Instance.new("Frame")
profileCard.BackgroundColor3 = Color3.fromRGB(19, 28, 48)
profileCard.BackgroundTransparency = 0.12
profileCard.Position = UDim2.fromOffset(6, 12)
profileCard.Size = UDim2.new(1, -12, 0, 125)
profileCard.Parent = home
addCorner(profileCard, 20)
addStroke(profileCard, Color3.fromRGB(82, 109, 156), 0.55, 1)

local osMark = label(profileCard, "OS", "STUD OS", 12, Color3.fromRGB(130, 175, 255), Enum.Font.GothamBold)
osMark.Position = UDim2.fromOffset(18, 12)
osMark.Size = UDim2.new(1, -36, 0, 22)
local homeTime = label(profileCard, "Clock", "", 40, COLORS.ink, Enum.Font.GothamBold)
homeTime.Position = UDim2.fromOffset(17, 31)
homeTime.Size = UDim2.new(1, -34, 0, 50)
local profileLabel = label(profileCard, "Profile", "Loading profile…", 13, COLORS.muted, Enum.Font.GothamMedium)
profileLabel.Position = UDim2.fromOffset(19, 86)
profileLabel.Size = UDim2.new(1, -38, 0, 25)

local apps = Instance.new("Frame")
apps.BackgroundTransparency = 1
apps.Position = UDim2.fromOffset(6, 157)
apps.Size = UDim2.new(1, -12, 1, -164)
apps.Parent = home
local appGrid = Instance.new("UIGridLayout")
appGrid.CellPadding = UDim2.fromOffset(10, 12)
appGrid.CellSize = UDim2.new(0.25, -8, 0, 96)
appGrid.SortOrder = Enum.SortOrder.LayoutOrder
appGrid.Parent = apps

local appMeta = {
	{ "contacts", "Phone", "rbxassetid://91900298739645", COLORS.green },
	{ "messages", "Messages", "rbxassetid://138792521694255", COLORS.blue },
	{ "camera", "Camera", "rbxassetid://79469516734488", Color3.fromRGB(74, 82, 101) },
	{ "photos", "Photos", "rbxassetid://79202041326110", COLORS.orange },
	{ "social", "StudSpace", "rbxassetid://78972290900876", COLORS.purple },
	{ "tools", "Tools", "rbxassetid://130806761187039", Color3.fromRGB(69, 111, 153) },
	{ "settings", "Settings", "rbxassetid://88871196543710", Color3.fromRGB(92, 103, 122) },
}

local navigate
for order, meta in ipairs(appMeta) do
	local tile = Instance.new("Frame")
	tile.Name = meta[1]
	tile.BackgroundTransparency = 1
	tile.LayoutOrder = order
	tile.Parent = apps
	local icon = button(tile, "Icon", "", meta[4])
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 0)
	icon.Size = UDim2.fromOffset(58, 58)
	addCorner(icon, 16)
	local iconImage = Instance.new("ImageLabel")
	iconImage.Name = "Image"
	iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
	iconImage.Position = UDim2.fromScale(0.5, 0.5)
	iconImage.Size = UDim2.fromOffset(36, 36)
	iconImage.BackgroundTransparency = 1
	iconImage.Image = meta[3]
	iconImage.ScaleType = Enum.ScaleType.Fit
	iconImage.Parent = icon
	local title = label(tile, "Title", meta[2], 11, COLORS.ink, Enum.Font.GothamMedium)
	title.Position = UDim2.fromOffset(0, 62)
	title.Size = UDim2.new(1, 0, 0, 24)
	title.TextXAlignment = Enum.TextXAlignment.Center
	icon.Activated:Connect(function()
		navigate(meta[1])
	end)
end

local function addHeader(parent, titleText)
	local back = button(parent, "Back", "‹", COLORS.panel2)
	back.Position = UDim2.fromOffset(0, 4)
	back.Size = UDim2.fromOffset(38, 38)
	back.TextSize = 27
	back.Activated:Connect(function()
		navigate("home")
	end)
	local title = label(parent, "Title", titleText, 24, COLORS.ink, Enum.Font.GothamBold)
	title.Position = UDim2.fromOffset(50, 0)
	title.Size = UDim2.new(1, -96, 0, 46)
	return title
end

addHeader(contactsScreen, "Phone")
local contactsList = Instance.new("ScrollingFrame")
contactsList.Name = "Contacts"
contactsList.BackgroundTransparency = 1
contactsList.BorderSizePixel = 0
contactsList.Position = UDim2.fromOffset(0, 55)
contactsList.Size = UDim2.new(1, 0, 1, -55)
contactsList.AutomaticCanvasSize = Enum.AutomaticSize.Y
contactsList.CanvasSize = UDim2.new()
contactsList.ScrollBarThickness = 3
contactsList.Parent = contactsScreen
listLayout(contactsList, 8)

addHeader(messagesScreen, "Messages")
local messageContactTitle =
	label(messagesScreen, "Contact", "Choose a contact", 13, COLORS.muted, Enum.Font.GothamMedium)
messageContactTitle.Position = UDim2.fromOffset(50, 34)
messageContactTitle.Size = UDim2.new(1, -100, 0, 25)
local messageList = Instance.new("ScrollingFrame")
messageList.Name = "Conversation"
messageList.BackgroundTransparency = 1
messageList.BorderSizePixel = 0
messageList.Position = UDim2.fromOffset(0, 70)
messageList.Size = UDim2.new(1, 0, 1, -125)
messageList.AutomaticCanvasSize = Enum.AutomaticSize.Y
messageList.CanvasSize = UDim2.new()
messageList.ScrollBarThickness = 3
messageList.Parent = messagesScreen
local messageLayout = listLayout(messageList, 7)
local compose = Instance.new("TextBox")
compose.Name = "Compose"
compose.AnchorPoint = Vector2.new(0, 1)
compose.Position = UDim2.new(0, 0, 1, 0)
compose.Size = UDim2.new(1, -66, 0, 45)
compose.BackgroundColor3 = COLORS.panel
compose.BorderSizePixel = 0
compose.PlaceholderText = "Message"
compose.PlaceholderColor3 = COLORS.muted
compose.Text = ""
compose.TextColor3 = COLORS.ink
compose.TextSize = 14
compose.Font = Enum.Font.Gotham
compose.TextXAlignment = Enum.TextXAlignment.Left
compose.ClearTextOnFocus = false
compose.Parent = messagesScreen
addCorner(compose, 14)
local composePadding = Instance.new("UIPadding")
composePadding.PaddingLeft = UDim.new(0, 13)
composePadding.PaddingRight = UDim.new(0, 13)
composePadding.Parent = compose
local sendButton = button(messagesScreen, "Send", "Send", COLORS.blue)
sendButton.AnchorPoint = Vector2.new(1, 1)
sendButton.Position = UDim2.fromScale(1, 1)
sendButton.Size = UDim2.fromOffset(58, 45)

addHeader(cameraScreen, "Camera")

-- Camera mode: the shell background goes fully transparent while these opaque
-- panels rebuild the phone body around a clear window, so the live world fills
-- the viewfinder edge to edge. Patch frames square off the panel corners that
-- face the window (UICorner rounds all four).
local CAMERA_TOP = 96
local CAMERA_BOTTOM = 150
local CHROME_COLOR = Color3.fromRGB(8, 9, 13)

local cameraChrome = Instance.new("Frame")
cameraChrome.Name = "CameraChrome"
cameraChrome.BackgroundTransparency = 1
cameraChrome.Size = UDim2.fromScale(1, 1)
cameraChrome.Visible = false
cameraChrome.Parent = shell

local function chromePanel(name, anchorY)
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.BackgroundColor3 = CHROME_COLOR
	panel.BorderSizePixel = 0
	panel.AnchorPoint = Vector2.new(0, anchorY)
	panel.Position = UDim2.fromScale(0, anchorY)
	panel.Size = UDim2.new(1, 0, 0, anchorY == 0 and CAMERA_TOP or CAMERA_BOTTOM)
	panel.Parent = cameraChrome
	addCorner(panel, 34)
	local patch = Instance.new("Frame")
	patch.Name = "Patch"
	patch.BackgroundColor3 = CHROME_COLOR
	patch.BorderSizePixel = 0
	patch.AnchorPoint = Vector2.new(0, 1 - anchorY)
	patch.Position = UDim2.fromScale(0, 1 - anchorY)
	patch.Size = UDim2.new(1, 0, 0, 40)
	patch.Parent = panel
	return panel
end

chromePanel("TopPanel", 0)
local bottomPanel = chromePanel("BottomPanel", 1)

local cameraWindow = Instance.new("Frame")
cameraWindow.Name = "Window"
cameraWindow.BackgroundTransparency = 1
cameraWindow.Position = UDim2.fromOffset(0, CAMERA_TOP)
cameraWindow.Size = UDim2.new(1, 0, 1, -(CAMERA_TOP + CAMERA_BOTTOM))
cameraWindow.Parent = cameraChrome

for index, lineSpec in ipairs({
	{ UDim2.fromScale(1 / 3, 0), UDim2.new(0, 1, 1, 0) },
	{ UDim2.fromScale(2 / 3, 0), UDim2.new(0, 1, 1, 0) },
	{ UDim2.fromScale(0, 1 / 3), UDim2.new(1, 0, 0, 1) },
	{ UDim2.fromScale(0, 2 / 3), UDim2.new(1, 0, 0, 1) },
}) do
	local line = Instance.new("Frame")
	line.Name = "Grid" .. index
	line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	line.BackgroundTransparency = 0.86
	line.BorderSizePixel = 0
	line.Position = lineSpec[1]
	line.Size = lineSpec[2]
	line.Parent = cameraWindow
end

local zoomBar = Instance.new("Frame")
zoomBar.Name = "ZoomBar"
zoomBar.BackgroundTransparency = 1
zoomBar.AnchorPoint = Vector2.new(0.5, 1)
zoomBar.Position = UDim2.new(0.5, 0, 1, -10)
zoomBar.Size = UDim2.fromOffset(160, 30)
zoomBar.Parent = cameraWindow
local zoomLayout = listLayout(zoomBar, 8)
zoomLayout.FillDirection = Enum.FillDirection.Horizontal
zoomLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.Size = UDim2.fromScale(1, 1)
flash.Parent = cameraWindow

local galleryThumb = Instance.new("ImageButton")
galleryThumb.Name = "Gallery"
galleryThumb.BackgroundColor3 = Color3.fromRGB(22, 27, 38)
galleryThumb.BorderSizePixel = 0
galleryThumb.AutoButtonColor = true
galleryThumb.Position = UDim2.fromOffset(30, 24)
galleryThumb.Size = UDim2.fromOffset(56, 56)
galleryThumb.ScaleType = Enum.ScaleType.Crop
galleryThumb.Parent = bottomPanel
addCorner(galleryThumb, 14)
addStroke(galleryThumb, Color3.fromRGB(92, 102, 124), 0.45, 1)
local galleryPlaceholder = Instance.new("ImageLabel")
galleryPlaceholder.Name = "Placeholder"
galleryPlaceholder.AnchorPoint = Vector2.new(0.5, 0.5)
galleryPlaceholder.Position = UDim2.fromScale(0.5, 0.5)
galleryPlaceholder.Size = UDim2.fromOffset(30, 30)
galleryPlaceholder.BackgroundTransparency = 1
galleryPlaceholder.Image = "rbxassetid://79202041326110"
galleryPlaceholder.ScaleType = Enum.ScaleType.Fit
galleryPlaceholder.Parent = galleryThumb

local shutter = button(bottomPanel, "Shutter", "", Color3.fromRGB(235, 238, 245))
shutter.AnchorPoint = Vector2.new(0.5, 0)
shutter.Position = UDim2.new(0.5, 0, 0, 18)
shutter.Size = UDim2.fromOffset(68, 68)
addCorner(shutter, 34)
addStroke(shutter, Color3.fromRGB(230, 235, 244), 0.1, 4)

local flipButton = button(bottomPanel, "Flip", "FLIP", Color3.fromRGB(22, 27, 38))
flipButton.AnchorPoint = Vector2.new(1, 0)
flipButton.Position = UDim2.new(1, -30, 0, 24)
flipButton.Size = UDim2.fromOffset(56, 56)
flipButton.TextSize = 12
addCorner(flipButton, 28)
addStroke(flipButton, Color3.fromRGB(92, 102, 124), 0.45, 1)

local shutterSound = Instance.new("Sound")
shutterSound.Name = "ShutterSound"
shutterSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
shutterSound.Volume = 0.5
shutterSound.Parent = screenGui

local cameraModeActive = false
local selfieActive = false
local selfieConnection = nil
local savedCameraType = nil
local baseFov = 70
local zoomButtons = {}

local function setZoom(level, instant)
	for buttonLevel, zoomButton in pairs(zoomButtons) do
		local selected = buttonLevel == level
		zoomButton.BackgroundColor3 = selected and COLORS.blue or Color3.fromRGB(15, 18, 26)
		zoomButton.BackgroundTransparency = selected and 0.1 or 0.35
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local fov = baseFov / level
	if instant then
		camera.FieldOfView = fov
	else
		TweenService:Create(camera, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = fov,
		}):Play()
	end
end

for _, level in ipairs({ 1, 2, 3 }) do
	local pill = button(zoomBar, "Zoom" .. level, level .. "x", Color3.fromRGB(15, 18, 26))
	pill.LayoutOrder = level
	pill.Size = UDim2.fromOffset(44, 30)
	pill.TextSize = 12
	addCorner(pill, 15)
	zoomButtons[level] = pill
	pill.Activated:Connect(function()
		setZoom(level)
	end)
end

local function setSelfie(on)
	if selfieActive == on then
		return
	end
	local camera = workspace.CurrentCamera
	if on and not camera then
		return
	end
	selfieActive = on
	flipButton.BackgroundColor3 = on and COLORS.blue or Color3.fromRGB(22, 27, 38)
	if on then
		savedCameraType = camera.CameraType
		camera.CameraType = Enum.CameraType.Scriptable
		selfieConnection = RunService.RenderStepped:Connect(function()
			local character = player.Character
			local head = character and character:FindFirstChild("Head")
			local liveCamera = workspace.CurrentCamera
			if not (head and liveCamera) then
				return
			end
			local eye = head.Position + head.CFrame.LookVector * 4.5 + Vector3.new(0, 0.5, 0)
			liveCamera.CFrame = CFrame.lookAt(eye, head.Position + Vector3.new(0, 0.25, 0))
		end)
	else
		if selfieConnection then
			selfieConnection:Disconnect()
			selfieConnection = nil
		end
		local liveCamera = workspace.CurrentCamera
		if liveCamera then
			liveCamera.CameraType = savedCameraType or Enum.CameraType.Custom
		end
	end
end

local function enterCameraMode()
	if cameraModeActive then
		return
	end
	cameraModeActive = true
	local camera = workspace.CurrentCamera
	baseFov = camera and camera.FieldOfView or 70
	shell.BackgroundTransparency = 1
	cameraChrome.Visible = true
	setZoom(1, true)
end

local function exitCameraMode()
	if not cameraModeActive then
		return
	end
	cameraModeActive = false
	setSelfie(false)
	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = baseFov
	end
	shell.BackgroundTransparency = 0
	cameraChrome.Visible = false
end

flipButton.Activated:Connect(function()
	setSelfie(not selfieActive)
end)

player.CharacterAdded:Connect(function()
	if selfieActive then
		setSelfie(false)
	end
end)

local function computeCropRect()
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil
	end
	local viewport = camera.ViewportSize
	local inset = GuiService:GetGuiInset()
	local topLeft = cameraWindow.AbsolutePosition + inset
	local size = cameraWindow.AbsoluteSize
	local x0 = math.clamp(topLeft.X, 0, viewport.X)
	local y0 = math.clamp(topLeft.Y, 0, viewport.Y)
	local x1 = math.clamp(topLeft.X + size.X, 0, viewport.X)
	local y1 = math.clamp(topLeft.Y + size.Y, 0, viewport.Y)
	if x1 - x0 < 8 or y1 - y0 < 8 then
		return nil, nil
	end
	return Vector2.new(x0, y0), Vector2.new(x1 - x0, y1 - y0)
end

-- Captures are always the full screen; the stored crop rect trims the display
-- back to exactly what the viewfinder window framed. Gallery saves keep the
-- full uncropped shot.
local function applyPhotoImage(image, photo)
	local ok = pcall(function()
		image.ImageContent = Content.fromObject(photo.object)
	end)
	if ok and photo.cropOffset and photo.cropSize then
		image.ImageRectOffset = photo.cropOffset
		image.ImageRectSize = photo.cropSize
	else
		image.ImageRectOffset = Vector2.zero
		image.ImageRectSize = Vector2.zero
	end
	return ok
end

local function updateGalleryThumb()
	local latest = captures[1]
	if latest and applyPhotoImage(galleryThumb, latest) then
		galleryPlaceholder.Visible = false
	else
		pcall(function()
			galleryThumb.ImageContent = Content.none
		end)
		galleryThumb.ImageRectOffset = Vector2.zero
		galleryThumb.ImageRectSize = Vector2.zero
		galleryPlaceholder.Visible = true
	end
end

local function playCaptureFeedback()
	flash.BackgroundTransparency = 0.15
	TweenService:Create(flash, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	if settings.sounds then
		shutterSound:Play()
	end
end

galleryThumb.Activated:Connect(function()
	navigate("photos")
end)

addHeader(photosScreen, "Photos")
local photoList = Instance.new("ScrollingFrame")
photoList.BackgroundTransparency = 1
photoList.BorderSizePixel = 0
photoList.Position = UDim2.fromOffset(0, 55)
photoList.Size = UDim2.new(1, 0, 1, -55)
photoList.AutomaticCanvasSize = Enum.AutomaticSize.Y
photoList.CanvasSize = UDim2.new()
photoList.ScrollBarThickness = 3
photoList.Parent = photosScreen
local photoGrid = Instance.new("UIGridLayout")
photoGrid.CellPadding = UDim2.fromOffset(7, 7)
photoGrid.CellSize = UDim2.new(0.5, -4, 0, 155)
photoGrid.Parent = photoList
local photosEmpty = label(
	photosScreen,
	"Empty",
	"No photos yet — open the Camera and take some.",
	13,
	COLORS.muted,
	Enum.Font.GothamMedium
)
photosEmpty.Position = UDim2.fromOffset(10, 70)
photosEmpty.Size = UDim2.new(1, -20, 0, 40)
photosEmpty.TextXAlignment = Enum.TextXAlignment.Center
photosEmpty.TextWrapped = true
photosEmpty.Visible = false

addHeader(socialScreen, "StudSpace")
local socialTag =
	label(socialScreen, "Tagline", "Posts travel through Roblox chat safety.", 11, COLORS.muted, Enum.Font.GothamMedium)
socialTag.Position = UDim2.fromOffset(50, 35)
socialTag.Size = UDim2.new(1, -55, 0, 22)
local socialList = Instance.new("ScrollingFrame")
socialList.BackgroundTransparency = 1
socialList.BorderSizePixel = 0
socialList.Position = UDim2.fromOffset(0, 67)
socialList.Size = UDim2.new(1, 0, 1, -125)
socialList.AutomaticCanvasSize = Enum.AutomaticSize.Y
socialList.CanvasSize = UDim2.new()
socialList.ScrollBarThickness = 3
socialList.Parent = socialScreen
listLayout(socialList, 8)
local postBox = Instance.new("TextBox")
postBox.AnchorPoint = Vector2.new(0, 1)
postBox.Position = UDim2.new(0, 0, 1, 0)
postBox.Size = UDim2.new(1, -66, 0, 46)
postBox.BackgroundColor3 = COLORS.panel
postBox.BorderSizePixel = 0
postBox.PlaceholderText = "Share with StudSpace"
postBox.PlaceholderColor3 = COLORS.muted
postBox.Text = ""
postBox.TextColor3 = COLORS.ink
postBox.TextSize = 13
postBox.Font = Enum.Font.Gotham
postBox.TextXAlignment = Enum.TextXAlignment.Left
postBox.ClearTextOnFocus = false
postBox.Parent = socialScreen
addCorner(postBox, 13)
local postPadding = Instance.new("UIPadding")
postPadding.PaddingLeft = UDim.new(0, 12)
postPadding.PaddingRight = UDim.new(0, 12)
postPadding.Parent = postBox
local postButton = button(socialScreen, "Post", "Post", COLORS.purple)
postButton.AnchorPoint = Vector2.new(1, 1)
postButton.Position = UDim2.fromScale(1, 1)
postButton.Size = UDim2.fromOffset(58, 46)

addHeader(toolsScreen, "Tools")
local toolClock = label(toolsScreen, "Clock", "", 48, COLORS.ink, Enum.Font.GothamBold)
toolClock.Position = UDim2.fromOffset(10, 70)
toolClock.Size = UDim2.new(1, -20, 0, 70)
toolClock.TextXAlignment = Enum.TextXAlignment.Center
local toolDate = label(toolsScreen, "Date", "", 15, COLORS.muted, Enum.Font.GothamMedium)
toolDate.Position = UDim2.fromOffset(10, 135)
toolDate.Size = UDim2.new(1, -20, 0, 30)
toolDate.TextXAlignment = Enum.TextXAlignment.Center
local calcDisplay = Instance.new("TextBox")
calcDisplay.Position = UDim2.fromOffset(5, 200)
calcDisplay.Size = UDim2.new(1, -10, 0, 58)
calcDisplay.BackgroundColor3 = COLORS.panel
calcDisplay.BorderSizePixel = 0
calcDisplay.Text = "0"
calcDisplay.TextColor3 = COLORS.ink
calcDisplay.TextSize = 24
calcDisplay.Font = Enum.Font.Code
calcDisplay.TextXAlignment = Enum.TextXAlignment.Right
calcDisplay.ClearTextOnFocus = false
calcDisplay.Parent = toolsScreen
addCorner(calcDisplay, 12)
local calcPad = Instance.new("UIPadding")
calcPad.PaddingLeft = UDim.new(0, 12)
calcPad.PaddingRight = UDim.new(0, 12)
calcPad.Parent = calcDisplay
local calcGrid = Instance.new("Frame")
calcGrid.BackgroundTransparency = 1
calcGrid.Position = UDim2.fromOffset(5, 270)
calcGrid.Size = UDim2.new(1, -10, 0, 260)
calcGrid.Parent = toolsScreen
local calcLayout = Instance.new("UIGridLayout")
calcLayout.CellPadding = UDim2.fromOffset(7, 7)
calcLayout.CellSize = UDim2.new(0.25, -6, 0, 48)
calcLayout.Parent = calcGrid

local calcTokens = {}
local calcValues = { "7", "8", "9", "/", "4", "5", "6", "*", "1", "2", "3", "-", "C", "0", "=", "+" }
for _, value in ipairs(calcValues) do
	local calcButton = button(calcGrid, "Key" .. value, value, value == "=" and COLORS.blue or COLORS.panel2)
	calcButton.Activated:Connect(function()
		if value == "C" then
			calcTokens = {}
			calcDisplay.Text = "0"
		elseif value == "=" then
			local expression = table.concat(calcTokens)
			local a, operator, b = expression:match("^([%-%d%.]+)([%+%-%*/])([%-%d%.]+)$")
			a, b = tonumber(a), tonumber(b)
			local result
			if a and b then
				if operator == "+" then
					result = a + b
				elseif operator == "-" then
					result = a - b
				elseif operator == "*" then
					result = a * b
				elseif operator == "/" and b ~= 0 then
					result = a / b
				end
			end
			calcTokens = result and { tostring(result) } or {}
			calcDisplay.Text = result and tostring(result) or "Error"
		else
			if #table.concat(calcTokens) < 24 then
				table.insert(calcTokens, value)
				calcDisplay.Text = table.concat(calcTokens)
			end
		end
	end)
end

addHeader(settingsScreen, "Settings")
local settingsProfile = label(settingsScreen, "Profile", "", 15, COLORS.ink, Enum.Font.GothamBold)
settingsProfile.Position = UDim2.fromOffset(10, 70)
settingsProfile.Size = UDim2.new(1, -20, 0, 55)
settingsProfile.TextWrapped = true
local dndButton = button(settingsScreen, "DND", "Do Not Disturb: Off", COLORS.panel2)
dndButton.Position = UDim2.fromOffset(5, 145)
dndButton.Size = UDim2.new(1, -10, 0, 52)
local soundButton = button(settingsScreen, "Sounds", "Phone sounds: On", COLORS.panel2)
soundButton.Position = UDim2.fromOffset(5, 207)
soundButton.Size = UDim2.new(1, -10, 0, 52)
local privacyCopy = label(
	settingsScreen,
	"Privacy",
	"Messages and StudSpace use Roblox TextChatService. Calls require Roblox voice eligibility and compatible communication groups. Camera saves use the native Captures gallery and keep the full screenshot.",
	13,
	COLORS.muted,
	Enum.Font.Gotham
)
privacyCopy.Position = UDim2.fromOffset(10, 290)
privacyCopy.Size = UDim2.new(1, -20, 0, 160)
privacyCopy.TextWrapped = true
privacyCopy.TextYAlignment = Enum.TextYAlignment.Top

local toast = label(shell, "Toast", "", 13, COLORS.ink, Enum.Font.GothamMedium)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 81)
toast.Size = UDim2.new(1, -40, 0, 42)
toast.BackgroundColor3 = Color3.fromRGB(29, 37, 55)
toast.BackgroundTransparency = 0.05
toast.TextXAlignment = Enum.TextXAlignment.Center
toast.TextWrapped = true
toast.Visible = false
toast.ZIndex = 50
addCorner(toast, 13)
addStroke(toast, COLORS.line, 0.25, 1)
local toastVersion = 0
local function showToast(text, isError)
	toastVersion += 1
	local version = toastVersion
	toast.Text = tostring(text or "")
	toast.TextColor3 = isError and Color3.fromRGB(255, 169, 176) or COLORS.ink
	toast.Visible = true
	task.delay(3, function()
		if toastVersion == version then
			toast.Visible = false
		end
	end)
end

local callOverlay = Instance.new("Frame")
callOverlay.Name = "CallOverlay"
callOverlay.BackgroundColor3 = Color3.fromRGB(7, 13, 24)
callOverlay.BackgroundTransparency = 0.03
callOverlay.Position = UDim2.fromOffset(0, 40)
callOverlay.Size = UDim2.new(1, 0, 1, -40)
callOverlay.Visible = false
callOverlay.ZIndex = 40
callOverlay.Parent = shell
local callName = label(callOverlay, "Name", "", 28, COLORS.ink, Enum.Font.GothamBold)
callName.Position = UDim2.fromOffset(25, 125)
callName.Size = UDim2.new(1, -50, 0, 50)
callName.TextXAlignment = Enum.TextXAlignment.Center
callName.ZIndex = 41
local callStatus = label(callOverlay, "Status", "", 14, COLORS.muted, Enum.Font.GothamMedium)
callStatus.Position = UDim2.fromOffset(25, 178)
callStatus.Size = UDim2.new(1, -50, 0, 35)
callStatus.TextXAlignment = Enum.TextXAlignment.Center
callStatus.ZIndex = 41
local acceptButton = button(callOverlay, "Accept", "Accept", COLORS.green)
acceptButton.AnchorPoint = Vector2.new(0, 1)
acceptButton.Position = UDim2.new(0, 38, 1, -60)
acceptButton.Size = UDim2.fromOffset(120, 54)
acceptButton.ZIndex = 42
local hangupButton = button(callOverlay, "Hangup", "Hang up", COLORS.red)
hangupButton.AnchorPoint = Vector2.new(1, 1)
hangupButton.Position = UDim2.new(1, -38, 1, -60)
hangupButton.Size = UDim2.fromOffset(120, 54)
hangupButton.ZIndex = 42

local function remoteRequest(action, payload)
	local ok, success, result = pcall(function()
		return Remotes.PhoneRequest:InvokeServer(action, payload or {})
	end)
	if not ok then
		return false, "Phone service is unavailable."
	end
	return success, result
end

local function clearGenerated(container)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function getConversation(contact)
	local conversation = conversations[contact.userId]
	if not conversation then
		conversation = { contact = contact, messages = {} }
		conversations[contact.userId] = conversation
	end
	return conversation
end

local renderMessages
local function openConversation(contact)
	currentContact = contact
	getConversation(contact)
	navigate("messages")
	renderMessages()
	local ok, result = remoteRequest("prepareText", { userId = contact.userId })
	if not ok then
		showToast(result, true)
	elseif result and result.channel then
		channelContacts[result.channel] = result.contact or contact
	end
end

local function renderContacts()
	clearGenerated(contactsList)
	if #contacts == 0 then
		local empty =
			label(contactsList, "Empty", "No other online phone users.", 14, COLORS.muted, Enum.Font.GothamMedium)
		empty.Size = UDim2.new(1, 0, 0, 50)
		empty.TextXAlignment = Enum.TextXAlignment.Center
		return
	end
	for _, contact in ipairs(contacts) do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = COLORS.panel
		row.Size = UDim2.new(1, -4, 0, 76)
		row.Parent = contactsList
		addCorner(row, 14)
		local initial =
			label(row, "Initial", string.upper(string.sub(contact.name, 1, 1)), 18, COLORS.ink, Enum.Font.GothamBold)
		initial.BackgroundColor3 = Color3.fromRGB(48, 72, 110)
		initial.BackgroundTransparency = 0
		initial.Position = UDim2.fromOffset(11, 13)
		initial.Size = UDim2.fromOffset(48, 48)
		initial.TextXAlignment = Enum.TextXAlignment.Center
		addCorner(initial, 24)
		local name = label(row, "Name", contact.name, 14, COLORS.ink, Enum.Font.GothamBold)
		name.Position = UDim2.fromOffset(69, 10)
		name.Size = UDim2.new(1, -210, 0, 28)
		local number = label(row, "Number", contact.number, 11, COLORS.muted, Enum.Font.GothamMedium)
		number.Position = UDim2.fromOffset(69, 36)
		number.Size = UDim2.new(1, -210, 0, 24)
		local chat = button(row, "Chat", "Text", COLORS.blue)
		chat.AnchorPoint = Vector2.new(1, 0.5)
		chat.Position = UDim2.new(1, -70, 0.5, 0)
		chat.Size = UDim2.fromOffset(58, 38)
		chat.TextSize = 12
		chat.Activated:Connect(function()
			openConversation(contact)
		end)
		local call = button(row, "Call", "Call", COLORS.green)
		call.AnchorPoint = Vector2.new(1, 0.5)
		call.Position = UDim2.new(1, -7, 0.5, 0)
		call.Size = UDim2.fromOffset(56, 38)
		call.TextSize = 12
		call.Activated:Connect(function()
			local ok, result = remoteRequest("startCall", { userId = contact.userId })
			if not ok then
				showToast(result, true)
			end
		end)
	end
end

renderMessages = function()
	clearGenerated(messageList)
	if not currentContact then
		messageContactTitle.Text = "Choose someone in Phone"
		return
	end
	messageContactTitle.Text = currentContact.name .. "  •  " .. currentContact.number
	local conversation = getConversation(currentContact)
	for _, message in ipairs(conversation.messages) do
		local mine = message.mine
		local bubble = label(messageList, "Bubble", message.text, 14, COLORS.ink, Enum.Font.Gotham)
		bubble.AutomaticSize = Enum.AutomaticSize.Y
		bubble.Size = UDim2.new(0.82, 0, 0, 38)
		bubble.TextWrapped = true
		bubble.TextXAlignment = Enum.TextXAlignment.Left
		bubble.TextYAlignment = Enum.TextYAlignment.Top
		bubble.BackgroundColor3 = mine and COLORS.blue or COLORS.panel2
		bubble.BackgroundTransparency = 0
		bubble.AnchorPoint = mine and Vector2.new(1, 0) or Vector2.new(0, 0)
		bubble.Position = mine and UDim2.new(1, -4, 0, 0) or UDim2.fromOffset(4, 0)
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 12)
		padding.PaddingRight = UDim.new(0, 12)
		padding.PaddingTop = UDim.new(0, 9)
		padding.PaddingBottom = UDim.new(0, 9)
		padding.Parent = bubble
		addCorner(bubble, 14)
	end
	task.defer(function()
		messageList.CanvasPosition =
			Vector2.new(0, math.max(0, messageLayout.AbsoluteContentSize.Y - messageList.AbsoluteSize.Y))
	end)
end

local function renderSocial()
	clearGenerated(socialList)
	if #socialPosts == 0 then
		local empty = label(
			socialList,
			"Empty",
			"StudSpace is quiet. Be the first to post.",
			13,
			COLORS.muted,
			Enum.Font.GothamMedium
		)
		empty.Size = UDim2.new(1, 0, 0, 55)
		empty.TextXAlignment = Enum.TextXAlignment.Center
		return
	end
	for _, post in ipairs(socialPosts) do
		local card = Instance.new("Frame")
		card.BackgroundColor3 = COLORS.panel
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.Size = UDim2.new(1, -4, 0, 80)
		card.Parent = socialList
		addCorner(card, 14)
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 13)
		padding.PaddingRight = UDim.new(0, 13)
		padding.PaddingTop = UDim.new(0, 11)
		padding.PaddingBottom = UDim.new(0, 11)
		padding.Parent = card
		listLayout(card, 6)
		local author = label(card, "Author", post.author, 13, Color3.fromRGB(166, 193, 255), Enum.Font.GothamBold)
		author.Size = UDim2.new(1, 0, 0, 20)
		local body = label(card, "Body", post.text, 14, COLORS.ink, Enum.Font.Gotham)
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.Size = UDim2.new(1, 0, 0, 30)
		body.TextWrapped = true
		body.TextYAlignment = Enum.TextYAlignment.Top
	end
end

local photoViewer = Instance.new("Frame")
photoViewer.Name = "PhotoViewer"
photoViewer.BackgroundColor3 = Color3.fromRGB(6, 8, 14)
photoViewer.Position = UDim2.fromOffset(0, 40)
photoViewer.Size = UDim2.new(1, 0, 1, -40)
photoViewer.Visible = false
photoViewer.ZIndex = 39
photoViewer.Parent = shell
local viewerCaption = label(photoViewer, "Caption", "", 13, COLORS.muted, Enum.Font.GothamMedium)
viewerCaption.Position = UDim2.fromOffset(16, 10)
viewerCaption.Size = UDim2.new(1, -70, 0, 36)
local viewerClose = button(photoViewer, "Close", "×", COLORS.panel2)
viewerClose.AnchorPoint = Vector2.new(1, 0)
viewerClose.Position = UDim2.new(1, -12, 0, 8)
viewerClose.Size = UDim2.fromOffset(36, 36)
viewerClose.TextSize = 20
local viewerImage = Instance.new("ImageLabel")
viewerImage.Name = "Photo"
viewerImage.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
viewerImage.BorderSizePixel = 0
viewerImage.Position = UDim2.fromOffset(12, 52)
viewerImage.Size = UDim2.new(1, -24, 1, -140)
viewerImage.ScaleType = Enum.ScaleType.Fit
viewerImage.Parent = photoViewer
addCorner(viewerImage, 14)
local viewerSave = button(photoViewer, "Save", "Save to Roblox", COLORS.blue)
viewerSave.AnchorPoint = Vector2.new(0, 1)
viewerSave.Position = UDim2.new(0, 16, 1, -16)
viewerSave.Size = UDim2.new(0.5, -24, 0, 52)
local viewerDelete = button(photoViewer, "Delete", "Delete", COLORS.red)
viewerDelete.AnchorPoint = Vector2.new(1, 1)
viewerDelete.Position = UDim2.new(1, -16, 1, -16)
viewerDelete.Size = UDim2.new(0.5, -24, 0, 52)

local viewerCapture = nil
local renderPhotos
local function closePhotoViewer()
	viewerCapture = nil
	photoViewer.Visible = false
end
local function openPhotoViewer(photo)
	viewerCapture = photo
	applyPhotoImage(viewerImage, photo)
	viewerCaption.Text = photo.takenAt and os.date("%b %d  %I:%M %p", photo.takenAt) or ""
	photoViewer.Visible = true
end
viewerClose.Activated:Connect(closePhotoViewer)
viewerSave.Activated:Connect(function()
	local photo = viewerCapture
	if not photo then
		return
	end
	local ok, err = pcall(function()
		CaptureService:PromptSaveCapturesToGallery({ photo.object }, function(results)
			if results and results[photo.object] then
				showToast("Saved to Roblox Captures")
			end
		end)
	end)
	if not ok then
		showToast("This device could not open the Captures prompt: " .. tostring(err), true)
	end
end)
viewerDelete.Activated:Connect(function()
	local photo = viewerCapture
	if not photo then
		return
	end
	local index = table.find(captures, photo)
	if index then
		table.remove(captures, index)
	end
	closePhotoViewer()
	updateGalleryThumb()
	renderPhotos()
end)

renderPhotos = function()
	clearGenerated(photoList)
	photosEmpty.Visible = #captures == 0
	for index, photo in ipairs(captures) do
		local tile = Instance.new("ImageButton")
		tile.Name = "Photo" .. index
		tile.BackgroundColor3 = COLORS.panel2
		tile.BorderSizePixel = 0
		tile.AutoButtonColor = true
		tile.ScaleType = Enum.ScaleType.Crop
		tile.Parent = photoList
		addCorner(tile, 12)
		applyPhotoImage(tile, photo)
		tile.Activated:Connect(function()
			openPhotoViewer(photo)
		end)
	end
end

local function updateSettingsUI()
	dndButton.Text = "Do Not Disturb: " .. (settings.dnd and "On" or "Off")
	dndButton.BackgroundColor3 = settings.dnd and COLORS.purple or COLORS.panel2
	soundButton.Text = "Phone sounds: " .. (settings.sounds and "On" or "Off")
	soundButton.BackgroundColor3 = settings.sounds and COLORS.blue or COLORS.panel2
	if snapshot and snapshot.profile then
		settingsProfile.Text = snapshot.profile.name .. "\n" .. snapshot.profile.number
	end
end

navigate = function(name)
	if not screens[name] then
		return
	end
	currentScreen = name
	closePhotoViewer()
	if name == "camera" then
		enterCameraMode()
	else
		exitCameraMode()
	end
	for screenName, frame in pairs(screens) do
		frame.Visible = screenName == name
	end
	if name == "contacts" then
		renderContacts()
	elseif name == "messages" then
		renderMessages()
	elseif name == "photos" then
		renderPhotos()
	elseif name == "social" then
		renderSocial()
		local ok, result = remoteRequest("prepareSocial")
		if not ok then
			showToast(result, true)
		elseif result and result.channel then
			channelContacts[result.channel] = { social = true }
		end
	elseif name == "settings" then
		updateSettingsUI()
	end
end

local function applySnapshot(newSnapshot)
	if type(newSnapshot) ~= "table" then
		return
	end
	snapshot = newSnapshot
	contacts = type(newSnapshot.contacts) == "table" and newSnapshot.contacts or {}
	settings = type(newSnapshot.settings) == "table" and newSnapshot.settings or settings
	if snapshot.profile then
		profileLabel.Text = snapshot.profile.name .. "  •  " .. snapshot.profile.number
	end
	updateSettingsUI()
end

local function connectChannel(channel)
	if not channel:IsA("TextChannel") or connectedChannels[channel] then
		return
	end
	if channel.Name ~= "QBStudSpace" and not string.match(channel.Name, "^QBPhone_") then
		return
	end
	connectedChannels[channel] = channel.MessageReceived:Connect(function(message)
		if not message.TextSource then
			return
		end
		local sourceUserId = message.TextSource.UserId
		local sourcePlayer = Players:GetPlayerByUserId(sourceUserId)
		if channel.Name == "QBStudSpace" then
			table.insert(socialPosts, 1, {
				author = sourcePlayer and sourcePlayer.DisplayName or "Player",
				text = message.Text,
			})
			while #socialPosts > 50 do
				table.remove(socialPosts)
			end
			if currentScreen == "social" then
				renderSocial()
			end
			return
		end

		local contact = channelContacts[channel.Name]
		if not contact then
			local other = nil
			if sourceUserId ~= player.UserId then
				other = sourcePlayer
			end
			if other then
				for _, candidate in ipairs(contacts) do
					if candidate.userId == other.UserId then
						contact = candidate
						break
					end
				end
			end
		end
		if not contact then
			return
		end
		channelContacts[channel.Name] = contact
		local conversation = getConversation(contact)
		table.insert(conversation.messages, { text = message.Text, mine = sourceUserId == player.UserId })
		if currentScreen == "messages" and currentContact and currentContact.userId == contact.userId then
			renderMessages()
		elseif sourceUserId ~= player.UserId then
			showToast("New message from " .. contact.name)
		end
	end)
end

for _, child in ipairs(TextChatService:GetChildren()) do
	connectChannel(child)
end
TextChatService.ChildAdded:Connect(function(child)
	task.defer(connectChannel, child)
end)

sendButton.Activated:Connect(function()
	local text = compose.Text:match("^%s*(.-)%s*$")
	if text == "" or not currentContact then
		return
	end
	local ok, result = remoteRequest("prepareText", { userId = currentContact.userId })
	if not ok then
		showToast(result, true)
		return
	end
	local channelName = result and result.channel
	local channel = channelName and TextChatService:FindFirstChild(channelName)
	if not channel then
		showToast("Private channel is still loading.", true)
		return
	end
	channelContacts[channelName] = result.contact or currentContact
	compose.Text = ""
	local sendOk, sendErr = pcall(function()
		channel:SendAsync(text, "QBPhone")
	end)
	if not sendOk then
		showToast("Roblox blocked the message: " .. tostring(sendErr), true)
	end
end)

postButton.Activated:Connect(function()
	local text = postBox.Text:match("^%s*(.-)%s*$")
	if text == "" then
		return
	end
	local ok, result = remoteRequest("prepareSocial")
	if not ok then
		showToast(result, true)
		return
	end
	local channel = result and TextChatService:FindFirstChild(result.channel)
	if not channel then
		showToast("StudSpace is unavailable.", true)
		return
	end
	postBox.Text = ""
	local sendOk, sendErr = pcall(function()
		channel:SendAsync(text, "StudSpace")
	end)
	if not sendOk then
		showToast("Roblox blocked the post: " .. tostring(sendErr), true)
	end
end)

shutter.Activated:Connect(function()
	if captureBusy then
		return
	end
	captureBusy = true
	local cropOffset, cropSize = computeCropRect()
	playCaptureFeedback()
	local started, startErr = pcall(function()
		CaptureService:TakeScreenshotCaptureAsync(function(result, capture)
			-- Keep this callback deliberately tiny: engine builds in early 2026 could
			-- terminate the client if user callback code itself threw an error.
			task.defer(function()
				captureBusy = false
				if result == Enum.ScreenshotCaptureResult.Success and capture then
					table.insert(captures, 1, {
						object = capture,
						takenAt = os.time(),
						cropOffset = cropOffset,
						cropSize = cropSize,
					})
					while #captures > 24 do
						table.remove(captures)
					end
					updateGalleryThumb()
				else
					showToast("Roblox could not capture this photo.", true)
				end
			end)
		end, { UICaptureMode = Enum.UICaptureMode.None })
	end)
	if not started then
		captureBusy = false
		showToast("Camera unavailable: " .. tostring(startErr), true)
	end
end)

dndButton.Activated:Connect(function()
	settings.dnd = not settings.dnd
	updateSettingsUI()
	local ok, result = remoteRequest("settings", settings)
	if not ok then
		settings.dnd = not settings.dnd
		showToast(result, true)
		updateSettingsUI()
	end
end)

soundButton.Activated:Connect(function()
	settings.sounds = not settings.sounds
	updateSettingsUI()
	local ok, result = remoteRequest("settings", settings)
	if not ok then
		settings.sounds = not settings.sounds
		showToast(result, true)
		updateSettingsUI()
	end
end)

local function setPhoneOpen(open)
	phoneOpen = open
	screenGui.Enabled = open or currentCall ~= nil
	if not open then
		exitCameraMode()
		closePhotoViewer()
	end
	if open and not currentCall then
		navigate(currentScreen or "home")
	end
	GuiService.SelectedObject = nil
end

closeButton.Activated:Connect(function()
	setPhoneOpen(false)
end)
homeBar.Activated:Connect(function()
	if currentCall then
		return
	end
	navigate("home")
end)

acceptButton.Activated:Connect(function()
	local ok, result = remoteRequest("acceptCall")
	if not ok then
		showToast(result, true)
	end
end)
hangupButton.Activated:Connect(function()
	local action = currentCall and currentCall.state == "incoming" and "declineCall" or "hangupCall"
	local ok, result = remoteRequest(action)
	if not ok then
		showToast(result, true)
	end
end)

Remotes.OpenPhone.OnClientEvent:Connect(function(newSnapshot)
	applySnapshot(newSnapshot)
	currentScreen = "home"
	setPhoneOpen(true)
	navigate("home")
end)

Remotes.PhonePush.OnClientEvent:Connect(function(action, payload)
	payload = type(payload) == "table" and payload or {}
	if action == "conversationReady" and payload.channel and payload.contact then
		channelContacts[payload.channel] = payload.contact
		local channel = TextChatService:FindFirstChild(payload.channel)
		if channel then
			connectChannel(channel)
		end
	elseif action == "callState" then
		local state = payload.state
		if state == "ended" or state == "declined" or state == "missed" or state == "failed" then
			currentCall = nil
			callOverlay.Visible = false
			screenGui.Enabled = phoneOpen
			showToast("Call " .. state, state == "failed")
			return
		end
		currentCall = payload
		phoneOpen = true
		screenGui.Enabled = true
		callOverlay.Visible = true
		callName.Text = payload.contact and payload.contact.name or "Unknown"
		callStatus.Text = state == "incoming" and "Incoming Roblox voice call"
			or state == "dialing" and "Calling…"
			or state == "connected" and "Connected through Roblox voice"
			or state
		acceptButton.Visible = state == "incoming"
		hangupButton.Text = state == "incoming" and "Decline" or "Hang up"
	end
end)

local function hasPhoneInItems(items)
	if type(items) ~= "table" then
		return false
	end
	for _, item in pairs(items) do
		if type(item) == "table" and item.name == "phone" and (tonumber(item.amount) or 0) > 0 then
			return true
		end
	end
	return false
end

QBCoreClient.OnPlayerDataUpdated.Event:Connect(function(key, value)
	if key == "items" and phoneOpen and not hasPhoneInItems(value) then
		setPhoneOpen(false)
	elseif key == "all" and phoneOpen and type(value) == "table" and not hasPhoneInItems(value.items) then
		setPhoneOpen(false)
	end
end)

local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local availableHeight = math.max(300, viewport.Y - 28)
	local availableWidth = math.max(220, viewport.X - 28)
	local scaleViewport = Vector2.new(availableWidth, availableHeight)
	scale.Scale = QBUIScale.FromViewport(scaleViewport, QBUIScale.Profiles.Phone)
	local margin = viewport.X < 700 and 10 or 24
	shell.Position = UDim2.new(1, -margin, 1, -math.min(18, margin))
end

local cameraConnection
local function bindCamera()
	if cameraConnection then
		cameraConnection:Disconnect()
	end
	local camera = workspace.CurrentCamera
	if camera then
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	updateScale()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
bindCamera()

task.spawn(function()
	while true do
		local now = os.date("*t")
		local hour = now.hour % 12
		if hour == 0 then
			hour = 12
		end
		local suffix = now.hour >= 12 and "PM" or "AM"
		local time = ("%d:%02d %s"):format(hour, now.min, suffix)
		timeLabel.Text = time
		homeTime.Text = time
		toolClock.Text = time
		toolDate.Text = os.date("%A, %B %d")
		task.wait(1)
	end
end)

navigate("home")
