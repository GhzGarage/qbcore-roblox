-- Server-authoritative qb-shops-style item stores.
-- Delivery/restocking jobs are intentionally out of scope; configured stock lives
-- for the current server session and every purchase is revalidated at the counter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
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
local ShopService = {}

local INTERACTION_FOLDER_NAME = "QBShopLocations"
local started = false
local inventoryService = nil
local sessionStock = {}
local openShopIds = {}

local function config()
	return type(QBShared.Config.Shops) == "table" and QBShared.Config.Shops or {}
end

local function trim(value)
	return type(value) == "string" and (value:match("^%s*(.-)%s*$") or "") or ""
end

local function locationPosition(location)
	if type(location) ~= "table" then
		return nil
	end
	if typeof(location.position) == "Vector3" then
		return location.position
	end
	if type(location.position) == "table" then
		local x = tonumber(location.position.x or location.position.X)
		local y = tonumber(location.position.y or location.position.Y)
		local z = tonumber(location.position.z or location.position.Z)
		if x and y and z then
			return Vector3.new(x, y, z)
		end
	end
	return nil
end

local function getRoot(player)
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function gradeLevel(group)
	return type(group) == "table" and type(group.grade) == "table" and math.floor(tonumber(group.grade.level) or 0) or 0
end

local function namedRequirementPasses(name, grade, requirement)
	if requirement == nil then
		return true
	end
	if type(requirement) == "string" then
		return name == requirement
	end
	if type(requirement) ~= "table" then
		return false
	end

	if #requirement > 0 then
		for _, allowedName in ipairs(requirement) do
			if allowedName == name then
				return true
			end
		end
		return false
	end

	local requiredGrade = requirement[name]
	if requiredGrade == true then
		return true
	end
	if tonumber(requiredGrade) then
		return grade >= math.floor(tonumber(requiredGrade))
	end
	return false
end

local function licenseRequirementPasses(licenses, requirement)
	if requirement == nil then
		return true
	end
	licenses = type(licenses) == "table" and licenses or {}
	if type(requirement) == "string" then
		return licenses[requirement] == true
	end
	if type(requirement) ~= "table" then
		return false
	end
	for _, licenseName in ipairs(requirement) do
		if licenses[licenseName] == true then
			return true
		end
	end
	return false
end

local function playerCanAccess(playerObj, requirementSource)
	local data = playerObj and playerObj.PlayerData or {}
	local job = type(data.job) == "table" and data.job or {}
	local crew = type(data.crew) == "table" and data.crew or {}
	if not namedRequirementPasses(job.name, gradeLevel(job), requirementSource.requiredJob) then
		return false
	end
	if
		not namedRequirementPasses(
			crew.name,
			gradeLevel(crew),
			requirementSource.requiredCrew or requirementSource.requiredGang
		)
	then
		return false
	end
	if
		requirementSource.requiredGrade
		and gradeLevel(job) < math.floor(tonumber(requirementSource.requiredGrade) or 0)
	then
		return false
	end
	local metadata = type(data.metadata) == "table" and data.metadata or {}
	if not licenseRequirementPasses(metadata.licences, requirementSource.requiredLicense) then
		return false
	end
	if requirementSource.requiredItem and not inventoryService.HasItem(playerObj, requirementSource.requiredItem) then
		return false
	end
	return true
end

local function getProducts(location)
	local products = location and location.products
	if type(products) == "string" then
		products = type(config().Products) == "table" and config().Products[products] or nil
	end
	return type(products) == "table" and products or {}
end

local function findLocation(id)
	id = trim(id)
	for _, location in ipairs(config().Locations or {}) do
		if trim(location.id) == id then
			return location
		end
	end
	return nil
end

local function resolveShop(player, playerObj, access)
	if config().Enabled == false then
		return nil, nil, "Shops are currently unavailable."
	end
	if not playerObj then
		return nil, nil, "Character not loaded."
	end
	if playerObj:GetMetaData("isdead") == true then
		return nil, nil, "You cannot shop while dead."
	end

	local id = type(access) == "table" and trim(access.id) or ""
	local location = findLocation(id)
	if not location then
		return nil, nil, "That shop does not exist."
	end
	local position = locationPosition(location)
	local root = getRoot(player)
	local maxDistance = math.max(1, tonumber(config().ActionDistance) or 14)
	if not position or not root or (root.Position - position).Magnitude > maxDistance then
		return nil, nil, "Move closer to the shop counter."
	end
	if not playerCanAccess(playerObj, location) then
		return nil, nil, "You are not authorized to use this shop."
	end
	return location, { type = "shop", id = id }
