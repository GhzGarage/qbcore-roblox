-- Shared weather presets and blending helpers.
-- The server owns the authoritative state; clients use this table to render it.

local Weather = {}

Weather.Defaults = {
	Enabled = true,
	Dynamic = true,
	StartWeather = "CLEAR",
	TransitionSeconds = 45,
	MinWeatherSeconds = 600,
	MaxWeatherSeconds = 1200,
}

Weather.Order = {
	"CLEAR",
	"EXTRASUNNY",
	"CLOUDS",
	"OVERCAST",
	"FOG",
	"RAIN",
	"THUNDER",
	"SNOW",
}

Weather.Presets = {
	CLEAR = {
		label = "Clear",
		weight = 34,
		wind = Vector3.new(4, 0, 2),
		clouds = { Cover = 0.18, Density = 0.22, ColorAlpha = 0.05, Color = Color3.fromRGB(255, 255, 255) },
		lighting = { BrightnessMultiplier = 1, ExposureCompensationAdd = 0 },
		atmosphere = { DensityAdd = 0, HazeAdd = 0, GlareAdd = 0 },
		colorCorrection = { SaturationAdd = 0, ContrastAdd = 0, BrightnessAdd = 0 },
		sunRays = { IntensityMultiplier = 1 },
		precipitation = { rate = 0, kind = "none" },
		thunder = { chance = 0 },
	},

	EXTRASUNNY = {
		label = "Extra Sunny",
		weight = 18,
		wind = Vector3.new(2, 0, 1),
		clouds = { Cover = 0.06, Density = 0.08, ColorAlpha = 0.05, Color = Color3.fromRGB(255, 255, 255) },
		lighting = { BrightnessMultiplier = 1.08, ExposureCompensationAdd = 0.04, ShadowSoftnessAdd = -0.04 },
		atmosphere = { DensityAdd = -0.04, HazeAdd = -0.35, GlareAdd = 0.04 },
		colorCorrection = { SaturationAdd = 0.04, ContrastAdd = 0.02, BrightnessAdd = 0.01 },
		sunRays = { IntensityMultiplier = 1.25 },
		precipitation = { rate = 0, kind = "none" },
		thunder = { chance = 0 },
	},

	CLOUDS = {
		label = "Cloudy",
		weight = 30,
		wind = Vector3.new(8, 0, 3),
		clouds = { Cover = 0.56, Density = 0.52, ColorAlpha = 0.22, Color = Color3.fromRGB(214, 220, 226) },
		lighting = { BrightnessMultiplier = 0.92, ExposureCompensationAdd = -0.03, ShadowSoftnessAdd = 0.08 },
		atmosphere = { DensityAdd = 0.02, HazeAdd = 0.25, GlareAdd = -0.03 },
		colorCorrection = { SaturationAdd = -0.04, ContrastAdd = -0.01, BrightnessAdd = -0.01 },
		sunRays = { IntensityMultiplier = 0.65 },
		precipitation = { rate = 0, kind = "none" },
		thunder = { chance = 0 },
	},

	OVERCAST = {
		label = "Overcast",
		weight = 24,
		wind = Vector3.new(12, 0, 5),
		clouds = { Cover = 0.82, Density = 0.76, ColorAlpha = 0.42, Color = Color3.fromRGB(150, 158, 170) },
		lighting = { BrightnessMultiplier = 0.78, ExposureCompensationAdd = -0.1, ShadowSoftnessAdd = 0.2 },
		atmosphere = { DensityAdd = 0.06, HazeAdd = 0.75, GlareAdd = -0.08 },
		colorCorrection = { SaturationAdd = -0.12, ContrastAdd = -0.02, BrightnessAdd = -0.03 },
		sunRays = { IntensityMultiplier = 0.22 },
		precipitation = { rate = 0, kind = "none" },
		thunder = { chance = 0 },
	},

	FOG = {
		label = "Foggy",
		weight = 12,
		wind = Vector3.new(2, 0, 1),
		clouds = { Cover = 0.66, Density = 0.7, ColorAlpha = 0.45, Color = Color3.fromRGB(190, 196, 202) },
		lighting = { BrightnessMultiplier = 0.84, ExposureCompensationAdd = -0.02, ShadowSoftnessAdd = 0.28 },
		atmosphere = {
			DensityAdd = 0.18,
			HazeAdd = 2.4,
			GlareAdd = -0.05,
			ColorAlpha = 0.3,
			Color = Color3.fromRGB(188, 194, 200),
		},
		colorCorrection = { SaturationAdd = -0.18, ContrastAdd = -0.08, BrightnessAdd = -0.015 },
		sunRays = { IntensityMultiplier = 0.35 },
		precipitation = { rate = 0, kind = "none" },
		thunder = { chance = 0 },
	},

	RAIN = {
		label = "Rain",
		weight = 18,
		wind = Vector3.new(18, 0, 8),
		clouds = { Cover = 0.9, Density = 0.86, ColorAlpha = 0.58, Color = Color3.fromRGB(108, 118, 132) },
		lighting = { BrightnessMultiplier = 0.7, ExposureCompensationAdd = -0.12, ShadowSoftnessAdd = 0.32 },
		atmosphere = {
			DensityAdd = 0.1,
			HazeAdd = 1.25,
			GlareAdd = -0.12,
			ColorAlpha = 0.22,
			Color = Color3.fromRGB(140, 150, 166),
		},
		colorCorrection = {
			SaturationAdd = -0.2,
			ContrastAdd = -0.03,
			BrightnessAdd = -0.04,
			TintColorAlpha = 0.12,
			TintColor = Color3.fromRGB(202, 218, 235),
		},
		bloom = { IntensityAdd = 0.04, ThresholdAdd = -0.25 },
		sunRays = { IntensityMultiplier = 0.12 },
		precipitation = {
			kind = "rain",
			rate = 520,
			speed = 96,
			lifetime = 0.58,
			size = 0.11,
			transparency = 0.25,
			color = Color3.fromRGB(185, 210, 235),
		},
		thunder = { chance = 0.12, minDelay = 26, maxDelay = 55 },
	},

	THUNDER = {
		label = "Thunder",
		weight = 8,
		wind = Vector3.new(26, 0, 12),
		clouds = { Cover = 0.98, Density = 0.95, ColorAlpha = 0.72, Color = Color3.fromRGB(62, 70, 84) },
		lighting = { BrightnessMultiplier = 0.58, ExposureCompensationAdd = -0.18, ShadowSoftnessAdd = 0.4 },
		atmosphere = {
			DensityAdd = 0.14,
			HazeAdd = 1.8,
			GlareAdd = -0.18,
			ColorAlpha = 0.38,
			Color = Color3.fromRGB(105, 116, 136),
		},
		colorCorrection = {
			SaturationAdd = -0.26,
			ContrastAdd = 0.03,
			BrightnessAdd = -0.065,
			TintColorAlpha = 0.22,
			TintColor = Color3.fromRGB(190, 205, 230),
		},
		bloom = { IntensityAdd = 0.08, ThresholdAdd = -0.35 },
		sunRays = { IntensityMultiplier = 0.05 },
		precipitation = {
			kind = "rain",
			rate = 850,
			speed = 120,
			lifetime = 0.52,
			size = 0.13,
			transparency = 0.18,
			color = Color3.fromRGB(174, 205, 236),
		},
		thunder = { chance = 1, minDelay = 8, maxDelay = 20, flashBrightness = 0.75 },
	},

	SNOW = {
		label = "Snow",
		weight = 6,
		wind = Vector3.new(9, 0, 4),
		clouds = { Cover = 0.88, Density = 0.82, ColorAlpha = 0.54, Color = Color3.fromRGB(218, 224, 230) },
		lighting = { BrightnessMultiplier = 0.9, ExposureCompensationAdd = 0.04, ShadowSoftnessAdd = 0.35 },
		atmosphere = {
			DensityAdd = 0.1,
			HazeAdd = 1.1,
			GlareAdd = -0.05,
			ColorAlpha = 0.28,
			Color = Color3.fromRGB(220, 228, 238),
		},
		colorCorrection = {
			SaturationAdd = -0.22,
			ContrastAdd = -0.04,
			BrightnessAdd = 0.015,
			TintColorAlpha = 0.18,
			TintColor = Color3.fromRGB(225, 236, 255),
		},
		sunRays = { IntensityMultiplier = 0.28 },
		precipitation = {
			kind = "snow",
			rate = 250,
			speed = 18,
			lifetime = 3.8,
			size = 0.2,
			transparency = 0.08,
			color = Color3.fromRGB(245, 250, 255),
		},
		thunder = { chance = 0 },
	},
}

