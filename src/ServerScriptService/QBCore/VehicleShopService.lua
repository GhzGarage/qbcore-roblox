-- Roblox adaptation of qb-vehicleshop: shared catalog browsing, static showroom
-- displays, persistent character ownership, financing, and timed test drives.

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
local VehicleShopService = {}

local ROOT_FOLDER_NAME = "QBVehicleShop"
local ACTION_COOLDOWN = 0.5
local SPAWN_CLEAR_RADIUS = 12

local started = false
local VehicleService = nil
local lastActionAt = {}
local actionBusy = {}
local activeTestDrives = {}
local activeOwnedVehicles = {}

local function config()
	return type(QBShared.Config.VehicleShop) == "table" and QBShared.Config.VehicleShop or {}
end

local function trim(value)
	return type(value) == "string" and (value:match("^%s*(.-)%s*$") or "") or ""
end

local function positionOf(entry)
	if type(entry) ~= "table" then
		return nil
	end
	if typeof(entry.position) == "Vector3" then
		return entry.position
	end
	if type(entry.position) == "table" then
		local x = tonumber(entry.position.x or entry.position.X)
		local y = tonumber(entry.position.y or entry.position.Y)
		local z = tonumber(entry.position.z or entry.position.Z)
		if x and y and z then
			return Vector3.new(x, y, z)
		end
	end
	return nil
end

local function cframeOf(entry)
	local position = positionOf(entry)
	if not position then
		return nil
	end
	return CFrame.new(position) * CFrame.Angles(0, math.rad(tonumber(entry.heading) or 0), 0)
end

local function getRoot(player)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end
	return root
end

local function normalizeAccess(access)
	access = type(access) == "table" and access or {}
	return {
		mode = access.mode == "finance" and "finance" or "showroom",
		locationId = trim(access.locationId),
		vehicleName = trim(access.vehicleName),
	}
end

local function resolveAccess(player, requested)
	local access = normalizeAccess(requested)
	local root = getRoot(player)
	if not root then
		return nil, access, "Your character is unavailable."
	end
	local maxDistance = math.max(1, tonumber(config().ActionDistance) or 14)
	if access.mode == "finance" then
		local spot = config().FinanceSpot
		local position = positionOf(spot)
		local id = type(spot) == "table" and trim(spot.id) or "finance"
		if
			position
			and (access.locationId == "" or access.locationId == id)
			and (root.Position - position).Magnitude <= maxDistance
		then
			access.locationId = id
			return spot, access
		end
		return nil, access, "Move closer to the vehicle finance desk."
	end
	for _, spot in ipairs(config().ShowroomSpots or {}) do
		local position = positionOf(spot)
		local id = trim(spot.id)
		if
			position
			and (access.locationId == "" or access.locationId == id)
			and (root.Position - position).Magnitude <= maxDistance
		then
			access.locationId = id
			if access.vehicleName == "" then
				access.vehicleName = trim(spot.vehicle)
			end
			return spot, access
		end
	end
	return nil, access, "Move closer to a showroom vehicle."
end

local function isActivePlayer(player, playerObj)
	return player and player.Parent == Players and PlayerService.GetPlayer(player.UserId) == playerObj
end

local function isExcluded(vehicleName)
	local excluded = config().ExcludedVehicles
	return type(excluded) == "table" and excluded[vehicleName] == true
end

local function getPrice(vehicleName, definition)
	local overrides = config().Prices
	local price = type(overrides) == "table" and tonumber(overrides[vehicleName]) or nil
	price = price or tonumber(definition.price) or tonumber(config().DefaultPrice) or 0
	return math.max(0, math.floor(price))
end

local function getSellableDefinition(vehicleName)
	vehicleName = trim(vehicleName):lower()
	local definition = QBShared.Vehicles[vehicleName]
	if not definition or isExcluded(vehicleName) then
		return nil, "That vehicle is not sold here."
	end
	return definition, vehicleName
end

local function ensureOwnedVehicles(playerObj)
	if type(playerObj.PlayerData.vehicles) ~= "table" then
		playerObj.PlayerData.vehicles = {}
	end
	return playerObj.PlayerData.vehicles
