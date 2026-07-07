-- Clean QBCore HUD: compact status bars plus a small character/money panel.
-- Health reads from the Roblox Humanoid; armor, hunger, thirst, stress, money,
-- and job come from QBCoreClient.PlayerData.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local QBCoreClient = require(ReplicatedStorage.QBCoreClient)
local QBShared = require(ReplicatedStorage.QBShared.Main)

local player = Players.LocalPlayer

local COLORS = {
	panel = Color3.fromRGB(24, 30, 38),
	track = Color3.fromRGB(45, 54, 66),
	stroke = Color3.fromRGB(75, 88, 106),
	strokeSoft = Color3.fromRGB(58, 70, 86),
	text = Color3.fromRGB(240, 244, 248),
	muted = Color3.fromRGB(158, 170, 184),
	health = Color3.fromRGB(214, 76, 86),
	armor = Color3.fromRGB(72, 141, 213),
	hunger = Color3.fromRGB(224, 151, 67),
	thirst = Color3.fromRGB(73, 177, 205),
	stress = Color3.fromRGB(190, 102, 212),
	cash = Color3.fromRGB(70, 172, 112),
	bank = Color3.fromRGB(82, 150, 222),
	accent = Color3.fromRGB(235, 184, 76),
}

local BAR_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MIN_HUD_SCALE = 0.58

local function clampPercent(value)
	value = tonumber(value) or 0
	return math.clamp(value, 0, 100)
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

local function setCoreGuiEnabled(coreGuiType, enabled)
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(coreGuiType, enabled)
			end)
			if ok then
				return
			end
			task.wait(0.25)
		end
	end)
end

local function disableResetButton()
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCore("ResetButtonCallback", false)
			end)
			if ok then
				return
			end
			task.wait(0.25)
		end
	end)
end

local function applyCoreGuiOverrides()
	setCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	disableResetButton()
end

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

local function addPadding(parent, left, top, right, bottom)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, left or 0)
	padding.PaddingTop = UDim.new(0, top or 0)
	padding.PaddingRight = UDim.new(0, right or left or 0)
	padding.PaddingBottom = UDim.new(0, bottom or top or 0)
	padding.Parent = parent
	return padding
end

