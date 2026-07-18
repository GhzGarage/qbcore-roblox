-- Server-authoritative job and crew management inspired by qb-management. Roblox
-- proximity replaces qb-target and a native client panel replaces qb-menu.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local ManagementService = {}

local rosterStore = DataStoreService:GetDataStore("QBCore_ManagementRosters")
local memberIndexStore = DataStoreService:GetDataStore("QBCore_ManagementMemberIndex")
local pendingStore = DataStoreService:GetDataStore("QBCore_ManagementPending")
local FOLDER_NAME = "QBManagementLocations"
local ACTION_COOLDOWN = 0.35

local bankingService = nil
local started = false
local lastActionAt = {}
local actionBusy = {}

local function config()
	return type(QBShared.Config.Management) == "table" and QBShared.Config.Management or {}
end

local function trim(value)
	return type(value) == "string" and (value:match("^%s*(.-)%s*$") or "") or ""
end

local function cleanType(value)
	return value == "crew" and "crew" or "job"
end

local function registry(organizationType)
	return organizationType == "crew" and QBShared.Crews or QBShared.Jobs
end

local function defaultOrganization(organizationType)
	return organizationType == "crew" and "none" or "unemployed"
end

local function validOrganization(organizationType, name)
	return type(name) == "string"
		and name ~= defaultOrganization(organizationType)
		and registry(organizationType)[name] ~= nil
end

local function locationPosition(location)
	if type(location) ~= "table" then return nil end
	if typeof(location.position) == "Vector3" then return location.position end
	if type(location.position) == "table" then
		local x = tonumber(location.position.x or location.position.X)
		local y = tonumber(location.position.y or location.position.Y)
		local z = tonumber(location.position.z or location.position.Z)
		if x and y and z then return Vector3.new(x, y, z) end
	end
	return nil
end

local function getRoot(player)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then return nil end
	return root
end

local function findCitizenId(playerObj)
	for citizenId, candidate in pairs(PlayerService.PlayersByCitizenId) do
		if candidate == playerObj then return citizenId end
	end
	return ""
end

local function memberName(playerObj)
	local info = type(playerObj.PlayerData.charinfo) == "table" and playerObj.PlayerData.charinfo or {}
	local name = trim(tostring(info.firstname or "") .. " " .. tostring(info.lastname or ""))
	return name ~= "" and name or "Unknown Citizen"
end

local function organizationData(playerObj, organizationType)
	return playerObj and playerObj.PlayerData[organizationType]
end

local function gradeLevel(data)
	return math.max(0, math.floor(tonumber(type(data) == "table" and data.grade and data.grade.level) or 0))
end

local function isBoss(data)
	local grade = type(data) == "table" and data.grade or nil
	return type(data) == "table" and (data.isboss == true or (type(grade) == "table" and grade.isboss == true))
end

local function rosterKey(organizationType, name)
	return organizationType .. ":" .. name
end

local function memberSnapshot(playerObj, citizenId, organizationType)
	local organization = organizationData(playerObj, organizationType)
	local grade = type(organization) == "table" and organization.grade or {}
	return {
		citizenId = citizenId,
		userId = playerObj._source and playerObj._source.UserId or 0,
		name = memberName(playerObj),
		grade = gradeLevel(organization),
		gradeName = tostring(grade.name or "Grade 0"),
		isboss = isBoss(organization),
		updatedAt = os.time(),
	}
end

local function updateRoster(organizationType, name, citizenId, snapshot)
	if not validOrganization(organizationType, name) or citizenId == "" then return true end
	local ok, err = pcall(function()
		rosterStore:UpdateAsync(rosterKey(organizationType, name), function(record)
			record = type(record) == "table" and record or { members = {} }
			record.members = type(record.members) == "table" and record.members or {}
			record.members[citizenId] = snapshot
			record.updatedAt = os.time()
			return record
		end)
	end)
	if not ok then
		warn(("[QBCore.ManagementService] Roster update failed for %s:%s: %s"):format(organizationType, name, tostring(err)))
	end
	return ok
end

