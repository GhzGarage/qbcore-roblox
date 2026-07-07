-- Shared config for stage speaker jukeboxes.
-- Clients read labels/menu data from here; the server is still the authority for playback.

local StageMusic = {}

StageMusic.Defaults = {
	MenuDistance = 60,
	Volume = 0.5,
	MaxVolume = 1,
	VolumeStep = 0.2,
	Looping = true,
	Cooldown = 0.75,
	SearchCooldown = 4,
	SearchCacheSeconds = 120,
	SearchMaxResults = 8,
	AngleAttenuation = {
		[0] = 1,
		[45] = 0.85,
		[90] = 0.4,
		[135] = 0.15,
		[180] = 0.05,
	},
	DistanceAttenuation = {
		[0] = 1,
		[35] = 0.9,
		[70] = 0.45,
		[110] = 0.1,
		[140] = 0,
	},
}

StageMusic.Stations = {
	{
		id = "plaza_stage",
		label = "Plaza Stage",
		speakerPath = {
			"PlazaQuadrants",
			"PlazaStage",
			"Generated",
			"PlazaStage",
			"stage speaker",
		},
		speakerParts = {
			Left = { "LeftSpk_Cab" },
			Right = { "RightSpk_Cab" },
		},
		menuDistance = 60,
		volume = 0.5,
		looping = true,
		audienceTarget = Vector3.new(-133.345, 19.076, 135.622),

		-- Optional tuning:
		-- interactionPartPath = { "DJBooth" },
	},
}

StageMusic.Tracks = {
	-- Replace these with uploaded / permitted Roblox audio asset ids, then set enabled = true.
	{
		id = "change_my_mind",
		label = "Change My Mind",
		artist = "DistrokidOfficial",
		assetId = "rbxassetid://111579871505275",
		enabled = true,
	},
	{
		id = "3am_call",
		label = "3AM Call",
		artist = "DistrokidOfficial",
		assetId = "rbxassetid://84373057404593",
		enabled = true,
	},
}

local function trim(value)
	if type(value) ~= "string" then
		return ""
	end
	return value:match("^%s*(.-)%s*$") or ""
end

function StageMusic.NormalizeAssetId(assetId)
	if type(assetId) == "number" then
		return "rbxassetid://" .. tostring(math.floor(assetId))
	end

	if type(assetId) ~= "string" then
		return nil
	end

	assetId = trim(assetId)
	if assetId == "" or assetId == "rbxassetid://0000000000" then
		return nil
	end

	if assetId:match("^%d+$") then
		return "rbxassetid://" .. assetId
	end

	if assetId:match("^rbxassetid://%d+$") then
		return assetId
	end

	return nil
end

function StageMusic.GetStationById(stationId)
	stationId = trim(stationId)
	for _, station in ipairs(StageMusic.Stations) do
		if station.id == stationId then
			return station
		end
	end
	return nil
end

function StageMusic.GetTrackById(trackId)
	trackId = trim(trackId)
	for _, track in ipairs(StageMusic.Tracks) do
		if track.id == trackId and track.enabled ~= false and StageMusic.NormalizeAssetId(track.assetId) then
			return track
		end
	end
	return nil
end

function StageMusic.GetEnabledTracks()
	local tracks = {}
	for _, track in ipairs(StageMusic.Tracks) do
		if track.enabled ~= false and StageMusic.NormalizeAssetId(track.assetId) then
			tracks[#tracks + 1] = track
		end
	end
	return tracks
end

function StageMusic.GetTrackSubtitle(track)
	if type(track) ~= "table" then
		return ""
	end

	local parts = {}
	if type(track.artist) == "string" and track.artist ~= "" then
		parts[#parts + 1] = track.artist
	end
	if type(track.description) == "string" and track.description ~= "" then
		parts[#parts + 1] = track.description
	end

	return table.concat(parts, " - ")
end

return StageMusic
