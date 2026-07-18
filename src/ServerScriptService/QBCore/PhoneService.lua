-- Roblox-native smartphone backend.
-- Text travels through TextChatService channels, voice through the Audio API, and
-- every action is re-authorized against the player's inventory phone item.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local VoiceChatService = game:GetService("VoiceChatService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.QBRemotes)

local PhoneService = {}

local InventoryService
local PlayerService
local directoryStore = DataStoreService:GetDataStore("QBCore_PhoneDirectory")
local onlineByNumber = {}
local activeCalls = {} -- [UserId] = call
local phoneChannels = {} -- [stable pair key] = TextChannel
local socialChannel

local MAX_CALL_HISTORY = 50

local function trim(value)
	return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function hasPhone(playerObj)
	return playerObj and playerObj:GetItemByName("phone") ~= nil
end

local function ensurePhoneData(playerObj)
	local data = playerObj.PlayerData
	data.charinfo = data.charinfo or {}
	data.phone = data.phone or {}
	if data.phone.starterGranted == nil then
		data.phone.starterGranted = false
	end
	data.phone.settings = data.phone.settings or { dnd = false, sounds = true }
	data.phone.callHistory = data.phone.callHistory or {}
	return data.phone
end

local function fallbackPhoneNumber(playerObj)
	local citizenId = tostring(playerObj.PlayerData.citizenid or "")
	local hash = 17
	for index = 1, #citizenId do
		hash = (hash * 31 + string.byte(citizenId, index)) % 10000000
	end
	local source = playerObj._source
	local userId = source and source.UserId or 0
	hash = (hash + userId * 97 + (tonumber(playerObj.PlayerData.cid) or 0) * 7919) % 10000000
	return ("555-%04d-%03d"):format(math.floor(hash / 1000), hash % 1000)
end

local function claimPhoneNumber(playerObj)
	local citizenId = tostring(playerObj.PlayerData.citizenid or "")
	local current = trim(playerObj.PlayerData.charinfo.phone)
	if current ~= "" then
		return current
	end

	local candidate = fallbackPhoneNumber(playerObj)
	local claimed = false
	local ok = pcall(function()
		directoryStore:UpdateAsync("Number_" .. candidate, function(existing)
			if existing == nil or existing == citizenId then
				claimed = true
				return citizenId
			end
			return existing
		end)
	end)

	if not ok or not claimed then
		-- A deterministic suffix keeps Studio usable when API Services are disabled.
		candidate = candidate .. "-" .. tostring((tonumber(playerObj.PlayerData.cid) or 1) % 10)
	end
	playerObj.PlayerData.charinfo.phone = candidate
	return candidate
end

local function registerOnline(player, playerObj)
	ensurePhoneData(playerObj)
	local number = claimPhoneNumber(playerObj)
	onlineByNumber[number] = player
	playerObj:UpdateClient("charinfo", playerObj.PlayerData.charinfo)
	return number
end

local function getPlayerObj(player)
	return player and PlayerService and PlayerService.GetPlayer(player.UserId) or nil
end

local function displayName(playerObj)
	return playerObj and playerObj:GetName() or "Unknown"
end

local function contactFor(player)
	local object = getPlayerObj(player)
	if not object or not hasPhone(object) then
		return nil
	end
	return {
		userId = player.UserId,
		name = displayName(object),
		number = claimPhoneNumber(object),
		displayName = player.DisplayName,
	}
end

local function onlineContacts(forPlayer)
	local contacts = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= forPlayer then
			local contact = contactFor(other)
			if contact then
				contacts[#contacts + 1] = contact
			end
		end
	end
	table.sort(contacts, function(a, b)
		return string.lower(a.name) < string.lower(b.name)
	end)
	return contacts
end

local function makeSnapshot(player, playerObj)
	local phone = ensurePhoneData(playerObj)
	return {
		profile = {
			name = displayName(playerObj),
			number = claimPhoneNumber(playerObj),
			citizenId = playerObj.PlayerData.citizenid,
			userId = player.UserId,
		},
		contacts = onlineContacts(player),
		settings = phone.settings,
		callHistory = phone.callHistory,
	}
end

local function validateRequest(player)
	local playerObj = getPlayerObj(player)
	if not playerObj then
		return nil, "Character not loaded."
	end
	if not hasPhone(playerObj) then
		return nil, "You need a phone item."
	end
	registerOnline(player, playerObj)
	return playerObj
end

local function findTarget(payload)
	payload = type(payload) == "table" and payload or {}
	local userId = tonumber(payload.userId)
	local target = userId and Players:GetPlayerByUserId(userId) or nil
	if not target and trim(payload.number) ~= "" then
		target = onlineByNumber[trim(payload.number)]
	end
	return target
end

local function pairKey(a, b)
	local low, high = math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId)
	return tostring(low) .. "_" .. tostring(high)
