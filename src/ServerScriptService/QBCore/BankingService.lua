-- Server-authoritative personal, society, and ATM banking. Player balances remain on
-- PlayerData; shared accounts and queued cross-session transfers use dedicated stores.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local QBShared = require(ReplicatedStorage.QBShared.Main)
local Remotes = require(ReplicatedStorage.QBRemotes)

local function requireSiblingModule(name)
	local module = script.Parent:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		error(("QBCore setup error: %s must be a ModuleScript next to %s."):format(name, script:GetFullName()), 2)
	end
	return require(module)
end

local PlayerService = requireSiblingModule("PlayerService")
local BankingService = {}

local societyStore = DataStoreService:GetDataStore("QBCore_SocietyAccounts")
local transferStore = DataStoreService:GetDataStore("QBCore_BankTransferInbox")
local INTERACTION_FOLDER_NAME = "QBBankingLocations"
local ACTION_COOLDOWN = 0.35
local MAX_PENDING_TRANSFERS = 100
local MAX_PROCESSED_TRANSFERS = 200

local started = false
local lastActionAt = {}
local transactionBusy = {}

local function config()
	return type(QBShared.Config.Banking) == "table" and QBShared.Config.Banking or {}
end

local function trim(value)
	return type(value) == "string" and (value:match("^%s*(.-)%s*$") or "") or ""
end

local function locationPosition(location)
	if type(location) ~= "table" then
		return nil
	end
	if typeof(location.position) == "Vector3" then
		return location.position
	end
	if type(location.position) == "table" then
		local x = tonumber(location.position.x or location.position.X)
		local y = tonumber(location.position.y or location.position.Y)
		local z = tonumber(location.position.z or location.position.Z)
		if x and y and z then
			return Vector3.new(x, y, z)
		end
	end
	return nil
end

local function getRoot(player)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end
	return root
end

local function normalizeAccess(access)
	access = type(access) == "table" and access or {}
	local mode = access.mode == "atm" and "atm" or "bank"
	return { mode = mode, locationId = trim(access.locationId), pin = trim(access.pin) }
end

local function resolveAccess(player, access)
	access = normalizeAccess(access)
	local root = getRoot(player)
	if not root then
		return nil, nil, "Your character is unavailable."
	end
	local list = access.mode == "atm" and (config().ATMLocations or {}) or (config().Locations or {})
	local maxDistance = math.max(1, tonumber(config().ActionDistance) or 14)
	for _, location in ipairs(list) do
		local id = trim(location.id)
		local position = locationPosition(location)
		if
			(access.locationId == "" or access.locationId == id)
			and position
			and (root.Position - position).Magnitude <= maxDistance
		then
			access.locationId = id
			return location, access
		end
	end
	return nil, access, access.mode == "atm" and "Move closer to an ATM." or "Move closer to a bank counter."
end

local function findCitizenId(playerObj)
	for citizenId, candidate in pairs(PlayerService.PlayersByCitizenId) do
		if candidate == playerObj then
			return citizenId
		end
	end
	return ""
end

local function isActivePlayer(player, playerObj)
	return player and player.Parent == Players and PlayerService.GetPlayer(player.UserId) == playerObj
end

local function ensureBankingData(playerObj)
	local data = playerObj.PlayerData
	if type(data.banking) ~= "table" then
		data.banking = {}
	end
	local banking = data.banking
	if type(banking.statements) ~= "table" then
		banking.statements = {}
	end
	if type(banking.atm) ~= "table" then
		banking.atm = {}
	end
	if type(banking.processedTransferIds) ~= "table" then
		banking.processedTransferIds = {}
	end
	banking.nextStatementId = math.max(1, math.floor(tonumber(banking.nextStatementId) or 1))
	banking.atm.dayKey = math.floor(tonumber(banking.atm.dayKey) or 0)
	banking.atm.withdrawn = math.max(0, math.floor(tonumber(banking.atm.withdrawn) or 0))
	return banking
end

local function maxStatements()
	return math.max(1, math.floor(tonumber(config().MaxStatements) or 50))
end

local function copyStatements(statements)
	local result = {}
	for index, entry in ipairs(type(statements) == "table" and statements or {}) do
		if type(entry) == "table" then
			result[index] = {
				id = tonumber(entry.id) or index,
				time = tonumber(entry.time) or 0,
				account = tostring(entry.account or "checking"),
				kind = tostring(entry.kind or "deposit"),
				amount = tonumber(entry.amount) or 0,
				reason = tostring(entry.reason or "Bank transaction"),
				balance = tonumber(entry.balance) or 0,
				counterparty = tostring(entry.counterparty or ""),
				counterpartyCitizenId = tostring(entry.counterpartyCitizenId or ""),
			}
		end
	end
	return result
