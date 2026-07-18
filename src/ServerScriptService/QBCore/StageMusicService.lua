-- Server-owned stage speaker playback. Clients can ask for tracks by id only;
-- this service resolves the nearest registered station and controls the AudioPlayer.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.QBRemotes)
local StageMusic = require(ReplicatedStorage.QBShared.StageMusic)

local StageMusicService = {}

local PATH_TIMEOUT = 2

local stationStates = {}
local lastControlAt = {}
local lastSearchAt = {}
local searchCache = {}
local started = false

local function notify(player, text, notifyType, length)
	Remotes.Notify:FireClient(player, text, notifyType or "error", length or 4500)
end

local function trim(value)
	if type(value) ~= "string" then
		return ""
	end
	return value:match("^%s*(.-)%s*$") or ""
end

local function resolvePath(root, path, timeout)
	if typeof(root) ~= "Instance" or type(path) ~= "table" then
		return nil
	end

	local current = root
	for _, childName in ipairs(path) do
		if type(childName) ~= "string" or childName == "" then
			return nil
		end
		current = current:WaitForChild(childName, timeout or PATH_TIMEOUT)
		if not current then
			return nil
		end
	end

	return current
end

local function clampNumber(value, fallback, minValue, maxValue)
	value = tonumber(value)
	if not value then
		return fallback
	end
	return math.clamp(value, minValue, maxValue)
end

local function clampVolume(value)
	return clampNumber(value, StageMusic.Defaults.Volume, 0, StageMusic.Defaults.MaxVolume or 1)
end

local function setCurve(instance, methodName, curve)
	if typeof(instance) ~= "Instance" or type(curve) ~= "table" then
		return
	end

	pcall(function()
		instance[methodName](instance, curve)
	end)
end

local function getStationRoot(config)
	return resolvePath(workspace, config.speakerPath, PATH_TIMEOUT)
end

local function getPartFromRoot(root, relativePath)
	local part = resolvePath(root, relativePath, PATH_TIMEOUT)
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function getAudienceTarget(config, root, cabPart)
	if typeof(config.audienceTarget) == "Vector3" then
		return Vector3.new(config.audienceTarget.X, cabPart.Position.Y, config.audienceTarget.Z)
	end

	if type(config.audienceTargetPath) == "table" then
		local target = resolvePath(root, config.audienceTargetPath, 0.2)
		if target and target:IsA("BasePart") then
			return target.Position
		elseif target and target:IsA("Attachment") then
			return target.WorldPosition
		end
	end

	return nil
end

local function findExistingEmitter(cabPart, side)
	local preferredNames = {
		"QBStageMusic" .. side .. "Emitter",
		side .. "StageMusicEmitter",
		side .. "Emitter",
		"StageMusicEmitter",
	}

	for _, name in ipairs(preferredNames) do
		local found = cabPart:FindFirstChild(name, true)
		if found and found:IsA("AudioEmitter") then
			return found
		end
	end

	for _, descendant in ipairs(cabPart:GetDescendants()) do
		if descendant:IsA("AudioEmitter") then
			return descendant
		end
	end

	return nil
end

local function getOrCreateEmitter(config, root, cabPart, side)
	local emitter = findExistingEmitter(cabPart, side)
	if not emitter then
		local attachmentName = "QBStageMusic" .. side .. "Direction"
		local attachment = cabPart:FindFirstChild(attachmentName)
		if not attachment or not attachment:IsA("Attachment") then
			attachment = Instance.new("Attachment")
			attachment.Name = attachmentName
			attachment.Parent = cabPart
		end

		local target = getAudienceTarget(config, root, cabPart)
		attachment.WorldCFrame = target and CFrame.lookAt(cabPart.Position, target) or cabPart.CFrame

		emitter = Instance.new("AudioEmitter")
		emitter.Name = "QBStageMusic" .. side .. "Emitter"
		emitter.Parent = attachment
	end

	setCurve(emitter, "SetAngleAttenuation", config.angleAttenuation or StageMusic.Defaults.AngleAttenuation)
	setCurve(emitter, "SetDistanceAttenuation", config.distanceAttenuation or StageMusic.Defaults.DistanceAttenuation)

	return emitter
end

local function getOrCreateAudioPlayer(parent)
	local audioPlayer = parent:FindFirstChild("QBStageMusicPlayer")
	if not audioPlayer or not audioPlayer:IsA("AudioPlayer") then
		audioPlayer = Instance.new("AudioPlayer")
		audioPlayer.Name = "QBStageMusicPlayer"
		audioPlayer.Parent = parent
	end
	return audioPlayer
end

local function getInitialVolume(config)
	return clampVolume(config.volume or StageMusic.Defaults.Volume)
