-- Run this in Roblox Studio's Command Bar while NOT playing.
--
-- Some endorsed Roblox WeaponsSystem versions correctly guard Tool.Equipped, but
-- still auto-mark any weapon under Workspace as equipped during setup. Equipped
-- player Tools are replicated under Workspace, so another player's weapon can
-- become the local client's current weapon and enable the crosshair/camera.
--
-- This patches:
-- 1. WeaponsSystem.setWeaponEquipped(): ignore non-local player weapons.
-- 2. Libraries/BaseWeapon: only auto-equip Workspace weapons for the server or
--    the local player's own character.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPack = game:GetService("StarterPack")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local containers = {
	ReplicatedStorage,
	ServerScriptService,
	ServerStorage,
	StarterPack,
	StarterPlayer,
	Workspace,
}

local function literalPattern(value)
	return (value:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function findWeaponsSystemFolder()
	for _, container in ipairs(containers) do
		local weaponsSystem = container:FindFirstChild("WeaponsSystem")
		if weaponsSystem and weaponsSystem:IsA("Folder") then
			return weaponsSystem
		end
	end

	for _, container in ipairs(containers) do
		for _, descendant in ipairs(container:GetDescendants()) do
			if descendant:IsA("Folder") and descendant.Name == "WeaponsSystem" then
				return descendant
			end
		end
	end

	return nil
end

local function getModule(parent, path)
	local current = parent
	for _, name in ipairs(path) do
		current = current and current:FindFirstChild(name)
	end

	if current and current:IsA("ModuleScript") then
		return current
	end

	return nil
end

local function patchWeaponsSystem(moduleScript)
	local source = moduleScript.Source
	if source:find("weapon.player ~= Players.LocalPlayer", 1, true) then
		return false
	end

	local old = [[function WeaponsSystem.setWeaponEquipped(weapon, equipped)
	assert(not IsServer, "WeaponsSystem.setWeaponEquipped should only be called on the client.")
	if not weapon then
		return
	end]]

	local new = [[function WeaponsSystem.setWeaponEquipped(weapon, equipped)
	assert(not IsServer, "WeaponsSystem.setWeaponEquipped should only be called on the client.")
	if not weapon then
		return
	end
	if weapon.player ~= Players.LocalPlayer then
		return
	end]]

	local patched, count = source:gsub(literalPattern(old), new, 1)
	if count == 0 then
		error(
			"[Weapons patch] Found "
				.. moduleScript:GetFullName()
				.. ", but could not patch setWeaponEquipped(). Add this after the nil check: if weapon.player ~= Players.LocalPlayer then return end"
		)
	end

	moduleScript.Source = patched
	return true
end

local function patchBaseWeapon(moduleScript)
	local source = moduleScript.Source
	local new = "if self.instance:IsDescendantOf(workspace) and self.player and (IsServer or self.player == Players.LocalPlayer) then"
	if source:find(new, 1, true) then
		return false
	end

	local old = "if self.instance:IsDescendantOf(workspace) and self.player then"
	local patched, count = source:gsub(literalPattern(old), new, 1)
	if count == 0 then
		error(
			"[Weapons patch] Found "
				.. moduleScript:GetFullName()
				.. ", but could not patch the Workspace auto-equip block."
		)
	end

	moduleScript.Source = patched
	return true
end

local weaponsSystem = findWeaponsSystemFolder()
if not weaponsSystem then
	error("[Weapons patch] Could not find a WeaponsSystem folder.")
end

local weaponsSystemModule = getModule(weaponsSystem, { "WeaponsSystem" })
local baseWeaponModule = getModule(weaponsSystem, { "Libraries", "BaseWeapon" })

if not weaponsSystemModule then
	error("[Weapons patch] Could not find WeaponsSystem/WeaponsSystem ModuleScript.")
end
if not baseWeaponModule then
	error("[Weapons patch] Could not find WeaponsSystem/Libraries/BaseWeapon ModuleScript.")
end

local changed = 0
if patchWeaponsSystem(weaponsSystemModule) then
	changed = changed + 1
end
if patchBaseWeapon(baseWeaponModule) then
	changed = changed + 1
end

if changed == 0 then
	print(("[Weapons patch] %s already has the local crosshair fixes."):format(weaponsSystem:GetFullName()))
else
	print(("[Weapons patch] Patched %s with %d local crosshair fix(es). Stop and Play again."):format(weaponsSystem:GetFullName(), changed))
end