end

local function addPersonalStatement(playerObj, kind, amount, reason, counterparty, counterpartyCitizenId)
	local banking = ensureBankingData(playerObj)
	local entry = {
		id = banking.nextStatementId,
		time = os.time(),
		account = "checking",
		kind = kind,
		amount = amount,
		reason = reason,
		balance = tonumber(playerObj:GetMoney("bank")) or 0,
		counterparty = counterparty or "",
		counterpartyCitizenId = counterpartyCitizenId or "",
	}
	banking.nextStatementId += 1
	table.insert(banking.statements, 1, entry)
	while #banking.statements > maxStatements() do
		table.remove(banking.statements)
	end
	return entry
end

local function societyConfig()
	return type(config().Society) == "table" and config().Society or {}
end

local function validOrganization(organizationType, organizationName)
	if type(organizationName) ~= "string" or organizationName == "" then
		return false
	end
	if organizationType == "crew" then
		return QBShared.Crews[organizationName] ~= nil and organizationName ~= "none"
	end
	return QBShared.Jobs[organizationName] ~= nil and organizationName ~= "unemployed"
end

local function organizationStoreKey(organizationType, organizationName)
	return (organizationType == "crew" and "Crew_" or "Society_") .. organizationName
end

local function newSocietyRecord(organizationName, organizationType)
	local starts = societyConfig().StartingBalances
	local nested = type(starts) == "table" and starts[organizationType or "job"] or nil
	local start = type(nested) == "table" and tonumber(nested[organizationName])
		or (type(starts) == "table" and tonumber(starts[organizationName]) or nil)
	return {
		balance = math.max(0, math.floor(start or tonumber(societyConfig().DefaultBalance) or 0)),
		nextStatementId = 1,
		statements = {},
	}
end

local function reconcileSociety(record, organizationName, organizationType)
	if type(record) ~= "table" then
		record = newSocietyRecord(organizationName, organizationType)
	end
	record.balance = math.max(0, math.floor(tonumber(record.balance) or 0))
	record.nextStatementId = math.max(1, math.floor(tonumber(record.nextStatementId) or 1))
	if type(record.statements) ~= "table" then
		record.statements = {}
	end
	return record
end

local function mutateSociety(organizationName, delta, statement, organizationType)
	organizationType = organizationType == "crew" and "crew" or "job"
	if societyConfig().Enabled == false then
		return false, "Society banking is disabled."
	end
	if not validOrganization(organizationType, organizationName) then
		return false, "Unknown society account."
	end
	delta = math.floor(tonumber(delta) or 0)
	local outcome
	local ok, storeErr = pcall(function()
		societyStore:UpdateAsync(organizationStoreKey(organizationType, organizationName), function(record)
			record = reconcileSociety(record, organizationName, organizationType)
			if delta < 0 and record.balance < -delta then
				outcome = { false, "The society account has insufficient funds.", record.balance }
				return record
			end
			record.balance += delta
			if statement then
				local entry = {
					id = record.nextStatementId,
					time = os.time(),
					account = (organizationType == "crew" and "crew:" or "society:") .. organizationName,
					kind = statement.kind or (delta >= 0 and "deposit" or "withdraw"),
					amount = math.abs(delta),
					reason = statement.reason or "Society transaction",
					balance = record.balance,
					counterparty = statement.counterparty or "",
					counterpartyCitizenId = statement.counterpartyCitizenId or "",
				}
				record.nextStatementId += 1
				table.insert(record.statements, 1, entry)
				while #record.statements > maxStatements() do
					table.remove(record.statements)
				end
			end
			outcome = { true, nil, record.balance }
			return record
		end)
	end)
	if not ok then
		warn(
			("[QBCore.BankingService] Society update failed for %s:%s: %s"):format(
				organizationType,
				organizationName,
				tostring(storeErr)
			)
		)
		return false, "The society account is temporarily unavailable."
	end
	return table.unpack(outcome or { false, "The society account could not be updated." })
end