end

local function makePlate(owned)
	for _ = 1, 100 do
		local plate = ("QB%02d%04d"):format(math.random(0, 99), math.random(0, 9999))
		local used = false
		for _, entry in ipairs(owned) do
			if entry.plate == plate then
				used = true
				break
			end
		end
		if not used then
			return plate
		end
	end
	return ("QB%d"):format(os.time() % 1000000)
end

local function makeOwnershipId()
	return ("%d-%06d"):format(os.time(), math.random(0, 999999))
end

local function catalogSnapshot(playerObj)
	local ownedNames = {}
	for _, entry in ipairs(ensureOwnedVehicles(playerObj)) do
		ownedNames[tostring(entry.vehicle or "")] = true
	end
	local catalog = {}
	for vehicleName, definition in pairs(QBShared.Vehicles or {}) do
		if not isExcluded(vehicleName) then
			table.insert(catalog, {
				name = vehicleName,
				label = tostring(definition.label or vehicleName),
				brand = tostring(definition.brand or "Roblox"),
				category = tostring(definition.category or "other"),
				color = tostring(definition.color or ""),
				description = tostring(definition.description or ""),
				price = getPrice(vehicleName, definition),
				owned = ownedNames[vehicleName] == true,
				installed = VehicleService.HasVehicleTemplate(vehicleName),
			})
		end
	end
	table.sort(catalog, function(a, b)
		if a.category == b.category then
			return a.label:lower() < b.label:lower()
		end
		return a.category:lower() < b.category:lower()
	end)
	return catalog
end

local function ownedSnapshot(playerObj)
	local result = {}
	for _, entry in ipairs(ensureOwnedVehicles(playerObj)) do
		local definition = QBShared.Vehicles[entry.vehicle]
		if definition then
			local runtime = VehicleService.FindSpawnedOwnedVehicle(entry.id)
			table.insert(result, {
				id = tostring(entry.id or ""),
				vehicle = tostring(entry.vehicle or ""),
				label = tostring(definition.label or entry.vehicle),
				brand = tostring(definition.brand or "Roblox"),
				category = tostring(definition.category or "other"),
				plate = tostring(entry.plate or ""),
				price = math.max(0, math.floor(tonumber(entry.price) or 0)),
				balance = math.max(0, math.floor(tonumber(entry.balance) or 0)),
				paymentAmount = math.max(0, math.floor(tonumber(entry.paymentAmount) or 0)),
				paymentsLeft = math.max(0, math.floor(tonumber(entry.paymentsLeft) or 0)),
				nextPaymentAt = math.floor(tonumber(entry.nextPaymentAt) or 0),
				spawned = runtime ~= nil and runtime.Parent ~= nil,
				installed = VehicleService.HasVehicleTemplate(entry.vehicle),
			})
		end
	end
	table.sort(result, function(a, b)
		return a.label:lower() < b.label:lower()
	end)
	return result
end

local function getSnapshot(playerObj, access)
	return {
		label = tostring(config().Label or "Vehicle Shop"),
		access = { mode = access.mode, locationId = access.locationId },
		selectedVehicle = access.vehicleName,
		catalog = catalogSnapshot(playerObj),
		owned = ownedSnapshot(playerObj),
		finance = {
			minimumDownPercent = math.clamp(math.floor(tonumber(config().MinimumDownPercent) or 10), 0, 100),
			maximumPayments = math.max(1, math.floor(tonumber(config().MaximumPayments) or 24)),
			paymentIntervalHours = math.max(1, tonumber(config().PaymentIntervalHours) or 24),
		},
	}
end

local function isSpawnClear()
	local spawn = config().VehicleSpawn
	local position = positionOf(spawn)
	if not position then
		return false, "VehicleShop.VehicleSpawn has no valid position."
	end
	for _, vehicle in ipairs(VehicleService.GetSpawnedFolder():GetChildren()) do
		local vehiclePosition = VehicleService.GetVehiclePosition(vehicle)
		if vehiclePosition and (vehiclePosition - position).Magnitude < SPAWN_CLEAR_RADIUS then
			return false, "The dealership exit is blocked by another vehicle."
		end
	end
	return true
