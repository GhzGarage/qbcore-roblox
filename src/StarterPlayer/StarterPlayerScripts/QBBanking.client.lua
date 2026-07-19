-- Native Roblox banking UI. The server owns proximity checks, balances, transfers,
-- and statements; this client only renders snapshots and submits requests.

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
	input = Color3.fromRGB(19, 24, 31),
	stroke = Color3.fromRGB(73, 87, 104),
	strokeSoft = Color3.fromRGB(57, 69, 84),
	text = Color3.fromRGB(240, 244, 248),
	muted = Color3.fromRGB(157, 170, 184),
	green = Color3.fromRGB(65, 172, 110),
	greenDark = Color3.fromRGB(43, 125, 79),
	blue = Color3.fromRGB(74, 143, 216),
	blueDark = Color3.fromRGB(48, 99, 157),
	gold = Color3.fromRGB(229, 181, 77),
	red = Color3.fromRGB(202, 79, 83),
	disabled = Color3.fromRGB(79, 89, 101),
}

local ACTIONS = {
	deposit = {
		title = "Deposit cash",
		hint = "Move cash on hand into your checking account.",
		button = "Deposit funds",
		color = COLORS.green,
	},
	withdraw = {
		title = "Withdraw cash",
		hint = "Move money from checking into cash on hand.",
		button = "Withdraw funds",
		color = COLORS.blue,
	},
	transfer = {
		title = "Citizen transfer",
		hint = "Send funds by citizen ID. Offline recipients receive them on next login.",
		button = "Send transfer",
		color = COLORS.gold,
	},
	card = {
		title = "Issue bank card",
		hint = "Create a unique ATM card protected by your 4-digit PIN.",
		button = "Issue card",
		color = COLORS.green,
	},
	manage = {
		title = "Shared accounts",
		hint = "Open a player-shared account or manage one that you own.",
		button = "Open shared account",
		color = COLORS.green,
	},
}

local snapshot = nil
local currentAction = "deposit"
local selectedAccountId = "checking"
local accessContext = { mode = "bank", locationId = "" }
local isOpen = false
local busy = false
local refreshQueued = false
local renderedManageAccountId = nil
local submitIdleText = ACTIONS.deposit.button
local deleteConfirmAccountId = nil

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
	label.BorderSizePixel = 0
	label.Font = font or Enum.Font.Gotham
	label.Text = text or ""
	label.TextColor3 = color or COLORS.text
	label.TextSize = size or 14
	label.TextWrapped = false
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
	button.Selectable = true
	button.Text = text or "Button"
	button.TextColor3 = COLORS.text
	button.TextSize = 14
	button.TextWrapped = false
	button.Parent = parent
	addCorner(button, 7)
	return button
end

local function makeTextBox(parent, name, placeholder)
	local box = Instance.new("TextBox")
	box.Name = name
	box.BackgroundColor3 = COLORS.input
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Gotham
	box.PlaceholderColor3 = COLORS.muted
	box.PlaceholderText = placeholder or ""
	box.Text = ""
	box.TextColor3 = COLORS.text
	box.TextSize = 15
	box.TextTruncate = Enum.TextTruncate.AtEnd
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = parent
	addCorner(box, 7)
	addStroke(box, COLORS.strokeSoft, 0.15, 1)
	addPadding(box, 12, 0, 12, 0)
	return box
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

local function formatDate(timestamp)
	local value = tonumber(timestamp)
	if not value or value <= 0 then
		return "Just now"
	end
	return os.date("%m/%d/%Y  %H:%M", value)
end

local function callRemote(remote, ...)
	local results = table.pack(pcall(remote.InvokeServer, remote, ...))
	if not results[1] then
		warn("[QBBanking] Remote call failed: " .. tostring(results[2]))
		return nil, "The bank server did not respond."
	end
	return table.unpack(results, 2, results.n)
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QBBanking"
screenGui.DisplayOrder = 55
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.BackgroundColor3 = COLORS.page
overlay.BackgroundTransparency = 0.12
overlay.BorderSizePixel = 0
overlay.Active = true
overlay.Size = UDim2.fromScale(1, 1)
overlay.Parent = screenGui

local shell = Instance.new("Frame")
shell.Name = "Shell"
shell.AnchorPoint = Vector2.new(0.5, 0.5)
shell.BackgroundColor3 = COLORS.shell
shell.BorderSizePixel = 0
shell.Position = UDim2.fromScale(0.5, 0.5)
shell.Size = UDim2.fromOffset(920, 600)
shell.Parent = overlay
addCorner(shell, 10)
addStroke(shell, COLORS.stroke, 0.12, 1)

local shellScale = Instance.new("UIScale")
shellScale.Parent = shell

local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundTransparency = 1
header.Position = UDim2.fromOffset(24, 18)
header.Size = UDim2.new(1, -48, 0, 62)
header.Parent = shell

local eyebrow = makeLabel(header, "Eyebrow", "QBCORE FINANCIAL", 11, COLORS.green, Enum.Font.GothamBold)
eyebrow.Size = UDim2.new(1, -58, 0, 16)

local titleLabel = makeLabel(header, "Title", "Banking", 25, COLORS.text, Enum.Font.GothamBold)
titleLabel.Position = UDim2.fromOffset(0, 15)
titleLabel.Size = UDim2.new(0.58, 0, 0, 30)

local accountLabel = makeLabel(header, "Account", "", 12, COLORS.muted, Enum.Font.GothamMedium)
accountLabel.Position = UDim2.fromOffset(0, 43)
accountLabel.Size = UDim2.new(0.75, 0, 0, 19)

