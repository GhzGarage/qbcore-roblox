-- Centralized UI theme tokens for all Roblox-native QBCore UI.
-- Use Palette(name, overrides) so screens can share one look and still add small local keys.

local QBUITheme = {}

local function cloneMap(source)
	local copy = {}
	for key, value in pairs(source or {}) do
		copy[key] = value
	end
	return copy
end

QBUITheme.Tokens = {
	Radius = {
		sm = 6,
		md = 8,
		lg = 10,
		xl = 12,
	},
	Stroke = {
		defaultTransparency = 0.12,
		softTransparency = 0.25,
		thickness = 1,
	},
	TextSize = {
		sm = 12,
		md = 14,
		lg = 18,
		xl = 24,
	},
}

QBUITheme.Palettes = {
	Core = {
		page = Color3.fromRGB(12, 15, 20),
		shell = Color3.fromRGB(26, 31, 39),
		panel = Color3.fromRGB(32, 38, 48),
		panelSoft = Color3.fromRGB(38, 45, 56),
		input = Color3.fromRGB(20, 24, 31),
		stroke = Color3.fromRGB(74, 87, 103),
		strokeSoft = Color3.fromRGB(58, 70, 86),
		text = Color3.fromRGB(239, 243, 247),
		muted = Color3.fromRGB(158, 170, 184),
		green = Color3.fromRGB(62, 166, 105),
		blue = Color3.fromRGB(74, 143, 216),
		blueDark = Color3.fromRGB(48, 99, 157),
		gold = Color3.fromRGB(235, 184, 76),
		red = Color3.fromRGB(185, 73, 73),
		disabled = Color3.fromRGB(79, 89, 101),
	},
	Service = {
		page = Color3.fromRGB(10, 13, 18),
		shell = Color3.fromRGB(25, 31, 39),
		panel = Color3.fromRGB(32, 39, 49),
		panelSoft = Color3.fromRGB(38, 46, 58),
		input = Color3.fromRGB(19, 24, 31),
		stroke = Color3.fromRGB(73, 87, 104),
		strokeSoft = Color3.fromRGB(57, 69, 84),
		text = Color3.fromRGB(240, 244, 248),
		muted = Color3.fromRGB(157, 170, 184),
		green = Color3.fromRGB(65, 172, 110),
		blue = Color3.fromRGB(74, 143, 216),
		blueDark = Color3.fromRGB(48, 99, 157),
		gold = Color3.fromRGB(229, 181, 77),
		red = Color3.fromRGB(202, 79, 83),
		disabled = Color3.fromRGB(79, 89, 101),
	},
	Compact = {
		backdrop = Color3.fromRGB(7, 10, 14),
		panel = Color3.fromRGB(14, 18, 24),
		panelSoft = Color3.fromRGB(23, 29, 38),
		stroke = Color3.fromRGB(54, 65, 80),
		text = Color3.fromRGB(238, 242, 247),
		muted = Color3.fromRGB(151, 163, 180),
		green = Color3.fromRGB(38, 166, 112),
		blue = Color3.fromRGB(52, 126, 190),
		red = Color3.fromRGB(184, 67, 67),
	},
	Utility = {
		panel = Color3.fromRGB(24, 30, 38),
		panelSoft = Color3.fromRGB(37, 44, 55),
		stroke = Color3.fromRGB(75, 88, 106),
		text = Color3.fromRGB(240, 244, 248),
		muted = Color3.fromRGB(158, 170, 184),
		green = Color3.fromRGB(62, 166, 105),
		accent = Color3.fromRGB(235, 184, 76),
	},
}

function QBUITheme.Palette(name, overrides)
	local palette = cloneMap(QBUITheme.Palettes[name] or QBUITheme.Palettes.Core)
	for key, value in pairs(overrides or {}) do
		palette[key] = value
	end
	return palette
end

return QBUITheme
