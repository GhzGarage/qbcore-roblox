-- Native fixed-zoom minimap and client blip registry.
-- Normal blips are short-range. alwaysShow blips remain visible and clamp to
-- the map perimeter in the same style as long-range GTA blips.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local QBShared = require(ReplicatedStorage.QBShared.Main)
local QBUITheme = require(ReplicatedStorage.QBUITheme)
local QBUIScale = require(ReplicatedStorage.QBUIScale)

local QBMinimap = {}

local player = Players.LocalPlayer
local config = (QBShared.Config.HUD and QBShared.Config.HUD.Minimap) or {}

local COLORS = QBUITheme.Palette("Utility", {
	background = Color3.fromRGB(18, 24, 31),
	border = Color3.fromRGB(75, 88, 106),
	defaultBlip = Color3.fromRGB(235, 184, 76),
})

local MIN_HUD_SCALE = 0.58
local STATUS_TOP_OFFSET = 188 + (tonumber(config.Gap) or 10) -- bottom margin + status height + gap
local DEFAULT_SIZE = 216
local DEFAULT_STUDS_ACROSS = 1900
local DEFAULT_DISPLAY_RADIUS = 950
local DEFAULT_BLIP_SIZE = 20

local started = false
local enabled = config.Enabled ~= false
local visible = true
local blips = {}
local taggedBlipIds = {}
local taggedBlipSequence = 0
local renderConnection
local viewportConnection