local BLACKOUT_LAYER = {
	lighting = {
		BrightnessMultiplier = 0.38,
		ExposureCompensationAdd = -0.35,
		AmbientAlpha = 0.32,
		Ambient = Color3.fromRGB(8, 10, 16),
		OutdoorAmbientAlpha = 0.35,
		OutdoorAmbient = Color3.fromRGB(20, 24, 38),
	},
	colorCorrection = {
		BrightnessAdd = -0.08,
		ContrastAdd = 0.08,
		SaturationAdd = -0.08,
		TintColorAlpha = 0.08,
		TintColor = Color3.fromRGB(185, 205, 255),
	},
	bloom = { ThresholdAdd = -0.4, IntensityAdd = 0.08 },
}

local function clamp01(value)
	return math.clamp(tonumber(value) or 0, 0, 1)
end

local function normalizeName(value)
	if type(value) ~= "string" then
		return nil
	end
	local compact = value:upper():gsub("[^%w]+", "")
	if compact == "" then
		return nil
	end
	if compact == "SUNNY" then
		compact = "EXTRASUNNY"
	elseif compact == "CLOUDY" then
		compact = "CLOUDS"
	elseif compact == "STORM" or compact == "STORMY" then
		compact = "THUNDER"
	elseif compact == "FOGGY" then
		compact = "FOG"
	end
	return Weather.Presets[compact] and compact or nil
