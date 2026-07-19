-- Bus driver route job. Clock in at the transit yard (one prompt per route so
-- the driver can pick a line), drive the assigned route's stops in order,
-- park at each stop to let waiting passengers board, then return the bus for
-- a completion bonus. All lifecycle mechanics come from JobRouteKit; this
-- file only owns the bus-specific flow, stop props, and passenger NPCs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QBShared = require(ReplicatedStorage.QBShared.Main)

local BusJobService = {}

local started = false
local Kit = nil

local function config()
	return QBShared.Config.BusJob or {}
end

local function clearStopFolder(session)
	if session.data.stopFolder then
		session.data.stopFolder:Destroy()
		session.data.stopFolder = nil
	end
end

local function progressText(session)
	local route = session.data.route
	return ("Stop %d/%d — $%d earned"):format(
		math.min(session.data.stopIndex, #route.stops),
		#route.stops,
		session.earnings
	)
end

local function objectiveForReturn(session)
	Kit.SetObjective(session, {
		label = "Return to the yard",
		detail = config().Depot.label,
		position = config().Depot.position,
	}, ("Route complete — $%d earned"):format(session.earnings))
end

-- Buses aren't tracked by JobRouteKit's own position helper, so read the
-- pivot directly. Wrapped in pcall since the vehicle may be mid-destruction.
local function getBusPosition(vehicle)
	if not vehicle or not vehicle.Parent then
		return nil
	end
	local ok, cframe = pcall(function()
		return vehicle:GetPivot()
	end)
	if ok and cframe then
		return cframe.Position
	end
	return nil
end

local function spawnStop(session)
	local cfg = config()
	local route = session.data.route
	local stopIndex = session.data.stopIndex
	local stopPosition = route.stops[stopIndex]
	if not stopPosition then
		session.data.routeComplete = true
		objectiveForReturn(session)
		return
	end

	clearStopFolder(session)
	local folder = Instance.new("Folder")
	folder.Name = ("BusStop_%d"):format(session.player.UserId)
	folder.Parent = Kit.GetPropsFolder("Bus")
	session.data.stopFolder = folder

	-- Passengers waiting at this stop; kept local so the "Serve Stop" prompt
	-- below knows exactly who to walk to the bus without touching other stops.
	local stopNPCs = {}
	local passengers = cfg.PassengersPerStop or {}
	local passengerCount = math.random(
		math.max(0, tonumber(passengers.min) or 0),
		math.max(0, tonumber(passengers.max) or 0)
	)
	for _ = 1, passengerCount do
		local angle = math.random() * math.pi * 2
		local distance = 4 + math.random() * 4
		local npcPosition = stopPosition + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local npc = Kit.SpawnNPC(npcPosition, { displayName = "Passenger" })
		if npc then
			table.insert(stopNPCs, npc)
			table.insert(session.data.npcs, npc)
		end
	end

	-- Bus stop sign, visible from the street so the driver can line up the bus.
	Kit.CreatePOI({
		name = "BusStopSign",
		position = stopPosition,
		actionText = "Serve Stop",
		objectText = "Bus Stop",
		holdDuration = 0.5,
		promptDistance = cfg.PromptDistance,
		actionDistance = cfg.ActionDistance,
		parent = folder,
		visiblePart = true,
		size = Vector3.new(0.6, 7, 0.6),
		color = Color3.fromRGB(90, 112, 133),
		onTriggered = function(player, playerObj)
			local current = Kit.GetSession(player)
			if current ~= session or session.data.stopIndex ~= stopIndex or session.data.dwelling then
				return
			end
			if not Kit.VehicleNear(session.vehicle, stopPosition, cfg.BusDistance) then
				playerObj:Notify("Park the bus at the stop first.", "error", 3500)
				return
			end

			session.data.dwelling = true
			playerObj:Notify("Passengers boarding...", "primary", cfg.DwellSeconds * 1000)

			local busPosition = getBusPosition(session.vehicle) or stopPosition
			for _, npc in ipairs(stopNPCs) do
				Kit.WalkNPCToAndRemove(npc, busPosition, 6)
			end

			task.wait(cfg.DwellSeconds)

			-- The shift may have ended during the dwell (vehicle lost, player left);
			-- bail out so we don't spawn props for a dead session.
			if Kit.GetSession(player) ~= session then
				return
			end

			Kit.AddEarnings(session, route.payPerStop, true)
			playerObj:Notify(("Stop served (+$%d)."):format(route.payPerStop), "success", 3000)

			session.data.dwelling = false
			session.data.stopIndex += 1
			spawnStop(session)
		end,
	})

	Kit.SetObjective(session, {
		label = "Drive to the next stop",
		detail = ("%s — stop %d of %d"):format(route.label, stopIndex, #route.stops),
		position = stopPosition,
	}, progressText(session))
end

local function onEnded(session)
	clearStopFolder(session)
	for _, npc in ipairs(session.data.npcs or {}) do
		if npc.Parent then
			npc:Destroy()
		end
	end
end

local function beginShift(player, playerObj, route)
	local cfg = config()
	local session, err = Kit.Begin(player, playerObj, {
		jobName = "bus",
		jobLabel = "Bus Driver",
		vehicleName = cfg.Vehicle,
		vehicleSpawn = cfg.VehicleSpawn,
		onEnded = onEnded,
	})
	if not session then
		playerObj:Notify(err, "error", 5000)
		return
	end

	session.data.route = route
	session.data.stopIndex = 1
	session.data.npcs = {}
	session.data.dwelling = false
	session.data.routeComplete = false
	playerObj:Notify(
		("Shift started: %s (%d stops). Take the bus."):format(route.label, #route.stops),
		"success",
		5000
	)
	spawnStop(session)
end

local function endShift(player, playerObj, session)
	local finished = session.data.routeComplete == true
	local bonus = finished and session.data.route.finishBonus or 0
	if not finished then
		playerObj:Notify("Shift ended early — route bonus forfeited.", "primary", 4000)
	end
	Kit.End(player, { bonus = bonus, reason = finished and "finished" or "quit" })
end

function BusJobService.Start(JobRouteKit)
	if started or config().Enabled == false then
		return
	end
	started = true
	Kit = JobRouteKit

	local cfg = config()
	-- One depot prompt per route, offset so they don't overlap in the yard.
	for index, route in ipairs(cfg.Routes or {}) do
		local depotPosition = cfg.Depot.position + Vector3.new((index - 1) * 6, 0, 0)
		Kit.CreatePOI({
			name = ("BusDepot_%s"):format(route.id or tostring(index)),
			position = depotPosition,
			actionText = ("Start: %s"):format(route.label),
			objectText = cfg.Depot.label,
			promptDistance = cfg.PromptDistance,
			actionDistance = cfg.ActionDistance,
			attributes = { QBJobDepot = "bus" },
			onTriggered = function(player, playerObj)
				local session = Kit.GetSession(player)
				if session and session.jobName == "bus" then
					endShift(player, playerObj, session)
				elseif session then
					playerObj:Notify("Finish your current work shift first.", "error", 3500)
				else
					beginShift(player, playerObj, route)
				end
			end,
		})
	end
end

return BusJobService
