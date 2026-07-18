-- Server-authoritative first pass of a QBCore-style admin menu.
-- The client asks for context/actions; this module checks permissions and mutates data.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QBShared = require(ReplicatedStorage.QBShared.Main)
local Remotes = require(ReplicatedStorage.QBRemotes)

local Access = require(script.Parent.Access)
local PlayerService = require(script.Parent.PlayerService)
local TimeSyncService = require(script.Parent.TimeSyncService)
local VehicleService = require(script.Parent.VehicleService)
local WeatherService = require(script.Parent.WeatherService)

local AdminService = {}

local MIN_MENU_RANK = "admin"
local MAX_LOGS = 100

local logs = {}
local nextLogId = 0

local function trim(text)
	if type(text) ~= "string" then
		return ""
	end
	return text:match("^%s*(.-)%s*$") or ""
end

local function clampText(text, maxLength)
	text = trim(text)
	if #text > maxLength then
		return text:sub(1, maxLength)
	end
	return text
end

local function lowerText(text)
	text = trim(text)
	if text == "" then
		return ""
	end
	return text:lower()
end

local function notify(player, text, notifyType)
	Remotes.Notify:FireClient(player, text, notifyType or "primary", 3500)
end

local function getCharacterRoot(player)
	local character = player and player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

local function healRobloxCharacter(player)
	local character = player and player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	humanoid.Health = humanoid.MaxHealth
	return true
end

local function replenishMetadata(playerObj)
	playerObj:SetMetaData("hunger", 100)
	playerObj:SetMetaData("thirst", 100)
	playerObj:SetMetaData("stress", 0)
	playerObj:SetMetaData("armor", 100)
	playerObj:SetMetaData("isdead", false)
end

local function setCharacterArmor(player, amount)
	local humanoid = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:SetAttribute("Armor", amount)
	end
end

local function findCitizenIdFor(playerObj)
	for citizenId, candidate in pairs(PlayerService.PlayersByCitizenId) do
		if candidate == playerObj then
			return citizenId
		end
	end
	return nil
end

local function formatMoney(value)
	value = math.floor(tonumber(value) or 0)
	local formatted = tostring(value)
	while true do
		local nextFormatted, replacements = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = nextFormatted
		if replacements == 0 then
			break
		end
	end
	return "$" .. formatted
end

local function copyMoney(money)
	money = type(money) == "table" and money or {}
	return {
		cash = tonumber(money.cash) or 0,
		bank = tonumber(money.bank) or 0,
		crypto = tonumber(money.crypto) or 0,
	}
end

local function copyMetadata(metadata)
	metadata = type(metadata) == "table" and metadata or {}
	return {
		hunger = tonumber(metadata.hunger) or 0,
		thirst = tonumber(metadata.thirst) or 0,
		stress = tonumber(metadata.stress) or 0,
		armor = tonumber(metadata.armor) or 0,
		isdead = metadata.isdead == true,
	}
end

local function serializePlayer(userId, playerObj)
	local robloxPlayer = Players:GetPlayerByUserId(userId)
	local data = playerObj.PlayerData or {}
	local job = type(data.job) == "table" and data.job or {}
	local crew = type(data.crew) == "table" and data.crew or {}
	local charinfo = type(data.charinfo) == "table" and data.charinfo or {}

	local characterName = tostring(data.name or (robloxPlayer and robloxPlayer.DisplayName) or userId)
	if type(charinfo.firstname) == "string" and type(charinfo.lastname) == "string" then
		characterName = ("%s %s"):format(charinfo.firstname, charinfo.lastname)
	end

	local jobGrade = type(job.grade) == "table" and job.grade or {}
	local crewGrade = type(crew.grade) == "table" and crew.grade or {}

	return {
		userId = userId,
		name = robloxPlayer and robloxPlayer.Name or tostring(userId),
		displayName = robloxPlayer and robloxPlayer.DisplayName or tostring(userId),
		character = characterName,
		citizenId = findCitizenIdFor(playerObj),
		cid = data.cid,
		job = {
			name = job.name or "unemployed",
			label = job.label or job.name or "Unemployed",
			gradeName = jobGrade.name or "0",
			gradeLevel = tonumber(jobGrade.level) or 0,
			onduty = job.onduty == true,
		},
		crew = {
			name = crew.name or "none",
			label = crew.label or crew.name or "None",
			gradeName = crewGrade.name or "0",
			gradeLevel = tonumber(crewGrade.level) or 0,
		},
		money = copyMoney(data.money),
		moneyText = {
			cash = formatMoney(data.money and data.money.cash),
			bank = formatMoney(data.money and data.money.bank),
			crypto = formatMoney(data.money and data.money.crypto),
		},
		metadata = copyMetadata(data.metadata),
	}