local function readRoster(organizationType, name)
	local record
	local ok, err = pcall(function()
		record = rosterStore:GetAsync(rosterKey(organizationType, name))
	end)
	if not ok then
		warn(("[QBCore.ManagementService] Roster read failed for %s:%s: %s"):format(organizationType, name, tostring(err)))
		return nil, "The organization roster is temporarily unavailable."
	end
	return type(record) == "table" and type(record.members) == "table" and record.members or {}
end

local function syncMembership(playerObj, citizenId)
	if not playerObj or citizenId == "" then return false end
	local current = {
		job = tostring((organizationData(playerObj, "job") or {}).name or "unemployed"),
		crew = tostring((organizationData(playerObj, "crew") or {}).name or "none"),
	}
	local previous
	local ok, err = pcall(function()
		memberIndexStore:UpdateAsync(citizenId, function(record)
			previous = type(record) == "table" and record or {}
			return { job = current.job, crew = current.crew, updatedAt = os.time() }
		end)
	end)
	if not ok then
		warn(("[QBCore.ManagementService] Member index update failed for %s: %s"):format(citizenId, tostring(err)))
		return false
	end
	for _, organizationType in ipairs({ "job", "crew" }) do
		local oldName = previous and previous[organizationType]
		local newName = current[organizationType]
		if oldName and oldName ~= newName then
			updateRoster(organizationType, oldName, citizenId, nil)
		end
		if validOrganization(organizationType, newName) then
			updateRoster(organizationType, newName, citizenId, memberSnapshot(playerObj, citizenId, organizationType))
		end
	end
	return true
end

local function resolveAccess(player, requestedAccess)
	requestedAccess = type(requestedAccess) == "table" and requestedAccess or {}
	local requestedId = trim(requestedAccess.locationId)
	local root = getRoot(player)
	if not root then return nil, nil, "Your character is unavailable." end
	local maxDistance = math.max(1, tonumber(config().ActionDistance) or 14)
	for index, location in ipairs(config().Locations or {}) do
		local id = trim(location.id)
		if id == "" then id = "management_" .. index end
		local position = locationPosition(location)
		if (requestedId == "" or requestedId == id) and position and (root.Position - position).Magnitude <= maxDistance then
			local organizationType = cleanType(location.type)
			local playerObj = PlayerService.GetPlayer(player.UserId)
			local organization = organizationData(playerObj, organizationType)
			local name = type(organization) == "table" and tostring(organization.name or "") or ""
			if not validOrganization(organizationType, name) or not isBoss(organization) then
				return nil, nil, organizationType == "crew"
					and "Only a crew boss can use crew management."
					or "Only a job boss can use job management."
			end
			local restricted = trim(location.organization)
			if restricted ~= "" and restricted ~= name then
				return nil, nil, "This office belongs to another organization."
			end
			return location, {
				locationId = id,
				type = organizationType,
				organization = name,
			}, nil, playerObj
		end
	end
	return nil, nil, "Move closer to a management office."
end

local function serializeGrades(organizationType, name, actorLevel)
	local grades = {}
	local definition = registry(organizationType)[name]
	for gradeKey, info in pairs(definition and definition.grades or {}) do
		local level = math.max(0, math.floor(tonumber(gradeKey) or 0))
		grades[#grades + 1] = {
			level = level,
			name = tostring(info.name or ("Grade " .. level)),
			isboss = info.isboss == true,
			canAssign = level <= actorLevel,
		}
	end
	table.sort(grades, function(a, b) return a.level < b.level end)
	return grades
end

local function nearbyPlayers(player, organizationType, organizationName)
	local sourceRoot = getRoot(player)
	local nearby = {}
	if not sourceRoot then return nearby end
	local maxDistance = math.max(1, tonumber(config().HireDistance) or 12)
	for userId, targetObj in pairs(PlayerService.Players) do
		local target = Players:GetPlayerByUserId(userId)
		local targetRoot = target and target ~= player and getRoot(target)
		if targetRoot then
			local distance = (sourceRoot.Position - targetRoot.Position).Magnitude
			if distance <= maxDistance then
				local targetOrganization = organizationData(targetObj, organizationType) or {}
				nearby[#nearby + 1] = {
					userId = userId,
					citizenId = findCitizenId(targetObj),
					name = memberName(targetObj),
					distance = math.floor(distance * 10 + 0.5) / 10,
					current = tostring(targetOrganization.label or targetOrganization.name or "None"),
					alreadyMember = targetOrganization.name == organizationName,
				}
			end
		end
	end
	table.sort(nearby, function(a, b) return a.distance < b.distance end)
	return nearby
