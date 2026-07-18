-- Public garage storage/retrieval adapted from qb-garages. Owned vehicle records
-- live on the character profile; runtime instances remain in SpawnedVehicles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local QBShared = require(ReplicatedStorage.QBShared.Main)
local Remotes = require(ReplicatedStorage.QBRemotes)

local function requireSiblingModule(name)
	local module = script.Parent:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		error(("QBCore setup error: %s must be a ModuleScript next to %s."):format(name, script:GetFullName()), 2)
	end
	return require(module)
end

local PlayerService = requireSiblingModule("PlayerService")
local GarageService = {}

local FOLDER_NAME = "QBGarages"
local ACTION_COOLDOWN = 0.5

local started = false
local VehicleService = nil
local lastActionAt = {}
local actionBusy = {}

local function config()
	return type(QBShared.Config.Garages) == "table" and QBShared.Config.Garages or {}
end

local function trim(value)
	return type(value) == "string" and (value:match("^%s*(.-)%s*$") or "") or ""
end

local function vectorFrom(value)
	if typeof(value) == "Vector3" then return value end
	if type(value) == "table" then
		local source = value.position or value
		if typeof(source) == "Vector3" then return source end
		if type(source) == "table" then
			local x = tonumber(source.x or source.X)
			local y = tonumber(source.y or source.Y)
			local z = tonumber(source.z or source.Z)
			if x and y and z then return Vector3.new(x, y, z) end
		end
	end
	return nil
end

local function spawnCFrame(point)
	local position = vectorFrom(point)
	if not position then return nil end
	return CFrame.new(position) * CFrame.Angles(0, math.rad(tonumber(point.heading) or 0), 0)
end

local function getRoot(player)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then return nil end
	return root
end

local function garageById(garageId)
	for _, garage in ipairs(config().Locations or {}) do
		if trim(garage.id) == garageId then return garage end
	end
	return nil
end

local function defaultGarageId()
	local configured = trim(config().DefaultGarage)
	if configured ~= "" and garageById(configured) then return configured end
	local first = (config().Locations or {})[1]
	return first and trim(first.id) or "garage_1"
end

local function resolveAccess(player, requested)
	requested = type(requested) == "table" and requested or {}
	local garageId = trim(requested.garageId)
	local root = getRoot(player)
	if not root then return nil, nil, "Your character is unavailable." end
	local maxDistance = math.max(1, tonumber(config().ActionDistance) or 16)
	for _, garage in ipairs(config().Locations or {}) do
		local id = trim(garage.id)
		local position = vectorFrom(garage.takeVehicle)
		if position and (garageId == "" or garageId == id) and (root.Position - position).Magnitude <= maxDistance then
			return garage, { garageId = id }
		end
	end
	return nil, { garageId = garageId }, "Move closer to a garage entrance."
end

local function ensureOwned(playerObj)
	if type(playerObj.PlayerData.vehicles) ~= "table" then playerObj.PlayerData.vehicles = {} end
	return playerObj.PlayerData.vehicles
end

local function normalizeOwned(playerObj)
	local changed = false
	local fallbackGarage = defaultGarageId()
	for index, ownership in ipairs(ensureOwned(playerObj)) do
		if type(ownership.id) ~= "string" or ownership.id == "" then
			ownership.id = ("legacy-%s-%d"):format(tostring(ownership.plate or "vehicle"), index)
			changed = true
		end
		local runtime = VehicleService.FindSpawnedOwnedVehicle(ownership.id)
		local state = math.floor(tonumber(ownership.state) or (runtime and 0 or 1))
		if state < 0 or state > 2 then state = runtime and 0 or 1 end
		if state == 0 and not runtime and config().AutoRespawn ~= false then state = 1 end
		if ownership.state ~= state then ownership.state = state; changed = true end
		if (state == 1 or ownership.garage == nil or ownership.garage == "") and not garageById(tostring(ownership.garage or "")) then
			ownership.garage = fallbackGarage
			changed = true
		end
		if ownership.fuel == nil then
			local definition = QBShared.Vehicles[ownership.vehicle]
			ownership.fuel = tonumber(definition and definition.fuel) or 100
			changed = true
		end
		if ownership.engine == nil then ownership.engine = 1000; changed = true end
		if ownership.body == nil then ownership.body = 1000; changed = true end
	end
	if changed then playerObj:UpdateClient("vehicles", playerObj.PlayerData.vehicles); playerObj:Save() end
	return changed
