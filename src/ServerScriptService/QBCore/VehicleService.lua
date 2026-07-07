-- Server-side vehicle spawning. Vehicle definitions come from QBShared.Vehicles;
-- model templates live in ServerStorage/QBVehicleModels and runtime clones go into
-- Workspace/SpawnedVehicles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local QBShared = require(ReplicatedStorage.QBShared.Main)

local VehicleService = {}

local TEMPLATE_FOLDER_NAME = "QBVehicleModels"
local SPAWNED_FOLDER_NAME = "SpawnedVehicles"
local VEHICLE_ATTRIBUTE = "QBVehicle"
local VEHICLE_NAME_ATTRIBUTE = "QBVehicleName"
local VEHICLE_LABEL_ATTRIBUTE = "QBVehicleLabel"
local VEHICLE_PLATE_ATTRIBUTE = "QBVehiclePlate"
local VEHICLE_SPAWN_ID_ATTRIBUTE = "QBVehicleSpawnId"
local VEHICLE_OWNER_ATTRIBUTE = "QBOwnerUserId"

local started = false
local templateFolder = nil
local spawnedFolder = nil
local vehicleLookup = nil
local nextSpawnId = 0

local function ensureTemplateFolder()
	if templateFolder and templateFolder.Parent then
		return templateFolder
	end

	templateFolder = ServerStorage:FindFirstChild(TEMPLATE_FOLDER_NAME)
	if not templateFolder then
		templateFolder = Instance.new("Folder")
		templateFolder.Name = TEMPLATE_FOLDER_NAME
		templateFolder.Parent = ServerStorage
	end

	return templateFolder
end

local function ensureSpawnedFolder()
	if spawnedFolder and spawnedFolder.Parent then
		return spawnedFolder
	end

	spawnedFolder = Workspace:FindFirstChild(SPAWNED_FOLDER_NAME)
	if not spawnedFolder then
		spawnedFolder = Instance.new("Folder")
		spawnedFolder.Name = SPAWNED_FOLDER_NAME
		spawnedFolder.Parent = Workspace
	end

	return spawnedFolder
end

local function normalizeName(value)
	if type(value) ~= "string" then
		return ""
	end
	local normalized = value:lower():gsub("[^%w]+", "")
	return normalized
end

