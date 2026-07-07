--[[
    Time-of-day visual grading: every frame, lerps Lighting/effect properties between
    the two Config.World.TimeCycle keyframes around the current ClockTime. Client-side
    on purpose -- locally-set Lighting values mask the replicated ones, and the server
    only writes them once at boot. Never creates instances; it drives the ones the
    server made (PlayerService.ApplyWorldEnvironment) and skips any not yet replicated.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local QBShared = require(ReplicatedStorage.QBShared.Main)
local Weather = require(ReplicatedStorage.QBShared.Weather)

local world = QBShared.Config.World
local cycle = world and world.TimeCycle
local weatherStateFolder = ReplicatedStorage:FindFirstChild("QBWeatherState")

if
	not world
	or world.ForceClearNoon == false
	or type(cycle) ~= "table"
	or cycle.Enabled == false
	or type(cycle.Keyframes) ~= "table"
	or #cycle.Keyframes < 2
then
	return
end

-- Shallow copy before sorting so the shared config table is never mutated.
local keyframes = {}
for i, keyframe in ipairs(cycle.Keyframes) do
	keyframes[i] = keyframe
end
table.sort(keyframes, function(a, b)
	return (tonumber(a.Hour) or 0) < (tonumber(b.Hour) or 0)
end)

local function lerpValue(a, b, alpha)
	if typeof(a) == "Color3" and typeof(b) == "Color3" then
		return a:Lerp(b, alpha)
	end
	if type(a) == "number" and type(b) == "number" then
		return a + (b - a) * alpha
	end
	return alpha < 0.5 and a or b
end

-- Blends over prev's shape; a key missing from the next keyframe just holds its value.
local function blendTable(prev, nxt, alpha)
	local out = {}
	for key, value in pairs(prev) do
		local other = nxt[key]
		if type(value) == "table" and type(other) == "table" then
			out[key] = blendTable(value, other, alpha)
		elseif other ~= nil then
			out[key] = lerpValue(value, other, alpha)
		else
			out[key] = value
		end
	end
	return out
end

local function sample(hour)
	local count = #keyframes
	local prev, nxt = keyframes[count], keyframes[1]
	local span = (24 - prev.Hour) + nxt.Hour
	local into = hour >= prev.Hour and (hour - prev.Hour) or (hour + 24 - prev.Hour)

	if hour >= keyframes[1].Hour and hour < keyframes[count].Hour then
		for i = 1, count - 1 do
			if hour >= keyframes[i].Hour and hour < keyframes[i + 1].Hour then
				prev, nxt = keyframes[i], keyframes[i + 1]
				span = nxt.Hour - prev.Hour
				into = hour - prev.Hour
				break
			end
		end
	end

	local alpha = span > 0 and math.max(0, math.min(1, into / span)) or 0
	alpha = alpha * alpha * (3 - 2 * alpha) -- smoothstep: eases in/out of each keyframe
	return blendTable(prev, nxt, alpha)
end

local function getServerTime()
	local ok, value = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	if ok and type(value) == "number" then
		return value
	end
	return os.clock()
end

local function getWeatherStateFolder()
	if weatherStateFolder and weatherStateFolder.Parent then
		return weatherStateFolder
	end
	weatherStateFolder = ReplicatedStorage:FindFirstChild("QBWeatherState")
	return weatherStateFolder
end

local function getWeatherState()
	local folder = getWeatherStateFolder()
	if not folder then
		return nil
	end

	return {
		currentWeather = folder:GetAttribute("CurrentWeather"),
		nextWeather = folder:GetAttribute("NextWeather"),
		transitionStartedAt = folder:GetAttribute("TransitionStartedAt"),
		transitionDuration = folder:GetAttribute("TransitionDuration"),
		blackout = folder:GetAttribute("Blackout") == true,
	}
end

ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == "QBWeatherState" then
		weatherStateFolder = child
	end
end)

-- Lazy instance lookups: the server creates these at boot, but this script can start
-- before they replicate, and a re-parented/deleted effect should be re-found.
local found = {}
local function effect(className)
	local cached = found[className]
	if cached and cached.Parent then
		return cached
	end
	cached = Lighting:FindFirstChildOfClass(className)
	found[className] = cached
	return cached
end

local clouds
local function getClouds()
	if clouds and clouds.Parent then
		return clouds
	end
	clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
	return clouds
end

local warned = {}
local function applyProps(instance, props)
	if not instance or type(props) ~= "table" then
		return
	end
	for name, value in pairs(props) do
		local ok = pcall(function()
			instance[name] = value
		end)
		if not ok and not warned[name] then
			warned[name] = true
			warn(("QBTimeCycle: keyframe property %s.%s could not be applied"):format(instance.ClassName, name))
		end
	end
end

RunService.Heartbeat:Connect(function()
	local frame = sample(Lighting.ClockTime % 24)
	local weatherState = getWeatherState()
	if weatherState then
		local weatherLayer = Weather.SampleState(weatherState, getServerTime())
		Weather.ApplyLayerToFrame(frame, weatherLayer, weatherState.blackout)
	end

	Lighting.Brightness = frame.Brightness
	Lighting.ExposureCompensation = frame.ExposureCompensation
	Lighting.ShadowSoftness = frame.ShadowSoftness
	Lighting.Ambient = frame.Ambient
	Lighting.OutdoorAmbient = frame.OutdoorAmbient

	applyProps(effect("ColorCorrectionEffect"), frame.ColorCorrection)
	applyProps(effect("Atmosphere"), frame.Atmosphere)
	applyProps(effect("SunRaysEffect"), frame.SunRays)
	applyProps(effect("BloomEffect"), frame.Bloom)

	local sky = effect("Sky")
	if sky and frame.SunAngularSize then
		sky.SunAngularSize = frame.SunAngularSize
	end

	local cloudLayer = getClouds()
	if cloudLayer then
		if frame.CloudColor then
			cloudLayer.Color = frame.CloudColor
		end
		if frame.CloudCover ~= nil then
			cloudLayer.Cover = frame.CloudCover
		end
		if frame.CloudDensity ~= nil then
			cloudLayer.Density = frame.CloudDensity
		end
	end
end)