end

local function serializeItems()
	local items = {}
	for key, item in pairs(QBShared.Items or {}) do
		items[#items + 1] = {
			name = item.name or key,
			label = item.label or item.name or key,
			weight = tonumber(item.weight) or 0,
			type = item.type or "item",
			image = item.image or "",
			unique = item.unique == true,
			useable = item.useable == true,
			description = item.description or "",
		}
	end
	table.sort(items, function(left, right)
		return left.label:lower() < right.label:lower()
	end)
	return items
end

local function serializeJobGrades(grades)
	local list = {}
	for grade, info in pairs(type(grades) == "table" and grades or {}) do
		list[#list + 1] = {
			grade = tostring(grade),
			level = tonumber(grade) or 0,
			name = info.name or tostring(grade),
			payment = tonumber(info.payment) or 0,
			isboss = info.isboss == true,
		}
	end
	table.sort(list, function(left, right)
		return left.level < right.level
	end)
	return list
end

local function serializeJobs()
	local jobs = {}
	for name, job in pairs(QBShared.Jobs or {}) do
		jobs[#jobs + 1] = {
			name = name,
			label = job.label or name,
			type = job.type or "none",
			defaultDuty = job.defaultDuty == true,
			grades = serializeJobGrades(job.grades),
		}
	end
	table.sort(jobs, function(left, right)
		return left.label:lower() < right.label:lower()
	end)
	return jobs
end

local function serializeCrews()
	local crews = {}
	for name, crew in pairs(QBShared.Crews or {}) do
		crews[#crews + 1] = {
			name = name,
			label = crew.label or name,
			colors = type(crew.colors) == "table" and crew.colors or {},
			description = crew.description or "",
			grades = serializeJobGrades(crew.grades),
		}
	end
	table.sort(crews, function(left, right)
		return left.label:lower() < right.label:lower()
	end)
	return crews
end

local function serializeVehicles()
	local vehicles = {}
	for name, vehicle in pairs(QBShared.Vehicles or {}) do
		vehicles[#vehicles + 1] = {
			name = vehicle.name or name,
			label = vehicle.label or vehicle.name or name,
			brand = vehicle.brand or "",
			modelName = vehicle.modelName or vehicle.name or name,
			category = vehicle.category or "vehicle",
			assetId = vehicle.assetId,
			fuel = tonumber(vehicle.fuel) or 100,
			trunkSlots = tonumber(vehicle.trunkSlots) or 0,
			trunkWeight = tonumber(vehicle.trunkWeight) or 0,
			description = vehicle.description or "",
		}
	end
	table.sort(vehicles, function(left, right)
		return left.label:lower() < right.label:lower()
	end)
	return vehicles
end

local function copyLogs()
	local out = {}
	for index, entry in ipairs(logs) do
		out[index] = entry
	end
	return out
end

local function serializeWeather()
	local weatherState = WeatherService.GetState()
	local presets = weatherState.presets or WeatherService.GetPresetList()
	return {
		currentWeather = weatherState.currentWeather,
		nextWeather = weatherState.nextWeather,
		transitionDuration = weatherState.transitionDuration,
		frozen = weatherState.frozen == true,
		dynamic = weatherState.dynamic == true,
		blackout = weatherState.blackout == true,
		presets = presets,
	}
end