local function makeLabel(parent, name, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Text = text or ""
	label.TextColor3 = color or COLORS.text
	label.TextSize = size or 13
	label.Font = font or Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextWrapped = false
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = parent
	return label
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QBHud"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 20
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local infoPanel = Instance.new("Frame")
infoPanel.Name = "InfoPanel"
infoPanel.AnchorPoint = Vector2.new(1, 0)
infoPanel.Position = UDim2.new(1, -24, 0, 24)
infoPanel.Size = UDim2.fromOffset(270, 74)
infoPanel.BackgroundColor3 = COLORS.panel
infoPanel.BackgroundTransparency = 0.06
infoPanel.BorderSizePixel = 0
infoPanel.Parent = screenGui
addCorner(infoPanel, 8)
addStroke(infoPanel, COLORS.stroke, 0.32, 1)
addPadding(infoPanel, 12, 10, 12, 10)

local infoScale = Instance.new("UIScale")
infoScale.Parent = infoPanel

local characterLabel = makeLabel(infoPanel, "Character", "", 15, COLORS.text, Enum.Font.GothamBold)
characterLabel.Size = UDim2.new(1, -92, 0, 22)

local jobLabel = makeLabel(infoPanel, "Job", "", 12, COLORS.accent, Enum.Font.GothamBold)
jobLabel.AnchorPoint = Vector2.new(1, 0)
jobLabel.Position = UDim2.new(1, 0, 0, 0)
jobLabel.Size = UDim2.new(0, 88, 0, 22)
jobLabel.TextXAlignment = Enum.TextXAlignment.Right

local cashLabel = makeLabel(infoPanel, "Cash", "", 13, COLORS.cash, Enum.Font.GothamBold)
cashLabel.Position = UDim2.fromOffset(0, 31)
cashLabel.Size = UDim2.new(0.5, -4, 0, 22)

local bankLabel = makeLabel(infoPanel, "Bank", "", 13, COLORS.bank, Enum.Font.GothamBold)
bankLabel.Position = UDim2.new(0.5, 8, 0, 31)
bankLabel.Size = UDim2.new(0.5, -8, 0, 22)
bankLabel.TextXAlignment = Enum.TextXAlignment.Right

local statusPanel = Instance.new("Frame")
statusPanel.Name = "StatusPanel"
statusPanel.AnchorPoint = Vector2.new(0, 1)
statusPanel.Position = UDim2.new(0, 18, 1, -22)
statusPanel.Size = UDim2.fromOffset(270, 166)
statusPanel.BackgroundColor3 = COLORS.panel
statusPanel.BackgroundTransparency = 0.06
statusPanel.BorderSizePixel = 0
statusPanel.Parent = screenGui
addCorner(statusPanel, 8)
addStroke(statusPanel, COLORS.stroke, 0.32, 1)
addPadding(statusPanel, 12, 11, 12, 11)

local statusScale = Instance.new("UIScale")
statusScale.Parent = statusPanel

local titleRow = Instance.new("Frame")
titleRow.Name = "TitleRow"
titleRow.BackgroundTransparency = 1
titleRow.Size = UDim2.new(1, 0, 0, 20)
titleRow.Parent = statusPanel

local statusTitle = makeLabel(titleRow, "Title", "STATUS", 12, COLORS.muted, Enum.Font.GothamBold)
statusTitle.Size = UDim2.new(0.5, 0, 1, 0)

local statusHint = makeLabel(titleRow, "Hint", "", 12, COLORS.muted, Enum.Font.GothamMedium)
statusHint.AnchorPoint = Vector2.new(1, 0)
statusHint.Position = UDim2.new(1, 0, 0, 0)
statusHint.Size = UDim2.new(0.5, 0, 1, 0)
statusHint.TextXAlignment = Enum.TextXAlignment.Right

local rowsFrame = Instance.new("Frame")
rowsFrame.Name = "Rows"
rowsFrame.BackgroundTransparency = 1
rowsFrame.Position = UDim2.fromOffset(0, 28)
rowsFrame.Size = UDim2.new(1, 0, 1, -28)
rowsFrame.Parent = statusPanel

local rowsLayout = Instance.new("UIListLayout")
rowsLayout.FillDirection = Enum.FillDirection.Vertical
rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowsLayout.Padding = UDim.new(0, 6)
rowsLayout.Parent = rowsFrame

local bars = {}

local function makeStatusRow(name, labelText, color, layoutOrder)
	local row = Instance.new("Frame")
	row.Name = name .. "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 20)
	row.LayoutOrder = layoutOrder
	row.Parent = rowsFrame

	local label = makeLabel(row, "Label", labelText, 12, COLORS.text, Enum.Font.GothamBold)
	label.Size = UDim2.fromOffset(46, 20)

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundColor3 = COLORS.track
	track.BorderSizePixel = 0
	track.Position = UDim2.fromOffset(54, 5)
	track.Size = UDim2.new(1, -94, 0, 10)
	track.Parent = row
	addCorner(track, 5)
	addStroke(track, COLORS.strokeSoft, 0.45, 1)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Parent = track
	addCorner(fill, 5)

	local value = makeLabel(row, "Value", "0", 12, COLORS.muted, Enum.Font.GothamBold)
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, 0, 0, 0)
	value.Size = UDim2.fromOffset(34, 20)
	value.TextXAlignment = Enum.TextXAlignment.Right

	bars[name] = {
		fill = fill,
		value = value,
	}
end

makeStatusRow("health", "HP", COLORS.health, 1)
makeStatusRow("armor", "AR", COLORS.armor, 2)
makeStatusRow("hunger", "FOOD", COLORS.hunger, 3)
makeStatusRow("thirst", "WATR", COLORS.thirst, 4)
makeStatusRow("stress", "STRS", COLORS.stress, 5)

local ammoPanel = Instance.new("Frame")
ammoPanel.Name = "AmmoPanel"
ammoPanel.AnchorPoint = Vector2.new(0, 1)
ammoPanel.Position = UDim2.new(0, 18, 1, -198)
ammoPanel.Size = UDim2.fromOffset(270, 66)
ammoPanel.BackgroundColor3 = COLORS.panel
ammoPanel.BackgroundTransparency = 0.06
ammoPanel.BorderSizePixel = 0
ammoPanel.Visible = false
ammoPanel.Parent = screenGui
addCorner(ammoPanel, 8)
addStroke(ammoPanel, COLORS.stroke, 0.32, 1)
addPadding(ammoPanel, 12, 10, 12, 10)

local ammoScale = Instance.new("UIScale")
ammoScale.Parent = ammoPanel

local weaponLabel = makeLabel(ammoPanel, "Weapon", "", 12, COLORS.muted, Enum.Font.GothamBold)
weaponLabel.Size = UDim2.new(1, 0, 0, 16)

local ammoLabel = makeLabel(ammoPanel, "Ammo", "", 21, COLORS.text, Enum.Font.GothamBold)
ammoLabel.Position = UDim2.fromOffset(0, 20)
ammoLabel.Size = UDim2.new(0.6, 0, 0, 26)

local reserveLabel = makeLabel(ammoPanel, "Reserve", "", 13, COLORS.muted, Enum.Font.GothamBold)
reserveLabel.AnchorPoint = Vector2.new(1, 0)
reserveLabel.Position = UDim2.new(1, 0, 0, 20)
reserveLabel.Size = UDim2.new(0.4, 0, 0, 26)
reserveLabel.TextXAlignment = Enum.TextXAlignment.Right

