-- Server-authoritative medical item handlers and life-state tracking.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local QBShared = require(ReplicatedStorage.QBShared.Main)
local Remotes = require(ReplicatedStorage.QBRemotes)
local PlayerService = require(script.Parent.PlayerService)

local MedicalService = {}

local DEFAULT_BANDAGE_HEAL = 20
local DEFAULT_REVIVE_DISTANCE = 10
local DEFAULT_REVIVE_HEALTH = 40
local FULL_ARMOR = 100
local REGISTERED_WEAPON_TOOL_ATTRIBUTE = "QBWeaponTool"
local HOSPITAL_INTERACTION_FOLDER = "QBHospitalInteractions"
local HOSPITAL_ACTION_COOLDOWN = 0.35

local started = false
local weaponsBound = false
local weaponsFolderConnection = nil
local characterConnections = {}
local humanoidConnections = {}
local deathTimes = {}
local inventoryService
local vehicleService
local bankingService
local treatmentSessions = {}
local checkInBusy = {}
local bedOccupancy = {}
local jobVehicles = {}
local lastHospitalActionAt = {}
local lastDoctorCallAt = {}

local function clampPercent(value)
	return math.clamp(tonumber(value) or 0, 0, 100)
end

local function getDeathScreenConfig()
	local medical = QBShared.Config.Medical or {}
	return type(medical.DeathScreen) == "table" and medical.DeathScreen or {}
end

local function getRespawnConfig()
	local medical = QBShared.Config.Medical or {}
	return type(medical.Respawn) == "table" and medical.Respawn or {}
end

local function getRespawnDelay()
	return math.max(0, tonumber(getDeathScreenConfig().RespawnDelay) or 30)
end

local function getRespawnHealth()
	return math.max(1, tonumber(getRespawnConfig().Health) or 100)
end

local function getHospitalConfig()
	local medical = QBShared.Config.Medical or {}
	return type(medical.Hospital) == "table" and medical.Hospital or {}
end

local function trim(value)
	return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

local function vectorFrom(value)
	if typeof(value) == "Vector3" then
		return value
	end
	if type(value) == "table" then
		local source = value.position or value.coords or value
		if typeof(source) == "Vector3" then
			return source
		end
		local x = tonumber(source.x or source.X)
		local y = tonumber(source.y or source.Y)
		local z = tonumber(source.z or source.Z)
		if x and y and z then
			return Vector3.new(x, y, z)
		end
	end
	return nil
end

local function cframeFrom(value, fallbackHeading)
	local position = vectorFrom(value)
	if not position then
		return nil
	end
	local heading = tonumber(type(value) == "table" and (value.heading or value.ry)) or fallbackHeading or 0
	return CFrame.new(position) * CFrame.Angles(0, math.rad(heading), 0)
end

local function hospitalById(id)
	id = trim(id)
	for _, hospital in ipairs(getHospitalConfig().Hospitals or {}) do
		if trim(hospital.id) == id then
			return hospital
		end
	end
	return nil
end

local function jobGrade(playerObj)
	local job = type(playerObj and playerObj.PlayerData.job) == "table" and playerObj.PlayerData.job or {}
	local grade = type(job.grade) == "table" and job.grade or {}
	return math.max(0, math.floor(tonumber(grade.level) or 0))
end

local function getRobloxPlayer(playerObj)
	local player = playerObj and playerObj._source
	if typeof(player) == "Instance" and player:IsA("Player") then
		return player
	end
	return nil
end

local function getHumanoid(player)
	local character = player and player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function getRoot(player)
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function closeToPoints(player, points, maxDistance)
	local root = getRoot(player)
	if not root then
		return false
	end
	for _, point in ipairs(type(points) == "table" and points or {}) do
		local position = vectorFrom(point)
		if position and (root.Position - position).Magnitude <= maxDistance then
			return true
		end
	end
	return false
end

local function destroyRegisteredWeaponTools(container)
	if not container then
		return
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute(REGISTERED_WEAPON_TOOL_ATTRIBUTE) == true then
			child:Destroy()
		end
	end
end

local function clearActiveInventoryTools(player)
	if not player then
		return
	end

	destroyRegisteredWeaponTools(player:FindFirstChildOfClass("Backpack"))
	destroyRegisteredWeaponTools(player.Character)
end