local function getSocietyRecord(organizationName, organizationType)
	organizationType = organizationType == "crew" and "crew" or "job"
	local record
	local ok, err = pcall(function()
		record = societyStore:GetAsync(organizationStoreKey(organizationType, organizationName))
	end)
	if not ok then
		warn(
			("[QBCore.BankingService] Society read failed for %s:%s: %s"):format(
				organizationType,
				organizationName,
				tostring(err)
			)
		)
		return nil, "The society account is temporarily unavailable."
	end
	return reconcileSociety(record, organizationName, organizationType)
end

local function bossJob(playerObj)
	local job = playerObj and playerObj.PlayerData.job
	local grade = type(job) == "table" and job.grade or nil
	if
		type(job) == "table"
		and validOrganization("job", job.name)
		and (job.isboss == true or (type(grade) == "table" and grade.isboss == true))
	then
		return job.name, tostring(job.label or (QBShared.Jobs[job.name] and QBShared.Jobs[job.name].label) or job.name)
	end
	return nil
end

local function getAccount(playerObj, accountId, access)
	if type(accountId) ~= "string" or accountId == "" or accountId == "checking" then
		return { id = "checking", type = "checking" }
	end
	local jobName = accountId:match("^society:(.+)$")
	local bossName = bossJob(playerObj)
	if access.mode ~= "bank" or not jobName or bossName ~= jobName then
		return nil, "You do not have access to that account."
	end
	return { id = accountId, type = "society", jobName = jobName }
end

local function holderName(playerObj)
	local info = type(playerObj.PlayerData.charinfo) == "table" and playerObj.PlayerData.charinfo or {}
	local holder = trim(tostring(info.firstname or "") .. " " .. tostring(info.lastname or ""))
	return holder ~= "" and holder or playerObj:GetName()
end

local function currentDayKey()
	return math.floor(os.time() / 86400)
end

local function resetAtmDay(playerObj)
	local atm = ensureBankingData(playerObj).atm
	local today = currentDayKey()
	if atm.dayKey ~= today then
		atm.dayKey, atm.withdrawn = today, 0
	end
	return atm
end

local function getSnapshot(playerObj, location, access)
	local banking = ensureBankingData(playerObj)
	local personal = {
		id = "checking",
		name = "Checking",
		type = "checking",
		holder = holderName(playerObj),
		citizenId = findCitizenId(playerObj),
		balance = tonumber(playerObj:GetMoney("bank")) or 0,
		cash = tonumber(playerObj:GetMoney("cash")) or 0,
		statements = copyStatements(banking.statements),
	}
	local accounts = { personal }
	if access.mode == "bank" and societyConfig().Enabled ~= false then
		local jobName, label = bossJob(playerObj)
		if jobName then
			local society = getSocietyRecord(jobName)
			if society then
				table.insert(accounts, {
					id = "society:" .. jobName,
					name = label .. " Society",
					type = "society",
					holder = label,
					citizenId = jobName,
					balance = society.balance,
					cash = personal.cash,
					statements = copyStatements(society.statements),
				})
			end
		end
	end
	local atm = resetAtmDay(playerObj)
	return {
		account = personal,
		accounts = accounts,
		statements = personal.statements,
		location = {
			id = tostring(location.id or access.locationId),
			label = tostring(location.label or "QBCore Bank"),
		},
		access = { mode = access.mode, locationId = access.locationId },
		limits = {
			maxTransactionAmount = math.max(1, math.floor(tonumber(config().MaxTransactionAmount) or 1000000)),
			cardPrice = math.max(0, math.floor(tonumber(config().CardPrice) or 50)),
			dailyWithdrawalLimit = math.max(0, math.floor(tonumber(config().DailyWithdrawalLimit) or 5000)),
			dailyWithdrawn = atm.withdrawn,
			useDailyWithdrawalLimit = config().UseDailyWithdrawalLimit ~= false,
		},
	}
end

local function parseAmount(value)
	local amount = tonumber(value)
	local limit = math.max(1, math.floor(tonumber(config().MaxTransactionAmount) or 1000000))
	if not amount or amount ~= amount or amount == math.huge or amount <= 0 then
		return nil, "Enter a positive amount."
	end
	amount = math.floor(amount)
	if amount <= 0 then
		return nil, "Enter a positive whole-dollar amount."
	end
	if amount > limit then
		return nil, ("Transactions are limited to $%d."):format(limit)
	end
	return amount
end

local function cleanReason(value, fallback)
	local reason = trim(value):gsub("[%c]", " ")
	return (reason ~= "" and reason or fallback):sub(1, 60)
end

