-- Roblox-native qb-cityhall port: nearby public-job selection and document orders.
-- Every mutation is authorized from server-owned config and current player state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local QBShared = require(ReplicatedStorage.QBShared.Main)
local Remotes = require(ReplicatedStorage.QBRemotes)
local PlayerService = require(script.Parent.PlayerService)

local CityHallService = {}

local FOLDER_NAME = "QBCityHallInteractions"
local ACTION_COOLDOWN = 0.35

local inventoryService
local started = false
local actionBusy = {}
local lastActionAt = {}

local function config()
	return type(QBShared.Config.CityHall) == "table" and QBShared.Config.CityHall or {}
end

local function trim(value)
	return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

local function vectorFrom(value)
	if typeof(value) == "Vector3" then
		return value
	end
	if type(value) == "table" then
		local x = tonumber(value.x or value.X)
		local y = tonumber(value.y or value.Y)
		local z = tonumber(value.z or value.Z)
		if x and y and z then
			return Vector3.new(x, y, z)
		end
	end
	return nil
end

local function getRoot(player)
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function findLocation(id)
	id = trim(id)
	for _, location in ipairs(config().Locations or {}) do
		if trim(location.id) == id then
			return location
		end
	end
	return nil
end

local function resolveAccess(player, playerObj, requestedAccess)
	if config().Enabled == false then
		return nil, nil, "City Hall is currently closed."
	end
	if not playerObj then
		return nil, nil, "Load a character before using City Hall."
	end
	if playerObj:GetMetaData("isdead") == true then
		return nil, nil, "You cannot use City Hall while dead."
	end

	local locationId = type(requestedAccess) == "table" and trim(requestedAccess.locationId) or ""
	local location = findLocation(locationId)
	if not location then
		return nil, nil, "That City Hall location does not exist."
	end

	local position = vectorFrom(location.position)
	local root = getRoot(player)
	local maxDistance = math.max(1, tonumber(config().ActionDistance) or 14)
	if not position or not root or (root.Position - position).Magnitude > maxDistance then
		return nil, nil, "Move closer to the City Hall counter."
	end

	return location, { locationId = locationId }
end

local function licensesFor(playerObj)
	local metadata = type(playerObj.PlayerData.metadata) == "table" and playerObj.PlayerData.metadata or {}
	return type(metadata.licences) == "table" and metadata.licences or {}
end

local function documentIsEligible(playerObj, document)
	local requirement = trim(document.requiredLicense)
	return requirement == "" or licensesFor(playerObj)[requirement] == true
end

local function documentByName(name)
	name = trim(name):lower()
	for _, document in ipairs(config().Documents or {}) do
		if trim(document.name):lower() == name then
			return document
		end
	end
	return nil
end

local function availableJobNames()
	local result = {}
	local seen = {}
	local restricted = type(config().RestrictedJobs) == "table" and config().RestrictedJobs or {}
	for _, configuredName in ipairs(config().AvailableJobs or {}) do
		local name = trim(configuredName):lower()
		if name ~= "" and not seen[name] and restricted[name] ~= true and QBShared.Jobs[name] then
			seen[name] = true
			table.insert(result, name)
		end
	end
	return result
end

local function jobIsAvailable(name)
	name = trim(name):lower()
	for _, availableName in ipairs(availableJobNames()) do
		if availableName == name then
			return true
		end
	end
	return false
end

local function buildSnapshot(playerObj, location, access)
	local documents = {}
	for _, document in ipairs(config().Documents or {}) do
		local name = trim(document.name):lower()
		local item = QBShared.Items[name]
		if name ~= "" and item and documentIsEligible(playerObj, document) then
			table.insert(documents, {
				name = name,
				label = tostring(document.label or item.label or name),
				cost = math.max(0, math.floor(tonumber(document.cost) or 0)),
			})
		end
	end

	local jobs = {}
	for _, name in ipairs(availableJobNames()) do
		local job = QBShared.Jobs[name]
		table.insert(jobs, {
			name = name,
			label = tostring(job.label or name),
		})
	end

	return {
		access = access,
		label = tostring(location.label or "City Hall"),
		documents = documents,
		jobs = jobs,
	}
end

local function documentInfo(playerObj, itemName)
	local data = playerObj.PlayerData
	local charinfo = type(data.charinfo) == "table" and data.charinfo or {}
	if itemName == "id_card" then
		return {
			citizenid = data.citizenid,
			firstname = charinfo.firstname,
			lastname = charinfo.lastname,
			birthdate = charinfo.birthdate,
			gender = charinfo.gender,
			nationality = charinfo.nationality,
		}
	elseif itemName == "driver_license" then
		return {
			firstname = charinfo.firstname,
			lastname = charinfo.lastname,
			birthdate = charinfo.birthdate,
			type = "Class C Driver License",
		}
	elseif itemName == "weaponlicense" then
		return {
			firstname = charinfo.firstname,
			lastname = charinfo.lastname,
			birthdate = charinfo.birthdate,
		}
	end
	return nil
end