end

local function stateLabel(state)
	if state == 1 then return "Garaged" end
	if state == 2 then return "Impounded" end
	return "Out"
end

local function closestOwnedRuntime(playerObj, garage)
	local garagePosition = vectorFrom(garage.takeVehicle)
	if not garagePosition then return nil end
	local maxDistance = math.max(1, tonumber(config().StoreDistance) or 20)
	local ownedIds = {}
	for _, ownership in ipairs(ensureOwned(playerObj)) do ownedIds[tostring(ownership.id)] = ownership end
	local closestVehicle, closestOwnership, closestDistance = nil, nil, math.huge
	for _, vehicle in ipairs(VehicleService.GetSpawnedFolder():GetChildren()) do
		local ownership = ownedIds[tostring(vehicle:GetAttribute("QBOwnedVehicleId") or "")]
		local position = VehicleService.GetVehiclePosition(vehicle)
		if ownership and position then
			local distance = (position - garagePosition).Magnitude
			if distance <= maxDistance and distance < closestDistance then
				closestVehicle, closestOwnership, closestDistance = vehicle, ownership, distance
			end
		end
	end
	return closestVehicle, closestOwnership, closestDistance
end

local function snapshot(playerObj, garage, access)
	normalizeOwned(playerObj)
	local shared = config().SharedGarages == true
	local vehicles = {}
	for _, ownership in ipairs(ensureOwned(playerObj)) do
		local state = math.floor(tonumber(ownership.state) or 1)
		if shared or ownership.garage == access.garageId then
			local definition = QBShared.Vehicles[ownership.vehicle]
			if definition then
				table.insert(vehicles, {
					id = tostring(ownership.id), vehicle = tostring(ownership.vehicle),
					label = tostring(definition.label or ownership.vehicle), brand = tostring(definition.brand or "Roblox"),
					category = tostring(definition.category or "other"), plate = tostring(ownership.plate or ""),
					state = state, stateLabel = stateLabel(state), garage = tostring(ownership.garage or ""),
					fuel = math.clamp(math.floor(tonumber(ownership.fuel) or 100), 0, 100),
					engine = math.clamp(math.floor(tonumber(ownership.engine) or 1000), 0, 1000),
					body = math.clamp(math.floor(tonumber(ownership.body) or 1000), 0, 1000),
					balance = math.max(0, math.floor(tonumber(ownership.balance) or 0)),
					installed = VehicleService.HasVehicleTemplate(ownership.vehicle),
				})
			end
		end
	end
	table.sort(vehicles, function(a, b) return a.label:lower() < b.label:lower() end)
	local nearbyVehicle, nearbyOwnership = closestOwnedRuntime(playerObj, garage)
	return {
		garage = { id = access.garageId, label = tostring(garage.label or "Public Garage"), type = tostring(garage.type or "public") },
		vehicles = vehicles,
		nearby = nearbyVehicle and nearbyOwnership and {
			ownershipId = tostring(nearbyOwnership.id), label = tostring((QBShared.Vehicles[nearbyOwnership.vehicle] or {}).label or nearbyOwnership.vehicle),
			plate = tostring(nearbyOwnership.plate or ""),
		} or nil,
		sharedGarages = shared,
	}
end

local function findOwnership(playerObj, ownershipId)
	for _, ownership in ipairs(ensureOwned(playerObj)) do
		if tostring(ownership.id) == tostring(ownershipId) then return ownership end
	end
	return nil
end

local function spawnPointIsClear(point)
	local position = vectorFrom(point)
	if not position then return false end
	local radius = math.max(1, tonumber(config().SpawnClearRadius) or 12)
	for _, vehicle in ipairs(VehicleService.GetSpawnedFolder():GetChildren()) do
		local current = VehicleService.GetVehiclePosition(vehicle)
		if current and (current - position).Magnitude < radius then return false end
	end
	return true
end

local function openSpawnPoint(garage)
	for _, point in ipairs(garage.spawnPoints or {}) do
		if vectorFrom(point) and spawnPointIsClear(point) then return point end
	end
	return nil
end

