--[[
    Roblox port of server/player.lua's login/logout/CheckPlayerData/Save/DeleteCharacter
    section plus the shared server getters that don't touch
    natives (GetPlayer, GetPlayerByCitizenId, GetPlayers, GetPlayersByJob, ...).

    Mapping from the original model to the Roblox one:
      - license (Rockstar identifier) -> player.UserId (authenticated by the platform,
        so the duplicate-license check has nothing to guard against here).
      - one `players` SQL row per citizenid -> one session-locked DataStore key per
        account ("Account_<UserId>") holding all of that account's characters.
      - offline lookups by citizenid -> a separate QBCore_CitizenIndex DataStore
        mapping citizenId -> UserId.

    qb-inventory hooks, qb-log webhooks, and the anti-cheat DropPlayer calls are not
    ported -- see TODO.md and the inline TODO markers.
]]

local DataStoreService = game:GetService("DataStoreService")
local Lighting = game:GetService("Lighting")
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

local function requireSiblingModule(name)
	local module = script.Parent:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		error(("QBCore setup error: %s must be a ModuleScript next to %s."):format(name, script:GetFullName()), 2)
	end
	return require(module)
end

local ProfileStore = requireSiblingModule("ProfileStore")
local PlayerClass = requireSiblingModule("PlayerClass")
local AppearanceService = requireSiblingModule("AppearanceService")
local InventoryService = requireSiblingModule("InventoryService")

local PROFILE_WAIT_TIMEOUT = 10
local SPAWN_HEIGHT_OFFSET = 6
local LEGACY_DEFAULT_SPAWN_POSITIONS = {
	{ x = 0, y = 145, z = 0 },
	{ x = 0, y = 5, z = 0 },
}

local accountStore = ProfileStore.new("QBCore_PlayerAccounts")
local citizenIndex = DataStoreService:GetDataStore("QBCore_CitizenIndex")

local PlayerService = {}

PlayerService.Players = {} -- [UserId] = Player instance (online only)
PlayerService.PlayersByCitizenId = {} -- [citizenId] = Player instance (online only)

local accountProfiles = {} -- [UserId] = Profile instance, held for the account's whole connection
local statusLoopStarted = false

local function getAccountProfile(player)
	local deadline = os.clock() + PROFILE_WAIT_TIMEOUT

	repeat
		local profile = accountProfiles[player.UserId]
		if profile then
			return profile
		end

		if not player.Parent then
			return nil
		end

		task.wait()
	until os.clock() >= deadline

	return accountProfiles[player.UserId]
end

local function defaultAccountData()
	return { characters = {}, nextCid = 1 }
end

local function getMaxCharacterSlots()
	return tonumber(QBShared.Config.Player.MaxCharacterSlots) or 5
end

local function generateCitizenId()
	for _ = 1, 100 do
		local candidate = string.upper(
			string.char(math.random(65, 90), math.random(65, 90), math.random(65, 90))
				.. tostring(math.random(10000, 99999))
		)
		local ok, existing = pcall(function()
			return citizenIndex:GetAsync(candidate)
		end)
		if ok and not existing then
			return candidate
		end
	end
	error("PlayerService.generateCitizenId: exceeded 100 retries")
end

local function buildCharacterDefaults(cid, displayName)
	local data = ProfileStore.DeepCopy(QBShared.Config.Player.CharacterDefaults)
	data.cid = cid
	data.name = displayName
	return data
end

local function applyCameraSettings(player)
	local camera = QBShared.Config.Player.Camera
	if type(camera) ~= "table" then
		return
	end

	local minZoom = tonumber(camera.MinZoomDistance)
	local maxZoom = tonumber(camera.MaxZoomDistance)

	if minZoom then
		player.CameraMinZoomDistance = math.max(0.5, minZoom)
	end

	if maxZoom then
		player.CameraMaxZoomDistance = math.max(player.CameraMinZoomDistance, maxZoom)
	end
end

-- ─────────────────────────── shared server getters ───────────────────────────

function PlayerService.GetPlayer(userId)
	return PlayerService.Players[userId]
end

function PlayerService.GetPlayerByCitizenId(citizenId)
	return PlayerService.PlayersByCitizenId[citizenId]
end

