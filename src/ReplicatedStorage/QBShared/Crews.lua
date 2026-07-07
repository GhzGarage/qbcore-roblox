-- Shared crew registry. Keep this table Roblox-friendly and expand it with server-safe
-- groups as your experience needs them.

local Crews = {
	none = {
		label = "No Crew",
		colors = { primary = "neutral", accent = "white" },
		description = "Unaffiliated.",
		grades = { ["0"] = { name = "Unaffiliated" } },
	},

	vantage_row = {
		label = "Vantage Row",
		colors = { primary = "navy", accent = "gold" },
		description = "Corporate-adjacent operators using legitimate fronts for organized heist and vehicle work.",
		grades = {
			["0"] = { name = "Associate" },
			["1"] = { name = "Operator" },
			["2"] = { name = "Broker" },
			["3"] = { name = "Director", isboss = true },
		},
	},

	static_line = {
		label = "Static Line",
		colors = { primary = "red", accent = "black" },
		description = "Street-level crew built around territory, hustle, and gritty starter rivalries.",
		grades = {
			["0"] = { name = "Runner" },
			["1"] = { name = "Regular" },
			["2"] = { name = "Corner Lead" },
			["3"] = { name = "Shot Caller", isboss = true },
		},
	},

	the_undertow = {
		label = "The Undertow",
		colors = { primary = "teal", accent = "grey" },
		description = "Dockside and waterfront crew moving vehicle parts and off-book goods through industrial routes.",
		grades = {
			["0"] = { name = "Deckhand" },
			["1"] = { name = "Handler" },
			["2"] = { name = "Harbor Lead" },
			["3"] = { name = "Tide Boss", isboss = true },
		},
	},

	ironclad_motor_co = {
		label = "Ironclad Motor Co.",
		colors = { primary = "black", accent = "orange" },
		description = "Motor-club-styled crew focused on vehicle jobs, workshop fronts, and road rivalry gameplay.",
		grades = {
			["0"] = { name = "Prospect" },
			["1"] = { name = "Patch" },
			["2"] = { name = "Road Captain" },
			["3"] = { name = "President", isboss = true },
		},
	},
}

return Crews