end

local function stockFor(location, productIndex, product)
	local id = trim(location.id)
	sessionStock[id] = sessionStock[id] or {}
	if sessionStock[id][productIndex] == nil then
		sessionStock[id][productIndex] = math.max(0, math.floor(tonumber(product.amount) or 0))
	end
	return sessionStock[id][productIndex]
end

local function setStock(location, productIndex, amount)
	local id = trim(location.id)
	sessionStock[id] = sessionStock[id] or {}
	sessionStock[id][productIndex] = math.max(0, math.floor(tonumber(amount) or 0))
end

local function visibleProducts(playerObj, location)
	local visible = {}
	for productIndex, product in ipairs(getProducts(location)) do
		local definition = type(product) == "table" and QBShared.Items[trim(product.name):lower()] or nil
		if definition and playerCanAccess(playerObj, product) then
			table.insert(visible, {
				product = product,
				definition = definition,
				productIndex = productIndex,
			})
		end
	end
	return visible
end

local function copyInfo(info)
	local copy = {}
	if type(info) == "table" then
		for key, value in pairs(info) do
			if type(value) == "table" then
				local child = {}
				for childKey, childValue in pairs(value) do
					child[childKey] = childValue
				end
				copy[key] = child
			else
				copy[key] = value
			end
		end
	end
	return copy
end

