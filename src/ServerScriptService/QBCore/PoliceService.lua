-- Server-authoritative Roblox adaptation of qb-policejob's station POIs.
-- The service owns duty, armory, locker, trash, fingerprint, evidence, fleet,
-- impound, helicopter, and station-marker interactions. Every action rechecks
-- job, duty, station, and distance on the server.

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
local PoliceService = {}

local INTERACTION_FOLDER_NAME = "QBPoliceJobLocations"
local started = false
local inventoryService = nil
local vehicleService = nil
local sharedContainers = {}
local jobVehicles = {}
local requestBusy = {}

local function config()
	return type(QBShared.Config.PoliceJob) == "table" and QBShared.Config.PoliceJob or {}
end

local function trim(value)
	return type(value) == "string" and (value:match("^%s*(.-)%s*$") or "") or ""
end

local function vectorFrom(value)
	if typeof(value) == "Vector3" then
		return value
	end
	if type(value) ~= "table" then
		return nil
	end
	local source = value.position or value.coords or value
	if typeof(source) == "Vector3" then
		return source
	end
	if type(source) == "table" then
		local x = tonumber(source.x or source.X)
		local y = tonumber(source.y or source.Y)
		local z = tonumber(source.z or source.Z)
		if x and y and z then
			return Vector3.new(x, y, z)
		end
	end
	return nil
end

local function cframeFrom(value)
	if typeof(value) == "CFrame" then
		return value
	end
	local position = vectorFrom(value)
	if not position then
		return nil
	end
	local heading = type(value) == "table" and tonumber(value.heading or value.ry or value.w) or 0
	return CFrame.new(position) * CFrame.Angles(0, math.rad(heading or 0), 0)
end

local function getRoot(player)
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function closeTo(player, point, maxDistance)
	local root = getRoot(player)
	local position = vectorFrom(point)
	return root ~= nil and position ~= nil and (root.Position - position).Magnitude <= maxDistance
end

local function gradeLevel(playerObj)
	local job = playerObj and playerObj.PlayerData and playerObj.PlayerData.job
	return type(job) == "table" and type(job.grade) == "table" and math.floor(tonumber(job.grade.level) or 0) or 0
end

local function isPoliceEmployee(playerObj)
	local job = playerObj and playerObj.PlayerData and playerObj.PlayerData.job
	return type(job) == "table" and (job.name == "police" or job.type == "leo")
end

local function isOnDutyPolice(playerObj)
	local job = playerObj and playerObj.PlayerData and playerObj.PlayerData.job
	return isPoliceEmployee(playerObj) and job.onduty == true
end

local function stationById(stationId)
	stationId = trim(stationId)
	for _, station in ipairs(config().Stations or {}) do
		if trim(station.id) == stationId then
			return station
		end
	end
	return nil
end

local function pointAt(station, kind, index)
	local points = station and station[kind]
	return type(points) == "table" and points[math.floor(tonumber(index) or 0)] or nil
end

local function ensureFingerprint(playerObj)
	local existing = trim(playerObj:GetMetaData("fingerprint"))
	if existing ~= "" then
		return existing
	end
	local source = tostring(playerObj.PlayerData.citizenid or "UNKNOWN")
	local hash = 5381
	for index = 1, #source do
		hash = (hash * 33 + string.byte(source, index)) % 4294967296
	end
	local fingerprint = ("FGR%08X"):format(hash)
	playerObj:SetMetaData("fingerprint", fingerprint)
	playerObj:Save()
	return fingerprint
end

local function closestOtherPlayer(player, maxDistance)
	local root = getRoot(player)
	if not root then
		return nil
	end
	local closest, closestDistance = nil, maxDistance
	for _, candidate in ipairs(Players:GetPlayers()) do
		if candidate ~= player then
			local candidateRoot = getRoot(candidate)
			if candidateRoot then
				local distance = (candidateRoot.Position - root.Position).Magnitude
				if distance <= closestDistance then
					closest, closestDistance = candidate, distance
				end
			end
		end
	end
	return closest
end

