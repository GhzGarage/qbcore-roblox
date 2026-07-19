-- Standalone native management panel for jobs and crews. Authorization, proximity,
-- membership changes and nearby-player validation stay on the server.

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
local accessContext = { locationId = "" }
local activeTab = "members"
local selectedCitizenId = nil
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

local function callRemote(remote, ...)
	local results = table.pack(pcall(remote.InvokeServer, remote, ...))
	if not results[1] then
		warn("[QBManagement] Remote call failed: " .. tostring(results[2]))
		return nil, "The management server did not respond."
	end
	return table.unpack(results, 2, results.n)
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QBManagement"
screenGui.DisplayOrder = 58
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
shell.Size = UDim2.fromOffset(900, 620)
shell.Parent = overlay
addCorner(shell, 10)
addStroke(shell, COLORS.stroke, 0.12, 1)

local shellScale = Instance.new("UIScale")
shellScale.Parent = shell

local header = Instance.new("Frame")
header.BackgroundTransparency = 1
header.Position = UDim2.fromOffset(24, 17)
header.Size = UDim2.new(1, -48, 0, 68)
header.Parent = shell
local eyebrow = makeLabel(header, "Eyebrow", "QBCORE MANAGEMENT", 11, COLORS.gold, Enum.Font.GothamBold)
eyebrow.Size = UDim2.new(1, -60, 0, 17)
local titleLabel = makeLabel(header, "Title", "Organization Management", 25, COLORS.text, Enum.Font.GothamBold)
titleLabel.Position = UDim2.fromOffset(0, 16)
titleLabel.Size = UDim2.new(0.62, 0, 0, 31)
local subtitleLabel = makeLabel(
	header,
	"Subtitle",
	"Employees, grades, recruitment, and appearance.",
	12,
	COLORS.muted,
	Enum.Font.GothamMedium
)
subtitleLabel.Position = UDim2.fromOffset(0, 47)
subtitleLabel.Size = UDim2.new(0.7, 0, 0, 18)
local closeButton = makeButton(header, "Close", "X", COLORS.panelSoft)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, 0, 0, 2)
closeButton.Size = UDim2.fromOffset(42, 42)
closeButton.TextSize = 15

local divider = Instance.new("Frame")
divider.BackgroundColor3 = COLORS.strokeSoft
divider.BackgroundTransparency = 0.25
divider.BorderSizePixel = 0
divider.Position = UDim2.fromOffset(24, 96)
divider.Size = UDim2.new(1, -48, 0, 1)
divider.Parent = shell

local tabs = Instance.new("Frame")
tabs.BackgroundTransparency = 1
tabs.Position = UDim2.fromOffset(24, 109)
tabs.Size = UDim2.new(1, -48, 0, 39)
tabs.Parent = shell
local tabsLayout = Instance.new("UIListLayout")
tabsLayout.FillDirection = Enum.FillDirection.Horizontal
tabsLayout.Padding = UDim.new(0, 8)
tabsLayout.Parent = tabs
local membersTab = makeButton(tabs, "Members", "Members", COLORS.blueDark)
membersTab.Size = UDim2.fromOffset(130, 38)
local hireTab = makeButton(tabs, "Hire", "Nearby Hiring", COLORS.panelSoft)
hireTab.Size = UDim2.fromOffset(150, 38)
local wardrobeButton = makeButton(tabs, "Wardrobe", "Appearance", COLORS.panelSoft)
wardrobeButton.Size = UDim2.fromOffset(130, 38)
local refreshButton = makeButton(tabs, "Refresh", "Refresh", COLORS.panelSoft)
refreshButton.Size = UDim2.fromOffset(110, 38)

local content = Instance.new("Frame")
content.BackgroundTransparency = 1
content.Position = UDim2.fromOffset(24, 160)
content.Size = UDim2.new(1, -48, 1, -204)
content.Parent = shell

