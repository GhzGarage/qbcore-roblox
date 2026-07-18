--[[
    Server entry point: join gate (Access), account-profile claim + character-select
    remotes (PlayerService), world/time boot, paychecks, and shutdown saving.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function requireLocalModule(name)
	local module = script:FindFirstChild(name) or script.Parent:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		error(
			("QBCore setup error: %s must be a ModuleScript either inside %s or next to it."):format(
				name,
				script:GetFullName()
			),
			2
		)
	end
	return require(module)
end

local Access = requireLocalModule("Access")
local PlayerService = requireLocalModule("PlayerService")
local AppearanceService = requireLocalModule("AppearanceService")
local TimeSyncService = requireLocalModule("TimeSyncService")
local Commands = requireLocalModule("Commands")
local InventoryService = requireLocalModule("InventoryService")
local MedicalService = requireLocalModule("MedicalService")
local WeaponService = requireLocalModule("WeaponService")
local VehicleService = requireLocalModule("VehicleService")
local WeatherService = requireLocalModule("WeatherService")
local StageMusicService = requireLocalModule("StageMusicService")
local AdminService = requireLocalModule("AdminService")
local PaycheckService = requireLocalModule("PaycheckService")
local BankingService = requireLocalModule("BankingService")
local Remotes = require(ReplicatedStorage.QBRemotes)

PlayerService.StartStatusLoop()
BankingService.Start()
PaycheckService.SetSocietyFundsProvider(BankingService.WithdrawSocietyFunds)
PaycheckService.Start()
PlayerService.ApplyWorldEnvironment()
TimeSyncService.Start()
WeatherService.Start()
MedicalService.Start(InventoryService)
WeaponService.Start(InventoryService)
VehicleService.Start()
StageMusicService.Start()
Commands.Register()

-- We control spawn timing ourselves: no character should exist until a citizen is selected.
Players.CharacterAutoLoads = false

local function handlePlayerAdded(player)
	local ok, kickReason = Access.CheckJoin(player.UserId)
	if not ok then
		warn(("[QBCore] Kicking %s: %s"):format(player.Name, tostring(kickReason)))
		player:Kick(kickReason)
		return
	end

	PlayerService.OnPlayerJoin(player)
end

Players.PlayerAdded:Connect(handlePlayerAdded)

for _, player in ipairs(Players:GetPlayers()) do
	task.defer(handlePlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	AppearanceService.OnPlayerLeave(player)
	PlayerService.OnPlayerLeave(player)
end)

game:BindToClose(function()
	PaycheckService.Stop()
	PlayerService.SaveAllAndRelease()
end)

-- ─────────────────────────── character-select remotes ───────────────────────────

Remotes.GetCharacters.OnServerInvoke = function(player)
	return PlayerService.GetCharacterList(player)
end

Remotes.SelectCharacter.OnServerInvoke = function(player, citizenId)
	if type(citizenId) ~= "string" then
		return false, "Invalid request."
	end
	local ok, err = PlayerService.SelectCharacter(player, citizenId)
	if ok then
		BankingService.DeliverPendingTransfers(player, PlayerService.GetPlayer(player.UserId))
	end
	return ok, err
end

Remotes.CreateCharacter.OnServerInvoke = function(player, firstname, lastname)
	local citizenId, err = PlayerService.CreateCharacter(player, firstname, lastname)
	if not citizenId then
		return nil, err
	end
	return citizenId
end

Remotes.DeleteCharacter.OnServerInvoke = function(player, citizenId)
	if type(citizenId) ~= "string" then
		return false, "Invalid request."
	end
	return PlayerService.DeleteCharacter(player, citizenId)
end

-- ─────────────────────────── appearance remotes ───────────────────────────

Remotes.RequestAppearanceEditor.OnServerEvent:Connect(function(player)
	local playerObj = PlayerService.GetPlayer(player.UserId)
	if playerObj then
		AppearanceService.OpenEditor(player, playerObj, false)
	end
end)

Remotes.PreviewAppearance.OnServerEvent:Connect(function(player, payload)
	AppearanceService.Preview(player, payload)
end)

Remotes.CancelAppearanceEdit.OnServerEvent:Connect(function(player)
	AppearanceService.CancelEdit(player, PlayerService.GetPlayer(player.UserId))
end)

Remotes.SaveAppearance.OnServerInvoke = function(player, payload)
	local playerObj = PlayerService.GetPlayer(player.UserId)
	if not playerObj then
		return false, "Character not loaded."
	end
	return AppearanceService.SaveAppearance(player, playerObj, payload)
end

-- Inventory remotes. The server owns all mutations; the client only asks for slot actions.

Remotes.GetInventory.OnServerInvoke = function(player)
	local playerObj = PlayerService.GetPlayer(player.UserId)
	if not playerObj then
		return nil, "Character not loaded."
	end
	return InventoryService.GetSnapshot(playerObj)
end

Remotes.MoveInventoryItem.OnServerInvoke = function(player, fromSlot, toSlot)
	local playerObj = PlayerService.GetPlayer(player.UserId)
	if not playerObj then
		return false, "Character not loaded."
	end
	return InventoryService.MoveItem(playerObj, fromSlot, toSlot)
end

Remotes.GiveInventoryItem.OnServerInvoke = function(player, slot)
	local playerObj = PlayerService.GetPlayer(player.UserId)
	if not playerObj then
		return false, "Character not loaded."
	end
	return InventoryService.GiveSlot(playerObj, slot)
end

Remotes.UseInventorySlot.OnServerInvoke = function(player, slot)
	local playerObj = PlayerService.GetPlayer(player.UserId)
	if not playerObj then
		return false, "Character not loaded."
	end
	return InventoryService.UseSlot(playerObj, slot)
end

Remotes.RequestRespawn.OnServerInvoke = function(player)
	return MedicalService.RequestRespawn(player)
end

-- Admin menu remotes. Permission checks live in AdminService, not the client.

Remotes.GetAdminContext.OnServerInvoke = function(player)
	return AdminService.GetContext(player)
end

Remotes.AdminAction.OnServerInvoke = function(player, action, payload)
	return AdminService.HandleAction(player, action, payload)
end