end

local function setStationVolume(state, volume)
	state.currentVolume = clampVolume(volume)
	state.audioPlayer.Volume = state.currentVolume
	return state.currentVolume
end

local function getOrCreateWire(audioPlayer, emitter, side)
	local wireName = "QBStageMusic" .. side .. "Wire"
	local wire = audioPlayer:FindFirstChild(wireName)
	if not wire or not wire:IsA("Wire") then
		wire = Instance.new("Wire")
		wire.Name = wireName
		wire.Parent = audioPlayer
	end

	wire.SourceInstance = audioPlayer
	wire.TargetInstance = emitter
	return wire
end

local function getInteractionPosition(config, root, leftPart, rightPart)
	if type(config.interactionPartPath) == "table" then
		local interactionPart = resolvePath(root, config.interactionPartPath, 0.2)
		if interactionPart and interactionPart:IsA("BasePart") then
			return interactionPart.Position
		elseif interactionPart and interactionPart:IsA("Attachment") then
			return interactionPart.WorldPosition
		end
	end

	return (leftPart.Position + rightPart.Position) / 2
end

local function buildStationState(config)
	if type(config) ~= "table" or type(config.id) ~= "string" then
		return nil, "Invalid stage music station config."
	end

	local root = getStationRoot(config)
	if not root then
		return nil, ("Could not find speaker root for %s."):format(config.id)
	end

	local leftPath = config.speakerParts and config.speakerParts.Left
	local rightPath = config.speakerParts and config.speakerParts.Right
	local leftPart = getPartFromRoot(root, leftPath)
	local rightPart = getPartFromRoot(root, rightPath)
	if not leftPart or not rightPart then
		return nil, ("Could not find Left/Right speaker cabinet parts for %s."):format(config.id)
	end

	local leftEmitter = getOrCreateEmitter(config, root, leftPart, "Left")
	local rightEmitter = getOrCreateEmitter(config, root, rightPart, "Right")
	local audioPlayer = getOrCreateAudioPlayer(root)

	getOrCreateWire(audioPlayer, leftEmitter, "Left")
	getOrCreateWire(audioPlayer, rightEmitter, "Right")

	local state = {
		config = config,
		root = root,
		leftPart = leftPart,
		rightPart = rightPart,
		audioPlayer = audioPlayer,
		origin = getInteractionPosition(config, root, leftPart, rightPart),
		currentVolume = getInitialVolume(config),
		currentTrackId = nil,
		currentTrackLabel = nil,
	}
	setStationVolume(state, state.currentVolume)

	pcall(function()
		state.endedConnection = audioPlayer.Ended:Connect(function()
			state.currentTrackId = nil
			state.currentTrackLabel = nil
		end)
	end)

	return state
end

local function getStationState(config)
	local cached = stationStates[config.id]
	if cached and cached.root and cached.root.Parent then
		cached.origin = getInteractionPosition(config, cached.root, cached.leftPart, cached.rightPart)
		return cached
	end

	local state, err = buildStationState(config)
	if not state then
		warn("[StageMusicService] " .. tostring(err))
		return nil, err
	end

	stationStates[config.id] = state
	return state
end

local function getCharacterRoot(player)
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

local function getMaxDistance(config)
	return tonumber(config.menuDistance) or StageMusic.Defaults.MenuDistance
end

local function distanceToStation(player, state)
	local root = getCharacterRoot(player)
	if not root then
		return nil
	end

	local distance = (root.Position - state.origin).Magnitude
	distance = math.min(distance, (root.Position - state.leftPart.Position).Magnitude)
	distance = math.min(distance, (root.Position - state.rightPart.Position).Magnitude)
	return distance
end

local function findClosestStation(player)
	local bestState = nil
	local bestDistance = math.huge
	local closestState = nil
	local closestDistance = math.huge
	local lastErr = nil

	for _, config in ipairs(StageMusic.Stations) do
		local state, err = getStationState(config)
		if state then
			local distance = distanceToStation(player, state)
			if distance then
				if distance < closestDistance then
					closestState = state
					closestDistance = distance
				end
				if distance <= getMaxDistance(config) and distance < bestDistance then
					bestState = state
					bestDistance = distance
				end
			end
		else
			lastErr = err
		end
	end

	if bestState then
		return bestState, bestDistance
	end

	if closestState then
		return nil, closestDistance, ("Move closer to %s to use the music menu."):format(closestState.config.label)
	end

	return nil, nil, lastErr or "No registered stage speakers are available."
end

