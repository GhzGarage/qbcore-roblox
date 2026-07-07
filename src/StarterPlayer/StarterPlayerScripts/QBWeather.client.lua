-- Client weather renderer.
-- Weather state is synced by WeatherService; this LocalScript only renders local
-- precipitation and lightning around the current camera.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local QBShared = require(ReplicatedStorage.QBShared.Main)
local Remotes = require(ReplicatedStorage.QBRemotes)
local Weather = require(ReplicatedStorage.QBShared.Weather)

local WEATHER_FOLDER_NAME = "QBWeatherState"
local RAIN_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SNOW_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local latestSnapshot = nil
local weatherFolder = ReplicatedStorage:FindFirstChild(WEATHER_FOLDER_NAME)
local emitterPart = nil
local emitter = nil
local lightningEffect = nil
local thunderSound = nil
local nextThunderAt = 0
local flashUntil = 0
local flashStartedAt = 0
local flashDuration = 0.28

local function getServerTime()
	local ok, value = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	if ok and type(value) == "number" then
		return value
	end
	return os.clock()
end

local function getWeatherFolder()
	if weatherFolder and weatherFolder.Parent then
		return weatherFolder
	end
	weatherFolder = ReplicatedStorage:FindFirstChild(WEATHER_FOLDER_NAME)
	return weatherFolder
end

local function readStateFromFolder()
	local folder = getWeatherFolder()
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

local function getWeatherState()
	return readStateFromFolder() or latestSnapshot
end

local function normalizeAssetId(assetId)
	if type(assetId) == "number" then
		return "rbxassetid://" .. tostring(math.floor(assetId))
	elseif type(assetId) ~= "string" then
		return ""
	end

	if assetId == "" then
		return ""
	elseif assetId:match("^%d+$") then
		return "rbxassetid://" .. assetId
	elseif assetId:match("^rbxassetid://%d+$") then
		return assetId
	end
	return ""
end

local function ensureEmitter()
	if emitter and emitter.Parent and emitterPart and emitterPart.Parent then
		return emitter
	end

	emitterPart = Instance.new("Part")
	emitterPart.Name = "QBWeatherEmitter"
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanTouch = false
	emitterPart.CanQuery = false
	emitterPart.Transparency = 1
	emitterPart.Size = Vector3.new(160, 1, 160)
	emitterPart.Parent = Workspace

	emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Precipitation"
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.LockedToPart = false
	emitter.Parent = emitterPart

	pcall(function()
		emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	end)

	return emitter
end

local function ensureLightning()
	if lightningEffect and lightningEffect.Parent then
		return lightningEffect
	end

	lightningEffect = Instance.new("ColorCorrectionEffect")
	lightningEffect.Name = "QBWeatherLightning"
	lightningEffect.Brightness = 0
	lightningEffect.Contrast = 0
	lightningEffect.Saturation = 0
	lightningEffect.TintColor = Color3.new(1, 1, 1)
	lightningEffect.Parent = Lighting
	return lightningEffect
end

local function ensureThunderSound()
	if thunderSound and thunderSound.Parent then
		return thunderSound
	end

	local cfg = QBShared.Config.Weather or {}
	local soundId = normalizeAssetId(cfg.ThunderSoundId)
	if soundId == "" then
		return nil
	end

	thunderSound = Instance.new("Sound")
	thunderSound.Name = "QBWeatherThunder"
	thunderSound.SoundId = soundId
	thunderSound.Volume = 0.5
	thunderSound.RollOffMode = Enum.RollOffMode.InverseTapered
	thunderSound.Parent = SoundService
	return thunderSound
end

local function setNumberRangeProperty(object, property, value)
	pcall(function()
		object[property] = NumberRange.new(value)
	end)
end