function PlayerService.GetPlayers()
	local list = {}
	for userId in pairs(PlayerService.Players) do
		list[#list + 1] = userId
	end
	return list
end

function PlayerService.GetPlayersByJob(job, checkOnDuty)
	local list, count = {}, 0
	for userId, player in pairs(PlayerService.Players) do
		local jobData = player.PlayerData.job
		if jobData.name == job or jobData.type == job then
			if not checkOnDuty or jobData.onduty then
				list[#list + 1] = userId
				count = count + 1
			end
		end
	end
	return list, count
end

function PlayerService.StartStatusLoop()
	if statusLoopStarted then
		return
	end
	statusLoopStarted = true

	task.spawn(function()
		while true do
			local config = QBShared.Config
			local decay = config.StatusDecay or {}
			local interval = tonumber(config.StatusInterval) or 5

			task.wait(math.max(1, interval))

			-- Keep PlayerData.position fresh while the character exists; leave-time
			-- saves can no longer read the Character (already destroyed by then).
			for _, playerObj in pairs(PlayerService.Players) do
				playerObj:CapturePosition()
			end

			if decay.Enabled ~= false then
				local hungerDecay = tonumber(decay.Hunger) or 0
				local thirstDecay = tonumber(decay.Thirst) or 0

				for _, playerObj in pairs(PlayerService.Players) do
					local hunger = tonumber(playerObj:GetMetaData("hunger")) or 100
					local thirst = tonumber(playerObj:GetMetaData("thirst")) or 100

					if hungerDecay ~= 0 then
						playerObj:SetMetaData("hunger", hunger - hungerDecay)
					end

					if thirstDecay ~= 0 then
						playerObj:SetMetaData("thirst", thirst - thirstDecay)
					end
				end
			end
		end
	end)
end

-- Cross-server / offline lookup. Not session-locked -- read-only, do not mutate the
-- returned table and expect it to persist; go through the online Player object for that.
function PlayerService.GetOfflinePlayerByCitizenId(citizenId)
	local ok, userId = pcall(function()
		return citizenIndex:GetAsync(citizenId)
	end)
	if not ok or not userId then
		return nil
	end

	local accountData = accountStore:PeekAsync("Account_" .. userId)
	if not accountData then
		return nil
	end

	local characterData = accountData.characters[citizenId]
	if not characterData then
		return nil
	end

	local copy = ProfileStore.DeepCopy(characterData)
	ProfileStore.Reconcile(copy, QBShared.Config.Player.CharacterDefaults)
	InventoryService.ReconcilePlayerData(copy)
	return PlayerClass.new(nil, copy, nil, nil)
end

-- ─────────────────────────── join / character select / leave ───────────────────────────

-- Claims the account profile; does NOT spawn a character (character select does that).
function PlayerService.OnPlayerJoin(player)
	applyCameraSettings(player)

	local profile, err = accountStore:StartSessionAsync("Account_" .. player.UserId, defaultAccountData())
	if not profile then
		warn(
			("[QBCore.PlayerService] Profile load failed for %s (%d): %s"):format(
				player.Name,
				player.UserId,
				tostring(err)
			)
		)
		player:Kick(("Could not load your data (%s). Please try rejoining."):format(tostring(err)))
		return
	end
	accountProfiles[player.UserId] = profile
end

function PlayerService.GetCharacterList(player)
	local profile = getAccountProfile(player)
	if not profile then
		warn(
			("[QBCore.PlayerService] Character list requested before profile loaded for %s (%d)"):format(
				player.Name,
				player.UserId
			)
		)
		return {}
	end

	local list = {}
	for citizenId, data in pairs(profile.Data.characters) do
		list[#list + 1] = {
			citizenId = citizenId,
			cid = data.cid,
			firstname = data.charinfo.firstname,
			lastname = data.charinfo.lastname,
			job = data.job.label,
			cash = data.money.cash,
			bank = data.money.bank,
		}
	end
	table.sort(list, function(a, b)
		return a.cid < b.cid
	end)
	return list
end

local function saveCallbackFor(player, citizenId)
	return function(playerData)
		local profile = accountProfiles[player.UserId]
		if not profile then
			return
		end
		profile.Data.characters[citizenId] = playerData
		profile:Save()
	end
end

-- Config.World key -> class of the effect instance kept under Lighting
local WORLD_EFFECT_CLASSES = {
	ColorCorrection = "ColorCorrectionEffect",
	Atmosphere = "Atmosphere",
	SunRays = "SunRaysEffect",
	Bloom = "BloomEffect",
	DepthOfField = "DepthOfFieldEffect",
}

local function applyWorldEffects(world)
	for configKey, className in pairs(WORLD_EFFECT_CLASSES) do
		local props = world[configKey]
		if type(props) == "table" then
			local effect = Lighting:FindFirstChildOfClass(className)
			if not effect then
				effect = Instance.new(className)
				effect.Name = "QB" .. className
				effect.Parent = Lighting
			end
			for name, value in pairs(props) do
				local ok, err = pcall(function()
					effect[name] = value
				end)
				if not ok then
					warn(("Config.World.%s.%s could not be applied: %s"):format(configKey, name, err))
				end
			end
		end
	end
end

local function setupSkyAndClouds(world)
	local skyCfg = world.Sky
	if type(skyCfg) == "table" then
		if skyCfg.Create ~= false then
			local sky = Lighting:FindFirstChildOfClass("Sky")
			if not sky then
				sky = Instance.new("Sky")
				sky.Name = "QBSky"
				sky.Parent = Lighting
			end
			-- Celestial numbers only; skybox textures are never touched, and the client
			-- TimeCycle driver owns SunAngularSize.
			sky.StarCount = tonumber(skyCfg.StarCount) or 3000
			sky.MoonAngularSize = tonumber(skyCfg.MoonAngularSize) or 11
		end
		if skyCfg.GeographicLatitude ~= nil then
			Lighting.GeographicLatitude = tonumber(skyCfg.GeographicLatitude) or 0
		end
	end

	local cover = tonumber(world.CloudCover) or 0
	local density = tonumber(world.CloudDensity) or 0
	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
	if not clouds and (cover > 0 or density > 0) then
		clouds = Instance.new("Clouds")
		clouds.Parent = Workspace.Terrain
	end
	if clouds then
		clouds.Cover = cover
		clouds.Density = density
	end
end

local function applyWorldEnvironment()
	local world = QBShared.Config.World
	if not world or world.ForceClearNoon == false then
		return
	end

	-- TimeSyncService owns the clock when enabled; resetting it here (this runs on
	-- every spawn) would snap the advancing time back.
	local timeSyncEnabled = type(world.Time) == "table" and world.Time.Enabled ~= false
	if not timeSyncEnabled then
		Lighting.ClockTime = tonumber(world.ClockTime) or 12
	end
	Lighting.Brightness = tonumber(world.Brightness) or 2.5
	Lighting.EnvironmentDiffuseScale = tonumber(world.EnvironmentDiffuseScale) or 1
	Lighting.EnvironmentSpecularScale = tonumber(world.EnvironmentSpecularScale) or 1
	Lighting.ShadowSoftness = tonumber(world.ShadowSoftness) or 0.2

	if typeof(world.Ambient) == "Color3" then
		Lighting.Ambient = world.Ambient
	end
	if typeof(world.OutdoorAmbient) == "Color3" then
		Lighting.OutdoorAmbient = world.OutdoorAmbient
	end

	applyWorldEffects(world)
	setupSkyAndClouds(world)
end

-- Run at boot so the Sky/Clouds/effect instances exist before any client's TimeCycle
-- driver looks for them; re-runs harmlessly on every character spawn.
PlayerService.ApplyWorldEnvironment = applyWorldEnvironment

local function matchesPosition(pos, other)
	return math.abs((pos.x or 0) - (other.x or 0)) < 0.01
		and math.abs((pos.y or 0) - (other.y or 0)) < 0.01
		and math.abs((pos.z or 0) - (other.z or 0)) < 0.01
end

local function isDefaultSpawnPosition(pos)
	local default = QBShared.Config.Player.CharacterDefaults.position
	if type(pos) ~= "table" or type(default) ~= "table" then
		return true
	end

	if matchesPosition(pos, default) then
		return true
	end

	for _, legacyDefault in ipairs(LEGACY_DEFAULT_SPAWN_POSITIONS) do
		if matchesPosition(pos, legacyDefault) then
			return true
		end
	end

	return false
end

local function cframeFromPosition(pos)
	pos = pos or QBShared.Config.Player.CharacterDefaults.position
	return CFrame.new(pos.x or 0, pos.y or SPAWN_HEIGHT_OFFSET, pos.z or 0) * CFrame.Angles(0, math.rad(pos.ry or 0), 0)
end

local function findSpawnLocation()
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("SpawnLocation") and descendant.Enabled then
			return descendant
		end
	end
	return nil
end

local function findLargestBasePart()
	local largestPart = nil
	local largestArea = 0

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("BasePart") and not descendant:IsA("SpawnLocation") then
			local area = descendant.Size.X * descendant.Size.Z
			if area > largestArea then
				largestArea = area
				largestPart = descendant
			end
		end
	end

	return largestPart
end

local function resolveSpawnCFrame(pos)
	if not isDefaultSpawnPosition(pos) then
		return cframeFromPosition(pos), "saved position"
	end

	local default = QBShared.Config.Player.CharacterDefaults.position
	if type(default) == "table" then
		return cframeFromPosition(default), "configured default spawn"
	end

	local spawnLocation = findSpawnLocation()
	if spawnLocation then
		return spawnLocation.CFrame + Vector3.new(0, SPAWN_HEIGHT_OFFSET, 0),
			"SpawnLocation " .. spawnLocation:GetFullName()
	end

	pos = pos or QBShared.Config.Player.CharacterDefaults.position
	local origin = Vector3.new(pos.x or 0, math.max((pos.y or 0) + 500, 500), pos.z or 0)
	local result = Workspace:Raycast(origin, Vector3.new(0, -1000, 0))
	if result then
		return CFrame.new(result.Position + Vector3.new(0, SPAWN_HEIGHT_OFFSET, 0)) * CFrame.Angles(
			0,
			math.rad(pos.ry or 0),
			0
		),
			"ground raycast"
	end

	local largestPart = findLargestBasePart()
	if largestPart then
		local spawnPosition = largestPart.Position + Vector3.new(0, largestPart.Size.Y / 2 + SPAWN_HEIGHT_OFFSET, 0)
		return CFrame.new(spawnPosition) * CFrame.Angles(0, math.rad(pos.ry or 0), 0),
			"largest part " .. largestPart:GetFullName()
	end

	local default = QBShared.Config.Player.CharacterDefaults.position
	return CFrame.new(default.x or 0, (default.y or 145) + SPAWN_HEIGHT_OFFSET, default.z or 0), "emergency fallback"
end

local function resolveRespawnCFrame()
	local medical = QBShared.Config.Medical or {}
	local respawn = type(medical.Respawn) == "table" and medical.Respawn or {}

	if respawn.UseConfiguredLocation == true and type(respawn.Location) == "table" then
		return cframeFromPosition(respawn.Location), "configured medical respawn"
	end

	return resolveSpawnCFrame(QBShared.Config.Player.CharacterDefaults.position)
end

local function hideSpawnForceFields(character)
	local function hideForceField(instance)
		if instance:IsA("ForceField") then
			instance.Visible = false
		end
	end

	for _, child in ipairs(character:GetChildren()) do
		hideForceField(child)
	end

	local connection
	connection = character.ChildAdded:Connect(hideForceField)
	task.delay(3, function()
		if connection then
			connection:Disconnect()
		end
	end)
end

local function loadCharacterIntoWorld(player, playerObj)
	local pos = playerObj.PlayerData.position
	local spawnCFrame, spawnReason = resolveSpawnCFrame(pos)
	print(("[QBCore.PlayerService] Spawning %s via %s"):format(player.Name, spawnReason))

	applyWorldEnvironment()
	player:LoadCharacter()
	local character = player.Character or player.CharacterAdded:Wait()
	hideSpawnForceFields(character)
	local root = character:WaitForChild("HumanoidRootPart")
	root.CFrame = spawnCFrame
end

function PlayerService.RespawnPlayer(player, playerObj, spawnCFrame, health)
	if not player or not playerObj then
		return false, "Character not loaded."
	end

	spawnCFrame = spawnCFrame or resolveRespawnCFrame()
	applyWorldEnvironment()
	player:LoadCharacter()

	local character = player.Character or player.CharacterAdded:Wait()
	hideSpawnForceFields(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)

	if not humanoid or not root then
		return false, "Respawn character did not finish loading."
	end

	root.CFrame = spawnCFrame
	humanoid.Health = math.clamp(tonumber(health) or humanoid.MaxHealth, 1, humanoid.MaxHealth)

	return true
end

function PlayerService.SelectCharacter(player, citizenId)
	local profile = getAccountProfile(player)
	if not profile then
		return false, "Your data is not loaded."
	end

	local stored = profile.Data.characters[citizenId]
	if not stored then
		return false, "Character not found."
	end

	ProfileStore.Reconcile(stored, QBShared.Config.Player.CharacterDefaults)
	InventoryService.ReconcilePlayerData(stored)
	stored.name = player.DisplayName

	local playerObj = PlayerClass.new(
		player,
		ProfileStore.DeepCopy(stored),
		saveCallbackFor(player, citizenId),
		function()
			PlayerService.Logout(player)
		end
	)

	PlayerService.Players[player.UserId] = playerObj
	PlayerService.PlayersByCitizenId[citizenId] = playerObj

	-- CharacterRemoving still has the intact character; this is the last reliable
	-- moment to record where the player was before a despawn/disconnect.
	playerObj._characterRemovingConn = player.CharacterRemoving:Connect(function(character)
		playerObj:CapturePosition(character)
	end)

	loadCharacterIntoWorld(player, playerObj)
	AppearanceService.OnCharacterSelected(player, playerObj)

	playerObj:UpdateClient()
	Remotes.PlayerLoaded:FireClient(player)
	playerObj:Notify(("Welcome, %s."):format(playerObj:GetName()), "success", 4000)

	-- First spawn on a fresh character: hand them the appearance editor. Fired after
	-- PlayerLoaded so the client's character-select UI is already gone when it opens.
	local appearanceConfig = QBShared.Config.Appearance
	if
		not playerObj.PlayerData.appearance
		and (not appearanceConfig or appearanceConfig.PromptNewCharacters ~= false)
	then
		AppearanceService.OpenEditor(player, playerObj, true)
	end

	return true
end

function PlayerService.CreateCharacter(player, firstname, lastname)
	local profile = getAccountProfile(player)
	if not profile then
		return nil, "Your data is not loaded."
	end

	local count = 0
	for _ in pairs(profile.Data.characters) do
		count = count + 1
	end
	if count >= getMaxCharacterSlots() then
		return nil, "You have reached the maximum number of characters."
	end

	if
		type(firstname) ~= "string"
		or type(lastname) ~= "string"
		or #firstname == 0
		or #lastname == 0
		or #firstname > 20
		or #lastname > 20
	then
		return nil, "Invalid name."
	end

	local citizenId = generateCitizenId()
	local cid = profile.Data.nextCid
	profile.Data.nextCid = cid + 1

	local data = buildCharacterDefaults(cid, player.DisplayName)
	data.charinfo.firstname = firstname
	data.charinfo.lastname = lastname
	InventoryService.SeedStarterItems(data)

	profile.Data.characters[citizenId] = data
	profile:Save()

	local ok = pcall(function()
		citizenIndex:SetAsync(citizenId, player.UserId)
	end)
	if not ok then
		warn("[QBCore.PlayerService] Failed to write citizen index for " .. citizenId)
	end

	return citizenId
end

function PlayerService.DeleteCharacter(player, citizenId)
	local profile = getAccountProfile(player)
	if not profile then
		return false, "Your data is not loaded."
	end
	if not profile.Data.characters[citizenId] then
		return false, "Character not found."
	end
	if PlayerService.PlayersByCitizenId[citizenId] then
		return false, "That character is currently loaded."
	end

	profile.Data.characters[citizenId] = nil
	profile:Save()

	pcall(function()
		citizenIndex:RemoveAsync(citizenId)
	end)

	-- TODO: delete rows in whatever other DataStores/tables track per-character data
	-- once you build them (houses, vehicles, phone contacts, bank accounts, ...) --
	-- mirrors the `playertables` sweep in the original QBCore.Player.DeleteCharacter.

	return true
end

-- Saves + unregisters the current character, then kicks the player so they can rejoin and
-- pick a different one. A no-rejoin "return to character select" flow (despawning the
-- character, resetting the camera/UI in place) is not implemented -- see TODO.md.
local function unregisterPlayer(player, playerObj)
	if playerObj._characterRemovingConn then
		playerObj._characterRemovingConn:Disconnect()
		playerObj._characterRemovingConn = nil
	end

	PlayerService.Players[player.UserId] = nil
	for citizenId, p in pairs(PlayerService.PlayersByCitizenId) do
		if p == playerObj then
			PlayerService.PlayersByCitizenId[citizenId] = nil
			break
		end
	end
end

function PlayerService.Logout(player)
	local playerObj = PlayerService.Players[player.UserId]
	if not playerObj then
		return
	end

	playerObj:Save()
	unregisterPlayer(player, playerObj)

	player:Kick("Rejoin to select a different character.")
end

function PlayerService.OnPlayerLeave(player)
	local playerObj = PlayerService.Players[player.UserId]
	if playerObj then
		playerObj:Save()
		unregisterPlayer(player, playerObj)
	end

	local profile = accountProfiles[player.UserId]
	if profile then
		profile:Release()
		accountProfiles[player.UserId] = nil
	end
end

-- Saves and releases every still-open session so a server shutdown never loses data.
function PlayerService.SaveAllAndRelease()
	for _, playerObj in pairs(PlayerService.Players) do
		playerObj:Save()
	end
	for _, profile in pairs(accountProfiles) do
		profile:Release()
	end
end

return PlayerService
