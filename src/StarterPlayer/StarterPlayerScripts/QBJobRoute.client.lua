-- Objective waypoint + progress bar for the route jobs (garbage, delivery,
-- bus, taxi, tow). Entirely server-driven: renders whatever snapshot the
-- JobRouteUpdated remote pushes and clears when it pushes nil.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Remotes = require(ReplicatedStorage.QBRemotes)
local QBUITheme = require(ReplicatedStorage.QBUITheme)

local COLORS = QBUITheme.Palette("Utility")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QBJobRoute"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 40
screenGui.Parent = player:WaitForChild("PlayerGui")

-- ─────────────────────────── progress bar ───────────────────────────

local bar = Instance.new("Frame")
bar.Name = "ProgressBar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -18)
bar.Size = UDim2.fromOffset(340, 54)
bar.BackgroundColor3 = COLORS.panel
bar.BackgroundTransparency = 0.08
bar.Visible = false
bar.Parent = screenGui

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 10)
barCorner.Parent = bar

local barStroke = Instance.new("UIStroke")
barStroke.Color = COLORS.stroke
barStroke.Thickness = 1
barStroke.Parent = bar

local jobText = Instance.new("TextLabel")
jobText.Name = "Job"
jobText.BackgroundTransparency = 1
jobText.Position = UDim2.fromOffset(14, 7)
jobText.Size = UDim2.new(1, -28, 0, 18)
jobText.Font = Enum.Font.GothamBold
jobText.TextSize = 14
jobText.TextColor3 = COLORS.accent
jobText.TextXAlignment = Enum.TextXAlignment.Left
jobText.Parent = bar

local detailText = Instance.new("TextLabel")
detailText.Name = "Detail"
detailText.BackgroundTransparency = 1
detailText.Position = UDim2.fromOffset(14, 27)
detailText.Size = UDim2.new(1, -28, 0, 16)
detailText.Font = Enum.Font.Gotham
detailText.TextSize = 13
detailText.TextColor3 = COLORS.text
detailText.TextXAlignment = Enum.TextXAlignment.Left
detailText.Parent = bar

-- ─────────────────────────── waypoint marker ───────────────────────────

local markerAnchor = Instance.new("Part")
markerAnchor.Name = "QBJobRouteMarker"
markerAnchor.Anchored = true
markerAnchor.CanCollide, markerAnchor.CanQuery, markerAnchor.CanTouch = false, false, false
markerAnchor.Transparency = 1
markerAnchor.Size = Vector3.new(1, 1, 1)

local billboard = Instance.new("BillboardGui")
billboard.Name = "Waypoint"
billboard.AlwaysOnTop = true
billboard.Size = UDim2.fromOffset(200, 56)
billboard.StudsOffset = Vector3.new(0, 6, 0)
billboard.MaxDistance = math.huge
billboard.Parent = markerAnchor

local markerLabel = Instance.new("TextLabel")
markerLabel.BackgroundTransparency = 1
markerLabel.Size = UDim2.new(1, 0, 0, 20)
markerLabel.Font = Enum.Font.GothamBold
markerLabel.TextSize = 15
markerLabel.TextColor3 = COLORS.accent
markerLabel.TextStrokeTransparency = 0.4
markerLabel.Parent = billboard

local distanceLabel = Instance.new("TextLabel")
distanceLabel.BackgroundTransparency = 1
distanceLabel.Position = UDim2.fromOffset(0, 20)
distanceLabel.Size = UDim2.new(1, 0, 0, 18)
distanceLabel.Font = Enum.Font.Gotham
distanceLabel.TextSize = 13
distanceLabel.TextColor3 = COLORS.text
distanceLabel.TextStrokeTransparency = 0.4
distanceLabel.Parent = billboard

local caret = Instance.new("TextLabel")
caret.BackgroundTransparency = 1
caret.Position = UDim2.fromOffset(0, 38)
caret.Size = UDim2.new(1, 0, 0, 18)
caret.Font = Enum.Font.GothamBold
caret.TextSize = 16
caret.TextColor3 = COLORS.accent
caret.TextStrokeTransparency = 0.4
caret.Text = "▼"
caret.Parent = billboard

local currentTarget = nil
local distanceConnection = nil

local function stopDistanceUpdates()
	if distanceConnection then
		distanceConnection:Disconnect()
		distanceConnection = nil
	end
end

local function startDistanceUpdates()
	stopDistanceUpdates()
	local accumulated = 0
	distanceConnection = RunService.Heartbeat:Connect(function(step)
		accumulated += step
		if accumulated < 0.25 then
			return
		end
		accumulated = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and currentTarget then
			distanceLabel.Text = ("%dm"):format(math.floor((root.Position - currentTarget).Magnitude / 3.57))
		end
	end)
end

local function clearAll()
	currentTarget = nil
	stopDistanceUpdates()
	markerAnchor.Parent = nil
	bar.Visible = false
end

Remotes.JobRouteUpdated.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" then
		clearAll()
		return
	end

	jobText.Text = tostring(snapshot.jobLabel or "Work")
	local pieces = {}
	if snapshot.label then
		table.insert(pieces, tostring(snapshot.label))
	end
	if snapshot.progress then
		table.insert(pieces, tostring(snapshot.progress))
	end
	detailText.Text = table.concat(pieces, "  •  ")
	bar.Visible = true

	if typeof(snapshot.position) == "Vector3" then
		currentTarget = snapshot.position
		markerLabel.Text = tostring(snapshot.label or "Objective")
		distanceLabel.Text = tostring(snapshot.detail or "")
		markerAnchor.CFrame = CFrame.new(snapshot.position + Vector3.new(0, 2, 0))
		markerAnchor.Parent = Workspace
		startDistanceUpdates()
	else
		currentTarget = nil
		stopDistanceUpdates()
		markerAnchor.Parent = nil
	end
end)