local function addUnique(list, lookup, value)
	if type(value) ~= "string" then
		return
	end

	value = value:gsub("^%s+", ""):gsub("%s+$", "")
	if value == "" or lookup[value] then
		return
	end

	lookup[value] = true
	list[#list + 1] = value
end

local function addLookup(lookup, value, definition)
	local normalized = normalizeName(value)
	if normalized == "" then
		return
	end
	lookup[normalized] = lookup[normalized] or definition
end

local function buildVehicleLookup()
	local lookup = {}

	for key, definition in pairs(QBShared.Vehicles or {}) do
		definition.name = definition.name or key
		addLookup(lookup, key, definition)
		addLookup(lookup, definition.name, definition)
		addLookup(lookup, definition.label, definition)
		addLookup(lookup, definition.modelName, definition)

		if type(definition.aliases) == "table" then
			for _, alias in ipairs(definition.aliases) do
				addLookup(lookup, alias, definition)
			end
		end
	end

	return lookup
end

local function getVehicleLookup()
	if not vehicleLookup then
		vehicleLookup = buildVehicleLookup()
	end
	return vehicleLookup
end

local function getTemplateCandidates(definition)
	local list = {}
	local lookup = {}

	addUnique(list, lookup, definition.modelName)
	addUnique(list, lookup, definition.templateName)
	addUnique(list, lookup, definition.label)
	addUnique(list, lookup, definition.name)

	if type(definition.aliases) == "table" then
		for _, alias in ipairs(definition.aliases) do
			addUnique(list, lookup, alias)
		end
	end

	return list
end

local function findVehicleTemplate(definition)
	local folder = ensureTemplateFolder()
	local candidates = getTemplateCandidates(definition)

	for _, candidate in ipairs(candidates) do
		local child = folder:FindFirstChild(candidate)
		if child then
			return child, candidates[1] or definition.name
		end
	end

	local normalizedCandidates = {}
	for _, candidate in ipairs(candidates) do
		normalizedCandidates[normalizeName(candidate)] = true
	end

	for _, child in ipairs(folder:GetChildren()) do
		if normalizedCandidates[normalizeName(child.Name)] then
			return child, candidates[1] or definition.name
		end
	end

	return nil, candidates[1] or definition.name
end

local function getSpawnCFrame(player, distance)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return CFrame.new(0, 145, 0)
	end

	local look = root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.001 then
		look = Vector3.new(0, 0, -1)
	else
		look = look.Unit
	end

	local position = root.Position + (look * (tonumber(distance) or 14)) + Vector3.new(0, 3, 0)
	return CFrame.lookAt(position, position + look)
end

local function pivotVehicle(instance, cframe)
	if typeof(cframe) ~= "CFrame" then
		return
	end

	if instance:IsA("PVInstance") then
		instance:PivotTo(cframe)
	elseif instance:IsA("Model") then
		instance:PivotTo(cframe)
	elseif instance:IsA("BasePart") then
		instance.CFrame = cframe
	end
end

local function makePlate()
	return ("QBC%04d"):format(math.random(0, 9999))
end

local function getVehiclePosition(instance)
	if instance:IsA("PVInstance") or instance:IsA("Model") then
		return instance:GetPivot().Position
	elseif instance:IsA("BasePart") then
		return instance.Position
	end

	local part = instance:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end

local function applyConfiguredAttributes(vehicle, definition, extraAttributes)
	local attributes = type(definition.attributes) == "table" and definition.attributes or {}
	for attributeName, value in pairs(attributes) do
		if type(attributeName) == "string" then
			vehicle:SetAttribute(attributeName, value)
		end
	end

	if type(extraAttributes) == "table" then
		for attributeName, value in pairs(extraAttributes) do
			if type(attributeName) == "string" then
				vehicle:SetAttribute(attributeName, value)
			end
		end
	end
end

function VehicleService.Start()
	if started then
		return
	end
	started = true

	ensureTemplateFolder()
	ensureSpawnedFolder()
end

function VehicleService.GetTemplateFolder()
	return ensureTemplateFolder()
end

function VehicleService.GetSpawnedFolder()
	return ensureSpawnedFolder()
end

function VehicleService.GetVehicleDefinition(vehicleName)
	local definition = getVehicleLookup()[normalizeName(vehicleName)]
	if definition then
		return definition
	end

	return nil, ("Unknown vehicle %q."):format(tostring(vehicleName))
end

function VehicleService.SpawnVehicle(player, vehicleName, options)
	options = type(options) == "table" and options or {}

	local definition, definitionErr = VehicleService.GetVehicleDefinition(vehicleName)
	if not definition then
		return nil, definitionErr
	end

	local template, expectedName = findVehicleTemplate(definition)
	if not template then
		return nil,
			('%s model is not installed. Add a Model named "%s" to ServerStorage > %s.'):format(
				definition.label or definition.name,
				tostring(expectedName),
				TEMPLATE_FOLDER_NAME
			)
	end

	local spawnId = nextSpawnId + 1
	nextSpawnId = spawnId

	local plate = options.plate or makePlate()
	local clone = template:Clone()
	clone.Name = definition.modelName or definition.name
	clone:SetAttribute(VEHICLE_ATTRIBUTE, true)
	clone:SetAttribute(VEHICLE_NAME_ATTRIBUTE, definition.name)
	clone:SetAttribute(VEHICLE_LABEL_ATTRIBUTE, definition.label or definition.name)
	clone:SetAttribute(VEHICLE_PLATE_ATTRIBUTE, plate)
	clone:SetAttribute(VEHICLE_SPAWN_ID_ATTRIBUTE, spawnId)
	if player then
		clone:SetAttribute(VEHICLE_OWNER_ATTRIBUTE, player.UserId)
	end
	applyConfiguredAttributes(clone, definition, options.attributes)

	local spawnCFrame = options.cframe or getSpawnCFrame(player, options.distance)
	pivotVehicle(clone, spawnCFrame)
	clone.Parent = ensureSpawnedFolder()

	return clone, definition, plate
end

function VehicleService.DeleteClosestVehicle(player, maxDistance)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, "Your character needs to be spawned."
	end

	maxDistance = tonumber(maxDistance) or 30
	local closestVehicle = nil
	local closestDistance = math.huge

	for _, vehicle in ipairs(ensureSpawnedFolder():GetChildren()) do
		local position = getVehiclePosition(vehicle)
		if position then
			local distance = (position - root.Position).Magnitude
			if distance < closestDistance then
				closestDistance = distance
				closestVehicle = vehicle
			end
		end
	end

	if not closestVehicle or closestDistance > maxDistance then
		return false, ("No spawned vehicle within %d studs."):format(math.floor(maxDistance))
	end

	local label = closestVehicle:GetAttribute(VEHICLE_LABEL_ATTRIBUTE) or closestVehicle.Name
	closestVehicle:Destroy()
	return true, ("Deleted %s."):format(label)
end

return VehicleService
