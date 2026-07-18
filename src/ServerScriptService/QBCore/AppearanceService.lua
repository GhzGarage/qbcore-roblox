--[[
    Per-character appearance backend (rough port of the qb-clothing role in QBCore).

    Each character slot stores a serialized HumanoidDescription (a plain, DataStore-safe
    table) in PlayerData.appearance and it is re-applied on every spawn, so characters on
    the same account can look completely different. The player's real site-wide avatar is
    never touched -- we never call PromptSaveAvatar, only Humanoid:ApplyDescription on the
    in-world character.

    The client (QBAppearance.client.lua) edits a working copy and streams it here through
    the PreviewAppearance remote; every payload is sanitized (whitelisted keys, clamped
    scales, capped/deduped accessory list) before it goes anywhere near ApplyDescription.
    Nothing persists until SaveAppearance, which optionally re-checks catalog ownership
    through MarketplaceService so a modified client cannot save items it does not own.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local function requireQBShared()
	local shared = ReplicatedStorage:FindFirstChild("QBShared")
	if not shared then
		error("QBCore setup error: ReplicatedStorage must contain QBShared.", 2)
	end

	if shared:IsA("ModuleScript") then
		return require(shared)
	end

	for _, moduleName in ipairs({ "Main", "init", "init.lua" }) do
		local module = shared:FindFirstChild(moduleName)
		if module and module:IsA("ModuleScript") then
			return require(module)
		end
	end

	error(
		"QBCore setup error: ReplicatedStorage.QBShared must be a ModuleScript, or a Folder containing a Main ModuleScript.",
		2
	)
end

local QBShared = requireQBShared()
local Remotes = require(ReplicatedStorage.QBRemotes)

local AppearanceService = {}
local outfitCodeStore = DataStoreService:GetDataStore("QBCore_OutfitCodes")
local CLOTHING_FOLDER_NAME = "QBClothingShops"
local OUTFIT_ACTION_COOLDOWN = 0.4
local SHARE_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

local playerService = nil
local started = false
local lastOutfitActionAt = {}
local outfitBusy = {}

-- serialized-table key -> HumanoidDescription property
local SCALE_KEYS = {
	height = "HeightScale",
	width = "WidthScale",
	depth = "DepthScale",
	head = "HeadScale",
	bodyType = "BodyTypeScale",
	proportion = "ProportionScale",
}
local BODY_PART_KEYS = {
	face = "Face",
	head = "Head",
	torso = "Torso",
	leftArm = "LeftArm",
	rightArm = "RightArm",
	leftLeg = "LeftLeg",
	rightLeg = "RightLeg",
}
-- Classic clothing properties only; layered clothing is stored as accessories.
local CLOTHING_KEYS = { shirt = "Shirt", pants = "Pants", graphicTShirt = "GraphicTShirt" }
local COLOR_KEYS = {
	head = "HeadColor",
	torso = "TorsoColor",
	leftArm = "LeftArmColor",
	rightArm = "RightArmColor",
	leftLeg = "LeftLegColor",
	rightLeg = "RightLegColor",
}

-- Shop category -> serialized fields/accessory types that category is allowed to
-- change. This map is enforced server-side; hidden client tabs are only presentation.
local CATEGORY_ACCESS = {
	Hair = { accessories = { Hair = true } },
	Hats = { accessories = { Hat = true } },
	FaceAcc = { accessories = { Face = true } },
	Faces = { bodyParts = { face = true } },
	Shirts = { clothing = { shirt = true } },
	Pants = { clothing = { pants = true } },
	TShirts = { clothing = { graphicTShirt = true } },
	LayeredTShirts = { accessories = { TShirt = true } },
	LayeredShirts = { accessories = { Shirt = true } },
	LayeredPants = { accessories = { Pants = true } },
	Jackets = { accessories = { Jacket = true } },
	Sweaters = { accessories = { Sweater = true } },
	Shorts = { accessories = { Shorts = true } },
	Dresses = { accessories = { DressSkirt = true } },
	Shoes = { accessories = { LeftShoe = true, RightShoe = true } },
	Neck = { accessories = { Neck = true } },
	Shoulder = { accessories = { Shoulder = true } },
	Front = { accessories = { Front = true } },
	Back = { accessories = { Back = true } },
	Waist = { accessories = { Waist = true } },
	Skin = { colors = true },
	Body = { scales = true },
}

-- Shareable outfits are deliberately narrower than a full appearance. Hair,
-- eyebrows/eyelashes, face assets, body parts/scales, and skin colors never enter a
-- saved outfit or code.
local OUTFIT_ACCESSORY_TYPES = {
	Hat = true,
	Face = true,
	Neck = true,
	Shoulder = true,
	Front = true,
	Back = true,
	Waist = true,
	TShirt = true,
	Shirt = true,
	Pants = true,
	Jacket = true,
	Sweater = true,
	Shorts = true,
	DressSkirt = true,
	LeftShoe = true,
	RightShoe = true,
}

local VALID_ACCESSORY_TYPES = {}
for _, item in ipairs(Enum.AccessoryType:GetEnumItems()) do
	if item ~= Enum.AccessoryType.Unknown then
		VALID_ACCESSORY_TYPES[item.Name] = item
	end
end

local sessions = {} -- [UserId] = { respawnConn, editing, original, pending, applying }
local ownershipCache = {} -- [UserId] = { [assetId] = true|false }

local function appearanceConfig()
	return QBShared.Config.Appearance or {}
end

local function clothingConfig()
	return type(QBShared.Config.Clothing) == "table" and QBShared.Config.Clothing or {}
end

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, entry in pairs(value) do
		copy[key] = deepCopy(entry)
	end
	return copy
end

local function trim(value)
	return type(value) == "string" and (value:match("^%s*(.-)%s*$") or "") or ""
end

local function scaleRange(key)
	local range = (appearanceConfig().Scales or {})[key] or {}
	local min = tonumber(range.Min) or 0
	local max = tonumber(range.Max) or math.max(1, min)
	local default = math.clamp(tonumber(range.Default) or 1, min, max)
	return min, max, default
end

local function getSession(userId)
	local session = sessions[userId]
	if not session then
		session = {}
		sessions[userId] = session
	end
	return session
end

-- ─────────────────────────── (de)serialization + sanitizing ───────────────────────────

function AppearanceService.Serialize(description)
	local out = { scales = {}, bodyParts = {}, clothing = {}, colors = {}, accessories = {} }

	for key, prop in pairs(SCALE_KEYS) do
		out.scales[key] = description[prop]
	end
	for key, prop in pairs(BODY_PART_KEYS) do
		out.bodyParts[key] = description[prop]
	end
	for key, prop in pairs(CLOTHING_KEYS) do
		out.clothing[key] = description[prop]
	end
	for key, prop in pairs(COLOR_KEYS) do
		out.colors[key] = description[prop]:ToHex()
	end

	for _, accessory in ipairs(description:GetAccessories(true)) do
		out.accessories[#out.accessories + 1] = {
			id = accessory.AssetId,
			type = accessory.AccessoryType.Name,
			isLayered = accessory.IsLayered or false,
			order = accessory.Order,
			puffiness = accessory.Puffiness,
		}
	end

	return out
end

function AppearanceService.Deserialize(appearance)
	local description = Instance.new("HumanoidDescription")

	local scales = type(appearance.scales) == "table" and appearance.scales or {}
	for key, prop in pairs(SCALE_KEYS) do
		local value = tonumber(scales[key])
		if value then
			description[prop] = value
		end
	end

	local bodyParts = type(appearance.bodyParts) == "table" and appearance.bodyParts or {}
	for key, prop in pairs(BODY_PART_KEYS) do
		description[prop] = tonumber(bodyParts[key]) or 0
	end

	local clothing = type(appearance.clothing) == "table" and appearance.clothing or {}
	for key, prop in pairs(CLOTHING_KEYS) do
		description[prop] = tonumber(clothing[key]) or 0
	end

	local colors = type(appearance.colors) == "table" and appearance.colors or {}
	for key, prop in pairs(COLOR_KEYS) do
		if type(colors[key]) == "string" then
			local ok, color = pcall(Color3.fromHex, colors[key])
			if ok then
				description[prop] = color
			end
		end
	end

	local specs = {}
	for _, entry in ipairs(type(appearance.accessories) == "table" and appearance.accessories or {}) do
		local accessoryType = type(entry) == "table" and VALID_ACCESSORY_TYPES[entry.type]
		local assetId = accessoryType and tonumber(entry.id)
		if assetId and assetId > 0 then
			local spec = { AssetId = assetId, AccessoryType = accessoryType, IsLayered = entry.isLayered == true }
			if spec.IsLayered then
				-- Order/Puffiness are layered-clothing-only; SetAccessories rejects them on rigid items
				spec.Order = tonumber(entry.order) or #specs + 1
				spec.Puffiness = tonumber(entry.puffiness)
			end
			specs[#specs + 1] = spec
		end
	end
	if #specs > 0 then
		description:SetAccessories(specs, true)
	end

	return description
end

local function sanitizeAssetId(value)
	value = tonumber(value)
	if not value or value ~= value or value < 0 or value > 1e15 then
		return 0
	end
	return math.floor(value)
end

-- Rebuilds a client payload from scratch, copying only whitelisted keys with type checks
-- and clamps. Returns nil if the payload is not even a table.
local function sanitizeAppearance(payload)
	if type(payload) ~= "table" then
		return nil
	end

	local out = { scales = {}, bodyParts = {}, clothing = {}, colors = {}, accessories = {} }

	local scalesIn = type(payload.scales) == "table" and payload.scales or {}
	for key in pairs(SCALE_KEYS) do
		local min, max, default = scaleRange(key)
		out.scales[key] = math.clamp(tonumber(scalesIn[key]) or default, min, max)
	end

	local bodyPartsIn = type(payload.bodyParts) == "table" and payload.bodyParts or {}
	for key in pairs(BODY_PART_KEYS) do
		out.bodyParts[key] = sanitizeAssetId(bodyPartsIn[key])
	end

	local clothingIn = type(payload.clothing) == "table" and payload.clothing or {}
	for key in pairs(CLOTHING_KEYS) do
		out.clothing[key] = sanitizeAssetId(clothingIn[key])
	end

	local colorsIn = type(payload.colors) == "table" and payload.colors or {}
	for key in pairs(COLOR_KEYS) do
		local hex = colorsIn[key]
		if type(hex) == "string" then
			hex = hex:gsub("^#", ""):lower()
			if hex:match("^%x%x%x%x%x%x$") then
				out.colors[key] = hex
			end
		end
	end

	local maxAccessories = tonumber(appearanceConfig().MaxAccessories) or 15
	local seen = {}
	for _, entry in ipairs(type(payload.accessories) == "table" and payload.accessories or {}) do
		if #out.accessories >= maxAccessories then
			break
		end
		if type(entry) == "table" then
			local id = sanitizeAssetId(entry.id)
			local isLayered = entry.isLayered == true
			if id > 0 and not seen[id] and type(entry.type) == "string" and VALID_ACCESSORY_TYPES[entry.type] then
				seen[id] = true
				local defaultOrder = #out.accessories + 1
				out.accessories[#out.accessories + 1] = {
					id = id,
					type = entry.type,
					isLayered = isLayered,
					order = isLayered and math.clamp(math.floor(tonumber(entry.order) or defaultOrder), 0, 100) or nil,
					puffiness = isLayered and math.clamp(tonumber(entry.puffiness) or 1, 0, 2) or nil,
				}
			end
		end
	end

	return out
end

local function categorySet(categories)
	local set = {}
	for _, key in ipairs(type(categories) == "table" and categories or {}) do
		if type(key) == "string" and CATEGORY_ACCESS[key] then
			set[key] = true
		end
	end
	return set
end

local function restrictToCategories(original, candidate, categories)
	original = sanitizeAppearance(original) or sanitizeAppearance({})
	candidate = sanitizeAppearance(candidate)
	if not candidate then
		return nil
	end
	local allowedCategories = categorySet(categories)
	local result = deepCopy(original)
	local allowedAccessoryTypes = {}
	for categoryKey in pairs(allowedCategories) do
		local access = CATEGORY_ACCESS[categoryKey]
		if access.scales then
			result.scales = deepCopy(candidate.scales)
		end
		if access.colors then
			result.colors = deepCopy(candidate.colors)
		end
		for key in pairs(access.bodyParts or {}) do
			result.bodyParts[key] = candidate.bodyParts[key]
		end
		for key in pairs(access.clothing or {}) do
			result.clothing[key] = candidate.clothing[key]
		end
		for accessoryType in pairs(access.accessories or {}) do
			allowedAccessoryTypes[accessoryType] = true
		end
	end
	if next(allowedAccessoryTypes) then
		local accessories = {}
		for _, entry in ipairs(original.accessories) do
			if not allowedAccessoryTypes[entry.type] then
				accessories[#accessories + 1] = deepCopy(entry)
			end
		end
		for _, entry in ipairs(candidate.accessories) do
			if allowedAccessoryTypes[entry.type] then
				accessories[#accessories + 1] = deepCopy(entry)
			end
		end
		result.accessories = accessories
	end
	return sanitizeAppearance(result)
end

local function extractWearables(appearance)
	local clean = sanitizeAppearance(appearance) or sanitizeAppearance({})
	local wearable = { clothing = deepCopy(clean.clothing), accessories = {} }
	for _, entry in ipairs(clean.accessories) do
		if OUTFIT_ACCESSORY_TYPES[entry.type] then
			wearable.accessories[#wearable.accessories + 1] = deepCopy(entry)
		end
	end
	return wearable
end

local function mergeWearables(baseAppearance, wearable)
	local base = sanitizeAppearance(baseAppearance) or sanitizeAppearance({})
	local cleanWearable =
		extractWearables({ clothing = wearable and wearable.clothing, accessories = wearable and wearable.accessories })
	base.clothing = cleanWearable.clothing
	local accessories = {}
	for _, entry in ipairs(base.accessories) do
		if not OUTFIT_ACCESSORY_TYPES[entry.type] then
			accessories[#accessories + 1] = deepCopy(entry)
		end
	end
	for _, entry in ipairs(cleanWearable.accessories) do
		accessories[#accessories + 1] = deepCopy(entry)
	end
	base.accessories = accessories
	return sanitizeAppearance(base)
end

local function getCharacterRoot(player)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end
	return root
end

local function shopPosition(shop)
	if type(shop) ~= "table" then
		return nil
	end
	if typeof(shop.position) == "Vector3" then
		return shop.position
	end
	if type(shop.position) == "table" then
		local x = tonumber(shop.position.x or shop.position.X)
		local y = tonumber(shop.position.y or shop.position.Y)
		local z = tonumber(shop.position.z or shop.position.Z)
		if x and y and z then
			return Vector3.new(x, y, z)
		end
	end
	return nil
end

local function roleAllowed(playerObj, shop)
	local requiredJob = trim(shop.requiredJob):lower()
	local requiredCrew = trim(shop.requiredCrew):lower()
	local minGrade = math.max(0, math.floor(tonumber(shop.minGrade) or 0))
	if requiredJob ~= "" then
		local job = playerObj and playerObj.PlayerData.job or {}
		if job.name ~= requiredJob or math.floor(tonumber((job.grade or {}).level) or 0) < minGrade then
			return false, "Your job cannot use this clothing room."
		end
	end
	if requiredCrew ~= "" then
		local crew = playerObj and playerObj.PlayerData.crew or {}
		if crew.name ~= requiredCrew or math.floor(tonumber((crew.grade or {}).level) or 0) < minGrade then
			return false, "Your crew cannot use this clothing room."
		end
	end
	return true
end

local function resolveShop(player, locationId, playerObj)
	local root = getCharacterRoot(player)
	if not root then
		return nil, "Your character is unavailable."
	end
	local requestedId = trim(locationId)
	local maxDistance = math.max(1, tonumber(clothingConfig().ActionDistance) or 14)
	for index, shop in ipairs(clothingConfig().Shops or {}) do
		local id = trim(shop.id)
		if id == "" then
			id = "clothing_shop_" .. index
		end
		local position = shopPosition(shop)
		if
			(requestedId == "" or requestedId == id)
			and position
			and (root.Position - position).Magnitude <= maxDistance
		then
			local allowed, err = roleAllowed(playerObj, shop)
			if not allowed then
				return nil, err
			end
			return shop, nil, id
		end
	end
	return nil, "Move closer to a clothing shop."
end

local function sessionContextAppearance(session, candidate)
	local context = type(session.context) == "table" and session.context or { mode = "full" }
	if context.outfitsOnly == true then
		-- Outfit actions are separate, server-authoritative mutations. The ordinary
		-- preview/save remotes must never turn a wardrobe into a full appearance editor.
		return deepCopy(session.original)
	end
	if context.mode == "shop" then
		return restrictToCategories(session.original, candidate, context.categories)
	end
	return sanitizeAppearance(candidate)
end

local function appearanceAssetSet(appearance)
	local set = {}
	local clean = sanitizeAppearance(appearance)
	if not clean then
		return set
	end
	for _, entry in ipairs(clean.accessories) do
		if entry.id > 0 then
			set[entry.id] = true
		end
	end
	for key in pairs(CLOTHING_KEYS) do
		local id = clean.clothing[key]
		if id and id > 0 then
			set[id] = true
		end
	end
	return set
end

-- ─────────────────────────── ownership validation ───────────────────────────

local function playerOwnsAsset(player, assetId)
	local cache = ownershipCache[player.UserId]
	if not cache then
		cache = {}
		ownershipCache[player.UserId] = cache
	end
	if cache[assetId] ~= nil then
		return cache[assetId]
	end

	local ok, owns = pcall(MarketplaceService.PlayerOwnsAsset, MarketplaceService, player, assetId)
	if not ok then
		-- fail open: a marketplace API hiccup should not block saving a look
		warn(
			("[QBCore.AppearanceService] PlayerOwnsAsset(%d) failed for %s: %s"):format(
				assetId,
				player.Name,
				tostring(owns)
			)
		)
		return true
	end

	cache[assetId] = owns
	return owns
end

-- Only checks the pieces the editor lets players add (accessories + classic clothing).
-- Body parts and faces that arrive with a bundle avatar often fail PlayerOwnsAsset even
-- though the player legitimately wears them, so they are left alone.
local function validateOwnership(player, appearance)
	local ids = {}
	for _, entry in ipairs(appearance.accessories) do
		ids[#ids + 1] = entry.id
	end
	for key in pairs(CLOTHING_KEYS) do
		local id = appearance.clothing[key]
		if id and id > 0 then
			ids[#ids + 1] = id
		end
	end

	for _, assetId in ipairs(ids) do
		if not playerOwnsAsset(player, assetId) then
			return false, assetId
		end
	end
	return true
end

local function validateNewOwnership(player, original, appearance)
	local existing = appearanceAssetSet(original)
	local clean = sanitizeAppearance(appearance)
	if not clean then
		return false, 0
	end
	for _, entry in ipairs(clean.accessories) do
		if entry.id > 0 and not existing[entry.id] and not playerOwnsAsset(player, entry.id) then
			return false, entry.id
		end
	end
	for key in pairs(CLOTHING_KEYS) do
		local id = clean.clothing[key]
		if id and id > 0 and not existing[id] and not playerOwnsAsset(player, id) then
			return false, id
		end
	end
	return true
end

-- ─────────────────────────── applying + spawn hooks ───────────────────────────

function AppearanceService.ApplyToCharacter(character, appearance)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or type(appearance) ~= "table" then
		return false
	end

	local ok, err = pcall(function()
		humanoid:ApplyDescription(AppearanceService.Deserialize(appearance))
	end)
	if not ok then
		warn("[QBCore.AppearanceService] ApplyDescription failed: " .. tostring(err))
	end
	return ok
end

-- Called by PlayerService right after the character is loaded into the world: applies the
-- saved look (if any) and keeps re-applying it on every respawn for the session.
function AppearanceService.OnCharacterSelected(player, playerObj)
	local session = getSession(player.UserId)

	if session.respawnConn then
		session.respawnConn:Disconnect()
	end
	session.respawnConn = player.CharacterAdded:Connect(function(character)
		local saved = playerObj.PlayerData.appearance
		if saved and character:WaitForChild("Humanoid", 10) then
			AppearanceService.ApplyToCharacter(character, saved)
		end
	end)

	local saved = playerObj.PlayerData.appearance
	if saved then
		AppearanceService.ApplyToCharacter(player.Character, saved)
	end
end

-- ─────────────────────────── editor session ───────────────────────────

local function ensureOutfits(playerObj)
	if type(playerObj.PlayerData.outfits) ~= "table" then
		playerObj.PlayerData.outfits = {}
	end
	return playerObj.PlayerData.outfits
end

local function outfitSummaries(playerObj)
	local summaries = {}
	for _, outfit in ipairs(ensureOutfits(playerObj)) do
		if type(outfit) == "table" and type(outfit.id) == "string" then
			summaries[#summaries + 1] = {
				id = outfit.id,
				name = tostring(outfit.name or "Saved Outfit"),
				code = tostring(outfit.code or ""),
				createdAt = tonumber(outfit.createdAt) or 0,
			}
		end
	end
	table.sort(summaries, function(a, b)
		if a.createdAt == b.createdAt then
			return string.lower(a.name) < string.lower(b.name)
		end
		return a.createdAt > b.createdAt
	end)
	return summaries
end

local function cleanOutfitName(value)
	local maxLength = math.clamp(math.floor(tonumber(clothingConfig().MaxOutfitNameLength) or 30), 3, 60)
	local name = trim(value):gsub("[%c]", " "):gsub("%s+", " ")
	if name == "" then
		return nil, "Enter an outfit name."
	end
	return name:sub(1, maxLength)
end

local function randomShareCode()
	local length = math.clamp(math.floor(tonumber(clothingConfig().ShareCodeLength) or 8), 6, 12)
	local chars = table.create(length)
	for index = 1, length do
		local offset = math.random(1, #SHARE_CODE_ALPHABET)
		chars[index] = SHARE_CODE_ALPHABET:sub(offset, offset)
	end
	return table.concat(chars)
end

local function createShareCode(record)
	for _ = 1, 20 do
		local code = randomShareCode()
		local claimToken = HttpService:GenerateGUID(false)
		local candidate = deepCopy(record)
		candidate.claimToken = claimToken
		local stored
		local ok, err = pcall(function()
			stored = outfitCodeStore:UpdateAsync("Code_" .. code, function(existing)
				if existing ~= nil then
					return existing
				end
				return candidate
			end)
		end)
		if ok and type(stored) == "table" and stored.claimToken == claimToken then
			return code
		end
		if not ok then
			warn(("[QBCore.AppearanceService] Outfit code creation failed: %s"):format(tostring(err)))
			return nil, "The outfit code service is temporarily unavailable."
		end
	end
	return nil, "A unique outfit code could not be generated."
end

local function revokeShareCode(code)
	code = trim(code):upper()
	if code ~= "" then
		pcall(function()
			outfitCodeStore:RemoveAsync("Code_" .. code)
		end)
	end
end

local function validateSessionAccess(player, playerObj, session, requireOutfits)
	if not session or not session.editing then
		return false, "The appearance editor is not open."
	end
	local context = type(session.context) == "table" and session.context or { mode = "full" }
	if requireOutfits and context.allowOutfits ~= true then
		return false, "Outfits are not available here."
	end
	if tonumber(context.expiresAt) and os.clock() > context.expiresAt then
		return false, "This wardrobe session expired."
	end
	if context.mode == "shop" then
		local shop, err, id = resolveShop(player, context.locationId, playerObj)
		if not shop or id ~= context.locationId then
			return false, err or "Move closer to the clothing shop."
		end
	end
	return true
end

local function saveCurrentAppearance(player, playerObj, session, nextAppearance)
	local previous = deepCopy(playerObj.PlayerData.appearance or session.original)
	playerObj:SetPlayerData("appearance", nextAppearance)
	if playerObj:Save() ~= true then
		playerObj:SetPlayerData("appearance", previous)
		playerObj:Save()
		return false, "Your appearance could not be saved; the change was reversed."
	end
	session.original = deepCopy(nextAppearance)
	session.pending = nil
	AppearanceService.ApplyToCharacter(player.Character, nextAppearance)
	return true
end

local function saveOutfit(player, playerObj, session, payload)
	local name, nameErr = cleanOutfitName(payload.name)
	if not name then
		return false, nameErr
	end
	local outfits = ensureOutfits(playerObj)
	local maxOutfits = math.clamp(math.floor(tonumber(clothingConfig().MaxOutfits) or 20), 1, 100)
	if #outfits >= maxOutfits then
		return false, ("You can save at most %d outfits."):format(maxOutfits)
	end
	local candidate = sessionContextAppearance(session, payload.appearance)
	if not candidate then
		return false, "Invalid outfit data."
	end
	if appearanceConfig().ValidateOwnership ~= false then
		local owns, badAssetId = validateNewOwnership(player, session.original, candidate)
		if not owns then
			return false, ("You don't own one of those items (asset %d)."):format(badAssetId)
		end
	end
	local wearable = extractWearables(candidate)
	local createdAt = os.time()
	local id = HttpService:GenerateGUID(false)
	local code, codeErr = createShareCode({ version = 1, wearable = wearable, createdAt = createdAt })
	if not code then
		return false, codeErr
	end
	local previous = deepCopy(outfits)
	outfits[#outfits + 1] = { id = id, name = name, code = code, wearable = wearable, createdAt = createdAt }
	playerObj:SetPlayerData("outfits", outfits)
	if playerObj:Save() ~= true then
		playerObj:SetPlayerData("outfits", previous)
		playerObj:Save()
		revokeShareCode(code)
		return false, "The outfit could not be saved."
	end
	return true, { message = ("Saved %s. Share code: %s"):format(name, code), outfits = outfitSummaries(playerObj) }
end

local function findOutfit(playerObj, id)
	for index, outfit in ipairs(ensureOutfits(playerObj)) do
		if type(outfit) == "table" and outfit.id == id then
			return outfit, index
		end
	end
	return nil
end

local function applyWearable(player, playerObj, session, wearable, message, shared)
	local base = playerObj.PlayerData.appearance or session.original
	local merged = mergeWearables(base, wearable)
	local context = type(session.context) == "table" and session.context or { mode = "full" }
	if context.mode == "shop" and context.outfitsOnly ~= true then
		merged = restrictToCategories(base, merged, context.categories)
	end
	if shared and clothingConfig().RequireOwnershipForSharedOutfits == true then
		local owns, badAssetId = validateOwnership(
			player,
			sanitizeAppearance({
				clothing = wearable and wearable.clothing,
				accessories = wearable and wearable.accessories,
			})
		)
		if not owns then
			return false, ("You don't own one of those items (asset %d)."):format(badAssetId)
		end
	end
	local saved, err = saveCurrentAppearance(player, playerObj, session, merged)
	if not saved then
		return false, err
	end
	return true, { message = message, outfits = outfitSummaries(playerObj), appearance = merged }
end

local function applySavedOutfit(player, playerObj, session, payload)
	local outfit = findOutfit(playerObj, trim(payload.id))
	if not outfit then
		return false, "That saved outfit no longer exists."
	end
	return applyWearable(
		player,
		playerObj,
		session,
		outfit.wearable,
		("Applied %s."):format(outfit.name or "outfit"),
		false
	)
end

local function applySharedCode(player, playerObj, session, payload)
	local code = trim(payload.code):upper():gsub("[^A-Z0-9]", "")
	-- Accept the full supported range so codes remain valid if ShareCodeLength is
	-- changed after outfits have already been shared.
	if #code < 6 or #code > 12 then
		return false, "Enter a 6-12 character outfit code."
	end
	local record
	local ok, err = pcall(function()
		record = outfitCodeStore:GetAsync("Code_" .. code)
	end)
	if not ok then
		warn(("[QBCore.AppearanceService] Outfit code read failed for %s: %s"):format(code, tostring(err)))
		return false, "The outfit code service is temporarily unavailable."
	end
	if type(record) ~= "table" or tonumber(record.version) ~= 1 or type(record.wearable) ~= "table" then
		return false, "That outfit code was not found."
	end
	return applyWearable(player, playerObj, session, record.wearable, ("Applied outfit code %s."):format(code), true)
end

local function deleteOutfit(playerObj, payload)
	local outfit, index = findOutfit(playerObj, trim(payload.id))
	if not outfit then
		return false, "That saved outfit no longer exists."
	end
	local outfits = ensureOutfits(playerObj)
	local previous = deepCopy(outfits)
	table.remove(outfits, index)
	playerObj:SetPlayerData("outfits", outfits)
	if playerObj:Save() ~= true then
		playerObj:SetPlayerData("outfits", previous)
		playerObj:Save()
		return false, "The outfit could not be deleted."
	end
	revokeShareCode(outfit.code)
	return true, { message = "Outfit deleted and share code revoked.", outfits = outfitSummaries(playerObj) }
end

local function handleOutfitAction(player, playerObj, action, payload)
	local session = sessions[player.UserId]
	local allowed, err = validateSessionAccess(player, playerObj, session, true)
	if not allowed then
		return false, err
	end
	payload = type(payload) == "table" and payload or {}
	if action == "save" then
		return saveOutfit(player, playerObj, session, payload)
	end
	if action == "apply" then
		return applySavedOutfit(player, playerObj, session, payload)
	end
	if action == "apply_code" then
		return applySharedCode(player, playerObj, session, payload)
	end
	if action == "delete" then
		return deleteOutfit(playerObj, payload)
	end
	if action == "refresh" then
		return true, { message = "Outfits refreshed.", outfits = outfitSummaries(playerObj) }
	end
	return false, "Unknown outfit action."
end

function AppearanceService.OpenEditor(player, playerObj, isNewCharacter, requestedContext)
	local session = getSession(player.UserId)
	local context = { mode = "full", title = "Appearance", allowOutfits = false }
	if type(requestedContext) == "table" and requestedContext.mode == "shop" then
		local shop, accessErr, locationId = resolveShop(player, requestedContext.locationId, playerObj)
		if not shop then
			return false, accessErr
		end
		context = {
			mode = "shop",
			locationId = locationId,
			title = tostring(shop.label or "Clothing Shop"),
			categories = deepCopy(type(shop.categories) == "table" and shop.categories or {}),
			allowOutfits = shop.allowOutfits == true,
			outfitsOnly = shop.outfitsOnly == true,
		}
	elseif type(requestedContext) == "table" and requestedContext.mode == "wardrobe" then
		context = {
			mode = "wardrobe",
			title = tostring(requestedContext.title or "Organization Wardrobe"),
			categories = {},
			allowOutfits = true,
			outfitsOnly = true,
			expiresAt = os.clock() + 300,
		}
	end

	-- Start from what the character actually looks like right now (their real avatar on a
	-- fresh character, their saved look otherwise) so the editor never opens "blank".
	local current
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local ok, description = pcall(humanoid.GetAppliedDescription, humanoid)
		if ok and description then
			current = AppearanceService.Serialize(description)
		end
	end
	current = sanitizeAppearance(current or playerObj.PlayerData.appearance or {})

	session.editing = true
	session.original = deepCopy(current)
	session.pending = nil
	session.context = context
	if context.allowOutfits then
		context.outfits = outfitSummaries(playerObj)
	end

	Remotes.OpenAppearanceEditor:FireClient(player, current, isNewCharacter == true, context)
	return true
end

-- Live try-on while the editor is open. ApplyDescription yields while assets load, which
-- doubles as the rate limit: incoming payloads just overwrite `pending` and only the
-- latest one is applied when the previous apply finishes.
function AppearanceService.Preview(player, payload)
	local session = sessions[player.UserId]
	if not session or not session.editing then
		return
	end

	local clean = sessionContextAppearance(session, payload)
	if not clean then
		return
	end

	session.pending = clean
	if session.applying then
		return
	end

	session.applying = true
	task.spawn(function()
		while session.pending do
			local nextAppearance = session.pending
			session.pending = nil
			AppearanceService.ApplyToCharacter(player.Character, nextAppearance)
		end
		session.applying = false
	end)
end

function AppearanceService.CancelEdit(player, playerObj)
	local session = sessions[player.UserId]
	if not session or not session.editing then
		return
	end

	session.editing = false
	session.pending = nil
	session.context = nil

	local restore = (playerObj and playerObj.PlayerData.appearance) or session.original
	if restore then
		AppearanceService.ApplyToCharacter(player.Character, restore)
	end
end

function AppearanceService.SaveAppearance(player, playerObj, payload)
	local session = sessions[player.UserId]
	local accessOk, accessErr = validateSessionAccess(player, playerObj, session, false)
	if not accessOk then
		return false, accessErr
	end
	local context = type(session.context) == "table" and session.context or { mode = "full" }
	if context.outfitsOnly == true then
		-- Applying an outfit already persists immediately. "Done" only closes this
		-- session, so a modified client cannot submit identity/face/body fields here.
		session.editing = false
		session.pending = nil
		session.context = nil
		return true
	end

	local clean = sessionContextAppearance(session, payload)
	if not clean then
		return false, "Invalid appearance data."
	end

	if appearanceConfig().ValidateOwnership ~= false then
		local ok, badAssetId
		if context.mode == "shop" then
			ok, badAssetId = validateNewOwnership(player, session.original, clean)
		else
			ok, badAssetId = validateOwnership(player, clean)
		end
		if not ok then
			return false, ("You don't own one of those items (asset %d)."):format(badAssetId)
		end
	end

	local saved, saveErr = saveCurrentAppearance(player, playerObj, session, clean)
	if not saved then
		return false, saveErr
	end
	session.editing = false
	session.pending = nil
	session.context = nil

	return true
end

local function createClothingInteractions()
	local folder = Workspace:FindFirstChild(CLOTHING_FOLDER_NAME)
	if folder and not folder:IsA("Folder") then
		warn(("[QBCore.AppearanceService] Workspace.%s must be a Folder."):format(CLOTHING_FOLDER_NAME))
		return
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CLOTHING_FOLDER_NAME
		folder.Parent = Workspace
	end
	for index, shop in ipairs(clothingConfig().Shops or {}) do
		local position = shopPosition(shop)
		if position then
			local id = trim(shop.id)
			if id == "" then
				id = "clothing_shop_" .. index
			end
			local part = Instance.new("Part")
			part.Name = "Clothing_" .. id:gsub("[^%w_]", "_")
			part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
			part.CastShadow, part.Transparency, part.Size, part.Position = false, 1, Vector3.new(2, 2, 2), position
			part.Parent = folder
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "ClothingPrompt"
			prompt.ActionText = shop.outfitsOnly == true and "Change Outfit" or "Browse"
			prompt.ObjectText = tostring(shop.label or "Clothing Shop")
			prompt.KeyboardKeyCode, prompt.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
			prompt.HoldDuration = 0.15
			prompt.MaxActivationDistance = math.max(1, tonumber(clothingConfig().PromptDistance) or 10)
			prompt.RequiresLineOfSight = false
			prompt.Parent = part
			prompt.Triggered:Connect(function(player)
				local playerObj = playerService and playerService.GetPlayer(player.UserId)
				if not playerObj then
					return
				end
				local resolved, accessErr = resolveShop(player, id, playerObj)
				if not resolved then
					playerObj:Notify(accessErr or "You cannot use this clothing shop.", "error", 4000)
					return
				end
				AppearanceService.OpenEditor(player, playerObj, false, { mode = "shop", locationId = id })
			end)
		else
			warn(("[QBCore.AppearanceService] Clothing shop %d has no valid position."):format(index))
		end
	end
end

function AppearanceService.Start(service)
	if started then
		return
	end
	assert(
		type(service) == "table" and type(service.GetPlayer) == "function",
		"AppearanceService.Start requires PlayerService"
	)
	playerService = service
	started = true
	Remotes.OutfitAction.OnServerInvoke = function(player, action, payload)
		if clothingConfig().Enabled == false then
			return false, "Clothing shops are currently unavailable."
		end
		local playerObj = playerService.GetPlayer(player.UserId)
		if not playerObj then
			return false, "Load a character before managing outfits."
		end
		local now = os.clock()
		if now - (lastOutfitActionAt[player] or 0) < OUTFIT_ACTION_COOLDOWN then
			return false, "Please wait before submitting another outfit action."
		end
		lastOutfitActionAt[player] = now
		if outfitBusy[player] then
			return false, "Another outfit action is already running."
		end
		outfitBusy[player] = true
		local handlerOk, ok, result =
			pcall(handleOutfitAction, player, playerObj, type(action) == "string" and action:lower() or "", payload)
		outfitBusy[player] = nil
		if not handlerOk then
			warn(("[QBCore.AppearanceService] Outfit action failed for %s: %s"):format(player.Name, tostring(ok)))
			return false, "The outfit action could not be completed."
		end
		return ok, result
	end
	if clothingConfig().Enabled ~= false then
		createClothingInteractions()
	end
end

function AppearanceService.DeleteOutfitCodes(playerData)
	for _, outfit in
		ipairs(type(playerData) == "table" and type(playerData.outfits) == "table" and playerData.outfits or {})
	do
		if type(outfit) == "table" then
			revokeShareCode(outfit.code)
		end
	end
end

function AppearanceService.OnPlayerLeave(player)
	local session = sessions[player.UserId]
	if session and session.respawnConn then
		session.respawnConn:Disconnect()
	end
	sessions[player.UserId] = nil
	ownershipCache[player.UserId] = nil
	lastOutfitActionAt[player] = nil
	outfitBusy[player] = nil
end

return AppearanceService
