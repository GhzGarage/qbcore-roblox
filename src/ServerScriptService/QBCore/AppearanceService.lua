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

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

function AppearanceService.OpenEditor(player, playerObj, isNewCharacter)
	local session = getSession(player.UserId)

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
	current = current or playerObj.PlayerData.appearance or sanitizeAppearance({})

	session.editing = true
	session.original = current
	session.pending = nil

	Remotes.OpenAppearanceEditor:FireClient(player, current, isNewCharacter == true)
end

-- Live try-on while the editor is open. ApplyDescription yields while assets load, which
-- doubles as the rate limit: incoming payloads just overwrite `pending` and only the
-- latest one is applied when the previous apply finishes.
function AppearanceService.Preview(player, payload)
	local session = sessions[player.UserId]
	if not session or not session.editing then
		return
	end

	local clean = sanitizeAppearance(payload)
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

	local restore = (playerObj and playerObj.PlayerData.appearance) or session.original
	if restore then
		AppearanceService.ApplyToCharacter(player.Character, restore)
	end
end

function AppearanceService.SaveAppearance(player, playerObj, payload)
	local session = sessions[player.UserId]
	if not session or not session.editing then
		return false, "The appearance editor is not open."
	end

	local clean = sanitizeAppearance(payload)
	if not clean then
		return false, "Invalid appearance data."
	end

	if appearanceConfig().ValidateOwnership ~= false then
		local ok, badAssetId = validateOwnership(player, clean)
		if not ok then
			return false, ("You don't own one of those items (asset %d)."):format(badAssetId)
		end
	end

	session.editing = false
	session.pending = nil

	playerObj:SetPlayerData("appearance", clean)
	playerObj:Save()
	AppearanceService.ApplyToCharacter(player.Character, clean)

	return true
end

function AppearanceService.OnPlayerLeave(player)
	local session = sessions[player.UserId]
	if session and session.respawnConn then
		session.respawnConn:Disconnect()
	end
	sessions[player.UserId] = nil
	ownershipCache[player.UserId] = nil
end

return AppearanceService
