-- Roblox port of shared/main.lua's GetShared/GetCoreObject pattern.
-- Server and client require this shared main module directly.

local QBShared = {}

local function findSharedModule(name)
	local module = script:FindFirstChild(name) or script.Parent:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		error(
			("QBShared setup error: %s must be a ModuleScript inside %s or next to it."):format(
				name,
				script:GetFullName()
			),
			2
		)
	end
	return module
end

local JobsModule = require(findSharedModule("Jobs"))

QBShared.Config = require(findSharedModule("Config"))
QBShared.Items = require(findSharedModule("Items"))
QBShared.Vehicles = require(findSharedModule("Vehicles"))
QBShared.Weather = require(findSharedModule("Weather"))
QBShared.Jobs = JobsModule.List
QBShared.ForceJobDefaultDutyAtLogin = JobsModule.ForceJobDefaultDutyAtLogin
QBShared.Crews = require(findSharedModule("Crews"))

--- @param namespace 'Jobs' | 'Crews' | 'Items' | 'Vehicles' | 'Weather' | 'Config'
--- @param item string?
function QBShared.GetShared(namespace, item)
	local ns = QBShared[namespace]
	if not ns then
		return nil
	end
	return item and ns[item] or ns
end

return QBShared