local function copyInfo(info)
	local copy = {}
	if type(info) == "table" then
		for key, value in pairs(info) do
			copy[key] = type(value) == "table" and table.clone(value) or value
		end
	end
	return copy
end

local function deepEqual(left, right)
	if type(left) ~= type(right) then
		return false
	end
	if type(left) ~= "table" then
		return left == right
	end
	for key, value in pairs(left) do
		if not deepEqual(value, right[key]) then
			return false
		end
	end
	for key in pairs(right) do
		if left[key] == nil then
			return false
		end
	end
	return true
end

local function itemDefinition(name)
	return type(name) == "string" and QBShared.Items[name:lower()] or nil
end

local function containerSlots()
	return math.max(1, math.floor(tonumber(config().ContainerSlots) or 30))
end

local function getContainer(playerObj, stationId, kind, drawer)
	if kind == "stash" then
		playerObj.PlayerData.policeStashes = type(playerObj.PlayerData.policeStashes) == "table"
			and playerObj.PlayerData.policeStashes
			or {}
		local stashes = playerObj.PlayerData.policeStashes
		stashes[stationId] = type(stashes[stationId]) == "table" and stashes[stationId] or {}
		return stashes[stationId]
	end
	local key = kind == "evidence" and ("evidence:%s:%d"):format(stationId, drawer) or ("trash:%s"):format(stationId)
	sharedContainers[key] = type(sharedContainers[key]) == "table" and sharedContainers[key] or {}
	return sharedContainers[key]
end

local function containerWeight(container)
	local total = 0
	for _, item in pairs(container) do
		local definition = itemDefinition(item.name)
		if definition then
			total += (tonumber(definition.weight) or 0) * math.max(0, math.floor(tonumber(item.amount) or 0))
		end
	end
	return total
end

local function findContainerSlot(container, name, info)
	local firstFree = nil
	for slot = 1, containerSlots() do
		local item = container[tostring(slot)] or container[slot]
		if not item and not firstFree then
			firstFree = slot
		elseif
			item
			and item.name == name
			and itemDefinition(name)
			and itemDefinition(name).unique ~= true
			and deepEqual(item.info or {}, info or {})
		then
			return slot, item
		end
	end
	return firstFree, nil
end

local function addToContainer(container, item, amount)
	local definition = itemDefinition(item and item.name)
	amount = math.floor(tonumber(amount) or 0)
	if not definition or amount < 1 then
		return false, "Invalid item."
	end
	local maxWeight = math.max(0, tonumber(config().ContainerMaxWeight) or 250000)
	if containerWeight(container) + (tonumber(definition.weight) or 0) * amount > maxWeight then
		return false, "That container is full."
	end
	local slot, existing = findContainerSlot(container, definition.name, item.info)
	if not slot then
		return false, "That container has no free slots."
	end
	if existing then
		existing.amount = math.floor(tonumber(existing.amount) or 0) + amount
		container[tostring(slot)] = existing
	else
		container[tostring(slot)] = {
			name = definition.name,
			amount = amount,
			slot = slot,
			info = copyInfo(item.info),
		}
	end
	return true, slot
end

local function removeFromContainer(container, slot, amount)
	slot = math.floor(tonumber(slot) or 0)
	amount = math.floor(tonumber(amount) or 0)
	local key = tostring(slot)
	local item = container[key] or container[slot]
	if not item or amount < 1 or amount > (tonumber(item.amount) or 0) then
		return nil, "That container does not have enough items."
	end
	local removed = {
		name = item.name,
		amount = amount,
		info = copyInfo(item.info),
	}
	item.amount -= amount
	if item.amount <= 0 then
		container[key], container[slot] = nil, nil
	else
		container[key] = item
	end
	return removed
end