end

local function seatPlayer(player, vehicle)
	task.defer(function()
		if not vehicle or not vehicle.Parent then
			return
		end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true) or vehicle:FindFirstChildWhichIsA("Seat", true)
		if humanoid and seat then
			seat:Sit(humanoid)
		end
	end)
end

local function spawnOwnedVehicle(player, ownership)
	local clear, clearErr = isSpawnClear()
	if not clear then
		return nil, clearErr
	end
	local existing = VehicleService.FindSpawnedOwnedVehicle(ownership.id)
	if existing and existing.Parent then
		return nil, "That owned vehicle is already out."
	end
	local spawnCFrame = cframeOf(config().VehicleSpawn)
	local vehicle, definitionOrErr = VehicleService.SpawnVehicle(player, ownership.vehicle, {
		cframe = spawnCFrame,
		plate = ownership.plate,
		attributes = { QBOwnedVehicleId = ownership.id, QBVehicleShopVehicle = true },
	})
	if not vehicle then
		return nil, definitionOrErr
	end
	activeOwnedVehicles[ownership.id] = vehicle
	vehicle.AncestryChanged:Connect(function(_, parent)
		if not parent and activeOwnedVehicles[ownership.id] == vehicle then
			activeOwnedVehicles[ownership.id] = nil
		end
	end)
	seatPlayer(player, vehicle)
	return vehicle
end

local function takePayment(playerObj, amount, reason)
	if amount <= 0 then
		return true, "none"
	end
	if (tonumber(playerObj:GetMoney("cash")) or 0) >= amount and playerObj:RemoveMoney("cash", amount, reason) then
		return true, "cash"
	end
	if (tonumber(playerObj:GetMoney("bank")) or 0) >= amount and playerObj:RemoveMoney("bank", amount, reason) then
		return true, "bank"
	end
	return false, "You do not have enough cash or bank funds."
end

local function refundPayment(playerObj, amount, moneyType, reason)
	if amount > 0 and (moneyType == "cash" or moneyType == "bank") then
		playerObj:AddMoney(moneyType, amount, reason)
	end
end

