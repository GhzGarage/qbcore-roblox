-- Centralized resolution scaling helpers for all Roblox-native QBCore UI.

local QBUIScale = {}

QBUIScale.Profiles = {
	HUD = {
		baseX = 980,
		baseY = 720,
		min = 0.58,
		max = 1,
	},
	Panel = {
		baseX = 960,
		baseY = 720,
		min = 0.58,
		max = 1,
	},
	WidePanel = {
		baseX = 1000,
		baseY = 680,
		min = 0.52,
		max = 1,
	},
	Dialog = {
		baseX = 760,
		baseY = 640,
		min = 0.76,
		max = 1,
	},
	CompactDialog = {
		baseX = 620,
		baseY = 420,
		min = 0.72,
		max = 1,
	},
	Phone = {
		baseX = 390,
		baseY = 720,
		min = 0.42,
		max = 1,
	},
}

local function clampScale(viewport, profile)
	profile = profile or QBUIScale.Profiles.Panel
	local xScale = viewport.X / profile.baseX
	local yScale = viewport.Y / profile.baseY
	return math.clamp(math.min(xScale, yScale), profile.min, profile.max)
end

function QBUIScale.GetViewportSize(camera)
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

function QBUIScale.FromViewport(viewport, profile)
	return clampScale(viewport, profile)
end

function QBUIScale.FromCamera(camera, profile)
	return clampScale(QBUIScale.GetViewportSize(camera), profile)
end

return QBUIScale