local function getCharacterCFrame(player)
	local root = getRoot(player)
	if root then
		return root.CFrame
	end

	local character = player and player.Character
	if not character then
		return nil
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant.CFrame
		end
	end

	return nil
end

local function isAlive(playerObj, player)
	if not playerObj or playerObj:GetMetaData("isdead") == true then
		return false
	end

	local humanoid = getHumanoid(player)
	return humanoid ~= nil and humanoid.Health > 0 and humanoid:GetState() ~= Enum.HumanoidStateType.Dead
end

local function isDeadCharacter(player)
	local humanoid = getHumanoid(player)
	return humanoid ~= nil and (humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead)
end

local function isOnDutyAmbulance(playerObj)
	local job = type(playerObj and playerObj.PlayerData and playerObj.PlayerData.job) == "table"
			and playerObj.PlayerData.job
		or {}
	return (job.name == "ambulance" or job.type == "ems") and job.onduty ~= false
end

local function isAmbulanceEmployee(playerObj)
	local job = type(playerObj and playerObj.PlayerData and playerObj.PlayerData.job) == "table"
			and playerObj.PlayerData.job
		or {}
	return job.name == "ambulance" or job.type == "ems"
end

local function authorizedHospitalVehicles(playerObj, hospital)
	local grade = jobGrade(playerObj)
	local vehicles = {}
	for _, entry in ipairs(type(hospital.authorizedVehicles) == "table" and hospital.authorizedVehicles or {}) do
		local name = type(entry) == "table" and trim(entry.name):lower() or trim(entry):lower()
		local minimumGrade = type(entry) == "table" and math.max(0, math.floor(tonumber(entry.minGrade) or 0)) or 0
		local definition = name ~= "" and QBShared.Vehicles[name] or nil
		if definition and grade >= minimumGrade then
			table.insert(vehicles, {
				name = name,
				label = tostring(type(entry) == "table" and entry.label or definition.label or name),
			})
		end
	end
	return vehicles
end

local function findAuthorizedHospitalVehicle(playerObj, hospital, requestedName)
	requestedName = trim(requestedName):lower()
	for _, vehicle in ipairs(authorizedHospitalVehicles(playerObj, hospital)) do
		if vehicle.name == requestedName then
			return vehicle
		end
	end
	return nil
end

local function countOnDutyDoctors()
	local userIds, count = PlayerService.GetPlayersByJob("ambulance", true)
	return userIds, count
end

local function alertDoctors(player, playerObj, hospital)
	local cooldown = math.max(0, tonumber(getHospitalConfig().DoctorCallCooldown) or 60)
	local now = os.clock()
	if now - (lastDoctorCallAt[player] or -math.huge) < cooldown then
		return false, "EMS has already been notified."
	end
	lastDoctorCallAt[player] = now

	local userIds = countOnDutyDoctors()
	for _, userId in ipairs(userIds) do
		local doctor = PlayerService.GetPlayer(userId)
		if doctor then
			doctor:Notify(
				("Doctor needed at %s for %s."):format(tostring(hospital.label or "Hospital"), playerObj:GetName()),
				"primary",
				6000
			)
		end
	end
	return true, "On-duty EMS has been notified."
end

local function reserveBed(hospital, player)
	local hospitalId = trim(hospital.id)
	bedOccupancy[hospitalId] = bedOccupancy[hospitalId] or {}
	local occupied = bedOccupancy[hospitalId]
	for bedIndex, bed in ipairs(type(hospital.beds) == "table" and hospital.beds or {}) do
		local occupant = occupied[bedIndex]
		if not occupant or occupant.Parent ~= Players then
			local bedCFrame = cframeFrom(bed)
			if bedCFrame then
				occupied[bedIndex] = player
				return bedIndex, bedCFrame
			end
		end
	end
	return nil, nil
end

local function releaseBed(hospitalId, bedIndex, player)
	local occupied = bedOccupancy[hospitalId]
	if occupied and occupied[bedIndex] == player then
		occupied[bedIndex] = nil
	end
end

local function hospitalExitCFrame(hospital)
	local checkIn = type(hospital.checkIn) == "table" and hospital.checkIn[1] or nil
	local base = cframeFrom(checkIn)
	return base and (base + Vector3.new(0, 0, 6)) or nil
end