local closeButton = makeButton(header, "Close", "×", COLORS.panelSoft)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, 0, 0, 2)
closeButton.Size = UDim2.fromOffset(42, 42)
closeButton.TextSize = 24

local divider = Instance.new("Frame")
divider.Name = "Divider"
divider.BackgroundColor3 = COLORS.strokeSoft
divider.BackgroundTransparency = 0.25
divider.BorderSizePixel = 0
divider.Position = UDim2.fromOffset(24, 91)
divider.Size = UDim2.new(1, -48, 0, 1)
divider.Parent = shell

local body = Instance.new("Frame")
body.Name = "Body"
body.BackgroundTransparency = 1
body.Position = UDim2.fromOffset(24, 108)
body.Size = UDim2.new(1, -48, 1, -132)
body.Parent = shell

local leftColumn = Instance.new("Frame")
leftColumn.Name = "AccountColumn"
leftColumn.BackgroundTransparency = 1
leftColumn.Size = UDim2.new(0.62, -8, 1, 0)
leftColumn.Parent = body

local rightColumn = Instance.new("Frame")
rightColumn.Name = "ActionColumn"
rightColumn.BackgroundColor3 = COLORS.panel
rightColumn.BorderSizePixel = 0
rightColumn.Position = UDim2.new(0.62, 8, 0, 0)
rightColumn.Size = UDim2.new(0.38, -8, 1, 0)
rightColumn.Parent = body
addCorner(rightColumn, 9)
addStroke(rightColumn, COLORS.strokeSoft, 0.2, 1)
addPadding(rightColumn, 18, 18, 18, 18)

local balanceRow = Instance.new("Frame")
balanceRow.Name = "Balances"
balanceRow.BackgroundTransparency = 1
balanceRow.Size = UDim2.new(1, 0, 0, 112)
balanceRow.Parent = leftColumn

local checkingCard = Instance.new("Frame")
checkingCard.Name = "CheckingCard"
checkingCard.BackgroundColor3 = COLORS.blueDark
checkingCard.BorderSizePixel = 0
checkingCard.Size = UDim2.new(0.62, -7, 1, 0)
checkingCard.Parent = balanceRow
addCorner(checkingCard, 9)
addStroke(checkingCard, COLORS.blue, 0.38, 1)
addPadding(checkingCard, 17, 14, 17, 14)

local checkingTitle =
	makeLabel(checkingCard, "Title", "CHECKING BALANCE", 11, Color3.fromRGB(190, 217, 245), Enum.Font.GothamBold)
checkingTitle.Size = UDim2.new(1, 0, 0, 18)

local checkingBalance = makeLabel(checkingCard, "Balance", "$0", 30, COLORS.text, Enum.Font.GothamBold)
checkingBalance.Position = UDim2.fromOffset(0, 27)
checkingBalance.Size = UDim2.new(1, 0, 0, 38)

local checkingCaption = makeLabel(
	checkingCard,
	"Caption",
	"Available immediately",
	12,
	Color3.fromRGB(196, 214, 234),
	Enum.Font.GothamMedium
)
checkingCaption.Position = UDim2.fromOffset(0, 70)
checkingCaption.Size = UDim2.new(1, 0, 0, 18)

local cashCard = Instance.new("Frame")
cashCard.Name = "CashCard"
cashCard.BackgroundColor3 = COLORS.panel
cashCard.BorderSizePixel = 0
cashCard.Position = UDim2.new(0.62, 7, 0, 0)
cashCard.Size = UDim2.new(0.38, -7, 1, 0)
cashCard.Parent = balanceRow
addCorner(cashCard, 9)
addStroke(cashCard, COLORS.strokeSoft, 0.2, 1)
addPadding(cashCard, 16, 14, 16, 14)

local cashTitle = makeLabel(cashCard, "Title", "CASH ON HAND", 11, COLORS.muted, Enum.Font.GothamBold)
cashTitle.Size = UDim2.new(1, 0, 0, 18)

local cashBalance = makeLabel(cashCard, "Balance", "$0", 24, COLORS.green, Enum.Font.GothamBold)
cashBalance.Position = UDim2.fromOffset(0, 29)
cashBalance.Size = UDim2.new(1, 0, 0, 34)

local cashCaption = makeLabel(cashCard, "Caption", "Depositable funds", 11, COLORS.muted, Enum.Font.GothamMedium)
cashCaption.Position = UDim2.fromOffset(0, 71)
cashCaption.Size = UDim2.new(1, 0, 0, 18)

local accountSelector = Instance.new("ScrollingFrame")
accountSelector.Name = "AccountSelector"
accountSelector.BackgroundTransparency = 1
accountSelector.BorderSizePixel = 0
accountSelector.Position = UDim2.fromOffset(0, 122)
accountSelector.Size = UDim2.new(1, 0, 0, 34)
accountSelector.AutomaticCanvasSize = Enum.AutomaticSize.X
accountSelector.CanvasSize = UDim2.fromOffset(0, 0)
accountSelector.ScrollingDirection = Enum.ScrollingDirection.X
accountSelector.ScrollBarImageColor3 = COLORS.stroke
accountSelector.ScrollBarThickness = 3
accountSelector.Parent = leftColumn

