-- Client menu for the stage speaker jukebox. The server owns playback.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Remotes = require(ReplicatedStorage.QBRemotes)
local StageMusic = require(ReplicatedStorage.QBShared.StageMusic)
local QBCoreClient = require(ReplicatedStorage.QBCoreClient)

local player = Players.LocalPlayer

local CONTROL_EVENT = "StageMusicControl"
local MENU_TITLE = "Stage Music"

local qbMenuOpen = nil

local function notify(text, notifyType, length)
	QBCoreClient.OnNotify:Fire(text, notifyType or "primary", length or 3000)
end

local function hasAudioListener()
	local camera = workspace.CurrentCamera
	if camera and camera:FindFirstChildWhichIsA("AudioListener", true) then
		return true
	end

	local character = player.Character
	if character and character:FindFirstChildWhichIsA("AudioListener", true) then
		return true
	end

	return false
end

local function ensureClientAudioBridge()
	if hasAudioListener() then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local ok, listenerOrErr = pcall(function()
		local listener = Instance.new("AudioListener")
		listener.Name = "QBStageAudioListener"
		listener.Parent = camera
		return listener
	end)
	if not ok then
		warn("[QBStageMusic] Could not create AudioListener: " .. tostring(listenerOrErr))
		return
	end

	local listener = listenerOrErr
	local output = SoundService:FindFirstChildWhichIsA("AudioDeviceOutput", true)
	if not output then
		local outputOk, outputOrErr = pcall(function()
			local created = Instance.new("AudioDeviceOutput")
			created.Name = "QBStageAudioOutput"
			created.Parent = SoundService
			return created
		end)
		if not outputOk then
			warn("[QBStageMusic] Could not create AudioDeviceOutput: " .. tostring(outputOrErr))
			return
		end
		output = outputOrErr
	end

	local wireOk, wireErr = pcall(function()
		local wire = Instance.new("Wire")
		wire.Name = "QBStageAudioOutputWire"
		wire.SourceInstance = listener
		wire.TargetInstance = output
		wire.Parent = listener
	end)
	if not wireOk then
		warn("[QBStageMusic] Could not wire AudioListener to output: " .. tostring(wireErr))
	end
end

local function ensureQBMenu()
	if qbMenuOpen then
		return true
	end

	local playerGui = player:WaitForChild("PlayerGui")
	local menuGui = playerGui:WaitForChild("QBMenu", 8)
	if not menuGui then
		notify("QBMenu is not loaded yet.", "error")
		return false
	end

	qbMenuOpen = menuGui:WaitForChild("OpenMenu", 4)
	if not qbMenuOpen then
		notify("QBMenu is missing its open API.", "error")
		return false
	end

	return true
end

local function buildAction(action, stationId, trackId, extraArgs)
	local args = {
		action = action,
		stationId = stationId,
	}
	if trackId ~= nil then
		args.trackId = trackId
	end
	if type(extraArgs) == "table" then
		for key, value in pairs(extraArgs) do
			args[key] = value
		end
	end

	return {
		event = CONTROL_EVENT,
		isServer = true,
		args = args,
	}
end

local function formatVolume(value)
	value = tonumber(value) or StageMusic.Defaults.Volume
	return ("%d%%"):format(math.floor(value * 100 + 0.5))
end

local function buildMenuItems(station)
	local stationId = tostring(station.id or "")
	local stationLabel = tostring(station.label or "Stage")
	local volumeLabel = formatVolume(station.volume)
	local keepSearchArgs = type(station.searchResults) == "table" and { keepSearch = true } or nil
	local items = {
		{
			header = MENU_TITLE,
			txt = stationLabel,
			isMenuHeader = true,
		},
		{
			header = "Controls",
			isMenuHeader = true,
		},
		{
			header = "Lower Volume",
			txt = "Current volume: " .. volumeLabel,
			params = buildAction("volume_down", stationId, nil, keepSearchArgs),
			shouldClose = false,
		},
		{
			header = "Raise Volume",
			txt = "Current volume: " .. volumeLabel,
			params = buildAction("volume_up", stationId, nil, keepSearchArgs),
			shouldClose = false,
		},
	}

	if station.currentTrackLabel and station.currentTrackLabel ~= "" then
		items[#items + 1] = {
			header = "Stop Music",
			txt = "Now playing: " .. station.currentTrackLabel,
			params = buildAction("stop", stationId, nil, keepSearchArgs),
			shouldClose = false,
		}
	end

	if type(station.searchResults) == "table" then
		items[#items + 1] = {
			header = "Search Results",
			txt = tostring(station.searchQuery or ""),
			isMenuHeader = true,
		}

		if #station.searchResults == 0 then
			items[#items + 1] = {
				header = "No results",
				txt = "Try another search.",
				disabled = true,
			}
		else
			for _, track in ipairs(station.searchResults) do
				items[#items + 1] = {
					header = track.label or track.id,
					txt = StageMusic.GetTrackSubtitle(track),
					params = buildAction("play_search", stationId, nil, {
						searchId = track.searchId,
					}),
				}
			end
		end
	end

	local tracks = StageMusic.GetEnabledTracks()
	if #tracks == 0 then
		items[#items + 1] = {
			header = "No tracks configured",
			txt = "Add enabled tracks in QBShared/StageMusic.lua.",
			disabled = true,
		}
		return items
	end

	items[#items + 1] = {
		header = "Saved Tracks",
		isMenuHeader = true,
	}

	for _, track in ipairs(tracks) do
		items[#items + 1] = {
			header = track.label or track.id,
			txt = StageMusic.GetTrackSubtitle(track),
			params = buildAction("play", stationId, track.id),
		}
	end

	return items
end

local function openStageMusicMenu(station)
	if type(station) ~= "table" then
		return
	end

	ensureClientAudioBridge()
	if not ensureQBMenu() then
		return
	end

	qbMenuOpen:Invoke(buildMenuItems(station), {
		title = MENU_TITLE,
		subtitle = tostring(station.label or "Stage"),
	})
end

Remotes.OpenStageMusicMenu.OnClientEvent:Connect(openStageMusicMenu)