local function nearestHospital(position)
	local closest
	local closestDistance = math.huge
	for _, hospital in ipairs(getHospitalConfig().Hospitals or {}) do
		local checkIn = type(hospital.checkIn) == "table" and vectorFrom(hospital.checkIn[1]) or nil
		if checkIn then
			local distance = position and (position - checkIn).Magnitude or 0
			if distance < closestDistance then
				closestDistance = distance
				closest = hospital
			end
		end
	end
	return closest
end

local function chargeHospital(playerObj)
	local hospital = getHospitalConfig()
	local cost = math.max(0, math.floor(tonumber(hospital.BillCost) or 0))
	local paymentType = trim(hospital.PaymentType):lower()
	if paymentType == "" then
		paymentType = "bank"
	end
	if cost <= 0 then
		return true, 0, paymentType
	end
	if not playerObj:RemoveMoney(paymentType, cost, "hospital-treatment") then
		return false, cost, paymentType
	end
	if bankingService and type(bankingService.AddSocietyFunds) == "function" then
		task.spawn(function()
			bankingService.AddSocietyFunds("ambulance", cost, "Hospital treatment")
		end)
	end
	return true, cost, paymentType
end

local function finishTreatment(player)
	local session = treatmentSessions[player]
	if not session then
		return
	end
	treatmentSessions[player] = nil
	releaseBed(session.hospitalId, session.bedIndex, player)
	if session.root and session.root.Parent then
		session.root.Anchored = session.wasAnchored == true
	end

	local playerObj = PlayerService.GetPlayer(player.UserId)
	if not playerObj or playerObj ~= session.playerObj then
		return
	end
	local exitCFrame = hospitalExitCFrame(session.hospital) or session.bedCFrame
	if playerObj:GetMetaData("isdead") == true or isDeadCharacter(player) then
		local ok = MedicalService.RevivePlayer(playerObj, player, exitCFrame, getRespawnHealth())
		if not ok then
			playerObj:Notify("Hospital treatment could not revive you.", "error", 4000)
			return
		end
	else
		local humanoid = getHumanoid(player)
		local root = getRoot(player)
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
		end
		if root and exitCFrame then
			root.CFrame = exitCFrame + Vector3.new(0, 3, 0)
		end
		playerObj:SetMetaData("isdead", false)
	end
	playerObj:SetMetaData("hunger", 100)
	playerObj:SetMetaData("thirst", 100)
	playerObj:Save()
	playerObj:Notify("Treatment complete. You are healthy again.", "success", 4500)
end

local function beginHospitalCheckIn(player, playerObj, hospital)
	if treatmentSessions[player] or checkInBusy[player] then
		return false, "You are already checking in."
	end
	local hospitalConfig = getHospitalConfig()
	local maxDistance = math.max(1, tonumber(hospitalConfig.ActionDistance) or 14)
	if not closeToPoints(player, hospital.checkIn, maxDistance) then
		return false, "Move closer to the hospital check-in desk."
	end

	local _, doctorCount = countOnDutyDoctors()
	local minimumDoctors = math.max(0, math.floor(tonumber(hospitalConfig.MinimalDoctors) or 0))
	if minimumDoctors > 0 and doctorCount >= minimumDoctors then
		return alertDoctors(player, playerObj, hospital)
	end

	checkInBusy[player] = true
	local admissionSeconds = math.max(0, tonumber(hospitalConfig.AdmissionSeconds) or 2)
	if admissionSeconds > 0 then
		task.wait(admissionSeconds)
	end
	if PlayerService.GetPlayer(player.UserId) ~= playerObj or not closeToPoints(player, hospital.checkIn, maxDistance) then
		checkInBusy[player] = nil
		return false, "Hospital check-in was canceled."
	end

	local root = getRoot(player)
	if not root then
		checkInBusy[player] = nil
		return false, "Your character is not ready for treatment."
	end

	local bedIndex, bedCFrame = reserveBed(hospital, player)
	if not bedIndex then
		checkInBusy[player] = nil
		return false, "All treatment beds are occupied."
	end
	local paid, cost, paymentType = chargeHospital(playerObj)
	if not paid then
		releaseBed(trim(hospital.id), bedIndex, player)
		checkInBusy[player] = nil
		return false, ("You need $%d available in %s for treatment."):format(cost, paymentType)
	end

	local wasAnchored = root.Anchored
	root.CFrame = bedCFrame + Vector3.new(0, 3, 0)
	root.Anchored = true
	treatmentSessions[player] = {
		playerObj = playerObj,
		hospital = hospital,
		hospitalId = trim(hospital.id),
		bedIndex = bedIndex,
		bedCFrame = bedCFrame,
		root = root,
		wasAnchored = wasAnchored,
	}
	checkInBusy[player] = nil
	local treatmentSeconds = math.max(0, tonumber(hospitalConfig.TreatmentSeconds) or 20)
	playerObj:Notify(("Treatment started. Estimated time: %d seconds."):format(math.ceil(treatmentSeconds)), "primary", 4500)
	task.delay(treatmentSeconds, finishTreatment, player)
	return true, ("Checked into %s for $%d (%s)."):format(tostring(hospital.label or "Hospital"), cost, paymentType)
