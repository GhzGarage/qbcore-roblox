-- Client-side mirror of WeaponService's reserve-ammo clamp. The Weapons Kit
-- predicts reloads locally by filling CurrentAmmo toward capacity before the
-- server confirms, so snap that prediction to the ammo items we actually carry
-- (partial reloads included) and the HUD never shows bullets the server is
-- about to take back.
--
-- Note: tools/patch-weapons-noammo-reload.lua fixes the actual exploit where
-- firing (not reloading) with an empty magazine could re-trigger a full refill
-- with zero reserve ammo. That has to be patched in the kit's own BaseWeapon
-- source -- useAmmo() and reload() are called back-to-back inside the kit's
-- fire(), with no yield in between, so no client script can intervene there.
-- This script only handles legitimate reloads (R / gamepad) that partially or
-- fully exceed what the player is carrying.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local QBCoreClient = require(ReplicatedStorage.QBCoreClient)
local QBShared = require(ReplicatedStorage.QBShared.Main)

local player = Players.LocalPlayer

local WEAPON_TOOL_ATTRIBUTE = "QBWeaponTool"
local WEAPON_ITEM_ATTRIBUTE = "QBInventoryItemName"
local CURRENT_AMMO_NAME = "CurrentAmmo"
local RELOAD_KEYS = {
	[Enum.KeyCode.R] = true,
	[Enum.KeyCode.ButtonX] = true,
}
local NOTIFY_COOLDOWN = 1.5

local weaponConnections = {}
local characterConnections = {}

local currentAmmoItemName = nil
local currentAmmoLabel = nil
local currentCapacity = nil
local currentAmmoValue = nil
local lastNotifyAt = 0

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

local function notifyNoAmmo()
	if os.clock() - lastNotifyAt < NOTIFY_COOLDOWN then
		return
	end
	lastNotifyAt = os.clock()
	QBCoreClient.OnNotify:Fire(("No %s left."):format(currentAmmoLabel or "ammo"), "error", 2000)
end

local function bindAmmoValue(ammoValue)
	currentAmmoValue = ammoValue
	local lastAmmo = tonumber(ammoValue.Value) or 0
	local applying = false

	weaponConnections[#weaponConnections + 1] = ammoValue.Changed:Connect(function(newValue)
		if applying then
			return
		end

		newValue = tonumber(newValue) or 0
		if newValue <= lastAmmo then
			lastAmmo = newValue
			return
		end

		local requested = newValue - lastAmmo
		local loaded = math.min(requested, countReserve(currentAmmoItemName))
		if loaded < requested then
			applying = true
			ammoValue.Value = lastAmmo + loaded
			applying = false
			if loaded == 0 then
				notifyNoAmmo()
			end
		end
		lastAmmo += loaded
	end)
end

local function watchWeapon(tool)
	disconnectAll(weaponConnections)
	currentAmmoItemName = nil
	currentAmmoLabel = nil
	currentCapacity = nil
	currentAmmoValue = nil

	if not tool then
		return
	end

	local definition = getWeaponDefinition(tool)
	local weapon = definition and type(definition.weapon) == "table" and definition.weapon or {}
	local ammoItemName = type(weapon.ammoItem) == "string" and weapon.ammoItem or nil
	if not ammoItemName then
		return
	end

	local ammoDefinition = QBShared.Items[ammoItemName]
	local configValues = type(weapon.config) == "table" and weapon.config
		or type(weapon.configuration) == "table" and weapon.configuration
		or nil

	currentAmmoItemName = ammoItemName
	currentAmmoLabel = ammoDefinition and ammoDefinition.label or ammoItemName
	currentCapacity = configValues and tonumber(configValues.AmmoCapacity) or nil

	local ammoValue = tool:FindFirstChild(CURRENT_AMMO_NAME)
	if ammoValue and ammoValue:IsA("ValueBase") then
		bindAmmoValue(ammoValue)
	else
		weaponConnections[#weaponConnections + 1] = tool.ChildAdded:Connect(function(child)
			if child.Name == CURRENT_AMMO_NAME and child:IsA("ValueBase") and not currentAmmoValue then
				bindAmmoValue(child)
			end
		end)
	end
end

local function bindCharacter(character)
	disconnectAll(characterConnections)
	watchWeapon(nil)

	characterConnections[#characterConnections + 1] = character.ChildAdded:Connect(function(child)
		if isWeaponTool(child) then
			watchWeapon(child)
		end
	end)

	characterConnections[#characterConnections + 1] = character.ChildRemoved:Connect(function(child)
		if not child:IsA("Tool") then
			return
		end
		local equipped = character:FindFirstChildOfClass("Tool")
		watchWeapon(equipped and isWeaponTool(equipped) and equipped or nil)
	end)

	local equipped = character:FindFirstChildOfClass("Tool")
	if equipped and isWeaponTool(equipped) then
		watchWeapon(equipped)
	end
end

-- Immediate feedback for a direct R-press with an empty reserve, even before
-- the kit's own reload guard (correctly) refuses to do anything.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not RELOAD_KEYS[input.KeyCode] then
		return
	end
	if not currentAmmoItemName or countReserve(currentAmmoItemName) > 0 then
		return
	end

	local loaded = currentAmmoValue and tonumber(currentAmmoValue.Value) or nil
	if loaded and currentCapacity and loaded >= currentCapacity then
		return
	end
	notifyNoAmmo()
end)

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	task.defer(bindCharacter, player.Character)
end
