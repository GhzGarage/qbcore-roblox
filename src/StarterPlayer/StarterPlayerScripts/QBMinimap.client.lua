-- Starts the native QBHUD minimap. The shared QBMinimap module also exposes
-- AddBlip/RemoveBlip/SetBlipAlwaysShow for other client systems.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QBMinimap = require(ReplicatedStorage:WaitForChild("QBMinimap"))

QBMinimap.Start()
