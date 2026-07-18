-- Shared custom renderer for every ProximityPrompt in the workspace.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local COLORS = {
	panel = Color3.fromRGB(24, 30, 38),
	panelSoft = Color3.fromRGB(37, 44, 55),
	stroke = Color3.fromRGB(75, 88, 106),
	text = Color3.fromRGB(240, 244, 248),
	muted = Color3.fromRGB(158, 170, 184),
	accent = Color3.fromRGB(235, 184, 76),
}

local PROMPT_HEIGHT = 64
local PROMPT_HEIGHT_COMPACT = 54
local MIN_PROMPT_WIDTH = 170
local MAX_PROMPT_WIDTH = 350
local MAX_TEXT_WIDTH = 265
local INPUT_SIZE = 38
local FADE_TIME = 0.12

local KEY_TEXT = {
	[Enum.KeyCode.LeftControl] = "Ctrl",
	[Enum.KeyCode.RightControl] = "Ctrl",
	[Enum.KeyCode.LeftShift] = "Shift",
	[Enum.KeyCode.RightShift] = "Shift",
	[Enum.KeyCode.LeftAlt] = "Alt",
	[Enum.KeyCode.RightAlt] = "Alt",
	[Enum.KeyCode.Return] = "Enter",
	[Enum.KeyCode.Backspace] = "Back",
	[Enum.KeyCode.PageUp] = "PgUp",
	[Enum.KeyCode.PageDown] = "PgDn",
	[Enum.KeyCode.Insert] = "Ins",
	[Enum.KeyCode.Delete] = "Del",
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QBPrompts"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 64
screenGui.Parent = playerGui

local activePrompts = {}
local styleConnections = setmetatable({}, { __mode = "k" })

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

local function addStroke(parent, color, transparency, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or COLORS.stroke
	stroke.Transparency = transparency or 0
	stroke.Thickness = thickness or 1
	stroke.Parent = parent
	return stroke
end

local function getKeyboardText(keyCode)
	if KEY_TEXT[keyCode] then
		return KEY_TEXT[keyCode]
	end

	local text = UserInputService:GetStringForKeyCode(keyCode)
	if text == "" then
		text = keyCode.Name
	end
	return text
end

local function getGamepadImage(keyCode)
	local ok, image = pcall(function()
		return UserInputService:GetImageForKeyCode(keyCode)
	end)
	return ok and image or ""
end

local function getGamepadText(keyCode)
	return keyCode.Name:gsub("^Button", "")
end

local function measureText(text, size, font)
	if text == "" then
		return 0
	end
	return TextService:GetTextSize(text, size, font, Vector2.new(MAX_TEXT_WIDTH, 40)).X
end

local function createPrompt(prompt, inputType)
	local oldPrompt = activePrompts[prompt]
	if oldPrompt then
		oldPrompt.cleanup(true)
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "QBPrompt_" .. prompt.Name
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = prompt.Parent
	billboard.Parent = screenGui

	local group = Instance.new("CanvasGroup")
	group.Name = "Panel"
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.5)
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundColor3 = COLORS.panel
	group.BackgroundTransparency = 0.04
	group.BorderSizePixel = 0
	group.ClipsDescendants = true
	group.GroupTransparency = 1
	group.Parent = billboard
	addCorner(group, 8)
	addStroke(group, COLORS.stroke, 0.25, 1)

	local groupScale = Instance.new("UIScale")
	groupScale.Scale = 0.94
	groupScale.Parent = group

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.BackgroundColor3 = COLORS.accent
	accent.BorderSizePixel = 0
	accent.Size = UDim2.new(0, 3, 1, 0)
	accent.Parent = group

	local inputFrame = Instance.new("Frame")
	inputFrame.Name = "Input"
	inputFrame.AnchorPoint = Vector2.new(0, 0.5)
	inputFrame.Position = UDim2.new(0, 11, 0.5, 0)
	inputFrame.Size = UDim2.fromOffset(INPUT_SIZE, INPUT_SIZE)
	inputFrame.BackgroundColor3 = COLORS.panelSoft
	inputFrame.BorderSizePixel = 0
	inputFrame.Parent = group
	addCorner(inputFrame, 7)
	local inputStroke = addStroke(inputFrame, COLORS.accent, 0.38, 1)

	local inputScale = Instance.new("UIScale")
	inputScale.Parent = inputFrame

	local inputText = Instance.new("TextLabel")
	inputText.Name = "Key"
	inputText.BackgroundTransparency = 1
	inputText.Position = UDim2.fromOffset(4, 4)
	inputText.Size = UDim2.new(1, -8, 1, -8)
	inputText.Font = Enum.Font.GothamBold
	inputText.TextColor3 = COLORS.accent
	inputText.TextScaled = true
	inputText.AutoLocalize = false
	inputText.Parent = inputFrame

	local inputTextConstraint = Instance.new("UITextSizeConstraint")
	inputTextConstraint.MinTextSize = 8
	inputTextConstraint.MaxTextSize = 14
	inputTextConstraint.Parent = inputText

	local inputImage = Instance.new("ImageLabel")
	inputImage.Name = "Icon"
	inputImage.AnchorPoint = Vector2.new(0.5, 0.5)
	inputImage.Position = UDim2.fromScale(0.5, 0.5)
	inputImage.Size = UDim2.fromOffset(25, 25)
	inputImage.BackgroundTransparency = 1
	inputImage.ImageColor3 = COLORS.accent
	inputImage.ScaleType = Enum.ScaleType.Fit
	inputImage.Parent = inputFrame

	local actionLabel = Instance.new("TextLabel")
	actionLabel.Name = "Action"
	actionLabel.BackgroundTransparency = 1
	actionLabel.Position = UDim2.fromOffset(60, 10)
	actionLabel.Size = UDim2.new(1, -72, 0, 22)
	actionLabel.Font = Enum.Font.GothamBold
	actionLabel.TextColor3 = COLORS.text
	actionLabel.TextSize = 15
	actionLabel.TextXAlignment = Enum.TextXAlignment.Left
	actionLabel.TextYAlignment = Enum.TextYAlignment.Center
	actionLabel.TextTruncate = Enum.TextTruncate.AtEnd
	actionLabel.Parent = group

	local objectLabel = Instance.new("TextLabel")
	objectLabel.Name = "Object"
	objectLabel.BackgroundTransparency = 1
	objectLabel.Position = UDim2.fromOffset(60, 32)
	objectLabel.Size = UDim2.new(1, -72, 0, 18)
	objectLabel.Font = Enum.Font.GothamMedium
	objectLabel.TextColor3 = COLORS.muted
	objectLabel.TextSize = 12
	objectLabel.TextXAlignment = Enum.TextXAlignment.Left
	objectLabel.TextYAlignment = Enum.TextYAlignment.Center
	objectLabel.TextTruncate = Enum.TextTruncate.AtEnd
	objectLabel.Parent = group

	local progressTrack = Instance.new("Frame")
	progressTrack.Name = "HoldTrack"
	progressTrack.AnchorPoint = Vector2.new(0, 1)
	progressTrack.Position = UDim2.fromScale(0, 1)
	progressTrack.Size = UDim2.new(1, 0, 0, 3)
	progressTrack.BackgroundColor3 = COLORS.panelSoft
	progressTrack.BorderSizePixel = 0
	progressTrack.Parent = group

	local progressFill = Instance.new("Frame")
	progressFill.Name = "Progress"
	progressFill.Size = UDim2.fromScale(0, 1)
	progressFill.BackgroundColor3 = COLORS.accent
	progressFill.BorderSizePixel = 0
	progressFill.Parent = progressTrack

	local clickTarget = Instance.new("TextButton")
	clickTarget.Name = "ClickTarget"
	clickTarget.Size = UDim2.fromScale(1, 1)
	clickTarget.BackgroundTransparency = 1
	clickTarget.Text = ""
	clickTarget.AutoButtonColor = false
	clickTarget.Selectable = false
	clickTarget.ZIndex = 10
	clickTarget.Parent = group

	local connections = {}
	local holdTween
	local buttonDown = false
	local cleaned = false
	local record = {}

	local function updateInput()
		inputImage.Visible = false
		inputText.Visible = false

		if inputType == Enum.ProximityPromptInputType.Touch then
			inputImage.Image = "rbxasset://textures/ui/Controls/TouchTapIcon.png"
			inputImage.Visible = true
		elseif inputType == Enum.ProximityPromptInputType.Gamepad then
			local image = getGamepadImage(prompt.GamepadKeyCode)
			if image ~= "" then
				inputImage.Image = image
				inputImage.Visible = true
			else
				inputText.Text = getGamepadText(prompt.GamepadKeyCode)
				inputText.Visible = true
			end
		else
			inputText.Text = getKeyboardText(prompt.KeyboardKeyCode)
			inputText.Visible = true
		end
	end

	local function updateTextAndSize()
		local actionText = tostring(prompt.ActionText or "")
		local objectText = tostring(prompt.ObjectText or "")
		local compact = objectText == ""
		local height = compact and PROMPT_HEIGHT_COMPACT or PROMPT_HEIGHT
		local textWidth = math.max(
			measureText(actionText, 15, Enum.Font.GothamBold),
			measureText(objectText, 12, Enum.Font.GothamMedium)
		)
		local width = math.clamp(72 + textWidth, MIN_PROMPT_WIDTH, MAX_PROMPT_WIDTH)

		billboard.Size = UDim2.fromOffset(width, height)
		billboard.SizeOffset = Vector2.new(prompt.UIOffset.X / width, prompt.UIOffset.Y / height)
		actionLabel.Text = actionText
		actionLabel.AutoLocalize = prompt.AutoLocalize
		actionLabel.RootLocalizationTable = prompt.RootLocalizationTable
		objectLabel.Text = objectText
		objectLabel.AutoLocalize = prompt.AutoLocalize
		objectLabel.RootLocalizationTable = prompt.RootLocalizationTable
		objectLabel.Visible = not compact
		actionLabel.Position = UDim2.fromOffset(60, compact and 16 or 10)
	end

	local function updateClickability()
		local clickable = inputType == Enum.ProximityPromptInputType.Touch or prompt.ClickablePrompt
		billboard.Active = clickable
		clickTarget.Active = clickable
	end

	local function resetHold(animated)
		if holdTween then
			holdTween:Cancel()
			holdTween = nil
		end
		if animated then
			TweenService:Create(progressFill, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {
				Size = UDim2.fromScale(0, 1),
			}):Play()
		else
			progressFill.Size = UDim2.fromScale(0, 1)
		end
		TweenService:Create(inputScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
		inputStroke.Transparency = 0.38
	end

	local function beginHold()
		resetHold(false)
		if prompt.HoldDuration > 0 then
			holdTween = TweenService:Create(progressFill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), {
				Size = UDim2.fromScale(1, 1),
			})
			holdTween:Play()
		end
		TweenService:Create(inputScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad), { Scale = 1.08 }):Play()
		inputStroke.Transparency = 0
	end

	function record.cleanup(immediate)
		if cleaned then
			return
		end
		cleaned = true

		if buttonDown then
			buttonDown = false
			prompt:InputHoldEnd()
		end
		if holdTween then
			holdTween:Cancel()
		end
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		if activePrompts[prompt] == record then
			activePrompts[prompt] = nil
		end

		if immediate then
			billboard:Destroy()
		else
			TweenService:Create(group, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				GroupTransparency = 1,
			}):Play()
			TweenService:Create(groupScale, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Scale = 0.96,
			}):Play()
			task.delay(FADE_TIME, function()
				billboard:Destroy()
			end)
		end
	end

	table.insert(
		connections,
		prompt.PromptHidden:Connect(function()
			record.cleanup(false)
		end)
	)
	table.insert(
		connections,
		prompt.Destroying:Connect(function()
			record.cleanup(true)
		end)
	)
	table.insert(connections, prompt.PromptButtonHoldBegan:Connect(beginHold))
	table.insert(
		connections,
		prompt.PromptButtonHoldEnded:Connect(function()
			resetHold(true)
		end)
	)
	table.insert(
		connections,
		prompt.Triggered:Connect(function()
			TweenService:Create(inputFrame, TweenInfo.new(0.08, Enum.EasingStyle.Quad), {
				BackgroundColor3 = COLORS.accent,
			}):Play()
			task.delay(0.09, function()
				if not cleaned then
					TweenService:Create(inputFrame, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
						BackgroundColor3 = COLORS.panelSoft,
					}):Play()
				end
			end)
		end)
	)
	table.insert(
		connections,
		prompt.Changed:Connect(function(property)
			if
				property == "ActionText"
				or property == "ObjectText"
				or property == "UIOffset"
				or property == "AutoLocalize"
				or property == "RootLocalizationTable"
			then
				updateTextAndSize()
			elseif property == "KeyboardKeyCode" or property == "GamepadKeyCode" then
				updateInput()
			elseif property == "ClickablePrompt" then
				updateClickability()
			elseif property == "HoldDuration" then
				progressTrack.Visible = prompt.HoldDuration > 0
				if prompt.HoldDuration <= 0 then
					resetHold(false)
				end
			end
		end)
	)
	table.insert(
		connections,
		prompt.AncestryChanged:Connect(function()
			billboard.Adornee = prompt.Parent
		end)
	)
	table.insert(
		connections,
		clickTarget.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				if input.UserInputState ~= Enum.UserInputState.Change and not buttonDown then
					buttonDown = true
					prompt:InputHoldBegin()
				end
			end
		end)
	)
	table.insert(
		connections,
		clickTarget.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				if buttonDown then
					buttonDown = false
					prompt:InputHoldEnd()
				end
			end
		end)
	)

	activePrompts[prompt] = record
	updateInput()
	updateTextAndSize()
	updateClickability()
	progressTrack.Visible = prompt.HoldDuration > 0

	TweenService:Create(group, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
	}):Play()
	TweenService:Create(groupScale, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

local function enforceCustomStyle(prompt)
	if styleConnections[prompt] then
		return
	end

	local changingStyle = false
	local function enforce()
		if not changingStyle and prompt.Style ~= Enum.ProximityPromptStyle.Custom then
			changingStyle = true
			prompt.Style = Enum.ProximityPromptStyle.Custom
			changingStyle = false
		end
	end

	local styleConnection = prompt:GetPropertyChangedSignal("Style"):Connect(enforce)
	styleConnections[prompt] = styleConnection
	prompt.Destroying:Once(function()
		styleConnection:Disconnect()
		styleConnections[prompt] = nil
	end)
	enforce()
end

ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	enforceCustomStyle(prompt)
	createPrompt(prompt, inputType)
end)

workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") then
		enforceCustomStyle(descendant)
	end
end)

for _, descendant in ipairs(workspace:GetDescendants()) do
	if descendant:IsA("ProximityPrompt") then
		enforceCustomStyle(descendant)
	end
end
