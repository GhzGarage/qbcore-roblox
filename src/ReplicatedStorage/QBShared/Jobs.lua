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
}

return Jobs
