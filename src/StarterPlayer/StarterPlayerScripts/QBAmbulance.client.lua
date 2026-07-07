-- Death screen and self-respawn flow, inspired by qb-ambulancejob.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.QBRemotes)
local QBCoreClient = require(ReplicatedStorage.QBCoreClient)
local QBShared = require(ReplicatedStorage.QBShared.Main)

local player = Players.LocalPlayer

local medicalConfig = QBShared.Config.Medical or {}
local deathConfig = type(medicalConfig.DeathScreen) == "table" and medicalConfig.DeathScreen or {}

if deathConfig.Enabled == false then
	return
end

local function getKeyCode(name, fallback)
	local ok, keyCode = pcall(function()
		return Enum.KeyCode[tostring(name)]
	end)
	if ok and keyCode then
		return keyCode
	end
	return fallback
end

local RESPAWN_DELAY = math.max(0, tonumber(deathConfig.RespawnDelay) or 30)
local RESPAWN_KEY = getKeyCode(deathConfig.RespawnKey or "E", Enum.KeyCode.E)
local GAMEPAD_RESPAWN_KEY = getKeyCode(deathConfig.GamepadRespawnKey or "ButtonX", Enum.KeyCode.ButtonX)

local COLORS = {
	backdrop = Color3.fromRGB(9, 10, 13),
	panel = Color3.fromRGB(24, 28, 34),
	panelSoft = Color3.fromRGB(34, 39, 48),
	stroke = Color3.fromRGB(86, 98, 116),
	text = Color3.fromRGB(241, 245, 249),
	muted = Color3.fromRGB(163, 174, 187),
	red = Color3.fromRGB(198, 70, 82),
	green = Color3.fromRGB(62, 166, 105),
	warning = Color3.fromRGB(232, 170, 73),
}

local isDead = false
local busy = false
local deathStartedAt = 0
local lastError = ""
local statusClearAt = 0
local humanoidConnection = nil

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QBAmbulance"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 70
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = COLORS.backdrop
backdrop.BackgroundTransparency = 0.25
backdrop.BorderSizePixel = 0
backdrop.Parent = screenGui

local shell = Instance.new("Frame")
shell.Name = "Shell"
shell.AnchorPoint = Vector2.new(0.5, 1)
shell.Position = UDim2.new(0.5, 0, 1, -36)
shell.Size = UDim2.fromOffset(560, 182)
shell.BackgroundColor3 = COLORS.panel
shell.BackgroundTransparency = 0.04
shell.BorderSizePixel = 0
shell.Parent = backdrop

local shellCorner = Instance.new("UICorner")
shellCorner.CornerRadius = UDim.new(0, 8)
shellCorner.Parent = shell

local shellStroke = Instance.new("UIStroke")
shellStroke.Color = COLORS.stroke
shellStroke.Transparency = 0.18
shellStroke.Thickness = 1
shellStroke.Parent = shell

local shellPadding = Instance.new("UIPadding")
shellPadding.PaddingLeft = UDim.new(0, 18)
shellPadding.PaddingRight = UDim.new(0, 18)
shellPadding.PaddingTop = UDim.new(0, 16)
shellPadding.PaddingBottom = UDim.new(0, 16)
shellPadding.Parent = shell

local shellConstraint = Instance.new("UISizeConstraint")
shellConstraint.MinSize = Vector2.new(300, 162)
shellConstraint.MaxSize = Vector2.new(560, 200)
shellConstraint.Parent = shell

local shellScale = Instance.new("UIScale")
shellScale.Parent = shell

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 10)
layout.Parent = shell

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "You Are Incapacitated"
title.TextColor3 = COLORS.text
title.TextSize = 25
title.TextWrapped = false
title.TextXAlignment = Enum.TextXAlignment.Left
title.Size = UDim2.new(1, 0, 0, 30)
title.LayoutOrder = 1
title.Parent = shell

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.Gotham
subtitle.Text = "Wait for EMS or self-respawn when the timer ends."
subtitle.TextColor3 = COLORS.muted
subtitle.TextSize = 14
subtitle.TextWrapped = true
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Size = UDim2.new(1, 0, 0, 24)
subtitle.LayoutOrder = 2
subtitle.Parent = shell

local actionRow = Instance.new("Frame")
actionRow.Name = "ActionRow"
actionRow.BackgroundTransparency = 1
actionRow.Size = UDim2.new(1, 0, 0, 54)
actionRow.LayoutOrder = 3
actionRow.Parent = shell

