-- Direct port of shared/jobs.lua — pure data, no natives involved, so it carries over as-is.
-- Trimmed to a representative subset; copy the rest of your jobs table over from the FiveM version.

local Jobs = {}

Jobs.ForceJobDefaultDutyAtLogin = true

Jobs.List = {
	unemployed = { label = "Civilian", defaultDuty = true, grades = { ["0"] = { name = "Freelancer", payment = 10 } } },
	police = {
		label = "Law Enforcement",
		type = "leo",
		defaultDuty = true,
		grades = {
			["0"] = { name = "Recruit", payment = 50 },
			["1"] = { name = "Officer", payment = 75 },
			["2"] = { name = "Sergeant", payment = 100 },
			["3"] = { name = "Lieutenant", payment = 125 },
			["4"] = { name = "Chief", isboss = true, payment = 150 },
		},
	},
	ambulance = {
		label = "EMS",
		type = "ems",
		defaultDuty = true,
		grades = {
			["0"] = { name = "Recruit", payment = 50 },
			["1"] = { name = "Paramedic", payment = 75 },
			["2"] = { name = "Doctor", payment = 100 },
			["3"] = { name = "Surgeon", payment = 125 },
			["4"] = { name = "Chief", isboss = true, payment = 150 },
		},
	},
	trucker = {
		label = "Truck Driver",
		defaultDuty = true,
		grades = { ["0"] = { name = "Driver", payment = 35 } },
	},
	taxi = {
		label = "Taxi Driver",
		defaultDuty = true,
		grades = { ["0"] = { name = "Driver", payment = 35 } },
	},
	tow = {
		label = "Tow Truck Driver",
		defaultDuty = true,
		grades = { ["0"] = { name = "Driver", payment = 35 } },
	},
	reporter = {
		label = "News Reporter",
		defaultDuty = true,
		grades = { ["0"] = { name = "Reporter", payment = 35 } },
	},
	garbage = {
		label = "Garbage Collector",
		defaultDuty = true,
		grades = { ["0"] = { name = "Collector", payment = 35 } },
	},
	bus = {
		label = "Bus Driver",
		defaultDuty = true,
		grades = { ["0"] = { name = "Driver", payment = 35 } },
	},
	hotdog = {
		label = "Hot Dog Vendor",
		defaultDuty = true,
		grades = { ["0"] = { name = "Vendor", payment = 30 } },
	},
	realestate = {
		label = "Real Estate Agent",
		defaultDuty = true,
		grades = { ["0"] = { name = "Agent", payment = 35 } },
	},
	cardealer = {
		label = "Vehicle Dealer",
		defaultDuty = true,
		grades = { ["0"] = { name = "Salesperson", payment = 35 } },
	},
	delivery = {
		label = "Delivery Driver",
		defaultDuty = true,
		grades = { ["0"] = { name = "Driver", payment = 35 } },
	},
}

return Jobs
