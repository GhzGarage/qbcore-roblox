--[[
    Roblox port of the join gate (closed-server check, whitelist, bans) and of ace
    permissions as graded ranks: Access.HasPermission is the shared permission
    equivalent, driven by Config.Server.PermissionRanks/Permissions.
    Per-command aces are not ported (rank tiers only), bans are UserId-only (Roblox
    exposes no IPs), and Ban/Whitelist/Unban are plain functions with no admin UI yet.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

local bansStore = DataStoreService:GetDataStore("QBCore_Bans")
local whitelistStore = DataStoreService:GetDataStore("QBCore_Whitelist")

local Access = {}

-- ─── graded permissions ───

local DEFAULT_RANKS = { "user", "mod", "admin", "god" }

local function getRanks()
	local ranks = QBShared.Config.Server.PermissionRanks
	return (type(ranks) == "table" and #ranks > 0) and ranks or DEFAULT_RANKS
end

local function rankIndex(rankName)
	for index, name in ipairs(getRanks()) do
		if name == rankName then
			return index
		end
	end
	return nil
end

-- Returns rankName, rankLevel (index into PermissionRanks).
function Access.GetRank(userId)
	local server = QBShared.Config.Server
	local ranks = getRanks()

	-- The experience owner is always top rank, like FiveM's console principal.
	if game.CreatorType == Enum.CreatorType.User and userId == game.CreatorId then
		return ranks[#ranks], #ranks
	end
	if RunService:IsStudio() and server.StudioTestersAreGod ~= false then
		return ranks[#ranks], #ranks
	end

	local highest = 1
	for index, name in ipairs(ranks) do
		local grants = type(server.Permissions) == "table" and server.Permissions[name]
		if type(grants) == "table" and grants[userId] == true and index > highest then
			highest = index
		end
	end

	-- Legacy Config.Server.Admins allowlist still counts as "admin".
	local adminIndex = rankIndex("admin")
	if adminIndex and adminIndex > highest and type(server.Admins) == "table" and server.Admins[userId] == true then
		highest = adminIndex
	end

	return ranks[highest], highest
end

-- minRank must be a name from PermissionRanks. True if the player's rank is at least that high.
function Access.HasPermission(userId, minRank)
	local needed = rankIndex(minRank)
	if not needed then
		warn(("[QBCore.Access] HasPermission called with unknown rank %q"):format(tostring(minRank)))
		return false
	end
	local _, level = Access.GetRank(userId)
	return level >= needed
end

function Access.IsAdmin(userId)
	return Access.HasPermission(userId, "admin")
end

-- expireAt: unix timestamp, or nil for a permanent ban
function Access.BanPlayer(userId, reason, expireAt)
	local ok, err = pcall(function()
		bansStore:SetAsync(tostring(userId), { reason = reason or "No reason specified", expireAt = expireAt })
	end)
	if not ok then
		warn(("[QBCore.Access] Failed to ban %d: %s"):format(userId, tostring(err)))
	end
	return ok
end

function Access.UnbanPlayer(userId)
	local ok = pcall(function()
		bansStore:RemoveAsync(tostring(userId))
	end)
	return ok
end

-- Returns isBanned: boolean, reason: string?
function Access.IsBanned(userId)
	local ok, record = pcall(function()
		return bansStore:GetAsync(tostring(userId))
	end)
	if not ok or not record then
		return false
	end

	if record.expireAt and os.time() >= record.expireAt then
		Access.UnbanPlayer(userId)
		return false
	end

	return true, record.reason
end

function Access.WhitelistPlayer(userId)
	local ok = pcall(function()
		whitelistStore:SetAsync(tostring(userId), true)
	end)
	return ok
end

function Access.UnwhitelistPlayer(userId)
	local ok = pcall(function()
		whitelistStore:RemoveAsync(tostring(userId))
	end)
	return ok
end

function Access.IsWhitelisted(userId)
	if Access.IsAdmin(userId) then
		return true
	end
	local ok, record = pcall(function()
		return whitelistStore:GetAsync(tostring(userId))
	end)
	return ok and record == true
end

-- Returns ok: boolean, kickReason: string?
function Access.CheckJoin(userId)
	local Config = QBShared.Config.Server

	if Config.Closed and not Access.IsAdmin(userId) then
		return false, Config.ClosedReason
	end

	local banned, reason = Access.IsBanned(userId)
	if banned then
		return false, "You are banned: " .. (reason or "No reason specified")
	end

	if Config.Whitelist and not Access.IsWhitelisted(userId) then
		return false, "This server is whitelisted and your account is not on the list."
	end

	return true
end

return Access
