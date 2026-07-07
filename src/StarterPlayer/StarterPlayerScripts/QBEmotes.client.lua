-- QBCore-style emote menu opened by /emotes.
-- Uses QBMenu for selection and Humanoid:PlayEmoteAsync for Roblox avatar emotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.QBRemotes)
local QBCoreClient = require(ReplicatedStorage.QBCoreClient)

local player = Players.LocalPlayer

local EMOTE_EVENT = "qb-emotes:client:play"
local MENU_TITLE = "Emotes"
local MENU_SUBTITLE = "Choose an emote to play or stop"
local TRACK_FADE_TIME = 0.15

local DEFAULT_EMOTES = {
	{ name = "wave", label = "Wave", source = "default" },
	{ name = "point", label = "Point", source = "default" },
	{ name = "cheer", label = "Cheer", source = "default" },
	{ name = "laugh", label = "Laugh", source = "default" },
	{ name = "dance", label = "Dance", source = "default" },
	{ name = "dance2", label = "Dance 2", source = "default" },
	{ name = "dance3", label = "Dance 3", source = "default" },
}

local currentEmoteName = nil
local currentTrack = nil
local currentHumanoid = nil
local stoppedConnection = nil
local busy = false

local qbMenuGui = nil
local qbMenuOpen = nil
local qbMenuRefresh = nil
local qbMenuSelected = nil
local playEmote

local function notify(text, notifyType, length)
	QBCoreClient.OnNotify:Fire(text, notifyType or "primary", length or 2500)
end

local function trim(value)
	if type(value) ~= "string" then
		return ""
	end
	return value:match("^%s*(.-)%s*$") or ""
end

local function normalizeName(value)
	return trim(tostring(value or "")):lower():gsub("%s+", "")
end

local function displayName(emoteName)
	emoteName = tostring(emoteName or "")
	return emoteName:gsub("(%D)(%d+)$", "%1 %2")
end

local function getEmoteLabel(emote)
	if type(emote) == "table" then
		return tostring(emote.label or emote.name or "")
	end
	return displayName(emote)
end

local function getEmoteName(emote)
	if type(emote) == "table" then
		return trim(tostring(emote.name or ""))
	end
	return trim(emote)
end

local function getEmoteSource(emote)
	if type(emote) == "table" and type(emote.source) == "string" then
		return emote.source
	end
	return "description"
end

local function disconnectStoppedConnection()
	if stoppedConnection then
		stoppedConnection:Disconnect()
		stoppedConnection = nil
	end
end

local function clearCurrentEmote()
	disconnectStoppedConnection()
	currentEmoteName = nil
	currentTrack = nil
	currentHumanoid = nil
end

local function getHumanoid()
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function getPlayingTracks(humanoid)
	if not humanoid then
		return {}
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local ok, tracks = pcall(function()
			return animator:GetPlayingAnimationTracks()
		end)
		if ok and type(tracks) == "table" then
			return tracks
		end
	end

	local ok, tracks = pcall(function()
		return humanoid:GetPlayingAnimationTracks()
	end)
	if ok and type(tracks) == "table" then
		return tracks
	end

	return {}
end

local function trackMatchesEmote(track, emoteName)
	if not track or type(emoteName) ~= "string" then
		return false
	end

	return normalizeName(track.Name) == normalizeName(emoteName)
end

local function stopTrack(track)
	if not track then
		return false
	end

	local ok, isPlaying = pcall(function()
		return track.IsPlaying
	end)
	if not ok or not isPlaying then
		return false
	end

	local stopped = pcall(function()
		track:Stop(TRACK_FADE_TIME)
	end)
	return stopped
end

local function stopMatchingEmoteTracks(humanoid, emoteName)
	local stopped = false
	for _, track in ipairs(getPlayingTracks(humanoid)) do
		if track ~= currentTrack and trackMatchesEmote(track, emoteName) then
			stopped = stopTrack(track) or stopped
		end
	end
	return stopped
end