local accountSelectorLayout = Instance.new("UIListLayout")
accountSelectorLayout.FillDirection = Enum.FillDirection.Horizontal
accountSelectorLayout.SortOrder = Enum.SortOrder.LayoutOrder
accountSelectorLayout.Padding = UDim.new(0, 8)
accountSelectorLayout.Parent = accountSelector

local accountButtons = {}

local historyHeader = Instance.new("Frame")
historyHeader.Name = "HistoryHeader"
historyHeader.BackgroundTransparency = 1
historyHeader.Position = UDim2.fromOffset(0, 168)
historyHeader.Size = UDim2.new(1, 0, 0, 30)
historyHeader.Parent = leftColumn

local historyTitle = makeLabel(historyHeader, "Title", "Recent activity", 17, COLORS.text, Enum.Font.GothamBold)
historyTitle.Size = UDim2.new(0.58, 0, 1, 0)

local historyCount = makeLabel(historyHeader, "Count", "0 statements", 12, COLORS.muted, Enum.Font.GothamMedium)
historyCount.AnchorPoint = Vector2.new(1, 0)
historyCount.Position = UDim2.new(1, 0, 0, 0)
historyCount.Size = UDim2.new(0.42, 0, 1, 0)
historyCount.TextXAlignment = Enum.TextXAlignment.Right

local history = Instance.new("ScrollingFrame")
history.Name = "StatementHistory"
history.BackgroundColor3 = COLORS.panel
history.BorderSizePixel = 0
history.Position = UDim2.fromOffset(0, 204)
history.Size = UDim2.new(1, 0, 1, -204)
history.AutomaticCanvasSize = Enum.AutomaticSize.Y
history.CanvasSize = UDim2.fromOffset(0, 0)
history.ScrollBarImageColor3 = COLORS.stroke
history.ScrollBarThickness = 5
history.Parent = leftColumn
addCorner(history, 9)
addStroke(history, COLORS.strokeSoft, 0.22, 1)
addPadding(history, 12, 12, 12, 12)

local historyLayout = Instance.new("UIListLayout")
historyLayout.FillDirection = Enum.FillDirection.Vertical
historyLayout.SortOrder = Enum.SortOrder.LayoutOrder
historyLayout.Padding = UDim.new(0, 7)
historyLayout.Parent = history

local actionTabs = Instance.new("Frame")
actionTabs.Name = "Tabs"
actionTabs.BackgroundTransparency = 1
actionTabs.Size = UDim2.new(1, 0, 0, 38)
actionTabs.Parent = rightColumn

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Padding = UDim.new(0, 6)
tabLayout.Parent = actionTabs

local tabButtons = {}
for order, actionName in ipairs({ "deposit", "withdraw", "transfer", "card", "manage" }) do
	local button = makeButton(
		actionTabs,
		"Tab_" .. actionName,
		actionName == "manage" and "Accounts" or (actionName:sub(1, 1):upper() .. actionName:sub(2)),
		COLORS.panelSoft
	)
	button.LayoutOrder = order
	button.Size = UDim2.new(1 / 5, -5, 1, 0)
	button.TextSize = 12
	tabButtons[actionName] = button
end

local actionTitle = makeLabel(rightColumn, "ActionTitle", "Deposit cash", 20, COLORS.text, Enum.Font.GothamBold)
actionTitle.Position = UDim2.fromOffset(0, 55)
actionTitle.Size = UDim2.new(1, 0, 0, 28)

local actionHint = makeLabel(rightColumn, "ActionHint", "", 12, COLORS.muted, Enum.Font.Gotham)
actionHint.Position = UDim2.fromOffset(0, 84)
actionHint.Size = UDim2.new(1, 0, 0, 38)
actionHint.TextWrapped = true
actionHint.TextYAlignment = Enum.TextYAlignment.Top

local amountLabel = makeLabel(rightColumn, "AmountLabel", "AMOUNT", 11, COLORS.muted, Enum.Font.GothamBold)
amountLabel.Position = UDim2.fromOffset(0, 126)
amountLabel.Size = UDim2.new(1, 0, 0, 18)

local amountBox = makeTextBox(rightColumn, "Amount", "Whole dollars")
amountBox.Position = UDim2.fromOffset(0, 147)
amountBox.Size = UDim2.new(1, 0, 0, 42)

local recipientLabel =
	makeLabel(rightColumn, "RecipientLabel", "RECIPIENT CITIZEN ID", 11, COLORS.muted, Enum.Font.GothamBold)
recipientLabel.Position = UDim2.fromOffset(0, 201)
recipientLabel.Size = UDim2.new(1, 0, 0, 18)

local recipientBox = makeTextBox(rightColumn, "Recipient", "Example: ABC12345")
recipientBox.Position = UDim2.fromOffset(0, 222)
recipientBox.Size = UDim2.new(1, 0, 0, 42)

local reasonLabel = makeLabel(rightColumn, "ReasonLabel", "MEMO", 11, COLORS.muted, Enum.Font.GothamBold)
reasonLabel.Size = UDim2.new(1, 0, 0, 18)

local reasonBox = makeTextBox(rightColumn, "Reason", "Optional transaction memo")
reasonBox.Size = UDim2.new(1, 0, 0, 42)

local submitButton = makeButton(rightColumn, "Submit", "Deposit funds", COLORS.green)
submitButton.Size = UDim2.new(1, 0, 0, 44)

local addMemberButton = makeButton(rightColumn, "AddMember", "Add member", COLORS.blueDark)
addMemberButton.Size = UDim2.new(0.5, -4, 0, 40)
addMemberButton.Visible = false

