-- Taxi driver route job. Clock in at the cab stand, then ferry randomly
-- dispatched fares between pickup and dropoff stops drawn far apart on the
-- map. The destination is hidden until the passenger is actually picked up,
-- payout scales with the straight-line trip distance, and the next fare
-- dispatches automatically after a short delay — the shift is open-ended
-- and only stops when the player ends it back at the cab stand.
-- All lifecycle mechanics come from JobRouteKit; this file only owns the
-- taxi-specific flow and passenger props.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QBShared = require(ReplicatedStorage.QBShared.Main)

local TaxiJobService = {}

local started = false
local Kit = nil

-- Small pool of first names handed to dispatched fares; no assets required.
local FARE_NAMES = { "Marge", "Otis", "Priya", "Dmitri", "Wanda", "Lou", "Nadia", "Hank", "Fiona", "Carlos" }

local function config()
	return QBShared.Config.TaxiJob or {}
end

local function xzDistance(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Random point offset on the XZ plane, distance between minDist and maxDist.
local function randomOffset(minDist, maxDist)
	local angle = math.random() * math.pi * 2
	local distance = minDist + math.random() * math.max(0, maxDist - minDist)
	return Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local function clearFareProps(session)
	if session.data.fareFolder then
		session.data.fareFolder:Destroy()
		session.data.fareFolder = nil
	end
end

local function progressText(session)
	return ("Fares: %d — $%d earned"):format(session.data.fareCount, session.earnings)
end

-- Draws a pickup/dropoff pair at least MinFareDistance apart on the XZ plane.
-- The stop pool is authored so such a pair always exists.
local function pickFarePair(cfg)
	local stops = cfg.FareStops or {}
	local minDistance = tonumber(cfg.MinFareDistance) or 0
	local pickup, dropoff
	repeat
		pickup = stops[math.random(#stops)]
		dropoff = stops[math.random(#stops)]
	until pickup and dropoff and xzDistance(pickup, dropoff) >= minDistance
	return pickup, dropoff
end

local function dispatchFare(session)
	local cfg = config()
	local pickup, dropoff = pickFarePair(cfg)
	local name = FARE_NAMES[math.random(#FARE_NAMES)]
	local fareNumber = session.data.fareCount -- identifies this fare for stale-trigger guards

	clearFareProps(session)
	local folder = Instance.new("Folder")
	folder.Name = tostring(session.player.UserId)
	folder.Parent = Kit.GetPropsFolder("Taxi")
	session.data.fareFolder = folder

	local npc = Kit.SpawnNPC(pickup + randomOffset(2, 4), { displayName = name })
	if npc then
		table.insert(session.data.npcs, npc)
	end

	local pickupPOI
	pickupPOI = Kit.CreatePOI({
		name = "TaxiPickup",
		position = pickup,
		actionText = "Pick Up Fare",
		objectText = name,
		holdDuration = 0.5,
		promptDistance = cfg.PromptDistance,
		actionDistance = cfg.ActionDistance,
		parent = folder,
		onTriggered = function(player, playerObj)
			local current = Kit.GetSession(player)
			if current ~= session or session.data.fareCount ~= fareNumber then
				return
			end
			if not Kit.VehicleNear(session.vehicle, pickup, cfg.PickupDistance) then
				playerObj:Notify("Bring the cab to the passenger.", "error", 3500)
				return
			end

			if npc and npc.Parent then
				local ok, pivot = pcall(function()
					return session.vehicle:GetPivot()
				end)
				if ok and pivot then
					Kit.WalkNPCToAndRemove(npc, pivot.Position, 6)
				else
					npc:Destroy()
				end
			end

			if pickupPOI then
				pickupPOI:Destroy()
				pickupPOI = nil
			end
			playerObj:Notify(("%s hopped in. Destination revealed."):format(name), "success", 3500)

			-- Dropoff is only revealed now — nothing about it exists before pickup.
			Kit.CreatePOI({
				name = "TaxiDropoff",
				position = dropoff,
				actionText = "Drop Off Fare",
				objectText = name,
				holdDuration = 0.5,
				promptDistance = cfg.PromptDistance,
				actionDistance = cfg.ActionDistance,
				parent = folder,
				onTriggered = function(dropPlayer, dropPlayerObj)
					local dropCurrent = Kit.GetSession(dropPlayer)
					if dropCurrent ~= session or session.data.fareCount ~= fareNumber then
						return
					end
					if not Kit.VehicleNear(session.vehicle, dropoff, cfg.PickupDistance) then
						dropPlayerObj:Notify("Bring the cab to the destination.", "error", 3500)
						return
					end

					local fare = math.floor(cfg.FareBase + xzDistance(pickup, dropoff) * cfg.PayPerStud)
					Kit.AddEarnings(session, fare, true)
					dropPlayerObj:Notify(("Fare paid $%d."):format(fare), "success", 3500)

					-- Passenger hops out and walks off while the next fare spins up.
					local dropoffNPC = Kit.SpawnNPC(dropoff + randomOffset(2, 4), { displayName = name })
					if dropoffNPC then
						table.insert(session.data.npcs, dropoffNPC)
						Kit.WalkNPCToAndRemove(dropoffNPC, dropoff + randomOffset(15, 15), 8)
					end

					session.data.fareCount += 1
					Kit.SetObjective(session, {
						label = "Waiting for dispatch...",
					}, progressText(session))

					task.delay(cfg.NextFareDelay, function()
						if Kit.GetSession(session.player) == session then
							dispatchFare(session)
						end
					end)
				end,
			})

			Kit.SetObjective(session, {
				label = "Drop off the fare",
				detail = ("Fare: %s"):format(name),
				position = dropoff,
			}, progressText(session))
		end,
	})

	Kit.SetObjective(session, {
		label = "Pick up the fare",
		detail = ("Pick up %s"):format(name),
		position = pickup,
	}, progressText(session))
end

local function onFareEnded(session)
	clearFareProps(session)
	for _, npc in ipairs(session.data.npcs) do
		if npc and npc.Parent then
			npc:Destroy()
		end
	end
end

local function beginShift(player, playerObj)
	local cfg = config()
	local session, err = Kit.Begin(player, playerObj, {
		jobName = "taxi",
		jobLabel = "Taxi Driver",
		vehicleName = cfg.Vehicle,
		vehicleSpawn = cfg.VehicleSpawn,
		onEnded = onFareEnded,
	})
	if not session then
		playerObj:Notify(err, "error", 5000)
		return
	end

	session.data.fareCount = 0
	session.data.npcs = {}
	playerObj:Notify("Shift started. Fares keep coming until you end the shift at the cab stand.", "success", 5000)
	dispatchFare(session)
end

-- Open-ended job: ending the shift always pays out whatever was earned so
-- far, no completion bonus.
local function endShift(player, playerObj, session)
	Kit.End(player, { bonus = 0, reason = "finished" })
end

function TaxiJobService.Start(JobRouteKit)
	if started or config().Enabled == false then
		return
	end
	started = true
	Kit = JobRouteKit

	local cfg = config()
	Kit.CreatePOI({
		name = "TaxiDepot",
		position = cfg.Depot.position,
		actionText = "Taxi Shift",
		objectText = cfg.Depot.label or "Cab Stand",
		promptDistance = cfg.PromptDistance,
		actionDistance = cfg.ActionDistance,
		attributes = { QBJobDepot = "taxi" },
		onTriggered = function(player, playerObj)
			local session = Kit.GetSession(player)
			if session and session.jobName == "taxi" then
				endShift(player, playerObj, session)
			elseif session then
				playerObj:Notify("Finish your current work shift first.", "error", 3500)
			else
				beginShift(player, playerObj)
			end
		end,
	})
end

return TaxiJobService
