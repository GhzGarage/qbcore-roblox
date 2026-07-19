-- Shared vehicle registry. These entries describe QBCore gameplay metadata; the
-- actual drivable models live in ServerStorage > QBVehicleModels.

local ATTRIBUTE_PROFILES = {
	emergency = {
		AllowCarjacking = true,
		BaseEngineRPM = 850,
		BrakingTorque = 95000,
		DrivingTorque = 30000,
		MaxEngineRPM = 6200,
		MaxSpeed = 47.5,
		MaxSteer = 0.86,
		ReverseSpeed = 14,
		StrutSpringDampingFront = 1500,
		StrutSpringDampingRear = 1450,
		StrutSpringStiffnessFront = 26000,
		StrutSpringStiffnessRear = 25000,
		TakeOffAccessories = true,
		TorsionSpringDamping = 170,
		TorsionSpringStiffness = 22000,
		WheelFriction = 1.9,
	},

	sedan = {
		AllowCarjacking = true,
		BaseEngineRPM = 850,
		BrakingTorque = 82000,
		DrivingTorque = 26000,
		MaxEngineRPM = 6200,
		MaxSpeed = 46,
		MaxSteer = 0.84,
		ReverseSpeed = 13,
		StrutSpringDampingFront = 1450,
		StrutSpringDampingRear = 1400,
		StrutSpringStiffnessFront = 24500,
		StrutSpringStiffnessRear = 23500,
		TakeOffAccessories = true,
		TorsionSpringDamping = 165,
		TorsionSpringStiffness = 21000,
		WheelFriction = 1.85,
	},

	sports = {
		AllowCarjacking = true,
		BaseEngineRPM = 1050,
		BrakingTorque = 110000,
		DrivingTorque = 36000,
		MaxEngineRPM = 7600,
		MaxSpeed = 62.5,
		MaxSteer = 0.94,
		ReverseSpeed = 16,
		StrutSpringDampingFront = 1650,
		StrutSpringDampingRear = 1600,
		StrutSpringStiffnessFront = 32000,
		StrutSpringStiffnessRear = 30500,
		TakeOffAccessories = true,
		TorsionSpringDamping = 190,
		TorsionSpringStiffness = 28000,
		WheelFriction = 2,
	},

	supercar = {
		AllowCarjacking = true,
		BaseEngineRPM = 1200,
		BrakingTorque = 125000,
		DrivingTorque = 42500,
		MaxEngineRPM = 8400,
		MaxSpeed = 72.5,
		MaxSteer = 0.95,
		ReverseSpeed = 17.5,
		StrutSpringDampingFront = 1800,
		StrutSpringDampingRear = 1750,
		StrutSpringStiffnessFront = 36000,
		StrutSpringStiffnessRear = 34500,
		TakeOffAccessories = true,
		TorsionSpringDamping = 205,
		TorsionSpringStiffness = 32000,
		WheelFriction = 2.05,
	},

	offroad = {
		AllowCarjacking = true,
		BaseEngineRPM = 900,
		BrakingTorque = 98000,
		DrivingTorque = 34000,
		MaxEngineRPM = 6800,
		MaxSpeed = 52.5,
		MaxSteer = 0.98,
		ReverseSpeed = 15,
		StrutSpringDampingFront = 1550,
		StrutSpringDampingRear = 1500,
		StrutSpringStiffnessFront = 28500,
		StrutSpringStiffnessRear = 27500,
		TakeOffAccessories = true,
		TorsionSpringDamping = 185,
		TorsionSpringStiffness = 25500,
		WheelFriction = 2.25,
	},

	utility = {
		AllowCarjacking = true,
		BaseEngineRPM = 800,
		BrakingTorque = 95000,
		DrivingTorque = 32500,
		MaxEngineRPM = 5800,
		MaxSpeed = 39,
		MaxSteer = 0.8,
		ReverseSpeed = 12,
		StrutSpringDampingFront = 1600,
		StrutSpringDampingRear = 1550,
		StrutSpringStiffnessFront = 31500,
		StrutSpringStiffnessRear = 30500,
		TakeOffAccessories = true,
		TorsionSpringDamping = 185,
		TorsionSpringStiffness = 25000,
		WheelFriction = 2.1,
	},

	pickup = {
		AllowCarjacking = true,
		BaseEngineRPM = 800,
		BrakingTorque = 105000,
		DrivingTorque = 37500,
		MaxEngineRPM = 5600,
		MaxSpeed = 41,
		MaxSteer = 0.76,
		ReverseSpeed = 11.5,
		StrutSpringDampingFront = 1700,
		StrutSpringDampingRear = 1650,
		StrutSpringStiffnessFront = 33500,
		StrutSpringStiffnessRear = 36000,
		TakeOffAccessories = true,
		TorsionSpringDamping = 195,
		TorsionSpringStiffness = 28000,
		WheelFriction = 2,
	},

	suv = {
		AllowCarjacking = true,
		BaseEngineRPM = 825,
		BrakingTorque = 98000,
		DrivingTorque = 34000,
		MaxEngineRPM = 5900,
		MaxSpeed = 44,
		MaxSteer = 0.78,
		ReverseSpeed = 12,
		StrutSpringDampingFront = 1650,
		StrutSpringDampingRear = 1600,
		StrutSpringStiffnessFront = 31500,
		StrutSpringStiffnessRear = 32000,
		TakeOffAccessories = true,
		TorsionSpringDamping = 185,
		TorsionSpringStiffness = 25500,
		WheelFriction = 1.95,
	},

	van = {
		AllowCarjacking = true,
		BaseEngineRPM = 780,
		BrakingTorque = 100000,
		DrivingTorque = 35000,
		MaxEngineRPM = 5400,
		MaxSpeed = 37.5,
		MaxSteer = 0.72,
		ReverseSpeed = 11,
		StrutSpringDampingFront = 1750,
		StrutSpringDampingRear = 1700,
		StrutSpringStiffnessFront = 34500,
		StrutSpringStiffnessRear = 37000,
		TakeOffAccessories = true,
		TorsionSpringDamping = 200,
		TorsionSpringStiffness = 30000,
		WheelFriction = 1.8,
	},
}

