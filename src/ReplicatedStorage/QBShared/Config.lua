-- Roblox port of config.lua. GTA5-native settings with no Roblox equivalent were dropped.

local Config = {}

-- Mirrors the place's Max Players setting (Game Settings -> Places); scripts can't
-- change the real cap, so this is read-only info. Falls back to 48 in Studio tests
-- where MaxPlayers can report 0.
local placeMaxPlayers = game:GetService("Players").MaxPlayers
Config.MaxPlayers = placeMaxPlayers > 0 and placeMaxPlayers or 48

Config.UpdateInterval = 5 * 60 -- seconds between periodic autosaves (was minutes in the FiveM version)
Config.StatusInterval = 120 -- seconds between hunger/thirst ticks
Config.StatusDecay = {
	Enabled = true,
	Hunger = 1, -- percent removed every StatusInterval
	Thirst = 1, -- percent removed every StatusInterval
}

Config.World = {
	ForceClearNoon = true, -- master switch for everything below
	ClockTime = 0, -- static time of day; only used when Time.Enabled below is false
	-- qb-weathersync-style time progression, advanced by TimeSyncService.lua.
	Time = {
		Enabled = true, -- advance the clock over real time; false = freeze at ClockTime above
		StartHour = 12, -- ClockTime when the server boots (0-24)
		DayLengthMinutes = 48, -- real minutes per full in-game day (48 matches qb-weathersync's default pace)
		Freeze = false, -- boot with the clock frozen; toggle at runtime with /freezetime
	},
	-- NOTE: Lighting.Technology must be set to "Future" manually in Studio; scripts
	-- can't change it. (Unified Lighting beta: use LightingStyle "Realistic" instead.)
	Brightness = 2.5,
	EnvironmentDiffuseScale = 1,
	EnvironmentSpecularScale = 1,
	ShadowSoftness = 0.2, -- 0 = razor sharp, 1 = overcast-diffuse; 0.2 suits clear noon
	Ambient = Color3.fromRGB(70, 70, 70), -- kept dark so shadows have depth
	OutdoorAmbient = Color3.fromRGB(150, 150, 150),
	-- Volumetric clouds; Cover/Density are the shape, TimeCycle below animates the color.
	CloudCover = 0.45,
	CloudDensity = 0.7,
	-- Structural sky setup, applied once by the server at boot.
	Sky = {
		Create = true, -- create a Sky under Lighting if none exists; a custom Studio skybox is left alone
		StarCount = 4500,
		MoonAngularSize = 14,
		GeographicLatitude = 35, -- tilts the sun's arc low across the sky -> longer golden hours
	},
	-- Post-processing effects, created under Lighting (the Atmosphere replaces classic fog).
	ColorCorrection = {
		Saturation = 0.2,
		Contrast = 0.1,
		Brightness = 0,
		TintColor = Color3.fromRGB(255, 248, 240), -- subtle warm sunlight
	},
	Atmosphere = {
		Density = 0.35,
		Offset = 0.25,
		Haze = 1.5,
		Glare = 0,
		Color = Color3.fromRGB(199, 199, 199),
		Decay = Color3.fromRGB(104, 112, 124), -- bluish-gray tint on distant shadows
	},
	SunRays = {
		Intensity = 0.05,
		Spread = 0.75,
	},
	Bloom = {
		Intensity = 0.3,
		Size = 24,
		Threshold = 2, -- only real light sources / neon bloom, not the baseplate
	},
	DepthOfField = {
		FocusDistance = 50,
		InFocusRadius = 40,
		FarIntensity = 0.2,
		NearIntensity = 0,
	},
	-- Time-of-day color grading. Each client (QBTimeCycle) lerps every property between
	-- the two keyframes around the current ClockTime, wrapping across midnight. The sun
	-- rises at 6:00 and sets at 18:00. Every keyframe must carry the full property set;
	-- the flat values above are the boot-time look and take over if this is disabled.
	TimeCycle = {
		Enabled = true,
		Keyframes = {
			{ -- midnight: cool moonlit blue; exposure lifted so gameplay stays readable
				Hour = 0,
				Brightness = 1.2,
				ExposureCompensation = 0.35,
				ShadowSoftness = 0.5,
				Ambient = Color3.fromRGB(12, 14, 22),
				OutdoorAmbient = Color3.fromRGB(28, 34, 58),
				SunAngularSize = 21,
				CloudColor = Color3.fromRGB(70, 78, 100),
				ColorCorrection = { Saturation = -0.05, Contrast = 0.12, TintColor = Color3.fromRGB(198, 212, 255) },
				Atmosphere = {
					Density = 0.32,
					Offset = 0.2,
					Haze = 1.8,
					Glare = 0,
					Color = Color3.fromRGB(110, 118, 140),
					Decay = Color3.fromRGB(46, 54, 86),
				},
				SunRays = { Intensity = 0.01 },
				Bloom = { Intensity = 0.5, Threshold = 1.1 }, -- low threshold: streetlights/neon glow at night
			},
			{ -- pre-dawn: sky starts lifting toward the east
				Hour = 5,
				Brightness = 1.4,
				ExposureCompensation = 0.3,
				ShadowSoftness = 0.5,
				Ambient = Color3.fromRGB(16, 17, 26),
				OutdoorAmbient = Color3.fromRGB(40, 44, 66),
				SunAngularSize = 23,
				CloudColor = Color3.fromRGB(92, 96, 116),
				ColorCorrection = { Saturation = 0, Contrast = 0.12, TintColor = Color3.fromRGB(206, 214, 250) },
				Atmosphere = {
					Density = 0.34,
					Offset = 0.3,
					Haze = 2,
					Glare = 0.05,
					Color = Color3.fromRGB(126, 128, 148),
					Decay = Color3.fromRGB(62, 64, 92),
				},
				SunRays = { Intensity = 0.03 },
				Bloom = { Intensity = 0.48, Threshold = 1.15 },
			},
			{ -- sunrise: warm pink-orange, big low sun, haze catches the light
				Hour = 6.5,
				Brightness = 2,
				ExposureCompensation = 0.1,
				ShadowSoftness = 0.45,
				Ambient = Color3.fromRGB(48, 42, 44),
				OutdoorAmbient = Color3.fromRGB(125, 100, 95),
				SunAngularSize = 25,
				CloudColor = Color3.fromRGB(235, 180, 140),
				ColorCorrection = { Saturation = 0.15, Contrast = 0.1, TintColor = Color3.fromRGB(255, 214, 178) },
				Atmosphere = {
					Density = 0.38,
					Offset = 0.5,
					Haze = 2.3,
					Glare = 0.35,
					Color = Color3.fromRGB(222, 170, 128),
					Decay = Color3.fromRGB(150, 104, 88),
				},
				SunRays = { Intensity = 0.13 },
				Bloom = { Intensity = 0.42, Threshold = 1.4 },
			},
			{ -- morning: fresh, clean, slightly cool
				Hour = 9,
				Brightness = 2.4,
				ExposureCompensation = 0,
				ShadowSoftness = 0.25,
				Ambient = Color3.fromRGB(62, 64, 68),
				OutdoorAmbient = Color3.fromRGB(140, 145, 150),
				SunAngularSize = 14,
				CloudColor = Color3.fromRGB(250, 250, 252),
				ColorCorrection = { Saturation = 0.18, Contrast = 0.1, TintColor = Color3.fromRGB(255, 244, 234) },
				Atmosphere = {
					Density = 0.35,
					Offset = 0.25,
					Haze = 1.7,
					Glare = 0.05,
					Color = Color3.fromRGB(204, 206, 210),
					Decay = Color3.fromRGB(110, 116, 128),
				},
				SunRays = { Intensity = 0.07 },
				Bloom = { Intensity = 0.32, Threshold = 1.8 },
			},
			{ -- noon: the original "clear noon" grade this config shipped with
				Hour = 12,
				Brightness = 2.5,
				ExposureCompensation = 0,
				ShadowSoftness = 0.2,
				Ambient = Color3.fromRGB(70, 70, 70),
				OutdoorAmbient = Color3.fromRGB(150, 150, 150),
				SunAngularSize = 12,
				CloudColor = Color3.fromRGB(255, 255, 255),
				ColorCorrection = { Saturation = 0.2, Contrast = 0.1, TintColor = Color3.fromRGB(255, 248, 240) },
				Atmosphere = {
					Density = 0.35,
					Offset = 0.25,
					Haze = 1.5,
					Glare = 0,
					Color = Color3.fromRGB(199, 199, 199),
					Decay = Color3.fromRGB(104, 112, 124),
				},
				SunRays = { Intensity = 0.05 },
				Bloom = { Intensity = 0.3, Threshold = 2 },
			},
			{ -- golden hour: everything warms up, shadows stretch and soften
				Hour = 16.5,
				Brightness = 2.3,
				ExposureCompensation = 0,
				ShadowSoftness = 0.3,
				Ambient = Color3.fromRGB(66, 60, 52),
				OutdoorAmbient = Color3.fromRGB(150, 135, 115),
				SunAngularSize = 18,
				CloudColor = Color3.fromRGB(255, 235, 210),
				ColorCorrection = { Saturation = 0.22, Contrast = 0.11, TintColor = Color3.fromRGB(255, 231, 200) },
				Atmosphere = {
					Density = 0.36,
					Offset = 0.35,
					Haze = 2,
					Glare = 0.18,
					Color = Color3.fromRGB(214, 190, 160),
					Decay = Color3.fromRGB(128, 108, 96),
				},
				SunRays = { Intensity = 0.1 },
				Bloom = { Intensity = 0.35, Threshold = 1.7 },
			},
			{ -- sunset: the showpiece -- huge orange sun, glare, god rays, lit clouds
				Hour = 18.2,
				Brightness = 1.9,
				ExposureCompensation = 0.05,
				ShadowSoftness = 0.4,
				Ambient = Color3.fromRGB(52, 42, 40),
				OutdoorAmbient = Color3.fromRGB(120, 88, 76),
				SunAngularSize = 26,
				CloudColor = Color3.fromRGB(255, 170, 120),
				ColorCorrection = { Saturation = 0.25, Contrast = 0.13, TintColor = Color3.fromRGB(255, 206, 160) },
				Atmosphere = {
					Density = 0.4,
					Offset = 0.6,
					Haze = 2.6,
					Glare = 0.55,
					Color = Color3.fromRGB(226, 152, 108),
					Decay = Color3.fromRGB(158, 96, 74),
				},
				SunRays = { Intensity = 0.16 },
				Bloom = { Intensity = 0.45, Threshold = 1.35 },
			},
			{ -- blue hour: sun just gone, deep desaturated blues before true night
				Hour = 19.5,
				Brightness = 1.4,
				ExposureCompensation = 0.2,
				ShadowSoftness = 0.5,
				Ambient = Color3.fromRGB(26, 26, 40),
				OutdoorAmbient = Color3.fromRGB(58, 62, 96),
				SunAngularSize = 21,
				CloudColor = Color3.fromRGB(110, 115, 150),
				ColorCorrection = { Saturation = 0.05, Contrast = 0.12, TintColor = Color3.fromRGB(196, 204, 250) },
				Atmosphere = {
					Density = 0.36,
					Offset = 0.35,
					Haze = 2.1,
					Glare = 0.05,
					Color = Color3.fromRGB(140, 145, 175),
					Decay = Color3.fromRGB(70, 74, 110),
				},
				SunRays = { Intensity = 0.03 },
				Bloom = { Intensity = 0.5, Threshold = 1.2 },
			},
			{ -- night: settles into the midnight look (wraps back to Hour = 0)
				Hour = 21,
				Brightness = 1.2,
				ExposureCompensation = 0.35,
				ShadowSoftness = 0.5,
				Ambient = Color3.fromRGB(12, 14, 22),
				OutdoorAmbient = Color3.fromRGB(30, 36, 60),
				SunAngularSize = 21,
				CloudColor = Color3.fromRGB(72, 80, 102),
				ColorCorrection = { Saturation = -0.05, Contrast = 0.12, TintColor = Color3.fromRGB(198, 212, 255) },
				Atmosphere = {
					Density = 0.32,
					Offset = 0.2,
					Haze = 1.8,
					Glare = 0,
					Color = Color3.fromRGB(112, 120, 142),
					Decay = Color3.fromRGB(48, 56, 88),
				},
				SunRays = { Intensity = 0.01 },
				Bloom = { Intensity = 0.5, Threshold = 1.1 },
			},
		},
	},
}

Config.Weather = {
	Enabled = true,
	Dynamic = true,
	StartWeather = "CLEAR",
	TransitionSeconds = 45,
	MinWeatherSeconds = 10 * 60,
	MaxWeatherSeconds = 20 * 60,
	Freeze = false,
	Blackout = false,
	-- Tag Light instances, or models/folders containing Light instances, with one
	-- of these tags to let /blackout toggle them.
	BlackoutLightTags = { "QBBlackoutLight", "StreetLight" },
	-- Optional uploaded/allowed thunder sound. Leave blank for visual-only thunder.
	ThunderSoundId = "",
}

Config.Money = {
	MoneyTypes = { cash = 500, bank = 5000, crypto = 0 }, -- starting balances
	DontAllowMinus = { cash = true, crypto = true }, -- moneytype -> true
	MinusLimit = -5000,
	PayCheckEnabled = true,
	PayCheckTimeOut = 10 * 60, -- seconds between paycheck rounds
	PayCheckOnDutyOnly = true, -- false pays every loaded character, regardless of duty state
	-- When true, each paycheck is debited from the matching Banking society account first.
	-- Leave false to keep the usual QBCore behavior where paychecks do not cost society funds.
	PayCheckSociety = false,
}

Config.Banking = {
	Enabled = true,
	PromptDistance = 10, -- studs; distance at which Roblox shows the bank prompt
	ActionDistance = 14, -- server-side allowance for opening/submitting banking actions
	MaxTransactionAmount = 1000000,
	MaxStatements = 50, -- newest per-character checking-account statements retained
	CardPrice = 50,
	UseDailyWithdrawalLimit = true,
	DailyWithdrawalLimit = 5000,
	Society = {
		Enabled = true,
		DefaultBalance = 0,
		-- Optional per-job first-use balances, for example: police = 25000.
		StartingBalances = {},
	},
	SharedAccounts = {
		Enabled = true,
		MaxOwned = 2,
		MaxMembers = 10, -- additional members per account; the owner is not counted
		MinNameLength = 3,
		MaxNameLength = 32,
	},
	Locations = {
		{
			id = "test_bank",
			label = "QBCore Bank",
			position = Vector3.new(6.21, 3.45, -1492.88),
		},
	},
	ATMLocations = {
		{
			id = "test_atm",
			label = "QBCore ATM",
			position = Vector3.new(26.21, 3.45, -1492.88),
		},
	},
}

Config.VehicleShop = {
	Enabled = true,
	Label = "Premium Deluxe Motorsport",
	PromptDistance = 10,
	ActionDistance = 14,
	DefaultPrice = 0,
	AllowDuplicatePurchases = false,
	TestDriveSeconds = 60,
	MinimumDownPercent = 10,
	MaximumPayments = 24,
	PaymentIntervalHours = 24,
	ExcludedVehicles = { taxi = true, police = true },
	Prices = {}, -- optional per-vehicle overrides; shared vehicle prices currently default to $0
	ShowroomSpots = {
		{
			id = "showroom_1",
			vehicle = "dune_buggy_beige",
			position = Vector3.new(-146.919, 0.997, -36.539),
			heading = -45,
		},
		{
			id = "showroom_2",
			vehicle = "light_utility_black",
			position = Vector3.new(-146.958, 0.997, -55.219),
			heading = -45,
		},
		{ id = "showroom_3", vehicle = "pickup_blue", position = Vector3.new(-146.998, 0.997, -73.758), heading = -45 },
		{ id = "showroom_4", vehicle = "sports", position = Vector3.new(-147.036, 0.997, -91.908), heading = -45 },
	},
	FinanceSpot = {
		id = "finance",
		position = Vector3.new(-143.852, 4.707, -115.063),
	},
	VehicleSpawn = {
		position = Vector3.new(-208.801, 2.524, -146.146),
		heading = 180,
	},
}

Config.Garages = {
	Enabled = true,
	PromptDistance = 10,
	ActionDistance = 16,
	StoreDistance = 20,
	SpawnClearRadius = 12,
	AutoRespawn = true, -- return out vehicles to their last/default garage when the owner leaves
	SharedGarages = false, -- false restricts retrieval to the garage where the vehicle was stored
	DefaultGarage = "garage_1",
	Locations = {
		{
			id = "garage_1",
			label = "Public Garage 1",
			type = "public",
			takeVehicle = Vector3.new(0, 0, 0),
			spawnPoints = { { position = Vector3.new(0, 0, 0), heading = 0 } },
		},
		{
			id = "garage_2",
			label = "Public Garage 2",
			type = "public",
			takeVehicle = Vector3.new(0, 0, 0),
			spawnPoints = { { position = Vector3.new(0, 0, 0), heading = 0 } },
		},
	},
}

-- Boss/crew management locations. A location with no `organization` restriction
-- follows the boss's current job or crew, which makes these two origin placeholders
-- useful until each headquarters has its final map position. Copy a location and set
-- organization = "police" (or a crew id) when an office should be organization-specific.
Config.Management = {
	Enabled = true,
	PromptDistance = 10,
	ActionDistance = 14,
	HireDistance = 12,
	Locations = {
		{
			id = "job_management_1",
			label = "Job Management",
			type = "job",
			position = Vector3.new(0, 0, 0),
		},
		{
			id = "crew_management_1",
			label = "Crew Management",
			type = "crew",
			position = Vector3.new(0, 0, 0),
		},
	},
}

Config.Inventory = {
	Slots = 30,
	HotbarSlots = 5,
	MaxWeight = 120000, -- grams, matching QBCore-style item weights
	MaxStack = 999,
	GiveDistance = 10,
	StarterItems = {
		{ name = "sandwich", amount = 2, slot = 1 },
		{ name = "water_bottle", amount = 2, slot = 2 },
		{ name = "phone", amount = 1, slot = 3 },
	},
}

-- qb-shops-style item stores. Products are hydrated from QBShared.Items by the
-- server, so labels, weights, images, and useable flags stay authoritative there.
-- The two sample locations sit near CharacterDefaults.position for immediate
-- playtesting; move or replace them when storefront positions are finalized.
Config.Shops = {
	Enabled = true,
	PromptDistance = 10,
	ActionDistance = 14,
	MaxPurchaseAmount = 100,
	DefaultPaymentTypes = { "cash" },
	Products = {
		general = {
			{ name = "sandwich", price = 2, amount = 50 },
			{ name = "water_bottle", price = 2, amount = 50 },
			{ name = "coffee", price = 3, amount = 50 },
			{ name = "bandage", price = 100, amount = 50 },
			{ name = "lockpick", price = 200, amount = 25 },
			{ name = "armor", price = 2500, amount = 10 },
		},
		weapons = {
			{ name = "pistol_ammo", price = 5, amount = 250, requiredLicense = "weapon" },
			{ name = "shotgun_ammo", price = 8, amount = 100, requiredLicense = "weapon" },
			{ name = "rifle_ammo", price = 10, amount = 250, requiredLicense = "weapon" },
			{ name = "weapon_pistol", price = 2500, amount = 5, requiredLicense = "weapon" },
			{ name = "weapon_shotgun", price = 4000, amount = 5, requiredLicense = "weapon" },
			{ name = "weapon_auto_rifle", price = 7500, amount = 3, requiredLicense = "weapon" },
		},
	},
	Locations = {
		{
			id = "general_store_1",
			label = "24/7 Supermarket",
			position = Vector3.new(-166, 3.7, 333.57),
			products = "general",
			useStock = true,
		},
		{
			id = "weapon_shop_1",
			label = "Ammu-Nation",
			position = Vector3.new(-166, 3.7, 348.57),
			products = "weapons",
			useStock = true,
		},
	},
}

-- qb-cityhall-style public services. Jobs listed here are the only jobs that can
-- be selected at City Hall; RestrictedJobs is also enforced independently so a
-- future config edit cannot accidentally make emergency or whitelisted roles public.
Config.CityHall = {
	Enabled = true,
	PromptDistance = 10,
	ActionDistance = 14,
	AvailableJobs = {
		"trucker",
		"taxi",
		"tow",
		"reporter",
		"garbage",
		"bus",
		"hotdog",
		"realestate",
		"cardealer",
		"delivery",
	},
	RestrictedJobs = {
		police = true,
		ambulance = true,
		mechanic = true,
	},
	Documents = {
		{ name = "id_card", label = "ID Card", cost = 50 },
		{ name = "driver_license", label = "Driver License", cost = 50, requiredLicense = "driver" },
		{ name = "weaponlicense", label = "Weapon License", cost = 50, requiredLicense = "weapon" },
	},
	Locations = {
		{
			id = "city_hall",
			label = "City Hall",
			position = Vector3.new(-175, 3.7, 333.57),
		},
	},
}

Config.Medical = {
	DeathScreen = {
		Enabled = true,
		RespawnDelay = 30, -- seconds before self-respawn is available
		RespawnKey = "E",
		GamepadRespawnKey = "ButtonX",
	},
	Respawn = {
		WipeInventory = false,
		Health = 100,
		-- When false, respawn uses CharacterDefaults.position, then the same
		-- map safety fallbacks used by character select. Set true to force Location.
		UseConfiguredLocation = false,
		Location = { x = -175.00, y = 3.70, z = 333.57, ry = 358.6 },
	},
	Hospital = {
		Enabled = true,
		PromptDistance = 10,
		ActionDistance = 14,
		AdmissionSeconds = 2,
		TreatmentSeconds = 20,
		BillCost = 2000,
		PaymentType = "bank",
		MinimalDoctors = 2,
		DoctorCallCooldown = 60,
		RespawnAtNearestHospital = true,
		Hospitals = {
			{
				id = "palmera_medical",
				label = "Palmera Medical Center",
				checkIn = { Vector3.new(-249.08, 2.43, -1066.27) },
				duty = { Vector3.new(-254.39, 2.43, -1064.81) },
				vehicle = { Vector3.new(-205.90, 2.35, -982.20) },
				vehicleSpawn = { position = Vector3.new(-195.90, 3.35, -982.20), heading = 90 },
				authorizedVehicles = {
					{ name = "ambulance", label = "Ambulance", minGrade = 0 },
				},
				beds = {
					{ position = Vector3.new(-259.64, 3.06, -1025.53), heading = 121 },
					{ position = Vector3.new(-265.69, 3.06, -1029.15), heading = 121 },
					{ position = Vector3.new(-267.92, 3.06, -1031.34), heading = 125 },
					{ position = Vector3.new(-273.79, 3.06, -1034.69), heading = 125 },
					{ position = Vector3.new(-281.93, 3.06, -1040.41), heading = 122 },
					{ position = Vector3.new(-284.33, 3.06, -1042.07), heading = 120 },
					{ position = Vector3.new(-287.67, 3.06, -1044.71), heading = 127 },
					{ position = Vector3.new(-290.27, 3.06, -1046.18), heading = 126 },
				},
			},
			{
				id = "palmera_trauma",
				label = "Palmera Trauma Center",
				checkIn = { Vector3.new(-290.11, 2.43, -1005.73) },
				duty = { Vector3.new(-293.99, 2.43, -1003.28) },
				vehicle = { Vector3.new(-240.04, 2.35, -931.98) },
				vehicleSpawn = { position = Vector3.new(-230.04, 3.35, -931.98), heading = 90 },
				authorizedVehicles = {
					{ name = "ambulance", label = "Ambulance", minGrade = 0 },
				},
				beds = {
					{ position = Vector3.new(-308.02, 3.06, -991.67), heading = 215 },
					{ position = Vector3.new(-309.98, 3.06, -988.42), heading = 212 },
					{ position = Vector3.new(-312.17, 3.06, -985.41), heading = 211 },
					{ position = Vector3.new(-314.45, 3.06, -982.20), heading = 215 },
					{ position = Vector3.new(-303.85, 3.06, -979.02), heading = 31 },
					{ position = Vector3.new(-305.96, 3.06, -975.94), heading = 33 },
					{ position = Vector3.new(-308.16, 3.06, -972.82), heading = 37 },
				},
			},
		},
	},
}

-- Per-character appearance (qb-clothing-style). Each character slot stores a serialized
-- HumanoidDescription in its PlayerData and re-applies it on spawn; the player's real
-- site-wide Roblox avatar is never modified.
Config.Appearance = {
	PromptNewCharacters = true, -- open the appearance editor automatically on a character's first spawn
	AllowFullEditorCommand = false, -- false requires normal changes to happen at categorized shops
	ValidateOwnership = true, -- server re-checks catalog ownership on save (previewing is always free try-on)
	MaxAccessories = 15,
	-- Slider ranges for the editor's Body tab; the server clamps saves to these too.
	Scales = {
		height = { Min = 0.9, Max = 1.05, Default = 1 },
		width = { Min = 0.7, Max = 1, Default = 1 },
		depth = { Min = 0.7, Max = 1, Default = 1 }, -- no slider; follows the width slider
		head = { Min = 0.95, Max = 1, Default = 1 },
		bodyType = { Min = 0, Max = 1, Default = 0 },
		proportion = { Min = 0, Max = 1, Default = 0 },
	},
	-- Hex swatches shown in the editor's Skin tab.
	SkinTones = {
		"F7DCC4",
		"F0C8A0",
		"E3B58B",
		"D6A077",
		"C68642",
		"A5694F",
		"8D5524",
		"6B4226",
		"4C2E1E",
		"35211A",
	},
}

-- Categorized qb-clothing-style shops. These origin locations are placeholders;
-- move them to real storefronts before playtesting. Category ids match the tabs in
-- QBAppearance.client.lua and are also enforced by the server on preview/save.
Config.Clothing = {
	Enabled = true,
	PromptDistance = 10,
	ActionDistance = 14,
	MaxOutfits = 20,
	MaxOutfitNameLength = 30,
	ShareCodeLength = 8,
	RequireOwnershipForSharedOutfits = false,
	Shops = {
		{
			id = "clothing_shop_1",
			label = "Clothing Store",
			position = Vector3.new(0, 0, 0),
			categories = {
				"Shirts",
				"Pants",
				"TShirts",
				"LayeredTShirts",
				"LayeredShirts",
				"LayeredPants",
				"Jackets",
				"Sweaters",
				"Shorts",
				"Dresses",
				"Shoes",
			},
			allowOutfits = true,
		},
		{
			id = "accessory_shop_1",
			label = "Accessory Store",
			position = Vector3.new(0, 0, 0),
			categories = { "Hats", "FaceAcc", "Neck", "Shoulder", "Front", "Back", "Waist" },
			allowOutfits = true,
		},
		{
			id = "barber_shop_1",
			label = "Barber Shop",
			position = Vector3.new(0, 0, 0),
			categories = { "Hair" },
			allowOutfits = false,
		},
		{
			id = "outfit_room_1",
			label = "Outfit Wardrobe",
			position = Vector3.new(0, 0, 0),
			categories = {},
			allowOutfits = true,
			outfitsOnly = true,
		},
	},
}

-- qb-spawn and qb-apartments-style character entry. Apartment positions are
-- placeholders until the map entrance is chosen. Install a Model named
-- "StarterApartment" under ServerStorage/QBApartmentInteriors to replace the
-- generated blockout; marker parts are documented in README.md.
Config.Spawn = {
	Enabled = true, -- master QBSpawn UI switch; false always uses automatic destinations
	AllowSelectionForExistingCharacters = true, -- false resumes returning characters at their last location
	DefaultSpawn = {
		position = Vector3.new(-175, 3.7, 333.57),
		heading = 358.6,
	},
	Locations = {
		{ id = "city_hall", label = "City Hall", position = Vector3.new(-175, 3.7, 333.57), heading = 358.6 },
		{ id = "legion_square", label = "Legion Square", position = Vector3.new(0, 0, 0), heading = 0 },
	},
}

Config.Apartments = {
	Enabled = true,
	Starting = true, -- false sends fresh characters directly to Config.Spawn.DefaultSpawn
	PromptDistance = 10,
	ActionDistance = 14,
	DoorbellTimeout = 30,
	MaxStashSlots = 50,
	MaxStashWeight = 250000,
	InteriorGridOrigin = Vector3.new(20000, 500, 20000),
	InteriorGridSpacing = 180,
	Buildings = {
		{
			id = "starter_apartments",
			label = "Starter Apartments",
			position = Vector3.new(0, 0, 0),
			heading = 0,
			interior = "StarterApartment",
		},
	},
}

Config.Player = {
	MaxCharacterSlots = 5,
	Bloodtypes = { "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-" },
	Camera = {
		MinZoomDistance = 0.5,
		MaxZoomDistance = 22, -- normal third-person distance; Roblox default is much farther out
	},

	-- Static defaults only; per-character ids (citizenid, phone, ...) are generated
	-- by PlayerService.CreateCharacter instead.
	CharacterDefaults = {
		cid = 1,
		money = { cash = 500, bank = 5000, crypto = 0 },
		banking = {
			nextStatementId = 1,
			statements = {},
			atm = { dayKey = 0, withdrawn = 0 },
			processedTransferIds = {},
		},
		vehicles = {},
		outfits = {},
		apartment = { id = "", buildingId = "", label = "", stash = {} },
		charinfo = {
			firstname = "Firstname",
			lastname = "Lastname",
			birthdate = "00-00-0000",
			gender = 0,
			nationality = "USA",
			phone = "",
		},
		phone = {
			starterGranted = false,
			settings = { dnd = false, sounds = true },
			callHistory = {},
		},
		job = {
			name = "unemployed",
			label = "Civilian",
			onduty = false,
			type = "none",
			grade = { name = "Freelancer", level = 0, payment = 10, isboss = false },
		},
		crew = {
			name = "none",
			label = "No Crew",
			grade = { name = "none", level = 0, isboss = false },
		},
		metadata = {
			hunger = 100,
			thirst = 100,
			stress = 0,
			isdead = false,
			armor = 0,
			rep = {},
			criminalrecord = { hasRecord = false, date = nil },
			licences = { driver = true, business = false, weapon = false },
		},
		items = {},
		-- Roblox spawn CFrame components (position + Y rotation), replaces the vector4 DefaultSpawn
		position = { x = -175.00, y = 3.70, z = 333.57, ry = 358.6 },
	},
}

Config.Server = {
	Closed = false,
	ClosedReason = "Server Closed",
	Whitelist = false,
	-- FiveM-ace-style graded permissions keyed by UserId. Everyone is implicitly the
	-- lowest rank, higher ranks imply the ones below, and the game owner is always god.
	PermissionRanks = { "user", "mod", "admin", "god" }, -- ordered lowest -> highest
	Permissions = {
		god = {
			[3488348086] = true,
			[337531482] = true,
			[9126300721] = true,
		},
		admin = {
			-- [123456789] = true,
		},
		mod = {
			-- [123456789] = true,
		},
	},
	StudioTestersAreGod = true, -- Studio playtests get top rank so admin commands are testable without config edits
}

return Config
