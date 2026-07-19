-- Shared toolbox for the route-style civilian jobs (garbage, delivery, bus,
-- taxi, tow). This module deliberately does not run any job's flow — each job
-- service owns its own loop in its own file. What lives here is only the
-- mechanics every route job needs identically: ground-snapped prompt POIs, a
-- single work session per player with a job vehicle, objective pushes for the
-- client waypoint, escrowed earnings paid out on shift end, disposable NPCs,
-- and cleanup when the player leaves or the job vehicle is destroyed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.QBRemotes)

local JobRouteKit = {}

local PROPS_FOLDER_NAME = "QBJobProps"
local NPC_FOLDER_NAME = "QBJobNPCs"

local started = false
local playerService = nil
local vehicleService = nil
local sessions = {} -- [Player] = session

-- ─────────────────────────── value coercion ───────────────────────────

function JobRouteKit.VectorFrom(value)
	if typeof(value) == "Vector3" then
		return value
	end
	if typeof(value) == "CFrame" then
		return value.Position
	end
	if type(value) == "table" then
		if typeof(value.position) == "Vector3" then
			return value.position
		end
		local x, y, z = tonumber(value.x or value[1]), tonumber(value.y or value[2]), tonumber(value.z or value[3])
		if x and y and z then
			return Vector3.new(x, y, z)
		end
	end
	return nil
end

function JobRouteKit.CFrameFrom(value)
	if typeof(value) == "CFrame" then
		return value
	end
	local position = JobRouteKit.VectorFrom(value)
	if not position then
		return nil
	end
	local heading = type(value) == "table" and tonumber(value.heading) or nil
	if heading then
		return CFrame.new(position) * CFrame.Angles(0, math.rad(heading), 0)
	end
	return CFrame.new(position)
end

-- Job configs author positions with y = 0 and let the server find the ground,
-- so hand-authored coords stay valid even when district terrain heights move.
function JobRouteKit.SnapToGround(position, extraHeight)
	position = JobRouteKit.VectorFrom(position)
	if not position then
		return nil
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = {}
	local spawned = Workspace:FindFirstChild("SpawnedVehicles")
	if spawned then
		table.insert(filter, spawned)
	end
	local props = Workspace:FindFirstChild(PROPS_FOLDER_NAME)
	if props then
		table.insert(filter, props)
	end
	params.FilterDescendantsInstances = filter

	local origin = Vector3.new(position.X, math.max(position.Y, 0) + 500, position.Z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -1000, 0), params)
	local groundY = result and result.Position.Y or position.Y
	return Vector3.new(position.X, groundY + (tonumber(extraHeight) or 0), position.Z)
end

function JobRouteKit.GroundCFrame(value, extraHeight)
	local cframe = JobRouteKit.CFrameFrom(value)
	if not cframe then
		return nil
	end
	local snapped = JobRouteKit.SnapToGround(cframe.Position, extraHeight)
	return CFrame.new(snapped) * (cframe - cframe.Position)
end

-- ─────────────────────────── proximity helpers ───────────────────────────

local function getRoot(player)
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

function JobRouteKit.CloseTo(player, position, maxDistance)
	local root = getRoot(player)
	position = JobRouteKit.VectorFrom(position)
	if not root or not position then
		return false
	end
	local offset = root.Position - position
	-- Ignore height: authored coords are ground-snapped and characters stand above them.
	return Vector2.new(offset.X, offset.Z).Magnitude <= (tonumber(maxDistance) or 14)
end

function JobRouteKit.VehicleNear(vehicle, position, maxDistance)
	if not vehicle or not vehicle.Parent or not vehicleService then
		return false
	end
	position = JobRouteKit.VectorFrom(position)
	local vehiclePosition = vehicleService.GetVehiclePosition(vehicle)
	if not position or not vehiclePosition then
		return false
	end
	local offset = vehiclePosition - position
	return Vector2.new(offset.X, offset.Z).Magnitude <= (tonumber(maxDistance) or 30)
end

