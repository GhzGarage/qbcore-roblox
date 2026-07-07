--[[
    Client-side PlayerData cache (port of client/events.lua's OnPlayerUpdated handlers).
    Any LocalScript can require this to read the cache or hook the signals below.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.QBRemotes)

local QBCoreClient = {}

QBCoreClient.PlayerData = nil -- nil until PlayerLoaded fires

QBCoreClient.OnPlayerLoaded = Instance.new("BindableEvent")
QBCoreClient.OnPlayerDataUpdated = Instance.new("BindableEvent") -- fires (key, value)
QBCoreClient.OnNotify = Instance.new("BindableEvent") -- fires (text, notifyType, length)

function QBCoreClient.GetPlayerData()
	return QBCoreClient.PlayerData
end

Remotes.PlayerLoaded.OnClientEvent:Connect(function()
	QBCoreClient.OnPlayerLoaded:Fire()
end)

Remotes.PlayerDataUpdated.OnClientEvent:Connect(function(key, val)
	if key == "all" then
		QBCoreClient.PlayerData = val
	else
		QBCoreClient.PlayerData = QBCoreClient.PlayerData or {}
		QBCoreClient.PlayerData[key] = val
	end
	QBCoreClient.OnPlayerDataUpdated:Fire(key, val)
end)

Remotes.Notify.OnClientEvent:Connect(function(text, notifyType, length)
	QBCoreClient.OnNotify:Fire(text, notifyType, length)
end)

return QBCoreClient