local statusLabel = makeLabel(shell, "Status", "", 12, COLORS.muted, Enum.Font.GothamMedium)
statusLabel.Position = UDim2.fromOffset(24, 584)
statusLabel.Size = UDim2.new(1, -48, 0, 20)
statusLabel.TextXAlignment = Enum.TextXAlignment.Center

local function makePage(name)
	local page = Instance.new("Frame")
	page.Name = name
	page.BackgroundTransparency = 1
	page.Size = UDim2.fromScale(1, 1)
	page.Visible = false
	page.Parent = content
	return page
end

local membersPage = makePage("MembersPage")
local hirePage = makePage("HirePage")

local memberListPanel = Instance.new("Frame")
memberListPanel.BackgroundColor3 = COLORS.panel
memberListPanel.BorderSizePixel = 0
memberListPanel.Size = UDim2.new(0.46, -7, 1, 0)
memberListPanel.Parent = membersPage
addCorner(memberListPanel, 9)
addStroke(memberListPanel, COLORS.strokeSoft, 0.2, 1)
local memberHeading = makeLabel(memberListPanel, "Heading", "ROSTER", 11, COLORS.muted, Enum.Font.GothamBold)
memberHeading.Position = UDim2.fromOffset(16, 12)
memberHeading.Size = UDim2.new(1, -32, 0, 20)
local memberList = Instance.new("ScrollingFrame")
memberList.Name = "MemberList"
memberList.BackgroundTransparency = 1
memberList.BorderSizePixel = 0
memberList.Position = UDim2.fromOffset(12, 42)
memberList.Size = UDim2.new(1, -24, 1, -54)
memberList.ScrollBarThickness = 4
memberList.ScrollBarImageColor3 = COLORS.stroke
memberList.AutomaticCanvasSize = Enum.AutomaticSize.Y
memberList.CanvasSize = UDim2.new()
memberList.Parent = memberListPanel
local memberLayout = Instance.new("UIListLayout")
memberLayout.Padding = UDim.new(0, 7)
memberLayout.Parent = memberList

local memberDetail = Instance.new("Frame")
memberDetail.BackgroundColor3 = COLORS.panel
memberDetail.BorderSizePixel = 0
memberDetail.Position = UDim2.new(0.46, 7, 0, 0)
memberDetail.Size = UDim2.new(0.54, -7, 1, 0)
memberDetail.Parent = membersPage
addCorner(memberDetail, 9)
addStroke(memberDetail, COLORS.strokeSoft, 0.2, 1)
local detailEyebrow = makeLabel(memberDetail, "Eyebrow", "SELECTED MEMBER", 11, COLORS.muted, Enum.Font.GothamBold)
detailEyebrow.Position = UDim2.fromOffset(20, 16)
detailEyebrow.Size = UDim2.new(1, -40, 0, 18)
local detailName = makeLabel(memberDetail, "Name", "Choose a roster member", 21, COLORS.text, Enum.Font.GothamBold)
detailName.Position = UDim2.fromOffset(20, 38)
detailName.Size = UDim2.new(1, -40, 0, 30)
local detailMeta =
	makeLabel(memberDetail, "Meta", "Grade controls appear here.", 12, COLORS.muted, Enum.Font.GothamMedium)
detailMeta.Position = UDim2.fromOffset(20, 70)
detailMeta.Size = UDim2.new(1, -40, 0, 20)
local gradeHeading = makeLabel(memberDetail, "GradeHeading", "ASSIGN GRADE", 11, COLORS.muted, Enum.Font.GothamBold)
gradeHeading.Position = UDim2.fromOffset(20, 112)
gradeHeading.Size = UDim2.new(1, -40, 0, 18)
local gradeList = Instance.new("ScrollingFrame")
gradeList.BackgroundTransparency = 1
gradeList.BorderSizePixel = 0
gradeList.Position = UDim2.fromOffset(20, 139)
gradeList.Size = UDim2.new(1, -40, 1, -211)
gradeList.AutomaticCanvasSize = Enum.AutomaticSize.Y
gradeList.CanvasSize = UDim2.new()
gradeList.ScrollBarThickness = 4
gradeList.ScrollBarImageColor3 = COLORS.stroke
gradeList.Parent = memberDetail
local gradeLayout = Instance.new("UIListLayout")
gradeLayout.Padding = UDim.new(0, 7)
gradeLayout.Parent = gradeList
local fireButton = makeButton(memberDetail, "Fire", "Remove Member", COLORS.red)
fireButton.Position = UDim2.new(0, 20, 1, -54)
fireButton.Size = UDim2.new(1, -40, 0, 38)