local function resolveContainer(player, playerObj, access)
	if config().Enabled == false or not isOnDutyPolice(playerObj) then
		return nil, nil, "Only on-duty law enforcement can use this container."
	end
	local stationId = type(access) == "table" and trim(access.stationId) or ""
	local kind = type(access) == "table" and trim(access.kind):lower() or ""
	local index = type(access) == "table" and math.floor(tonumber(access.index) or 0) or 0
	local station = stationById(stationId)
	local point = station and pointAt(station, kind, index)
	if not station or not point or (kind ~= "stash" and kind ~= "trash" and kind ~= "evidence") then
		return nil, nil, "That police container does not exist."
	end
	if not closeTo(player, point, math.max(1, tonumber(config().ActionDistance) or 14)) then
		return nil, nil, "Move closer to the police container."
	end
	local drawer = kind == "evidence" and math.max(1, math.floor(tonumber(point.drawer) or index)) or 0
	return getContainer(playerObj, stationId, kind, drawer), {
		type = "police_container",
		stationId = stationId,
		kind = kind,
		index = index,
		drawer = drawer,
	}, station
end

local function containerSnapshot(player, playerObj, access)
	local container, normalized, stationOrError = resolveContainer(player, playerObj, access)
	if not container then
		return nil, nil, stationOrError
	end
	local items = {}
	for slot = 1, containerSlots() do
		local stored = container[tostring(slot)] or container[slot]
		local definition = itemDefinition(stored and stored.name)
		if definition and (tonumber(stored.amount) or 0) > 0 then
			items[tostring(slot)] = {
				name = definition.name,
				label = definition.label or definition.name,
				amount = stored.amount,
				stock = stored.amount,
				slot = slot,
				info = copyInfo(stored.info),
				weight = tonumber(definition.weight) or 0,
				type = definition.type or "item",
				image = definition.image or "",
				unique = definition.unique == true,
				useable = false,
				shouldClose = false,
				description = definition.description or "",
				price = 0,
			}
		end
	end
	local kindLabel = normalized.kind == "stash" and "Personal Locker"
		or normalized.kind == "trash" and "Police Trash"
		or ("Evidence Drawer %d"):format(normalized.drawer)
	return {
		type = "container",
		id = ("%s:%s:%d"):format(normalized.stationId, normalized.kind, normalized.drawer),
		label = ("%s | %s"):format(tostring(stationOrError.label or "Police"), kindLabel),
		items = items,
		slots = containerSlots(),
		maxWeight = math.max(0, tonumber(config().ContainerMaxWeight) or 250000),
		totalWeight = containerWeight(container),
		readOnly = false,
		actions = { purchase = false, withdraw = true, deposit = true },
	}, normalized
end

local function handleContainerAction(player, playerObj, action, payload)
	local container, normalized, err = resolveContainer(player, playerObj, payload.access)
	if not container then
		return false, err
	end
	local amount = math.floor(tonumber(payload.amount) or 0)
	if amount < 1 or amount > 999 then
		return false, "Invalid transfer amount."
	end
	if action == "withdraw" then
		local slot = math.floor(tonumber(payload.slot) or 0)
		local stored = container[tostring(slot)] or container[slot]
		if not stored or amount > (tonumber(stored.amount) or 0) then
			return false, "That container does not have enough items."
		end
		local canAdd, canAddErr = inventoryService.CanAddItem(playerObj, stored.name, amount, nil, stored.info)
		if not canAdd then
			return false, canAddErr
		end
		local removed = removeFromContainer(container, slot, amount)
		local added, addErr = inventoryService.AddItem(playerObj, removed.name, amount, nil, removed.info, "police-container-withdraw")
		if not added then
			addToContainer(container, removed, amount)
			return false, addErr or "The item could not be withdrawn."
		end
	elseif action == "deposit" then
		local playerSlot = math.floor(tonumber(payload.playerSlot) or 0)
		local item = inventoryService.GetItemBySlot(playerObj, playerSlot)
		if not item or amount > (tonumber(item.amount) or 0) then
			return false, "Your inventory does not have enough items in that slot."
		end
		local added, addErr = addToContainer(container, item, amount)
		if not added then
			return false, addErr
		end
		local removed, removeErr = inventoryService.RemoveItem(playerObj, item.name, amount, playerSlot, "police-container-deposit")
		if not removed then
			removeFromContainer(container, addErr, amount)
			return false, removeErr or "The item could not be deposited."
		end
	else
		return false, "That container action is not supported."
	end
	if normalized.kind == "stash" then
		playerObj:Save()
	end
	return true, inventoryService.GetOpenSnapshot(playerObj, player, normalized)