end

function MedicalService.SetArmor(playerObj, amount)
	if not playerObj then
		return false
	end

	amount = clampPercent(amount)
	playerObj:SetMetaData("armor", amount)

	local player = getRobloxPlayer(playerObj)
	local humanoid = getHumanoid(player)
	if humanoid then
		humanoid:SetAttribute("Armor", amount)
	end

	return true
end

local function healSelf(playerObj, item, definition)
	local player = getRobloxPlayer(playerObj)
	if not player then
		return false, "Character not loaded."
	end
	if not isAlive(playerObj, player) then
		return false, "You cannot use that while dead."
	end

	local humanoid = getHumanoid(player)
	if humanoid.Health >= humanoid.MaxHealth then
		return false, "You are already healthy."
	end

	local medical = type(definition.medical) == "table" and definition.medical or {}
	local healAmount = math.max(1, tonumber(medical.health) or DEFAULT_BANDAGE_HEAL)
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + healAmount)
	return true, nil, ("Healed %d health."):format(healAmount)
end

local function useArmor(playerObj, item, definition)
	local player = getRobloxPlayer(playerObj)
	if not player then
		return false, "Character not loaded."
	end
	if not isAlive(playerObj, player) then
		return false, "You cannot use that while dead."
	end

	local medical = type(definition.medical) == "table" and definition.medical or {}
	local armorAmount = clampPercent(medical.amount or FULL_ARMOR)
	local currentArmor = clampPercent(playerObj:GetMetaData("armor"))
	if currentArmor >= armorAmount then
		return false, "Your armor is already full."
	end

	MedicalService.SetArmor(playerObj, armorAmount)
	return true, nil, "Armor equipped."
end

local function findNearbyDeadTarget(playerObj, definition)
	local player = getRobloxPlayer(playerObj)
	if not player then
		return nil, "Character not loaded."
	end
	if not isAlive(playerObj, player) then
		return nil, "You cannot use that while dead."
	end

	local sourceRoot = getRoot(player)
	if not sourceRoot then
		return nil, "Character not spawned."
	end

	local medical = type(definition.medical) == "table" and definition.medical or {}
	local reviveDistance = math.max(1, tonumber(medical.reviveDistance) or DEFAULT_REVIVE_DISTANCE)
	local closest = nil
	local closestDistance = reviveDistance

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer ~= player and isDeadCharacter(targetPlayer) then
			local targetObj = PlayerService.GetPlayer(targetPlayer.UserId)
			local targetCFrame = targetObj and getCharacterCFrame(targetPlayer)
			if targetCFrame then
				local distance = (targetCFrame.Position - sourceRoot.Position).Magnitude
				if distance <= closestDistance then
					closestDistance = distance
					closest = {
						player = targetPlayer,
						playerObj = targetObj,
						cframe = targetCFrame,
					}
				end
			end
		end
	end

	if not closest then
		return nil, "No dead character nearby."
	end

	return closest
end

function MedicalService.RevivePlayer(targetObj, targetPlayer, reviveCFrame, reviveHealth)
	if not targetObj or not targetPlayer then
		return false, "No target to revive."
	end

	deathTimes[targetPlayer] = nil
	targetObj:SetMetaData("isdead", false)
	targetPlayer:LoadCharacter()

	local character = targetPlayer.Character or targetPlayer.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid", 5)
	local root = character:WaitForChild("HumanoidRootPart", 5)

	if root and reviveCFrame then
		root.CFrame = reviveCFrame + Vector3.new(0, 3, 0)
	end

	if humanoid then
		humanoid.Health = math.clamp(tonumber(reviveHealth) or DEFAULT_REVIVE_HEALTH, 1, humanoid.MaxHealth)
	end

	return true
