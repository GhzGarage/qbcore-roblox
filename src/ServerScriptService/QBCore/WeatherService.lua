-- Server-authoritative weather sync.
-- Clients render particles/local grading, but this service owns current weather,
-- automatic cycling, blackout state, GlobalWind, and replication.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local QBShared = require(ReplicatedStorage.QBShared.Main)
local Remotes = require(ReplicatedStorage.QBRemotes)

local Weather = QBShared.Weather

local WeatherService = {}

local STATE_FOLDER_NAME = "QBWeatherState"
local ORIGINAL_ENABLED_ATTRIBUTE = "QBWeatherOriginalEnabled"
local LOOP_INTERVAL = 1

local started = false
local stateFolder = nil
local nextAutoChangeAt = 0
local tagConnections = {}

local state = {
	currentWeather = Weather.Defaults.StartWeather,
	nextWeather = Weather.Defaults.StartWeather,
	transitionStartedAt = 0,
	transitionDuration = 0,
	frozen = false,
	dynamic = true,
	blackout = false,
	updatedAt = 0,
}

local function now()
	local ok, value = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	if ok and type(value) == "number" then
		return value
	end
	return os.clock()
end

local function config()
	local cfg = QBShared.Config.Weather
	return type(cfg) == "table" and cfg or {}
end

local function configValue(key)
	local cfg = config()
	if cfg[key] ~= nil then
		return cfg[key]
	end
	return Weather.Defaults[key]
end

local function getTransitionSeconds(override)
	local value = tonumber(override)
	if value == nil then
		value = tonumber(configValue("TransitionSeconds")) or Weather.Defaults.TransitionSeconds
	end
	return math.max(0, value)
end

local function getDurationSeconds()
	local minSeconds = tonumber(configValue("MinWeatherSeconds")) or Weather.Defaults.MinWeatherSeconds
	local maxSeconds = tonumber(configValue("MaxWeatherSeconds")) or Weather.Defaults.MaxWeatherSeconds
	minSeconds = math.max(30, math.floor(minSeconds))
	maxSeconds = math.max(minSeconds, math.floor(maxSeconds))
	return math.random(minSeconds, maxSeconds)
end

local function getStateFolder()
	if stateFolder and stateFolder.Parent then
		return stateFolder
	end

	stateFolder = ReplicatedStorage:FindFirstChild(STATE_FOLDER_NAME)
	if not stateFolder then
		stateFolder = Instance.new("Folder")
		stateFolder.Name = STATE_FOLDER_NAME
		stateFolder.Parent = ReplicatedStorage
	end
	return stateFolder
end

local function snapshot()
	return {
		currentWeather = state.currentWeather,
		nextWeather = state.nextWeather,
		transitionStartedAt = state.transitionStartedAt,
		transitionDuration = state.transitionDuration,
		frozen = state.frozen,
		dynamic = state.dynamic,
		blackout = state.blackout,
		updatedAt = state.updatedAt,
		presets = Weather.GetPresetList(),
	}
end

local function publish()
	state.updatedAt = now()

	local folder = getStateFolder()
	folder:SetAttribute("CurrentWeather", state.currentWeather)
	folder:SetAttribute("NextWeather", state.nextWeather)
	folder:SetAttribute("TransitionStartedAt", state.transitionStartedAt)
	folder:SetAttribute("TransitionDuration", state.transitionDuration)
	folder:SetAttribute("Frozen", state.frozen)
	folder:SetAttribute("Dynamic", state.dynamic)
	folder:SetAttribute("Blackout", state.blackout)
	folder:SetAttribute("UpdatedAt", state.updatedAt)

	local layer = Weather.BlendPresets(state.currentWeather, state.nextWeather, 1)
	if typeof(layer.wind) == "Vector3" then
		Workspace.GlobalWind = layer.wind
	end

	Remotes.WeatherStateUpdated:FireAllClients(snapshot())
end

local function sendSnapshot(player)
	Remotes.WeatherStateUpdated:FireClient(player, snapshot())
end

local function setLightBlackout(light, enabled)
	if not light:IsA("Light") then
		return
	end

	if enabled then
		if light:GetAttribute(ORIGINAL_ENABLED_ATTRIBUTE) == nil then
			light:SetAttribute(ORIGINAL_ENABLED_ATTRIBUTE, light.Enabled)
		end
		light.Enabled = false
	else
		local original = light:GetAttribute(ORIGINAL_ENABLED_ATTRIBUTE)
		if original ~= nil then
			light.Enabled = original == true
			light:SetAttribute(ORIGINAL_ENABLED_ATTRIBUTE, nil)
		end
	end