local function getShopSnapshot(player, playerObj, access)
	local location, normalizedAccess, err = resolveShop(player, playerObj, access)
	if not location then
		return nil, nil, err
	end
	openShopIds[player] = normalizedAccess.id

	local items = {}
	local visible = visibleProducts(playerObj, location)
	for displaySlot, entry in ipairs(visible) do
		local definition = entry.definition
		local product = entry.product
		local stock = location.useStock == false and math.max(0, math.floor(tonumber(product.amount) or 0))
			or stockFor(location, entry.productIndex, product)
		items[tostring(displaySlot)] = {
			name = definition.name,
			label = definition.label or definition.name,
			amount = stock,
			stock = stock,
			slot = displaySlot,
			info = copyInfo(product.info),
			weight = tonumber(definition.weight) or 0,
			type = definition.type or "item",
			image = definition.image or "",
			unique = definition.unique == true,
			useable = false,
			shouldClose = false,
			description = definition.description or "",
			price = math.max(0, math.floor(tonumber(product.price) or 0)),
		}
	end

	return {
		type = "shop",
		id = normalizedAccess.id,
		label = tostring(location.label or "Shop"),
		items = items,
		slots = math.max(#visible, math.floor(tonumber(location.slots) or 0)),
		maxWeight = 0,
		totalWeight = 0,
		readOnly = true,
		actions = { purchase = true, take = false, deposit = false },
	},
		normalizedAccess
end

local function refreshOtherCustomers(shopId, purchasingPlayer)
	for openPlayer, openShopId in pairs(openShopIds) do
		if openPlayer.Parent ~= Players then
			openShopIds[openPlayer] = nil
		elseif openPlayer ~= purchasingPlayer and openShopId == shopId then
			Remotes.OpenInventory:FireClient(openPlayer, { type = "shop", id = shopId })
		end
	end
end

local function paymentTypesFor(location, product)
	local paymentTypes = product.paymentTypes
		or product.paymentType
		or location.paymentTypes
		or config().DefaultPaymentTypes
	if type(paymentTypes) == "string" then
		return { paymentTypes }
	end
	return type(paymentTypes) == "table" and paymentTypes or { "cash" }
end

local function purchase(player, playerObj, payload)
	local location, normalizedAccess, err = resolveShop(player, playerObj, payload.access)
	if not location then
		return false, err
	end

	local slot = math.floor(tonumber(payload.slot) or 0)
	local amount = math.floor(tonumber(payload.amount) or 0)
	local maxAmount = math.max(1, math.floor(tonumber(config().MaxPurchaseAmount) or 100))
	if slot < 1 or amount < 1 or amount > maxAmount then
		return false, "Invalid purchase amount."
	end

	local entry = visibleProducts(playerObj, location)[slot]
	if not entry then
		return false, "That product is unavailable."
	end
	local product = entry.product
	local definition = entry.definition
	local stock = location.useStock == false and math.max(0, math.floor(tonumber(product.amount) or 0))
		or stockFor(location, entry.productIndex, product)
	if stock <= 0 or amount > stock then
		return false, "The shop does not have enough stock."
	end

	local canAdd, canAddErr = inventoryService.CanAddItem(playerObj, definition.name, amount, nil, product.info)
	if not canAdd then
		return false, canAddErr or "You cannot carry that purchase."
	end

	local unitPrice = math.max(0, math.floor(tonumber(product.price) or 0))
	local totalPrice = unitPrice * amount
	local paidWith = nil
	for _, moneyType in ipairs(paymentTypesFor(location, product)) do
		if type(moneyType) == "string" and (tonumber(playerObj:GetMoney(moneyType)) or -1) >= totalPrice then
			paidWith = moneyType:lower()
			break
		end
	end
	if not paidWith then
		return false, "You do not have enough money."
	end
	if not playerObj:RemoveMoney(paidWith, totalPrice, "shop-purchase") then
		return false, "The payment could not be completed."
	end

	local added, addErr =
		inventoryService.AddItem(playerObj, definition.name, amount, nil, product.info, "shop-purchase")
	if not added then
		playerObj:AddMoney(paidWith, totalPrice, "shop-purchase-rollback")
		return false, addErr or "The purchase could not be added to your inventory."
	end
	if location.useStock ~= false then
		setStock(location, entry.productIndex, stock - amount)
		refreshOtherCustomers(normalizedAccess.id, player)
	end

	playerObj:Notify(
		("Purchased %dx %s for $%d (%s)."):format(amount, definition.label or definition.name, totalPrice, paidWith),
		"success",
		3500
	)
	return true, inventoryService.GetOpenSnapshot(playerObj, player, normalizedAccess)
end

local function handleAction(player, playerObj, action, payload)
	if action == "purchase" then
		return purchase(player, playerObj, payload)
	end
	return false, "That shop action is not supported."
end

local function closeShop(player, _, access)
	local id = type(access) == "table" and trim(access.id) or ""
	if openShopIds[player] == id then
		openShopIds[player] = nil
	end
end

local function safePartName(id, index)
	local value = trim(id):gsub("[^%w_%-]", "_")
	return value ~= "" and value or ("Shop_%d"):format(index)
end

local function createInteraction(location, index, folder)
	local id = trim(location.id)
	local position = locationPosition(location)
	if id == "" or not position then
		warn(("[QBCore.ShopService] Shop %d needs a unique id and Vector3 position."):format(index))
		return
	end

	local part = folder:FindFirstChild(safePartName(id, index))
	if part and not part:IsA("BasePart") then
		warn(("[QBCore.ShopService] %s must be a BasePart."):format(part:GetFullName()))
		return
	end
	if not part then
		part = Instance.new("Part")
		part.Name = safePartName(id, index)
		part.Parent = folder
	end
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.CastShadow, part.Transparency, part.Size, part.Position = false, 1, Vector3.new(2, 2, 2), position

	local prompt = part:FindFirstChild("ShopPrompt")
	if prompt and not prompt:IsA("ProximityPrompt") then
		warn(("[QBCore.ShopService] %s.ShopPrompt must be a ProximityPrompt."):format(part:GetFullName()))
		return
	end
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ShopPrompt"
		prompt.Parent = part
	end
	prompt.ActionText = "Open Shop"
	prompt.ObjectText = tostring(location.label or "Shop")
	prompt.KeyboardKeyCode, prompt.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = math.max(1, tonumber(config().PromptDistance) or 10)
	prompt.RequiresLineOfSight = false
	prompt.Enabled = config().Enabled ~= false
	prompt.Triggered:Connect(function(player)
		local playerObj = PlayerService.GetPlayer(player.UserId)
		local resolved, access, err = resolveShop(player, playerObj, { type = "shop", id = id })
		if resolved then
			Remotes.OpenInventory:FireClient(player, access)
		elseif playerObj then
			playerObj:Notify(err or "That shop is unavailable.", "error", 3500)
		end
	end)
end

local function createInteractions()
	local folder = Workspace:FindFirstChild(INTERACTION_FOLDER_NAME)
	if folder and not folder:IsA("Folder") then
		warn(("[QBCore.ShopService] Workspace.%s must be a Folder."):format(INTERACTION_FOLDER_NAME))
		return
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = INTERACTION_FOLDER_NAME
		folder.Parent = Workspace
	end
	for index, location in ipairs(config().Locations or {}) do
		createInteraction(location, index, folder)
	end
end

function ShopService.Start(InventoryService)
	if started then
		return
	end
	started = true
	inventoryService = InventoryService
	inventoryService.RegisterExternalProvider("shop", {
		GetSnapshot = getShopSnapshot,
		HandleAction = handleAction,
		Close = closeShop,
	})
	Players.PlayerRemoving:Connect(function(player)
		openShopIds[player] = nil
	end)
	createInteractions()
end

return ShopService