local function stopCurrentEmote(humanoid)
	humanoid = humanoid or currentHumanoid or getHumanoid()
	local emoteName = currentEmoteName
	local stopped = stopTrack(currentTrack)

	if emoteName then
		stopped = stopMatchingEmoteTracks(humanoid, emoteName) or stopped
	end

	clearCurrentEmote()
	return stopped
end

local function setCurrentTrack(humanoid, emoteName, track)
	disconnectStoppedConnection()
	currentHumanoid = humanoid
	currentEmoteName = emoteName
	currentTrack = track

	if track then
		stoppedConnection = track.Stopped:Connect(function()
			if currentTrack == track then
				clearCurrentEmote()
			end
		end)
	end
end

local function makeTrackSet(humanoid)
	local trackSet = {}
	for _, track in ipairs(getPlayingTracks(humanoid)) do
		trackSet[track] = true
	end
	return trackSet
end

local function findStartedEmoteTrack(humanoid, beforeTracks, emoteName)
	local fallback = nil

	for _ = 1, 4 do
		for _, track in ipairs(getPlayingTracks(humanoid)) do
			local isPlaying = false
			pcall(function()
				isPlaying = track.IsPlaying
			end)

			if isPlaying then
				if not beforeTracks[track] then
					return track
				end
				if not fallback and trackMatchesEmote(track, emoteName) then
					fallback = track
				end
			end
		end

		task.wait()
	end

	return fallback
end

local function isCurrentEmoteActive(humanoid, emoteName)
	if currentEmoteName ~= emoteName then
		return false
	end

	if currentTrack then
		local ok, isPlaying = pcall(function()
			return currentTrack.IsPlaying
		end)
		if ok and isPlaying then
			return true
		end
	end

	for _, track in ipairs(getPlayingTracks(humanoid)) do
		local ok, isPlaying = pcall(function()
			return track.IsPlaying
		end)
		if ok and isPlaying and trackMatchesEmote(track, emoteName) then
			setCurrentTrack(humanoid, emoteName, track)
			return true
		end
	end

	return false
end

