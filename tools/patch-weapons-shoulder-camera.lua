-- Run this in Roblox Studio's Command Bar while NOT playing.
--
-- Roblox's endorsed WeaponsSystem ShoulderCamera can spam:
-- "Unable to assign property C0. Property is read only"
-- from applyRootJointFix(). This wraps that root-joint write once and disables
-- the tiny visual fix if the current rig/runtime rejects it.

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

local function findShoulderCamera()
    for _, container in ipairs(containers) do
        local weaponsSystem = container:FindFirstChild("WeaponsSystem")
        local libraries = weaponsSystem and weaponsSystem:FindFirstChild("Libraries")
        local shoulderCamera = libraries and libraries:FindFirstChild("ShoulderCamera")
        if shoulderCamera and shoulderCamera:IsA("ModuleScript") then
            return shoulderCamera
        end
    end

    for _, container in ipairs(containers) do
        for _, descendant in ipairs(container:GetDescendants()) do
            if descendant:IsA("ModuleScript") and descendant.Name == "ShoulderCamera" then
                return descendant
            end
        end
    end

    return nil
end

local shoulderCamera = findShoulderCamera()
if not shoulderCamera then
    error("[Weapons patch] Could not find WeaponsSystem/Libraries/ShoulderCamera.")
end

local source = shoulderCamera.Source
if source:find("rootJointFixFailed", 1, true) then
    print(("[Weapons patch] %s is already patched."):format(shoulderCamera:GetFullName()))
    return
end

local replacement = [[
if not self.rootJointFixFailed then
    local ok = pcall(function()
        self.rootJoint.C0 = CFrame.new(self.rootJoint.C0.Position, self.rootJoint.C0.Position + rotationFix.LookVector)
    end)
    self.rootJointFixFailed = not ok
end]]

local patched, count = source:gsub(
    "self%.rootJoint%.C0%s*=%s*CFrame%.new%(%s*self%.rootJoint%.C0%.Position%s*,%s*self%.rootJoint%.C0%.Position%s*%+%s*rotationFix%.[Ll]ookVector%s*%)",
    replacement,
    1
)

if count == 0 then
    local functionStart = source:find("function%s+ShoulderCamera:applyRootJointFix%s*%(")
    local nextFunctionStart = functionStart and source:find("\nfunction%s+ShoulderCamera:", functionStart + 1)

    if not functionStart or not nextFunctionStart then
        error(
            "[Weapons patch] Found ShoulderCamera, but could not find applyRootJointFix(). "
                .. "Open "
                .. shoulderCamera:GetFullName()
                .. " and patch applyRootJointFix() manually."
        )
    end

    local noopFunction = [[
function ShoulderCamera:applyRootJointFix()
    -- Disabled by QBCore setup: current Roblox runtimes can reject rootJoint.C0 writes.
    self.rootJointFixFailed = true
end
]]

    patched = source:sub(1, functionStart - 1) .. noopFunction .. source:sub(nextFunctionStart + 1)
end

shoulderCamera.Source = patched
print(("[Weapons patch] Patched %s. Stop and Play again."):format(shoulderCamera:GetFullName()))