local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "Timer"
timerLabel.BackgroundColor3 = COLORS.panelSoft
timerLabel.BorderSizePixel = 0
timerLabel.Font = Enum.Font.GothamBold
timerLabel.Text = "00"
timerLabel.TextColor3 = COLORS.warning
timerLabel.TextSize = 24
timerLabel.TextWrapped = false
timerLabel.TextXAlignment = Enum.TextXAlignment.Center
timerLabel.Size = UDim2.new(0, 108, 1, 0)
timerLabel.Parent = actionRow

local timerCorner = Instance.new("UICorner")
timerCorner.CornerRadius = UDim.new(0, 8)
timerCorner.Parent = timerLabel

local respawnButton = Instance.new("TextButton")
respawnButton.Name = "Respawn"
respawnButton.AnchorPoint = Vector2.new(1, 0)
respawnButton.Position = UDim2.new(1, 0, 0, 0)
respawnButton.Size = UDim2.new(1, -122, 1, 0)
respawnButton.BackgroundColor3 = COLORS.green
respawnButton.BorderSizePixel = 0
respawnButton.AutoButtonColor = true
respawnButton.Font = Enum.Font.GothamBold
respawnButton.Text = "Respawn"
respawnButton.TextColor3 = COLORS.text
respawnButton.TextSize = 17
respawnButton.TextWrapped = false
respawnButton.Parent = actionRow

local respawnCorner = Instance.new("UICorner")
respawnCorner.CornerRadius = UDim.new(0, 8)
respawnCorner.Parent = respawnButton

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.GothamMedium
statusLabel.Text = ""
statusLabel.TextColor3 = COLORS.muted
statusLabel.TextSize = 13
statusLabel.TextWrapped = false
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
statusLabel.TextXAlignment = Enum.TextXAlignment.Center
statusLabel.Size = UDim2.new(1, 0, 0, 18)
statusLabel.LayoutOrder = 4
statusLabel.Parent = shell

local function getViewportSize()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function updateResponsiveLayout()
	local viewport = getViewportSize()
	local compact = viewport.X < 680 or viewport.Y < 460
	local tiny = viewport.X < 430 or viewport.Y < 360
	local margin = tiny and 10 or compact and 16 or 36
	local width = math.floor(math.min(560, math.max(300, viewport.X - margin * 2)) + 0.5)
	local height = tiny and 158 or compact and 172 or 182
	local scale = math.clamp(math.min(viewport.X / 620, viewport.Y / 420), 0.72, 1)

	shellScale.Scale = scale
	shellConstraint.MinSize = Vector2.new(math.min(300, width), math.min(150, height))
	shellConstraint.MaxSize = Vector2.new(width, height)
	shell.Size = UDim2.fromOffset(width, height)
	shell.Position = UDim2.new(0.5, 0, 1, -math.floor(margin / scale + 0.5))

	local padX = tiny and 12 or 18
	local padY = tiny and 12 or 16
	shellPadding.PaddingLeft = UDim.new(0, padX)
	shellPadding.PaddingRight = UDim.new(0, padX)
	shellPadding.PaddingTop = UDim.new(0, padY)
	shellPadding.PaddingBottom = UDim.new(0, padY)
	layout.Padding = UDim.new(0, tiny and 7 or 10)

	title.TextSize = tiny and 18 or compact and 21 or 25
	title.Size = UDim2.new(1, 0, 0, tiny and 23 or 30)
	subtitle.TextSize = tiny and 11 or 14
	subtitle.Size = UDim2.new(1, 0, 0, tiny and 34 or 24)
	actionRow.Size = UDim2.new(1, 0, 0, tiny and 44 or 54)
	timerLabel.Size = UDim2.new(0, tiny and 74 or 108, 1, 0)
	timerLabel.TextSize = tiny and 18 or 24
	respawnButton.Position = UDim2.new(1, 0, 0, 0)
	respawnButton.Size = UDim2.new(1, -(tiny and 84 or 122), 1, 0)
	respawnButton.TextSize = tiny and 13 or 17
	statusLabel.TextSize = tiny and 11 or 13
end

local function getRemaining()
	if not isDead then
		return 0
	end
	return math.max(0, RESPAWN_DELAY - (os.clock() - deathStartedAt))
end