local hirePanel = Instance.new("Frame")
hirePanel.BackgroundColor3 = COLORS.panel
hirePanel.BorderSizePixel = 0
hirePanel.Size = UDim2.fromScale(1, 1)
hirePanel.Parent = hirePage
addCorner(hirePanel, 9)
addStroke(hirePanel, COLORS.strokeSoft, 0.2, 1)
local hireHeading = makeLabel(hirePanel, "Heading", "NEARBY CITIZENS", 11, COLORS.muted, Enum.Font.GothamBold)
hireHeading.Position = UDim2.fromOffset(18, 14)
hireHeading.Size = UDim2.new(1, -36, 0, 20)
local hireHint = makeLabel(
	hirePanel,
	"Hint",
	"Only loaded characters within the configured hiring distance appear.",
	12,
	COLORS.muted,
	Enum.Font.GothamMedium
)
hireHint.Position = UDim2.fromOffset(18, 35)
hireHint.Size = UDim2.new(1, -36, 0, 20)
local hireList = Instance.new("ScrollingFrame")
hireList.BackgroundTransparency = 1
hireList.BorderSizePixel = 0
hireList.Position = UDim2.fromOffset(14, 68)
hireList.Size = UDim2.new(1, -28, 1, -82)
hireList.AutomaticCanvasSize = Enum.AutomaticSize.Y
hireList.CanvasSize = UDim2.new()
hireList.ScrollBarThickness = 4
hireList.ScrollBarImageColor3 = COLORS.stroke
hireList.Parent = hirePanel
local hireLayout = Instance.new("UIListLayout")
hireLayout.Padding = UDim.new(0, 8)
hireLayout.Parent = hireList

local renderAll

local function setStatus(message, color)
	statusLabel.Text = tostring(message or "")
	statusLabel.TextColor3 = color or COLORS.muted
end

local function clearContainer(container, keepLayout)
	for _, child in ipairs(container:GetChildren()) do
		if child ~= keepLayout then
			child:Destroy()
		end
	end
end

local function selectedMember()
	for _, member in ipairs(snapshot and snapshot.members or {}) do
		if member.citizenId == selectedCitizenId then
			return member
		end
	end
	return nil
end

local function setBusy(value)
	busy = value
	refreshButton.Active = not value
	refreshButton.AutoButtonColor = not value
	refreshButton.BackgroundColor3 = value and COLORS.disabled or COLORS.panelSoft
end

local function performAction(action, payload)
	if busy then
		return
	end
	setBusy(true)
	payload = type(payload) == "table" and payload or {}
	payload.access = accessContext
	local ok, result = callRemote(Remotes.ManagementAction, action, payload)
	setBusy(false)
	if not ok then
		setStatus(result or "Action failed.", COLORS.red)
		return
	end
	snapshot = result.snapshot
	setStatus(result.message or "Action completed.", COLORS.green)
	if selectedCitizenId and not selectedMember() then
		selectedCitizenId = nil
	end
	renderAll()
end

local function renderTabs()
	membersPage.Visible = activeTab == "members"
	hirePage.Visible = activeTab == "hire"
	membersTab.BackgroundColor3 = activeTab == "members" and COLORS.blueDark or COLORS.panelSoft
	hireTab.BackgroundColor3 = activeTab == "hire" and COLORS.blueDark or COLORS.panelSoft