-- ─────────────────────────── world folders ───────────────────────────

local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

function JobRouteKit.GetPropsFolder(subfolderName)
	local root = ensureFolder(Workspace, PROPS_FOLDER_NAME)
	if type(subfolderName) == "string" and subfolderName ~= "" then
		return ensureFolder(root, subfolderName)
	end
	return root
end

-- ─────────────────────────── prompt POIs ───────────────────────────

-- Creates an invisible anchored part with a ProximityPrompt, ground-snapped,
-- mirroring the PoliceService interaction pattern. opts:
--   name, position (required), actionText, objectText, holdDuration,
--   promptDistance, actionDistance, attributes (table), parent (folder),
--   visiblePart (bool: render a small marker instead of invisible),
--   onTriggered(player, playerObj) (required)
function JobRouteKit.CreatePOI(opts)
	local position = JobRouteKit.SnapToGround(opts.position, 1.5)
	if not position then
		warn(("[QBCore.JobRouteKit] Invalid POI position for %s."):format(tostring(opts.name)))
		return nil
	end

	local part = Instance.new("Part")
	part.Name = tostring(opts.name or "JobPOI")
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.CastShadow = false
	part.Transparency = opts.visiblePart and 0 or 1
	part.Size = opts.size or Vector3.new(2, 2, 2)
	if opts.visiblePart then
		part.Color = opts.color or Color3.fromRGB(235, 184, 76)
		part.Material = Enum.Material.SmoothPlastic
	end
	part.CFrame = CFrame.new(position)
	if type(opts.attributes) == "table" then
		for attributeName, value in pairs(opts.attributes) do
			part:SetAttribute(attributeName, value)
		end
	end
	part.Parent = opts.parent or JobRouteKit.GetPropsFolder()

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "JobPrompt"
	prompt.ActionText = tostring(opts.actionText or "Interact")
	prompt.ObjectText = tostring(opts.objectText or "Job")
	prompt.KeyboardKeyCode, prompt.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
	prompt.HoldDuration = tonumber(opts.holdDuration) or 0.15
	prompt.MaxActivationDistance = math.max(1, tonumber(opts.promptDistance) or 10)
	prompt.RequiresLineOfSight = false
	prompt.Enabled = opts.enabled ~= false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player)
		local playerObj = playerService and playerService.GetPlayer(player.UserId)
		if not playerObj then
			return
		end
		if not JobRouteKit.CloseTo(player, position, math.max(1, tonumber(opts.actionDistance) or 14)) then
			playerObj:Notify("Move closer.", "error", 3000)
			return
		end
		opts.onTriggered(player, playerObj)
	end)

	return part, prompt
end

-- ─────────────────────────── client objective sync ───────────────────────────

local function pushObjective(session)
	local player = session.player
	if not player or player.Parent ~= Players then
		return
	end
	local objective = session.objective
	Remotes.JobRouteUpdated:FireClient(player, {
		jobName = session.jobName,
		jobLabel = session.jobLabel,
		label = objective and objective.label or nil,
		detail = objective and objective.detail or nil,
		position = objective and objective.position or nil,
		progress = session.progress,
		earnings = session.earnings,
	})
end

local function clearObjective(player)
	if player and player.Parent == Players then
		Remotes.JobRouteUpdated:FireClient(player, nil)
	end
end

-- ─────────────────────────── sessions ───────────────────────────

function JobRouteKit.GetSession(player)
	return sessions[player]
end

