-- Toast notification UI for Player:Notify / QBCoreClient.OnNotify.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local QBCoreClient = require(ReplicatedStorage.QBCoreClient)

local player = Players.LocalPlayer

local MAX_TOASTS = 5
local DEFAULT_DURATION = 4
local TOAST_WIDTH = 330
local TOAST_TEXT_X = 12
local TOAST_TEXT_RIGHT = 12
local TOAST_TITLE_Y = 6
local TOAST_TITLE_HEIGHT = 18
local TOAST_BODY_Y = 26
local TOAST_MIN_HEIGHT = 56
local TOAST_MAX_HEIGHT = 96

local COLORS = {
	background = Color3.fromRGB(24, 30, 38),
	stroke = Color3.fromRGB(75, 88, 106),
	text = Color3.fromRGB(242, 246, 250),
	muted = Color3.fromRGB(159, 171, 185),
	success = Color3.fromRGB(66, 173, 111),
	error = Color3.fromRGB(218, 76, 86),
	warning = Color3.fromRGB(230, 169, 69),
	info = Color3.fromRGB(82, 150, 222),
	primary = Color3.fromRGB(111, 136, 166),
}

local TYPE_META = {
	success = { title = "Success", color = COLORS.success },
	error = { title = "Error", color = COLORS.error },
	warning = { title = "Warning", color = COLORS.warning },
	warn = { title = "Warning", color = COLORS.warning },
	info = { title = "Info", color = COLORS.info },
	primary = { title = "Notice", color = COLORS.primary },
}

local function round(value)
	return math.floor(value + 0.5)
end

local function getViewportSize()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QBNotify"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 80
screenGui.Parent = player:WaitForChild("PlayerGui")

local container = Instance.new("Frame")
container.Name = "ToastStack"
container.AnchorPoint = Vector2.new(1, 0)
container.Position = UDim2.new(1, -24, 0, 110)
container.Size = UDim2.fromOffset(TOAST_WIDTH, 360)
container.BackgroundTransparency = 1
container.Parent = screenGui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 10)
layout.Parent = container

local containerScale = Instance.new("UIScale")
containerScale.Parent = container

local activeToasts = {}
local nextLayoutOrder = 0

local function updateResponsiveLayout()
	local viewport = getViewportSize()
	local scale = math.clamp(math.min(viewport.X / 900, viewport.Y / 720), 0.58, 1)
	local hudScale = math.clamp(math.min(viewport.X / 980, viewport.Y / 720), 0.58, 1)
	local margin = round(24 * scale)
	local topOffset = viewport.Y < 470 and round(58 * scale) or viewport.Y < 560 and round(78 * scale)
		or round(110 * scale)
	local hudBottom = round(24 * hudScale) + round(74 * hudScale) + round(16 * scale)
	topOffset = math.max(topOffset, hudBottom)

	containerScale.Scale = scale
	container.Position = UDim2.new(1, -margin, 0, topOffset)
	container.Size = UDim2.fromOffset(TOAST_WIDTH, math.max(160, math.min(360, viewport.Y - topOffset - margin)))
	layout.Padding = UDim.new(0, round(10 * scale))
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

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

local function addStroke(parent, color, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency or 0
	stroke.Thickness = 1
	stroke.Parent = parent
	return stroke
end

local function normalizeDuration(length)
	local seconds = tonumber(length) or DEFAULT_DURATION
	if seconds > 30 then
		seconds = seconds / 1000
	end
	return math.clamp(seconds, 1.5, 12)
end

local function destroyToast(toast)
	if toast:GetAttribute("Dismissing") then
		return
	end
	toast:SetAttribute("Dismissing", true)

	for index, active in ipairs(activeToasts) do
		if active == toast then
			table.remove(activeToasts, index)
			break
		end
	end

	local fade = TweenService:Create(toast, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
		Position = toast.Position + UDim2.fromOffset(24, 0),
	})
	fade:Play()
	fade.Completed:Once(function()
		toast:Destroy()
	end)
end

local function trimToMax()
	while #activeToasts > MAX_TOASTS do
		destroyToast(activeToasts[1])
	end
end

local function makeTextLabel(parent, name, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextSize = size
	label.Font = font
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextWrapped = true
	label.Parent = parent
	return label
end

local function getToastSize(text)
	local bodyWidth = TOAST_WIDTH - TOAST_TEXT_X - TOAST_TEXT_RIGHT
	local bounds = TextService:GetTextSize(text, 15, Enum.Font.Gotham, Vector2.new(bodyWidth, math.huge))
	local bodyHeight = math.clamp(math.ceil(bounds.Y), 18, 58)
	return bodyHeight, math.clamp(TOAST_BODY_Y + bodyHeight + 8, TOAST_MIN_HEIGHT, TOAST_MAX_HEIGHT)
end

local function showToast(message, notifyType, length)
	local text = tostring(message or "")
	if text == "" then
		return
	end

	local meta = TYPE_META[string.lower(tostring(notifyType or "info"))] or TYPE_META.info
	local duration = normalizeDuration(length)
	local bodyHeight, toastHeight = getToastSize(text)

	nextLayoutOrder -= 1

	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.BackgroundColor3 = COLORS.background
	toast.BackgroundTransparency = 1
	toast.BorderSizePixel = 0
	toast.LayoutOrder = nextLayoutOrder
	toast.Size = UDim2.new(1, 0, 0, toastHeight)
	toast.Position = UDim2.fromOffset(24, 0)
	toast.Parent = container
	addCorner(toast, 8)
	addStroke(toast, COLORS.stroke, 0.35)

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.BackgroundColor3 = meta.color
	accent.BorderSizePixel = 0
	accent.Position = UDim2.new(0, 0, 0, 0)
	accent.Size = UDim2.new(0, 4, 1, 0)
	accent.Parent = toast
	addCorner(accent, 8)

	local title = makeTextLabel(toast, "Title", meta.title, 14, meta.color, Enum.Font.GothamBold)
	title.Position = UDim2.fromOffset(TOAST_TEXT_X, TOAST_TITLE_Y)
	title.Size = UDim2.new(1, -(TOAST_TEXT_X + TOAST_TEXT_RIGHT), 0, TOAST_TITLE_HEIGHT)

	local body = makeTextLabel(toast, "Body", text, 15, COLORS.text, Enum.Font.Gotham)
	body.Position = UDim2.fromOffset(TOAST_TEXT_X, TOAST_BODY_Y)
	body.Size = UDim2.new(1, -(TOAST_TEXT_X + TOAST_TEXT_RIGHT), 0, bodyHeight)
	body.TextYAlignment = Enum.TextYAlignment.Top

	table.insert(activeToasts, toast)
	trimToMax()

	TweenService:Create(toast, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.06,
		Position = UDim2.fromOffset(0, 0),
	}):Play()

	task.delay(duration, function()
		if toast.Parent then
			destroyToast(toast)
		end
	end)
end

QBCoreClient.OnNotify.Event:Connect(showToast)

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindResponsiveLayout)
bindResponsiveLayout()