end

local function renderMembers()
	clearContainer(memberList, memberLayout)
	for _, member in ipairs(snapshot and snapshot.members or {}) do
		local button = makeButton(
			memberList,
			"Member_" .. member.citizenId,
			"",
			member.citizenId == selectedCitizenId and COLORS.blueDark or COLORS.panelSoft
		)
		button.Size = UDim2.new(1, -5, 0, 58)
		button.Text = ""
		local dot = Instance.new("Frame")
		dot.BackgroundColor3 = member.online and COLORS.green or COLORS.disabled
		dot.BorderSizePixel = 0
		dot.Position = UDim2.fromOffset(13, 14)
		dot.Size = UDim2.fromOffset(8, 8)
		dot.Parent = button
		addCorner(dot, 4)
		local name = makeLabel(button, "Name", member.name, 13, COLORS.text, Enum.Font.GothamBold)
		name.Position = UDim2.fromOffset(30, 7)
		name.Size = UDim2.new(1, -42, 0, 23)
		local meta = makeLabel(
			button,
			"Meta",
			("%s  |  %s"):format(member.gradeName, member.online and "Online" or "Offline"),
			11,
			COLORS.muted,
			Enum.Font.GothamMedium
		)
		meta.Position = UDim2.fromOffset(30, 30)
		meta.Size = UDim2.new(1, -42, 0, 18)
		button.Activated:Connect(function()
			selectedCitizenId = member.citizenId
			renderAll()
		end)
	end
	if #(snapshot and snapshot.members or {}) == 0 then
		local empty =
			makeLabel(memberList, "Empty", "No indexed members yet.", 13, COLORS.muted, Enum.Font.GothamMedium)
		empty.Size = UDim2.new(1, -5, 0, 45)
		empty.TextXAlignment = Enum.TextXAlignment.Center
	end
	local member = selectedMember()
	clearContainer(gradeList, gradeLayout)
	if not member then
		detailName.Text = "Choose a roster member"
		detailMeta.Text = "Grade controls appear here."
		fireButton.Visible = false
		return
	end
	detailName.Text = member.name
	detailMeta.Text = ("%s | %s | %s"):format(
		member.citizenId,
		member.gradeName,
		member.online and "Online" or "Offline"
	)
	fireButton.Visible = not member.isSelf
	for _, grade in ipairs(snapshot.grades or {}) do
		local label = ("Grade %d  -  %s%s"):format(grade.level, grade.name, grade.isboss and "  (Boss)" or "")
		local button = makeButton(
			gradeList,
			"Grade_" .. grade.level,
			label,
			grade.level == member.grade and COLORS.blueDark or COLORS.panelSoft
		)
		button.Size = UDim2.new(1, -5, 0, 38)
		button.Active = grade.canAssign and not member.isSelf and grade.level ~= member.grade
		button.AutoButtonColor = button.Active
		if not button.Active and grade.level ~= member.grade then
			button.BackgroundColor3 = COLORS.disabled
		end
		button.Activated:Connect(function()
			if button.Active then
				performAction("set_grade", { citizenId = member.citizenId, grade = grade.level })
			end
		end)
	end
end

