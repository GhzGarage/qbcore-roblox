--[[
    Server entry point: join gate (Access), account-profile claim + character-select
    remotes (PlayerService), world/time boot, paychecks, and shutdown saving.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Disable platform auto-spawning before any service startup work can yield.
Players.CharacterAutoLoads = false

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
local ShopService = requireLocalModule("ShopService")
local CityHallService = requireLocalModule("CityHallService")
local MedicalService = requireLocalModule("MedicalService")
local WeaponService = requireLocalModule("WeaponService")
local VehicleService = requireLocalModule("VehicleService")
local VehicleShopService = requireLocalModule("VehicleShopService")
local GarageService = requireLocalModule("GarageService")
local ManagementService = requireLocalModule("ManagementService")
local WeatherService = requireLocalModule("WeatherService")
local StageMusicService = requireLocalModule("StageMusicService")
local AdminService = requireLocalModule("AdminService")
local PaycheckService = requireLocalModule("PaycheckService")
local BankingService = requireLocalModule("BankingService")
local PhoneService = requireLocalModule("PhoneService")
local ApartmentService = requireLocalModule("ApartmentService")
local SpawnService = requireLocalModule("SpawnService")
local Remotes = require(ReplicatedStorage.QBRemotes)
local QBShared = require(ReplicatedStorage.QBShared.Main)

PlayerService.StartStatusLoop()
AppearanceService.Start(PlayerService)
BankingService.Start()
PhoneService.Start(InventoryService, PlayerService)
ManagementService.Start(AppearanceService)
PaycheckService.SetSocietyFundsProvider(BankingService.WithdrawSocietyFunds)
PaycheckService.Start()
PlayerService.ApplyWorldEnvironment()
TimeSyncService.Start()
WeatherService.Start()
MedicalService.Start(InventoryService)
WeaponService.Start(InventoryService)
ShopService.Start(InventoryService)
CityHallService.Start(InventoryService)
ApartmentService.Start(PlayerService, InventoryService, AppearanceService)
SpawnService.Start(PlayerService, ApartmentService, function(player, playerObj)
	BankingService.DeliverPendingTransfers(player, playerObj)
	ManagementService.OnCharacterLoaded(player, playerObj)
	PhoneService.OnCharacterLoaded(player, playerObj)
	PlayerService.OpenInitialAppearance(player, playerObj)
end)
VehicleService.Start()
VehicleShopService.Start(VehicleService)
GarageService.Start(VehicleService)
StageMusicService.Start()
Commands.Register()

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
	SpawnService.OnPlayerLeave(player)
	ApartmentService.OnPlayerLeave(player)
	PhoneService.OnPlayerLeave(player)
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
		local playerObj = PlayerService.GetSelectedPlayer(player.UserId)
		SpawnService.BeginSelection(player, playerObj)
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
	if playerObj and QBShared.Config.Appearance.AllowFullEditorCommand ~= false then
		AppearanceService.OpenEditor(player, playerObj, false)
	elseif playerObj then
		playerObj:Notify("Visit a clothing, accessory, barber, or outfit shop.", "primary", 5000)
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

Remotes.GetInventory.OnServerInvoke = function(player, access)
	local playerObj = PlayerService.GetPlayer(player.UserId)
	if not playerObj then
		return nil, "Character not loaded."
	end
	return InventoryService.GetOpenSnapshot(playerObj, player, access)
end

Remotes.InventoryAction.OnServerInvoke = function(player, action, payload)
	local playerObj = PlayerService.GetPlayer(player.UserId)
	if not playerObj then
		return false, "Character not loaded."
	end
	return InventoryService.HandleExternalAction(playerObj, player, action, payload)
end

Remotes.CloseInventory.OnServerEvent:Connect(function(player, access)
	InventoryService.CloseExternal(PlayerService.GetPlayer(player.UserId), player, access)
end)

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