-- def: jobName (must match PlayerData.job.name), jobLabel, vehicleName,
--      vehicleSpawn ({position, heading}), onEnded(session, reason)?
-- Returns session or nil, errorMessage.
function JobRouteKit.Begin(player, playerObj, def)
	if sessions[player] then
		return nil, "You are already working. Finish or end your current shift first."
	end

	local job = playerObj.PlayerData and playerObj.PlayerData.job
	if type(job) ~= "table" or job.name ~= def.jobName then
		return nil, ("You need the %s job for this. Visit City Hall to apply."):format(tostring(def.jobLabel or def.jobName))
	end

	local spawnCFrame = JobRouteKit.GroundCFrame(def.vehicleSpawn, 3)
	if not spawnCFrame then
		return nil, "This job has no valid vehicle spawn configured."
	end

	local vehicle, definitionOrError = vehicleService.SpawnVehicle(player, def.vehicleName, {
		cframe = spawnCFrame,
		attributes = { QBJobVehicle = def.jobName },
	})
	if not vehicle then
		return nil, definitionOrError
	end

	local session = {
		player = player,
		playerObj = playerObj,
		jobName = def.jobName,
		jobLabel = def.jobLabel or def.jobName,
		def = def,
		vehicle = vehicle,
		earnings = 0,
		progress = nil,
		objective = nil,
		data = {},
		_connections = {},
		_ended = false,
	}
	sessions[player] = session

	table.insert(session._connections, vehicle.AncestryChanged:Connect(function()
		if not vehicle:IsDescendantOf(Workspace) and not session._ended then
			playerObj:Notify("Your work vehicle was lost. Shift ended.", "error", 5000)
			JobRouteKit.End(player, { reason = "vehicle_lost" })
		end
	end))

	return session
end

function JobRouteKit.SetObjective(session, objective, progressText)
	if not session or session._ended then
		return
	end
	if objective then
		local position = JobRouteKit.VectorFrom(objective.position)
		session.objective = {
			label = tostring(objective.label or "Objective"),
			detail = objective.detail and tostring(objective.detail) or nil,
			position = position and JobRouteKit.SnapToGround(position, 2) or nil,
		}
	else
		session.objective = nil
	end
	if progressText ~= nil then
		session.progress = tostring(progressText)
	end
	pushObjective(session)
end

function JobRouteKit.AddEarnings(session, amount, quiet)
	amount = math.floor(tonumber(amount) or 0)
	if not session or session._ended or amount <= 0 then
		return
	end
	session.earnings += amount
	if not quiet then
		session.playerObj:Notify(("+$%d earned (total $%d this shift)."):format(amount, session.earnings), "success", 3000)
	end
	pushObjective(session)
end

-- opts: bonus (number, only paid when the service decides the shift completed),
--       reason ("finished" | "quit" | "vehicle_lost" | "left").
function JobRouteKit.End(player, opts)
	local session = sessions[player]
	if not session or session._ended then
		return false
	end
	session._ended = true
	sessions[player] = nil
	opts = type(opts) == "table" and opts or {}

	for _, connection in ipairs(session._connections) do
		connection:Disconnect()
	end

	local bonus = math.floor(tonumber(opts.bonus) or 0)
	local total = session.earnings + math.max(bonus, 0)
	if total > 0 then
		if session.playerObj:AddMoney("bank", total, session.jobName .. "_shift") then
			if opts.reason ~= "left" then
				local message = bonus > 0
						and ("Shift complete: $%d earned plus a $%d bonus deposited."):format(session.earnings, bonus)
					or ("Shift over: $%d deposited into your bank."):format(total)
				session.playerObj:Notify(message, "success", 5000)
			end
		else
			warn(("[QBCore.JobRouteKit] Could not deposit $%d for %s."):format(total, tostring(player)))
		end
	end

	if session.vehicle and session.vehicle.Parent then
		session.vehicle:Destroy()
	end
	session.vehicle = nil

	if type(session.def.onEnded) == "function" then
		local ok, err = pcall(session.def.onEnded, session, tostring(opts.reason or "quit"))
		if not ok then
			warn(("[QBCore.JobRouteKit] onEnded for %s failed: %s"):format(session.jobName, tostring(err)))
		end
	end

	clearObjective(player)
	return true
end