local function pushLog(actor, action, target, details)
	nextLogId += 1
	local entry = {
		id = nextLogId,
		time = os.time(),
		timeText = os.date("%H:%M:%S"),
		actor = actor.DisplayName,
		actorName = actor.Name,
		actorUserId = actor.UserId,
		action = action,
		target = target or "",
		details = details or "",
	}
	table.insert(logs, 1, entry)
	while #logs > MAX_LOGS do
		table.remove(logs)
	end
end

local function targetFromPayload(payload)
	local userId = nil
	if type(payload) == "table" then
		userId = tonumber(payload.userId)
	end
	if not userId then
		return nil, nil, "Select a player first."
	end

	local playerObj = PlayerService.GetPlayer(userId)
	local robloxPlayer = Players:GetPlayerByUserId(userId)
	if not playerObj or not robloxPlayer then
		return nil, nil, "That player does not have a loaded character."
	end

	return playerObj, robloxPlayer
end

local function result(actor, message)
	return true, {
		message = message,
		context = AdminService.GetContext(actor),
	}
end

local function deny(message)
	return false, message or "You do not have permission."
end

local function setTime(payload)
	local hour = tonumber(payload.hour)
	local minute = tonumber(payload.minute) or 0
	if not hour then
		return false, "Enter a valid hour."
	end

	hour = math.floor(hour)
	minute = math.floor(minute)
	if hour < 0 or hour > 23 or minute < 0 or minute > 59 then
		return false, "Time must be between 00:00 and 23:59."
	end

	if not TimeSyncService.SetTime(hour, minute) then
		return false, "Time could not be changed."
	end

	return true, ("%02d:%02d"):format(hour, minute)
end

local function isFiniteNumber(value)
	value = tonumber(value)
	return value ~= nil and value == value and math.abs(value) <= 1000000
end