local function purchase(player, playerObj, payload, access, financed)
	local definition, vehicleNameOrErr = getSellableDefinition(payload.vehicleName)
	if not definition then
		return false, vehicleNameOrErr
	end
	local vehicleName = vehicleNameOrErr
	local owned = ensureOwnedVehicles(playerObj)
	if config().AllowDuplicatePurchases == false then
		for _, entry in ipairs(owned) do
			if entry.vehicle == vehicleName then
				return false, "You already own this vehicle."
			end
		end
	end
	local price = getPrice(vehicleName, definition)
	local downPayment, payments = price, 0
	if financed and price > 0 then
		downPayment = math.floor(tonumber(payload.downPayment) or -1)
		payments = math.floor(tonumber(payload.payments) or 0)
		local minDown = math.ceil(price * math.clamp((tonumber(config().MinimumDownPercent) or 10) / 100, 0, 1))
		if downPayment < minDown or downPayment > price then
			return false, ("Down payment must be between $%d and $%d."):format(minDown, price)
		end
		local maxPayments = math.max(1, math.floor(tonumber(config().MaximumPayments) or 24))
		if payments < 1 or payments > maxPayments then
			return false, ("Choose between 1 and %d payments."):format(maxPayments)
		end
	end
	local paid, moneyTypeOrErr =
		takePayment(playerObj, downPayment, financed and "vehicle-finance-down" or "vehicle-purchase")
	if not paid then
		return false, moneyTypeOrErr
	end
	local balance = math.max(0, price - downPayment)
	local ownership = {
		id = makeOwnershipId(),
		vehicle = vehicleName,
		plate = makePlate(owned),
		price = price,
		purchasedAt = os.time(),
		balance = balance,
		paymentAmount = balance > 0 and math.ceil(balance / payments) or 0,
		paymentsLeft = balance > 0 and payments or 0,
		nextPaymentAt = balance > 0
				and (os.time() + math.floor((tonumber(config().PaymentIntervalHours) or 24) * 3600))
			or 0,
		state = 0,
		garage = type(QBShared.Config.Garages) == "table" and QBShared.Config.Garages.DefaultGarage or nil,
		fuel = tonumber(definition.fuel) or 100,
		engine = 1000,
		body = 1000,
	}
	table.insert(owned, ownership)
	if not isActivePlayer(player, playerObj) or playerObj:Save() ~= true then
		table.remove(owned, #owned)
		refundPayment(playerObj, downPayment, moneyTypeOrErr, "vehicle-purchase-rollback")
		return false, "Your vehicle ownership could not be saved; the payment was returned."
	end
	playerObj:UpdateClient("vehicles", owned)
	local vehicle, spawnErr = spawnOwnedVehicle(player, ownership)
	local message = ("Purchased %s (%s)."):format(definition.label or vehicleName, ownership.plate)
	if not vehicle then
		message = message .. " It is owned, but was not spawned: " .. tostring(spawnErr)
	end
	return true, message
end

local function testDrive(player, playerObj, payload)
	local definition, vehicleNameOrErr = getSellableDefinition(payload.vehicleName)
	if not definition then
		return false, vehicleNameOrErr
	end
	local current = activeTestDrives[player]
	if current and current.vehicle and current.vehicle.Parent then
		return false, "Finish your current test drive first."
	end
	local clear, clearErr = isSpawnClear()
	if not clear then
		return false, clearErr
	end
	local token = {}
	local vehicle, spawnErr = VehicleService.SpawnVehicle(player, vehicleNameOrErr, {
		cframe = cframeOf(config().VehicleSpawn),
		plate = "TEST",
		attributes = { QBTestDrive = true, QBVehicleShopVehicle = true },
	})
	if not vehicle then
		return false, spawnErr
	end
	activeTestDrives[player] = { vehicle = vehicle, token = token }
	vehicle.AncestryChanged:Connect(function(_, parent)
		local active = activeTestDrives[player]
		if not parent and active and active.token == token then
			activeTestDrives[player] = nil
		end
	end)
	seatPlayer(player, vehicle)
	local seconds = math.max(10, math.floor(tonumber(config().TestDriveSeconds) or 60))
	task.delay(seconds, function()
		local active = activeTestDrives[player]
		if not active or active.token ~= token then
			return
		end
		activeTestDrives[player] = nil
		if vehicle.Parent then
			vehicle:Destroy()
		end
		if PlayerService.GetPlayer(player.UserId) == playerObj then
			playerObj:Notify("Your test drive has ended.", "primary", 5000)
		end
	end)
	return true, ("Test drive started for %d seconds."):format(seconds)
end

local function findOwnership(playerObj, ownershipId)
	for _, entry in ipairs(ensureOwnedVehicles(playerObj)) do
		if tostring(entry.id) == tostring(ownershipId) then
			return entry
		end
	end
	return nil
end

local function spawnOwned(player, playerObj, payload, access)
	if access.mode ~= "finance" then
		return false, "Owned vehicles are released from the finance desk."
	end
	local ownership = findOwnership(playerObj, payload.ownershipId)
	if not ownership then
		return false, "Owned vehicle not found."
	end
	local vehicle, err = spawnOwnedVehicle(player, ownership)
	if not vehicle then
		return false, err
	end
	return true,
		("Spawned %s (%s)."):format(
			(QBShared.Vehicles[ownership.vehicle] or {}).label or ownership.vehicle,
			ownership.plate
		)
end

local function financePayment(player, playerObj, payload, access)
	if access.mode ~= "finance" then
		return false, "Finance payments must be made at the finance desk."
	end
	local ownership = findOwnership(playerObj, payload.ownershipId)
	if not ownership then
		return false, "Financed vehicle not found."
	end
	local balance = math.max(0, math.floor(tonumber(ownership.balance) or 0))
	if balance <= 0 then
		return false, "That vehicle is already paid off."
	end
	local amount = payload.payoff == true and balance or math.floor(tonumber(payload.amount) or 0)
	local minimum = math.min(balance, math.max(1, math.floor(tonumber(ownership.paymentAmount) or 1)))
	if amount < minimum or amount > balance then
		return false, ("Payment must be between $%d and $%d."):format(minimum, balance)
	end
	local paid, moneyTypeOrErr = takePayment(playerObj, amount, "vehicle-finance-payment")
	if not paid then
		return false, moneyTypeOrErr
	end
	local oldBalance, oldAmount, oldLeft, oldNext =
		ownership.balance, ownership.paymentAmount, ownership.paymentsLeft, ownership.nextPaymentAt
	ownership.balance = balance - amount
	ownership.paymentsLeft = ownership.balance > 0
			and math.max(1, math.floor(tonumber(ownership.paymentsLeft) or 1) - 1)
		or 0
	ownership.paymentAmount = ownership.balance > 0 and math.ceil(ownership.balance / ownership.paymentsLeft) or 0
	ownership.nextPaymentAt = ownership.balance > 0
			and (os.time() + math.floor((tonumber(config().PaymentIntervalHours) or 24) * 3600))
		or 0
	if playerObj:Save() ~= true then
		ownership.balance, ownership.paymentAmount, ownership.paymentsLeft, ownership.nextPaymentAt =
			oldBalance, oldAmount, oldLeft, oldNext
		refundPayment(playerObj, amount, moneyTypeOrErr, "vehicle-finance-rollback")
		return false, "The payment could not be saved; your money was returned."
	end
	playerObj:UpdateClient("vehicles", playerObj.PlayerData.vehicles)
	return true,
		ownership.balance <= 0 and "Vehicle paid off." or ("Payment accepted. Remaining balance: $%d."):format(
			ownership.balance
		)
end

local ACTIONS = {
	purchase = function(player, playerObj, payload, access)
		return purchase(player, playerObj, payload, access, false)
	end,
	finance = function(player, playerObj, payload, access)
		return purchase(player, playerObj, payload, access, true)
	end,
	test_drive = testDrive,
	spawn_owned = spawnOwned,
	finance_payment = financePayment,
}

local function createPrompt(parent, name, position, actionText, objectText, context)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.CastShadow, part.Transparency, part.Size, part.Position = false, 1, Vector3.new(2, 2, 2), position
	part.Parent = parent
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "VehicleShopPrompt"
	prompt.ActionText, prompt.ObjectText = actionText, objectText
	prompt.KeyboardKeyCode, prompt.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = math.max(1, tonumber(config().PromptDistance) or 10)
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		local playerObj = PlayerService.GetPlayer(player.UserId)
		local resolved, access = resolveAccess(player, context)
		if playerObj and resolved then
			Remotes.OpenVehicleShop:FireClient(player, access)
		end
	end)
