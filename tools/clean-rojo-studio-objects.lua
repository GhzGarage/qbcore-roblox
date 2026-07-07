-- Run this in Roblox Studio's Command Bar while NOT playing and with the Rojo
-- plugin disconnected. It removes only the known objects managed by this Rojo
-- project, including stale copies from earlier manual setup attempts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local StarterPlayerScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")

local targets = {
    { parent = ReplicatedStorage, names = {
        "QBShared",
        "QBRemoteNames",
        "QBRemotes",
        "QBCoreClient",
        "QBRemoteInstances",
    } },
    { parent = ServerScriptService, names = {
        "QBCore",
        "init.server",
        "Main",
        "Access",
        "AdminService",
        "AppearanceService",
        "CommandService",
        "Commands",
        "InventoryService",
        "ProfileStore",
        "PlayerService",
        "PlayerClass",
        "TimeSyncService",
    } },
}

if StarterPlayerScripts then
    table.insert(targets, {
        parent = StarterPlayerScripts,
        names = {
            "QBAppearance",
            "QBAdmin",
            "QBCoreClient",
            "QBHUD",
            "QBInventory",
            "QBNotify",
            "QBTimeCycle",
            "init.client",
        },
    })
end

local removed = 0

for _, target in ipairs(targets) do
    for _, name in ipairs(target.names) do
        for _, child in ipairs(target.parent:GetChildren()) do
            if child.Name == name then
                print(("[Rojo clean] Removing %s (%s)"):format(child:GetFullName(), child.ClassName))
                child:Destroy()
                removed += 1
            end
        end
    end
end

print(("[Rojo clean] Removed %d object(s). Reconnect Rojo to localhost:34872 now."):format(removed))