end

function MedicalService.RequestRespawn(player)
	local playerObj = PlayerService.GetPlayer(player.UserId)
	if not playerObj then
		return false, "Character not loaded."
	end
	if playerObj:GetMetaData("isdead") ~= true and not isDeadCharacter(player) then
		return false, "You are not dead."
	end

	local diedAt = deathTimes[player]
	if not diedAt then
		diedAt = os.clock()
		deathTimes[player] = diedAt
	end

	local remaining = getRespawnDelay() - (os.clock() - diedAt)
	if remaining > 0 then
		return false, ("Respawn available in %d seconds."):format(math.ceil(remaining))
	end

	local hospitalConfig = getHospitalConfig()
	local destinationHospital
	local respawnCFrame
	if hospitalConfig.Enabled ~= false and hospitalConfig.RespawnAtNearestHospital ~= false then
		local oldRoot = getRoot(player)
		destinationHospital = nearestHospital(oldRoot and oldRoot.Position or nil)
		respawnCFrame = destinationHospital and hospitalExitCFrame(destinationHospital) or nil
	end

	local ok, err = PlayerService.RespawnPlayer(player, playerObj, respawnCFrame, getRespawnHealth())
	if not ok then
		return false, err
	end

	local respawn = getRespawnConfig()
	if respawn.WipeInventory == true then
		playerObj:SetInventory({})
		clearActiveInventoryTools(player)
	end

	deathTimes[player] = nil
	playerObj:SetMetaData("isdead", false)
	MedicalService.SetArmor(playerObj, 0)
	local paid, cost, paymentType = true, 0, "bank"
	if destinationHospital then
		paid, cost, paymentType = chargeHospital(playerObj)
	end
	playerObj:Save()
	if destinationHospital and paid and cost > 0 then
		playerObj:Notify(
			("You respawned at %s. Hospital bill: $%d (%s)."):format(
				tostring(destinationHospital.label or "Hospital"),
				cost,
				paymentType
			),
			"success",
			4500
		)
	elseif destinationHospital and not paid then
		playerObj:Notify(
			("You respawned at %s. The $%d hospital bill could not be collected."):format(
				tostring(destinationHospital.label or "Hospital"),
				cost
			),
			"warning",
			4500
		)
	else
		playerObj:Notify("You respawned.", "success", 2500)
	end
	return true
end

local function reviveNearbyPlayer(playerObj, item, definition)
	if not isOnDutyAmbulance(playerObj) then
		return false, "You need to be on-duty EMS to use that."
	end

	local target, err = findNearbyDeadTarget(playerObj, definition)
	if not target then
		return false, err
	end

	local medical = type(definition.medical) == "table" and definition.medical or {}
	local ok, reviveErr = MedicalService.RevivePlayer(
		target.playerObj,
		target.player,
		target.cframe,
		tonumber(medical.reviveHealth) or DEFAULT_REVIVE_HEALTH
	)
	if not ok then
		return false, reviveErr
	end

	target.playerObj:Notify("You were revived by EMS.", "success", 3500)
	return true, nil, ("Revived %s."):format(target.playerObj:GetName())
end

local function handleMedicalItem(playerObj, item, definition)
	local medical = type(definition.medical) == "table" and definition.medical or {}
	if medical.action == "heal" then
		return healSelf(playerObj, item, definition)
	elseif medical.action == "armor" then
		return useArmor(playerObj, item, definition)
	elseif medical.action == "revive" then
		return reviveNearbyPlayer(playerObj, item, definition)
	end

	return false, "Nothing happens."
end