end

local function lerpValue(left, right, alpha)
	if typeof(left) == "Color3" and typeof(right) == "Color3" then
		return left:Lerp(right, alpha)
	elseif typeof(left) == "Vector3" and typeof(right) == "Vector3" then
		return left:Lerp(right, alpha)
	elseif type(left) == "number" and type(right) == "number" then
		return left + (right - left) * alpha
	elseif right ~= nil and alpha >= 0.5 then
		return right
	end
	return left
end

local function blendTables(left, right, alpha)
	left = type(left) == "table" and left or {}
	right = type(right) == "table" and right or {}

	local out = {}
	for key, value in pairs(left) do
		local other = right[key]
		if type(value) == "table" and type(other) == "table" then
			out[key] = blendTables(value, other, alpha)
		else
			out[key] = other ~= nil and lerpValue(value, other, alpha) or value
		end
	end
	for key, value in pairs(right) do
		if out[key] == nil then
			out[key] = value
		end
	end
	return out
end

local function applyColorBlend(current, layer, colorKey, alphaKey)
	local color = layer[colorKey]
	local alpha = clamp01(layer[alphaKey])
	if typeof(current) == "Color3" and typeof(color) == "Color3" and alpha > 0 then
		return current:Lerp(color, alpha)
	end
	return current
end

local function addNumber(value, amount, minValue, maxValue)
	local out = (tonumber(value) or 0) + (tonumber(amount) or 0)
	if minValue ~= nil or maxValue ~= nil then
		out = math.clamp(out, minValue or -math.huge, maxValue or math.huge)
	end
	return out
end

local function multiplyNumber(value, multiplier, minValue, maxValue)
	local out = (tonumber(value) or 0) * (tonumber(multiplier) or 1)
	if minValue ~= nil or maxValue ~= nil then
		out = math.clamp(out, minValue or -math.huge, maxValue or math.huge)
	end
	return out
end

function Weather.NormalizeName(value)
	return normalizeName(value)
end

function Weather.GetPreset(value)
	local name = normalizeName(value) or Weather.Defaults.StartWeather
	return Weather.Presets[name], name
end

function Weather.GetPresetList()
	local list = {}
	for _, name in ipairs(Weather.Order) do
		local preset = Weather.Presets[name]
		if preset then
			list[#list + 1] = {
				name = name,
				label = preset.label or name,
			}
		end
	end
	return list
end

function Weather.GetRandomNext(currentName)
	local totalWeight = 0
	for _, name in ipairs(Weather.Order) do
		local preset = Weather.Presets[name]
		if preset and name ~= currentName then
			totalWeight += math.max(0, tonumber(preset.weight) or 0)
		end
	end

	if totalWeight <= 0 then
		return Weather.Defaults.StartWeather
	end

	local roll = math.random() * totalWeight
	local cursor = 0
	for _, name in ipairs(Weather.Order) do
		local preset = Weather.Presets[name]
		if preset and name ~= currentName then
			cursor += math.max(0, tonumber(preset.weight) or 0)
			if roll <= cursor then
				return name
			end
		end
	end

	return Weather.Defaults.StartWeather
end

function Weather.BlendPresets(currentName, nextName, alpha)
	local current = Weather.Presets[normalizeName(currentName) or Weather.Defaults.StartWeather]
		or Weather.Presets.CLEAR
	local nextPreset = Weather.Presets[normalizeName(nextName) or normalizeName(currentName) or Weather.Defaults.StartWeather]
		or current
	return blendTables(current, nextPreset, clamp01(alpha))
end

function Weather.GetTransitionAlpha(state, now)
	state = type(state) == "table" and state or {}
	local duration = tonumber(state.transitionDuration) or 0
	if duration <= 0 then
		return 1
	end

	local startedAt = tonumber(state.transitionStartedAt) or now
	return clamp01(((tonumber(now) or 0) - startedAt) / duration)
