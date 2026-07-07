-- Server-authoritative medical item handlers and life-state tracking.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QBShared = require(ReplicatedStorage.QBShared.Main)
local PlayerService = require(script.Parent.PlayerService)

local MedicalService = {}

local DEFAULT_BANDAGE_HEAL = 20
local DEFAULT_REVIVE_DISTANCE = 10
local DEFAULT_REVIVE_HEALTH = 40
local FULL_ARMOR = 100
local REGISTERED_WEAPON_TOOL_ATTRIBUTE = "QBWeaponTool"

local started = false
local weaponsBound = false
local weaponsFolderConnection = nil
local characterConnections = {}
local humanoidConnections = {}
local deathTimes = {}

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

	local ok, err = PlayerService.RespawnPlayer(player, playerObj, nil, getRespawnHealth())
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
	playerObj:Save()
	playerObj:Notify("You respawned.", "success", 2500)
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

function MedicalService.Start(InventoryService)
	if started then
		return
	end
	started = true

	for itemName, definition in pairs(QBShared.Items) do
		if type(definition.medical) == "table" then
			InventoryService.CreateUseableItem(itemName, handleMedicalItem)
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(unwatchPlayer)

	watchWeaponsSystem()
end

return MedicalService
