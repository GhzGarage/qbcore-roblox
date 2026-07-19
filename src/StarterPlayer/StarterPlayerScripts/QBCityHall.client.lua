-- Native QBMenu presentation for City Hall. The server owns all eligibility,
-- pricing, proximity, money, inventory, and job-assignment decisions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QBCoreClient = require(ReplicatedStorage.QBCoreClient)
local Remotes = require(ReplicatedStorage.QBRemotes)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local menuGui = playerGui:WaitForChild("QBMenu")
local openMenuFunction = menuGui:WaitForChild("OpenMenu")

local currentSnapshot
local requestBusy = false

local function notify(message, notifyType, duration)
	QBCoreClient.OnNotify:Fire(tostring(message or "City Hall request failed."), notifyType or "error", duration or 3500)
end

local function openMenu(items, options)
	local ok, result = pcall(function()
		return openMenuFunction:Invoke(items, options)
	end)
	if not ok then
		warn("[QBCityHall] Could not open QBMenu: " .. tostring(result))
	end
	return ok and result
end

local openMainMenu
local openDocumentMenu
local openJobMenu

local function runAction(action, fields)
	if requestBusy or not currentSnapshot then
		return false
	end
	requestBusy = true
	local payload = type(fields) == "table" and fields or {}
	payload.access = currentSnapshot.access
	local invokeOk, ok, message = pcall(function()
		return Remotes.CityHallAction:InvokeServer(action, payload)
	end)
	requestBusy = false
	if not invokeOk then
		notify("City Hall did not respond. Please try again.")
		return false
	end
	if not ok then
		notify(message)
		return false
	end
	return true
end

openMainMenu = function()
	if not currentSnapshot then
		return
	end
	openMenu({
		{ header = currentSnapshot.label or "City Hall", isMenuHeader = true },
		{
			header = "Identity & Licenses",
			txt = "Order an eligible government document",
			shouldClose = false,
			action = openDocumentMenu,
		},
		{
			header = "Job Center",
			txt = "Choose from available public jobs",
			shouldClose = false,
			action = openJobMenu,
		},
	}, {
		title = currentSnapshot.label or "City Hall",
		subtitle = "City services",
	})
end

openDocumentMenu = function()
	if not currentSnapshot then
		return
	end
	local items = {
		{ header = "Identity & Licenses", isMenuHeader = true },
		{
			header = "< Back",
			txt = "Return to City Hall",
			shouldClose = false,
			action = openMainMenu,
		},
	}
	for _, document in ipairs(currentSnapshot.documents or {}) do
		local documentName = document.name
		local documentLabel = document.label
		local documentCost = document.cost
		table.insert(items, {
			header = tostring(documentLabel or documentName),
			txt = ("Order instantly - $%d cash"):format(math.max(0, tonumber(documentCost) or 0)),
			action = function()
				runAction("order_document", { document = documentName })
			end,
		})
	end
	if #(currentSnapshot.documents or {}) == 0 then
		table.insert(items, {
			header = "No documents available",
			txt = "You are not currently eligible for a document.",
			disabled = true,
		})
	end
	openMenu(items, { title = "Identity & Licenses", subtitle = "Documents are issued immediately" })
end

openJobMenu = function()
	if not currentSnapshot then
		return
	end
	local items = {
		{ header = "Job Center", isMenuHeader = true },
		{
			header = "< Back",
			txt = "Return to City Hall",
			shouldClose = false,
			action = openMainMenu,
		},
	}
	for _, job in ipairs(currentSnapshot.jobs or {}) do
		local jobName = job.name
		local jobLabel = job.label
		table.insert(items, {
			header = tostring(jobLabel or jobName),
			txt = "Start this job immediately",
			action = function()
				runAction("select_job", { job = jobName })
			end,
		})
	end
	if #(currentSnapshot.jobs or {}) == 0 then
		table.insert(items, {
			header = "No public jobs available",
			txt = "Please check back later.",
			disabled = true,
		})
	end
	openMenu(items, { title = "Job Center", subtitle = "Police, EMS, and mechanic are restricted" })
end

Remotes.OpenCityHall.OnClientEvent:Connect(function(access)
	if requestBusy then
		return
	end
	requestBusy = true
	local invokeOk, snapshot, err = pcall(function()
		return Remotes.GetCityHall:InvokeServer(access)
	end)
	requestBusy = false
	if not invokeOk then
		notify("City Hall did not respond. Please try again.")
		return
	end
	if type(snapshot) ~= "table" then
		notify(err or "City Hall is unavailable.")
		return
	end
	currentSnapshot = snapshot
	openMainMenu()
end)
