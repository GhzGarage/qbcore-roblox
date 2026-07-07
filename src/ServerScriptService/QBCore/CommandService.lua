--[[
    Roblox port of QBCore.Commands. FiveM scans every chat message for a leading "/";
    Roblox's TextChatService owns that prefix instead: each command is registered as a
    TextChatCommand, unregistered slash-messages never reach the server, and registered
    ones get chat-bar autocomplete for free. Triggered fires server-side with the raw
    (unfiltered) text, so argument parsing and permission checks are all trust-safe.

    CommandService.Add mirrors QBCore.Commands.Add:
        Add(name, help, arguments, argsRequired, callback, permission?, secondaryAlias?)
      - arguments: array of { name = "id", help = "target player" }, used for usage text
      - argsRequired: when true, fewer tokens than #arguments notifies usage and aborts
      - callback(player, args, rawText) -- args is the message split on whitespace,
        alias removed; may yield
      - permission: a rank name from Config.Server.PermissionRanks (default "user")

    Per-command feedback goes through the existing Notify remote (toasts); there is no
    server-side DisplaySystemMessage, so chat-line replies are not used.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Remotes = require(ReplicatedStorage.QBRemotes)

local function requireSiblingModule(name)
	local module = script.Parent:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		error(("QBCore setup error: %s must be a ModuleScript next to %s."):format(name, script:GetFullName()), 2)
	end
	return require(module)
end

local Access = requireSiblingModule("Access")

local CommandService = {}

CommandService.List = {} -- [name] = { name, help, arguments, permission, usage }

local function notify(player, text, notifyType, length)
	Remotes.Notify:FireClient(player, text, notifyType or "error", length or 5000)
end

CommandService.Notify = notify

local function usageString(name, arguments)
	local parts = { "/" .. name }
	for _, argument in ipairs(arguments or {}) do
		parts[#parts + 1] = ("[%s]"):format(argument.name or "?")
	end
	return table.concat(parts, " ")
end

function CommandService.Add(name, help, arguments, argsRequired, callback, permission, secondaryAlias)
	assert(type(name) == "string" and #name > 0, "CommandService.Add: name must be a non-empty string")
	assert(type(callback) == "function", "CommandService.Add: callback must be a function")

	name = name:lower()
	if CommandService.List[name] then
		warn(("[QBCore.CommandService] Command %q registered twice; keeping the first."):format(name))
		return
	end

	permission = permission or "user"
	arguments = type(arguments) == "table" and arguments or {}
	local usage = usageString(name, arguments)

	local command = Instance.new("TextChatCommand")
	command.Name = "QBCommand_" .. name
	command.PrimaryAlias = "/" .. name
	if type(secondaryAlias) == "string" and #secondaryAlias > 0 then
		command.SecondaryAlias = "/" .. secondaryAlias:lower()
	end

	command.Triggered:Connect(function(textSource, unfilteredText)
		local player = Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			return
		end

		if not Access.HasPermission(player.UserId, permission) then
			notify(player, ("You don't have permission to use /%s."):format(name))
			return
		end

		local args = {}
		for token in unfilteredText:gmatch("%S+") do
			args[#args + 1] = token
		end
		table.remove(args, 1) -- the alias itself

		if argsRequired and #args < #arguments then
			notify(player, "Usage: " .. usage)
			return
		end

		local ok, err = pcall(callback, player, args, unfilteredText)
		if not ok then
			warn(
				("[QBCore.CommandService] /%s errored for %s (%d): %s"):format(
					name,
					player.Name,
					player.UserId,
					tostring(err)
				)
			)
			notify(player, "That command failed to run.")
		end
	end)

	command.Parent = TextChatService

	CommandService.List[name] = {
		name = name,
		help = help or "",
		arguments = arguments,
		permission = permission,
		usage = usage,
	}
end

-- Commands the given user is allowed to run, sorted by name (used by /commands).
function CommandService.GetVisibleCommands(userId)
	local visible = {}
	for _, info in pairs(CommandService.List) do
		if Access.HasPermission(userId, info.permission) then
			visible[#visible + 1] = info
		end
	end
	table.sort(visible, function(a, b)
		return a.name < b.name
	end)
	return visible
end

return CommandService