local function setStatus(text, color)
	lastError = text or ""
	statusClearAt = lastError ~= "" and os.clock() + 3 or 0
	statusLabel.TextColor3 = color or COLORS.muted
	statusLabel.Text = lastError
end

local function setDead(nextDead)
	if nextDead == isDead then
		return
	end

	isDead = nextDead
	busy = false
	screenGui.Enabled = isDead
	lastError = ""
	statusClearAt = 0

	if isDead then
		deathStartedAt = os.clock()
	else
		deathStartedAt = 0
	end
end

local function syncDeathStateFromPlayerData(playerData)
	local metadata = type(playerData) == "table" and type(playerData.metadata) == "table" and playerData.metadata or {}
	setDead(metadata.isdead == true)
end

local function parseRemainingSeconds(message)
	if type(message) ~= "string" then
		return nil
	end
	return tonumber(message:match("(%d+)%s+seconds?"))
end

local function requestRespawn()
	if busy or not isDead then
		return
	end

	local remaining = getRemaining()
	if remaining > 0 then
		setStatus(("Respawn available in %d seconds."):format(math.ceil(remaining)), COLORS.warning)
		return
	end

	busy = true
	setStatus("Respawning...", COLORS.muted)

	local ok, result, err = pcall(function()
		return Remotes.RequestRespawn:InvokeServer()
	end)

	busy = false
	if not ok then
		setStatus("Respawn request failed.", COLORS.red)
		return
	end
	if result == false then
		local message = err or "Respawn request failed."
		local serverRemaining = parseRemainingSeconds(message)
		if serverRemaining then
			deathStartedAt = os.clock() - math.max(0, RESPAWN_DELAY - serverRemaining)
		end
		setStatus(message, COLORS.red)
		return
	end

	setDead(false)
end

local function updateVisualState()
	if not isDead then
		return
	end

	local remaining = math.ceil(getRemaining())
	local canRespawn = remaining <= 0 and not busy

	if remaining > 0 then
		timerLabel.Text = tostring(remaining)
		timerLabel.TextColor3 = COLORS.warning
	else
		timerLabel.Text = "Ready"
		timerLabel.TextColor3 = COLORS.green
	end

	respawnButton.Active = canRespawn
	respawnButton.AutoButtonColor = canRespawn
	respawnButton.BackgroundColor3 = canRespawn and COLORS.green or Color3.fromRGB(80, 89, 102)
	respawnButton.Text = busy and "Respawning..." or canRespawn and ("Respawn (" .. RESPAWN_KEY.Name .. ")") or "Respawn Locked"

	if lastError ~= "" and statusClearAt > 0 and os.clock() >= statusClearAt then
		lastError = ""
		statusClearAt = 0
	end

	if lastError == "" then
		if remaining > 0 then
			statusLabel.TextColor3 = COLORS.muted
			statusLabel.Text = "EMS can revive you before self-respawn unlocks."
		else
			statusLabel.TextColor3 = COLORS.green
			statusLabel.Text = "Self-respawn is available."
		end
	else
		statusLabel.Text = lastError
	end
end

local function bindCharacter(character)
	if humanoidConnection then
		humanoidConnection:Disconnect()
		humanoidConnection = nil
	end

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid and character then
		humanoid = character:WaitForChild("Humanoid", 10)
	end
	if not humanoid then
		return
	end

	humanoidConnection = humanoid.Died:Connect(function()
		setDead(true)
	end)
end

respawnButton.Activated:Connect(requestRespawn)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not isDead then
		return
	end

	if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == RESPAWN_KEY then
		requestRespawn()
	elseif input.UserInputType == Enum.UserInputType.Gamepad1 and input.KeyCode == GAMEPAD_RESPAWN_KEY then
		requestRespawn()
	end
end)

QBCoreClient.OnPlayerLoaded.Event:Connect(function()
	syncDeathStateFromPlayerData(QBCoreClient.GetPlayerData())
end)

QBCoreClient.OnPlayerDataUpdated.Event:Connect(function(key, value)
	if key == "all" then
		syncDeathStateFromPlayerData(value)
	elseif key == "metadata" then
		syncDeathStateFromPlayerData({ metadata = value })
	end
end)

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	task.defer(bindCharacter, player.Character)
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateResponsiveLayout)
updateResponsiveLayout()

RunService.RenderStepped:Connect(updateVisualState)

if QBCoreClient.GetPlayerData() then
	syncDeathStateFromPlayerData(QBCoreClient.GetPlayerData())
end