end

local function vehicleChoices(playerObj, station, key)
	local result = {}
	for _, entry in ipairs(type(station[key]) == "table" and station[key] or {}) do
		if type(entry) == "table" and gradeLevel(playerObj) >= math.max(0, math.floor(tonumber(entry.minGrade) or 0)) then
			table.insert(result, { name = trim(entry.name), label = tostring(entry.label or entry.name) })
		end
	end
	return result
end

local function resolveFleetAccess(player, playerObj, access, kind)
	if not isOnDutyPolice(playerObj) then
		return nil, "Only on-duty law enforcement can use the police fleet."
	end
	local station = stationById(type(access) == "table" and access.stationId)
	local index = type(access) == "table" and math.floor(tonumber(access.index) or 0) or 0
	local point = station and pointAt(station, kind, index)
	if not station or not point or not closeTo(player, point, math.max(1, tonumber(config().ActionDistance) or 14)) then
		return nil, "Move closer to the police fleet point."
	end
	return station
end

local function spawnFleetVehicle(player, playerObj, payload, kind)
	local station, err = resolveFleetAccess(player, playerObj, payload.access, kind)
	if not station then
		return false, err
	end
	local listKey = kind == "helicopter" and "authorizedHelicopters" or "authorizedVehicles"
	local spawnKey = kind == "helicopter" and "helicopterSpawn" or "vehicleSpawn"
	local requested = trim(payload.vehicle)
	local authorized = nil
	for _, entry in ipairs(vehicleChoices(playerObj, station, listKey)) do
		if entry.name == requested then
			authorized = entry
			break
		end
	end
	if not authorized then
		return false, "That fleet vehicle is not authorized for your grade."
	end
	local spawnCFrame = cframeFrom(station[spawnKey])
	if not spawnCFrame then
		return false, "This station does not have a valid fleet spawn."
	end
	local previous = jobVehicles[player]
	if previous and previous.Parent then
		previous:Destroy()
	end
	local vehicle, definitionOrError = vehicleService.SpawnVehicle(player, authorized.name, {
		cframe = spawnCFrame,
		attributes = { QBPoliceJobVehicle = true, QBPoliceStationId = trim(station.id) },
	})
	if not vehicle then
		return false, definitionOrError or "The fleet vehicle could not be spawned."
	end
	jobVehicles[player] = vehicle
	return true, ("%s is ready at the station."):format(authorized.label)
end

local function impoundClosestVehicle(player, playerObj, station, point)
	if not isOnDutyPolice(playerObj) then
		return false, "Only on-duty law enforcement can impound vehicles."
	end
	local folder = vehicleService.GetSpawnedFolder()
	local pointPosition = vectorFrom(point)
	local closest, closestDistance = nil, math.max(1, tonumber(config().ImpoundDistance) or 24)
	for _, vehicle in ipairs(folder:GetChildren()) do
		local position = vehicleService.GetVehiclePosition(vehicle)
		if position then
			local distance = (position - pointPosition).Magnitude
			if distance <= closestDistance then
				closest, closestDistance = vehicle, distance
			end
		end
	end
	if not closest then
		return false, "No vehicle is close enough to the impound point."
	end
	local ownershipId = trim(closest:GetAttribute("QBOwnedVehicleId"))
	local ownerUserId = tonumber(closest:GetAttribute("QBOwnerUserId"))
	if ownershipId ~= "" and ownerUserId then
		local ownerObj = PlayerService.GetPlayer(ownerUserId)
		for _, ownership in pairs(ownerObj and ownerObj.PlayerData.vehicles or {}) do
			if type(ownership) == "table" and tostring(ownership.id or ownership.ownershipId or "") == ownershipId then
				ownership.state = 2
				ownership.impound = trim(station.id)
				ownerObj:Save()
				break
			end
		end
	end
	local label = tostring(closest:GetAttribute("QBVehicleLabel") or closest.Name)
	closest:Destroy()
	return true, ("%s was impounded."):format(label)
end

local function safeName(value)
	local result = trim(value):gsub("[^%w_%-]", "_")
	return result ~= "" and result or "Police"