local function findRequestedStation(player, stationId)
	if type(stationId) ~= "string" or stationId == "" then
		return findClosestStation(player)
	end

	local config = StageMusic.GetStationById(stationId)
	if not config then
		return nil, nil, "That music station is not registered."
	end

	local state, err = getStationState(config)
	if not state then
		return nil, nil, err or "That music station is not available."
	end

	local distance = distanceToStation(player, state)
	if not distance then
		return nil, nil, "Your character is not ready yet."
	end

	if distance > getMaxDistance(config) then
		return nil, distance, ("Move closer to %s to control the music."):format(config.label)
	end

	return state, distance
end

local function isAudioPlaying(audioPlayer)
	local ok, value = pcall(function()
		return audioPlayer.IsPlaying
	end)
	return ok and value == true
end

local function stationSnapshot(state, distance)
	return {
		id = state.config.id,
		label = state.config.label,
		distance = distance and math.floor(distance + 0.5) or nil,
		currentTrackId = state.currentTrackId,
		currentTrackLabel = state.currentTrackLabel,
		volume = state.currentVolume,
		isPlaying = isAudioPlaying(state.audioPlayer),
	}
end

local function passesCooldown(player)
	local now = os.clock()
	local cooldown = StageMusic.Defaults.Cooldown
	local last = lastControlAt[player.UserId]
	if last and now - last < cooldown then
		return false
	end
	lastControlAt[player.UserId] = now
	return true
end

local function playTrackDefinition(player, state, track)
	local assetId = StageMusic.NormalizeAssetId(track.assetId)
	if not assetId then
		notify(player, "That track is missing a valid Roblox audio asset id.")
		return
	end

	local audioPlayer = state.audioPlayer
	pcall(function()
		audioPlayer:Stop()
	end)

	local assetAssigned = pcall(function()
		audioPlayer.Asset = assetId
	end)
	if not assetAssigned then
		audioPlayer.AssetId = assetId
	end

	setStationVolume(state, state.currentVolume or track.volume or state.config.volume or StageMusic.Defaults.Volume)
	if track.looping ~= nil then
		audioPlayer.Looping = track.looping == true
	else
		audioPlayer.Looping = state.config.looping ~= false
	end
	pcall(function()
		audioPlayer.TimePosition = 0
	end)

	local ok, err = pcall(function()
		audioPlayer:Play()
	end)

	if not ok then
		warn(("[StageMusicService] Failed to play %s: %s"):format(tostring(track.id), tostring(err)))
		notify(player, "That track could not be played.")
		return
	end

	state.currentTrackId = track.id
	state.currentTrackLabel = track.label or track.id
	notify(player, ("Playing %s on %s."):format(state.currentTrackLabel, state.config.label), "success", 3500)
end

local function playTrack(player, state, trackId)
	local track = StageMusic.GetTrackById(trackId)
	if not track then
		notify(player, "That track is not configured.")
		return
	end

	playTrackDefinition(player, state, track)
end

local function stopTrack(player, state)
	pcall(function()
		state.audioPlayer:Stop()
	end)
	state.currentTrackId = nil
	state.currentTrackLabel = nil
	notify(player, ("Stopped music on %s."):format(state.config.label), "primary", 3000)
end

local function adjustVolume(player, state, delta)
	local step = tonumber(delta) or StageMusic.Defaults.VolumeStep
	local volume = setStationVolume(state, (state.currentVolume or StageMusic.Defaults.Volume) + step)
	notify(player, ("Stage volume: %d%%."):format(math.floor(volume * 100 + 0.5)), "primary", 1500)
end

local function makeSearchTrack(audio)
	if type(audio) ~= "table" then
		return nil
	end

	local assetId = tonumber(audio.Id)
	if not assetId then
		return nil
	end

	local title = trim(tostring(audio.Title or ""))
	if title == "" then
		title = "Audio " .. tostring(assetId)
	end

	local artist = trim(tostring(audio.Artist or ""))
	local duration = tonumber(audio.Duration)
	local description = ""
	if duration and duration > 0 then
		local minutes = math.floor(duration / 60)
		local seconds = math.floor(duration % 60)
		description = ("%d:%02d"):format(minutes, seconds)
	end

	return {
		id = "search_" .. tostring(assetId),
		searchId = assetId,
		label = title,
		artist = artist,
		description = description,
		assetId = "rbxassetid://" .. tostring(assetId),
		enabled = true,
	}
end

local function cacheSearchResults(player, stationId, query, tracks)
	local byId = {}
	for _, track in ipairs(tracks) do
		byId[track.searchId] = track
	end

	searchCache[player.UserId] = {
		stationId = stationId,
		query = query,
		results = tracks,
		expiresAt = os.clock() + StageMusic.Defaults.SearchCacheSeconds,
		resultsById = byId,
	}