local minimapFrame
local minimapScale
local mapRotator
local mapImage
local fallbackLabel
local blipLayer
local playerMarker

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function addStroke(parent, color, transparency, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = thickness
	stroke.Parent = parent
	return stroke
end

local function normalizeImageId(value)
	if type(value) == "number" and value > 0 then
		return "rbxassetid://" .. tostring(math.floor(value))
	end
	if type(value) ~= "string" or value == "" then
		return ""
	end
	if value:match("^%d+$") then
		return "rbxassetid://" .. value
	end
	return value
end

local function getViewportSize()
	return QBUIScale.GetViewportSize(workspace.CurrentCamera)
end

local function updateResponsiveLayout()
	if not minimapFrame then
		return
	end

	local viewport = getViewportSize()
	local scale = QBUIScale.FromViewport(viewport, QBUIScale.Profiles.HUD)
	minimapScale.Scale = scale
	minimapFrame.Position = UDim2.new(0, math.floor(18 * scale + 0.5), 1, -math.floor(STATUS_TOP_OFFSET * scale + 0.5))
end

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

local function resolvePosition(source)
	if typeof(source) == "Vector3" then
		return source
	end
	if typeof(source) ~= "Instance" or not source.Parent then
		return nil
	end
	if source:IsA("Attachment") then
		return source.WorldPosition
	end
	if source:IsA("BasePart") then
		return source.Position
	end
	if source:IsA("Model") then
		return source:GetPivot().Position
	end
	return nil
end

local function createBlipGui(blip)
	if not blipLayer or blip.gui then
		return
	end

	local size = math.max(12, tonumber(blip.options.size) or DEFAULT_BLIP_SIZE)
	local icon = Instance.new("Frame")
	icon.Name = "Blip_" .. blip.id
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Size = UDim2.fromOffset(size, size)
	icon.BackgroundColor3 = blip.options.color or COLORS.defaultBlip
	icon.BorderSizePixel = 0
	icon.Visible = false
	icon.ZIndex = 4
	icon.Parent = blipLayer
	addCorner(icon, math.floor(size / 2))
	addStroke(icon, Color3.fromRGB(12, 16, 22), 0.08, 2)

	local imageId = normalizeImageId(blip.options.image)
	if imageId ~= "" then
		local imageLabel = Instance.new("ImageLabel")
		imageLabel.Name = "Image"
		imageLabel.BackgroundTransparency = 1
		imageLabel.Position = UDim2.fromOffset(3, 3)
		imageLabel.Size = UDim2.new(1, -6, 1, -6)
		imageLabel.Image = imageId
		imageLabel.ZIndex = 5
		imageLabel.Parent = icon
	else
		local symbol = Instance.new("TextLabel")
		symbol.Name = "Symbol"
		symbol.BackgroundTransparency = 1
		symbol.Size = UDim2.fromScale(1, 1)
		symbol.Font = Enum.Font.GothamBold
		symbol.Text = tostring(blip.options.symbol or ".")
		symbol.TextColor3 = COLORS.text
		symbol.TextScaled = true
		symbol.ZIndex = 5
		symbol.Parent = icon

		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = math.max(10, size - 6)
		constraint.MinTextSize = 8
		constraint.Parent = symbol
	end

	blip.gui = icon
end

local function destroyBlipGui(blip)
	if blip and blip.gui then
		blip.gui:Destroy()
		blip.gui = nil
	end
end

function QBMinimap.AddBlip(id, options)
	assert(type(id) == "string" and id ~= "", "QBMinimap.AddBlip requires a non-empty string id")
	assert(type(options) == "table", "QBMinimap.AddBlip requires an options table")
	assert(resolvePosition(options.position or options.instance), "QBMinimap blip requires a Vector3 or world instance")

	local existing = blips[id]
	if existing then
		destroyBlipGui(existing)
	end

	local blip = {
		id = id,
		options = options,
		gui = nil,
	}
	blips[id] = blip
	createBlipGui(blip)
	return id
end

function QBMinimap.RemoveBlip(id)
	local blip = blips[id]
	if not blip then
		return false
	end
	destroyBlipGui(blip)
	blips[id] = nil
	return true
end

function QBMinimap.SetBlipAlwaysShow(id, shouldAlwaysShow)
	local blip = blips[id]
	if not blip then
		return false
	end
	blip.options.alwaysShow = shouldAlwaysShow == true
	return true
end

function QBMinimap.SetVisible(shouldShow)
	visible = shouldShow == true
	if minimapFrame and not visible then
		minimapFrame.Visible = false
	end
end

function QBMinimap.IsVisible()
	return visible
end

local function addTaggedBlip(instance)
	if not resolvePosition(instance) then
		warn(("QBMinimap ignored unsupported tagged instance %s"):format(instance:GetFullName()))
		return
	end

	taggedBlipSequence += 1
	local configuredId = instance:GetAttribute("MinimapId")
	local id = type(configuredId) == "string" and configuredId ~= "" and configuredId
		or ("tagged_%d"):format(taggedBlipSequence)
	taggedBlipIds[instance] = id

	QBMinimap.AddBlip(id, {
		instance = instance,
		label = instance:GetAttribute("MinimapLabel") or instance.Name,
		image = instance:GetAttribute("MinimapImage"),
		symbol = instance:GetAttribute("MinimapSymbol"),
		color = instance:GetAttribute("MinimapColor"),
		size = instance:GetAttribute("MinimapSize"),
		displayRadius = instance:GetAttribute("MinimapDisplayRadius"),
		alwaysShow = instance:GetAttribute("MinimapAlwaysShow") == true,
	})
end

local function removeTaggedBlip(instance)
	local id = taggedBlipIds[instance]
	if id then
		QBMinimap.RemoveBlip(id)
		taggedBlipIds[instance] = nil
	end
end

local function createGui()
	local screenGui = player:WaitForChild("PlayerGui"):WaitForChild("QBHud")
	local size = math.max(120, tonumber(config.Size) or DEFAULT_SIZE)

	minimapFrame = Instance.new("CanvasGroup")
	minimapFrame.Name = "Minimap"
	minimapFrame.AnchorPoint = Vector2.new(0, 1)
	minimapFrame.Position = UDim2.new(0, 18, 1, -STATUS_TOP_OFFSET)
	minimapFrame.Size = UDim2.fromOffset(size, size)
	minimapFrame.BackgroundColor3 = COLORS.background
	minimapFrame.BorderSizePixel = 0
	minimapFrame.ClipsDescendants = true
	minimapFrame.ZIndex = 1
	minimapFrame.Parent = screenGui
	addCorner(minimapFrame, 14)
	addStroke(minimapFrame, COLORS.border, 0.2, 2)

	minimapScale = Instance.new("UIScale")
	minimapScale.Parent = minimapFrame

	mapRotator = Instance.new("Frame")
	mapRotator.Name = "MapRotator"
	mapRotator.BackgroundTransparency = 1
	mapRotator.Size = UDim2.fromScale(1, 1)
	mapRotator.ZIndex = 1
	mapRotator.Parent = minimapFrame

	local imageId = normalizeImageId(config.Image)
	mapImage = Instance.new("ImageLabel")
	mapImage.Name = "MapImage"
	mapImage.AnchorPoint = Vector2.new(0.5, 0.5)
	mapImage.BackgroundTransparency = 1
	mapImage.Image = imageId
	mapImage.ScaleType = Enum.ScaleType.Stretch
	mapImage.ZIndex = 1
	mapImage.Parent = mapRotator

	fallbackLabel = Instance.new("TextLabel")
	fallbackLabel.Name = "MissingMapImage"
	fallbackLabel.BackgroundTransparency = 1
	fallbackLabel.Position = UDim2.fromScale(0.12, 0.32)
	fallbackLabel.Size = UDim2.fromScale(0.76, 0.36)
	fallbackLabel.Font = Enum.Font.GothamBold
	fallbackLabel.Text = imageId == "" and "MINIMAP\nIMAGE NOT SET" or "LOADING\nMINIMAP"
	fallbackLabel.TextColor3 = COLORS.muted
	fallbackLabel.TextSize = 12
	fallbackLabel.TextWrapped = true
	fallbackLabel.Visible = true
	fallbackLabel.ZIndex = 2
	fallbackLabel.Parent = minimapFrame
	if imageId ~= "" then
		local function updateMapLoadState()
			fallbackLabel.Visible = not mapImage.IsLoaded
		end
		mapImage:GetPropertyChangedSignal("IsLoaded"):Connect(updateMapLoadState)
		updateMapLoadState()
	end

	blipLayer = Instance.new("Frame")
	blipLayer.Name = "Blips"
	blipLayer.BackgroundTransparency = 1
	blipLayer.Size = UDim2.fromScale(1, 1)
	blipLayer.ZIndex = 3
	blipLayer.Parent = minimapFrame

	playerMarker = Instance.new("Frame")
	playerMarker.Name = "PlayerMarker"
	playerMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	playerMarker.BackgroundTransparency = 1
	playerMarker.Position = UDim2.fromScale(0.5, 0.5)
	playerMarker.Size = UDim2.fromOffset(26, 26)
	playerMarker.ZIndex = 7
	playerMarker.Parent = minimapFrame

	local markerNose = Instance.new("Frame")
	markerNose.Name = "Nose"
	markerNose.AnchorPoint = Vector2.new(0.5, 1)
	markerNose.BackgroundColor3 = COLORS.text
	markerNose.BorderSizePixel = 0
	markerNose.Position = UDim2.fromScale(0.5, 0.4)
	markerNose.Size = UDim2.fromOffset(5, 10)
	markerNose.ZIndex = 7
	markerNose.Parent = playerMarker
	addCorner(markerNose, 2)
	addStroke(markerNose, Color3.fromRGB(10, 14, 20), 0.08, 2)

	local markerBody = Instance.new("Frame")
	markerBody.Name = "Body"
	markerBody.AnchorPoint = Vector2.new(0.5, 0.5)
	markerBody.BackgroundColor3 = COLORS.text
	markerBody.BorderSizePixel = 0
	markerBody.Position = UDim2.fromScale(0.5, 0.56)
	markerBody.Rotation = 45
	markerBody.Size = UDim2.fromOffset(13, 13)
	markerBody.ZIndex = 8
	markerBody.Parent = playerMarker
	addCorner(markerBody, 2)
	addStroke(markerBody, Color3.fromRGB(10, 14, 20), 0.08, 2)

	for _, blip in pairs(blips) do
		createBlipGui(blip)
	end
end

local function headingDegrees(root)
	local look = root.CFrame.LookVector
	return math.deg(math.atan2(look.X, -look.Z))
end

local function rotatePoint(point, degrees)
	local radians = math.rad(degrees)
	local cosine = math.cos(radians)
	local sine = math.sin(radians)
	return Vector2.new(point.X * cosine - point.Y * sine, point.X * sine + point.Y * cosine)
end

local function clampToRectangle(point, halfExtent)
	if math.abs(point.X) <= halfExtent and math.abs(point.Y) <= halfExtent then
		return point, false
	end

	local xScale = math.abs(point.X) > 0 and halfExtent / math.abs(point.X) or math.huge
	local yScale = math.abs(point.Y) > 0 and halfExtent / math.abs(point.Y) or math.huge
	return point * math.min(xScale, yScale), true
end

local function updateMap(root)
	local size = math.max(120, tonumber(config.Size) or DEFAULT_SIZE)
	local studsAcross = math.max(100, tonumber(config.StudsAcross) or DEFAULT_STUDS_ACROSS)
	local pixelsPerStud = size / studsAcross
	local pixelSize = config.MapPixelSize or Vector2.new(2752, 1536)
	local originPixel = config.WorldOriginPixel or Vector2.new(1426.5, 761)
	local studsPerPixel = config.StudsPerPixel or Vector2.new(4.470588, 4.469771)
	local sourceScale = ((studsPerPixel.X + studsPerPixel.Y) * 0.5) * pixelsPerStud
	local worldPosition = root.Position
	local playerPixel = Vector2.new(
		worldPosition.X / studsPerPixel.X + originPixel.X,
		worldPosition.Z / studsPerPixel.Y + originPixel.Y
	)
	local imageOffset = (pixelSize * 0.5 - playerPixel) * sourceScale
	local heading = headingDegrees(root)
	local mapRotation = config.RotateWithHeading == false and 0 or -heading

	mapImage.Size = UDim2.fromOffset(pixelSize.X * sourceScale, pixelSize.Y * sourceScale)
	mapImage.Position = UDim2.new(0.5, imageOffset.X, 0.5, imageOffset.Y)
	mapRotator.Rotation = mapRotation
	playerMarker.Rotation = config.RotateWithHeading == false and heading or 0

	local edgePadding = math.max(0, tonumber(config.EdgePadding) or 13)
	local halfExtent = size * 0.5 - edgePadding

	for id, blip in pairs(blips) do
		local gui = blip.gui
		local blipPosition = resolvePosition(blip.options.position or blip.options.instance)
		if not gui or not blipPosition then
			if gui then
				gui.Visible = false
			end
			if blip.options.instance and not blipPosition then
				QBMinimap.RemoveBlip(id)
			end
			continue
		end

		local delta = Vector2.new(blipPosition.X - worldPosition.X, blipPosition.Z - worldPosition.Z)
		local distance = delta.Magnitude
		local screenPoint = rotatePoint(delta * pixelsPerStud, mapRotation)
		local clampedPoint, wasClamped = clampToRectangle(screenPoint, halfExtent)
		local alwaysShow = blip.options.alwaysShow == true
		local displayRadius = math.max(
			0,
			tonumber(blip.options.displayRadius) or tonumber(config.DefaultDisplayRadius) or DEFAULT_DISPLAY_RADIUS
		)

		gui.Visible = alwaysShow or (distance <= displayRadius and not wasClamped)
		if gui.Visible then
			local finalPoint = alwaysShow and clampedPoint or screenPoint
			gui.Position = UDim2.new(0.5, finalPoint.X, 0.5, finalPoint.Y)
		end
	end
end

local function getRootPart()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

function QBMinimap.Start()
	if started or not enabled then
		return
	end
	started = true

	for _, definition in ipairs(config.Blips or {}) do
		QBMinimap.AddBlip(definition.id, definition)
	end

	createGui()
	bindResponsiveLayout()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindResponsiveLayout)

	local function updateApartmentVisibility()
		QBMinimap.SetVisible(player:GetAttribute("QBApartmentId") == nil)
	end
	player:GetAttributeChangedSignal("QBApartmentId"):Connect(updateApartmentVisibility)
	updateApartmentVisibility()

	local tag = tostring(config.CollectionTag or "QBMinimapBlip")
	for _, instance in ipairs(CollectionService:GetTagged(tag)) do
		addTaggedBlip(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(addTaggedBlip)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(removeTaggedBlip)

	renderConnection = RunService.RenderStepped:Connect(function()
		local root = getRootPart()
		local shouldRender = root ~= nil and visible
		if minimapFrame then
			minimapFrame.Visible = shouldRender
		end
		if shouldRender then
			updateMap(root)
		end
	end)
end

return QBMinimap