local function seatPlayer(player, vehicle)
	task.defer(function()
		if not vehicle or not vehicle.Parent then return end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true) or vehicle:FindFirstChildWhichIsA("Seat", true)
		if humanoid and seat then seat:Sit(humanoid) end
	end)
end

local function retrieve(player, playerObj, payload, garage, access)
	local ownership = findOwnership(playerObj, payload.ownershipId)
	if not ownership then return false, "Owned vehicle not found." end
	if math.floor(tonumber(ownership.state) or 1) == 2 then return false, "That vehicle is impounded." end
	if math.floor(tonumber(ownership.state) or 1) ~= 1 then return false, "That vehicle is already out." end
	if config().SharedGarages ~= true and ownership.garage ~= access.garageId then return false, "That vehicle is stored at another garage." end
	if VehicleService.FindSpawnedOwnedVehicle(ownership.id) then return false, "That vehicle is already spawned." end
	if not VehicleService.HasVehicleTemplate(ownership.vehicle) then return false, "The vehicle template is not installed." end
	local point = openSpawnPoint(garage)
	if not point then return false, "All garage spawn points are blocked." end
	local previousState = ownership.state
	ownership.state = 0
	if playerObj:Save() ~= true then ownership.state = previousState; return false, "The vehicle state could not be saved." end
	local vehicle, err = VehicleService.SpawnVehicle(player, ownership.vehicle, {
		cframe = spawnCFrame(point), plate = ownership.plate,
		attributes = {
			QBOwnedVehicleId = ownership.id, QBGarageVehicle = true,
			Fuel = tonumber(ownership.fuel) or 100, QBEngineHealth = tonumber(ownership.engine) or 1000,
			QBBodyHealth = tonumber(ownership.body) or 1000,
		},
	})
	if not vehicle then ownership.state = previousState; playerObj:Save(); return false, err end
	playerObj:UpdateClient("vehicles", playerObj.PlayerData.vehicles)
	seatPlayer(player, vehicle)
	return true, ("Retrieved %s (%s)."):format((QBShared.Vehicles[ownership.vehicle] or {}).label or ownership.vehicle, ownership.plate)
end

local function unseatOccupants(vehicle)
	if vehicle:IsA("Seat") or vehicle:IsA("VehicleSeat") then
		if vehicle.Occupant then vehicle.Occupant.Sit = false end
	end
	for _, descendant in ipairs(vehicle:GetDescendants()) do
		if (descendant:IsA("Seat") or descendant:IsA("VehicleSeat")) and descendant.Occupant then
			descendant.Occupant.Sit = false
		end
	end
end

local function store(player, playerObj, _, garage, access)
	local vehicle, ownership = closestOwnedRuntime(playerObj, garage)
	if not vehicle or not ownership then return false, "Move one of your owned vehicles closer to the garage entrance." end
	if tonumber(vehicle:GetAttribute("QBOwnerUserId")) ~= player.UserId then return false, "You do not own that vehicle." end
	local oldState, oldGarage = ownership.state, ownership.garage
	local oldFuel, oldEngine, oldBody = ownership.fuel, ownership.engine, ownership.body
	ownership.state, ownership.garage = 1, access.garageId
	ownership.fuel = math.clamp(tonumber(vehicle:GetAttribute("Fuel")) or tonumber(ownership.fuel) or 100, 0, 100)
	ownership.engine = math.clamp(tonumber(vehicle:GetAttribute("QBEngineHealth")) or tonumber(ownership.engine) or 1000, 0, 1000)
	ownership.body = math.clamp(tonumber(vehicle:GetAttribute("QBBodyHealth")) or tonumber(ownership.body) or 1000, 0, 1000)
	if playerObj:Save() ~= true then
		ownership.state, ownership.garage = oldState, oldGarage
		ownership.fuel, ownership.engine, ownership.body = oldFuel, oldEngine, oldBody
		return false, "The vehicle could not be stored because its state did not save."
	end
	playerObj:UpdateClient("vehicles", playerObj.PlayerData.vehicles)
	unseatOccupants(vehicle)
	vehicle:Destroy()
	return true, ("Stored %s (%s) in %s."):format((QBShared.Vehicles[ownership.vehicle] or {}).label or ownership.vehicle, ownership.plate, garage.label or access.garageId)