end

local function getSearchCache(player, stationId)
	local cache = searchCache[player.UserId]
	if not cache or cache.expiresAt < os.clock() or cache.stationId ~= stationId then
		searchCache[player.UserId] = nil
		return nil
	end
	return cache
end

local function getCachedSearchTrack(player, stationId, searchId)
	local cache = getSearchCache(player, stationId)
	if not cache then
		return nil
	end

	return cache.resultsById[tonumber(searchId)]
end

local function getCachedSearchSnapshot(player, stationId)
	local cache = getSearchCache(player, stationId)
	if not cache then
		return nil
	end

	return {
		searchQuery = cache.query,
		searchResults = cache.results,
	}
end

local function searchAudio(query)
	local params = Instance.new("AudioSearchParams")
	params.SearchKeyword = query
	pcall(function()
		params.AudioSubType = Enum.AudioSubType.Music
	end)

	local ok, pagesOrErr = pcall(function()
		return AssetService:SearchAudioAsync(params)
	end)
	if not ok then
		return nil, tostring(pagesOrErr)
	end

	local tracks = {}
	local currentPage = pagesOrErr:GetCurrentPage()
	for _, audio in ipairs(currentPage) do
		local track = makeSearchTrack(audio)
		if track then
			tracks[#tracks + 1] = track
			if #tracks >= StageMusic.Defaults.SearchMaxResults then
				break
			end
		end
	end

	return tracks
end

local function openMenuSnapshot(player, state, distance, extra)
	local snapshot = stationSnapshot(state, distance)
	if type(extra) == "table" then
		for key, value in pairs(extra) do
			snapshot[key] = value
		end
	end

	Remotes.OpenStageMusicMenu:FireClient(player, snapshot)
end

function StageMusicService.OpenMenuFor(player)
	local state, distance, err = findClosestStation(player)
	if not state then
		notify(player, err or "No nearby stage speakers found.")
		return false
	end

	openMenuSnapshot(player, state, distance)
	return true
end

function StageMusicService.OpenSearchMenuFor(player, query)
	query = trim(query)
	if #query < 2 then
		notify(player, "Search needs at least two characters.")
		return false
	end

	local state, distance, err = findClosestStation(player)
	if not state then
		notify(player, err or "No nearby stage speakers found.")
		return false
	end

	local now = os.clock()
	local last = lastSearchAt[player.UserId]
	if last and now - last < StageMusic.Defaults.SearchCooldown then
		notify(player, "Wait a moment before searching again.", "primary", 1500)
		return false
	end
	lastSearchAt[player.UserId] = now

	local tracks, searchErr = searchAudio(query)
	if not tracks then
		warn("[StageMusicService] Audio search failed: " .. tostring(searchErr))
		notify(player, "Creator Store search failed. Try another query in a moment.")
		return false
	end

	cacheSearchResults(player, state.config.id, query, tracks)
	openMenuSnapshot(player, state, distance, {
		searchQuery = query,
		searchResults = tracks,
	})
	return true
end

function StageMusicService.Start()
	if started then
		return
	end
	started = true

	Remotes.StageMusicControl.OnServerEvent:Connect(function(player, payload)
		if type(payload) ~= "table" then
			return
		end
		if not passesCooldown(player) then
			return
		end

		local state, distance, err = findRequestedStation(player, payload.stationId)
		if not state then
			notify(player, err or "No nearby stage speakers found.")
			return
		end

		local action = tostring(payload.action or ""):lower()
		if action == "play" then
			playTrack(player, state, payload.trackId or payload.track)
		elseif action == "play_search" then
			local track = getCachedSearchTrack(player, state.config.id, payload.searchId)
			if not track then
				notify(player, "Search result expired. Search again to play it.")
				return
			end
			playTrackDefinition(player, state, track)
		elseif action == "stop" then
			stopTrack(player, state)
			openMenuSnapshot(
				player,
				state,
				distance,
				payload.keepSearch and getCachedSearchSnapshot(player, state.config.id) or nil
			)
		elseif action == "volume_up" then
			adjustVolume(player, state, StageMusic.Defaults.VolumeStep)
			openMenuSnapshot(
				player,
				state,
				distance,
				payload.keepSearch and getCachedSearchSnapshot(player, state.config.id) or nil
			)
		elseif action == "volume_down" then
			adjustVolume(player, state, -StageMusic.Defaults.VolumeStep)
			openMenuSnapshot(
				player,
				state,
				distance,
				payload.keepSearch and getCachedSearchSnapshot(player, state.config.id) or nil
			)
		else
			notify(player, "Unknown music action.")
		end
	end)
end

return StageMusicService
