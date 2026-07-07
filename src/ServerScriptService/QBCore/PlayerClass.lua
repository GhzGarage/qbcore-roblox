--[[
    Roblox port of server/player.lua's `Player` class: job/crew validation, money rules,
    metadata/rep accessors. AddMethod/AddField and the qb-log webhooks are not ported --
    ModuleScripts share tables by reference, so extend a Player instance directly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function requireQBShared()
	local shared = ReplicatedStorage:FindFirstChild("QBShared")
	if not shared then
		error("QBCore setup error: ReplicatedStorage must contain QBShared.", 2)
	end

	if shared:IsA("ModuleScript") then
		return require(shared)
	end

	for _, moduleName in ipairs({ "Main", "init", "init.lua" }) do
		local module = shared:FindFirstChild(moduleName)
		if module and module:IsA("ModuleScript") then
			return require(module)
		end
	end

	error(
		"QBCore setup error: ReplicatedStorage.QBShared must be a ModuleScript, or a Folder containing a Main ModuleScript.",
		2
	)
end

local QBShared = requireQBShared()
local Remotes = require(ReplicatedStorage.QBRemotes)
local InventoryService = require(script.Parent.InventoryService)

local Player = {}
Player.__index = Player

-- source: the Roblox Players-service Player instance, or nil for an offline/admin-tool lookup
-- playerData: table
-- saveCallback: function(playerData) -- persists PlayerData into the owning account profile
-- logoutCallback: function() -- tears down the session (see PlayerService.Logout)
function Player.new(source, playerData, saveCallback, logoutCallback)
	local self = setmetatable({}, Player)
	self.PlayerData = playerData
	self.Offline = source == nil
	self._source = source
	self._saveCallback = saveCallback
	self._logoutCallback = logoutCallback

	return self
end

function Player:GetPlayerData()
	return self.PlayerData
end

function Player:UpdateClient(key, val)
	if self.Offline then
		return
	end
	if key then
		Remotes.PlayerDataUpdated:FireClient(self._source, key, val)
	else
		Remotes.PlayerDataUpdated:FireClient(self._source, "all", self.PlayerData)
	end
end

function Player:SetJob(job, grade)
	job = job:lower()
	grade = grade or "0"
	local jobInfo = QBShared.Jobs[job]
	if not jobInfo then
		return false
	end

	self.PlayerData.job = {
		name = job,
		label = jobInfo.label,
		onduty = jobInfo.defaultDuty,
		type = jobInfo.type or "none",
		grade = { name = "No Grades", level = 0, payment = 30, isboss = false },
	}

	local gradeKey = tostring(grade)
	local gradeInfo = jobInfo.grades[gradeKey]
	if gradeInfo then
		self.PlayerData.job.grade.name = gradeInfo.name
		self.PlayerData.job.grade.level = tonumber(gradeKey)
		self.PlayerData.job.grade.payment = gradeInfo.payment
		self.PlayerData.job.grade.isboss = gradeInfo.isboss or false
		self.PlayerData.job.isboss = gradeInfo.isboss or false
	end

	if not self.Offline then
		self:UpdateClient("job", self.PlayerData.job)
	end
	return true
end

function Player:SetCrew(crew, grade)
	crew = crew:lower()
	grade = grade or "0"
	local crewInfo = QBShared.Crews[crew]
	if not crewInfo then
		return false
	end

	self.PlayerData.crew = {
		name = crew,
		label = crewInfo.label,
		grade = { name = "No Grades", level = 0, isboss = false },
	}

	local gradeKey = tostring(grade)
	local gradeInfo = crewInfo.grades[gradeKey]
	if gradeInfo then
		self.PlayerData.crew.grade.name = gradeInfo.name
		self.PlayerData.crew.grade.level = tonumber(gradeKey)
		self.PlayerData.crew.grade.isboss = gradeInfo.isboss or false
		self.PlayerData.crew.isboss = gradeInfo.isboss or false
	end

	if not self.Offline then
		self:UpdateClient("crew", self.PlayerData.crew)
	end
	return true
end

function Player:Notify(text, notifyType, length)
	if self.Offline then
		return
	end
	Remotes.Notify:FireClient(self._source, text, notifyType, length)
end

function Player:GetName()
	local charinfo = self.PlayerData.charinfo
	return charinfo.firstname .. " " .. charinfo.lastname
end

function Player:SetJobDuty(onDuty)
	self.PlayerData.job.onduty = not not onDuty
	if not self.Offline then
		self:UpdateClient("job", self.PlayerData.job)
	end
end

function Player:SetPlayerData(key, val)
	if not key or type(key) ~= "string" then
		return
	end
	self.PlayerData[key] = val
	self:UpdateClient(key, val)
end

function Player:SetMetaData(meta, val)
	if not meta or type(meta) ~= "string" then
		return
	end
	if meta == "hunger" or meta == "thirst" or meta == "stress" or meta == "armor" then
		val = math.min(100, math.max(0, tonumber(val) or 0))
	elseif meta == "isdead" then
		val = val == true
	end
	self.PlayerData.metadata[meta] = val
	self:UpdateClient("metadata", self.PlayerData.metadata)
end

function Player:GetMetaData(meta)
	if not meta or type(meta) ~= "string" then
		return
	end
	return self.PlayerData.metadata[meta]
end

function Player:AddRep(rep, amount)
	if not rep or not amount then
		return
	end
	local current = self.PlayerData.metadata.rep[rep] or 0
	self.PlayerData.metadata.rep[rep] = current + amount
	self:UpdateClient("metadata", self.PlayerData.metadata)
end

function Player:RemoveRep(rep, amount)
	if not rep or not amount then
		return
	end
	local current = self.PlayerData.metadata.rep[rep] or 0
	self.PlayerData.metadata.rep[rep] = math.max(0, current - amount)
	self:UpdateClient("metadata", self.PlayerData.metadata)
end

function Player:GetRep(rep)
	if not rep then
		return
	end
	return self.PlayerData.metadata.rep[rep] or 0
end

function Player:AddMoney(moneytype, amount, reason)
	moneytype = moneytype:lower()
	amount = tonumber(amount)
	if not amount or amount < 0 then
		return false
	end
	if self.PlayerData.money[moneytype] == nil then
		return false
	end

	self.PlayerData.money[moneytype] = self.PlayerData.money[moneytype] + amount
	if not self.Offline then
		self:UpdateClient("money", self.PlayerData.money)
		Remotes.PlayerDataUpdated:FireClient(self._source, "moneyChange", {
			type = moneytype,
			amount = amount,
			action = "add",
			reason = reason or "unknown",
		})
	end
	return true
end

function Player:RemoveMoney(moneytype, amount, reason)
	moneytype = moneytype:lower()
	amount = tonumber(amount)
	if not amount or amount < 0 then
		return false
	end
	if self.PlayerData.money[moneytype] == nil then
		return false
	end

	local config = QBShared.Config.Money
	if config.DontAllowMinus[moneytype] and (self.PlayerData.money[moneytype] - amount) < 0 then
		return false
	end
	if self.PlayerData.money[moneytype] - amount < config.MinusLimit then
		return false
	end

	self.PlayerData.money[moneytype] = self.PlayerData.money[moneytype] - amount
	if not self.Offline then
		self:UpdateClient("money", self.PlayerData.money)
		Remotes.PlayerDataUpdated:FireClient(self._source, "moneyChange", {
			type = moneytype,
			amount = amount,
			action = "remove",
			reason = reason or "unknown",
		})
	end
	return true
end

function Player:SetMoney(moneytype, amount, reason)
	moneytype = moneytype:lower()
	amount = tonumber(amount)
	if not amount or amount < 0 then
		return false
	end
	if self.PlayerData.money[moneytype] == nil then
		return false
	end

	self.PlayerData.money[moneytype] = amount
	if not self.Offline then
		self:UpdateClient("money", self.PlayerData.money)
		Remotes.PlayerDataUpdated:FireClient(self._source, "moneyChange", {
			type = moneytype,
			amount = amount,
			action = "set",
			reason = reason or "unknown",
		})
	end
	return true
end

function Player:GetMoney(moneytype)
	if not moneytype then
		return false
	end
	return self.PlayerData.money[moneytype:lower()]
end

function Player:AddItem(item, amount, slot, info, reason)
	return InventoryService.AddItem(self, item, amount, slot, info, reason)
end

function Player:RemoveItem(item, amount, slot, reason)
	return InventoryService.RemoveItem(self, item, amount, slot, reason)
end

function Player:HasItem(items, amount)
	return InventoryService.HasItem(self, items, amount)
end

function Player:GetItemBySlot(slot)
	return InventoryService.GetItemBySlot(self, slot)
end

function Player:GetItemByName(item)
	return InventoryService.GetItemByName(self, item)
end

function Player:GetItemsByName(item)
	return InventoryService.GetItemsByName(self, item)
end

function Player:GetItemCount(items)
	return InventoryService.GetItemCount(self, items)
end

function Player:SetInventory(items)
	return InventoryService.SetInventory(self, items)
end

function Player:UseItemSlot(slot)
	return InventoryService.UseSlot(self, slot)
end

function Player:GiveItemSlot(slot)
	return InventoryService.GiveSlot(self, slot)
end

local function capturePosition(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return nil
	end

	local _, yaw = root.CFrame:ToOrientation()
	return {
		x = root.Position.X,
		y = root.Position.Y,
		z = root.Position.Z,
		ry = math.deg(yaw),
	}
end

-- Records the character's current position into PlayerData. PlayerService calls this
-- continuously (status loop) and from CharacterRemoving, because by the time
-- PlayerRemoving/BindToClose handlers run the Character reference is often already nil
-- and a capture attempted only at save time silently keeps the stale/default position.
function Player:CapturePosition(character)
	if self.Offline then
		return nil
	end

	character = character or (self._source and self._source.Character)
	local capturedPosition = capturePosition(character)
	if capturedPosition then
		self.PlayerData.position = capturedPosition
	end
	return capturedPosition
end

function Player:Save()
	if not self.Offline then
		self:CapturePosition()
	end

	if self._saveCallback then
		self._saveCallback(self.PlayerData)
	end
end

function Player:Logout()
	if self.Offline then
		return
	end
	if self._logoutCallback then
		self._logoutCallback()
	end
end

return Player