local function copyAttributes(profile)
	local attributes = {}
	for key, value in pairs(profile) do
		attributes[key] = value
	end
	return attributes
end

local function vehicle(definition)
	definition.brand = definition.brand or "Roblox"
	definition.price = tonumber(definition.price) or 0
	definition.fuel = definition.fuel or 100
	definition.gloveboxSlots = definition.gloveboxSlots or 5
	definition.gloveboxWeight = definition.gloveboxWeight or 10000

	local profileName = definition.attributeProfile
	if profileName then
		local profile = ATTRIBUTE_PROFILES[profileName]
		assert(profile, ("Unknown vehicle attribute profile %q."):format(profileName))
		definition.attributes = copyAttributes(profile)
		definition.attributeProfile = nil
	end

	return definition
end

local function board(definition)
	definition.brand = definition.brand or "Roblox"
	definition.price = tonumber(definition.price) or 0
	definition.category = definition.category or "personal"
	definition.fuel = definition.fuel or 0
	definition.trunkSlots = definition.trunkSlots or 0
	definition.trunkWeight = definition.trunkWeight or 0
	return definition
end

local Vehicles = {
	dune_buggy_beige = vehicle({
		name = "dune_buggy_beige",
		label = "Dune Buggy (Beige)",
		modelName = "Dune Buggy (beige)",
		category = "offroad",
		color = "beige",
		trunkSlots = 10,
		trunkWeight = 30000,
		attributeProfile = "offroad",
		aliases = { "dune_buggy", "dune_beige", "buggy", "buggy_beige", "beige_buggy" },
		description = "A lightweight off-road buggy built for sand and rough terrain.",
	}),

	dune_buggy_blue = vehicle({
		name = "dune_buggy_blue",
		label = "Dune Buggy (Blue)",
		modelName = "Dune Buggy (blue)",
		category = "offroad",
		color = "blue",
		trunkSlots = 10,
		trunkWeight = 30000,
		attributeProfile = "offroad",
		aliases = { "dune_blue", "buggy_blue", "blue_buggy" },
		description = "A blue off-road dune buggy variant.",
	}),

	dune_buggy_orange = vehicle({
		name = "dune_buggy_orange",
		label = "Dune Buggy (Orange)",
		modelName = "Dune Buggy (orange)",
		category = "offroad",
		color = "orange",
		trunkSlots = 10,
		trunkWeight = 30000,
		attributeProfile = "offroad",
		aliases = { "dune_orange", "buggy_orange", "orange_buggy" },
		description = "An orange off-road dune buggy variant.",
	}),

	hoverboard = board({
		name = "hoverboard",
		label = "Hoverboard",
		modelName = "HoverBoard",
		aliases = { "hover_board" },
		description = "A compact personal board template.",
	}),

	taxi = vehicle({
		name = "taxi",
		label = "Taxi",
		brand = "Declasse",
		modelName = "Taxi",
		category = "service",
		color = "yellow",
		trunkSlots = 35,
		trunkWeight = 65000,
		attributeProfile = "sedan",
		aliases = { "taxi" },
		description = "A taxi-service sedan template.",
	}),

	ambulance = vehicle({
		name = "ambulance",
		label = "Ambulance",
		modelName = "Ambulance",
		category = "emergency",
		color = "white",
		trunkSlots = 50,
		trunkWeight = 100000,
		attributeProfile = "emergency",
		aliases = { "ems", "medical", "bp_ambulance" },
		description = "An emergency medical response vehicle for on-duty EMS.",
	}),

	light_utility_black = vehicle({
		name = "light_utility_black",
		label = "Light Utility Vehicle (Black)",
		modelName = "Light Utility Vehicle (black)",
		category = "utility",
		color = "black",
		trunkSlots = 18,
		trunkWeight = 50000,
		attributeProfile = "utility",
		aliases = { "light_utility", "light_utility_vehicle", "luv", "luv_black", "utility_black" },
		description = "A compact light utility vehicle.",
	}),

	light_utility_green_camo = vehicle({
		name = "light_utility_green_camo",
		label = "Light Utility Vehicle (Green Camo)",
		modelName = "Light Utility Vehicle (green camo)",
		category = "utility",
		color = "green camo",
		trunkSlots = 18,
		trunkWeight = 50000,
		attributeProfile = "utility",
		aliases = { "luv_green_camo", "green_camo_luv", "utility_green_camo" },
		description = "A green-camouflage light utility vehicle variant.",
	}),

	light_utility_pink = vehicle({
		name = "light_utility_pink",
		label = "Light Utility Vehicle (Pink)",
		modelName = "Light Utility Vehicle (pink)",
		category = "utility",
		color = "pink",
		trunkSlots = 18,
		trunkWeight = 50000,
		attributeProfile = "utility",
		aliases = { "luv_pink", "pink_luv", "utility_pink" },
		description = "A pink light utility vehicle variant.",
	}),

	light_utility_white_camo = vehicle({
		name = "light_utility_white_camo",
		label = "Light Utility Vehicle (White Camo)",
		modelName = "Light Utility Vehicle (white camo)",
		category = "utility",
		color = "white camo",
		trunkSlots = 18,
		trunkWeight = 50000,
		attributeProfile = "utility",
		aliases = { "luv_white_camo", "white_camo_luv", "utility_white_camo" },
		description = "A white-camouflage light utility vehicle variant.",
	}),

	longboard = board({
		name = "longboard",
		label = "Longboard",
		modelName = "LongBoard",
		aliases = { "long_board" },
		description = "A longboard personal transport template.",
	}),

	pickup_blue = vehicle({
		name = "pickup_blue",
		label = "Pickup Truck (Blue)",
		modelName = "Pickup Truck (blue)",
		category = "trucks",
		color = "blue",
		trunkSlots = 35,
		trunkWeight = 80000,
		attributeProfile = "pickup",
		aliases = { "pickup", "pickup_truck", "truck", "blue_pickup", "blue_truck" },
		description = "A blue pickup truck with extra storage space.",
	}),

	pickup_bronze = vehicle({
		name = "pickup_bronze",
		label = "Pickup Truck (Bronze)",
		modelName = "Pickup Truck (bronze)",
		category = "trucks",
		color = "bronze",
		trunkSlots = 35,
		trunkWeight = 80000,
		attributeProfile = "pickup",
		aliases = { "pickup_truck_bronze", "bronze_pickup", "bronze_truck" },
		description = "A bronze pickup truck variant.",
	}),

	pickup_white = vehicle({
		name = "pickup_white",
		label = "Pickup Truck (White)",
		modelName = "Pickup Truck (white)",
		category = "trucks",
		color = "white",
		trunkSlots = 35,
		trunkWeight = 80000,
		attributeProfile = "pickup",
		aliases = { "pickup_truck_white", "white_pickup", "white_truck" },
		description = "A white pickup truck variant.",
	}),

	police = vehicle({
		name = "police",
		label = "Police Cruiser",
		modelName = "Police Car",
		assetId = 6418230807,
		category = "emergency",
		trunkSlots = 40,
		trunkWeight = 80000,
		attributeProfile = "emergency",
		aliases = { "police_car", "policecar", "cop", "cruiser" },
		description = "A law-enforcement vehicle template for police gameplay.",
	}),

	ripboard = board({
		name = "ripboard",
		label = "Ripboard",
		modelName = "Ripboard",
		aliases = { "rip_board" },
		description = "A ripboard personal transport template.",
	}),

	suv_black = vehicle({
		name = "suv_black",
		label = "SUV (Black)",
		modelName = "SUV (black)",
		category = "suvs",
		color = "black",
		trunkSlots = 35,
		trunkWeight = 75000,
		attributeProfile = "suv",
		aliases = { "suv", "black_suv" },
		description = "A black SUV with balanced passenger and cargo utility.",
	}),

	suv_blue = vehicle({
		name = "suv_blue",
		label = "SUV (Blue)",
		modelName = "SUV (blue)",
		category = "suvs",
		color = "blue",
		trunkSlots = 35,
		trunkWeight = 75000,
		attributeProfile = "suv",
		aliases = { "blue_suv" },
		description = "A blue SUV variant.",
	}),

	suv_white = vehicle({
		name = "suv_white",
		label = "SUV (White)",
		modelName = "SUV (white)",
		category = "suvs",
		color = "white",
		trunkSlots = 35,
		trunkWeight = 75000,
		attributeProfile = "suv",
		aliases = { "white_suv" },
		description = "A white SUV variant.",
	}),

	sedan_aqua = vehicle({
		name = "sedan_aqua",
		label = "Sedan (Aqua)",
		modelName = "Sedan (aqua)",
		category = "sedans",
		color = "aqua",
		trunkSlots = 30,
		trunkWeight = 60000,
		attributeProfile = "sedan",
		aliases = { "aqua_sedan" },
		description = "An aqua sedan variant.",
	}),

	sedan_black = vehicle({
		name = "sedan_black",
		label = "Sedan (Black)",
		modelName = "Sedan (black)",
		category = "sedans",
		color = "black",
		trunkSlots = 30,
		trunkWeight = 60000,
		attributeProfile = "sedan",
		aliases = { "black_sedan" },
		description = "A black sedan variant.",
	}),

	sedan_orange = vehicle({
		name = "sedan_orange",
		label = "Sedan (Orange)",
		modelName = "Sedan (orange)",
		category = "sedans",
		color = "orange",
		trunkSlots = 30,
		trunkWeight = 60000,
		attributeProfile = "sedan",
		aliases = { "orange_sedan" },
		description = "An orange sedan variant.",
	}),

	sedan_red = vehicle({
		name = "sedan_red",
		label = "Sedan (Red)",
		modelName = "Sedan (red)",
		category = "sedans",
		color = "red",
		trunkSlots = 30,
		trunkWeight = 60000,
		attributeProfile = "sedan",
		aliases = { "red_sedan" },
		description = "A red sedan variant.",
	}),

	sedan_white = vehicle({
		name = "sedan_white",
		label = "Sedan (White)",
		modelName = "Sedan (white)",
		category = "sedans",
		color = "white",
		trunkSlots = 30,
		trunkWeight = 60000,
		attributeProfile = "sedan",
		aliases = { "sedan", "white_sedan" },
		description = "A white sedan variant.",
	}),

	skateboard1 = board({
		name = "skateboard1",
		label = "Skateboard 1",
		modelName = "Skateboard1",
		aliases = { "skateboard", "skateboard_1" },
		description = "A skateboard personal transport template.",
	}),

	skateboard2 = board({
		name = "skateboard2",
		label = "Skateboard 2",
		modelName = "Skateboard2",
		aliases = { "skateboard_2" },
		description = "A second skateboard personal transport template.",
	}),

	skateboard3 = board({
		name = "skateboard3",
		label = "Skateboard 3",
		modelName = "Skateboard3",
		aliases = { "skateboard_3" },
		description = "A third skateboard personal transport template.",
	}),

	sports = vehicle({
		name = "sports",
		label = "Sports Car (Blue)",
		modelName = "Sports Car (blue)",
		assetId = 6433323089,
		category = "sports",
		color = "blue",
		trunkSlots = 20,
		trunkWeight = 50000,
		attributeProfile = "sports",
		aliases = { "sports_car", "sportscar", "sports_blue", "blue_sports", "sportscar_blue" },
		description = "A fast civilian vehicle template for early vehicle-system testing.",
	}),

	sports_red = vehicle({
		name = "sports_red",
		label = "Sports Car (Red)",
		modelName = "Sports Car (red)",
		assetId = 6433323089,
		category = "sports",
		color = "red",
		trunkSlots = 20,
		trunkWeight = 50000,
		attributeProfile = "sports",
		aliases = { "red_sports", "sports_red", "sportscar_red" },
		description = "A red sports car variant.",
	}),

	sports_white = vehicle({
		name = "sports_white",
		label = "Sports Car (White)",
		modelName = "Sports Car (white)",
		assetId = 6433323089,
		category = "sports",
		color = "white",
		trunkSlots = 20,
		trunkWeight = 50000,
		attributeProfile = "sports",
		aliases = { "white_sports", "sports_white", "sportscar_white" },
		description = "A white sports car variant.",
	}),

	supercar_blue = vehicle({
		name = "supercar_blue",
		label = "Supercar (Blue)",
		modelName = "Supercar (blue)",
		category = "super",
		color = "blue",
		trunkSlots = 15,
		trunkWeight = 40000,
		attributeProfile = "supercar",
		aliases = { "supercar", "blue_supercar" },
		description = "A high-performance blue supercar.",
	}),

	supercar_green = vehicle({
		name = "supercar_green",
		label = "Supercar (Green)",
		modelName = "Supercar (green)",
		category = "super",
		color = "green",
		trunkSlots = 15,
		trunkWeight = 40000,
		attributeProfile = "supercar",
		aliases = { "green_supercar" },
		description = "A green supercar variant.",
	}),

	supercar_yellow = vehicle({
		name = "supercar_yellow",
		label = "Supercar (Yellow)",
		modelName = "Supercar (yellow)",
		category = "super",
		color = "yellow",
		trunkSlots = 15,
		trunkWeight = 40000,
		attributeProfile = "supercar",
		aliases = { "yellow_supercar" },
		description = "A yellow supercar variant.",
	}),

	van_1970 = vehicle({
		name = "van_1970",
		label = "Van (1970)",
		modelName = "Van (1970)",
		category = "vans",
		trunkSlots = 50,
		trunkWeight = 120000,
		attributeProfile = "van",
		aliases = { "1970_van", "classic_van" },
		description = "A classic van with generous cargo capacity.",
	}),

	van_pro = vehicle({
		name = "van_pro",
		label = "Van (Pro)",
		modelName = "Van (pro)",
		category = "vans",
		trunkSlots = 50,
		trunkWeight = 120000,
		attributeProfile = "van",
		aliases = { "pro_van", "work_van" },
		description = "A professional work van variant.",
	}),

	van_white = vehicle({
		name = "van_white",
		label = "Van (White)",
		modelName = "Van (white)",
		category = "vans",
		color = "white",
		trunkSlots = 50,
		trunkWeight = 120000,
		attributeProfile = "van",
		aliases = { "van", "white_van" },
		description = "A white cargo van variant.",
	}),
}

return Vehicles