end

local function buildSnapshot(player, playerObj, access, location)
	local organization = organizationData(playerObj, access.type)
	local definition = registry(access.type)[access.organization] or {}
	local members, rosterErr = readRoster(access.type, access.organization)
	if not members then return nil, rosterErr end
	for citizenId, onlineObj in pairs(PlayerService.PlayersByCitizenId) do
		local onlineOrganization = organizationData(onlineObj, access.type)
		if type(onlineOrganization) == "table" and onlineOrganization.name == access.organization then
			members[citizenId] = memberSnapshot(onlineObj, citizenId, access.type)
			task.spawn(syncMembership, onlineObj, citizenId)
		end
	end
	local serialized = {}
	for citizenId, member in pairs(members) do
		if type(member) == "table" then
			local online = PlayerService.GetPlayerByCitizenId(citizenId) ~= nil
			serialized[#serialized + 1] = {
				citizenId = citizenId,
				name = tostring(member.name or ("Citizen " .. citizenId)),
				grade = math.max(0, math.floor(tonumber(member.grade) or 0)),
				gradeName = tostring(member.gradeName or "Grade 0"),
				isboss = member.isboss == true,
				online = online,
				isSelf = citizenId == findCitizenId(playerObj),
			}
		end
	end
	table.sort(serialized, function(a, b)
		if a.grade == b.grade then return string.lower(a.name) < string.lower(b.name) end
		return a.grade > b.grade
	end)
	local balance, balanceErr = bankingService.GetOrganizationFunds(access.type, access.organization)
	if balance == nil then return nil, balanceErr end
	return {
		access = access,
		location = { id = access.locationId, label = tostring(location.label or "Management") },
		organization = {
			type = access.type,
			name = access.organization,
			label = tostring(organization.label or definition.label or access.organization),
			grade = gradeLevel(organization),
			gradeName = tostring((organization.grade or {}).name or "Boss"),
		},
		balance = balance,
		cash = math.floor(tonumber(playerObj:GetMoney("cash")) or 0),
		grades = serializeGrades(access.type, access.organization, gradeLevel(organization)),
		members = serialized,
		nearby = nearbyPlayers(player, access.type, access.organization),
	}
end

local function memberFromRoster(access, citizenId)
	local onlineObj = PlayerService.GetPlayerByCitizenId(citizenId)
	if onlineObj then
		local organization = organizationData(onlineObj, access.type)
		if type(organization) == "table" and organization.name == access.organization then
			return memberSnapshot(onlineObj, citizenId, access.type), onlineObj
		end
		return nil
	end
	local members = readRoster(access.type, access.organization)
	return members and members[citizenId] or nil, nil
end

local function queueAssignment(citizenId, organizationType, name, grade)
	local ok, err = pcall(function()
		pendingStore:UpdateAsync(citizenId, function(record)
			record = type(record) == "table" and record or {}
			record[organizationType] = { name = name, grade = tostring(grade), queuedAt = os.time() }
			return record
		end)
	end)
	if not ok then
		warn(("[QBCore.ManagementService] Pending assignment failed for %s: %s"):format(citizenId, tostring(err)))
	end
	return ok
end

local function assignOnline(targetObj, organizationType, name, grade)
	local previous = organizationData(targetObj, organizationType) or {}
	local previousName = tostring(previous.name or defaultOrganization(organizationType))
	local previousGrade = tostring((previous.grade or {}).level or 0)
	local ok
	if organizationType == "crew" then
		ok = targetObj:SetCrew(name, tostring(grade))
	else
		ok = targetObj:SetJob(name, tostring(grade))
	end
	if not ok then return false, "That grade does not exist." end
	if targetObj:Save() ~= true then
		if organizationType == "crew" then
			targetObj:SetCrew(previousName, previousGrade)
		else
			targetObj:SetJob(previousName, previousGrade)
		end
		targetObj:Save()
		return false, "The member profile could not be saved; the change was reversed."
	end
	syncMembership(targetObj, findCitizenId(targetObj))
	return true