end

function Weather.SampleState(state, now)
	state = type(state) == "table" and state or {}
	local alpha = Weather.GetTransitionAlpha(state, now)
	return Weather.BlendPresets(state.currentWeather, state.nextWeather or state.currentWeather, alpha), alpha
end

function Weather.ApplyLayerToFrame(frame, layer, blackout)
	if type(frame) ~= "table" or type(layer) ~= "table" then
		return frame
	end

	local lighting = type(layer.lighting) == "table" and layer.lighting or {}
	frame.Brightness = multiplyNumber(frame.Brightness, lighting.BrightnessMultiplier, 0, 10)
	frame.Brightness = addNumber(frame.Brightness, lighting.BrightnessAdd, 0, 10)
	frame.ExposureCompensation = addNumber(frame.ExposureCompensation, lighting.ExposureCompensationAdd, -3, 3)
	frame.ShadowSoftness = addNumber(frame.ShadowSoftness, lighting.ShadowSoftnessAdd, 0, 1)
	frame.Ambient = applyColorBlend(frame.Ambient, lighting, "Ambient", "AmbientAlpha")
	frame.OutdoorAmbient = applyColorBlend(frame.OutdoorAmbient, lighting, "OutdoorAmbient", "OutdoorAmbientAlpha")

	local colorCorrection = type(frame.ColorCorrection) == "table" and frame.ColorCorrection or {}
	local ccLayer = type(layer.colorCorrection) == "table" and layer.colorCorrection or {}
	colorCorrection.Saturation = addNumber(colorCorrection.Saturation, ccLayer.SaturationAdd, -1, 1)
	colorCorrection.Contrast = addNumber(colorCorrection.Contrast, ccLayer.ContrastAdd, -1, 1)
	colorCorrection.Brightness = addNumber(colorCorrection.Brightness, ccLayer.BrightnessAdd, -1, 1)
	colorCorrection.TintColor = applyColorBlend(colorCorrection.TintColor, ccLayer, "TintColor", "TintColorAlpha")
	frame.ColorCorrection = colorCorrection

	local atmosphere = type(frame.Atmosphere) == "table" and frame.Atmosphere or {}
	local atmLayer = type(layer.atmosphere) == "table" and layer.atmosphere or {}
	atmosphere.Density = addNumber(atmosphere.Density, atmLayer.DensityAdd, 0, 1)
	atmosphere.Haze = addNumber(atmosphere.Haze, atmLayer.HazeAdd, 0, 10)
	atmosphere.Glare = addNumber(atmosphere.Glare, atmLayer.GlareAdd, 0, 10)
	atmosphere.Offset = addNumber(atmosphere.Offset, atmLayer.OffsetAdd, -1, 1)
	atmosphere.Color = applyColorBlend(atmosphere.Color, atmLayer, "Color", "ColorAlpha")
	atmosphere.Decay = applyColorBlend(atmosphere.Decay, atmLayer, "Decay", "DecayAlpha")
	frame.Atmosphere = atmosphere

	local bloom = type(frame.Bloom) == "table" and frame.Bloom or {}
	local bloomLayer = type(layer.bloom) == "table" and layer.bloom or {}
	bloom.Intensity = addNumber(bloom.Intensity, bloomLayer.IntensityAdd, 0, 10)
	bloom.Threshold = addNumber(bloom.Threshold, bloomLayer.ThresholdAdd, 0, 10)
	frame.Bloom = bloom

	local sunRays = type(frame.SunRays) == "table" and frame.SunRays or {}
	local sunLayer = type(layer.sunRays) == "table" and layer.sunRays or {}
	sunRays.Intensity = multiplyNumber(sunRays.Intensity, sunLayer.IntensityMultiplier, 0, 1)
	sunRays.Intensity = addNumber(sunRays.Intensity, sunLayer.IntensityAdd, 0, 1)
	frame.SunRays = sunRays

	local clouds = type(layer.clouds) == "table" and layer.clouds or {}
	if clouds.Cover ~= nil then
		frame.CloudCover = math.clamp(tonumber(clouds.Cover) or 0, 0, 1)
	end
	if clouds.Density ~= nil then
		frame.CloudDensity = math.clamp(tonumber(clouds.Density) or 0, 0, 1)
	end
	frame.CloudColor = applyColorBlend(frame.CloudColor, clouds, "Color", "ColorAlpha")

	if blackout == true then
		Weather.ApplyLayerToFrame(frame, BLACKOUT_LAYER, false)
	end

	return frame
end

return Weather