local function appendUnique(list, seen, emoteName)
	emoteName = trim(emoteName)
	if emoteName == "" then
		return
	end

	local key = normalizeName(emoteName)
	if seen[key] then
		return
	end

	seen[key] = true
	list[#list + 1] = emoteName
end

local function appendUniqueEntry(list, seen, entry)
	local emoteName = getEmoteName(entry)
	if emoteName == "" then
		return
	end

	local key = normalizeName(emoteName)
	if seen[key] then
		return
	end

	seen[key] = true
	list[#list + 1] = entry
end

local function appendDescriptionEmotes(list, seen, description)
	if not description then
		return
	end

	local ok, emotes = pcall(function()
		return description:GetEmotes()
	end)
	if ok and type(emotes) == "table" then
		for emoteName in pairs(emotes) do
			appendUnique(list, seen, emoteName)
		end
	end

	local equippedOk, equipped = pcall(function()
		return description:GetEquippedEmotes()
	end)
	if equippedOk and type(equipped) == "table" then
		for _, emoteName in ipairs(equipped) do
			appendUnique(list, seen, emoteName)
		end
	end
end

local function getEmoteList()
	local list = {}
	local seen = {}

	for _, emote in ipairs(DEFAULT_EMOTES) do
		appendUniqueEntry(list, seen, emote)
	end

	local humanoid = getHumanoid()
	if humanoid then
		local ok, description = pcall(function()
			return humanoid:GetAppliedDescription()
		end)
		if ok then
			appendDescriptionEmotes(list, seen, description)
		end
	end

	return list
end

local function buildMenuItems()
	local items = {
		{
			header = MENU_TITLE,
			txt = MENU_SUBTITLE,
			isMenuHeader = true,
		},
	}

	for _, emoteName in ipairs(getEmoteList()) do
		local name = getEmoteName(emoteName)
		local label = getEmoteLabel(emoteName)
		local isActive = currentEmoteName == name
		items[#items + 1] = {
			header = label,
			txt = isActive and "Playing now. Select again to stop." or "Play this emote.",
			params = {
				event = EMOTE_EVENT,
				args = {
					name = name,
					label = label,
					source = getEmoteSource(emoteName),
				},
			},
			shouldClose = false,
		}
	end

	return items
end

local function ensureQBMenu()
	if qbMenuOpen and qbMenuRefresh and qbMenuSelected then
		return true
	end

	local playerGui = player:WaitForChild("PlayerGui")
	qbMenuGui = playerGui:WaitForChild("QBMenu", 8)
	if not qbMenuGui then
		notify("QBMenu is not loaded yet.", "error")
		return false
	end

	qbMenuOpen = qbMenuGui:WaitForChild("OpenMenu", 4)
	qbMenuRefresh = qbMenuGui:WaitForChild("RefreshMenu", 4)
	qbMenuSelected = qbMenuGui:WaitForChild("MenuSelected", 4)

	if not qbMenuOpen or not qbMenuRefresh or not qbMenuSelected then
		notify("QBMenu is missing its bindable API.", "error")
		return false
	end

	qbMenuSelected.Event:Connect(function(eventName, emote)
		if eventName ~= EMOTE_EVENT then
			return
		end

		local selectedEmote = getEmoteName(emote)
		if selectedEmote ~= "" then
			task.spawn(function()
				local changed = false
				local ok, err = pcall(function()
					changed = playEmote(emote)
				end)
				if not ok then
					warn("[QBEmotes] play failed: " .. tostring(err))
				end
				if changed and qbMenuRefresh then
					qbMenuRefresh:Invoke(buildMenuItems(), {
						title = MENU_TITLE,
						subtitle = MENU_SUBTITLE,
					})
				end
			end)
		end
	end)

	return true
end

local function playAnimateScriptEmote(character, emoteName)
	local animate = character and character:FindFirstChild("Animate")
	local playBindable = animate and animate:FindFirstChild("PlayEmote")
	if not playBindable or not playBindable:IsA("BindableFunction") then
		return false, nil
	end

	local ok, played, track = pcall(function()
		return playBindable:Invoke(emoteName)
	end)
	if not ok then
		warn(("[QBEmotes] Animate.PlayEmote(%s) failed: %s"):format(emoteName, tostring(played)))
		return false, nil
	end

	return played == true, track
end

playEmote = function(emoteName)
	if busy then
		return false
	end

	local source = getEmoteSource(emoteName)
	local label = getEmoteLabel(emoteName)
	emoteName = getEmoteName(emoteName)
	if emoteName == "" then
		return false
	end

	local character = player.Character
	local humanoid = getHumanoid()
	if not humanoid then
		notify("Your character is not ready yet.", "error")
		return false
	end

	if currentHumanoid and currentHumanoid ~= humanoid then
		clearCurrentEmote()
	end

	if isCurrentEmoteActive(humanoid, emoteName) then
		stopCurrentEmote(humanoid)
		notify(("Stopped %s."):format(label), "primary")
		return true
	end

	busy = true
	stopCurrentEmote(humanoid)

	local beforeTracks = makeTrackSet(humanoid)
	local played = false
	local track = nil

	if source == "default" then
		played, track = playAnimateScriptEmote(character, emoteName)
	else
		local ok, playedOrErr = pcall(function()
			return humanoid:PlayEmoteAsync(emoteName)
		end)

		if not ok then
			warn(("[QBEmotes] PlayEmoteAsync(%s) failed: %s"):format(emoteName, tostring(playedOrErr)))
		else
			played = playedOrErr == true
		end
	end

	if not played then
		busy = false
		clearCurrentEmote()
		notify(("%s is not available for this character."):format(label), "error", 4000)
		return true
	end

	track = track or findStartedEmoteTrack(humanoid, beforeTracks, emoteName)
	setCurrentTrack(humanoid, emoteName, track)
	notify(("Playing %s."):format(label), "success", 2000)

	busy = false
	return true
end

local function openEmoteMenu()
	if not ensureQBMenu() then
		return
	end

	qbMenuOpen:Invoke(buildMenuItems(), {
		title = MENU_TITLE,
		subtitle = MENU_SUBTITLE,
	})
end

player.CharacterAdded:Connect(function()
	clearCurrentEmote()
end)

Remotes.OpenEmoteMenu.OnClientEvent:Connect(openEmoteMenu)