local function configureEmitter(layer)
	local precipitation = type(layer.precipitation) == "table" and layer.precipitation or {}
	local rate = math.max(0, tonumber(precipitation.rate) or 0)
	local active = rate > 1
	local particleEmitter = ensureEmitter()

	particleEmitter.Enabled = active
	particleEmitter.Rate = active and rate or 0

	if not active then
		return
	end

	local kind = precipitation.kind == "snow" and "snow" or "rain"
	local wind = typeof(layer.wind) == "Vector3" and layer.wind or Vector3.zero
	local color = typeof(precipitation.color) == "Color3" and precipitation.color or Color3.new(1, 1, 1)
	local size = tonumber(precipitation.size) or (kind == "snow" and 0.2 or 0.1)
	local transparency = math.clamp(tonumber(precipitation.transparency) or 0.2, 0, 1)
	local lifetime = tonumber(precipitation.lifetime) or (kind == "snow" and 3.6 or 0.55)
	local speed = tonumber(precipitation.speed) or (kind == "snow" and 16 or 92)

	particleEmitter.Texture = kind == "snow" and SNOW_TEXTURE or RAIN_TEXTURE
	particleEmitter.Color = ColorSequence.new(color)
	particleEmitter.Size = NumberSequence.new(size)
	particleEmitter.Transparency = NumberSequence.new(transparency)
	particleEmitter.LightEmission = kind == "snow" and 0.35 or 0.08
	particleEmitter.LightInfluence = 0.2
	particleEmitter.EmissionDirection = Enum.NormalId.Bottom
	particleEmitter.Lifetime = NumberRange.new(lifetime * 0.85, lifetime * 1.15)
	particleEmitter.SpreadAngle = kind == "snow" and Vector2.new(38, 38) or Vector2.new(8, 8)
	setNumberRangeProperty(particleEmitter, "Speed", speed)

	if kind == "snow" then
		particleEmitter.Acceleration = Vector3.new(wind.X * 1.2, -6, wind.Z * 1.2)
		particleEmitter.Drag = 3
		emitterPart.Size = Vector3.new(150, 1, 150)
	else
		particleEmitter.Acceleration = Vector3.new(wind.X * 2.2, -70, wind.Z * 2.2)
		particleEmitter.Drag = 0
		emitterPart.Size = Vector3.new(170, 1, 170)
	end
end

local function updateEmitterPosition(layer)
	if not emitterPart or not emitterPart.Parent then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local precipitation = type(layer.precipitation) == "table" and layer.precipitation or {}
	local kind = precipitation.kind == "snow" and "snow" or "rain"
	local height = kind == "snow" and 42 or 58
	emitterPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, height, 0))
end

local function scheduleNextThunder(layer, currentTime)
	local thunder = type(layer.thunder) == "table" and layer.thunder or {}
	local minDelay = math.max(3, tonumber(thunder.minDelay) or 18)
	local maxDelay = math.max(minDelay, tonumber(thunder.maxDelay) or 42)
	nextThunderAt = currentTime + minDelay + math.random() * (maxDelay - minDelay)
end

local function triggerLightning(layer, currentTime)
	flashStartedAt = currentTime
	flashDuration = 0.18 + math.random() * 0.22
	flashUntil = currentTime + flashDuration

	local sound = ensureThunderSound()
	if sound then
		pcall(function()
			sound.TimePosition = 0
			sound:Play()
		end)
	end
end

local function updateLightning(layer, currentTime)
	local thunder = type(layer.thunder) == "table" and layer.thunder or {}
	local chance = math.clamp(tonumber(thunder.chance) or 0, 0, 1)
	local precipitation = type(layer.precipitation) == "table" and layer.precipitation or {}
	local rate = tonumber(precipitation.rate) or 0

	if chance <= 0 or rate < 50 then
		nextThunderAt = 0
	else
		if nextThunderAt <= 0 then
			scheduleNextThunder(layer, currentTime)
		elseif currentTime >= nextThunderAt then
			if math.random() <= chance then
				triggerLightning(layer, currentTime)
			end
			scheduleNextThunder(layer, currentTime)
		end
	end

	local effect = ensureLightning()
	if currentTime < flashUntil then
		local alpha = 1 - math.clamp((currentTime - flashStartedAt) / flashDuration, 0, 1)
		local brightness = tonumber(thunder.flashBrightness) or 0.55
		effect.Brightness = brightness * alpha
		effect.Contrast = 0.12 * alpha
	else
		effect.Brightness = 0
		effect.Contrast = 0
	end
end

ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == WEATHER_FOLDER_NAME then
		weatherFolder = child
	end
end)

Remotes.WeatherStateUpdated.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) == "table" then
		latestSnapshot = snapshot
	end
end)

RunService.RenderStepped:Connect(function()
	local state = getWeatherState()
	if not state then
		if emitter then
			emitter.Enabled = false
			emitter.Rate = 0
		end
		return
	end

	local currentTime = getServerTime()
	local layer = Weather.SampleState(state, currentTime)
	configureEmitter(layer)
	updateEmitterPosition(layer)
	updateLightning(layer, currentTime)
end)
