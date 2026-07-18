-- Inventory-backed Roblox Tool equip flow.
--
-- Weapon items live in PlayerData like every other QBCore item. The actual Roblox
-- Tool stays as a server-side template and is cloned into the player's Backpack
-- only while equipped, so no pickup weapon has to sit in Workspace.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPack = game:GetService("StarterPack")
local Workspace = game:GetService("Workspace")

local QBShared = require(ReplicatedStorage.QBShared.Main)

local WeaponService = {}

local TOOL_FOLDER_NAME = "QBWeaponTools"
local SYSTEM_FOLDER_NAME = "WeaponsSystem"
local CONFIGURATION_NAME = "Configuration"
local REGISTERED_ATTRIBUTE = "QBWeaponTool"
local ITEM_ATTRIBUTE = "QBInventoryItemName"
local SLOT_ATTRIBUTE = "QBInventorySlot"
local TEMPLATE_ATTRIBUTE = "QBToolTemplateName"

local started = false
local inventoryService = nil
local toolFolder = nil
local weaponDefinitionsByName = {}
local configuredToolNames = {}
local CONFIG_VALUE_CLASS_BY_TYPE = {
	boolean = "BoolValue",
	number = "NumberValue",
	string = "StringValue",
}

local function ensureToolFolder()
	if toolFolder and toolFolder.Parent then
		return toolFolder
	end

	toolFolder = ServerStorage:FindFirstChild(TOOL_FOLDER_NAME)
	if not toolFolder then
		toolFolder = Instance.new("Folder")
		toolFolder.Name = TOOL_FOLDER_NAME
		toolFolder.Parent = ServerStorage
	end

	return toolFolder
end

local function getSystemFolder()
	return ServerScriptService:FindFirstChild(SYSTEM_FOLDER_NAME)
end