-- The endorsed Weapons Kit tracks the loaded magazine in a "CurrentAmmo" value
-- it creates on the Tool at runtime; capacity comes from Configuration values
-- that WeaponService applies from the shared item definition.
local WEAPON_TOOL_ATTRIBUTE = "QBWeaponTool"
local WEAPON_ITEM_ATTRIBUTE = "QBInventoryItemName"
local CURRENT_AMMO_NAME = "CurrentAmmo"

local weaponConnections = {}
local characterToolConnections = {}

local function disconnectAll(connections)
	for index = #connections, 1, -1 do
		connections[index]:Disconnect()
		connections[index] = nil
	end
end

local function getWeaponDefinition(tool)
	local itemName = tool:GetAttribute(WEAPON_ITEM_ATTRIBUTE)
	if type(itemName) ~= "string" then
		return nil
	end
	return QBShared.Items[itemName]
end

local function isWeaponTool(instance)
	return instance:IsA("Tool")
		and (instance:GetAttribute(WEAPON_TOOL_ATTRIBUTE) == true or getWeaponDefinition(instance) ~= nil)
end

local function getAmmoCapacity(tool, definition)
	local config = tool:FindFirstChild("Configuration")
	local capacityValue = config and config:FindFirstChild("AmmoCapacity")
	if capacityValue and capacityValue:IsA("ValueBase") then
		return tonumber(capacityValue.Value)
	end

	local weapon = definition and type(definition.weapon) == "table" and definition.weapon or nil
	local configValues = weapon and (weapon.config or weapon.configuration) or nil
	if type(configValues) == "table" then
		return tonumber(configValues.AmmoCapacity)
	end

	return nil
end

local currentAmmoItemName = nil

local function countReserve(ammoItemName)
	local playerData = QBCoreClient.GetPlayerData()
	local items = playerData and playerData.items
	if type(items) ~= "table" then
		return 0
	end

	local count = 0
	for _, item in pairs(items) do
		if type(item) == "table" and item.name == ammoItemName then
			count += tonumber(item.amount) or 0
		end
	end
	return count
end

local function refreshReserve()
	if not currentAmmoItemName then
		reserveLabel.Text = ""
		return
	end
	reserveLabel.Text = ("×%d"):format(countReserve(currentAmmoItemName))
end

local function setAmmoText(current, capacity)
	if current and capacity then
		ammoLabel.Text = ("%d / %d"):format(current, capacity)
	elseif capacity then
		ammoLabel.Text = ("- / %d"):format(capacity)
	elseif current then
		ammoLabel.Text = tostring(current)
	else
		ammoLabel.Text = "-"
	end
end