end

local function applyAssignment(access, citizenId, name, grade, rosterEntry)
	local onlineObj = PlayerService.GetPlayerByCitizenId(citizenId)
	if onlineObj then
		local ok, err = assignOnline(onlineObj, access.type, name, grade)
		return ok, err, false
	end
	if not queueAssignment(citizenId, access.type, name, grade) then
		return false, "The offline change could not be queued.", false
	end
	if validOrganization(access.type, name) then
		local gradeInfo = registry(access.type)[name].grades[tostring(grade)]
		local updated = {
			citizenId = citizenId,
			userId = tonumber(rosterEntry.userId) or 0,
			name = tostring(rosterEntry.name or ("Citizen " .. citizenId)),
			grade = tonumber(grade) or 0,
			gradeName = tostring(gradeInfo and gradeInfo.name or ("Grade " .. tostring(grade))),
			isboss = gradeInfo and gradeInfo.isboss == true or false,
			updatedAt = os.time(),
		}
		updateRoster(access.type, access.organization, citizenId, updated)
	else
		updateRoster(access.type, access.organization, citizenId, nil)
	end
	return true, nil, true
end

local function setGrade(player, playerObj, payload, access)
	local citizenId = trim(payload.citizenId):upper()
	local actorCitizenId = findCitizenId(playerObj)
	if citizenId == "" or citizenId == actorCitizenId then return false, "You cannot change your own grade here." end
	local requestedGrade = tonumber(payload.grade)
	if not requestedGrade or requestedGrade < 0 or requestedGrade ~= math.floor(requestedGrade) then
		return false, "Choose a valid whole-number grade."
	end
	local grade = math.floor(requestedGrade)
	local gradeInfo = registry(access.type)[access.organization].grades[tostring(grade)]
	if not gradeInfo then return false, "That grade does not exist." end
	if grade > gradeLevel(organizationData(playerObj, access.type)) then
		return false, "You cannot assign a grade above your own."
	end
	local member, targetObj = memberFromRoster(access, citizenId)
	if not member then return false, "That citizen is not in your organization." end
	if targetObj and gradeLevel(organizationData(targetObj, access.type)) > gradeLevel(organizationData(playerObj, access.type)) then
		return false, "You cannot manage a higher-ranked member."
	end
	local ok, err, queued = applyAssignment(access, citizenId, access.organization, grade, member)
	if not ok then return false, err end
	if targetObj then targetObj:Notify(("Your %s grade is now %s."):format(access.type, gradeInfo.name), "success", 5000) end
	return true, queued and "Grade change queued for the member's next login." or "Member grade updated."
end

local function fireMember(player, playerObj, payload, access)
	local citizenId = trim(payload.citizenId):upper()
	if citizenId == "" or citizenId == findCitizenId(playerObj) then return false, "You cannot remove yourself." end
	local member, targetObj = memberFromRoster(access, citizenId)
	if not member then return false, "That citizen is not in your organization." end
	if (tonumber(member.grade) or 0) > gradeLevel(organizationData(playerObj, access.type)) then
		return false, "You cannot remove a higher-ranked member."
	end
	local ok, err, queued = applyAssignment(access, citizenId, defaultOrganization(access.type), 0, member)
	if not ok then return false, err end
	if targetObj then targetObj:Notify(("You were removed from %s."):format(access.organization), "error", 5000) end
	return true, queued and "Removal queued for the member's next login." or "Member removed."
end