end

local function createInteraction(folder, station, stationIndex, kind, point, pointIndex, actionText, callback)
	local position = vectorFrom(point)
	if not position then
		warn(("[QBCore.PoliceService] Invalid %s point %d for station %d."):format(kind, pointIndex, stationIndex))
		return
	end
	local name = ("%s_%s_%d"):format(safeName(station.id), kind, pointIndex)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.CastShadow, part.Transparency, part.Size = false, 1, Vector3.new(2, 2, 2)
	part.CFrame = cframeFrom(point) or CFrame.new(position)
	part:SetAttribute("QBPoliceStationId", trim(station.id))
	part:SetAttribute("QBPoliceStationLabel", tostring(station.label or "Police Station"))
	part:SetAttribute("QBPolicePOI", kind)
	part.Parent = folder

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PolicePrompt"
	prompt.ActionText = actionText
	prompt.ObjectText = tostring(station.label or "Police Station")
	prompt.KeyboardKeyCode, prompt.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
	prompt.HoldDuration = kind == "Impound" and 1 or 0.15
	prompt.MaxActivationDistance = math.max(1, tonumber(config().PromptDistance) or 10)
	prompt.RequiresLineOfSight = false
	prompt.Enabled = config().Enabled ~= false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		local playerObj = PlayerService.GetPlayer(player.UserId)
		if not playerObj then
			return
		end
		if not closeTo(player, point, math.max(1, tonumber(config().ActionDistance) or 14)) then
			playerObj:Notify("Move closer to the police point.", "error", 3500)
			return
		end
		callback(player, playerObj)
	end)
end

local function requireOnDuty(playerObj)
	if isOnDutyPolice(playerObj) then
		return true
	end
	playerObj:Notify("Only on-duty law enforcement can use this point.", "error", 3500)
	return false
end

local function createStationInteractions(folder, station, stationIndex)
	local stationId = trim(station.id)
	for index, point in ipairs(station.duty or {}) do
		createInteraction(folder, station, stationIndex, "Duty", point, index, "Toggle Duty", function(_, playerObj)
			if not isPoliceEmployee(playerObj) then
				playerObj:Notify("Only law-enforcement employees can use this duty point.", "error", 3500)
				return
			end
			local nextDuty = playerObj.PlayerData.job.onduty ~= true
			playerObj:SetJobDuty(nextDuty)
			playerObj:Save()
			playerObj:Notify(nextDuty and "You are now on duty." or "You are now off duty.", "success", 3500)
		end)
	end
	for index, point in ipairs(station.armory or {}) do
		createInteraction(folder, station, stationIndex, "Armory", point, index, "Open Armory", function(player, playerObj)
			if requireOnDuty(playerObj) then
				Remotes.OpenInventory:FireClient(player, { type = "shop", id = trim(point.shopId) })
			end
		end)
	end
	for _, kind in ipairs({ "stash", "trash", "evidence" }) do
		for index, point in ipairs(station[kind] or {}) do
			local action = kind == "stash" and "Open Locker" or kind == "trash" and "Open Trash" or "Open Evidence"
			createInteraction(folder, station, stationIndex, kind:gsub("^%l", string.upper), point, index, action, function(player, playerObj)
				if requireOnDuty(playerObj) then
					Remotes.OpenInventory:FireClient(player, {
						type = "police_container",
						stationId = stationId,
						kind = kind,
						index = index,
					})
				end
			end)
		end
	end
	for index, point in ipairs(station.fingerprint or {}) do
		createInteraction(folder, station, stationIndex, "Fingerprint", point, index, "Scan Fingerprint", function(player, playerObj)
			if not requireOnDuty(playerObj) then
				return
			end
			local target = closestOtherPlayer(player, math.max(1, tonumber(config().FingerprintDistance) or 12))
			local targetObj = target and PlayerService.GetPlayer(target.UserId)
			if not targetObj then
				playerObj:Notify("Bring another player to the fingerprint scanner.", "error", 3500)
				return
			end
			Remotes.OpenPoliceJob:FireClient(player, {
				view = "fingerprint",
				label = tostring(station.label or "Police Station"),
				fingerprint = ensureFingerprint(targetObj),
				name = targetObj:GetName(),
				citizenId = tostring(targetObj.PlayerData.citizenid or "Unknown"),
			})
		end)
	end
	for _, fleetKind in ipairs({ "vehicle", "helicopter" }) do
		for index, point in ipairs(station[fleetKind] or {}) do
			local isHelicopter = fleetKind == "helicopter"
			createInteraction(
				folder,
				station,
				stationIndex,
				isHelicopter and "Helicopter" or "Vehicle",
				point,
				index,
				isHelicopter and "Open Air Support" or "Open Police Garage",
				function(player, playerObj)
					if not requireOnDuty(playerObj) then
						return
					end
					Remotes.OpenPoliceJob:FireClient(player, {
						view = "fleet",
						fleetKind = fleetKind,
						label = tostring(station.label or "Police Station"),
						vehicles = vehicleChoices(
							playerObj,
							station,
							isHelicopter and "authorizedHelicopters" or "authorizedVehicles"
						),
						access = { stationId = stationId, index = index, kind = fleetKind },
					})
				end
			)
		end
	end
	for index, point in ipairs(station.impound or {}) do
		createInteraction(folder, station, stationIndex, "Impound", point, index, "Impound Nearby Vehicle", function(player, playerObj)
			local ok, message = impoundClosestVehicle(player, playerObj, station, point)
			playerObj:Notify(message, ok and "success" or "error", 3500)
		end)
	end