local function renderHiring()
	clearContainer(hireList, hireLayout)
	for _, candidate in ipairs(snapshot and snapshot.nearby or {}) do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = COLORS.panelSoft
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, -5, 0, 66)
		row.Parent = hireList
		addCorner(row, 7)
		local name = makeLabel(row, "Name", candidate.name, 14, COLORS.text, Enum.Font.GothamBold)
		name.Position = UDim2.fromOffset(16, 9)
		name.Size = UDim2.new(1, -180, 0, 23)
		local meta = makeLabel(
			row,
			"Meta",
			("%s | %.1f studs | %s"):format(candidate.citizenId, candidate.distance, candidate.current),
			11,
			COLORS.muted,
			Enum.Font.GothamMedium
		)
		meta.Position = UDim2.fromOffset(16, 34)
		meta.Size = UDim2.new(1, -180, 0, 18)
		local hire = makeButton(
			row,
			"Hire",
			candidate.alreadyMember and "Already Member" or "Hire",
			candidate.alreadyMember and COLORS.disabled or COLORS.green
		)
		hire.AnchorPoint = Vector2.new(1, 0.5)
		hire.Position = UDim2.new(1, -13, 0.5, 0)
		hire.Size = UDim2.fromOffset(140, 38)
		hire.Active = not candidate.alreadyMember
		hire.AutoButtonColor = hire.Active
		hire.Activated:Connect(function()
			if hire.Active then
				performAction("hire", { userId = candidate.userId })
			end
		end)
	end
	if #(snapshot and snapshot.nearby or {}) == 0 then
		local empty =
			makeLabel(hireList, "Empty", "No nearby loaded citizens.", 14, COLORS.muted, Enum.Font.GothamMedium)
		empty.Size = UDim2.new(1, -5, 0, 60)
		empty.TextXAlignment = Enum.TextXAlignment.Center
	end
end

renderAll = function()
	if not snapshot then
		return
	end
	titleLabel.Text = snapshot.organization.label .. " Management"
	subtitleLabel.Text = ("%s office | %s"):format(
		snapshot.organization.type == "crew" and "Crew" or "Job",
		snapshot.organization.gradeName
	)
	renderTabs()
	renderMembers()
	renderHiring()
end

local function fetchSnapshot(showLoading)
	if busy then
		return
	end
	setBusy(true)
	if showLoading then
		setStatus("Loading management data...", COLORS.muted)
	end
	local result, err = callRemote(Remotes.GetManagement, accessContext)
	setBusy(false)
	if not result then
		setStatus(err or "Management data is unavailable.", COLORS.red)
		return false
	end
	snapshot = result
	if selectedCitizenId and not selectedMember() then
		selectedCitizenId = nil
	end
	setStatus("", COLORS.muted)
	renderAll()
	return true
end

local function closeManagement(force)
	if busy and not force then
		return
	end
	isOpen = false
	screenGui.Enabled = false
	snapshot = nil
	selectedCitizenId = nil
	GuiService.SelectedObject = nil
end

local function openManagement(access)
	accessContext = type(access) == "table" and access or { locationId = "" }
	isOpen = true
	activeTab = "members"
	screenGui.Enabled = true
	fetchSnapshot(true)
end

membersTab.Activated:Connect(function()
	activeTab = "members"
	renderAll()
end)
hireTab.Activated:Connect(function()
	activeTab = "hire"
	renderAll()
end)
wardrobeButton.Activated:Connect(function()
	if busy then
		return
	end
	setBusy(true)
	local ok, opened, err =
		pcall(Remotes.OpenManagementWardrobe.InvokeServer, Remotes.OpenManagementWardrobe, accessContext)
	setBusy(false)
	if not ok or not opened then
		setStatus(err or "The wardrobe could not be opened.", COLORS.red)
		return
	end
	closeManagement(true)
end)
refreshButton.Activated:Connect(function()
	fetchSnapshot(false)
end)
closeButton.Activated:Connect(closeManagement)
fireButton.Activated:Connect(function()
	local member = selectedMember()
	if member and not member.isSelf then
		performAction("fire", { citizenId = member.citizenId })
	end
end)
Remotes.OpenManagement.OnClientEvent:Connect(openManagement)

UserInputService.InputBegan:Connect(function(input, processed)
	if not isOpen or processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
		closeManagement()
	end
end)

local function updateScale()
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	shellScale.Scale = math.min(1, viewport.X / 950, viewport.Y / 670)
end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateScale)
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end
updateScale()
QBCoreClient.OnPlayerLoaded.Event:Connect(function()
	if isOpen then
		closeManagement(true)
	end
end)