local function filterForUserId(text, sourcePlayer, targetUserId, fallback)
	if type(text) ~= "string" or not sourcePlayer or not sourcePlayer:IsA("Player") or not tonumber(targetUserId) then
		return fallback
	end
	local ok, result =
		pcall(TextService.FilterStringAsync, TextService, text, sourcePlayer.UserId, Enum.TextFilterContext.PrivateChat)
	if not ok or not result then
		return fallback
	end
	local filteredOk, filtered = pcall(result.GetNonChatStringForUserAsync, result, tonumber(targetUserId))
	return filteredOk and type(filtered) == "string" and filtered ~= "" and filtered:sub(1, 60) or fallback
end

local function hasValidCardPin(playerObj, pin)
	if not pin:match("^%d%d%d%d$") then
		return false
	end
	local citizenId = findCitizenId(playerObj)
	for _, item in ipairs(playerObj:GetItemsByName("bank_card")) do
		local info = type(item.info) == "table" and item.info or {}
		if tostring(info.citizenId or "") == citizenId and tostring(info.pin or "") == pin then
			return true
		end
	end
	return false
end

local function validateAtm(playerObj, access)
	if access.mode ~= "atm" then
		return true
	end
	if not hasValidCardPin(playerObj, access.pin) then
		return false, "Insert your bank card and enter its 4-digit PIN."
	end
	return true
end

local function debitAccount(playerObj, account, amount, statement)
	if account.type == "checking" then
		if (tonumber(playerObj:GetMoney("bank")) or 0) < amount then
			return false, "This account has insufficient funds."
		end
		if not playerObj:RemoveMoney("bank", amount, "bank-" .. statement.kind) then
			return false, "The account could not be debited."
		end
		addPersonalStatement(
			playerObj,
			statement.kind,
			amount,
			statement.reason,
			statement.counterparty,
			statement.counterpartyCitizenId
		)
		return true
	end
	return mutateSociety(account.jobName, -amount, statement)
end

local function creditAccount(playerObj, account, amount, statement)
	if account.type == "checking" then
		if not playerObj:AddMoney("bank", amount, "bank-" .. statement.kind) then
			return false, "The account could not accept the funds."
		end
		addPersonalStatement(
			playerObj,
			statement.kind,
			amount,
			statement.reason,
			statement.counterparty,
			statement.counterpartyCitizenId
		)
		return true
	end
	return mutateSociety(account.jobName, amount, statement)
end

local function rollbackDebit(playerObj, account, amount)
	if account.type == "checking" then
		playerObj:AddMoney("bank", amount, "bank-rollback")
	else
		mutateSociety(account.jobName, amount, { kind = "refund", reason = "Reversed transaction" })
	end
end

local function deposit(player, playerObj, payload, access)
	if access.mode == "atm" then
		return false, "Cash deposits are only available at a bank counter."
	end
	local amount, err = parseAmount(payload.amount)
	if not amount then
		return false, err
	end
	local account, accountErr = getAccount(playerObj, payload.accountId, access)
	if not account then
		return false, accountErr
	end
	if (tonumber(playerObj:GetMoney("cash")) or 0) < amount then
		return false, "You do not have enough cash."
	end
	local reason = filterForUserId(cleanReason(payload.reason, "Cash deposit"), player, player.UserId, "Cash deposit")
	if not isActivePlayer(player, playerObj) then
		return false, "Your banking session ended."
	end
	if not playerObj:RemoveMoney("cash", amount, "bank-deposit") then
		return false, "The cash deposit could not be completed."
	end
	local ok, creditErr = creditAccount(playerObj, account, amount, { kind = "deposit", reason = reason })
	if not ok then
		playerObj:AddMoney("cash", amount, "bank-deposit-rollback")
		return false, creditErr
	end
	playerObj:UpdateClient("banking", playerObj.PlayerData.banking)
	playerObj:Save()
	return true, "Deposit successful."
end

