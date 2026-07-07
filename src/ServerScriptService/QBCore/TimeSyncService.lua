--[[
    Roblox port of qb-weathersync's time half: clock progression. Lighting.ClockTime
    is server-authoritative and replicates to every client automatically. The /time
    and /freezetime commands live in Commands.lua and call the setters below.
    Weather/blackout state lives in WeatherService.lua.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function requireQBShared()
	local shared = ReplicatedStorage:FindFirstChild("QBShared")
	if not shared then
		error("QBCore setup error: ReplicatedStorage must contain QBShared.", 2)
	end

	if shared:IsA("ModuleScript") then
		return require(shared)
	end

	for _, moduleName in ipairs({ "Main", "init", "init.lua" }) do
		local module = shared:FindFirstChild(moduleName)
		if module and module:IsA("ModuleScript") then
			return require(module)
		end
	end

	error(
		"QBCore setup error: ReplicatedStorage.QBShared must be a ModuleScript, or a Folder containing a Main ModuleScript.",
		2
	)
end

local QBShared = requireQBShared()

local UPDATE_INTERVAL = 1 -- seconds between Lighting.ClockTime writes; 1 Hz is visually seamless at default pace

local TimeSyncService = {}

local started = false
local frozen = false
local clockTime = 12 -- our own float so sub-second increments aren't lost to property round-tripping

local function timeConfig()
	local world = QBShared.Config.World
	return (world and world.Time) or {}
end

-- hour may be fractional; minute is optional on top of that
function TimeSyncService.SetTime(hour, minute)
	hour = tonumber(hour)
	if not hour then
		return false
	end
	clockTime = (hour + (tonumber(minute) or 0) / 60) % 24
	Lighting.ClockTime = clockTime
	return true
end

function TimeSyncService.SetFreeze(state)
	frozen = state == true
end

function TimeSyncService.IsFrozen()
	return frozen
end

function TimeSyncService.GetTime()
	return clockTime
end

function TimeSyncService.Start()
	if started then
		return
	end
	started = true

	local cfg = timeConfig()
	frozen = cfg.Freeze == true

	if cfg.Enabled == false then
		-- static clock: honor World.ClockTime, keep the commands, never advance
		TimeSyncService.SetTime(QBShared.Config.World.ClockTime or 12)
		return
	end

	TimeSyncService.SetTime(cfg.StartHour or QBShared.Config.World.ClockTime or 12)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(UPDATE_INTERVAL)
			local now = os.clock()
			local elapsed = now - last
			last = now

			if not frozen then
				-- re-read each tick so DayLengthMinutes can be live-tuned
				local dayLengthSeconds = math.max(60, (tonumber(timeConfig().DayLengthMinutes) or 48) * 60)
				clockTime = (clockTime + elapsed * 24 / dayLengthSeconds) % 24
				Lighting.ClockTime = clockTime
			end
		end
	end)
end

return TimeSyncService