end

local function createWorldShop()
	local old = Workspace:FindFirstChild(ROOT_FOLDER_NAME)
	if old then
		old:Destroy()
	end
	local rootFolder = Instance.new("Folder")
	rootFolder.Name = ROOT_FOLDER_NAME
	rootFolder.Parent = Workspace
	local displays = Instance.new("Folder")
	displays.Name = "ShowroomVehicles"
	displays.Parent = rootFolder
	local prompts = Instance.new("Folder")
	prompts.Name = "Prompts"
	prompts.Parent = rootFolder
	for index, spot in ipairs(config().ShowroomSpots or {}) do
		local id = trim(spot.id) ~= "" and trim(spot.id) or ("showroom_%d"):format(index)
		local vehicleName = trim(spot.vehicle)
		local position = positionOf(spot)
		if position then
			local vehicle, err = VehicleService.SpawnVehicle(nil, vehicleName, {
				cframe = cframeOf(spot),
				parent = displays,
				anchored = true,
				canCollide = false,
				disableScripts = true,
				attributes = { QBShowroomVehicle = true, QBVehicleShopVehicle = true, QBShowroomId = id },
			})
			if vehicle then
				vehicle.Name = "Display_" .. id
				if vehicle:IsA("BasePart") then
					vehicle.Anchored, vehicle.CanCollide, vehicle.CanTouch = true, false, false
				end
				for _, descendant in ipairs(vehicle:GetDescendants()) do
					if descendant:IsA("BasePart") then
						descendant.Anchored = true
						descendant.CanCollide = false
						descendant.CanTouch = false
					elseif descendant:IsA("BaseScript") then
						descendant.Enabled = false
					end
				end
			else
				warn(
					("[QBCore.VehicleShopService] Showroom %s could not spawn %s: %s"):format(
						id,
						vehicleName,
						tostring(err)
					)
				)
			end
			local definition = QBShared.Vehicles[vehicleName]
			createPrompt(
				prompts,
				"ShowroomPrompt_" .. id,
				position + Vector3.new(0, 2, 0),
				"Browse Vehicle",
				tostring(definition and definition.label or vehicleName),
				{
					mode = "showroom",
					locationId = id,
					vehicleName = vehicleName,
				}
			)
		end
	end
	local finance = config().FinanceSpot
	local financePosition = positionOf(finance)
	if financePosition then
		createPrompt(prompts, "FinancePrompt", financePosition, "Open Vehicle Shop", "Sales & Finance", {
			mode = "finance",
			locationId = trim(finance.id) ~= "" and trim(finance.id) or "finance",
		})
	end