local function withdraw(player, playerObj, payload, access)
	local amount, err = parseAmount(payload.amount)
	if not amount then
		return false, err
	end
	local account, accountErr = getAccount(playerObj, payload.accountId, access)
	if not account then
		return false, accountErr
	end
	local atm = resetAtmDay(playerObj)
	if access.mode == "atm" and config().UseDailyWithdrawalLimit ~= false then
		local limit = math.max(0, math.floor(tonumber(config().DailyWithdrawalLimit) or 5000))
		if atm.withdrawn + amount > limit then
			return false,
				("ATM daily withdrawal limit: $%d ($%d remaining)."):format(limit, math.max(0, limit - atm.withdrawn))
		end
	end
	local reason =
		filterForUserId(cleanReason(payload.reason, "Cash withdrawal"), player, player.UserId, "Cash withdrawal")
	if not isActivePlayer(player, playerObj) then
		return false, "Your banking session ended."
	end
	local ok, debitErr = debitAccount(playerObj, account, amount, { kind = "withdraw", reason = reason })
	if not ok then
		return false, debitErr
	end
	if not playerObj:AddMoney("cash", amount, "bank-withdrawal") then
		rollbackDebit(playerObj, account, amount)
		return false, "The withdrawal could not be completed."
	end
	if access.mode == "atm" then
		atm.withdrawn += amount
	end
	playerObj:UpdateClient("banking", playerObj.PlayerData.banking)
	playerObj:Save()
	return true, "Withdrawal successful."
end

local function removeQueuedTransfer(citizenId, transferId)
	pcall(function()
		transferStore:UpdateAsync("Inbox_" .. citizenId, function(record)
			record = type(record) == "table" and record or { transfers = {} }
			local kept = {}
			for _, transfer in ipairs(type(record.transfers) == "table" and record.transfers or {}) do
				if transfer.id ~= transferId then
					table.insert(kept, transfer)
				end
			end
			record.transfers = kept
			return record
		end)
	end)
end

local function queueTransfer(targetCitizenId, transfer)
	local ok, err = pcall(function()
		transferStore:UpdateAsync("Inbox_" .. targetCitizenId, function(record)
			record = type(record) == "table" and record or { transfers = {} }
			if type(record.transfers) ~= "table" then
				record.transfers = {}
			end
			local now = os.time()
			local kept = {}
			for _, existing in ipairs(record.transfers) do
				if existing.status == "ready" or now - (tonumber(existing.time) or 0) < 3600 then
					table.insert(kept, existing)
				end
			end
			if #kept >= MAX_PENDING_TRANSFERS then
				error("recipient inbox is full")
			end
			table.insert(kept, transfer)
			record.transfers = kept
			return record
		end)
	end)
	return ok, err
end

local function markTransferReady(targetCitizenId, transferId)
	for _ = 1, 3 do
		local found = false
		local ok = pcall(function()
			transferStore:UpdateAsync("Inbox_" .. targetCitizenId, function(record)
				record = type(record) == "table" and record or { transfers = {} }
				for _, transfer in ipairs(type(record.transfers) == "table" and record.transfers or {}) do
					if transfer.id == transferId then
						transfer.status = "ready"
						found = true
					end
				end
				return record
			end)
		end)
		if ok and found then
			return true
		end
		task.wait(0.1)
	end
	return false
end