local function watchEquippedWeapon(tool)
	disconnectAll(weaponConnections)

	if not tool then
		currentAmmoItemName = nil
		ammoPanel.Visible = false
		return
	end

	local definition = getWeaponDefinition(tool)
	weaponLabel.Text = string.upper(definition and definition.label or tool.Name)

	local weapon = definition and type(definition.weapon) == "table" and definition.weapon or {}
	currentAmmoItemName = type(weapon.ammoItem) == "string" and weapon.ammoItem or nil
	refreshReserve()

	local capacity = getAmmoCapacity(tool, definition)
	setAmmoText(nil, capacity)
	ammoPanel.Visible = true

	local function bindAmmoValue(ammoValue)
		local function refresh()
			setAmmoText(tonumber(ammoValue.Value), capacity)
		end
		weaponConnections[#weaponConnections + 1] = ammoValue:GetPropertyChangedSignal("Value"):Connect(refresh)
		refresh()
	end

	local ammoValue = tool:FindFirstChild(CURRENT_AMMO_NAME)
	if ammoValue and ammoValue:IsA("ValueBase") then
		bindAmmoValue(ammoValue)
	else
		weaponConnections[#weaponConnections + 1] = tool.ChildAdded:Connect(function(child)
			if child.Name == CURRENT_AMMO_NAME and child:IsA("ValueBase") then
				bindAmmoValue(child)
			end
		end)
	end
end

local function bindCharacterWeapons(character)
	disconnectAll(characterToolConnections)
	watchEquippedWeapon(nil)

	characterToolConnections[#characterToolConnections + 1] = character.ChildAdded:Connect(function(child)
		if isWeaponTool(child) then
			watchEquippedWeapon(child)
		end
	end)

	characterToolConnections[#characterToolConnections + 1] = character.ChildRemoved:Connect(function(child)
		if not child:IsA("Tool") then
			return
		end
		local equipped = character:FindFirstChildOfClass("Tool")
		watchEquippedWeapon(equipped and isWeaponTool(equipped) and equipped or nil)
	end)

	local equipped = character:FindFirstChildOfClass("Tool")
	if equipped and isWeaponTool(equipped) then
		watchEquippedWeapon(equipped)
	end
end

local function getViewportSize()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function updateResponsiveLayout()
	local viewport = getViewportSize()
	local scale = math.clamp(math.min(viewport.X / 980, viewport.Y / 720), MIN_HUD_SCALE, 1)

	infoScale.Scale = scale
	statusScale.Scale = scale
	ammoScale.Scale = scale

	infoPanel.Position = UDim2.new(1, -math.floor(24 * scale + 0.5), 0, math.floor(24 * scale + 0.5))
	statusPanel.Position = UDim2.new(0, math.floor(18 * scale + 0.5), 1, -math.floor(22 * scale + 0.5))
	-- Sits above the status panel: bottom margin + status height + a 10px gap.
	ammoPanel.Position = UDim2.new(0, math.floor(18 * scale + 0.5), 1, -math.floor(198 * scale + 0.5))
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

local function setBar(name, value)
	local bar = bars[name]
	if not bar then
		return
	end

	local percent = clampPercent(value)
	bar.value.Text = tostring(math.floor(percent + 0.5))

	local targetSize = UDim2.new(percent / 100, 0, 1, 0)
	TweenService:Create(bar.fill, BAR_TWEEN, {
		Size = targetSize,
	}):Play()
end

local humanoidConnection
local maxHealthConnection

local function setHealthFromHumanoid(humanoid)
	local maxHealth = math.max(humanoid.MaxHealth, 1)
	setBar("health", (humanoid.Health / maxHealth) * 100)
end

local function bindCharacter(character)
	if humanoidConnection then
		humanoidConnection:Disconnect()
		humanoidConnection = nil
	end
	if maxHealthConnection then
		maxHealthConnection:Disconnect()
		maxHealthConnection = nil
	end

	applyCoreGuiOverrides()
	bindCharacterWeapons(character)

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not humanoid then
		setBar("health", 0)
		return
	end

	setHealthFromHumanoid(humanoid)
	humanoidConnection = humanoid.HealthChanged:Connect(function()
		setHealthFromHumanoid(humanoid)
	end)
	maxHealthConnection = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		setHealthFromHumanoid(humanoid)
	end)
end

local function applyMetadata(metadata)
	metadata = metadata or {}
	setBar("armor", metadata.armor or 0)
	setBar("hunger", metadata.hunger or 0)
	setBar("thirst", metadata.thirst or 0)
	setBar("stress", metadata.stress or 0)
end

local function applyMoney(money)
	money = type(money) == "table" and money or {}
	cashLabel.Text = "Cash " .. formatMoney(money.cash)
	bankLabel.Text = "Bank " .. formatMoney(money.bank)
end

local function applyJob(job)
	job = type(job) == "table" and job or {}
	local grade = type(job.grade) == "table" and job.grade or {}
	jobLabel.Text = job.onduty == false and "OFF DUTY" or "ON DUTY"
	statusHint.Text = job.label or "Civilian"

	if grade.name and grade.name ~= "" then
		statusHint.Text = ("%s / %s"):format(statusHint.Text, grade.name)
	end
end

local function applyIdentity(playerData)
	local charinfo = type(playerData.charinfo) == "table" and playerData.charinfo or {}
	local firstname = tostring(charinfo.firstname or "")
	local lastname = tostring(charinfo.lastname or "")
	local fullName = (firstname .. " " .. lastname):match("^%s*(.-)%s*$")

	if fullName == "" then
		fullName = player.DisplayName
	end

	characterLabel.Text = fullName
end

local function applyPlayerData(playerData)
	if not playerData then
		screenGui.Enabled = false
		return
	end

	screenGui.Enabled = true
	applyCoreGuiOverrides()
	applyIdentity(playerData)
	applyMetadata(playerData.metadata)
	applyMoney(playerData.money)
	applyJob(playerData.job)
	refreshReserve()
end

QBCoreClient.OnPlayerLoaded.Event:Connect(function()
	applyPlayerData(QBCoreClient.GetPlayerData())
end)

QBCoreClient.OnPlayerDataUpdated.Event:Connect(function(key, value)
	if key == "all" then
		applyPlayerData(value)
	elseif key == "metadata" then
		applyMetadata(value)
	elseif key == "money" then
		applyMoney(value)
	elseif key == "job" then
		applyJob(value)
	elseif key == "items" then
		refreshReserve()
	elseif key == "charinfo" then
		applyPlayerData(QBCoreClient.GetPlayerData())
	end
end)

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	task.defer(bindCharacter, player.Character)
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindResponsiveLayout)
bindResponsiveLayout()

applyPlayerData(QBCoreClient.GetPlayerData())
