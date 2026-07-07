--[[
    Roblox replacement for oxmysql/MySQL.lua.

    This is a small, self-contained implementation of the "ProfileService/ProfileStore"
    session-locking pattern: each Roblox account gets exactly one DataStore key, a server
    claims a lock on it while the player is connected, autosaves periodically, and releases
    the lock (with a final save) on the way out. That lock is what stops two servers (e.g. a
    player rejoining while their old server hasn't finished saving yet) from writing over
    each other and duplicating/erasing data.

    For production, swapping in the battle-tested community ProfileStore module is a
    reasonable upgrade -- the API here (Reconcile/Save/Release) intentionally matches theirs.
]]

local DataStoreService = game:GetService("DataStoreService")

local SESSION_TIMEOUT = 35 -- seconds. Longer than the autosave interval below so a live session's lock never looks stale.
local AUTOSAVE_INTERVAL = 60 -- seconds
local MAX_CLAIM_RETRIES = 5

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Fills in any keys present in `defaults` but missing from `data`, recursively.
-- Mirrors server/player.lua's applyDefaults — used both for brand new saves and for
-- migrating older saves forward when you add new fields to CharacterDefaults later.
local function reconcile(data, defaults)
	for key, value in pairs(defaults) do
		if data[key] == nil then
			data[key] = deepCopy(value)
		elseif type(value) == "table" and type(data[key]) == "table" then
			reconcile(data[key], value)
		end
	end
	return data
end

local Profile = {}
Profile.__index = Profile

function Profile:Reconcile(defaults)
	reconcile(self.Data, defaults)
end

-- Writes the current in-memory Data to the DataStore immediately. Also called automatically
-- on the autosave interval and once more on :Release().
function Profile:Save()
	if not self.IsActive then
		return false
	end

	local ok, err = pcall(function()
		self._store:UpdateAsync(self._key, function(record)
			record = record or {}
			record.Data = self.Data
			record.MetaData = record.MetaData or {}
			record.MetaData.ActiveSession = { JobId = game.JobId, PlaceId = game.PlaceId }
			record.MetaData.LastUpdate = os.time()
			return record
		end)
	end)

	if not ok then
		warn(("[QBCore.ProfileStore] Save failed for %s: %s"):format(self._key, tostring(err)))
		return false
	end
	return true
end

-- Final save + releases the session lock so another server (character select after a
-- rejoin, or a new server the player teleports to) can claim this profile again.
-- Always call this from PlayerRemoving / BindToClose — never just drop the reference.
function Profile:Release()
	if not self.IsActive then
		return
	end
	self.IsActive = false

	if self._autosaveThread then
		task.cancel(self._autosaveThread)
		self._autosaveThread = nil
	end

	local ok, err = pcall(function()
		self._store:UpdateAsync(self._key, function(record)
			record = record or {}
			record.Data = self.Data
			record.MetaData = record.MetaData or {}
			-- Only clear the lock if we still own it — guards against clobbering a lock
			-- another server claimed after ours went stale.
			local session = record.MetaData.ActiveSession
			if not session or session.JobId == game.JobId then
				record.MetaData.ActiveSession = nil
			end
			record.MetaData.LastUpdate = os.time()
			return record
		end)
	end)

	if not ok then
		warn(("[QBCore.ProfileStore] Release save failed for %s: %s"):format(self._key, tostring(err)))
	end

	if self._onRelease then
		self._onRelease()
	end
end

local ProfileStore = {}
ProfileStore.__index = ProfileStore

-- Exposed so PlayerService can reconcile a single character's data against
-- CharacterDefaults without needing a full Profile wrapper around it.
ProfileStore.Reconcile = reconcile
ProfileStore.DeepCopy = deepCopy

function ProfileStore.new(name)
	return setmetatable({
		_store = DataStoreService:GetDataStore(name),
	}, ProfileStore)
end

-- Read-only peek at a record without claiming its session lock. Used for cross-account
-- lookups (e.g. GetOfflinePlayerByCitizenId) where the caller has no intention of saving.
function ProfileStore:PeekAsync(key)
	local ok, record = pcall(function()
		return self._store:GetAsync(key)
	end)
	if not ok or not record then
		return nil
	end
	return record.Data
end

--- Claims the session lock for `key`, creating a fresh record (seeded with `defaultData`) if
--- none exists yet. Returns nil, errorMessage if another server currently holds a live lock.
--- @param key string
--- @param defaultData table
function ProfileStore:StartSessionAsync(key, defaultData)
	for attempt = 1, MAX_CLAIM_RETRIES do
		local claimed, claimFailedReason = nil, nil

		local ok, err = pcall(function()
			self._store:UpdateAsync(key, function(record)
				local now = os.time()
				if record and record.MetaData and record.MetaData.ActiveSession then
					local session = record.MetaData.ActiveSession
					local isStale = (now - (record.MetaData.LastUpdate or 0)) > SESSION_TIMEOUT
					if session.JobId ~= game.JobId and not isStale then
						claimFailedReason = "session_locked"
						return nil -- abort the write; leave the existing lock alone
					end
				end

				record = record or { Data = deepCopy(defaultData), MetaData = {} }
				record.MetaData = record.MetaData or {}
				record.MetaData.ActiveSession = { JobId = game.JobId, PlaceId = game.PlaceId }
				record.MetaData.LastUpdate = now
				claimed = record
				return record
			end)
		end)

		if not ok then
			claimFailedReason = tostring(err)
		end

		if claimed then
			local profile = setmetatable({
				Data = deepCopy(claimed.Data),
				IsActive = true,
				_store = self._store,
				_key = key,
			}, Profile)

			profile._autosaveThread = task.spawn(function()
				while true do
					task.wait(AUTOSAVE_INTERVAL)
					profile:Save()
				end
			end)

			return profile
		end

		if claimFailedReason == "session_locked" then
			task.wait(6) -- give the other server's session a chance to time out / release
		else
			return nil, claimFailedReason
		end
	end

	return nil, "session_locked"
end

return ProfileStore