end

local function eligibleDirectParticipants(requester, target)
	local ok, participants = pcall(function()
		return TextChatService:CanUsersDirectChatAsync(requester.UserId, { target.UserId })
	end)
	if not ok or type(participants) ~= "table" then
		return false
	end
	local foundRequester = false
	local foundTarget = false
	for _, userId in ipairs(participants) do
		foundRequester = foundRequester or tonumber(userId) == requester.UserId
		foundTarget = foundTarget or tonumber(userId) == target.UserId
	end
	-- Some engine versions return only eligible targets, while newer versions return
	-- all participants. Accept either documented shape without weakening the check.
	return foundTarget and (foundRequester or #participants == 1)
end

local function prepareTextChannel(player, target)
	if not eligibleDirectParticipants(player, target) then
		return nil, "Roblox communication settings do not allow this conversation."
	end

	local key = pairKey(player, target)
	local channel = phoneChannels[key]
	if channel and channel.Parent then
		return channel
	end

	channel = Instance.new("TextChannel")
	channel.Name = "QBPhone_" .. key
	channel.Parent = TextChatService
	local ok, err = pcall(function()
		channel:AddUserAsync(player.UserId)
		channel:AddUserAsync(target.UserId)
	end)
	if not ok then
		channel:Destroy()
		return nil, "Roblox could not create the private channel: " .. tostring(err)
	end
	phoneChannels[key] = channel

	local senderContact = contactFor(player)
	local targetContact = contactFor(target)
	Remotes.PhonePush:FireClient(player, "conversationReady", { channel = channel.Name, contact = targetContact })
	Remotes.PhonePush:FireClient(target, "conversationReady", { channel = channel.Name, contact = senderContact })
	return channel
end

local function groupsOverlap(groups)
	if type(groups) ~= "table" or type(groups[1]) ~= "table" or type(groups[2]) ~= "table" then
		return false
	end
	local first = {}
	for _, id in ipairs(groups[1]) do
		first[id] = true
	end
	for _, id in ipairs(groups[2]) do
		if first[id] then
			return true
		end
	end
	return false
end

local function canVoiceCall(a, b)
	local okA, enabledA = pcall(function()
		return VoiceChatService:IsVoiceEnabledForUserIdAsync(a.UserId)
	end)
	local okB, enabledB = pcall(function()
		return VoiceChatService:IsVoiceEnabledForUserIdAsync(b.UserId)
	end)
	if not okA or not okB or not enabledA or not enabledB then
		return false, "Both players must be eligible for and enable Roblox voice chat."
	end
	local okGroups, groups = pcall(function()
		return VoiceChatService:GetChatGroupsAsync({ a, b })
	end)
	if not okGroups then
		return false, "Voice group checks are unavailable. Enable Chat & Voice Groups APIs for the experience."
	end
	if not groupsOverlap(groups) then
		return false, "Roblox age or communication settings do not allow this call."
	end
	return true
end

local function callPayload(call, forPlayer, state)
	local other = call.caller == forPlayer and call.receiver or call.caller
	return {
		state = state,
		contact = contactFor(other),
		startedAt = call.startedAt,
	}
end

local function pushCall(call, state)
	if call.caller.Parent then
		Remotes.PhonePush:FireClient(call.caller, "callState", callPayload(call, call.caller, state))
	end
	if call.receiver.Parent then
		Remotes.PhonePush:FireClient(call.receiver, "callState", callPayload(call, call.receiver, state))
	end
end

local function appendCallHistory(player, other, direction, missed, startedAt)
	local object = getPlayerObj(player)
	if not object then
		return
	end
	local data = ensurePhoneData(object)
	table.insert(data.callHistory, 1, {
		name = contactFor(other) and contactFor(other).name or other.DisplayName,
		number = contactFor(other) and contactFor(other).number or "",
		direction = direction,
		missed = missed == true,
		time = os.time(),
		duration = startedAt and math.max(0, os.time() - startedAt) or 0,
	})
	while #data.callHistory > MAX_CALL_HISTORY do
		table.remove(data.callHistory)
	end
end

local function destroyCallAudio(call)
	for _, instance in ipairs(call.audio or {}) do
		if instance and instance.Parent then
			instance:Destroy()
		end
	end
	call.audio = {}
end

local function endCall(call, reason, declinedBy)
	if not call or call.ended then
		return
	end
	call.ended = true
	destroyCallAudio(call)
	activeCalls[call.caller.UserId] = nil
	activeCalls[call.receiver.UserId] = nil
	local missed = call.state ~= "connected"
	appendCallHistory(call.caller, call.receiver, "outgoing", missed, call.connectedAt)
	appendCallHistory(call.receiver, call.caller, "incoming", missed, call.connectedAt)
	pushCall(call, reason or (declinedBy and "declined" or "ended"))
end

local function findVoiceInput(player)
	return player:FindFirstChildWhichIsA("AudioDeviceInput")
end

local function connectCallAudio(call)
	local callerInput = findVoiceInput(call.caller)
	local receiverInput = findVoiceInput(call.receiver)
	if not callerInput or not receiverInput then
		return false, "Roblox Audio API inputs are unavailable. Enable voice and set VoiceChatService.UseAudioApi to Enabled."
	end

	local folder = Workspace:FindFirstChild("QBPhoneCallAudio")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "QBPhoneCallAudio"
		folder.Parent = Workspace
	end

	local callerOutput = Instance.new("AudioDeviceOutput")
	callerOutput.Name = "CallOutput_" .. call.caller.UserId
	callerOutput.Player = call.caller
	callerOutput.Parent = folder
	local receiverOutput = Instance.new("AudioDeviceOutput")
	receiverOutput.Name = "CallOutput_" .. call.receiver.UserId
	receiverOutput.Player = call.receiver
	receiverOutput.Parent = folder

	local toCaller = Instance.new("Wire")
	toCaller.Name = "CallWire_" .. call.receiver.UserId .. "_to_" .. call.caller.UserId
	toCaller.SourceInstance = receiverInput
	toCaller.TargetInstance = callerOutput
	toCaller.Parent = folder
	local toReceiver = Instance.new("Wire")
	toReceiver.Name = "CallWire_" .. call.caller.UserId .. "_to_" .. call.receiver.UserId
	toReceiver.SourceInstance = callerInput
	toReceiver.TargetInstance = receiverOutput
	toReceiver.Parent = folder
	call.audio = { toCaller, toReceiver, callerOutput, receiverOutput }
	return true
end

local function startSocialChannel()
	local existing = TextChatService:FindFirstChild("QBStudSpace")
	if existing and existing:IsA("TextChannel") then
		socialChannel = existing
	else
		socialChannel = Instance.new("TextChannel")
		socialChannel.Name = "QBStudSpace"
		socialChannel.Parent = TextChatService
	end
end

local function addSocialUser(player)
	if not socialChannel then
		return
	end
	local ok, allowed = pcall(function()
		return TextChatService:CanUserChatAsync(player.UserId)
	end)
	if ok and allowed then
		pcall(function()
			socialChannel:AddUserAsync(player.UserId)
		end)
	end
end

function PhoneService.Open(player, playerObj)
	if not player or not playerObj or not hasPhone(playerObj) then
		return false, "You need a phone item."
	end
	registerOnline(player, playerObj)
	addSocialUser(player)
	Remotes.OpenPhone:FireClient(player, makeSnapshot(player, playerObj))
	return true
end

function PhoneService.OnCharacterLoaded(player, playerObj)
	if not playerObj then
		return
	end
	local phoneData = ensurePhoneData(playerObj)
	if phoneData.starterGranted ~= true then
		if hasPhone(playerObj) then
			phoneData.starterGranted = true
		elseif playerObj:AddItem("phone", 1, nil, {}, "phone-starter-migration") then
			phoneData.starterGranted = true
		else
			playerObj:Notify("Make one inventory slot free to receive your smartphone.", "error", 5000)
		end
		if phoneData.starterGranted then
			playerObj:Save()
		end
	end
	registerOnline(player, playerObj)
	addSocialUser(player)
end

function PhoneService.OnPlayerLeave(player)
	local object = getPlayerObj(player)
	if object and object.PlayerData.charinfo then
		onlineByNumber[object.PlayerData.charinfo.phone] = nil
	end
	local call = activeCalls[player.UserId]
	if call then
		endCall(call, "ended")
	end
	for key, channel in pairs(phoneChannels) do
		local first, second = string.match(key, "^(%d+)_(%d+)$")
		if tonumber(first) == player.UserId or tonumber(second) == player.UserId then
			if channel.Parent then
				channel:Destroy()
			end
			phoneChannels[key] = nil
		end
	end
end

function PhoneService.Start(inventory, playersService)
	InventoryService = inventory
	PlayerService = playersService
	startSocialChannel()

	InventoryService.CreateUseableItem("phone", function(playerObj)
		local player = playerObj._source
		if not player then
			return false, "Phone is only available online."
		end
		local ok, err = PhoneService.Open(player, playerObj)
		if not ok then
			return false, err
		end
		return true, nil, "Phone opened."
	end)

	Remotes.GetPhoneSnapshot.OnServerInvoke = function(player)
		local playerObj, err = validateRequest(player)
		if not playerObj then
			return nil, err
		end
		return makeSnapshot(player, playerObj)
	end

	Remotes.PhoneRequest.OnServerInvoke = function(player, action, payload)
		local playerObj, err = validateRequest(player)
		if not playerObj then
			return false, err
		end
		payload = type(payload) == "table" and payload or {}

		if action == "prepareText" then
			local target = findTarget(payload)
			if not target or target == player then
				return false, "That player is not available."
			end
			local targetObj = getPlayerObj(target)
			if not targetObj or not hasPhone(targetObj) then
				return false, "That player does not have a phone."
			end
			local channel, channelErr = prepareTextChannel(player, target)
			if not channel then
				return false, channelErr
			end
			return true, { channel = channel.Name, contact = contactFor(target) }
		elseif action == "startCall" then
			local target = findTarget(payload)
			if not target or target == player then
				return false, "That player is not available."
			end
			local targetObj = getPlayerObj(target)
			if not targetObj or not hasPhone(targetObj) then
				return false, "That player does not have a phone."
			end
			if activeCalls[player.UserId] or activeCalls[target.UserId] then
				return false, "One of you is already in a call."
			end
			local targetPhone = ensurePhoneData(targetObj)
			if targetPhone.settings.dnd == true then
				return false, "That player has Do Not Disturb enabled."
			end
			local eligible, voiceErr = canVoiceCall(player, target)
			if not eligible then
				return false, voiceErr
			end
			local call = {
				caller = player,
				receiver = target,
				state = "ringing",
				startedAt = os.time(),
				audio = {},
			}
			activeCalls[player.UserId] = call
			activeCalls[target.UserId] = call
			Remotes.PhonePush:FireClient(player, "callState", callPayload(call, player, "dialing"))
			Remotes.PhonePush:FireClient(target, "callState", callPayload(call, target, "incoming"))
			task.delay(30, function()
				if not call.ended and call.state == "ringing" then
					endCall(call, "missed")
				end
			end)
			return true
		elseif action == "acceptCall" then
			local call = activeCalls[player.UserId]
			if not call or call.receiver ~= player or call.state ~= "ringing" then
				return false, "There is no incoming call to accept."
			end
			local connected, audioErr = connectCallAudio(call)
			if not connected then
				endCall(call, "failed")
				return false, audioErr
			end
			call.state = "connected"
			call.connectedAt = os.time()
			pushCall(call, "connected")
			return true
		elseif action == "declineCall" or action == "hangupCall" then
			local call = activeCalls[player.UserId]
			if not call then
				return false, "There is no active call."
			end
			endCall(call, action == "declineCall" and "declined" or "ended", player)
			return true
		elseif action == "settings" then
			local phone = ensurePhoneData(playerObj)
			phone.settings.dnd = payload.dnd == true
			phone.settings.sounds = payload.sounds ~= false
			playerObj:Save()
			return true, phone.settings
		elseif action == "prepareSocial" then
			addSocialUser(player)
			if not socialChannel or not socialChannel:FindFirstChild(tostring(player.UserId)) then
				-- TextSource names are engine-owned and can vary; SendAsync will provide
				-- the final authoritative error if the source is unavailable.
			end
			return true, { channel = socialChannel and socialChannel.Name or "" }
		end

		return false, "Unknown phone action."
	end
end

return PhoneService
