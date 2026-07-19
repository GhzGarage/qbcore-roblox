-- qb-spawn-style selection shown after multicharacter chooses a citizen. The
-- server validates the destination before creating the Roblox character at all.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QBShared = require(ReplicatedStorage.QBShared.Main)
local Remotes = require(ReplicatedStorage.QBRemotes)

local SpawnService = {}

local playerService
local apartmentService
local onSpawnCompleted
local pending = {}
local started = false

local function config()
	return type(QBShared.Config.Spawn) == "table" and QBShared.Config.Spawn or {}
end

local function positionOf(entry)
	if type(entry) ~= "table" then
		return nil
	end
	if typeof(entry.position) == "Vector3" then
		return entry.position
	end
	local value = entry.position or entry
	if type(value) == "table" then
		local x, y, z = tonumber(value.x or value.X), tonumber(value.y or value.Y), tonumber(value.z or value.Z)
		if x and y and z then
			return Vector3.new(x, y, z)
		end
	end
	return nil
end

local function headingOf(entry)
	return tonumber(type(entry) == "table" and (entry.heading or entry.ry)) or 0
end

local function asPosition(position)
	return { x = position.X, y = position.Y, z = position.Z }
end

local function choiceFromLocation(location, index)
	local position = positionOf(location)
	if not position then
		return nil
	end
	local id = type(location.id) == "string" and location.id ~= "" and location.id or ("spawn_" .. index)
	return {
		id = "location:" .. id,
		kind = "location",
		label = tostring(location.label or id),
		description = tostring(location.description or "Spawn at this public location."),
		position = asPosition(position),
		heading = headingOf(location),
		serverPosition = position,
	}
end

local function publicChoice(choice)
	return {
		id = choice.id,
		kind = choice.kind,
		label = choice.label,
		description = choice.description,
		position = choice.position,
		heading = choice.heading,
	}
end

local function spawnCFrame(position, heading)
	return CFrame.new(position + Vector3.new(0, 3, 0)) * CFrame.Angles(0, math.rad(heading or 0), 0)
end

local function defaultChoice()
	local configured = type(config().DefaultSpawn) == "table" and config().DefaultSpawn or nil
	local legacyDefault = QBShared.Config.Player.CharacterDefaults.position
	local position = positionOf(configured) or positionOf(legacyDefault) or Vector3.new(0, 5, 0)
	return {
		id = "default_spawn",
		kind = "location",
		label = "Default Spawn",
		description = "Enter the city at the configured default location.",
		position = asPosition(position),
		heading = configured and headingOf(configured) or headingOf(legacyDefault),
		serverPosition = position,
	}
end

local function lastLocationChoice(playerObj)
	local saved = positionOf(playerObj.PlayerData.position)
	if not saved then
		return nil
	end
	return {
		id = "last_location",
		kind = "location",
		label = "Last Location",
		description = "Continue from the last saved outdoor location.",
		position = asPosition(saved),
		heading = headingOf(playerObj.PlayerData.position),
		serverPosition = saved,
	}
end

local function complete(player, selected)
	local session = pending[player]
	if not session then
		return false, "The spawn selection expired."
	end
	local playerObj = playerService.GetSelectedPlayer(player.UserId)
	if not playerObj or playerObj ~= session.playerObj then
		pending[player] = nil
		return false, "Character not loaded."
	end
	local choice = session.choices[selected]
	if not choice then
		return false, "Choose a valid spawn location."
	end
	local ok, preparedOrError
	local prepared
	local destination
	if choice.kind == "apartment" then
		local buildingId = choice.id:match("^apartment:(.+)$")
		ok, preparedOrError = apartmentService.PrepareStarterSpawn(player, playerObj, buildingId)
		if ok then
			prepared, destination = preparedOrError, preparedOrError.spawnCFrame
		end
	elseif choice.kind == "owned_apartment" then
		ok, preparedOrError = apartmentService.PrepareOwnedSpawn(player, playerObj)
		if ok then
			prepared, destination = preparedOrError, preparedOrError.spawnCFrame
		end
	else
		ok = choice.serverPosition ~= nil
		preparedOrError = ok and nil or "That spawn location is unavailable."
		if ok then
			destination = spawnCFrame(choice.serverPosition, choice.heading)
		end
	end
	if not ok then
		return false, preparedOrError
	end
	session.prepared = prepared

	-- The character does not exist before this line. Creating it is the final,
	-- server-authorized step after a spawn choice has been validated.
	playerObj._suppressPositionCapture = true
	local spawned, spawnErr = playerService.SpawnSelectedCharacter(player, playerObj, destination)
	if not spawned then
		if prepared then
			apartmentService.CancelPreparedSpawn(player, prepared)
		end
		session.prepared = nil
		return false, spawnErr
	end
	if prepared then
		local entered, enterErr = apartmentService.CompletePreparedSpawn(player, playerObj, prepared)
		if not entered then
			if player.Character then
				player.Character:Destroy()
			end
			apartmentService.CancelPreparedSpawn(player, prepared)
			session.prepared = nil
			return false, enterErr
		end
	else
		playerObj._suppressPositionCapture = false
		playerObj:CapturePosition()
		playerObj:Save()
	end
	local finalized, finalizeErr = playerService.FinalizeSelectedCharacter(player, playerObj)
	if not finalized then
		if player.Character then
			player.Character:Destroy()
		end
		if prepared then
			apartmentService.CancelPreparedSpawn(player, prepared)
		end
		session.prepared = nil
		return false, finalizeErr
	end
	session.prepared = nil
	pending[player] = nil
	if onSpawnCompleted then
		task.defer(onSpawnCompleted, player, playerObj)
	end
	return true
