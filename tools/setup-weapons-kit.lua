-- Run this in Roblox Studio's Command Bar while NOT playing after inserting an
-- endorsed Roblox weapon from Toolbox. It creates the QBCore weapon template
-- folder and moves the imported pistol/system instances to their expected homes.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPack = game:GetService("StarterPack")
local Workspace = game:GetService("Workspace")

local TOOL_FOLDER_NAME = "QBWeaponTools"
local SYSTEM_FOLDER_NAME = "WeaponsSystem"
local WEAPON_TOOL_NAMES = {
    AR = true,
    AutoRifle = true,
    ["Auto Rifle"] = true,
    Crossbow = true,
    GrenadeLauncher = true,
    ["Grenade Launcher"] = true,
    Pistol = true,
    Railgun = true,
    RocketLauncher = true,
    ["Rocket Launcher"] = true,
    Shotgun = true,
    SMG = true,
    Sniper = true,
    SniperRifle = true,
    ["Sniper Rifle"] = true,
    SubmachineGun = true,
    ["Submachine Gun"] = true,
}

local function ensureFolder(parent, name)
    local folder = parent:FindFirstChild(name)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = name
        folder.Parent = parent
        print(("[Weapons setup] Created %s."):format(folder:GetFullName()))
    end
    return folder
end

local toolFolder = ensureFolder(ServerStorage, TOOL_FOLDER_NAME)

local function moveWeaponTools(container)
    for _, descendant in ipairs(container:GetDescendants()) do
        if descendant:IsA("Tool") and WEAPON_TOOL_NAMES[descendant.Name] and descendant.Parent ~= toolFolder then
            print(("[Weapons setup] Moving %s to %s."):format(descendant:GetFullName(), toolFolder:GetFullName()))
            descendant.Parent = toolFolder
        end
    end
end

for _, container in ipairs({ Workspace, StarterPack, ServerStorage }) do
    moveWeaponTools(container)
end

local function moveWeaponsSystem(container)
    if ServerScriptService:FindFirstChild(SYSTEM_FOLDER_NAME) then
        return false
    end

    for _, descendant in ipairs(container:GetDescendants()) do
        if descendant:IsA("Folder") and descendant.Name == SYSTEM_FOLDER_NAME then
            print(("[Weapons setup] Moving %s to ServerScriptService."):format(descendant:GetFullName()))
            descendant.Parent = ServerScriptService
            return true
        end
    end

    return false
end

if not ServerScriptService:FindFirstChild(SYSTEM_FOLDER_NAME) then
    for _, container in ipairs({ Workspace, StarterPack, ServerStorage, ReplicatedStorage }) do
        if moveWeaponsSystem(container) then
            break
        end
    end
end

if ServerScriptService:FindFirstChild(SYSTEM_FOLDER_NAME) then
    print("[Weapons setup] WeaponsSystem is in ServerScriptService.")
else
    warn("[Weapons setup] No WeaponsSystem folder was found. Insert the endorsed pistol, then run this again.")
end

if toolFolder:FindFirstChild("Pistol") then
    print("[Weapons setup] Pistol is in ServerStorage/QBWeaponTools.")
else
    warn("[Weapons setup] No Pistol Tool was found. Insert the endorsed pistol, then run this again.")
end