local function transfer(player, playerObj, payload, access)
	local amount, err = parseAmount(payload.amount)
	if not amount then
		return false, err
	end
	local account, accountErr = getAccount(playerObj, payload.accountId, access)
	if not account then
		return false, accountErr
	end
	local targetCitizenId = string.upper(trim(payload.citizenId))
	if not targetCitizenId:match("^%u%u%u%d%d%d%d%d$") then
		return false, "Enter a valid citizen ID (for example, ABC12345)."
	end
	local senderCitizenId = findCitizenId(playerObj)
	if targetCitizenId == senderCitizenId then
		return false, "You cannot transfer money to the same account."
	end
	local targetObj = PlayerService.GetPlayerByCitizenId(targetCitizenId)
	local targetPlayer = targetObj and targetObj._source
	local targetUserId = targetPlayer and targetPlayer.UserId
		or PlayerService.GetAccountUserIdByCitizenId(targetCitizenId)
	if not targetUserId then
		return false, "That citizen account does not exist."
	end
	if not targetObj then
		targetObj = PlayerService.GetOfflinePlayerByCitizenId(targetCitizenId)
		if not targetObj then
			return false, "That citizen account does not exist."
		end
	end
	local rawReason = cleanReason(payload.reason, "Citizen transfer")
	local senderReason = filterForUserId(rawReason, player, player.UserId, "Citizen transfer")
	local recipientReason = filterForUserId(rawReason, player, targetUserId, "Citizen transfer")
	local senderName = filterForUserId(playerObj:GetName(), player, targetUserId, "Citizen " .. senderCitizenId)
	local targetName = "Citizen " .. targetCitizenId
	if targetPlayer and targetPlayer:IsA("Player") then
		targetName = filterForUserId(targetObj:GetName(), targetPlayer, player.UserId, targetName)
	end
	if not isActivePlayer(player, playerObj) then
		return false, "Your banking session ended."
	end

	if targetPlayer and isActivePlayer(targetPlayer, targetObj) then
		local ok, debitErr = debitAccount(playerObj, account, amount, {
			kind = "transfer_out",
			reason = senderReason,
			counterparty = targetName,
			counterpartyCitizenId = targetCitizenId,
		})
		if not ok then
			return false, debitErr
		end
		if not targetObj:AddMoney("bank", amount, "bank-transfer-in") then
			rollbackDebit(playerObj, account, amount)
			return false, "The recipient account could not accept the transfer."
		end
		addPersonalStatement(targetObj, "transfer_in", amount, recipientReason, senderName, senderCitizenId)
		playerObj:UpdateClient("banking", playerObj.PlayerData.banking)
		targetObj:UpdateClient("banking", targetObj.PlayerData.banking)
		playerObj:Save()
		targetObj:Save()
		targetObj:Notify(("%s sent you $%d."):format(senderName, amount), "success", 6000)
		return true, "Transfer successful."
	end

	local transferId = HttpService:GenerateGUID(false)
	local queued, queueErr = queueTransfer(targetCitizenId, {
		id = transferId,
		status = "pending",
		time = os.time(),
		amount = amount,
		senderCitizenId = senderCitizenId,
		senderName = senderName,
		reason = recipientReason,
	})
	if not queued then
		warn(("[QBCore.BankingService] Transfer queue failed: %s"):format(tostring(queueErr)))
		return false, "The recipient account is temporarily unavailable."
	end
	local ok, debitErr = debitAccount(playerObj, account, amount, {
		kind = "transfer_out",
		reason = senderReason,
		counterparty = targetName,
		counterpartyCitizenId = targetCitizenId,
	})
	if not ok then
		removeQueuedTransfer(targetCitizenId, transferId)
		return false, debitErr
	end
	-- A personal debit must be durably saved before the recipient can observe a
	-- ready transfer. Society debits are already committed by UpdateAsync.
	if account.type == "checking" and playerObj:Save() ~= true then
		rollbackDebit(playerObj, account, amount)
		addPersonalStatement(playerObj, "refund", amount, "Queued transfer reversed", targetName, targetCitizenId)
		playerObj:Save()
		removeQueuedTransfer(targetCitizenId, transferId)
		return false, "Your account could not be saved; the transfer was reversed."
	end
	if not markTransferReady(targetCitizenId, transferId) then
		rollbackDebit(playerObj, account, amount)
		removeQueuedTransfer(targetCitizenId, transferId)
		if account.type == "checking" then
			addPersonalStatement(playerObj, "refund", amount, "Queued transfer reversed", targetName, targetCitizenId)
		end
		playerObj:Save()
		return false, "The queued transfer could not be finalized; your funds were returned."
	end
	playerObj:UpdateClient("banking", playerObj.PlayerData.banking)
	playerObj:Save()
	return true, "Transfer queued safely for the recipient's next login."
end

local function orderCard(player, playerObj, payload, access)
	if access.mode ~= "bank" then
		return false, "New cards must be issued at a bank counter."
	end
	local pin = trim(payload.pin)
	if not pin:match("^%d%d%d%d$") then
		return false, "Choose a 4-digit PIN."
	end
	local price = math.max(0, math.floor(tonumber(config().CardPrice) or 50))
	if (tonumber(playerObj:GetMoney("bank")) or 0) < price then
		return false, ("A bank card costs $%d."):format(price)
	end
	if price > 0 and not playerObj:RemoveMoney("bank", price, "bank-card") then
		return false, "The card charge could not be completed."
	end
	local cardNumber = ("%04d-%04d-%04d"):format(math.random(0, 9999), math.random(0, 9999), math.random(0, 9999))
	local added, addErr = playerObj:AddItem("bank_card", 1, nil, {
		citizenId = findCitizenId(playerObj),
		cardNumber = cardNumber,
		pin = pin,
		issuedAt = os.time(),
	}, "bank-card")
	if not added then
		if price > 0 then
			playerObj:AddMoney("bank", price, "bank-card-rollback")
		end
		return false, addErr or "There is no room for the bank card."
	end
	if price > 0 then
		addPersonalStatement(playerObj, "card", price, "Bank card issued")
	end
	playerObj:UpdateClient("banking", playerObj.PlayerData.banking)
	playerObj:Save()
	return true, ("Card %s issued. Keep your PIN private."):format(cardNumber)