end

function VehicleShopService.Start(vehicleService)
	if started then
		return
	end
	assert(type(vehicleService) == "table", "VehicleShopService.Start requires VehicleService")
	VehicleService = vehicleService
	started = true
	Remotes.GetVehicleShop.OnServerInvoke = function(player, requestedAccess)
		if config().Enabled == false then
			return nil, "The vehicle shop is closed."
		end
		local playerObj = PlayerService.GetPlayer(player.UserId)
		if not playerObj then
			return nil, "Load a character before using the vehicle shop."
		end
		local location, access, err = resolveAccess(player, requestedAccess)
		if not location then
			return nil, err
		end
		return getSnapshot(playerObj, access)
	end
	Remotes.VehicleShopAction.OnServerInvoke = function(player, action, payload)
		if config().Enabled == false then
			return false, "The vehicle shop is closed."
		end
		local playerObj = PlayerService.GetPlayer(player.UserId)
		if not playerObj then
			return false, "Load a character before using the vehicle shop."
		end
		payload = type(payload) == "table" and payload or {}
		local location, access, err = resolveAccess(player, payload.access)
		if not location then
			return false, err
		end
		local now = os.clock()
		if now - (lastActionAt[player] or 0) < ACTION_COOLDOWN then
			return false, "Please wait before submitting another request."
		end
		lastActionAt[player] = now
		action = type(action) == "string" and action:lower() or ""
		local handler = ACTIONS[action]
		if not handler then
			return false, "Unknown vehicle-shop action."
		end
		if actionBusy[player] then
			return false, "A vehicle-shop request is already in progress."
		end
		actionBusy[player] = true
		local handlerOk, ok, message = pcall(handler, player, playerObj, payload, access)
		actionBusy[player] = nil
		if not handlerOk then
			warn(("[QBCore.VehicleShopService] %s failed for %s: %s"):format(action, player.Name, tostring(ok)))
			return false, "The vehicle-shop request could not be completed."
		end
		if not ok then
			return false, message
		end
		playerObj:Notify(tostring(message or "Vehicle-shop request complete."), "success", 5000)
		return true, { message = message, snapshot = getSnapshot(playerObj, access) }
	end
	Players.PlayerRemoving:Connect(function(player)
		lastActionAt[player], actionBusy[player] = nil, nil
		local test = activeTestDrives[player]
		activeTestDrives[player] = nil
		if test and test.vehicle and test.vehicle.Parent then
			test.vehicle:Destroy()
		end
		local garages = QBShared.Config.Garages
		local shouldReturnToGarage = type(garages) ~= "table" or garages.AutoRespawn ~= false
		if shouldReturnToGarage then
			for ownershipId, vehicle in pairs(activeOwnedVehicles) do
				if vehicle and vehicle:GetAttribute("QBOwnerUserId") == player.UserId then
					activeOwnedVehicles[ownershipId] = nil
					if vehicle.Parent then
						vehicle:Destroy()
					end
				end
			end
		end
	end)
	if config().Enabled ~= false then
		createWorldShop()
	end
end

return VehicleShopService
