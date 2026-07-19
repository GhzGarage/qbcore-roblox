-- Native menus for the server-owned QBPoliceJob POIs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Remotes = require(ReplicatedStorage.QBRemotes)
local QBCoreClient = require(ReplicatedStorage.QBCoreClient)

local menuGui = player:WaitForChild("PlayerGui"):WaitForChild("QBMenu")
local openMenuFunction = menuGui:WaitForChild("OpenMenu")

local currentSnapshot = nil
local busy = false

local function notify(message, notifyType)
	QBCoreClient.OnNotify:Fire(tostring(message or "Police request failed."), notifyType or "error", 3500)
end

local function openMenu(items, options)
	local ok, result = pcall(function()
		return openMenuFunction:Invoke(items, options)
	end)
	if not ok then
		warn("[QBPoliceJob] Could not open QBMenu: " .. tostring(result))
	end
	return ok and result
end

local function runAction(action, fields)
	if busy or type(currentSnapshot) ~= "table" then
		return false
	end
	busy = true
	local payload = type(fields) == "table" and fields or {}
	payload.access = currentSnapshot.access
	local invokeOk, ok, message = pcall(function()
		return Remotes.PoliceAction:InvokeServer(action, payload)
	end)
	busy = false
	if not invokeOk then
		notify("Police services did not respond. Please try again.")
		return false
	end
	if not ok then
		notify(message)
		return false
	end
	notify(message, "success")
	return true
end

local function openFleetMenu(snapshot)
	local isHelicopter = snapshot.fleetKind == "helicopter"
	local items = {
		{ header = isHelicopter and "Police Air Support" or "Police Garage", isMenuHeader = true },
	}
	for _, vehicle in ipairs(type(snapshot.vehicles) == "table" and snapshot.vehicles or {}) do
		local vehicleName = vehicle.name
		table.insert(items, {
			header = tostring(vehicle.label or vehicleName or "Fleet Vehicle"),
			txt = isHelicopter and "Retrieve this police aircraft" or "Retrieve this on-duty police vehicle",
			action = function()
				runAction(isHelicopter and "spawn_helicopter" or "spawn_vehicle", { vehicle = vehicleName })
			end,
		})
	end
	if #items == 1 then
		table.insert(items, {
			header = "No vehicles configured",
			txt = isHelicopter and "Add an aircraft definition and model before enabling air support."
				or "Your police grade has no authorized vehicles.",
			disabled = true,
		})
	end
	openMenu(items, {
		title = snapshot.label or "Police Fleet",
		subtitle = isHelicopter and "On-duty air support" or "On-duty motor pool",
	})
end

local function openFingerprintResult(snapshot)
	openMenu({
		{ header = "Fingerprint Result", isMenuHeader = true },
		{ header = tostring(snapshot.name or "Unknown Person"), txt = "Name", disabled = true },
		{ header = tostring(snapshot.citizenId or "Unknown"), txt = "Citizen ID", disabled = true },
		{ header = tostring(snapshot.fingerprint or "No match"), txt = "Fingerprint ID", disabled = true },
	}, {
		title = snapshot.label or "Fingerprint Scanner",
		subtitle = "Verified biometric result",
	})
end

Remotes.OpenPoliceJob.OnClientEvent:Connect(function(snapshot)
	if busy or type(snapshot) ~= "table" then
		return
	end
	currentSnapshot = snapshot
	if snapshot.view == "fleet" then
		openFleetMenu(snapshot)
	elseif snapshot.view == "fingerprint" then
		openFingerprintResult(snapshot)
	else
		notify("That police service is unavailable.")
	end
end)