local function onCharacterAdded(player, character)
	if humanoidConnections[player] then
		humanoidConnections[player]:Disconnect()
		humanoidConnections[player] = nil
	end

	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or player.Character ~= character then
			return
		end
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		local playerObj = PlayerService.GetPlayer(player.UserId)
		if playerObj then
			humanoid:SetAttribute("Armor", clampPercent(playerObj:GetMetaData("armor")))
			if humanoid.Health > 0 and humanoid:GetState() ~= Enum.HumanoidStateType.Dead then
				deathTimes[player] = nil
				playerObj:SetMetaData("isdead", false)
			end
		end

		humanoidConnections[player] = humanoid.Died:Connect(function()
			local currentObj = PlayerService.GetPlayer(player.UserId)
			if currentObj then
				deathTimes[player] = os.clock()
				currentObj:SetMetaData("isdead", true)
				MedicalService.SetArmor(currentObj, 0)
			else
				humanoid:SetAttribute("Armor", 0)
			end
		end)
	end)
end

local function watchPlayer(player)
	if characterConnections[player] then
		return
	end

	characterConnections[player] = player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

local function unwatchPlayer(player)
	if characterConnections[player] then
		characterConnections[player]:Disconnect()
		characterConnections[player] = nil
	end
	if humanoidConnections[player] then
		humanoidConnections[player]:Disconnect()
		humanoidConnections[player] = nil
	end
	local session = treatmentSessions[player]
	if session then
		releaseBed(session.hospitalId, session.bedIndex, player)
		if session.root and session.root.Parent then
			session.root.Anchored = session.wasAnchored == true
		end
		treatmentSessions[player] = nil
	end
	local vehicle = jobVehicles[player]
	if vehicle and vehicle.Parent then
		vehicle:Destroy()
	end
	jobVehicles[player] = nil
	checkInBusy[player] = nil
	lastHospitalActionAt[player] = nil
	lastDoctorCallAt[player] = nil
	deathTimes[player] = nil
end

function MedicalService.ApplyWeaponDamage(system, target, amount, damageType, dealer, hitInfo, damageData)
	if not target or not target:IsA("Humanoid") then
		return
	end

	amount = math.max(0, tonumber(amount) or 0)
	local targetPlayer = Players:GetPlayerFromCharacter(target.Parent)
	local targetObj = targetPlayer and PlayerService.GetPlayer(targetPlayer.UserId)

	if targetObj then
		local armor = clampPercent(targetObj:GetMetaData("armor") or target:GetAttribute("Armor"))
		if armor > 0 and amount > 0 then
			local absorbed = math.min(armor, amount)
			MedicalService.SetArmor(targetObj, armor - absorbed)
			amount -= absorbed
		end
	end

	if amount > 0 then
		target:TakeDamage(amount)
	end
end

local function bindWeaponsSystem(folder)
	if weaponsBound or not folder or folder.Name ~= "WeaponsSystem" then
		return
	end

	local module = folder:FindFirstChild("WeaponsSystem")
	if not module or not module:IsA("ModuleScript") then
		if not weaponsFolderConnection then
			weaponsFolderConnection = folder.ChildAdded:Connect(function(child)
				if child.Name == "WeaponsSystem" then
					bindWeaponsSystem(folder)
				end
			end)
		end
		return
	end

	local ok, weaponsSystem = pcall(require, module)
	if not ok or type(weaponsSystem) ~= "table" or type(weaponsSystem.setDamageCallback) ~= "function" then
		return
	end

	weaponsSystem.setDamageCallback(MedicalService.ApplyWeaponDamage)
	weaponsBound = true
	if weaponsFolderConnection then
		weaponsFolderConnection:Disconnect()
		weaponsFolderConnection = nil
	end
end

local function watchWeaponsSystem()
	bindWeaponsSystem(ReplicatedStorage:FindFirstChild("WeaponsSystem"))

	ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == "WeaponsSystem" then
			task.defer(bindWeaponsSystem, child)
		end
	end)
end

local function spawnHospitalVehicle(player, playerObj, hospital, payload)
	local hospitalConfig = getHospitalConfig()
	local maxDistance = math.max(1, tonumber(hospitalConfig.ActionDistance) or 14)
	if not closeToPoints(player, hospital.vehicle, maxDistance) then
		return false, "Move closer to the ambulance retrieval point."
	end
	if not isOnDutyAmbulance(playerObj) then
		return false, "You need to be on-duty EMS to retrieve an ambulance."
	end
	local requested = findAuthorizedHospitalVehicle(playerObj, hospital, payload.vehicle)
	if not requested then
		return false, "That emergency vehicle is not authorized for your grade."
	end
	local spawnCFrame = cframeFrom(hospital.vehicleSpawn)
	if not spawnCFrame then
		return false, "This hospital does not have a valid vehicle spawn."
	end
	if not vehicleService or type(vehicleService.SpawnVehicle) ~= "function" then
		return false, "Vehicle service is unavailable."
	end

	local previous = jobVehicles[player]
	if previous and previous.Parent then
		previous:Destroy()
	end
	jobVehicles[player] = nil

	local vehicle, definitionOrError = vehicleService.SpawnVehicle(player, requested.name, {
		cframe = spawnCFrame,
	})
	if not vehicle then
		return false, definitionOrError or "The ambulance could not be spawned."
	end
	jobVehicles[player] = vehicle
	return true, ("%s is ready outside."):format(tostring(requested.label or "Ambulance"))