local removeMemberButton = makeButton(rightColumn, "RemoveMember", "Remove member", COLORS.panelSoft)
removeMemberButton.Position = UDim2.new(0.5, 4, 0, 0)
removeMemberButton.Size = UDim2.new(0.5, -4, 0, 40)
removeMemberButton.Visible = false

local deleteAccountButton = makeButton(rightColumn, "DeleteAccount", "Close empty account", COLORS.red)
deleteAccountButton.Size = UDim2.new(1, 0, 0, 40)
deleteAccountButton.Visible = false

local statusLabel = makeLabel(rightColumn, "Status", "", 12, COLORS.muted, Enum.Font.GothamMedium)
statusLabel.Size = UDim2.new(1, 0, 0, 18)
statusLabel.TextWrapped = true
statusLabel.TextXAlignment = Enum.TextXAlignment.Center
statusLabel.TextYAlignment = Enum.TextYAlignment.Top

local limitLabel = makeLabel(rightColumn, "Limit", "", 10, COLORS.muted, Enum.Font.GothamMedium)
limitLabel.AnchorPoint = Vector2.new(0, 1)
limitLabel.Position = UDim2.new(0, 0, 1, 0)
limitLabel.Size = UDim2.new(1, 0, 0, 17)
limitLabel.TextXAlignment = Enum.TextXAlignment.Center

local pinGate = Instance.new("Frame")
pinGate.Name = "PinGate"
pinGate.AnchorPoint = Vector2.new(0.5, 0.5)
pinGate.BackgroundColor3 = COLORS.panel
pinGate.BorderSizePixel = 0
pinGate.Position = UDim2.fromScale(0.5, 0.53)
pinGate.Size = UDim2.fromOffset(390, 230)
pinGate.Visible = false
pinGate.ZIndex = 20
pinGate.Parent = shell
addCorner(pinGate, 10)
addStroke(pinGate, COLORS.stroke, 0.05, 1)

local pinTitle = makeLabel(pinGate, "Title", "ATM card verification", 21, COLORS.text, Enum.Font.GothamBold)
pinTitle.Position = UDim2.fromOffset(24, 20)
pinTitle.Size = UDim2.new(1, -48, 0, 30)
pinTitle.ZIndex = 21

local pinHint = makeLabel(
	pinGate,
	"Hint",
	"Enter the 4-digit PIN for a bank card in your inventory.",
	12,
	COLORS.muted,
	Enum.Font.Gotham
)
pinHint.Position = UDim2.fromOffset(24, 54)
pinHint.Size = UDim2.new(1, -48, 0, 38)
pinHint.TextWrapped = true
pinHint.ZIndex = 21

local pinBox = makeTextBox(pinGate, "Pin", "4-digit PIN")
pinBox.Position = UDim2.fromOffset(24, 100)
pinBox.Size = UDim2.new(1, -48, 0, 42)
pinBox.ZIndex = 21

local pinButton = makeButton(pinGate, "Verify", "Access ATM", COLORS.green)
pinButton.Position = UDim2.fromOffset(24, 154)
pinButton.Size = UDim2.new(1, -48, 0, 42)
pinButton.ZIndex = 21

local pinStatus = makeLabel(pinGate, "Status", "", 11, COLORS.red, Enum.Font.GothamMedium)
pinStatus.Position = UDim2.fromOffset(24, 200)
pinStatus.Size = UDim2.new(1, -48, 0, 20)
pinStatus.TextXAlignment = Enum.TextXAlignment.Center
pinStatus.ZIndex = 21

local function setStatus(text, color)
	statusLabel.Text = text or ""
	statusLabel.TextColor3 = color or COLORS.muted
end

local function setBusy(nextBusy)
	busy = nextBusy
	for _, button in pairs(tabButtons) do
		button.Active = not busy
		button.AutoButtonColor = not busy
	end
	for _, button in ipairs(accountButtons) do
		button.Active = not busy
		button.AutoButtonColor = not busy
	end
	closeButton.Active = not busy
	closeButton.AutoButtonColor = not busy
	for _, button in ipairs({ submitButton, addMemberButton, removeMemberButton, deleteAccountButton }) do
		button.Active = not busy
		button.AutoButtonColor = not busy
	end
	amountBox.TextEditable = not busy
	recipientBox.TextEditable = not busy
	reasonBox.TextEditable = not busy
	submitButton.Text = busy and "Processing..." or submitIdleText
	submitButton.BackgroundColor3 = busy and COLORS.disabled or ACTIONS[currentAction].color
end

local function clearStatements()
	for _, child in ipairs(history:GetChildren()) do
		if
			not child:IsA("UIListLayout")
			and not child:IsA("UIPadding")
			and not child:IsA("UICorner")
			and not child:IsA("UIStroke")
		then
			child:Destroy()
		end
	end
end

local function statementPresentation(kind)
	if kind == "deposit" then
		return "Deposit", "+", COLORS.green
	elseif kind == "withdraw" then
		return "Withdrawal", "−", COLORS.red
	elseif kind == "transfer_in" then
		return "Transfer received", "+", COLORS.green
	elseif kind == "transfer_out" then
		return "Transfer sent", "−", COLORS.gold
	elseif kind == "paycheck" then
		return "Employee paycheck", "−", COLORS.gold
	elseif kind == "card" then
		return "Bank card", "−", COLORS.gold
	elseif kind == "refund" then
		return "Reversal", "+", COLORS.green
	end
	return "Transaction", "", COLORS.text
end