local function addUnique(list, lookup, value)
	if type(value) ~= "string" then
		return
	end

	value = value:gsub("^%s+", ""):gsub("%s+$", "")
	if value == "" or lookup[value] then
		return
	end

	lookup[value] = true
	list[#list + 1] = value
end

local function titleCase(value)
	return (value:gsub("^%l", string.upper))
end

local function titleCaseWords(value)
	return (value:gsub("(%a)([%w_']*)", function(first, rest)
		return first:upper() .. rest:lower()
	end))
end

local function compactName(value)
	if type(value) ~= "string" then
		return nil
	end
	value = value:gsub("[%s_%-]+", "")
	return value ~= "" and value or nil
end

local function addToolNameVariants(list, lookup, value)
	addUnique(list, lookup, value)
	if type(value) ~= "string" then
		return
	end

	local spaced = value:gsub("_", " ")
	addUnique(list, lookup, spaced)
	addUnique(list, lookup, titleCaseWords(spaced))
	addUnique(list, lookup, compactName(value))
	addUnique(list, lookup, compactName(titleCaseWords(spaced)))
end

local function getToolNameCandidates(definition)
	local list = {}
	local lookup = {}
	local weapon = type(definition.weapon) == "table" and definition.weapon or {}

	addToolNameVariants(list, lookup, weapon.toolName)
	addToolNameVariants(list, lookup, definition.toolName)
	addToolNameVariants(list, lookup, definition.name)

	if type(definition.name) == "string" then
		local stripped = definition.name:match("^weapon_(.+)$")
		if stripped then
			addToolNameVariants(list, lookup, stripped)
			addToolNameVariants(list, lookup, titleCase(stripped))
		end
	end

	addToolNameVariants(list, lookup, definition.label)

	if type(weapon.toolNames) == "table" then
		for _, toolName in ipairs(weapon.toolNames) do
			addToolNameVariants(list, lookup, toolName)
		end
	end

	return list
end

local function getPlayerFromPlayerObj(playerObj)
	local player = playerObj and playerObj._source
	if typeof(player) == "Instance" and player:IsA("Player") then
		return player
	end
	return nil
end

local function isInPlayerCharacter(instance)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and instance:IsDescendantOf(character) then
			return true
		end
	end
	return false
end

local function isRegisteredWeaponTool(tool)
	return tool:GetAttribute(REGISTERED_ATTRIBUTE) == true
end

local function nameMatchesAnyWeapon(toolName)
	return configuredToolNames[toolName] == true
end

local function storeLooseWorkspaceTool(tool)
	if not tool:IsA("Tool") or isInPlayerCharacter(tool) then
		return
	end

	if not isRegisteredWeaponTool(tool) and not nameMatchesAnyWeapon(tool.Name) then
		return
	end

	if isRegisteredWeaponTool(tool) then
		tool:Destroy()
		return
	end

	local folder = ensureToolFolder()
	local existing = folder:FindFirstChild(tool.Name)
	if existing and existing:IsA("Tool") and existing ~= tool then
		tool:Destroy()
		return
	end

	tool.Parent = folder
end

local function storeLooseWeaponsSystem(folder)
	if not folder:IsA("Folder") or folder.Name ~= SYSTEM_FOLDER_NAME then
		return
	end
	if folder.Parent == ServerScriptService then
		return
	end

	local existing = getSystemFolder()
	if existing then
		return
	end

	folder.Parent = ServerScriptService
end

local function collectLooseImportedInstances()
	for _, container in ipairs({ Workspace, StarterPack, ServerStorage }) do
		for _, descendant in ipairs(container:GetDescendants()) do
			if descendant:IsA("Tool") then
				storeLooseWorkspaceTool(descendant)
			elseif descendant:IsA("Folder") and descendant.Name == SYSTEM_FOLDER_NAME then
				storeLooseWeaponsSystem(descendant)
			end
		end
	end
end

local function findToolTemplate(definition)
	collectLooseImportedInstances()

	local candidates = getToolNameCandidates(definition)
	local folder = ensureToolFolder()

	for _, toolName in ipairs(candidates) do
		local tool = folder:FindFirstChild(toolName)
		if tool and tool:IsA("Tool") then
			return tool
		end
	end

	for _, toolName in ipairs(candidates) do
		local tool = ServerStorage:FindFirstChild(toolName)
		if tool and tool:IsA("Tool") then
			tool.Parent = folder
			return tool
		end
	end

	return nil, candidates[1] or definition.label or definition.name
end

local function getConfiguredWeaponValues(definition)
	local weapon = type(definition.weapon) == "table" and definition.weapon or nil
	if not weapon then
		return nil
	end

	if type(weapon.config) == "table" then
		return weapon.config
	end

	if type(weapon.configuration) == "table" then
		return weapon.configuration
	end

	return nil
end

local function getOrCreateToolConfiguration(tool)
	local config = tool:FindFirstChild(CONFIGURATION_NAME)
	if config then
		if config:IsA("Configuration") then
			return config
		end

		warn(
			("[WeaponService] %s has a %q child that is a %s, not a Configuration."):format(
				tool:GetFullName(),
				CONFIGURATION_NAME,
				config.ClassName
			)
		)
		return nil
	end

	config = Instance.new("Configuration")
	config.Name = CONFIGURATION_NAME
	config.Parent = tool
	return config
end

local function getConfigValueClass(value)
	local valueType = typeof(value)
	return CONFIG_VALUE_CLASS_BY_TYPE[valueType]
end

local function setWeaponConfigValue(config, valueName, value)
	if type(valueName) ~= "string" or valueName == "" then
		return
	end

	local className = getConfigValueClass(value)
	if not className then
		warn(("[WeaponService] Ignoring unsupported weapon config %q (%s)."):format(valueName, typeof(value)))
		return
	end

	local valueObj = config:FindFirstChild(valueName)
	if valueObj and not valueObj:IsA("ValueBase") then
		warn(
			("[WeaponService] Ignoring weapon config %q because %s is a %s, not a ValueBase."):format(
				valueName,
				valueObj:GetFullName(),
				valueObj.ClassName
			)
		)
		return
	end

	if not valueObj then
		valueObj = Instance.new(className)
		valueObj.Name = valueName
		valueObj.Parent = config
	end

	local ok, err = pcall(function()
		valueObj.Value = value
	end)
	if not ok then
		warn(
			("[WeaponService] Could not set weapon config %q on %s: %s"):format(
				valueName,
				valueObj:GetFullName(),
				tostring(err)
			)
		)
	end
end

local function applyWeaponConfiguration(tool, definition)
	local configValues = getConfiguredWeaponValues(definition)
	if not configValues then
		return
	end

	local config = getOrCreateToolConfiguration(tool)
	if not config then
		return
	end

	for valueName, value in pairs(configValues) do
		setWeaponConfigValue(config, valueName, value)
	end
end

local function destroyWeaponTools(container, itemName)
	if not container then
		return false
	end

	local removed = false
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and isRegisteredWeaponTool(child) then
			if not itemName or child:GetAttribute(ITEM_ATTRIBUTE) == itemName then
				child:Destroy()
				removed = true
			end
		end
	end
	return removed
end

local function clearPlayerWeaponTools(player, itemName)
	local removed = false
	removed = destroyWeaponTools(player:FindFirstChildOfClass("Backpack"), itemName) or removed
	removed = destroyWeaponTools(player.Character, itemName) or removed
	return removed
end

-- Reserve-ammo economy on top of the endorsed Weapons Kit. The kit owns the
-- "CurrentAmmo" IntValue on each weapon Tool server-side: it creates it at full
-- capacity, decrements it per shot, and refills it to AmmoCapacity when a reload
-- finishes. Any increase therefore IS a reload (or the initial fill), so we charge
-- it against the player's ammo items (1 item = 1 bullet) and clamp the refill to
-- what they actually carry. The loaded count is persisted on the inventory item so
-- re-equipping does not grant a free magazine.
local CURRENT_AMMO_NAME = "CurrentAmmo"
local AMMO_INFO_KEY = "ammo"

local function saveLoadedAmmo(playerObj, tool, definition, ammo)
	if not inventoryService then
		return
	end

	ammo = math.max(0, math.floor(tonumber(ammo) or 0))
	local slot = tonumber(tool:GetAttribute(SLOT_ATTRIBUTE))
	if not inventoryService.SetItemData(playerObj, definition.name, AMMO_INFO_KEY, ammo, slot) then
		inventoryService.SetItemData(playerObj, definition.name, AMMO_INFO_KEY, ammo, nil)
	end
end

local function trackWeaponAmmo(playerObj, tool, item, definition)
	if not inventoryService then
		return
	end

	local ammoValue = tool:WaitForChild(CURRENT_AMMO_NAME, 10)
	if not ammoValue or not ammoValue:IsA("ValueBase") or tool.Parent == nil then
		return
	end
	local inventory = inventoryService

	local weapon = type(definition.weapon) == "table" and definition.weapon or {}
	local ammoItemName = type(weapon.ammoItem) == "string" and weapon.ammoItem or nil
	local configValues = getConfiguredWeaponValues(definition)
	local capacity = configValues and tonumber(configValues.AmmoCapacity) or nil

	-- The kit creates the value at 0 and fills it to capacity during its own
	-- setup; wait that out so the persisted count is not overwritten.
	local waitedUntil = os.clock() + 2
	while ammoValue.Value <= 0 and os.clock() < waitedUntil and tool.Parent ~= nil do
		task.wait(0.1)
	end

	local persisted = type(item.info) == "table" and tonumber(item.info[AMMO_INFO_KEY]) or nil
	if persisted then
		persisted = math.floor(persisted)
		ammoValue.Value = math.clamp(persisted, 0, capacity or math.max(persisted, 0))
	end

	local lastAmmo = tonumber(ammoValue.Value) or 0
	local applying = false

	ammoValue.Changed:Connect(function(newValue)
		if applying then
			return
		end

		newValue = tonumber(newValue) or 0
		if newValue <= lastAmmo or not ammoItemName then
			lastAmmo = newValue
			return
		end

		local requested = newValue - lastAmmo
		local available = inventory.GetItemCount(playerObj, ammoItemName)
		local loaded = math.min(requested, available)

		if loaded > 0 then
			inventory.RemoveItem(playerObj, ammoItemName, loaded, nil, "weapon-reload")
		end
		if loaded < requested then
			applying = true
			ammoValue.Value = lastAmmo + loaded
			applying = false
			if loaded == 0 then
				local ammoDefinition = QBShared.Items[ammoItemName]
				playerObj:Notify(
					("No %s left."):format(ammoDefinition and ammoDefinition.label or ammoItemName),
					"error",
					2500
				)
			end
		end

		lastAmmo += loaded
	end)

	tool.Destroying:Connect(function()
		saveLoadedAmmo(playerObj, tool, definition, lastAmmo)
	end)
end

local function equipWeapon(playerObj, item, definition)
	local player = getPlayerFromPlayerObj(playerObj)
	if not player then
		return false, "Character not loaded."
	end

	if clearPlayerWeaponTools(player, definition.name) then
		return true, nil, ("Holstered %s."):format(definition.label or definition.name)
	end

	local template, expectedName = findToolTemplate(definition)
	if not template then
		return false,
			("%s tool is not installed. Add a Tool named %q to ServerStorage > %s, or place it in Workspace once so QBCore can store it."):format(
				definition.label or definition.name,
				tostring(expectedName),
				TOOL_FOLDER_NAME
			)
	end

	clearPlayerWeaponTools(player)

	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then
		return false, "Backpack is not ready."
	end

	local clone = template:Clone()
	clone.CanBeDropped = false
	clone:SetAttribute(REGISTERED_ATTRIBUTE, true)
	clone:SetAttribute(ITEM_ATTRIBUTE, definition.name)
	clone:SetAttribute(SLOT_ATTRIBUTE, tonumber(item.slot) or 0)
	clone:SetAttribute(TEMPLATE_ATTRIBUTE, template.Name)
	applyWeaponConfiguration(clone, definition)
	clone.Parent = backpack
	task.spawn(trackWeaponAmmo, playerObj, clone, item, definition)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:EquipTool(clone)
	end

	return true, nil, ("Equipped %s."):format(definition.label or definition.name)
end

local function registerWeaponItems(InventoryService)
	table.clear(weaponDefinitionsByName)
	table.clear(configuredToolNames)

	for itemName, definition in pairs(QBShared.Items) do
		local weaponConfig = type(definition.weapon) == "table" and definition.weapon or nil
		if definition.type == "weapon" or weaponConfig then
			weaponDefinitionsByName[itemName] = definition
			for _, toolName in ipairs(getToolNameCandidates(definition)) do
				configuredToolNames[toolName] = true
			end

			InventoryService.CreateUseableItem(itemName, equipWeapon)
		end
	end
end

function WeaponService.Start(InventoryService)
	if started then
		return
	end
	started = true
	inventoryService = InventoryService

	ensureToolFolder()
	registerWeaponItems(InventoryService)
	collectLooseImportedInstances()

	for _, container in ipairs({ Workspace, StarterPack, ServerStorage }) do
		container.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("Tool") then
				task.defer(storeLooseWorkspaceTool, descendant)
			elseif descendant:IsA("Folder") and descendant.Name == SYSTEM_FOLDER_NAME then
				task.defer(storeLooseWeaponsSystem, descendant)
			end
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		clearPlayerWeaponTools(player)
	end)
end

function WeaponService.GetToolFolder()
	return ensureToolFolder()
end

return WeaponService