local function parseCoordinateText(text)
	if type(text) ~= "string" then
		return nil
	end

	local normalized = text:gsub("[^%d%+%-%.]+", " ")
	local numbers = {}
	for token in normalized:gmatch("%S+") do
		local value = tonumber(token)
		if value then
			numbers[#numbers + 1] = value
		end
	end

	if #numbers < 3 then
		return nil
	end

	return numbers[1], numbers[2], numbers[3], numbers[4]
end

local function parseTeleportCoordinates(payload)
	payload = type(payload) == "table" and payload or {}

	local x = tonumber(payload.x)
	local y = tonumber(payload.y)
	local z = tonumber(payload.z)
	local heading = tonumber(payload.heading or payload.ry)

	if not (x and y and z) then
		x, y, z, heading = parseCoordinateText(payload.coords or payload.coordinates or payload.position)
	end

	if not (isFiniteNumber(x) and isFiniteNumber(y) and isFiniteNumber(z)) then
		return nil, "Enter coordinates like 100,100,100."
	end
	if heading ~= nil and not isFiniteNumber(heading) then
		return nil, "Heading must be a valid number."
	end

	return {
		x = x,
		y = y,
		z = z,
		heading = heading,
	}
end

local ACTIONS = {}

function ACTIONS.selfHeal(actor, payload)
	local playerObj = PlayerService.GetPlayer(actor.UserId)
	if not playerObj then
		return false, "Your character is not loaded."
	end

	healRobloxCharacter(actor)
	replenishMetadata(playerObj)
	setCharacterArmor(actor, 100)
	pushLog(actor, "selfHeal", actor.DisplayName, "Self heal")
	notify(actor, "You were healed.", "success")
	return result(actor, "You were healed.")
end

function ACTIONS.announce(actor, payload)
	local message = clampText(payload.message, 180)
	if message == "" then
		return false, "Enter an announcement message."
	end

	Remotes.Notify:FireAllClients(message, "primary", 7000)
	pushLog(actor, "announce", "Server", message)
	return result(actor, "Announcement sent.")
end

function ACTIONS.setTime(actor, payload)
	local ok, valueOrErr = setTime(payload)
	if not ok then
		return false, valueOrErr
	end

	pushLog(actor, "setTime", "World", valueOrErr)
	Remotes.Notify:FireAllClients("Time changed to " .. valueOrErr .. ".", "primary", 3000)
	return result(actor, "Time changed to " .. valueOrErr .. ".")
end

function ACTIONS.toggleFreezeTime(actor, payload)
	local nextState = not TimeSyncService.IsFrozen()
	TimeSyncService.SetFreeze(nextState)
	pushLog(actor, "freezeTime", "World", nextState and "Frozen" or "Running")
	return result(actor, nextState and "Time frozen." or "Time resumed.")
end

function ACTIONS.setWeather(actor, payload)
	local weatherName = lowerText(payload.weatherName or payload.weather)
	if weatherName == "" then
		return false, "Enter a weather type."
	end

	local ok, message = WeatherService.SetWeather(weatherName)
	if not ok then
		return false, message
	end

	pushLog(actor, "setWeather", "World", weatherName)
	Remotes.Notify:FireAllClients(message, "primary", 3000)
	return result(actor, message)
end

function ACTIONS.toggleFreezeWeather(actor, payload)
	local frozen = WeatherService.SetFrozen(not WeatherService.IsFrozen())
	pushLog(actor, "freezeWeather", "World", frozen and "Frozen" or "Running")
	return result(actor, frozen and "Weather cycling frozen." or "Weather cycling resumed.")
end

function ACTIONS.toggleBlackout(actor, payload)
	local blackout = WeatherService.SetBlackout(not WeatherService.IsBlackout())
	pushLog(actor, "blackout", "World", blackout and "Enabled" or "Disabled")
	Remotes.Notify:FireAllClients(blackout and "Blackout enabled." or "Blackout disabled.", "primary", 3000)
	return result(actor, blackout and "Blackout enabled." or "Blackout disabled.")
end

function ACTIONS.gotoPlayer(actor, payload)
	local _, targetPlayer, err = targetFromPayload(payload)
	if not targetPlayer then
		return false, err
	end

	local actorRoot = getCharacterRoot(actor)
	local targetRoot = getCharacterRoot(targetPlayer)
	if not actorRoot or not targetRoot then
		return false, "Both characters need to be spawned."
	end

	actorRoot.CFrame = targetRoot.CFrame + Vector3.new(4, 0, 0)
	pushLog(actor, "goto", targetPlayer.DisplayName, tostring(targetPlayer.UserId))
	return result(actor, "Teleported to " .. targetPlayer.DisplayName .. ".")
end

function ACTIONS.bringPlayer(actor, payload)
	local _, targetPlayer, err = targetFromPayload(payload)
	if not targetPlayer then
		return false, err
	end

	local actorRoot = getCharacterRoot(actor)
	local targetRoot = getCharacterRoot(targetPlayer)
	if not actorRoot or not targetRoot then
		return false, "Both characters need to be spawned."
	end

	targetRoot.CFrame = actorRoot.CFrame + Vector3.new(4, 0, 0)
	pushLog(actor, "bring", targetPlayer.DisplayName, tostring(targetPlayer.UserId))
	return result(actor, "Brought " .. targetPlayer.DisplayName .. ".")
end

function ACTIONS.teleportToCoords(actor, payload)
	local playerObj = PlayerService.GetPlayer(actor.UserId)
	if not playerObj then
		return false, "Your character is not loaded."
	end

	local coords, err = parseTeleportCoordinates(payload)
	if not coords then
		return false, err
	end

	local root = getCharacterRoot(actor)
	if not root then
		return false, "Your character needs to be spawned."
	end

	local _, currentYaw = root.CFrame:ToOrientation()
	local heading = coords.heading ~= nil and math.rad(coords.heading) or currentYaw
	root.CFrame = CFrame.new(coords.x, coords.y, coords.z) * CFrame.Angles(0, heading, 0)

	pushLog(actor, "teleportCoords", actor.DisplayName, ("%.2f, %.2f, %.2f"):format(coords.x, coords.y, coords.z))
	return result(actor, "Teleported to coordinates.")
end

function ACTIONS.healPlayer(actor, payload)
	local targetObj, targetPlayer, err = targetFromPayload(payload)
	if not targetObj then
		return false, err
	end

	healRobloxCharacter(targetPlayer)
	replenishMetadata(targetObj)
	setCharacterArmor(targetPlayer, 100)
	targetObj:Notify("You were healed by an admin.", "success", 3500)
	pushLog(actor, "heal", targetPlayer.DisplayName, tostring(targetPlayer.UserId))
	return result(actor, "Healed " .. targetPlayer.DisplayName .. ".")
end

function ACTIONS.kickPlayer(actor, payload)
	local _, targetPlayer, err = targetFromPayload(payload)
	if not targetPlayer then
		return false, err
	end
	if targetPlayer == actor then
		return false, "You cannot kick yourself from the admin menu."
	end

	local reason = clampText(payload.reason, 120)
	if reason == "" then
		reason = "Kicked by admin."
	end

	pushLog(actor, "kick", targetPlayer.DisplayName, reason)
	targetPlayer:Kick(reason)
	return result(actor, "Kicked " .. targetPlayer.DisplayName .. ".")
end

function ACTIONS.banPlayer(actor, payload)
	local _, targetPlayer, err = targetFromPayload(payload)
	if not targetPlayer then
		return false, err
	end
	if targetPlayer == actor then
		return false, "You cannot ban yourself from the admin menu."
	end

	local reason = clampText(payload.reason, 120)
	if reason == "" then
		reason = "Banned by admin."
	end

	local durationHours = tonumber(payload.durationHours)
	local expireAt = nil
	if durationHours and durationHours > 0 then
		expireAt = os.time() + math.floor(durationHours * 3600)
	end

	if not Access.BanPlayer(targetPlayer.UserId, reason, expireAt) then
		return false, "Ban could not be saved."
	end

	pushLog(actor, "ban", targetPlayer.DisplayName, reason)
	targetPlayer:Kick("You are banned: " .. reason)
	return result(actor, "Banned " .. targetPlayer.DisplayName .. ".")
end

function ACTIONS.addMoney(actor, payload)
	local targetObj, targetPlayer, err = targetFromPayload(payload)
	if not targetObj then
		return false, err
	end

	local moneyType = lowerText(payload.moneyType)
	local amount = math.floor(tonumber(payload.amount) or 0)
	if amount <= 0 then
		return false, "Enter a positive amount."
	end

	if not targetObj:AddMoney(moneyType, amount, "admin-menu") then
		return false, "Money type is invalid."
	end

	pushLog(actor, "addMoney", targetPlayer.DisplayName, ("%s +%d"):format(moneyType, amount))
	return result(actor, ("Added %s to %s."):format(formatMoney(amount), targetPlayer.DisplayName))
end

function ACTIONS.setMoney(actor, payload)
	local targetObj, targetPlayer, err = targetFromPayload(payload)
	if not targetObj then
		return false, err
	end

	local moneyType = lowerText(payload.moneyType)
	local amount = math.floor(tonumber(payload.amount) or -1)
	if amount < 0 then
		return false, "Enter a zero or positive amount."
	end

	if not targetObj:SetMoney(moneyType, amount, "admin-menu") then
		return false, "Money type is invalid."
	end

	pushLog(actor, "setMoney", targetPlayer.DisplayName, ("%s = %d"):format(moneyType, amount))
	return result(actor, ("Set %s %s to %s."):format(targetPlayer.DisplayName, moneyType, formatMoney(amount)))
end

function ACTIONS.giveItem(actor, payload)
	local targetObj, targetPlayer, err = targetFromPayload(payload)
	if not targetObj then
		return false, err
	end

	local itemName = lowerText(payload.itemName)
	local amount = math.floor(tonumber(payload.amount) or 1)
	if itemName == "" then
		return false, "Enter an item name."
	end
	if amount <= 0 then
		return false, "Enter a positive amount."
	end

	local ok, addErr = targetObj:AddItem(itemName, amount, nil, nil, "admin-menu")
	if not ok then
		return false, addErr or "Item could not be given."
	end

	pushLog(actor, "giveItem", targetPlayer.DisplayName, ("%s x%d"):format(itemName, amount))
	return result(actor, ("Gave %s x%d."):format(itemName, amount))
end

function ACTIONS.spawnVehicle(actor, payload)
	local playerObj = PlayerService.GetPlayer(actor.UserId)
	if not playerObj then
		return false, "Your character is not loaded."
	end

	local vehicleName = lowerText(payload.vehicleName or payload.name)
	if vehicleName == "" then
		return false, "Enter a vehicle name."
	end

	local vehicle, definitionOrErr, plate = VehicleService.SpawnVehicle(actor, vehicleName, {
		ignoreRestrictions = true,
	})
	if not vehicle then
		return false, definitionOrErr or "Vehicle could not be spawned."
	end

	local label = definitionOrErr.label or definitionOrErr.name
	pushLog(actor, "spawnVehicle", label, plate)
	notify(actor, ("Spawned %s (%s)."):format(label, plate), "success")
	return result(actor, ("Spawned %s."):format(label))
end

function ACTIONS.setJob(actor, payload)
	local targetObj, targetPlayer, err = targetFromPayload(payload)
	if not targetObj then
		return false, err
	end

	local jobName = lowerText(payload.jobName)
	local grade = tostring(math.floor(tonumber(payload.grade) or 0))
	if jobName == "" then
		return false, "Enter a job name."
	end

	if not targetObj:SetJob(jobName, grade) then
		return false, "Unknown job."
	end

	pushLog(actor, "setJob", targetPlayer.DisplayName, ("%s:%s"):format(jobName, grade))
	return result(actor, ("Set %s job to %s."):format(targetPlayer.DisplayName, jobName))
end

function ACTIONS.setCrew(actor, payload)
	local targetObj, targetPlayer, err = targetFromPayload(payload)
	if not targetObj then
		return false, err
	end

	local crewName = lowerText(payload.crewName)
	local grade = tostring(math.floor(tonumber(payload.grade) or 0))
	if crewName == "" then
		return false, "Enter a crew name."
	end

	if not targetObj:SetCrew(crewName, grade) then
		return false, "Unknown crew."
	end

	pushLog(actor, "setCrew", targetPlayer.DisplayName, ("%s:%s"):format(crewName, grade))
	return result(actor, ("Set %s crew to %s."):format(targetPlayer.DisplayName, crewName))
end

function AdminService.GetContext(player)
	if not Access.HasPermission(player.UserId, MIN_MENU_RANK) then
		return {
			allowed = false,
			message = "You do not have permission to open the admin menu.",
		}
	end

	local rankName = Access.GetRank(player.UserId)
	local players = {}
	local playerIds = PlayerService.GetPlayers()
	table.sort(playerIds)

	for _, userId in ipairs(playerIds) do
		local playerObj = PlayerService.GetPlayer(userId)
		if playerObj then
			players[#players + 1] = serializePlayer(userId, playerObj)
		end
	end

	local time = TimeSyncService.GetTime()
	local hour = math.floor(time)
	local minute = math.floor((time - hour) * 60 + 0.5)
	if minute >= 60 then
		hour = (hour + 1) % 24
		minute = 0
	end

	return {
		allowed = true,
		rank = rankName,
		server = {
			maxPlayers = QBShared.Config.MaxPlayers,
			onlinePlayers = #Players:GetPlayers(),
			loadedCharacters = #players,
			timeText = ("%02d:%02d"):format(hour, minute),
			timeHour = hour,
			timeMinute = minute,
			timeFrozen = TimeSyncService.IsFrozen(),
		},
		players = players,
		items = serializeItems(),
		jobs = serializeJobs(),
		crews = serializeCrews(),
		vehicles = serializeVehicles(),
		weather = serializeWeather(),
		logs = copyLogs(),
	}
end

function AdminService.HandleAction(player, action, payload)
	if not Access.HasPermission(player.UserId, MIN_MENU_RANK) then
		return deny()
	end
	if type(action) ~= "string" or not ACTIONS[action] then
		return false, "Unknown admin action."
	end

	payload = type(payload) == "table" and payload or {}
	return ACTIONS[action](player, payload)
end

return AdminService
