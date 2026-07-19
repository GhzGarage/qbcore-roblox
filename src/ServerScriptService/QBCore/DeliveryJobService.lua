-- Delivery driver route job. Clock in at the parcel warehouse, drive the van
-- to randomly drawn doorsteps, carry the package to each door (van must be
-- parked nearby), then return the van for a completion bonus. All lifecycle
-- mechanics come from JobRouteKit; this file only owns the delivery-specific
-- flow and props.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QBShared = require(ReplicatedStorage.QBShared.Main)

local DeliveryJobService = {}

local started = false
local Kit = nil

local function config()
	return QBShared.Config.DeliveryJob or {}
end

local function clearStopProps(session)
	if session.data.stopFolder then
		session.data.stopFolder:Destroy()
		session.data.stopFolder = nil
	end
end

local function progressText(session)
	return ("Delivery %d/%d — $%d earned"):format(
		math.min(session.data.stopIndex, #session.data.stops),
		#session.data.stops,
		session.earnings
	)
end

local function objectiveForReturn(session)
	Kit.SetObjective(session, {
		label = "Return the van",
		detail = config().Depot.label,
		position = config().Depot.position,
	}, ("Route complete — $%d earned"):format(session.earnings))
end

-- Straight-line XZ distance from the depot, used for the distance pay bonus.
local function payForStop(cfg, stopPosition)
	local depotPosition = cfg.Depot.position
	local offset = Vector2.new(stopPosition.X - depotPosition.X, stopPosition.Z - depotPosition.Z)
	return math.floor((tonumber(cfg.PayBase) or 0) + offset.Magnitude * (tonumber(cfg.PayPerStud) or 0))
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
	folder.Name = ("DeliveryStop_%d"):format(session.player.UserId)
	folder.Parent = Kit.GetPropsFolder("Delivery")
	session.data.stopFolder = folder

	local pay = payForStop(cfg, stopPosition)

	-- Single prompt per stop: holding it simulates carrying the box to the door.
	Kit.CreatePOI({
		name = "DoorstepPad",
		position = stopPosition,
		actionText = "Deliver Package",
		objectText = "Delivery Address",
		holdDuration = 1.5,
		promptDistance = cfg.PromptDistance,
		actionDistance = cfg.ActionDistance,
		parent = folder,
		visiblePart = true,
		size = Vector3.new(3, 0.5, 3),
		color = Color3.fromRGB(196, 164, 116),
		onTriggered = function(player, playerObj)
			local current = Kit.GetSession(player)
			if current ~= session or session.data.stopIndex ~= stopIndex then
				return
			end
			if not Kit.VehicleNear(session.vehicle, stopPosition, cfg.VanDistance) then
				playerObj:Notify("Bring the delivery van to this address first.", "error", 3500)
				return
			end

			Kit.AddEarnings(session, pay, true)
			session.data.stopIndex += 1
			local remaining = #session.data.stops - (session.data.stopIndex - 1)
			playerObj:Notify(
				("Package delivered (+$%d). %d remaining."):format(pay, remaining),
				"success",
				3000
			)
			spawnStop(session)
		end,
	})

	Kit.SetObjective(session, {
		label = "Deliver the package",
		detail = "Park the van and carry it to the door",
		position = stopPosition,
	}, progressText(session))
end

local function buildRoute()
	local cfg = config()
	local pool = {}
	for _, stop in ipairs(cfg.Doorsteps or {}) do
		table.insert(pool, stop)
	end
	for index = #pool, 2, -1 do
		local swap = math.random(index)
		pool[index], pool[swap] = pool[swap], pool[index]
	end
	local route = {}
	for index = 1, math.min(math.max(1, tonumber(cfg.RouteSize) or 7), #pool) do
		route[index] = pool[index]
	end
	return route
end

local function beginShift(player, playerObj)
	local cfg = config()
	local session, err = Kit.Begin(player, playerObj, {
		jobName = "delivery",
		jobLabel = "Delivery Driver",
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
		("Shift started: %d packages on your route. Take the van."):format(#session.data.stops),
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

function DeliveryJobService.Start(JobRouteKit)
	if started or config().Enabled == false then
		return
	end
	started = true
	Kit = JobRouteKit

	local cfg = config()
	Kit.CreatePOI({
		name = "DeliveryDepot",
		position = cfg.Depot.position,
		actionText = "Delivery Route",
		objectText = cfg.Depot.label or "Parcel Warehouse",
		promptDistance = cfg.PromptDistance,
		actionDistance = cfg.ActionDistance,
		attributes = { QBJobDepot = "delivery" },
		onTriggered = function(player, playerObj)
			local session = Kit.GetSession(player)
			if session and session.jobName == "delivery" then
				endShift(player, playerObj, session)
			elseif session then
				playerObj:Notify("Finish your current work shift first.", "error", 3500)
			else
				beginShift(player, playerObj)
			end
		end,
	})
end

return DeliveryJobService