end

local ACTIONS = { retrieve = retrieve, store = store }

local function createPrompts()
	local old = Workspace:FindFirstChild(FOLDER_NAME)
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace
	for index, garage in ipairs(config().Locations or {}) do
		local position = vectorFrom(garage.takeVehicle)
		if position then
			local id = trim(garage.id) ~= "" and trim(garage.id) or ("garage_%d"):format(index)
			local part = Instance.new("Part")
			part.Name = "GaragePrompt_" .. id
			part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
			part.CastShadow, part.Transparency, part.Size, part.Position = false, 1, Vector3.new(2, 2, 2), position
			part.Parent = folder
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "GaragePrompt"
			prompt.ActionText = "Open Garage"
			prompt.ObjectText = tostring(garage.label or "Public Garage")
			prompt.KeyboardKeyCode, prompt.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
			prompt.HoldDuration = 0.15
			prompt.MaxActivationDistance = math.max(1, tonumber(config().PromptDistance) or 10)
			prompt.RequiresLineOfSight = false
			prompt.Parent = part
			prompt.Triggered:Connect(function(player)
				local playerObj = PlayerService.GetPlayer(player.UserId)
				local resolved, access = resolveAccess(player, { garageId = id })
				if playerObj and resolved then Remotes.OpenGarage:FireClient(player, access) end
			end)
		else
			warn(("[QBCore.GarageService] Garage %d has no valid takeVehicle position."):format(index))
		end
	end
end

function GarageService.Start(vehicleService)
	if started then return end
	assert(type(vehicleService) == "table", "GarageService.Start requires VehicleService")
	VehicleService = vehicleService
	started = true
	Remotes.GetGarage.OnServerInvoke = function(player, requestedAccess)
		if config().Enabled == false then return nil, "Garages are currently unavailable." end
		local playerObj = PlayerService.GetPlayer(player.UserId)
		if not playerObj then return nil, "Load a character before using a garage." end
		local garage, access, err = resolveAccess(player, requestedAccess)
		if not garage then return nil, err end
		return snapshot(playerObj, garage, access)
	end
	Remotes.GarageAction.OnServerInvoke = function(player, action, payload)
		if config().Enabled == false then return false, "Garages are currently unavailable." end
		local playerObj = PlayerService.GetPlayer(player.UserId)
		if not playerObj then return false, "Load a character before using a garage." end
		payload = type(payload) == "table" and payload or {}
		local garage, access, err = resolveAccess(player, payload.access)
		if not garage then return false, err end
		local now = os.clock()
		if now - (lastActionAt[player] or 0) < ACTION_COOLDOWN then return false, "Please wait before submitting another garage request." end
		lastActionAt[player] = now
		action = type(action) == "string" and action:lower() or ""
		local handler = ACTIONS[action]
		if not handler then return false, "Unknown garage action." end
		if actionBusy[player] then return false, "A garage request is already in progress." end
		actionBusy[player] = true
		local handlerOk, ok, message = pcall(handler, player, playerObj, payload, garage, access)
		actionBusy[player] = nil
		if not handlerOk then
			warn(("[QBCore.GarageService] %s failed for %s: %s"):format(action, player.Name, tostring(ok)))
			return false, "The garage request could not be completed."
		end
		if not ok then return false, message end
		playerObj:Notify(tostring(message), "success", 5000)
		return true, { message = message, snapshot = snapshot(playerObj, garage, access) }
	end
	Players.PlayerRemoving:Connect(function(player)
		lastActionAt[player], actionBusy[player] = nil, nil
		local playerObj = PlayerService.GetPlayer(player.UserId)
		if not playerObj then return end
		if config().AutoRespawn ~= false then
			local fallback = defaultGarageId()
			for _, ownership in ipairs(ensureOwned(playerObj)) do
				if math.floor(tonumber(ownership.state) or 0) == 0 then
					ownership.state = 1
					if not garageById(tostring(ownership.garage or "")) then ownership.garage = fallback end
				end
				local runtime = VehicleService.FindSpawnedOwnedVehicle(ownership.id)
				if runtime and runtime.Parent then runtime:Destroy() end
			end
			playerObj:Save()
		end
	end)
	if config().Enabled ~= false then createPrompts() end
end

return GarageService