local function orderDocument(playerObj, payload)
	local itemName = type(payload) == "table" and trim(payload.document):lower() or ""
	local document = documentByName(itemName)
	local definition = document and QBShared.Items[itemName] or nil
	local info = document and documentInfo(playerObj, itemName) or nil
	if not document or not definition or not info then
		return false, "That document is unavailable."
	end
	if not documentIsEligible(playerObj, document) then
		return false, "You are not eligible for that license."
	end

	local cost = math.max(0, math.floor(tonumber(document.cost) or 0))
	local canAdd, canAddErr = inventoryService.CanAddItem(playerObj, itemName, 1, nil, info)
	if not canAdd then
		return false, canAddErr or "You cannot carry that document."
	end
	if (tonumber(playerObj:GetMoney("cash")) or 0) < cost then
		return false, ("You need $%d cash to order this document."):format(cost)
	end

	if not playerObj:RemoveMoney("cash", cost, "cityhall-document") then
		return false, "The payment could not be completed."
	end
	local added, addErr = inventoryService.AddItem(playerObj, itemName, 1, nil, info, "cityhall-document")
	if not added then
		playerObj:AddMoney("cash", cost, "cityhall-document-rollback")
		return false, addErr or "The document could not be added to your inventory."
	end
	-- Keep the successful in-memory mutation if this immediate write is throttled;
	-- PlayerService's normal autosave/release path will retry without clobbering a
	-- different inventory action that may run while DataStore UpdateAsync yields.
	playerObj:Save()

	local label = tostring(document.label or definition.label or itemName)
	return true, ("Received %s for $%d."):format(label, cost)
end

local function selectJob(playerObj, payload)
	local name = type(payload) == "table" and trim(payload.job):lower() or ""
	if not jobIsAvailable(name) then
		return false, "That job cannot be selected at City Hall."
	end
	local job = QBShared.Jobs[name]
	if not job then
		return false, "That job is unavailable."
	end

	if not playerObj:SetJob(name, "0") then
		return false, "The job could not be assigned."
	end
	playerObj:Save()

	return true, ("You are now employed as %s."):format(tostring(job.label or name))
end

local ACTIONS = {
	order_document = orderDocument,
	select_job = selectJob,
}

local function safePartName(id, index)
	local value = trim(id):gsub("[^%w_%-]", "_")
	return value ~= "" and value or ("CityHall_%d"):format(index)
end

local function createInteraction(location, index, folder)
	local id = trim(location.id)
	local position = vectorFrom(location.position)
	if id == "" or not position then
		warn(("[QBCore.CityHallService] Location %d needs a unique id and Vector3 position."):format(index))
		return
	end

	local part = folder:FindFirstChild(safePartName(id, index))
	if part and not part:IsA("BasePart") then
		warn(("[QBCore.CityHallService] %s must be a BasePart."):format(part:GetFullName()))
		return
	end
	if not part then
		part = Instance.new("Part")
		part.Name = safePartName(id, index)
		part.Parent = folder
	end
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.CastShadow, part.Transparency, part.Size, part.Position = false, 1, Vector3.new(2, 2, 2), position

	local prompt = part:FindFirstChild("CityHallPrompt")
	if prompt and not prompt:IsA("ProximityPrompt") then
		warn(("[QBCore.CityHallService] %s.CityHallPrompt must be a ProximityPrompt."):format(part:GetFullName()))
		return
	end
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CityHallPrompt"
		prompt.Parent = part
	end
	prompt.ActionText = "Open City Services"
	prompt.ObjectText = tostring(location.label or "City Hall")
	prompt.KeyboardKeyCode, prompt.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = math.max(1, tonumber(config().PromptDistance) or 10)
	prompt.RequiresLineOfSight = false
	prompt.Enabled = config().Enabled ~= false
	prompt.Triggered:Connect(function(player)
		local playerObj = PlayerService.GetPlayer(player.UserId)
		local resolved, access, err = resolveAccess(player, playerObj, { locationId = id })
		if resolved then
			Remotes.OpenCityHall:FireClient(player, access)
		elseif playerObj then
			playerObj:Notify(err or "City Hall is unavailable.", "error", 3500)
		end
	end)
end

local function createInteractions()
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if folder and not folder:IsA("Folder") then
		warn(("[QBCore.CityHallService] Workspace.%s must be a Folder."):format(FOLDER_NAME))
		return
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = Workspace
	end
	for index, location in ipairs(config().Locations or {}) do
		createInteraction(location, index, folder)
	end
end

function CityHallService.Start(InventoryService)
	if started then
		return
	end
	assert(type(InventoryService) == "table", "CityHallService.Start requires InventoryService")
	inventoryService = InventoryService
	started = true

	Remotes.GetCityHall.OnServerInvoke = function(player, requestedAccess)
		local playerObj = PlayerService.GetPlayer(player.UserId)
		local location, access, err = resolveAccess(player, playerObj, requestedAccess)
		if not location then
			return nil, err
		end
		return buildSnapshot(playerObj, location, access)
	end

	Remotes.CityHallAction.OnServerInvoke = function(player, action, payload)
		local playerObj = PlayerService.GetPlayer(player.UserId)
		payload = type(payload) == "table" and payload or {}
		local location, access, err = resolveAccess(player, playerObj, payload.access)
		if not location then
			return false, err
		end

		local now = os.clock()
		if now - (lastActionAt[player] or 0) < ACTION_COOLDOWN then
			return false, "Please wait before submitting another City Hall request."
		end
		lastActionAt[player] = now
		action = type(action) == "string" and action:lower() or ""
		local handler = ACTIONS[action]
		if not handler then
			return false, "That City Hall action is not supported."
		end
		if actionBusy[player] then
			return false, "A City Hall request is already in progress."
		end

		actionBusy[player] = true
		local handlerOk, ok, message = pcall(handler, playerObj, payload, location, access)
		actionBusy[player] = nil
		if not handlerOk then
			warn(("[QBCore.CityHallService] %s failed for %s: %s"):format(action, player.Name, tostring(ok)))
			return false, "The City Hall request could not be completed."
		end
		if ok then
			playerObj:Notify(tostring(message), "success", 4000)
		end
		return ok, message
	end

	Players.PlayerRemoving:Connect(function(player)
		actionBusy[player] = nil
		lastActionAt[player] = nil
	end)

	createInteractions()
end

return CityHallService