local function hireMember(player, playerObj, payload, access)
	local targetUserId = math.floor(tonumber(payload.userId) or 0)
	local target = targetUserId > 0 and Players:GetPlayerByUserId(targetUserId) or nil
	local targetObj = target and PlayerService.GetPlayer(targetUserId)
	if not target or target == player or not targetObj then return false, "That player is no longer available." end
	local sourceRoot, targetRoot = getRoot(player), getRoot(target)
	if not sourceRoot or not targetRoot or (sourceRoot.Position - targetRoot.Position).Magnitude > math.max(1, tonumber(config().HireDistance) or 12) then
		return false, "That player is too far away to hire."
	end
	local current = organizationData(targetObj, access.type) or {}
	if current.name == access.organization then return false, "That player is already a member." end
	local ok, err = assignOnline(targetObj, access.type, access.organization, 0)
	if not ok then return false, err end
	targetObj:Notify(("You joined %s."):format((registry(access.type)[access.organization] or {}).label or access.organization), "success", 5000)
	return true, ("Hired %s."):format(memberName(targetObj))
end

local function parseAmount(value)
	local amount = tonumber(value)
	local limit = math.max(1, math.floor(tonumber(config().MaxTransactionAmount) or 1000000))
	if not amount or amount ~= amount or amount == math.huge or amount <= 0 then return nil, "Enter a positive amount." end
	amount = math.floor(amount)
	if amount <= 0 then return nil, "Enter a positive whole-dollar amount." end
	if amount > limit then return nil, ("Transactions are limited to $%d."):format(limit) end
	return amount
end

local function depositFunds(player, playerObj, payload, access)
	local amount, err = parseAmount(payload.amount)
	if not amount then return false, err end
	if (tonumber(playerObj:GetMoney("cash")) or 0) < amount then return false, "You do not have enough cash." end
	if not playerObj:RemoveMoney("cash", amount, "management-deposit") then return false, "The cash could not be removed." end
	local ok, accountErr = bankingService.ChangeOrganizationFunds(access.type, access.organization, amount, {
		kind = "deposit", reason = "Management deposit", counterparty = memberName(playerObj), counterpartyCitizenId = findCitizenId(playerObj),
	})
	if not ok then
		playerObj:AddMoney("cash", amount, "management-deposit-rollback")
		return false, accountErr
	end
	if playerObj:Save() ~= true then
		bankingService.ChangeOrganizationFunds(access.type, access.organization, -amount, { kind = "refund", reason = "Management deposit reversed" })
		playerObj:AddMoney("cash", amount, "management-deposit-save-rollback")
		playerObj:Save()
		return false, "Your profile could not be saved; the deposit was reversed."
	end
	return true, ("Deposited $%d."):format(amount)
end

local function withdrawFunds(player, playerObj, payload, access)
	local amount, err = parseAmount(payload.amount)
	if not amount then return false, err end
	local ok, accountErr = bankingService.ChangeOrganizationFunds(access.type, access.organization, -amount, {
		kind = "withdraw", reason = "Management withdrawal", counterparty = memberName(playerObj), counterpartyCitizenId = findCitizenId(playerObj),
	})
	if not ok then return false, accountErr end
	if not playerObj:AddMoney("cash", amount, "management-withdrawal") then
		bankingService.ChangeOrganizationFunds(access.type, access.organization, amount, { kind = "refund", reason = "Management withdrawal reversed" })
		return false, "The cash withdrawal could not be completed."
	end
	if playerObj:Save() ~= true then
		playerObj:RemoveMoney("cash", amount, "management-withdrawal-save-rollback")
		bankingService.ChangeOrganizationFunds(access.type, access.organization, amount, { kind = "refund", reason = "Management withdrawal reversed" })
		playerObj:Save()
		return false, "Your profile could not be saved; the withdrawal was reversed."
	end
	return true, ("Withdrew $%d."):format(amount)
end

local ACTIONS = {
	set_grade = setGrade,
	fire = fireMember,
	hire = hireMember,
	deposit = depositFunds,
	withdraw = withdrawFunds,
}