end

local function applyBlackoutToInstance(instance, enabled)
	if instance:IsA("Light") then
		setLightBlackout(instance, enabled)
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("Light") then
			setLightBlackout(descendant, enabled)
		end
	end
end

local function configuredBlackoutTags()
	local tags = config().BlackoutLightTags
	if type(tags) ~= "table" or #tags == 0 then
		return { "QBBlackoutLight", "StreetLight" }
	end
	return tags
end

local function applyBlackout()
	for _, tag in ipairs(configuredBlackoutTags()) do
		if type(tag) == "string" and tag ~= "" then
			for _, instance in ipairs(CollectionService:GetTagged(tag)) do
				applyBlackoutToInstance(instance, state.blackout)
			end

			if not tagConnections[tag] then
				tagConnections[tag] = CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
					if state.blackout then
						applyBlackoutToInstance(instance, true)
					end
				end)
			end
		end
	end
end

local function scheduleNextAutoChange()
	nextAutoChangeAt = now() + getDurationSeconds()
end

local function transitionComplete(currentTime)
	local duration = tonumber(state.transitionDuration) or 0
	return duration <= 0 or currentTime >= (state.transitionStartedAt + duration)
end

local function finalizeTransition(currentTime)
	if state.currentWeather == state.nextWeather and state.transitionDuration <= 0 then
		return
	end
	if not transitionComplete(currentTime) then
		return
	end

	state.currentWeather = state.nextWeather
	state.transitionDuration = 0
	state.transitionStartedAt = currentTime
	publish()
	scheduleNextAutoChange()
end

function WeatherService.GetState()
	return snapshot()
end

function WeatherService.GetCurrentWeather()
	return state.nextWeather or state.currentWeather
end

function WeatherService.GetPresetList()
	return Weather.GetPresetList()
end

function WeatherService.SetWeather(weatherName, transitionSeconds)
	local normalized = Weather.NormalizeName(weatherName)
	if not normalized then
		return false, ("Unknown weather %q."):format(tostring(weatherName))
	end

	local currentTime = now()
	finalizeTransition(currentTime)

	local duration = getTransitionSeconds(transitionSeconds)
	if duration <= 0 or normalized == state.currentWeather then
		state.currentWeather = normalized
		state.nextWeather = normalized
		state.transitionStartedAt = currentTime
		state.transitionDuration = 0
	else
		state.nextWeather = normalized
		state.transitionStartedAt = currentTime
		state.transitionDuration = duration
	end

	publish()
	scheduleNextAutoChange()

	local preset = Weather.Presets[normalized]
	return true, ("Weather set to %s."):format(preset and preset.label or normalized)
end

function WeatherService.SetFrozen(frozen)
	state.frozen = frozen == true
	publish()
	if not state.frozen then
		scheduleNextAutoChange()
	end
	return state.frozen
end

function WeatherService.IsFrozen()
	return state.frozen
end

function WeatherService.SetDynamic(dynamic)
	state.dynamic = dynamic == true
	publish()
	if state.dynamic then
		scheduleNextAutoChange()
	end
	return state.dynamic
end

function WeatherService.SetBlackout(enabled)
	state.blackout = enabled == true
	applyBlackout()
	publish()
	return state.blackout
end

function WeatherService.IsBlackout()
	return state.blackout
end

function WeatherService.Start()
	if started then
		return
	end
	started = true

	local startWeather = Weather.NormalizeName(configValue("StartWeather")) or Weather.Defaults.StartWeather
	local currentTime = now()
	state.currentWeather = startWeather
	state.nextWeather = startWeather
	state.transitionStartedAt = currentTime
	state.transitionDuration = 0
	state.dynamic = configValue("Dynamic") ~= false
	state.frozen = config().Freeze == true
	state.blackout = config().Blackout == true

	getStateFolder()
	applyBlackout()
	publish()
	scheduleNextAutoChange()

	Players.PlayerAdded:Connect(function(player)
		task.defer(sendSnapshot, player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(sendSnapshot, player)
	end

	task.spawn(function()
		while true do
			task.wait(LOOP_INTERVAL)

			local current = now()
			finalizeTransition(current)

			if
				configValue("Enabled") ~= false
				and state.dynamic
				and not state.frozen
				and state.transitionDuration <= 0
				and current >= nextAutoChangeAt
			then
				local nextWeather = Weather.GetRandomNext(state.currentWeather)
				WeatherService.SetWeather(nextWeather)
			end
		end
	end)
end

return WeatherService
