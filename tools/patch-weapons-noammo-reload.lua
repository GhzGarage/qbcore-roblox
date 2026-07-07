-- Run this in Roblox Studio's Command Bar while NOT playing.
--
-- Root cause: BaseWeapon:useAmmo() unconditionally sets self.canReload = true on
-- every trigger pull, even a dry one that used 0 ammo. BaseWeapon:fire() calls
-- useAmmo() and, if it returns <= 0, immediately calls self:reload() in the same
-- function -- no yield in between. So once a weapon has auto-reloaded empty and
-- canReload goes back to false, simply firing again (not pressing R) re-arms
-- canReload and re-triggers reload(), refilling the magazine to full even with
-- zero reserve ammo. This can't be blocked from outside the kit (no script can
-- run between useAmmo() and reload() inside the same call), so it has to be
-- patched at the source: only re-arm canReload when a shot actually used ammo.
--
-- This patches:
-- WeaponsSystem/Libraries/BaseWeapon:useAmmo() to skip the canReload = true
-- line when ammoUsed is 0.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPack = game:GetService("StarterPack")
local Workspace = game:GetService("Workspace")

local containers = {
	ServerScriptService,
	ReplicatedStorage,
	ServerStorage,
	StarterPack,
	Workspace,
}

local function findBaseWeapon()
	for _, container in ipairs(containers) do
		local weaponsSystem = container:FindFirstChild("WeaponsSystem")
		local libraries = weaponsSystem and weaponsSystem:FindFirstChild("Libraries")
		local baseWeapon = libraries and libraries:FindFirstChild("BaseWeapon")
		if baseWeapon and baseWeapon:IsA("ModuleScript") then
			return baseWeapon
		end
	end

	for _, container in ipairs(containers) do
		for _, descendant in ipairs(container:GetDescendants()) do
			if descendant:IsA("ModuleScript") and descendant.Name == "BaseWeapon" then
				return descendant
			end
		end
	end

	return nil
end

local function literalPattern(value)
	return (value:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function patchUseAmmo(moduleScript)
	local source = moduleScript.Source
	if source:find("if ammoUsed > 0 then", 1, true) and source:find("self.canReload = true", 1, true) then
		-- Could already be patched, or canReload = true could still appear
		-- elsewhere (onReloaded/new/cancelReload all set it too) -- only skip if
		-- the specific useAmmo copy is gone.
		local useAmmoStart = source:find("function BaseWeapon:useAmmo", 1, true)
		if useAmmoStart then
			local useAmmoEnd = source:find("\nend", useAmmoStart, true)
			local body = useAmmoEnd and source:sub(useAmmoStart, useAmmoEnd) or ""
			if body:find("if ammoUsed > 0 then", 1, true) then
				return false
			end
		end
	end

	local old = [[		self.ammoInWeaponValue.Value = self.ammoInWeaponValue.Value - ammoUsed
		self.canReload = true
		return ammoUsed]]

	local new = [[		self.ammoInWeaponValue.Value = self.ammoInWeaponValue.Value - ammoUsed
		if ammoUsed > 0 then
			self.canReload = true
		end
		return ammoUsed]]

	local patched, count = source:gsub(literalPattern(old), new, 1)
	if count == 0 then
		error(
			"[Weapons patch] Found "
				.. moduleScript:GetFullName()
				.. ", but could not patch useAmmo(). Inside BaseWeapon:useAmmo(), wrap the line "
				.. "'self.canReload = true' in 'if ammoUsed > 0 then ... end' so a dry-fire "
				.. "(0 ammo) no longer re-arms reload eligibility."
		)
	end

	moduleScript.Source = patched
	return true
end

local baseWeapon = findBaseWeapon()
if not baseWeapon then
	error("[Weapons patch] Could not find WeaponsSystem/Libraries/BaseWeapon ModuleScript.")
end

if patchUseAmmo(baseWeapon) then
	print(("[Weapons patch] Patched %s: dry-fire no longer re-arms reload. Stop and Play again."):format(baseWeapon:GetFullName()))
else
	print(("[Weapons patch] %s already has the no-ammo reload fix."):format(baseWeapon:GetFullName()))
end
