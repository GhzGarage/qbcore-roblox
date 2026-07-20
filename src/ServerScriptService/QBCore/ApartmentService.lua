-- qb-apartments-style public entrances, instanced apartment shells, doorbells,
-- wardrobes, and per-character stashes. Roblox has no routing buckets, so every
-- occupied apartment is cloned into a distant server-side grid cell.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local QBShared = require(ReplicatedStorage.QBShared.Main)
local Remotes = require(ReplicatedStorage.QBRemotes)

local ApartmentService = {}

local playerService
local inventoryService
local appearanceService
local started = false
local instances = {} -- [apartmentId] = { model, owner, occupants, building, slot }
local playerInstances = {} -- [Player] = apartmentId
local doorbells = {} -- [requestId] = request
local busy = {}
local lastRemoteAt = {}
local usedSlots = {}
local CHARACTER_ROOT_HEIGHT = 3

local function config()
	return type(QBShared.Config.Apartments) == "table" and QBShared.Config.Apartments or {}
end

local function trim(value)
	return type(value) == "string" and (value:match("^%s*(.-)%s*$") or "") or ""
end

local function copy(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, entry in pairs(value) do
		result[key] = copy(entry)
	end
	return result
end

local function filterForPlayer(text, sourcePlayer, targetPlayer, fallback)
	if not sourcePlayer or not targetPlayer then
		return fallback
	end
	local ok, result = pcall(
		TextService.FilterStringAsync,
		TextService,
		tostring(text or ""),
		sourcePlayer.UserId,
		Enum.TextFilterContext.PrivateChat
	)
	if not ok or not result then
		return fallback
	end
	local filteredOk, filtered = pcall(result.GetNonChatStringForUserAsync, result, targetPlayer.UserId)
	if not filteredOk or type(filtered) ~= "string" or filtered == "" then
		return fallback
	end
	return filtered
end

local function positionOf(entry)
	if type(entry) ~= "table" then
		return nil
	end
	if typeof(entry.position) == "Vector3" then
		return entry.position
	end
	local value = entry.position
	if type(value) == "table" then
		local x, y, z = tonumber(value.x or value.X), tonumber(value.y or value.Y), tonumber(value.z or value.Z)
		if x and y and z then
			return Vector3.new(x, y, z)
		end
	end
	return nil
end

local function getBuilding(buildingId)
	buildingId = trim(buildingId)
	for index, building in ipairs(config().Buildings or {}) do
		local id = trim(building.id)
		if id == "" then
			id = "apartments_" .. index
		end
		if id == buildingId then
			return building, id
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

local function closeToBuilding(player, building)
	local root, position = getRoot(player), positionOf(building)
	return root
		and position
		and (root.Position - position).Magnitude <= math.max(1, tonumber(config().ActionDistance) or 14)
end

local function ensureApartment(playerObj)
	local apartment = playerObj.PlayerData.apartment
	if type(apartment) ~= "table" then
		apartment = {}
	end
	apartment.id = trim(apartment.id)
	apartment.buildingId = trim(apartment.buildingId)
	apartment.label = trim(apartment.label)
	if type(apartment.stash) ~= "table" then
		apartment.stash = {}
	end
	local normalizedStash = {}
	local maxSlots = math.max(1, math.floor(tonumber(config().MaxStashSlots) or 50))
	for _, item in ipairs(apartment.stash) do
		local amount = type(item) == "table" and math.floor(tonumber(item.amount) or 0) or 0
		if #normalizedStash < maxSlots and amount > 0 and QBShared.Items[item.name] then
			normalizedStash[#normalizedStash + 1] = { name = item.name, amount = amount, info = copy(item.info) }
		end
	end
	apartment.stash = normalizedStash
	playerObj.PlayerData.apartment = apartment
	return apartment
end

local function hasApartment(apartment)
	return type(apartment) == "table" and trim(apartment.id) ~= "" and trim(apartment.buildingId) ~= ""
end

local function apartmentLabel(building, playerObj)
	return ("%s - %s"):format(tostring(building.label or "Apartment"), playerObj.PlayerData.citizenid)
end

local function assignApartment(playerObj, building, buildingId)
	local previous = copy(ensureApartment(playerObj))
	local apartment = ensureApartment(playerObj)
	apartment.id = apartment.id ~= "" and apartment.id or ("apt_" .. tostring(playerObj.PlayerData.citizenid))
	apartment.buildingId = buildingId
	apartment.label = apartmentLabel(building, playerObj)
	playerObj:SetPlayerData("apartment", apartment)
	if playerObj:Save() ~= true then
		playerObj:SetPlayerData("apartment", previous)
		return nil, "Your apartment assignment could not be saved."
	end
	return apartment
end

local function allocateSlot()
	local slot = 1
	while usedSlots[slot] do
		slot = slot + 1
	end
	usedSlots[slot] = true
	return slot
end

local function gridCFrame(slot)
	local origin = typeof(config().InteriorGridOrigin) == "Vector3" and config().InteriorGridOrigin
		or Vector3.new(20000, 500, 20000)
	local spacing = math.max(80, tonumber(config().InteriorGridSpacing) or 180)
	local column = (slot - 1) % 20
	local row = math.floor((slot - 1) / 20)
	return CFrame.new(origin + Vector3.new(column * spacing, 0, row * spacing))
end

local function makePart(model, name, size, cframe, color, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color or Color3.fromRGB(48, 53, 61)
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.Parent = model
	return part
end

local function makeBlockout()
	local model = Instance.new("Model")
	model.Name = "StarterApartment_Blockout"
	local wall = Color3.fromRGB(224, 222, 216)
	makePart(model, "Floor", Vector3.new(54, 1, 38), CFrame.new(0, 0, 0), Color3.fromRGB(88, 76, 64))
	makePart(model, "BackWall", Vector3.new(54, 14, 1), CFrame.new(0, 7, -19), wall)
	makePart(model, "FrontWall", Vector3.new(54, 14, 1), CFrame.new(0, 7, 19), wall)
	makePart(model, "LeftWall", Vector3.new(1, 14, 38), CFrame.new(-27, 7, 0), wall)
	makePart(model, "RightWall", Vector3.new(1, 14, 38), CFrame.new(27, 7, 0), wall)
	makePart(model, "KitchenIsland", Vector3.new(10, 3, 3), CFrame.new(8, 1.75, -8), Color3.fromRGB(58, 63, 71))
	makePart(model, "SofaBlockout", Vector3.new(8, 3, 3), CFrame.new(-8, 1.75, 2), Color3.fromRGB(70, 99, 112))
	makePart(model, "Spawn", Vector3.new(2, 1, 2), CFrame.new(0, 1, 14), Color3.new(1, 1, 1), 1)
	makePart(model, "Exit", Vector3.new(2, 2, 2), CFrame.new(0, 1, 17), Color3.new(1, 1, 1), 1)
	makePart(model, "Stash", Vector3.new(2, 2, 2), CFrame.new(23, 1, -15), Color3.new(1, 1, 1), 1)
	makePart(model, "Wardrobe", Vector3.new(2, 2, 2), CFrame.new(-23, 1, -15), Color3.new(1, 1, 1), 1)
	makePart(model, "Logout", Vector3.new(2, 2, 2), CFrame.new(-23, 1, 15), Color3.new(1, 1, 1), 1)
	return model
end

local function findMarker(model, name)
	local marker = model:FindFirstChild(name, true)
	return marker and marker:IsA("BasePart") and marker or nil
end

local function addPrompt(part, name, actionText, objectText, callback)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = math.max(1, tonumber(config().PromptDistance) or 10)
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(callback)
end

local interiorAction

local function createInstance(player, playerObj, apartment, building)
	local existing = instances[apartment.id]
	if existing then
		return existing
	end
	local templateFolder = ServerStorage:FindFirstChild("QBApartmentInteriors")
	local template = templateFolder and templateFolder:FindFirstChild(trim(building.interior))
	local model
	if template and template:IsA("Model") then
		model = template:Clone()
	else
		model = makeBlockout()
	end
	model.Name = "Apartment_" .. apartment.id:gsub("[^%w_]", "_")
	local slot = allocateSlot()
	model:PivotTo(gridCFrame(slot))
	model.Parent = Workspace:FindFirstChild("QBApartmentInstances")
	local instance = {
		model = model,
		owner = player,
		ownerCitizenId = playerObj.PlayerData.citizenid,
		occupants = {},
		building = building,
		buildingId = apartment.buildingId,
		slot = slot,
	}
	instances[apartment.id] = instance
	local actions = {
		{ marker = "Exit", name = "ExitPrompt", action = "leave", text = "Exit", object = "Apartment Door" },
		{ marker = "Stash", name = "StashPrompt", action = "stash", text = "Open", object = "Personal Stash" },
		{
			marker = "Wardrobe",
			name = "WardrobePrompt",
			action = "wardrobe",
			text = "Change Outfit",
			object = "Wardrobe",
		},
		{ marker = "Logout", name = "LogoutPrompt", action = "logout", text = "Logout", object = "Apartment" },
	}
	for _, data in ipairs(actions) do
		local marker = findMarker(model, data.marker)
		if marker then
			addPrompt(marker, data.name, data.text, data.object, function(triggeringPlayer)
				local ok, err = interiorAction(triggeringPlayer, data.action, {})
				if not ok then
					local triggeringObj = playerService.GetPlayer(triggeringPlayer.UserId)
					if triggeringObj then
						triggeringObj:Notify(err or "That apartment action is unavailable.", "error", 3500)
					end
				end
			end)
		end
	end
	return instance
end

local function exteriorCFrame(building)
	local position = positionOf(building) or Vector3.new(0, 0, 0)
	local heading = math.rad(tonumber(building.heading) or 0)
	return CFrame.new(position + Vector3.new(0, 3, 5)) * CFrame.Angles(0, heading, 0)
end

local function teleport(player, cframe)
	local root = getRoot(player)
	if not root then
		return false, "Your character is unavailable."
	end
	root.Anchored = false
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = cframe
	return true
end

local function prepareEntry(player, playerObj, apartment, asGuest)
	local building = getBuilding(apartment.buildingId)
	if not building then
		return false, "That apartment building is no longer configured."
	end
	local instance = instances[apartment.id]
	if not instance then
		if asGuest then
			return false, "That apartment is no longer occupied."
		end
		instance = createInstance(player, playerObj, apartment, building)
	end
	local spawnMarker = findMarker(instance.model, "Spawn") or findMarker(instance.model, "Exit")
	-- Markers are modeled as parts sitting on the floor. Place the HumanoidRootPart
	-- three studs above the marker's bottom rather than three studs above its center;
	-- the latter leaves the first-time apartment character visibly hovering.
	local markerOffset = spawnMarker and math.max(0, CHARACTER_ROOT_HEIGHT - spawnMarker.Size.Y / 2)
	local spawnCFrame = spawnMarker and (spawnMarker.CFrame + Vector3.new(0, markerOffset, 0))
		or (instance.model:GetPivot() + Vector3.new(0, 4, 0))
	return true, {
		apartmentId = apartment.id,
		asGuest = asGuest == true,
		spawnCFrame = spawnCFrame,
	}
end

local function completeEntry(player, playerObj, prepared)
	local instance = type(prepared) == "table" and instances[prepared.apartmentId]
	if not instance or (prepared.asGuest ~= true and instance.owner ~= player) then
		return false, "That apartment is no longer available."
	end
	local ok, err = teleport(player, prepared.spawnCFrame)
	if not ok then
		return false, err
	end
	instance.occupants[player] = prepared.asGuest == true and "guest" or "owner"
	playerInstances[player] = prepared.apartmentId
	playerObj._suppressPositionCapture = true
	player:SetAttribute("QBApartmentId", prepared.apartmentId)
	player:SetAttribute("QBApartmentGuest", prepared.asGuest == true)
	return true
end

local function enter(player, playerObj, apartment, asGuest)
	local ok, preparedOrError = prepareEntry(player, playerObj, apartment, asGuest)
	if not ok then
		return false, preparedOrError
	end
	return completeEntry(player, playerObj, preparedOrError)
end

local function cleanupInstance(apartmentId)
	local instance = instances[apartmentId]
	if not instance or next(instance.occupants) then
		return
	end
	usedSlots[instance.slot] = nil
	if instance.model then
		instance.model:Destroy()
	end
	instances[apartmentId] = nil
end

local function leaveOne(player, reason)
	local apartmentId = playerInstances[player]
	local instance = apartmentId and instances[apartmentId]
	if not instance then
		return false, "You are not inside an apartment."
	end
	instance.occupants[player] = nil
	playerInstances[player] = nil
	player:SetAttribute("QBApartmentId", nil)
	player:SetAttribute("QBApartmentGuest", nil)
	local playerObj = playerService.GetPlayer(player.UserId)
	if playerObj then
		playerObj._suppressPositionCapture = false
	end
	if player.Parent then
		teleport(player, exteriorCFrame(instance.building))
		if playerObj then
			playerObj:CapturePosition()
			if reason then
				playerObj:Notify(reason, "primary", 3500)
			end
		end
	end
	cleanupInstance(apartmentId)
	return true
end

local function leaveApartment(player)
	local apartmentId = playerInstances[player]
	local instance = apartmentId and instances[apartmentId]
	if not instance then
		return false, "You are not inside an apartment."
	end
	if instance.owner == player then
		local guests = {}
		for occupant, role in pairs(instance.occupants) do
			if occupant ~= player and role == "guest" then
				guests[#guests + 1] = occupant
			end
		end
		for _, guest in ipairs(guests) do
			leaveOne(guest, "The resident left the apartment.")
		end
	end
	return leaveOne(player)
end

local function occupantList(buildingId, viewer)
	local list = {}
	for _, instance in pairs(instances) do
		if
			instance.buildingId == buildingId
			and instance.occupants[instance.owner] == "owner"
			and instance.owner.Parent
		then
			local ownerObj = playerService.GetPlayer(instance.owner.UserId)
			if ownerObj then
				list[#list + 1] = {
					citizenId = instance.ownerCitizenId,
					name = filterForPlayer(ownerObj:GetName(), instance.owner, viewer, "Resident"),
					label = ensureApartment(ownerObj).label,
				}
			end
		end
	end
	table.sort(list, function(a, b)
		return string.lower(a.name) < string.lower(b.name)
	end)
	return list
end

local function menuSnapshot(player, playerObj, building, buildingId)
	local apartment = ensureApartment(playerObj)
	return {
		buildingId = buildingId,
		label = tostring(building.label or "Apartments"),
		ownsHere = hasApartment(apartment) and apartment.buildingId == buildingId,
		hasApartment = hasApartment(apartment),
		apartmentLabel = apartment.label,
		occupants = occupantList(buildingId, player),
	}
end

local function openBuilding(player, buildingId)
	local playerObj = playerService.GetPlayer(player.UserId)
	local building, resolvedId = getBuilding(buildingId)
	if not playerObj or not building or not closeToBuilding(player, building) then
		return false
	end
	Remotes.OpenApartment:FireClient(player, "menu", menuSnapshot(player, playerObj, building, resolvedId))
	return true
end

local function stashWeight(stash)
	local weight = 0
	for _, item in ipairs(stash) do
		local definition = QBShared.Items[item.name]
		if definition then
			weight = weight + (tonumber(definition.weight) or 0) * (tonumber(item.amount) or 0)
		end
	end
	return weight
end

local function hydrateStash(stash)
	local items = {}
	for index, item in ipairs(stash) do
		local definition = QBShared.Items[item.name]
		if definition and (tonumber(item.amount) or 0) > 0 then
			items[#items + 1] = {
				slot = index,
				name = item.name,
				label = definition.label or item.name,
				amount = item.amount,
				weight = tonumber(definition.weight) or 0,
				info = copy(item.info),
			}
		end
	end
	return items
end

local function ownerInside(player, playerObj)
	local apartment = ensureApartment(playerObj)
	local instance = instances[apartment.id]
	return instance and playerInstances[player] == apartment.id and instance.occupants[player] == "owner", apartment
end

local function stashSnapshot(playerObj, apartment)
	local inventory = inventoryService.GetSnapshot(playerObj)
	return {
		label = apartment.label ~= "" and apartment.label .. " Stash" or "Apartment Stash",
		inventory = inventory and inventory.items or {},
		stash = hydrateStash(apartment.stash),
		weight = stashWeight(apartment.stash),
		maxWeight = math.max(1, tonumber(config().MaxStashWeight) or 250000),
		maxSlots = math.max(1, math.floor(tonumber(config().MaxStashSlots) or 50)),
	}
end

local function storeItem(playerObj, apartment, payload)
	local slot = math.floor(tonumber(payload.slot) or 0)
	local item = inventoryService.GetItemBySlot(playerObj, slot)
	if not item then
		return false, "Select an inventory item."
	end
	local amount = math.clamp(math.floor(tonumber(payload.amount) or item.amount), 1, item.amount)
	if #apartment.stash >= math.max(1, math.floor(tonumber(config().MaxStashSlots) or 50)) then
		return false, "The apartment stash is full."
	end
	local definition = QBShared.Items[item.name]
	local nextWeight = stashWeight(apartment.stash) + (tonumber(definition and definition.weight) or 0) * amount
	if nextWeight > math.max(1, tonumber(config().MaxStashWeight) or 250000) then
		return false, "The apartment stash is too heavy."
	end
	local removed, err = inventoryService.RemoveItem(playerObj, item.name, amount, slot, "apartment-stash")
	if not removed then
		return false, err
	end
	apartment.stash[#apartment.stash + 1] = { name = item.name, amount = amount, info = copy(item.info) }
	playerObj:SetPlayerData("apartment", apartment)
	if playerObj:Save() ~= true then
		table.remove(apartment.stash, #apartment.stash)
		inventoryService.AddItem(playerObj, item.name, amount, slot, item.info, "apartment-stash-rollback")
		return false, "The stash could not be saved; your item was returned."
	end
	return true
end

local function takeItem(playerObj, apartment, payload)
	local slot = math.floor(tonumber(payload.slot) or 0)
	local item = apartment.stash[slot]
	if type(item) ~= "table" then
		return false, "Select a stash item."
	end
	local amount = math.clamp(math.floor(tonumber(payload.amount) or item.amount), 1, tonumber(item.amount) or 1)
	local added, err = inventoryService.AddItem(playerObj, item.name, amount, nil, item.info, "apartment-stash")
	if not added then
		return false, err
	end
	item.amount = (tonumber(item.amount) or 0) - amount
	if item.amount <= 0 then
		table.remove(apartment.stash, slot)
	end
	playerObj:SetPlayerData("apartment", apartment)
	if playerObj:Save() ~= true then
		inventoryService.RemoveItem(playerObj, item.name, amount, nil, "apartment-stash-rollback")
		if apartment.stash[slot] == item then
			item.amount = item.amount + amount
		else
			table.insert(apartment.stash, slot, { name = item.name, amount = amount, info = copy(item.info) })
		end
		return false, "The stash could not be saved; the item was returned to it."
	end
	return true
end

local function ringDoorbell(player, playerObj, payload)
	for _, pendingRequest in pairs(doorbells) do
		if pendingRequest.visitor == player then
			return false, "Your previous doorbell ring is still pending."
		end
	end
	local building = getBuilding(payload.buildingId)
	if not building or not closeToBuilding(player, building) then
		return false, "Move closer to the apartment entrance."
	end
	local targetCitizenId = trim(payload.citizenId)
	local targetObj = playerService.GetPlayerByCitizenId(targetCitizenId)
	local target = targetObj and targetObj._source
	local targetApartment = targetObj and ensureApartment(targetObj)
	local instance = targetApartment and instances[targetApartment.id]
	if
		not target
		or not instance
		or instance.buildingId ~= payload.buildingId
		or instance.occupants[target] ~= "owner"
	then
		return false, "That resident is no longer home."
	end
	local requestId = HttpService:GenerateGUID(false)
	local request = {
		id = requestId,
		visitor = player,
		visitorCitizenId = playerObj.PlayerData.citizenid,
		owner = target,
		apartmentId = targetApartment.id,
		expiresAt = os.clock() + math.max(5, tonumber(config().DoorbellTimeout) or 30),
	}
	doorbells[requestId] = request
	Remotes.OpenApartment:FireClient(target, "doorbell", {
		requestId = requestId,
		visitorName = filterForPlayer(playerObj:GetName(), player, target, "A visitor"),
		timeout = math.max(5, tonumber(config().DoorbellTimeout) or 30),
	})
	playerObj:Notify("You rang the apartment doorbell.", "primary", 3000)
	task.delay(math.max(5, tonumber(config().DoorbellTimeout) or 30) + 1, function()
		if doorbells[requestId] == request then
			doorbells[requestId] = nil
		end
	end)
	return true
end

local function answerDoorbell(player, payload)
	local request = doorbells[trim(payload.requestId)]
	if not request or request.owner ~= player then
		return false, "That doorbell request expired."
	end
	doorbells[request.id] = nil
	if payload.accept ~= true then
		local visitorObj = request.visitor.Parent and playerService.GetPlayer(request.visitor.UserId)
		if visitorObj then
			visitorObj:Notify("The resident did not answer the door.", "error", 3000)
		end
		return true
	end
	if os.clock() > request.expiresAt or not request.visitor.Parent then
		return false, "That visitor is no longer waiting."
	end
	if playerInstances[request.visitor] then
		return false, "That visitor is already inside an apartment."
	end
	local instance = instances[request.apartmentId]
	local visitorObj = playerService.GetPlayer(request.visitor.UserId)
	if
		not instance
		or instance.occupants[player] ~= "owner"
		or not visitorObj
		or not closeToBuilding(request.visitor, instance.building)
	then
		return false, "The visitor is no longer at the entrance."
	end
	local ownerObj = playerService.GetPlayer(player.UserId)
	local apartment = ownerObj and ensureApartment(ownerObj)
	local ok, err = enter(request.visitor, visitorObj, apartment, true)
	if ok then
		visitorObj:Notify("The resident let you into the apartment.", "success", 3500)
	end
	return ok, err
end

interiorAction = function(player, action, payload)
	local playerObj = playerService.GetPlayer(player.UserId)
	if not playerObj then
		return false, "Character not loaded."
	end
	if action == "leave" then
		return leaveApartment(player)
	end
	local isOwner, apartment = ownerInside(player, playerObj)
	if not isOwner then
		return false, "Only the resident can use that apartment feature."
	end
	if action == "stash" then
		Remotes.OpenApartment:FireClient(player, "stash", stashSnapshot(playerObj, apartment))
		return true
	end
	if action == "wardrobe" then
		return appearanceService.OpenEditor(
			player,
			playerObj,
			false,
			{ mode = "wardrobe", title = "Apartment Wardrobe" }
		)
	end
	if action == "logout" then
		leaveApartment(player)
		task.defer(playerService.Logout, player)
		return true
	end
	return false, "Unknown apartment action."
end

local function handleAction(player, action, payload)
	payload = type(payload) == "table" and payload or {}
	action = type(action) == "string" and action:lower() or ""
	local playerObj = playerService.GetPlayer(player.UserId)
	if not playerObj then
		return false, "Character not loaded."
	end
	if action == "open" then
		return openBuilding(player, payload.buildingId), "Move closer to the apartment entrance."
	end
	if action == "enter" then
		local apartment = ensureApartment(playerObj)
		local building = getBuilding(apartment.buildingId)
		if not hasApartment(apartment) or not building or not closeToBuilding(player, building) then
			return false, "Move closer to your apartment entrance."
		end
		return enter(player, playerObj, apartment, false)
	end
	if action == "move_here" then
		local building, buildingId = getBuilding(payload.buildingId)
		if not building or not closeToBuilding(player, building) then
			return false, "Move closer to the apartment entrance."
		end
		if playerInstances[player] then
			return false, "Leave the current apartment first."
		end
		local apartment, err = assignApartment(playerObj, building, buildingId)
		if not apartment then
			return false, err
		end
		return true, menuSnapshot(player, playerObj, building, buildingId)
	end
	if action == "ring" then
		return ringDoorbell(player, playerObj, payload)
	end
	if action == "answer" then
		return answerDoorbell(player, payload)
	end
	if action == "leave" or action == "stash" or action == "wardrobe" or action == "logout" then
		return interiorAction(player, action, payload)
	end
	local isOwner, apartment = ownerInside(player, playerObj)
	if action == "stash_refresh" and isOwner then
		return true, stashSnapshot(playerObj, apartment)
	end
	if (action == "stash_store" or action == "stash_take") and isOwner then
		if busy[player] then
			return false, "Another stash action is already running."
		end
		busy[player] = true
		local called, ok, err = pcall(function()
			if action == "stash_store" then
				return storeItem(playerObj, apartment, payload)
			end
			return takeItem(playerObj, apartment, payload)
		end)
		busy[player] = nil
		if not called then
			error(ok, 0)
		end
		if not ok then
			return false, err
		end
		return true, stashSnapshot(playerObj, apartment)
	end
	return false, "Unknown apartment action."
end

function ApartmentService.GetStartingChoices()
	local choices = {}
	for index, building in ipairs(config().Buildings or {}) do
		local position = positionOf(building)
		if position then
			local id = trim(building.id)
			if id == "" then
				id = "apartments_" .. index
			end
			choices[#choices + 1] = {
				id = "apartment:" .. id,
				kind = "apartment",
				buildingId = id,
				label = tostring(building.label or "Starter Apartment"),
				description = "Choose this building as your first home.",
				position = { x = position.X, y = position.Y, z = position.Z },
			}
		end
	end
	return choices
end

function ApartmentService.GetOwnedChoice(playerObj)
	local apartment = ensureApartment(playerObj)
	local building = hasApartment(apartment) and getBuilding(apartment.buildingId)
	local position = building and positionOf(building)
	if not building or not position then
		return nil
	end
	return {
		id = "owned_apartment",
		kind = "owned_apartment",
		label = apartment.label ~= "" and apartment.label or tostring(building.label or "My Apartment"),
		description = "Enter your apartment.",
		position = { x = position.X, y = position.Y, z = position.Z },
	}
end

function ApartmentService.PrepareStarterSpawn(player, playerObj, buildingId)
	local building, resolvedId = getBuilding(buildingId)
	if not building then
		return false, "That starter apartment is unavailable."
	end
	local apartment = ensureApartment(playerObj)
	if not hasApartment(apartment) then
		local assigned, err = assignApartment(playerObj, building, resolvedId)
		if not assigned then
			return false, err
		end
		apartment = assigned
	end
	return prepareEntry(player, playerObj, apartment, false)
end

function ApartmentService.PrepareOwnedSpawn(player, playerObj)
	local apartment = ensureApartment(playerObj)
	if not hasApartment(apartment) then
		return false, "This character does not own an apartment."
	end
	return prepareEntry(player, playerObj, apartment, false)
end

function ApartmentService.CompletePreparedSpawn(player, playerObj, prepared)
	return completeEntry(player, playerObj, prepared)
end

function ApartmentService.CancelPreparedSpawn(player, prepared)
	local apartmentId = type(prepared) == "table" and prepared.apartmentId
	local instance = apartmentId and instances[apartmentId]
	if instance and instance.owner == player and next(instance.occupants) == nil then
		cleanupInstance(apartmentId)
	end
end

function ApartmentService.OnPlayerLeave(player)
	local apartmentId = playerInstances[player]
	local instance = apartmentId and instances[apartmentId]
	if instance and instance.owner == player then
		local occupants = {}
		for occupant in pairs(instance.occupants) do
			occupants[#occupants + 1] = occupant
		end
		for _, occupant in ipairs(occupants) do
			if occupant ~= player then
				leaveOne(occupant, "The resident disconnected.")
			end
		end
	end
	if instance then
		instance.occupants[player] = nil
		playerInstances[player] = nil
		cleanupInstance(apartmentId)
	end
	busy[player] = nil
	lastRemoteAt[player] = nil
	for requestId, request in pairs(doorbells) do
		if request.owner == player or request.visitor == player then
			doorbells[requestId] = nil
		end
	end
end

local function createEntrances()
	local folder = Workspace:FindFirstChild("QBApartmentEntrances")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "QBApartmentEntrances"
		folder.Parent = Workspace
	end
	for index, building in ipairs(config().Buildings or {}) do
		local position = positionOf(building)
		if position then
			local id = trim(building.id)
			if id == "" then
				id = "apartments_" .. index
			end
			local part = Instance.new("Part")
			part.Name = "ApartmentEntrance_" .. id:gsub("[^%w_]", "_")
			part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
			part.Transparency, part.Size, part.Position = 1, Vector3.new(2, 2, 2), position
			part.Parent = folder
			addPrompt(part, "ApartmentPrompt", "Open", tostring(building.label or "Apartments"), function(player)
				openBuilding(player, id)
			end)
		end
	end
end

function ApartmentService.Start(players, inventory, appearance)
	if started then
		return
	end
	playerService, inventoryService, appearanceService = players, inventory, appearance
	assert(
		type(playerService) == "table" and type(playerService.GetPlayer) == "function",
		"ApartmentService needs PlayerService"
	)
	assert(
		type(inventoryService) == "table" and type(inventoryService.GetSnapshot) == "function",
		"ApartmentService needs InventoryService"
	)
	assert(
		type(appearanceService) == "table" and type(appearanceService.OpenEditor) == "function",
		"ApartmentService needs AppearanceService"
	)
	started = true
	local folder = Workspace:FindFirstChild("QBApartmentInstances") or Instance.new("Folder")
	folder.Name = "QBApartmentInstances"
	folder.Parent = Workspace
	Remotes.ApartmentAction.OnServerInvoke = function(player, action, payload)
		local now = os.clock()
		if now - (lastRemoteAt[player] or 0) < 0.2 then
			return false, "Please wait before trying that again."
		end
		lastRemoteAt[player] = now
		local ok, result, extra = pcall(handleAction, player, action, payload)
		if not ok then
			warn(("[QBCore.ApartmentService] Action failed for %s: %s"):format(player.Name, tostring(result)))
			return false, "The apartment action could not be completed."
		end
		return result, extra
	end
	if config().Enabled ~= false then
		createEntrances()
	end
end

return ApartmentService