end

local ACTIONS = { deposit = deposit, withdraw = withdraw, transfer = transfer, order_card = orderCard }

local function createInteraction(location, index, folder, mode)
	local position = locationPosition(location)
	if not position then
		warn(("[QBCore.BankingService] %s location %d has no valid position."):format(mode, index))
		return
	end
	local id = trim(location.id)
	if id == "" then
		id = mode .. "_" .. index
	end
	local partName = (mode == "atm" and "ATM_" or "Bank_") .. id:gsub("[^%w_]", "_")
	local part = folder:FindFirstChild(partName)
	if part and not part:IsA("BasePart") then
		warn(("[QBCore.BankingService] %s must be a BasePart."):format(part:GetFullName()))
		return
	end
	if not part then
		part = Instance.new("Part")
		part.Name = partName
		part.Parent = folder
	end
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.CastShadow, part.Transparency, part.Size, part.Position = false, 1, Vector3.new(2, 2, 2), position
	local prompt = part:FindFirstChild("BankPrompt")
	if prompt and not prompt:IsA("ProximityPrompt") then
		warn(("[QBCore.BankingService] %s.BankPrompt must be a ProximityPrompt."):format(part:GetFullName()))
		return
	end
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BankPrompt"
		prompt.Parent = part
	end
	prompt.ActionText = mode == "atm" and "Use ATM" or "Open Bank"
	prompt.ObjectText = tostring(location.label or (mode == "atm" and "QBCore ATM" or "QBCore Bank"))
	prompt.KeyboardKeyCode, prompt.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = math.max(1, tonumber(config().PromptDistance) or 10)
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(function(player)
		local playerObj = PlayerService.GetPlayer(player.UserId)
		local resolvedLocation, access = resolveAccess(player, { mode = mode, locationId = id })
		if playerObj and resolvedLocation then
			Remotes.OpenBank:FireClient(player, access)
		end
	end)
end

local function createInteractions()
	local folder = Workspace:FindFirstChild(INTERACTION_FOLDER_NAME)
	if folder and not folder:IsA("Folder") then
		warn(("[QBCore.BankingService] Workspace.%s must be a Folder."):format(INTERACTION_FOLDER_NAME))
		return
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = INTERACTION_FOLDER_NAME
		folder.Parent = Workspace
	end
	for index, location in ipairs(config().Locations or {}) do
		createInteraction(location, index, folder, "bank")
	end
	for index, location in ipairs(config().ATMLocations or {}) do
		createInteraction(location, index, folder, "atm")
	end
end

function BankingService.WithdrawSocietyFunds(jobName, amount, playerObj)
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	if amount <= 0 then
		return false, "Invalid paycheck amount."
	end
	return mutateSociety(jobName, -amount, {
		kind = "paycheck",
		reason = "Employee paycheck",
		counterparty = playerObj and playerObj:GetName() or "Employee",
		counterpartyCitizenId = playerObj and findCitizenId(playerObj) or "",
	})
end

function BankingService.AddSocietyFunds(jobName, amount, reason)
	return mutateSociety(
		jobName,
		math.max(0, math.floor(tonumber(amount) or 0)),
		{ kind = "deposit", reason = reason or "Society deposit" }
	)
end

-- Shared account API used by the management service. Job keys intentionally retain
-- the original Society_<job> storage format; crew accounts use Crew_<crew> keys.
function BankingService.GetOrganizationFunds(organizationType, organizationName)
	if not validOrganization(organizationType, organizationName) then
		return nil, "Unknown organization account."
	end
	local record, err = getSocietyRecord(organizationName, organizationType)
	return record and record.balance or nil, err
end

function BankingService.ChangeOrganizationFunds(organizationType, organizationName, delta, statement)
	return mutateSociety(organizationName, delta, statement, organizationType)
end

