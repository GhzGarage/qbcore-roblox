-- Tow truck dispatch job. Clock in at the impound lot, then wrecks keep
-- coming: drive to the breakdown spot, hook the wreck, haul it to the
-- impound bay, unload, and wait for the next dispatch. This is an
-- open-ended queue, not a route — there is no finish bonus, the player just
-- ends their shift at the depot whenever they're done for the day.
-- All lifecycle mechanics come from JobRouteKit; this file only owns the
-- tow-specific flow and props.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QBShared = require(ReplicatedStorage.QBShared.Main)

local TowJobService = {}

local started = false
local Kit = nil

local function config()
	return QBShared.Config.TowJob or {}
end

local function clearWreckProps(session)
	if session.data.propsFolder then
		session.data.propsFolder:Destroy()
		session.data.propsFolder = nil
	end
end

local function progressText(session)
	return ("Tows: %d — $%d earned"):format(session.data.towCount, session.earnings)
end

-- Tries a random wreck from the pool; on failure, warns and retries once
-- with the next pool entry before giving up.
local function trySpawnWreck(spot)
	local cfg = config()
	local pool = cfg.WreckPool or {}
	if #pool == 0 then
		return nil, "No wreck vehicles configured."
	end

	local spawnOptions = { anchored = true, attributes = { QBJobWreck = "tow" } }
	local index = math.random(#pool)
	local vehicle, err = Kit.SpawnWorldVehicle(pool[index], spot, spawnOptions)
	if vehicle then
		return vehicle
	end
	warn(("[QBCore.TowJobService] Wreck spawn failed for %s: %s"):format(tostring(pool[index]), tostring(err)))

	local nextIndex = (index % #pool) + 1
	if nextIndex == index then
		return nil, err
	end
	vehicle, err = Kit.SpawnWorldVehicle(pool[nextIndex], spot, spawnOptions)
	if vehicle then
		return vehicle
	end
	warn(("[QBCore.TowJobService] Wreck spawn retry failed for %s: %s"):format(tostring(pool[nextIndex]), tostring(err)))
	return nil, err
end

-- Forward-declared: the hook stage and the unload stage dispatch into each
-- other (unload's delayed callback calls back into dispatchWreck).
local dispatchWreck
local spawnUnloadStage

-- Builds the "Unload Vehicle" POI at the impound bay once a wreck is hooked.
spawnUnloadStage = function(session, dispatchNumber, spot)
	local cfg = config()

	clearWreckProps(session)
	local folder = Instance.new("Folder")
	folder.Name = ("TowStop_%d"):format(session.player.UserId)
	folder.Parent = Kit.GetPropsFolder("Tow")
	session.data.propsFolder = folder

	Kit.CreatePOI({
		name = "UnloadWreck",
		position = cfg.DropZone.position,
		actionText = "Unload Vehicle",
		objectText = "Impound Bay",
		holdDuration = 2,
		promptDistance = cfg.PromptDistance,
		actionDistance = cfg.ActionDistance,
		parent = folder,
		onTriggered = function(player, playerObj)
			local current = Kit.GetSession(player)
			if current ~= session or session.data.dispatchNumber ~= dispatchNumber then
				return
			end
			if not session.data.loaded then
				return
			end
			if not Kit.VehicleNear(session.vehicle, cfg.DropZone.position, cfg.HookDistance) then
				playerObj:Notify("Get the tow truck into the impound bay first.", "error", 3500)
				return
			end

			Kit.AddEarnings(session, cfg.PayPerVehicle, true)
			playerObj:Notify(("Wreck impounded (+$%d)."):format(cfg.PayPerVehicle), "success", 3000)
			session.data.towCount += 1
			session.data.loaded = false
			clearWreckProps(session)
			Kit.SetObjective(session, {
				label = "Waiting for dispatch...",
				position = cfg.Depot.position,
			}, progressText(session))

			task.delay(cfg.NextJobDelay, function()
				if Kit.GetSession(player) == session then
					dispatchWreck(session)
				end
			end)
		end,
	})

	Kit.SetObjective(session, {
		label = "Deliver the wreck",
		detail = cfg.Depot.label,
		position = cfg.DropZone.position,
	}, progressText(session))
end

-- Picks a breakdown spot and a wreck, spawns it, and builds the "Hook
-- Vehicle" POI. Called for the first job of a shift and again after every
-- unload once NextJobDelay has passed.
dispatchWreck = function(session)
	local cfg = config()
	local spots = cfg.BreakdownSpots or {}
	if #spots == 0 then
		session.playerObj:Notify("No breakdown spots configured. Shift ended.", "error", 5000)
		Kit.End(session.player, { bonus = 0, reason = "quit" })
		return
	end

	local spotIndex = math.random(#spots)
	while #spots > 1 and spotIndex == session.data.lastSpotIndex do
		spotIndex = math.random(#spots)
	end
	session.data.lastSpotIndex = spotIndex
	local spot = spots[spotIndex]

	local vehicle, err = trySpawnWreck(spot)
	if not vehicle then
		session.playerObj:Notify("Dispatch failed: " .. tostring(err), "error", 5000)
		Kit.End(session.player, { bonus = 0, reason = "quit" })
		return
	end

	session.data.wreck = vehicle
	session.data.loaded = false
	session.data.dispatchNumber += 1
	local dispatchNumber = session.data.dispatchNumber

	clearWreckProps(session)
	local folder = Instance.new("Folder")
	folder.Name = ("TowStop_%d"):format(session.player.UserId)
	folder.Parent = Kit.GetPropsFolder("Tow")
	session.data.propsFolder = folder

	Kit.CreatePOI({
		name = "HookWreck",
		position = spot,
		actionText = "Hook Vehicle",
		objectText = "Broken-down Vehicle",
		holdDuration = 2,
		promptDistance = cfg.PromptDistance,
		actionDistance = cfg.ActionDistance,
		parent = folder,
		onTriggered = function(player, playerObj)
			local current = Kit.GetSession(player)
			if current ~= session or session.data.dispatchNumber ~= dispatchNumber then
				return
			end
			if not Kit.VehicleNear(session.vehicle, spot, cfg.HookDistance) then
				playerObj:Notify("Back the tow truck up to the wreck first.", "error", 3500)
				return
			end

			-- Abstracted load: no physical welding in v1. A future upgrade
			-- could weld a visual clone of the wreck to the truck bed for
			-- the haul instead of despawning it outright.
			if session.data.wreck and session.data.wreck.Parent then
				session.data.wreck:Destroy()
			end
			session.data.wreck = nil
			session.data.loaded = true
			playerObj:Notify("Vehicle loaded. Haul it to the impound lot.", "success", 4000)
			spawnUnloadStage(session, dispatchNumber, spot)
		end,
	})

	Kit.SetObjective(session, {
		label = "Hook the wreck",
		detail = "Broken-down vehicle",
		position = spot,
	}, progressText(session))
end

local function onEnded(session)
	clearWreckProps(session)
	if session.data.wreck and session.data.wreck.Parent then
		session.data.wreck:Destroy()
	end
	session.data.wreck = nil
end

local function beginShift(player, playerObj)
	local cfg = config()
	local session, err = Kit.Begin(player, playerObj, {
		jobName = "tow",
		jobLabel = "Tow Truck Driver",
		vehicleName = cfg.Vehicle,
		vehicleSpawn = cfg.VehicleSpawn,
		onEnded = onEnded,
	})
	if not session then
		playerObj:Notify(err, "error", 5000)
		return
	end

	session.data.towCount = 0
	session.data.dispatchNumber = 0
	session.data.loaded = false
	playerObj:Notify("Shift started. Take the tow truck and wait for dispatch.", "success", 4000)
	dispatchWreck(session)
end

-- Open-ended job: ending the shift is always a clean "finished" end, never
-- a forfeited bonus, since there's no route to leave incomplete.
local function endShift(player, playerObj, session)
	Kit.End(player, { bonus = 0, reason = "finished" })
end

function TowJobService.Start(JobRouteKit)
	if started or config().Enabled == false then
		return
	end
	started = true
	Kit = JobRouteKit

	local cfg = config()
	Kit.CreatePOI({
		name = "TowDepot",
		position = cfg.Depot.position,
		actionText = "Tow Shift",
		objectText = cfg.Depot.label or "Impound Lot",
		promptDistance = cfg.PromptDistance,
		actionDistance = cfg.ActionDistance,
		attributes = { QBJobDepot = "tow" },
		onTriggered = function(player, playerObj)
			local session = Kit.GetSession(player)
			if session and session.jobName == "tow" then
				endShift(player, playerObj, session)
			elseif session then
				playerObj:Notify("Finish your current work shift first.", "error", 3500)
			else
				beginShift(player, playerObj)
			end
		end,
	})
end

return TowJobService
