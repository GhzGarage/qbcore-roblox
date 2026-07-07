--[[
    First-pass Roblox port of qb-inventory's player inventory core.

    Scope for now:
      - one player inventory stored in PlayerData.items
      - slots 1-5 are the hotbar
      - server-authoritative add/remove/move/use helpers
      - consumable items can update PlayerData.metadata

    Future systems (shops, stashes, drops, trunks, crafting) should build on the same
    slot/item helpers here instead of creating separate inventory shapes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QBShared = require(ReplicatedStorage.QBShared.Main)

local InventoryService = {}

local useableHandlers = {}
local playerService = nil

local DEFAULT_GIVE_DISTANCE = 10
local REGISTERED_WEAPON_TOOL_ATTRIBUTE = "QBWeaponTool"
local WEAPON_ITEM_ATTRIBUTE = "QBInventoryItemName"

local function getPlayerService()
	if not playerService then
		playerService = require(script.Parent.PlayerService)
	end
	return playerService
end

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in pairs(value) do
		copy[key] = deepCopy(child)
	end
	return copy
end

local function deepEqual(left, right)
	if left == right then
		return true
	end
	if type(left) ~= "table" or type(right) ~= "table" then
		return false
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

local function getInventoryConfig()
	return QBShared.Config.Inventory or {}
end

local function getSlotCount()
	return math.max(1, math.floor(tonumber(getInventoryConfig().Slots) or 30))
end

local function getHotbarSlotCount()
	local configured = math.floor(tonumber(getInventoryConfig().HotbarSlots) or 5)
	return math.clamp(configured, 1, getSlotCount())
end

local function getMaxWeight()
	return math.max(0, tonumber(getInventoryConfig().MaxWeight) or 120000)
end

local function getMaxStack()
	return math.max(1, math.floor(tonumber(getInventoryConfig().MaxStack) or 999))
end

local function getGiveDistance()
	return math.max(1, tonumber(getInventoryConfig().GiveDistance) or DEFAULT_GIVE_DISTANCE)
end

local function normalizeSlot(slot)
	slot = tonumber(slot)
	if not slot then
		return nil
	end
	slot = math.floor(slot)
	if slot < 1 or slot > getSlotCount() then
		return nil
	end
	return slot
end

local function normalizeAmount(amount)
	amount = math.floor(tonumber(amount) or 1)
	if amount < 1 then
		return nil
	end
	return amount
end

local function normalizeItemName(itemName)
	if type(itemName) ~= "string" then
		return nil
	end
	itemName = itemName:lower()
	if itemName == "" then
		return nil
	end
	return itemName
end

local function getItemDefinition(itemName)
	itemName = normalizeItemName(itemName)
	if not itemName then
		return nil
	end
	return QBShared.Items[itemName]
end

local function getRobloxPlayer(playerObj)
	local player = playerObj and playerObj._source
	if typeof(player) == "Instance" and player:IsA("Player") then
		return player
	end
	return nil
end

local function getHumanoid(player)
	local character = player and player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function getRoot(player)
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function getCharacterCFrame(player)
	local root = getRoot(player)
	if root then
		return root.CFrame
	end

	local character = player and player.Character
	if not character then
		return nil
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant.CFrame
		end
	end

	return nil
end

local function isAlive(playerObj, player)
	if not playerObj or playerObj:GetMetaData("isdead") == true then
		return false
	end

	local humanoid = getHumanoid(player)
	return humanoid ~= nil and humanoid.Health > 0 and humanoid:GetState() ~= Enum.HumanoidStateType.Dead
end

local function destroyRegisteredWeaponTools(container, itemName)
	if not container then
		return
	end

	for _, child in ipairs(container:GetChildren()) do
		if
			child:IsA("Tool")
			and child:GetAttribute(REGISTERED_WEAPON_TOOL_ATTRIBUTE) == true
			and child:GetAttribute(WEAPON_ITEM_ATTRIBUTE) == itemName
		then
			child:Destroy()
		end
	end
end

local function clearGivenWeaponTool(player, definition)
	if not player or not definition then
		return
	end
	if definition.type ~= "weapon" and type(definition.weapon) ~= "table" then
		return
	end

	destroyRegisteredWeaponTools(player:FindFirstChildOfClass("Backpack"), definition.name)
	destroyRegisteredWeaponTools(player.Character, definition.name)
end

local function getStoredItem(items, slot)
	slot = normalizeSlot(slot)
	if not slot or type(items) ~= "table" then
		return nil
	end
	return items[tostring(slot)] or items[slot]
end

local function setStoredItem(items, slot, item)
	slot = normalizeSlot(slot)
	if not slot then
		return
	end

	items[tostring(slot)] = item
	items[slot] = nil
	if item then
		item.slot = slot
	end
end

local function copyInfo(info)
	if type(info) ~= "table" then
		return {}
	end
	return deepCopy(info)
end

local function makeStoredItem(definition, amount, slot, info)
	return {
		name = definition.name,
		amount = amount,
		slot = slot,
		info = copyInfo(info),
	}
end

local function sanitizeStoredItem(rawItem, key)
	if type(rawItem) ~= "table" then
		return nil
	end

	local definition = getItemDefinition(rawItem.name)
	local slot = normalizeSlot(rawItem.slot or key)
	local amount = normalizeAmount(rawItem.amount)
	if not definition or not slot or not amount then
		return nil
	end

	return makeStoredItem(definition, amount, slot, rawItem.info)
end

local function hydrateItemForClient(item)
	local definition = getItemDefinition(item and item.name)
	if not definition then
		return nil
	end

	return {
		name = definition.name,
		label = definition.label or definition.name,
		amount = tonumber(item.amount) or 1,
		slot = tonumber(item.slot) or 1,
		info = copyInfo(item.info),
		weight = tonumber(definition.weight) or 0,
		type = definition.type or "item",
		image = definition.image or "",
		unique = definition.unique == true,
		useable = definition.useable == true or useableHandlers[definition.name] ~= nil,
		shouldClose = definition.shouldClose ~= false,
		description = definition.description or "",
	}
end

local function findFreeSlot(items)
	for slot = 1, getSlotCount() do
		if not getStoredItem(items, slot) then
			return slot
		end
	end
	return nil
end

local function findStackSlot(items, definition, info)
	if definition.unique then
		return nil
	end

	for slot = 1, getSlotCount() do
		local existing = getStoredItem(items, slot)
		local existingDefinition = existing and getItemDefinition(existing.name)
		if
			existing
			and existingDefinition
			and existing.name == definition.name
			and not existingDefinition.unique
			and deepEqual(existing.info or {}, info or {})
			and (tonumber(existing.amount) or 0) < getMaxStack()
		then
			return slot
		end
	end

	return nil
end

local function insertItems(items, definition, amount, preferredSlot, info)
	local maxStack = getMaxStack()

	if definition.unique then
		for index = 1, amount do
			local slot = nil
			if preferredSlot and index == 1 then
				slot = normalizeSlot(preferredSlot)
				if not slot then
					return false, "Invalid slot."
				end
				if getStoredItem(items, slot) then
					return false, "That slot is occupied."
				end
			else
				slot = findFreeSlot(items)
				if not slot then
					return false, "Inventory is full."
				end
			end
			setStoredItem(items, slot, makeStoredItem(definition, 1, slot, info))
		end
		return true
	end

	if preferredSlot then
		local slot = normalizeSlot(preferredSlot)
		if not slot then
			return false, "Invalid slot."
		end

		local existing = getStoredItem(items, slot)
		if not existing then
			setStoredItem(items, slot, makeStoredItem(definition, amount, slot, info))
			return true
		end

		if existing.name ~= definition.name or not deepEqual(existing.info or {}, info or {}) then
			return false, "That slot is occupied."
		end

		local total = (tonumber(existing.amount) or 0) + amount
		if total > maxStack then
			return false, "That stack is full."
		end
		existing.amount = total
		setStoredItem(items, slot, existing)
		return true
	end

	local remaining = amount
	while remaining > 0 do
		local stackSlot = findStackSlot(items, definition, info)
		if stackSlot then
			local existing = getStoredItem(items, stackSlot)
			local space = maxStack - (tonumber(existing.amount) or 0)
			local moved = math.min(space, remaining)
			existing.amount += moved
			remaining -= moved
			setStoredItem(items, stackSlot, existing)
		else
			local freeSlot = findFreeSlot(items)
			if not freeSlot then
				return false, "Inventory is full."
			end

			local moved = math.min(maxStack, remaining)
			setStoredItem(items, freeSlot, makeStoredItem(definition, moved, freeSlot, info))
			remaining -= moved
		end
	end

	return true
end

local function updatePlayerItems(playerObj)
	playerObj:SetPlayerData("items", playerObj.PlayerData.items)
end

local function findClosestGiveTarget(playerObj)
	local player = getRobloxPlayer(playerObj)
	if not player then
		return nil, "Character not loaded."
	end
	if not isAlive(playerObj, player) then
		return nil, "You cannot give items while dead."
	end

	local sourceRoot = getRoot(player)
	if not sourceRoot then
		return nil, "Character not spawned."
	end

	local closest = nil
	local closestDistance = getGiveDistance()
	local playerServiceModule = getPlayerService()

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer ~= player then
			local targetObj = playerServiceModule.GetPlayer(targetPlayer.UserId)
			local targetCFrame = targetObj and isAlive(targetObj, targetPlayer) and getCharacterCFrame(targetPlayer)
			if targetCFrame then
				local distance = (targetCFrame.Position - sourceRoot.Position).Magnitude
				if distance <= closestDistance then
					closestDistance = distance
					closest = {
						player = targetPlayer,
						playerObj = targetObj,
						cframe = targetCFrame,
					}
				end
			end
		end
	end

	if not closest then
		return nil, "No player nearby."
	end

	return closest
end

function InventoryService.ReconcilePlayerData(playerData)
	if type(playerData) ~= "table" then
		return {}
	end

	local source = type(playerData.items) == "table" and playerData.items or {}
	local normalized = {}

	for key, rawItem in pairs(source) do
		local item = sanitizeStoredItem(rawItem, key)
		if item and not getStoredItem(normalized, item.slot) then
			setStoredItem(normalized, item.slot, item)
		elseif item then
			local existing = getStoredItem(normalized, item.slot)
			local definition = getItemDefinition(item.name)
			if
				existing
				and definition
				and not definition.unique
				and existing.name == item.name
				and deepEqual(existing.info or {}, item.info or {})
			then
				existing.amount += item.amount
				setStoredItem(normalized, item.slot, existing)
			end
		end
	end

	playerData.items = normalized
	return normalized
end

function InventoryService.SeedStarterItems(playerData)
	InventoryService.ReconcilePlayerData(playerData)

	for _, starter in ipairs(getInventoryConfig().StarterItems or {}) do
		local definition = getItemDefinition(starter.name)
		local amount = normalizeAmount(starter.amount)
		if definition and amount then
			local ok, err = insertItems(playerData.items, definition, amount, starter.slot, starter.info)
			if not ok then
				warn(("[QBCore.InventoryService] Starter item %s skipped: %s"):format(starter.name, tostring(err)))
			end
		end
	end
end

function InventoryService.GetTotalWeight(items)
	local total = 0
	if type(items) ~= "table" then
		return total
	end

	for slot = 1, getSlotCount() do
		local item = getStoredItem(items, slot)
		local definition = getItemDefinition(item and item.name)
		if definition then
			total += (tonumber(definition.weight) or 0) * (tonumber(item.amount) or 1)
		end
	end

	return total
end

function InventoryService.GetFreeWeight(playerObj)
	if not playerObj then
		return 0
	end
	InventoryService.ReconcilePlayerData(playerObj.PlayerData)
	return math.max(0, getMaxWeight() - InventoryService.GetTotalWeight(playerObj.PlayerData.items))
end

function InventoryService.GetSnapshot(playerObj)
	if not playerObj then
		return nil
	end

	InventoryService.ReconcilePlayerData(playerObj.PlayerData)

	local items = {}
	for slot = 1, getSlotCount() do
		local hydrated = hydrateItemForClient(getStoredItem(playerObj.PlayerData.items, slot))
		if hydrated then
			items[tostring(slot)] = hydrated
		end
	end

	return {
		items = items,
		slots = getSlotCount(),
		hotbarSlots = getHotbarSlotCount(),
		maxWeight = getMaxWeight(),
		totalWeight = InventoryService.GetTotalWeight(playerObj.PlayerData.items),
	}
end

function InventoryService.CanAddItem(playerObj, itemName, amount, slot, info)
	if not playerObj then
		return false, "Character not loaded."
	end

	local definition = getItemDefinition(itemName)
	amount = normalizeAmount(amount)
	if not definition then
		return false, "Unknown item."
	end
	if not amount then
		return false, "Invalid amount."
	end

	InventoryService.ReconcilePlayerData(playerObj.PlayerData)

	local addedWeight = (tonumber(definition.weight) or 0) * amount
	if InventoryService.GetTotalWeight(playerObj.PlayerData.items) + addedWeight > getMaxWeight() then
		return false, "Inventory is too heavy."
	end

	local simulated = deepCopy(playerObj.PlayerData.items)
	return insertItems(simulated, definition, amount, slot, info)
end

function InventoryService.AddItem(playerObj, itemName, amount, slot, info, reason)
	if not playerObj then
		return false, "Character not loaded."
	end

	local definition = getItemDefinition(itemName)
	amount = normalizeAmount(amount)
	if not definition then
		return false, "Unknown item."
	end
	if not amount then
		return false, "Invalid amount."
	end

	local ok, err = InventoryService.CanAddItem(playerObj, definition.name, amount, slot, info)
	if not ok then
		return false, err
	end

	local inserted, insertErr = insertItems(playerObj.PlayerData.items, definition, amount, slot, info)
	if not inserted then
		return false, insertErr
	end

	updatePlayerItems(playerObj)
	return true, reason
end

function InventoryService.RemoveItem(playerObj, itemName, amount, slot, reason)
	if not playerObj then
		return false, "Character not loaded."
	end

	itemName = normalizeItemName(itemName)
	amount = normalizeAmount(amount)
	if not itemName then
		return false, "Invalid item."
	end
	if not amount then
		return false, "Invalid amount."
	end

	InventoryService.ReconcilePlayerData(playerObj.PlayerData)

	local remaining = amount
	if slot then
		local targetSlot = normalizeSlot(slot)
		if not targetSlot then
			return false, "Invalid slot."
		end

		local item = getStoredItem(playerObj.PlayerData.items, targetSlot)
		if not item or item.name ~= itemName then
			return false, "Item not found."
		end

		if (tonumber(item.amount) or 0) < amount then
			return false, "Not enough items."
		end

		item.amount -= amount
		if item.amount <= 0 then
			setStoredItem(playerObj.PlayerData.items, targetSlot, nil)
		else
			setStoredItem(playerObj.PlayerData.items, targetSlot, item)
		end

		updatePlayerItems(playerObj)
		return true, reason
	end

	local available = 0
	for currentSlot = 1, getSlotCount() do
		local item = getStoredItem(playerObj.PlayerData.items, currentSlot)
		if item and item.name == itemName then
			available += tonumber(item.amount) or 0
		end
	end
	if available < amount then
		return false, "Not enough items."
	end

	for currentSlot = 1, getSlotCount() do
		local item = getStoredItem(playerObj.PlayerData.items, currentSlot)
		if item and item.name == itemName and remaining > 0 then
			local currentAmount = tonumber(item.amount) or 0
			local removed = math.min(currentAmount, remaining)
			item.amount = currentAmount - removed
			remaining -= removed

			if item.amount <= 0 then
				setStoredItem(playerObj.PlayerData.items, currentSlot, nil)
			else
				setStoredItem(playerObj.PlayerData.items, currentSlot, item)
			end
		end
	end

	if remaining > 0 then
		return false, "Not enough items."
	end

	updatePlayerItems(playerObj)
	return true, reason
end

function InventoryService.MoveItem(playerObj, fromSlot, toSlot)
	if not playerObj then
		return false, "Character not loaded."
	end

	fromSlot = normalizeSlot(fromSlot)
	toSlot = normalizeSlot(toSlot)
	if not fromSlot or not toSlot then
		return false, "Invalid slot."
	end
	if fromSlot == toSlot then
		return true
	end

	InventoryService.ReconcilePlayerData(playerObj.PlayerData)

	local fromItem = getStoredItem(playerObj.PlayerData.items, fromSlot)
	if not fromItem then
		return false, "There is no item in that slot."
	end

	local toItem = getStoredItem(playerObj.PlayerData.items, toSlot)
	if not toItem then
		setStoredItem(playerObj.PlayerData.items, fromSlot, nil)
		setStoredItem(playerObj.PlayerData.items, toSlot, fromItem)
		updatePlayerItems(playerObj)
		return true
	end

	local fromDefinition = getItemDefinition(fromItem.name)
	if
		fromDefinition
		and not fromDefinition.unique
		and fromItem.name == toItem.name
		and deepEqual(fromItem.info or {}, toItem.info or {})
	then
		local combined = (tonumber(fromItem.amount) or 0) + (tonumber(toItem.amount) or 0)
		if combined <= getMaxStack() then
			toItem.amount = combined
			setStoredItem(playerObj.PlayerData.items, fromSlot, nil)
			setStoredItem(playerObj.PlayerData.items, toSlot, toItem)
			updatePlayerItems(playerObj)
			return true
		end
	end

	setStoredItem(playerObj.PlayerData.items, fromSlot, toItem)
	setStoredItem(playerObj.PlayerData.items, toSlot, fromItem)
	updatePlayerItems(playerObj)
	return true
end

function InventoryService.GiveSlot(playerObj, slot)
	if not playerObj then
		return false, "Character not loaded."
	end

	slot = normalizeSlot(slot)
	if not slot then
		return false, "Invalid slot."
	end

	InventoryService.ReconcilePlayerData(playerObj.PlayerData)

	local item = getStoredItem(playerObj.PlayerData.items, slot)
	local definition = getItemDefinition(item and item.name)
	if not item or not definition then
		return false, "Item not found."
	end

	local amount = 1
	if (tonumber(item.amount) or 0) < amount then
		return false, "Not enough items."
	end

	local target, targetErr = findClosestGiveTarget(playerObj)
	if not target then
		return false, targetErr
	end

	local info = copyInfo(item.info)
	local canAdd, canAddErr = InventoryService.CanAddItem(target.playerObj, definition.name, amount, nil, info)
	if not canAdd then
		return false, canAddErr or "That player cannot carry this item."
	end

	local removed, removeErr = InventoryService.RemoveItem(playerObj, definition.name, amount, slot, "give-item")
	if not removed then
		return false, removeErr
	end
	clearGivenWeaponTool(getRobloxPlayer(playerObj), definition)

	local added, addErr = InventoryService.AddItem(target.playerObj, definition.name, amount, nil, info, "give-item")
	if not added then
		local rolledBack, rollbackErr = InventoryService.AddItem(playerObj, definition.name, amount, slot, info, "give-item-rollback")
		if not rolledBack then
			warn(
				("[QBCore.InventoryService] Failed to roll back give of %s from %s: %s"):format(
					definition.name,
					tostring(playerObj:GetName()),
					tostring(rollbackErr)
				)
			)
		end
		return false, addErr or "That player could not receive the item."
	end

	local label = definition.label or definition.name
	local sourceName = playerObj:GetName()
	local targetName = target.playerObj:GetName()
	playerObj:Notify(("Gave %s to %s."):format(label, targetName), "success", 2500)
	target.playerObj:Notify(("Received %s from %s."):format(label, sourceName), "success", 3000)

	return true
end

function InventoryService.SetInventory(playerObj, items)
	if not playerObj then
		return false, "Character not loaded."
	end
	playerObj.PlayerData.items = type(items) == "table" and deepCopy(items) or {}
	InventoryService.ReconcilePlayerData(playerObj.PlayerData)
	updatePlayerItems(playerObj)
	return true
end

function InventoryService.GetItemBySlot(playerObj, slot)
	if not playerObj then
		return nil
	end
	InventoryService.ReconcilePlayerData(playerObj.PlayerData)
	local item = getStoredItem(playerObj.PlayerData.items, slot)
	return item and hydrateItemForClient(item) or nil
end

function InventoryService.GetItemsByName(playerObj, itemName)
	if not playerObj then
		return {}
	end
	itemName = normalizeItemName(itemName)
	if not itemName then
		return {}
	end

	InventoryService.ReconcilePlayerData(playerObj.PlayerData)

	local found = {}
	for slot = 1, getSlotCount() do
		local item = getStoredItem(playerObj.PlayerData.items, slot)
		if item and item.name == itemName then
			found[#found + 1] = hydrateItemForClient(item)
		end
	end
	return found
end

function InventoryService.GetItemByName(playerObj, itemName)
	return InventoryService.GetItemsByName(playerObj, itemName)[1]
end

function InventoryService.GetItemCount(playerObj, items)
	if not playerObj then
		return 0
	end
	InventoryService.ReconcilePlayerData(playerObj.PlayerData)

	local wanted = {}
	if type(items) == "string" then
		wanted[normalizeItemName(items)] = true
	elseif type(items) == "table" then
		for _, itemName in pairs(items) do
			itemName = normalizeItemName(itemName)
			if itemName then
				wanted[itemName] = true
			end
		end
	end

	local count = 0
	for slot = 1, getSlotCount() do
		local item = getStoredItem(playerObj.PlayerData.items, slot)
		if item and wanted[item.name] then
			count += tonumber(item.amount) or 0
		end
	end

	return count
end

function InventoryService.HasItem(playerObj, items, amount)
	amount = normalizeAmount(amount) or 1

	if type(items) == "string" then
		return InventoryService.GetItemCount(playerObj, items) >= amount
	end

	if type(items) ~= "table" then
		return false
	end

	for key, value in pairs(items) do
		local itemName = nil
		local requiredAmount = amount

		if type(key) == "number" then
			itemName = value
		else
			itemName = key
			requiredAmount = normalizeAmount(value) or amount
		end

		if InventoryService.GetItemCount(playerObj, itemName) < requiredAmount then
			return false
		end
	end

	return true
end

function InventoryService.SetItemData(playerObj, itemName, key, value, slot)
	if not playerObj or type(key) ~= "string" then
		return false
	end

	InventoryService.ReconcilePlayerData(playerObj.PlayerData)

	local item = nil
	if slot then
		item = getStoredItem(playerObj.PlayerData.items, slot)
		if item and normalizeItemName(itemName) and item.name ~= normalizeItemName(itemName) then
			return false
		end
	else
		for currentSlot = 1, getSlotCount() do
			local candidate = getStoredItem(playerObj.PlayerData.items, currentSlot)
			if candidate and candidate.name == normalizeItemName(itemName) then
				item = candidate
				slot = currentSlot
				break
			end
		end
	end

	if not item or not slot then
		return false
	end
	item.info = type(item.info) == "table" and item.info or {}
	item.info[key] = value
	setStoredItem(playerObj.PlayerData.items, slot, item)
	updatePlayerItems(playerObj)
	return true
end

function InventoryService.CreateUseableItem(itemName, handler)
	itemName = normalizeItemName(itemName)
	if not itemName or type(handler) ~= "function" then
		return false
	end
	useableHandlers[itemName] = handler
	return true
end

function InventoryService.UseSlot(playerObj, slot)
	if not playerObj then
		return false, "Character not loaded."
	end
	if playerObj:GetMetaData("isdead") == true then
		return false, "You cannot use items while dead."
	end

	slot = normalizeSlot(slot)
	if not slot then
		return false, "Invalid slot."
	end

	InventoryService.ReconcilePlayerData(playerObj.PlayerData)

	local item = getStoredItem(playerObj.PlayerData.items, slot)
	local definition = getItemDefinition(item and item.name)
	if not item or not definition then
		return false, "Item not found."
	end

	local used = false
	local successMessage = nil
	local handler = useableHandlers[definition.name]
	if handler then
		local ok, err, message = handler(playerObj, hydrateItemForClient(item), definition)
		if ok == false then
			return false, err or "Item could not be used."
		end
		used = true
		successMessage = message
	elseif type(definition.consume) == "table" then
		for meta, value in pairs(definition.consume) do
			local current = tonumber(playerObj:GetMetaData(meta)) or 0
			playerObj:SetMetaData(meta, current + (tonumber(value) or 0))
			used = true
		end
	end

	if not used and definition.useable ~= true then
		return false, "That item is not useable."
	elseif not used then
		return false, "Nothing happens."
	end

	if definition.removeOnUse ~= false then
		local removed, err = InventoryService.RemoveItem(playerObj, definition.name, 1, slot, "use-item")
		if not removed then
			return false, err
		end
	else
		updatePlayerItems(playerObj)
	end

	playerObj:Notify(successMessage or ("Used %s."):format(definition.label or definition.name), "success", 2500)
	return true
end

return InventoryService