function BankingService.DeliverPendingTransfers(player, playerObj)
	if not playerObj or not isActivePlayer(player, playerObj) then
		return 0
	end
	local citizenId = findCitizenId(playerObj)
	local record
	local ok, err = pcall(function()
		record = transferStore:GetAsync("Inbox_" .. citizenId)
	end)
	if not ok then
		warn(("[QBCore.BankingService] Transfer delivery read failed for %s: %s"):format(citizenId, tostring(err)))
		return 0
	end
	local banking = ensureBankingData(playerObj)
	local processed = {}
	for _, id in ipairs(banking.processedTransferIds) do
		processed[tostring(id)] = true
	end
	local removeIds, delivered, total = {}, 0, 0
	for _, transfer in ipairs(type(record) == "table" and type(record.transfers) == "table" and record.transfers or {}) do
		if transfer.status == "ready" then
			local id = tostring(transfer.id or "")
			if id ~= "" and not processed[id] then
				local amount = math.max(0, math.floor(tonumber(transfer.amount) or 0))
				if amount > 0 and playerObj:AddMoney("bank", amount, "queued-bank-transfer") then
					addPersonalStatement(
						playerObj,
						"transfer_in",
						amount,
						tostring(transfer.reason or "Citizen transfer"),
						tostring(transfer.senderName or "Citizen"),
						tostring(transfer.senderCitizenId or "")
					)
					table.insert(banking.processedTransferIds, id)
					processed[id] = true
					delivered += 1
					total += amount
				end
			end
			table.insert(removeIds, id)
		end
	end
	while #banking.processedTransferIds > MAX_PROCESSED_TRANSFERS do
		table.remove(banking.processedTransferIds, 1)
	end
	if #removeIds > 0 then
		playerObj:UpdateClient("banking", banking)
		local saved = playerObj:Save() == true
		local removeSet = {}
		for _, id in ipairs(removeIds) do
			removeSet[id] = true
		end
		if saved then
			pcall(function()
				transferStore:UpdateAsync("Inbox_" .. citizenId, function(current)
					current = type(current) == "table" and current or { transfers = {} }
					local kept = {}
					for _, transfer in ipairs(type(current.transfers) == "table" and current.transfers or {}) do
						if not removeSet[tostring(transfer.id or "")] then
							table.insert(kept, transfer)
						end
					end
					current.transfers = kept
					return current
				end)
			end)
		else
			warn(
				("[QBCore.BankingService] Keeping transfer inbox for %s because the credited profile did not save."):format(
					citizenId
				)
			)
		end
	end
	if delivered > 0 then
		playerObj:Notify(
			("%d queued transfer%s delivered ($%d)."):format(delivered, delivered == 1 and "" or "s", total),
			"success",
			6000
		)
	end
	return delivered
end

function BankingService.Start()
	if started then
		return
	end
	started = true
	Remotes.GetBanking.OnServerInvoke = function(player, requestedAccess)
		if config().Enabled == false then
			return nil, "Banking is currently unavailable."
		end
		local playerObj = PlayerService.GetPlayer(player.UserId)
		if not playerObj then
			return nil, "Load a character before using the bank."
		end
		local location, access, err = resolveAccess(player, requestedAccess)
		if not location then
			return nil, err
		end
		local pinOk, pinErr = validateAtm(playerObj, access)
		if not pinOk then
			return nil, pinErr
		end
		return getSnapshot(playerObj, location, access)
	end
	Remotes.BankingAction.OnServerInvoke = function(player, action, payload)
		if config().Enabled == false then
			return false, "Banking is currently unavailable."
		end
		local playerObj = PlayerService.GetPlayer(player.UserId)
		if not playerObj then
			return false, "Load a character before using the bank."
		end
		payload = type(payload) == "table" and payload or {}
		local location, access, err = resolveAccess(player, payload.access)
		if not location then
			return false, err
		end
		local pinOk, pinErr = validateAtm(playerObj, access)
		if not pinOk then
			return false, pinErr
		end
		local now = os.clock()
		if now - (lastActionAt[player] or 0) < ACTION_COOLDOWN then
			return false, "Please wait before submitting another transaction."
		end
		lastActionAt[player] = now
		action = type(action) == "string" and action:lower() or ""
		local handler = ACTIONS[action]
		if not handler then
			return false, "Unknown banking action."
		end
		if transactionBusy[player] then
			return false, "A banking transaction is already in progress."
		end
		transactionBusy[player] = true
		local handlerOk, ok, message = pcall(handler, player, playerObj, payload, access)
		transactionBusy[player] = nil
		if not handlerOk then
			warn(("[QBCore.BankingService] %s failed for %s: %s"):format(action, player.Name, tostring(ok)))
			return false, "The banking transaction could not be completed."
		end
		if not ok then
			return false, message
		end
		return true, { message = message, snapshot = getSnapshot(playerObj, location, access) }
	end
	Players.PlayerRemoving:Connect(function(player)
		lastActionAt[player], transactionBusy[player] = nil, nil
	end)
	if config().Enabled ~= false then
		createInteractions()
	end
end

return BankingService