end

local HOSPITAL_ACTIONS = {
	check_in = function(player, playerObj, hospital)
		return beginHospitalCheckIn(player, playerObj, hospital)
	end,
	spawn_vehicle = spawnHospitalVehicle,
}

local function safeInteractionName(hospitalId, kind, index)
	local id = trim(hospitalId):gsub("[^%w_%-]", "_")
	return ("%s_%s_%d"):format(id ~= "" and id or "Hospital", kind, index)
end

local function createInteractionPart(folder, hospital, hospitalIndex, kind, point, pointIndex, actionText, callback)
	local position = vectorFrom(point)
	if not position then
		warn(("[QBCore.MedicalService] Invalid %s point %d for hospital %d."):format(kind, pointIndex, hospitalIndex))
		return
	end
	local partName = safeInteractionName(hospital.id, kind, pointIndex)
	local part = folder:FindFirstChild(partName)
	if part and not part:IsA("BasePart") then
		warn(("[QBCore.MedicalService] %s must be a BasePart."):format(part:GetFullName()))
		return
	end
	if not part then
		part = Instance.new("Part")
		part.Name = partName
		part.Parent = folder
	end
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.CastShadow, part.Transparency, part.Size = false, 1, Vector3.new(2, 2, 2)
	part.CFrame = cframeFrom(point) or CFrame.new(position)
	part:SetAttribute("QBHospitalId", trim(hospital.id))
	part:SetAttribute("QBHospitalLabel", tostring(hospital.label or "Hospital"))
	part:SetAttribute("QBHospitalPOI", kind)

	local prompt = part:FindFirstChild("HospitalPrompt")
	if prompt and not prompt:IsA("ProximityPrompt") then
		warn(("[QBCore.MedicalService] %s.HospitalPrompt must be a ProximityPrompt."):format(part:GetFullName()))
		return
	end
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "HospitalPrompt"
		prompt.Parent = part
	end
	prompt.ActionText = actionText
	prompt.ObjectText = tostring(hospital.label or "Hospital")
	prompt.KeyboardKeyCode, prompt.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = math.max(1, tonumber(getHospitalConfig().PromptDistance) or 10)
	prompt.RequiresLineOfSight = false
	prompt.Enabled = getHospitalConfig().Enabled ~= false
	prompt.Triggered:Connect(function(player)
		local playerObj = PlayerService.GetPlayer(player.UserId)
		if not playerObj then
			return
		end
		local maxDistance = math.max(1, tonumber(getHospitalConfig().ActionDistance) or 14)
		if not closeToPoints(player, { point }, maxDistance) then
			playerObj:Notify("Move closer to the hospital point.", "error", 3500)
			return
		end
		callback(player, playerObj)
	end)
end