-- Spawns an unowned world vehicle (e.g. the tow job's broken-down wreck).
-- Scripts are disabled so nobody can drive off with it. Returns the vehicle
-- instance or nil, errorMessage.
function JobRouteKit.SpawnWorldVehicle(vehicleName, positionValue, options)
	options = type(options) == "table" and options or {}
	local cframe = JobRouteKit.GroundCFrame(positionValue, 3)
	if not cframe then
		return nil, "Invalid world-vehicle position."
	end
	return vehicleService.SpawnVehicle(nil, vehicleName, {
		cframe = cframe,
		disableScripts = true,
		anchored = options.anchored,
		attributes = options.attributes,
	})
end

-- ─────────────────────────── disposable NPCs ───────────────────────────

local npcAppearanceSeeds = { 1, 2, 3, 4, 5, 6 }

-- Runtime-generated humanoid rig for bus passengers and taxi fares; no assets
-- required. Returns the model or nil (description building can fail offline).
function JobRouteKit.SpawnNPC(position, opts)
	opts = type(opts) == "table" and opts or {}
	local snapped = JobRouteKit.SnapToGround(position, 3.2)
	if not snapped then
		return nil
	end

	local ok, model = pcall(function()
		local description = Instance.new("HumanoidDescription")
		local seed = npcAppearanceSeeds[math.random(#npcAppearanceSeeds)]
		local skinTones = {
			Color3.fromRGB(234, 184, 146),
			Color3.fromRGB(199, 143, 102),
			Color3.fromRGB(140, 91, 59),
			Color3.fromRGB(90, 57, 36),
		}
		local shirtColors = {
			Color3.fromRGB(196, 40, 28),
			Color3.fromRGB(13, 105, 172),
			Color3.fromRGB(245, 205, 48),
			Color3.fromRGB(75, 151, 75),
			Color3.fromRGB(107, 50, 124),
			Color3.fromRGB(105, 102, 92),
		}
		local skin = skinTones[(seed % #skinTones) + 1]
		description.HeadColor = skin
		description.LeftArmColor = skin
		description.RightArmColor = skin
		description.TorsoColor = shirtColors[math.random(#shirtColors)]
		description.LeftLegColor = shirtColors[math.random(#shirtColors)]
		description.RightLegColor = description.LeftLegColor
		description.HeightScale = 0.92 + math.random() * 0.16
		description.WidthScale = 0.94 + math.random() * 0.12
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[QBCore.JobRouteKit] Could not build NPC model: " .. tostring(model))
		return nil
	end

	model.Name = tostring(opts.name or "QBJobNPC")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = tostring(opts.displayName or "Citizen")
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	model:PivotTo(CFrame.new(snapped) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0))
	model.Parent = ensureFolder(Workspace, NPC_FOLDER_NAME)
	return model
end

-- Walks the NPC toward a position, then destroys it. Fire-and-forget.
function JobRouteKit.WalkNPCToAndRemove(npc, position, timeout)
	if not npc or not npc.Parent then
		return
	end
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local target = JobRouteKit.VectorFrom(position)
	if not humanoid or not target then
		npc:Destroy()
		return
	end
	task.spawn(function()
		humanoid:MoveTo(target)
		local finished = false
		local connection
		connection = humanoid.MoveToFinished:Connect(function()
			finished = true
		end)
		local deadline = os.clock() + (tonumber(timeout) or 8)
		while not finished and os.clock() < deadline and npc.Parent do
			task.wait(0.25)
		end
		if connection then
			connection:Disconnect()
		end
		if npc.Parent then
			npc:Destroy()
		end
	end)
end

-- ─────────────────────────── lifecycle ───────────────────────────

function JobRouteKit.Start(PlayerService, VehicleService)
	if started then
		return
	end
	started = true
	playerService = PlayerService
	vehicleService = VehicleService
end

-- Called from Main's PlayerRemoving handler BEFORE PlayerService.OnPlayerLeave,
-- so shift earnings are deposited while the character can still be saved.
-- (A self-registered PlayerRemoving connection would fire too late: Roblox runs
-- connections newest-first, and Main connects its save handler after Start.)
function JobRouteKit.OnPlayerLeave(player)
	JobRouteKit.End(player, { reason = "left" })
end

return JobRouteKit