end

local function createInteractions()
	local existing = Workspace:FindFirstChild(INTERACTION_FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = INTERACTION_FOLDER_NAME
	folder.Parent = Workspace
	for stationIndex, station in ipairs(config().Stations or {}) do
		if trim(station.id) == "" then
			warn(("[QBCore.PoliceService] Station %d needs a unique id."):format(stationIndex))
			continue
		end
		local marker = Instance.new("Folder")
		marker.Name = safeName(station.id) .. "_Station"
		marker:SetAttribute("QBPolicePOI", "Station")
		marker:SetAttribute("QBPoliceStationId", trim(station.id))
		marker:SetAttribute("QBPoliceStationLabel", tostring(station.label or "Police Station"))
		local stationPosition = vectorFrom(station.station)
		if stationPosition then
			marker:SetAttribute("X", stationPosition.X)
			marker:SetAttribute("Y", stationPosition.Y)
			marker:SetAttribute("Z", stationPosition.Z)
		end
		marker.Parent = folder
		createStationInteractions(folder, station, stationIndex)
	end
end

function PoliceService.Start(InventoryService, VehicleService)
	if started then
		return
	end
	started = true
	inventoryService = InventoryService
	vehicleService = VehicleService
	inventoryService.RegisterExternalProvider("police_container", {
		GetSnapshot = containerSnapshot,
		HandleAction = handleContainerAction,
	})
	Remotes.PoliceAction.OnServerInvoke = function(player, action, payload)
		if requestBusy[player] then
			return false, "A police request is already in progress."
		end
		local playerObj = PlayerService.GetPlayer(player.UserId)
		if not playerObj then
			return false, "Character not loaded."
		end
		requestBusy[player] = true
		local ok, result, message = pcall(function()
			payload = type(payload) == "table" and payload or {}
			if action == "spawn_vehicle" then
				return spawnFleetVehicle(player, playerObj, payload, "vehicle")
			elseif action == "spawn_helicopter" then
				return spawnFleetVehicle(player, playerObj, payload, "helicopter")
			end
			return false, "Unknown police action."
		end)
		requestBusy[player] = nil
		if not ok then
			warn("[QBCore.PoliceService] Police action failed: " .. tostring(result))
			return false, "The police request could not be completed."
		end
		return result, message
	end
	Players.PlayerRemoving:Connect(function(player)
		requestBusy[player] = nil
		local vehicle = jobVehicles[player]
		if vehicle and vehicle.Parent then
			vehicle:Destroy()
		end
		jobVehicles[player] = nil
	end)
	createInteractions()
end

return PoliceService