end

local function buildChoices(playerObj)
	local choices = {}
	local isNewCharacter = playerObj.PlayerData.appearance == nil
	local apartmentConfig = QBShared.Config.Apartments or {}
	local spawnUiEnabled = config().Enabled ~= false

	if isNewCharacter then
		if spawnUiEnabled and apartmentConfig.Enabled ~= false and apartmentConfig.Starting ~= false then
			for _, choice in ipairs(apartmentService.GetStartingChoices()) do
				local position = positionOf(choice.position)
				choice.serverPosition = position
				choices[choice.id] = choice
			end
			if next(choices) ~= nil then
				return choices, true, nil
			end
		end
		local fallback = defaultChoice()
		choices[fallback.id] = fallback
		return choices, true, fallback.id
	end

	local lastLocation = lastLocationChoice(playerObj) or defaultChoice()
	choices[lastLocation.id] = lastLocation
	if not spawnUiEnabled or config().AllowSelectionForExistingCharacters == false then
		return choices, false, lastLocation.id
	end

	local owned = apartmentConfig.Enabled ~= false and apartmentService.GetOwnedChoice(playerObj) or nil
	if owned then
		choices[owned.id] = owned
	end
	for index, location in ipairs(config().Locations or {}) do
		local choice = choiceFromLocation(location, index)
		if choice then
			choices[choice.id] = choice
		end
	end
	return choices, false, nil
end

function SpawnService.BeginSelection(player, playerObj)
	local choices, isNewCharacter, automaticChoiceId = buildChoices(playerObj)
	local list = {}
	for _, choice in pairs(choices) do
		list[#list + 1] = publicChoice(choice)
	end
	table.sort(list, function(a, b)
		if a.kind == b.kind then
			return string.lower(a.label) < string.lower(b.label)
		end
		if a.id == "last_location" then
			return true
		end
		if b.id == "last_location" then
			return false
		end
		return a.kind < b.kind
	end)
	pending[player] = { playerObj = playerObj, choices = choices }
	playerObj._suppressPositionCapture = true
	if automaticChoiceId then
		return complete(player, automaticChoiceId)
	end
	Remotes.OpenSpawnSelector:FireClient(player, {
		isNewCharacter = isNewCharacter,
		choices = list,
	})
	return true
end

function SpawnService.OnPlayerLeave(player)
	local session = pending[player]
	if session and session.prepared then
		apartmentService.CancelPreparedSpawn(player, session.prepared)
	end
	pending[player] = nil
end

function SpawnService.Start(players, apartments, completedCallback)
	if started then
		return
	end
	playerService, apartmentService, onSpawnCompleted = players, apartments, completedCallback
	assert(
		type(playerService) == "table" and type(playerService.GetSelectedPlayer) == "function",
		"SpawnService needs PlayerService"
	)
	assert(
		type(apartmentService) == "table" and type(apartmentService.GetStartingChoices) == "function",
		"SpawnService needs ApartmentService"
	)
	started = true
	Remotes.SelectSpawn.OnServerInvoke = function(player, choiceId)
		if type(choiceId) ~= "string" then
			return false, "Choose a valid spawn location."
		end
		local ok, result, err = pcall(complete, player, choiceId)
		if not ok then
			warn(("[QBCore.SpawnService] Selection failed for %s: %s"):format(player.Name, tostring(result)))
			local session = pending[player]
			if player.Character then
				player.Character:Destroy()
			end
			if session and session.prepared then
				apartmentService.CancelPreparedSpawn(player, session.prepared)
				session.prepared = nil
			end
			return false, "The spawn could not be completed."
		end
		return result, err
	end
end

return SpawnService