local function createHospitalInteractions()
	local folder = Workspace:FindFirstChild(HOSPITAL_INTERACTION_FOLDER)
	if folder and not folder:IsA("Folder") then
		warn(("[QBCore.MedicalService] Workspace.%s must be a Folder."):format(HOSPITAL_INTERACTION_FOLDER))
		return
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = HOSPITAL_INTERACTION_FOLDER
		folder.Parent = Workspace
	end

	local hospitalConfig = getHospitalConfig()
	for hospitalIndex, hospital in ipairs(hospitalConfig.Hospitals or {}) do
		local hospitalId = trim(hospital.id)
		if hospitalId == "" then
			warn(("[QBCore.MedicalService] Hospital %d needs a unique id."):format(hospitalIndex))
			continue
		end
		for pointIndex, point in ipairs(type(hospital.checkIn) == "table" and hospital.checkIn or {}) do
			createInteractionPart(folder, hospital, hospitalIndex, "CheckIn", point, pointIndex, "Check In", function(player)
				Remotes.OpenHospital:FireClient(player, {
					view = "checkin",
					access = { hospitalId = hospitalId },
					label = tostring(hospital.label or "Hospital"),
					cost = math.max(0, math.floor(tonumber(hospitalConfig.BillCost) or 0)),
					paymentType = trim(hospitalConfig.PaymentType):lower(),
					admissionSeconds = math.max(0, tonumber(hospitalConfig.AdmissionSeconds) or 2),
					treatmentSeconds = math.max(0, tonumber(hospitalConfig.TreatmentSeconds) or 20),
					minimumDoctors = math.max(0, math.floor(tonumber(hospitalConfig.MinimalDoctors) or 0)),
				})
			end)
		end
		for pointIndex, point in ipairs(type(hospital.duty) == "table" and hospital.duty or {}) do
			createInteractionPart(folder, hospital, hospitalIndex, "Duty", point, pointIndex, "Toggle Duty", function(_, playerObj)
				if not isAmbulanceEmployee(playerObj) then
					playerObj:Notify("Only EMS employees can use this duty point.", "error", 3500)
					return
				end
				local nextDuty = playerObj.PlayerData.job.onduty == false
				playerObj:SetJobDuty(nextDuty)
				playerObj:Save()
				playerObj:Notify(nextDuty and "You are now on duty." or "You are now off duty.", "success", 3500)
			end)
		end
		for pointIndex, point in ipairs(type(hospital.vehicle) == "table" and hospital.vehicle or {}) do
			createInteractionPart(folder, hospital, hospitalIndex, "Vehicle", point, pointIndex, "Retrieve Ambulance", function(player, playerObj)
				if not isOnDutyAmbulance(playerObj) then
					playerObj:Notify("You need to be on-duty EMS to use this point.", "error", 3500)
					return
				end
				Remotes.OpenHospital:FireClient(player, {
					view = "vehicles",
					access = { hospitalId = hospitalId },
					label = tostring(hospital.label or "Hospital"),
					vehicles = authorizedHospitalVehicles(playerObj, hospital),
				})
			end)
		end
	end
end

function MedicalService.Start(InventoryService, VehicleService, BankingService)
	if started then
		return
	end
	assert(type(InventoryService) == "table", "MedicalService.Start requires InventoryService")
	inventoryService = InventoryService
	vehicleService = VehicleService
	bankingService = BankingService
	started = true

	for itemName, definition in pairs(QBShared.Items) do
		if type(definition.medical) == "table" then
			inventoryService.CreateUseableItem(itemName, handleMedicalItem)
		end
	end

	Remotes.HospitalAction.OnServerInvoke = function(player, action, payload)
		local playerObj = PlayerService.GetPlayer(player.UserId)
		if not playerObj then
			return false, "Character not loaded."
		end
		local hospitalConfig = getHospitalConfig()
		if hospitalConfig.Enabled == false then
			return false, "Hospital services are unavailable."
		end
		payload = type(payload) == "table" and payload or {}
		local access = type(payload.access) == "table" and payload.access or {}
		local hospital = hospitalById(access.hospitalId)
		if not hospital then
			return false, "That hospital is unavailable."
		end
		local now = os.clock()
		if now - (lastHospitalActionAt[player] or 0) < HOSPITAL_ACTION_COOLDOWN then
			return false, "Please wait before submitting another hospital request."
		end
		lastHospitalActionAt[player] = now
		action = trim(action):lower()
		local handler = HOSPITAL_ACTIONS[action]
		if not handler then
			return false, "That hospital action is not supported."
		end
		local handlerOk, ok, message = pcall(handler, player, playerObj, hospital, payload)
		if not handlerOk then
			warn(("[QBCore.MedicalService] %s failed for %s: %s"):format(action, player.Name, tostring(ok)))
			return false, "The hospital request could not be completed."
		end
		if ok and message then
			playerObj:Notify(tostring(message), "success", 4000)
		end
		return ok, message
	end

	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(unwatchPlayer)

	if getHospitalConfig().Enabled ~= false then
		createHospitalInteractions()
	end
	watchWeaponsSystem()
end

return MedicalService