local function selectedAccount()
	for _, account in ipairs(snapshot and snapshot.accounts or {}) do
		if account.id == selectedAccountId then
			return account
		end
	end
	selectedAccountId = "checking"
	return snapshot and snapshot.account or {}
end

local function renderStatements()
	clearStatements()
	local account = selectedAccount()
	if currentAction == "manage" and account.type == "shared" and account.isOwner == true then
		local members = account.members or {}
		historyTitle.Text = "Account members"
		historyCount.Text = ("%d participant%s"):format(#members, #members == 1 and "" or "s")
		for index, member in ipairs(members) do
			local row = makeButton(
				history,
				"SharedMember_" .. tostring(member.citizenId or index),
				("%s  |  %s%s"):format(
					tostring(member.name or "Citizen"),
					tostring(member.citizenId or "-"),
					member.isOwner and "  |  OWNER" or ""
				),
				member.isOwner and COLORS.blueDark or COLORS.panelSoft
			)
			row.LayoutOrder = index
			row.Size = UDim2.new(1, 0, 0, 46)
			row.TextSize = 12
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextTruncate = Enum.TextTruncate.AtEnd
			addPadding(row, 12, 0, 12, 0)
			row.Active = not member.isOwner
			row.AutoButtonColor = row.Active
			row.Activated:Connect(function()
				if row.Active and not busy then
					recipientBox.Text = tostring(member.citizenId or "")
					setStatus("Member selected. Choose Remove member to revoke access.", COLORS.muted)
				end
			end)
		end
		return
	end
	historyTitle.Text = "Recent activity"
	local statements = account.statements or (snapshot and snapshot.statements) or {}
	historyCount.Text = ("%d statement%s"):format(#statements, #statements == 1 and "" or "s")

	if #statements == 0 then
		local empty = makeLabel(
			history,
			"Empty",
			"No banking activity yet. Your deposits, withdrawals, and transfers will appear here.",
			13,
			COLORS.muted,
			Enum.Font.Gotham
		)
		empty.Size = UDim2.new(1, 0, 0, 72)
		empty.TextWrapped = true
		empty.TextXAlignment = Enum.TextXAlignment.Center
		return
	end

	for index, entry in ipairs(statements) do
		local title, sign, tint = statementPresentation(entry.kind)
		local row = Instance.new("Frame")
		row.Name = "Statement_" .. tostring(entry.id or index)
		row.BackgroundColor3 = COLORS.panelSoft
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, 66)
		row.Parent = history
		addCorner(row, 7)
		addStroke(row, COLORS.strokeSoft, 0.42, 1)

		local marker = Instance.new("Frame")
		marker.Name = "Marker"
		marker.BackgroundColor3 = tint
		marker.BorderSizePixel = 0
		marker.Position = UDim2.fromOffset(0, 9)
		marker.Size = UDim2.fromOffset(3, 48)
		marker.Parent = row
		addCorner(marker, 2)

		local rowTitle = makeLabel(row, "Title", title, 13, COLORS.text, Enum.Font.GothamBold)
		rowTitle.Position = UDim2.fromOffset(13, 7)
		rowTitle.Size = UDim2.new(0.52, -13, 0, 20)

		local reason = tostring(entry.reason or "Bank transaction")
		if entry.counterparty and entry.counterparty ~= "" then
			reason = reason .. " · " .. tostring(entry.counterparty)
		end
		local rowReason = makeLabel(row, "Reason", reason, 11, COLORS.muted, Enum.Font.Gotham)
		rowReason.Position = UDim2.fromOffset(13, 27)
		rowReason.Size = UDim2.new(0.64, -13, 0, 17)

		local rowDate = makeLabel(row, "Date", formatDate(entry.time), 10, COLORS.muted, Enum.Font.GothamMedium)
		rowDate.Position = UDim2.fromOffset(13, 45)
		rowDate.Size = UDim2.new(0.62, -13, 0, 14)

		local rowAmount = makeLabel(row, "Amount", sign .. formatMoney(entry.amount), 15, tint, Enum.Font.GothamBold)
		rowAmount.AnchorPoint = Vector2.new(1, 0)
		rowAmount.Position = UDim2.new(1, -12, 0, 10)
		rowAmount.Size = UDim2.new(0.38, 0, 0, 22)
		rowAmount.TextXAlignment = Enum.TextXAlignment.Right

		local rowBalance = makeLabel(
			row,
			"Balance",
			"Balance " .. formatMoney(entry.balance),
			10,
			COLORS.muted,
			Enum.Font.GothamMedium
		)
		rowBalance.AnchorPoint = Vector2.new(1, 0)
		rowBalance.Position = UDim2.new(1, -12, 0, 37)
		rowBalance.Size = UDim2.new(0.38, 0, 0, 18)
		rowBalance.TextXAlignment = Enum.TextXAlignment.Right
	end
end

local render

local function renderBalances()
	local account = selectedAccount()
	checkingBalance.Text = formatMoney(account.balance)
	cashBalance.Text = formatMoney((snapshot and snapshot.account and snapshot.account.cash) or account.cash)
	cashCaption.Text = accessContext.mode == "atm" and "Deposit at a bank" or "Depositable funds"
	checkingTitle.Text = string.upper(tostring(account.name or "Checking")) .. " BALANCE"
	if account.type == "society" then
		checkingCaption.Text = "Boss-managed job funds"
	elseif account.type == "crew" then
		checkingCaption.Text = "Boss-managed crew funds"
	elseif account.type == "shared" then
		checkingCaption.Text = account.isOwner and "Player-shared account | Owner" or "Player-shared account | Member"
	else
		checkingCaption.Text = "Available immediately"
	end
	local location = snapshot and snapshot.location or {}
	titleLabel.Text = tostring(location.label or "Banking")
	accountLabel.Text = ("%s  ·  %s"):format(
		tostring(account.holder or player.DisplayName),
		account.type == "society" and ("Job " .. tostring(account.citizenId or "—"))
			or ("Citizen ID " .. tostring(account.citizenId or "—"))
	)
	if account.type == "crew" then
		accountLabel.Text = ("%s | Crew %s"):format(tostring(account.holder or player.DisplayName), tostring(account.citizenId or "-"))
	elseif account.type == "shared" then
		accountLabel.Text = ("%s | Shared #%s"):format(
			tostring(account.holder or player.DisplayName),
			tostring(account.accountNumber or "-")
		)
	end
	for _, button in ipairs(accountButtons) do
		button:Destroy()
	end
	table.clear(accountButtons)
	local accounts = snapshot and snapshot.accounts or {}
	for index, candidate in ipairs(accounts) do
		local button = makeButton(
			accountSelector,
			"Account_" .. tostring(index),
			tostring(candidate.name or "Account"),
			candidate.id == selectedAccountId and COLORS.blueDark or COLORS.panelSoft
		)
		button.LayoutOrder = index
		button.Size = #accounts == 2 and UDim2.new(0.5, -4, 1, -3) or UDim2.fromOffset(145, 31)
		button.TextSize = 12
		button.TextTruncate = Enum.TextTruncate.AtEnd
		button.Activated:Connect(function()
			if busy or not snapshot then
				return
			end
			selectedAccountId = candidate.id
			renderedManageAccountId = nil
			deleteConfirmAccountId = nil
			setStatus("")
			render()
		end)
		table.insert(accountButtons, button)
	end
	local showSelector = #accounts > 1
	accountSelector.Visible = showSelector
	historyHeader.Position = UDim2.fromOffset(0, showSelector and 168 or 122)
	history.Position = UDim2.fromOffset(0, showSelector and 204 or 158)
	history.Size = UDim2.new(1, 0, 1, showSelector and -204 or -158)
	local limits = snapshot and snapshot.limits or {}
	if accessContext.mode == "atm" and limits.useDailyWithdrawalLimit then
		limitLabel.Text = ("ATM today: %s / %s"):format(
			formatMoney(limits.dailyWithdrawn or 0),
			formatMoney(limits.dailyWithdrawalLimit or 0)
		)
	else
		limitLabel.Text = "Per-transaction limit: " .. formatMoney(limits.maxTransactionAmount or 0)
	end
end

local function renderAction()
	if accessContext.mode == "atm" and (currentAction == "deposit" or currentAction == "card" or currentAction == "manage") then
		currentAction = "withdraw"
	end
	local info = ACTIONS[currentAction]
	local account = selectedAccount()
	actionTitle.Text = info.title
	actionHint.Text = info.hint
	submitIdleText = info.button
	if currentAction == "card" and snapshot and snapshot.limits then
		actionHint.Text = info.hint .. " Issuance fee: " .. formatMoney(snapshot.limits.cardPrice or 0) .. "."
	elseif currentAction == "deposit" then
		actionHint.Text = "Move cash on hand into " .. tostring(account.name or "this account") .. "."
	elseif currentAction == "withdraw" then
		actionHint.Text = "Move money from " .. tostring(account.name or "this account") .. " into cash on hand."
	elseif currentAction == "transfer" then
		actionHint.Text = "Send funds from " .. tostring(account.name or "this account") .. " by citizen ID."
	end
	for actionName, button in pairs(tabButtons) do
		button.Visible = not (
			accessContext.mode == "atm" and (actionName == "deposit" or actionName == "card" or actionName == "manage")
		)
		button.Size = accessContext.mode == "atm" and UDim2.new(1 / 2, -3, 1, 0) or UDim2.new(1 / 5, -5, 1, 0)
		button.BackgroundColor3 = actionName == currentAction and COLORS.blueDark or COLORS.panelSoft
		button.TextColor3 = actionName == currentAction and COLORS.text or COLORS.muted
	end

	local transfer = currentAction == "transfer"
	local card = currentAction == "card"
	local manage = currentAction == "manage"
	local ownsShared = manage and account.type == "shared" and account.isOwner == true
	addMemberButton.Visible = ownsShared
	removeMemberButton.Visible = ownsShared
	deleteAccountButton.Visible = ownsShared
	amountLabel.Visible = not card
	amountBox.Visible = not card
	recipientLabel.Visible = transfer or card or manage
	recipientBox.Visible = transfer or card or manage
	reasonLabel.Visible = not card and not manage
	reasonBox.Visible = not card and not manage
	recipientLabel.Text = card and "4-DIGIT PIN" or "RECIPIENT CITIZEN ID"
	recipientBox.PlaceholderText = card and "Choose a 4-digit PIN" or "Example: ABC12345"
	amountLabel.Text = "AMOUNT"
	amountBox.PlaceholderText = "Whole dollars"
	if manage then
		if renderedManageAccountId ~= account.id then
			renderedManageAccountId = account.id
			amountBox.Text = ownsShared and tostring(account.name or "") or ""
			recipientBox.Text = ""
		end
		amountLabel.Text = ownsShared and "ACCOUNT NAME" or "NEW SHARED ACCOUNT NAME"
		amountBox.PlaceholderText = ownsShared and "Shared account name" or "Example: Household"
		recipientLabel.Text = ownsShared and "MEMBER CITIZEN ID" or "INITIAL DEPOSIT"
		recipientBox.PlaceholderText = ownsShared and "Example: ABC12345" or "0"
		if ownsShared then
			local memberCount = #(account.members or {})
			actionTitle.Text = "Manage " .. tostring(account.name or "shared account")
			actionHint.Text = ("Owner controls | %d member%s | Shared #%s"):format(
				memberCount,
				memberCount == 1 and "" or "s",
				tostring(account.accountNumber or "-")
			)
			submitIdleText = "Rename account"
			addMemberButton.Position = UDim2.fromOffset(0, 276)
			removeMemberButton.Position = UDim2.new(0.5, 4, 0, 276)
			submitButton.Position = UDim2.fromOffset(0, 326)
			deleteAccountButton.Position = UDim2.fromOffset(0, 380)
			deleteAccountButton.Text = deleteConfirmAccountId == account.id and "Confirm close account" or "Close empty account"
			statusLabel.Position = UDim2.fromOffset(0, 426)
		else
			local maximum = snapshot and snapshot.limits and snapshot.limits.maxSharedAccounts or 2
			actionHint.Text = ("Open a player-shared account and invite members after creation. You may own up to %d."):format(maximum)
			submitIdleText = "Open shared account"
			submitButton.Position = UDim2.fromOffset(0, 276)
			statusLabel.Position = UDim2.fromOffset(0, 323)
		end
	elseif transfer then
		reasonLabel.Position = UDim2.fromOffset(0, 276)
		reasonBox.Position = UDim2.fromOffset(0, 297)
		submitButton.Position = UDim2.fromOffset(0, 351)
		statusLabel.Position = UDim2.fromOffset(0, 396)
	elseif card then
		recipientLabel.Position = UDim2.fromOffset(0, 126)
		recipientBox.Position = UDim2.fromOffset(0, 147)
		submitButton.Position = UDim2.fromOffset(0, 201)
		statusLabel.Position = UDim2.fromOffset(0, 250)
	else
		reasonLabel.Position = UDim2.fromOffset(0, 201)
		reasonBox.Position = UDim2.fromOffset(0, 222)
		submitButton.Position = UDim2.fromOffset(0, 276)
		statusLabel.Position = UDim2.fromOffset(0, 323)
	end
	setBusy(busy)
end

render = function()
	renderBalances()
	renderStatements()
	renderAction()
end

local function updateResponsiveLayout()
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	shellScale.Scale = math.clamp(math.min(viewport.X / 970, viewport.Y / 650), 0.52, 1)
end

local function closeBank(force)
	if not isOpen or (busy and force ~= true) then
		return
	end
	isOpen = false
	screenGui.Enabled = false
	GuiService.SelectedObject = nil
	amountBox:ReleaseFocus()
	recipientBox:ReleaseFocus()
	reasonBox:ReleaseFocus()
	pinBox:ReleaseFocus()
	pinBox.Text = ""
	pinGate.Visible = false
	accessContext = { mode = "bank", locationId = "" }
	deleteConfirmAccountId = nil
	setStatus("")
end

local function fetchSnapshot(silent)
	if busy or not isOpen then
		return false
	end
	setBusy(true)
	if not silent then
		setStatus("Loading account...", COLORS.muted)
	end
	local nextSnapshot, err = callRemote(Remotes.GetBanking, accessContext)
	setBusy(false)
	if not nextSnapshot then
		setStatus(err or "The account could not be loaded.", COLORS.red)
		return false
	end
	snapshot = nextSnapshot
	if not silent then
		setStatus("Account ready.", COLORS.green)
	end
	render()
	return true
end

local function openBank(context)
	if type(context) == "string" then
		context = { mode = "bank", locationId = context }
	end
	context = type(context) == "table" and context or {}
	accessContext = {
		mode = context.mode == "atm" and "atm" or "bank",
		locationId = tostring(context.locationId or ""),
	}
	if isOpen then
		if accessContext.mode == "atm" then
			pinGate.Visible = true
			pinBox.Text = ""
			pinStatus.Text = ""
		else
			pinGate.Visible = false
			fetchSnapshot(true)
		end
		return
	end
	isOpen = true
	screenGui.Enabled = true
	updateResponsiveLayout()
	currentAction = accessContext.mode == "atm" and "withdraw" or "deposit"
	selectedAccountId = "checking"
	renderedManageAccountId = nil
	deleteConfirmAccountId = nil
	amountBox.Text = ""
	recipientBox.Text = ""
	reasonBox.Text = ""
	snapshot = nil
	render()
	if accessContext.mode == "atm" then
		pinGate.Visible = true
		pinBox.Text = ""
		pinStatus.Text = ""
		GuiService.SelectedObject = pinBox
	elseif fetchSnapshot(false) then
		GuiService.SelectedObject = tabButtons.deposit
	else
		task.delay(2.5, function()
			if isOpen and not snapshot and not busy then
				closeBank()
			end
		end)
	end
end

pinButton.Activated:Connect(function()
	if busy or not isOpen or accessContext.mode ~= "atm" then
		return
	end
	if not pinBox.Text:match("^%d%d%d%d$") then
		pinStatus.Text = "Enter a 4-digit PIN."
		return
	end
	accessContext.pin = pinBox.Text
	pinStatus.Text = "Verifying card..."
	if fetchSnapshot(true) then
		pinGate.Visible = false
		pinStatus.Text = ""
		GuiService.SelectedObject = tabButtons.withdraw
	else
		accessContext.pin = nil
		pinStatus.Text = "Card or PIN not recognized."
	end
end)

for actionName, button in pairs(tabButtons) do
	local selectedAction = actionName
	button.Activated:Connect(function()
		if busy then
			return
		end
		if currentAction ~= selectedAction then
			amountBox.Text = ""
			recipientBox.Text = ""
			reasonBox.Text = ""
			renderedManageAccountId = nil
		end
		currentAction = selectedAction
		setStatus("")
		render()
	end)
end

local function performBankingAction(serverAction, payload)
	if busy or not isOpen then
		return false
	end
	payload = type(payload) == "table" and payload or {}
	payload.access = accessContext
	setBusy(true)
	setStatus("Processing transaction...", COLORS.muted)
	local ok, result = callRemote(Remotes.BankingAction, serverAction, payload)
	setBusy(false)
	if ok ~= true then
		setStatus(result or "The transaction was declined.", COLORS.red)
		return false
	end
	snapshot = result.snapshot
	amountBox.Text = ""
	recipientBox.Text = ""
	reasonBox.Text = ""
	renderedManageAccountId = nil
	setStatus(result.message or "Transaction complete.", COLORS.green)
	render()
	return true
end

submitButton.Activated:Connect(function()
	if busy or not isOpen then
		return
	end
	if accessContext.mode == "atm" and currentAction == "deposit" then
		setStatus("Cash deposits are only available at a bank counter.", COLORS.red)
		return
	end
	if currentAction ~= "card" and amountBox.Text == "" then
		setStatus(currentAction == "manage" and "Enter an account name." or "Enter a transaction amount.", COLORS.red)
		return
	end
	if currentAction == "manage" then
		local account = selectedAccount()
		if account.type == "shared" and account.isOwner == true then
			performBankingAction("rename_shared", {
				accountId = selectedAccountId,
				name = amountBox.Text,
			})
		else
			performBankingAction("create_shared", {
				name = amountBox.Text,
				amount = recipientBox.Text ~= "" and recipientBox.Text or "0",
			})
		end
		return
	end
	if currentAction == "card" and not recipientBox.Text:match("^%d%d%d%d$") then
		setStatus("Choose a 4-digit PIN.", COLORS.red)
		return
	end

	local serverAction = currentAction == "card" and "order_card" or currentAction
	performBankingAction(serverAction, {
		amount = amountBox.Text,
		citizenId = recipientBox.Text,
		reason = reasonBox.Text,
		pin = recipientBox.Text,
		accountId = selectedAccountId,
	})
end)

addMemberButton.Activated:Connect(function()
	if recipientBox.Text == "" then
		setStatus("Enter the member's citizen ID.", COLORS.red)
		return
	end
	performBankingAction("add_shared_member", {
		accountId = selectedAccountId,
		citizenId = recipientBox.Text,
	})
end)

removeMemberButton.Activated:Connect(function()
	if recipientBox.Text == "" then
		setStatus("Enter the member's citizen ID.", COLORS.red)
		return
	end
	performBankingAction("remove_shared_member", {
		accountId = selectedAccountId,
		citizenId = recipientBox.Text,
	})
end)

deleteAccountButton.Activated:Connect(function()
	if deleteConfirmAccountId ~= selectedAccountId then
		deleteConfirmAccountId = selectedAccountId
		deleteAccountButton.Text = "Confirm close account"
		setStatus("Click again to permanently close this empty account.", COLORS.red)
		local confirmingAccountId = selectedAccountId
		task.delay(4, function()
			if deleteConfirmAccountId == confirmingAccountId then
				deleteConfirmAccountId = nil
				if isOpen and currentAction == "manage" then
					deleteAccountButton.Text = "Close empty account"
				end
			end
		end)
		return
	end
	deleteConfirmAccountId = nil
	performBankingAction("delete_shared", { accountId = selectedAccountId })
end)

closeButton.Activated:Connect(closeBank)

Remotes.OpenBank.OnClientEvent:Connect(function(context)
	openBank(context)
end)

QBCoreClient.OnPlayerDataUpdated.Event:Connect(function(key, value)
	if not isOpen then
		return
	end
	if key == "money" and snapshot and snapshot.account then
		snapshot.account.cash = tonumber(value and value.cash) or snapshot.account.cash
		snapshot.account.balance = tonumber(value and value.bank) or snapshot.account.balance
		for _, account in ipairs(snapshot.accounts or {}) do
			if account.type == "checking" then
				account.cash = snapshot.account.cash
				account.balance = snapshot.account.balance
			end
		end
		renderBalances()
	elseif key == "banking" and not refreshQueued then
		refreshQueued = true
		task.defer(function()
			refreshQueued = false
			if isOpen and not busy then
				fetchSnapshot(true)
			end
		end)
	end
end)

QBCoreClient.OnPlayerLoaded.Event:Connect(function()
	if isOpen then
		closeBank(true)
	end
end)

player.CharacterRemoving:Connect(function()
	if isOpen then
		closeBank(true)
	end
end)

UserInputService.InputBegan:Connect(function(input)
	if not isOpen or busy then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
		closeBank()
	end
end)

local viewportConnection = nil
local function bindResponsiveLayout()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	local camera = Workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveLayout)
	end
	updateResponsiveLayout()
end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindResponsiveLayout)
bindResponsiveLayout()
renderAction()