local function createInteractions()
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if folder and not folder:IsA("Folder") then
		warn(("[QBCore.ManagementService] Workspace.%s must be a Folder."):format(FOLDER_NAME))
		return
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = Workspace
	end
	for index, location in ipairs(config().Locations or {}) do
		local position = locationPosition(location)
		if position then
			local id = trim(location.id)
			if id == "" then id = "management_" .. index end
			local part = Instance.new("Part")
			part.Name = "Management_" .. id:gsub("[^%w_]", "_")
			part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
			part.CastShadow, part.Transparency, part.Size, part.Position = false, 1, Vector3.new(2, 2, 2), position
			part.Parent = folder
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "ManagementPrompt"
			prompt.ActionText = cleanType(location.type) == "crew" and "Manage Crew" or "Manage Employees"
			prompt.ObjectText = tostring(location.label or "Management")
			prompt.KeyboardKeyCode, prompt.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
			prompt.HoldDuration = 0.15
			prompt.MaxActivationDistance = math.max(1, tonumber(config().PromptDistance) or 10)
			prompt.RequiresLineOfSight = false
			prompt.Parent = part
			prompt.Triggered:Connect(function(player)
				local resolved, access = resolveAccess(player, { locationId = id })
				if resolved and access then Remotes.OpenManagement:FireClient(player, access) end
			end)
		else
			warn(("[QBCore.ManagementService] Location %d has no valid position."):format(index))
		end
	end
end

function ManagementService.OnCharacterLoaded(player, playerObj)
	if not playerObj then return end
	local citizenId = findCitizenId(playerObj)
	if citizenId == "" then return end
	local pending
	local readOk, readErr = pcall(function() pending = pendingStore:GetAsync(citizenId) end)
	if not readOk then
		warn(("[QBCore.ManagementService] Pending read failed for %s: %s"):format(citizenId, tostring(readErr)))
	else
		local changed = false
		for _, organizationType in ipairs({ "job", "crew" }) do
			local assignment = type(pending) == "table" and pending[organizationType] or nil
			if type(assignment) == "table" then
				local ok
				if organizationType == "crew" then
					ok = playerObj:SetCrew(tostring(assignment.name), tostring(assignment.grade))
				else
					ok = playerObj:SetJob(tostring(assignment.name), tostring(assignment.grade))
				end
				changed = ok or changed
			end
		end
		if changed and playerObj:Save() == true then
			pcall(function() pendingStore:RemoveAsync(citizenId) end)
			playerObj:Notify("An offline management change was applied.", "primary", 5000)
		end
	end
	syncMembership(playerObj, citizenId)
end

function ManagementService.Start(service)
	if started then return end
	assert(type(service) == "table" and type(service.GetOrganizationFunds) == "function", "ManagementService requires BankingService")
	bankingService = service
	started = true
	Remotes.GetManagement.OnServerInvoke = function(player, requestedAccess)
		if config().Enabled == false then return nil, "Management is currently unavailable." end
		local location, access, err, playerObj = resolveAccess(player, requestedAccess)
		if not location then return nil, err end
		return buildSnapshot(player, playerObj, access, location)
	end
	Remotes.ManagementAction.OnServerInvoke = function(player, action, payload)
		if config().Enabled == false then return false, "Management is currently unavailable." end
		payload = type(payload) == "table" and payload or {}
		local location, access, err, playerObj = resolveAccess(player, payload.access)
		if not location then return false, err end
		local now = os.clock()
		if now - (lastActionAt[player] or 0) < ACTION_COOLDOWN then return false, "Please wait before submitting another action." end
		lastActionAt[player] = now
		action = type(action) == "string" and string.lower(action) or ""
		local handler = ACTIONS[action]
		if not handler then return false, "Unknown management action." end
		if actionBusy[player] then return false, "Another management action is already running." end
		actionBusy[player] = true
		local handlerOk, ok, message = pcall(handler, player, playerObj, payload, access)
		actionBusy[player] = nil
		if not handlerOk then
			warn(("[QBCore.ManagementService] %s failed for %s: %s"):format(action, player.Name, tostring(ok)))
			return false, "The management action could not be completed."
		end
		if not ok then return false, message end
		local snapshot, snapshotErr = buildSnapshot(player, playerObj, access, location)
		if not snapshot then return false, snapshotErr end
		return true, { message = message, snapshot = snapshot }
	end
	Players.PlayerRemoving:Connect(function(player)
		lastActionAt[player], actionBusy[player] = nil, nil
	end)
	if config().Enabled ~= false then createInteractions() end
end

return ManagementService
