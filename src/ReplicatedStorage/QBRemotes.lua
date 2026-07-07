-- Creates (server) or waits for (client) the RemoteEvents/RemoteFunctions listed in
-- QBRemoteNames, and returns a flat { name = Instance } table either way. Both sides
-- require this same module so there is one place that can go out of sync, not two.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Names = require(script.Parent.QBRemoteNames)

local Remotes = {}

if RunService:IsServer() then
	local folder = ReplicatedStorage:FindFirstChild("QBRemoteInstances")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "QBRemoteInstances"
		folder.Parent = ReplicatedStorage
	end

	for _, name in ipairs(Names.RemoteEvents) do
		local instance = folder:FindFirstChild(name)
		if not instance then
			instance = Instance.new("RemoteEvent")
			instance.Name = name
			instance.Parent = folder
		end
		Remotes[name] = instance
	end

	for _, name in ipairs(Names.RemoteFunctions) do
		local instance = folder:FindFirstChild(name)
		if not instance then
			instance = Instance.new("RemoteFunction")
			instance.Name = name
			instance.Parent = folder
		end
		Remotes[name] = instance
	end
else
	local folder = ReplicatedStorage:WaitForChild("QBRemoteInstances")
	for _, name in ipairs(Names.RemoteEvents) do
		Remotes[name] = folder:WaitForChild(name)
	end
	for _, name in ipairs(Names.RemoteFunctions) do
		Remotes[name] = folder:WaitForChild(name)
	end
end

return Remotes
