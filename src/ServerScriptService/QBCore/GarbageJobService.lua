-- Garbage collection route job. Clock in at the sanitation depot, drive the
-- truck to randomly drawn dumpster stops, collect every bag at each stop
-- (truck must be parked nearby), then return the truck for a completion bonus.
-- All lifecycle mechanics come from JobRouteKit; this file only owns the
-- garbage-specific flow and props.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QBShared = require(ReplicatedStorage.QBShared.Main)

local GarbageJobService = {}

local started = false
local Kit = nil

local function config()
	return QBShared.Config.GarbageJob or {}
end

local function clearStopProps(session)
	if session.data.stopFolder then
		session.data.stopFolder:Destroy()
		session.data.stopFolder = nil
	end
end

local function progressText(session)
	return ("Stop %d/%d — $%d earned"):format(
		math.min(session.data.stopIndex, #session.data.stops),
		#session.data.stops,
		session.earnings
	)
end

local function objectiveForReturn(session)
	Kit.SetObjective(session, {
		label = "Return the truck",
		detail = config().Depot.label,
		position = config().Depot.position,
	}, ("Route complete — $%d earned"):format(session.earnings))
end

local function spawnStop(session)
	local cfg = config()
	local stopIndex = session.data.stopIndex
	local stopPosition = session.data.stops[stopIndex]
	if not stopPosition then
		session.data.routeComplete = true
		objectiveForReturn(session)
		return
	end

	clearStopProps(session)
	local folder = Instance.new("Folder")
	folder.Name = ("GarbageStop_%d"):format(session.player.UserId)
	folder.Parent = Kit.GetPropsFolder("Garbage")
	session.data.stopFolder = folder

	-- Dumpster prop so the stop is visible from the street.
	local ground = Kit.SnapToGround(stopPosition, 2)
	local dumpster = Instance.new("Part")
	dumpster.Name = "Dumpster"
	dumpster.Anchored, dumpster.CanCollide = true, true
	dumpster.Size = Vector3.new(6, 4, 3)
	dumpster.Color = Color3.fromRGB(52, 84, 60)
	dumpster.Material = Enum.Material.Metal
	dumpster.CFrame = CFrame.new(ground + Vector3.new(0, 0.5, 0))
	dumpster.Parent = folder

	local bagsTotal = math.random(
		math.max(1, tonumber(cfg.BagsPerStop and cfg.BagsPerStop.min) or 1),
		math.max(1, tonumber(cfg.BagsPerStop and cfg.BagsPerStop.max) or 3)
	)
	session.data.bagsRemaining = bagsTotal

	for bagIndex = 1, bagsTotal do
		local angle = (bagIndex / bagsTotal) * math.pi * 2
		local bagPosition = stopPosition + Vector3.new(math.cos(angle) * 5, 0, math.sin(angle) * 5)
		local bagPart
		bagPart = Kit.CreatePOI({
			name = ("TrashBag_%d"):format(bagIndex),
			position = bagPosition,
			actionText = "Collect Bag",
			objectText = "Trash Bag",
			holdDuration = 1,
			promptDistance = cfg.PromptDistance,
			actionDistance = cfg.ActionDistance,
			parent = folder,
			visiblePart = true,
			size = Vector3.new(1.8, 1.8, 1.8),
			color = Color3.fromRGB(35, 38, 42),
			onTriggered = function(player, playerObj)
				local current = Kit.GetSession(player)
				if current ~= session or session.data.stopIndex ~= stopIndex then
					return
				end
				if not Kit.VehicleNear(session.vehicle, stopPosition, cfg.TruckDistance) then
					playerObj:Notify("Bring the garbage truck to this dumpster first.", "error", 3500)
					return
				end
				if bagPart then
					bagPart:Destroy()
				end
				session.data.bagsRemaining -= 1
				Kit.AddEarnings(session, cfg.PayPerBag, true)
				if session.data.bagsRemaining <= 0 then
					playerObj:Notify("Stop cleared. Head to the next dumpster.", "success", 3000)
					session.data.stopIndex += 1
					spawnStop(session)
				else
					playerObj:Notify(
						("Bag collected (+$%d). %d left at this stop."):format(cfg.PayPerBag, session.data.bagsRemaining),
						"success",
						2500
					)
					Kit.SetObjective(session, session.objective, progressText(session))
				end
			end,
		})
	end

	Kit.SetObjective(session, {
		label = "Collect the trash",
		detail = ("%d bag%s at this dumpster"):format(bagsTotal, bagsTotal == 1 and "" or "s"),
		position = stopPosition,
	}, progressText(session))
end

local function buildRoute()
	local cfg = config()
	local pool = {}
	for _, stop in ipairs(cfg.DumpsterStops or {}) do
		table.insert(pool, stop)
	end
	for index = #pool, 2, -1 do
		local swap = math.random(index)
		pool[index], pool[swap] = pool[swap], pool[index]
	end
	local route = {}
	for index = 1, math.min(math.max(1, tonumber(cfg.RouteSize) or 8), #pool) do
		route[index] = pool[index]
	end
	return route
end

local function beginShift(player, playerObj)
	local cfg = config()
	local session, err = Kit.Begin(player, playerObj, {
		jobName = "garbage",
		jobLabel = "Garbage Collector",
		vehicleName = cfg.Vehicle,
		vehicleSpawn = cfg.VehicleSpawn,
		onEnded = clearStopProps,
	})
	if not session then
		playerObj:Notify(err, "error", 5000)
		return
	end

	session.data.stops = buildRoute()
	session.data.stopIndex = 1
	session.data.routeComplete = false
	playerObj:Notify(
		("Shift started: %d dumpster stops on your route. Take the truck."):format(#session.data.stops),
		"success",
		5000
	)
	spawnStop(session)
end

local function endShift(player, playerObj, session)
	local cfg = config()
	local finished = session.data.routeComplete == true
	local bonus = finished and cfg.FinishBonus or 0
	if not finished then
		playerObj:Notify("Shift ended early — route bonus forfeited.", "primary", 4000)
	end
	Kit.End(player, { bonus = bonus, reason = finished and "finished" or "quit" })
end

function GarbageJobService.Start(JobRouteKit)
	if started or config().Enabled == false then
		return
	end
	started = true
	Kit = JobRouteKit

	local cfg = config()
	Kit.CreatePOI({
		name = "GarbageDepot",
		position = cfg.Depot.position,
		actionText = "Garbage Route",
		objectText = cfg.Depot.label or "Sanitation Depot",
		promptDistance = cfg.PromptDistance,
		actionDistance = cfg.ActionDistance,
		attributes = { QBJobDepot = "garbage" },
		onTriggered = function(player, playerObj)
			local session = Kit.GetSession(player)
			if session and session.jobName == "garbage" then
				endShift(player, playerObj, session)
			elseif session then
				playerObj:Notify("Finish your current work shift first.", "error", 3500)
			else
				beginShift(player, playerObj)
			end
		end,
	})
end

return GarbageJobService
