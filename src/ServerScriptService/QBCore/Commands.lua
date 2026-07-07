--[[
    Roblox port of server/commands.lua: the default command set, registered through
    CommandService (TextChatCommand under the hood -- see CommandService.lua for how
    that differs from FiveM's "/"-prefix scanning).

    FiveM's [id] argument was a server id; here a target is a UserId or a (Display)Name
    prefix, case-insensitive. Commands not portable yet (vehicles, /me proximity text,
    /ooc chat routing, ...) are left for their subsystems.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function requireSiblingModule(name)
	local module = script.Parent:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		error(("QBCore setup error: %s must be a ModuleScript next to %s."):format(name, script:GetFullName()), 2)
	end
	return require(module)
end

local Access = requireSiblingModule("Access")
local AppearanceService = requireSiblingModule("AppearanceService")
local CommandService = requireSiblingModule("CommandService")
local PlayerService = requireSiblingModule("PlayerService")
local TimeSyncService = requireSiblingModule("TimeSyncService")
local VehicleService = requireSiblingModule("VehicleService")
local WeatherService = requireSiblingModule("WeatherService")
local StageMusicService = requireSiblingModule("StageMusicService")

local Remotes = require(ReplicatedStorage.QBRemotes)
local notify = CommandService.Notify

local Commands = {}

local function findTargetPlayer(token)
	if type(token) ~= "string" or #token == 0 then
		return nil
	end

	local userId = tonumber(token)
	if userId then
		return Players:GetPlayerByUserId(userId)
	end

	local lowered = token:lower()
	for _, candidate in ipairs(Players:GetPlayers()) do
		if
			candidate.Name:lower():sub(1, #lowered) == lowered
			or candidate.DisplayName:lower():sub(1, #lowered) == lowered
		then
			return candidate
		end
	end
	return nil
end

-- Resolves a command's [id] argument to an online, character-loaded player.
-- Notifies the sender and returns nil on any failure.
local function resolveTarget(player, token)
	local target = findTargetPlayer(token)
	if not target then
		notify(player, ("No player matching %q is online."):format(tostring(token)))
		return nil
	end
	local targetObj = PlayerService.GetPlayer(target.UserId)
	if not targetObj then
		notify(player, target.DisplayName .. " hasn't loaded a character yet.")
		return nil
	end
	return target, targetObj
end

local function getOwnPlayerObj(player)
	local playerObj = PlayerService.GetPlayer(player.UserId)
	if not playerObj then
		notify(player, "You haven't loaded a character yet.")
	end
	return playerObj
end

local registered = false

function Commands.Register()
	if registered then
		return
	end
	registered = true

	-- ─────────────────────────── everyone ───────────────────────────

	CommandService.Add("commands", "List the commands you can use", {}, false, function(player)
		local lines = {}
		for _, info in ipairs(CommandService.GetVisibleCommands(player.UserId)) do
			lines[#lines + 1] = info.usage .. (#info.help > 0 and (" - " .. info.help) or "")
		end
		notify(player, table.concat(lines, "\n"), "primary", 12000)
	end)

	CommandService.Add("id", "Show your UserId", {}, false, function(player)
		notify(player, ("Your UserId is %d."):format(player.UserId), "primary")
	end)

	CommandService.Add("logout", "Save and return to character select", {}, false, function(player)
		local playerObj = getOwnPlayerObj(player)
		if playerObj then
			playerObj:Logout()
		end
	end)

	CommandService.Add("appearance", "Edit this character's appearance", {}, false, function(player)
		local playerObj = getOwnPlayerObj(player)
		if playerObj then
			AppearanceService.OpenEditor(player, playerObj, false)
		end
	end, "user", "outfit")

	CommandService.Add("emotes", "Open the emote menu", {}, false, function(player)
		if getOwnPlayerObj(player) then
			Remotes.OpenEmoteMenu:FireClient(player)
		end
	end)

	CommandService.Add("music", "Open the closest stage music menu or search Creator Store audio", {
		{ name = "query", help = "search terms (optional)" },
	}, false, function(player, args)
		if getOwnPlayerObj(player) then
			if #args > 0 then
				StageMusicService.OpenSearchMenuFor(player, table.concat(args, " "))
			else
				StageMusicService.OpenMenuFor(player)
			end
		end
	end)

	CommandService.Add("musicsearch", "Search Creator Store audio for the closest stage", {
		{ name = "query", help = "search terms" },
	}, true, function(player, args)
		if getOwnPlayerObj(player) then
			StageMusicService.OpenSearchMenuFor(player, table.concat(args, " "))
		end
	end)

	CommandService.Add("job", "Show your current job", {}, false, function(player)
		local playerObj = getOwnPlayerObj(player)
		if not playerObj then
			return
		end
		local job = playerObj.PlayerData.job
		notify(
			player,
			("Job: %s (%s)%s"):format(job.label, job.grade.name, job.onduty and " - on duty" or ""),
			"primary"
		)
	end)

	CommandService.Add("crew", "Show your current crew", {}, false, function(player)
		local playerObj = getOwnPlayerObj(player)
		if not playerObj then
			return
		end
		local crew = playerObj.PlayerData.crew
		notify(player, ("Crew: %s (%s)"):format(crew.label, crew.grade.name), "primary")
	end)

	CommandService.Add("cash", "Show your cash balance", {}, false, function(player)
		local playerObj = getOwnPlayerObj(player)
		if playerObj then
			notify(player, ("Cash: $%d"):format(playerObj:GetMoney("cash") or 0), "primary")
		end
	end)

	CommandService.Add("bank", "Show your bank balance", {}, false, function(player)
		local playerObj = getOwnPlayerObj(player)
		if playerObj then
			notify(player, ("Bank: $%d"):format(playerObj:GetMoney("bank") or 0), "primary")
		end
	end)

	-- ─────────────────────────── admin ───────────────────────────

	CommandService.Add("admin", "Open the admin menu", {}, false, function(player)
		if not getOwnPlayerObj(player) then
			return
		end
		Remotes.OpenAdminMenu:FireClient(player)
	end, "admin")

	CommandService.Add(
		"setjob",
		"Set a player's job",
		{
			{ name = "id", help = "UserId or name" },
			{ name = "job", help = "job name" },
			{ name = "grade", help = "grade level" },
		},
		true,
		function(player, args)
			local target, targetObj = resolveTarget(player, args[1])
			if not target then
				return
			end
			if not targetObj:SetJob(args[2], args[3] or "0") then
				notify(player, ("Unknown job %q."):format(args[2]))
				return
			end
			notify(
				player,
				("Set %s's job to %s."):format(target.DisplayName, targetObj.PlayerData.job.label),
				"success"
			)
			targetObj:Notify(
				("Your job is now %s (%s)."):format(targetObj.PlayerData.job.label, targetObj.PlayerData.job.grade.name),
				"primary",
				5000
			)
		end,
		"admin"
	)

	CommandService.Add(
		"setcrew",
		"Set a player's crew",
		{
			{ name = "id", help = "UserId or name" },
			{ name = "crew", help = "crew name" },
			{ name = "grade", help = "grade level" },
		},
		true,
		function(player, args)
			local target, targetObj = resolveTarget(player, args[1])
			if not target then
				return
			end
			if not targetObj:SetCrew(args[2], args[3] or "0") then
				notify(player, ("Unknown crew %q."):format(args[2]))
				return
			end
			notify(player, ("Set %s's crew to %s."):format(target.DisplayName, targetObj.PlayerData.crew.label), "success")
			targetObj:Notify(("Your crew is now %s."):format(targetObj.PlayerData.crew.label), "primary", 5000)
		end,
		"admin"
	)

	CommandService.Add(
		"givemoney",
		"Give a player money",
		{
			{ name = "id", help = "UserId or name" },
			{ name = "type", help = "cash/bank/crypto" },
			{ name = "amount", help = "amount" },
		},
		true,
		function(player, args)
			local target, targetObj = resolveTarget(player, args[1])
			if not target then
				return
			end
			local amount = tonumber(args[3])
			if not amount or amount <= 0 then
				notify(player, "Amount must be a positive number.")
				return
			end
			if not targetObj:AddMoney(args[2], amount, "admin-givemoney") then
				notify(player, ("Unknown money type %q."):format(args[2]))
				return
			end
			notify(player, ("Gave %s $%d %s."):format(target.DisplayName, amount, args[2]:lower()), "success")
		end,
		"admin"
	)

	CommandService.Add(
		"setmoney",
		"Set a player's balance",
		{
			{ name = "id", help = "UserId or name" },
			{ name = "type", help = "cash/bank/crypto" },
			{ name = "amount", help = "amount" },
		},
		true,
		function(player, args)
			local target, targetObj = resolveTarget(player, args[1])
			if not target then
				return
			end
			local amount = tonumber(args[3])
			if not amount or amount < 0 then
				notify(player, "Amount must be zero or more.")
				return
			end
			if not targetObj:SetMoney(args[2], amount, "admin-setmoney") then
				notify(player, ("Unknown money type %q."):format(args[2]))
				return
			end
			notify(player, ("Set %s's %s to $%d."):format(target.DisplayName, args[2]:lower(), amount), "success")
		end,
		"admin"
	)

	CommandService.Add(
		"giveitem",
		"Give a player an item",
		{
			{ name = "id", help = "UserId or name" },
			{ name = "item", help = "item name" },
			{ name = "amount", help = "amount (optional)" },
		},
		true,
		function(player, args)
			local target, targetObj = resolveTarget(player, args[1])
			if not target then
				return
			end
			local amount = args[3] and tonumber(args[3]) or 1
			if not amount or amount <= 0 then
				notify(player, "Amount must be a positive number.")
				return
			end
			amount = math.floor(amount)
			local ok, err = targetObj:AddItem(args[2], amount, nil, nil, "admin-giveitem")
			if not ok then
				notify(player, err or ("Could not give item %q."):format(tostring(args[2])))
				return
			end
			notify(player, ("Gave %s x%d %s."):format(target.DisplayName, amount, args[2]:lower()), "success")
			targetObj:Notify(("Received x%d %s."):format(amount, args[2]:lower()), "success", 3500)
		end,
		"admin"
	)

	CommandService.Add(
		"car",
		"Spawn a configured vehicle",
		{
			{ name = "vehicle", help = "vehicle name" },
		},
		true,
		function(player, args)
			if not getOwnPlayerObj(player) then
				return
			end

			local vehicleName = table.concat(args, " ")
			local vehicle, definitionOrErr, plate = VehicleService.SpawnVehicle(player, vehicleName, {
				ignoreRestrictions = true,
			})
			if not vehicle then
				notify(player, definitionOrErr or "Vehicle could not be spawned.")
				return
			end

			notify(
				player,
				("Spawned %s (%s)."):format(definitionOrErr.label or definitionOrErr.name, plate),
				"success"
			)
		end,
		"admin"
	)

	CommandService.Add(
		"dv",
		"Delete the closest spawned vehicle",
		{
			{ name = "radius", help = "studs (optional)" },
		},
		false,
		function(player, args)
			local ok, message = VehicleService.DeleteClosestVehicle(player, args[1])
			notify(player, message, ok and "success" or "error")
		end,
		"admin",
		"deletevehicle"
	)

	CommandService.Add(
		"time",
		"Set the in-game time",
		{
			{ name = "hour", help = "0-23" },
			{ name = "minute", help = "0-59 (optional)" },
		},
		true,
		function(player, args)
			if not TimeSyncService.SetTime(args[1], args[2]) then
				notify(player, "Usage: /time [0-23] [minute]")
				return
			end
			local now = TimeSyncService.GetTime()
			notify(player, ("Time set to %02d:%02d."):format(math.floor(now), math.floor(now % 1 * 60)), "success")
		end,
		"admin"
	)

	CommandService.Add("freezetime", "Toggle the clock advancing", {}, false, function(player)
		TimeSyncService.SetFreeze(not TimeSyncService.IsFrozen())
		notify(player, TimeSyncService.IsFrozen() and "Time frozen." or "Time resumed.", "success")
	end, "admin")

	CommandService.Add(
		"weather",
		"Show or set synced weather",
		{
			{ name = "type", help = "weather type (optional)" },
		},
		false,
		function(player, args)
			if #args == 0 then
				local state = WeatherService.GetState()
				local current = state.nextWeather or state.currentWeather
				local names = {}
				for _, preset in ipairs(WeatherService.GetPresetList()) do
					names[#names + 1] = preset.name:lower()
				end
				notify(
					player,
					("Weather: %s. Available: %s."):format(tostring(current):lower(), table.concat(names, ", ")),
					"primary",
					9000
				)
				return
			end

			local ok, message = WeatherService.SetWeather(table.concat(args, " "))
			notify(player, message, ok and "success" or "error")
		end,
		"admin"
	)

	CommandService.Add("freezeweather", "Toggle automatic weather cycling", {}, false, function(player)
		local frozen = WeatherService.SetFrozen(not WeatherService.IsFrozen())
		notify(player, frozen and "Weather cycling frozen." or "Weather cycling resumed.", "success")
	end, "admin")

	CommandService.Add("blackout", "Toggle tagged world lights", {}, false, function(player)
		local blackout = WeatherService.SetBlackout(not WeatherService.IsBlackout())
		notify(player, blackout and "Blackout enabled." or "Blackout disabled.", "success")
	end, "admin")

	CommandService.Add(
		"kick",
		"Kick a player",
		{
			{ name = "id", help = "UserId or name" },
			{ name = "reason", help = "reason (optional)" },
		},
		true,
		function(player, args)
			local target = findTargetPlayer(args[1])
			if not target then
				notify(player, ("No player matching %q is online."):format(tostring(args[1])))
				return
			end
			local reason = #args > 1 and table.concat(args, " ", 2) or "No reason specified"
			target:Kick("Kicked: " .. reason)
			notify(player, ("Kicked %s."):format(target.DisplayName), "success")
		end,
		"admin"
	)

	-- ─────────────────────────── god ───────────────────────────

	CommandService.Add(
		"ban",
		"Ban a player (0 hours = permanent)",
		{
			{ name = "id", help = "UserId or name" },
			{ name = "hours", help = "duration; 0 = permanent" },
			{ name = "reason", help = "reason (optional)" },
		},
		true,
		function(player, args)
			local target = findTargetPlayer(args[1])
			if not target then
				notify(player, ("No player matching %q is online."):format(tostring(args[1])))
				return
			end
			local hours = tonumber(args[2])
			if not hours or hours < 0 then
				notify(player, "Hours must be a number (0 for permanent).")
				return
			end
			local reason = #args > 2 and table.concat(args, " ", 3) or "No reason specified"
			local expireAt = hours > 0 and (os.time() + math.floor(hours * 3600)) or nil

			if not Access.BanPlayer(target.UserId, reason, expireAt) then
				notify(player, "Ban could not be written; try again.")
				return
			end
			target:Kick("You are banned: " .. reason)
			notify(
				player,
				("Banned %s (%s)."):format(target.DisplayName, hours > 0 and hours .. "h" or "permanent"),
				"success"
			)
		end,
		"god"
	)
end

return Commands
