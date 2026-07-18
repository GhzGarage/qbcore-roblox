-- Server-owned job paycheck loop. Pay amounts come from the character's validated
-- job grade, while timing/duty/society behavior comes from Config.Money.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QBShared = require(ReplicatedStorage.QBShared.Main)

local function requireSiblingModule(name)
	local module = script.Parent:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		error(("QBCore setup error: %s must be a ModuleScript next to %s."):format(name, script:GetFullName()), 2)
	end
	return require(module)
end

local PlayerService = requireSiblingModule("PlayerService")

local PaycheckService = {}

local started = false
local loopGeneration = 0
local societyFundsProvider = nil
local warnedMissingSocietyProvider = false

local function moneyConfig()
	return QBShared.Config.Money or {}
end

local function paycheckInterval()
	local interval = tonumber(moneyConfig().PayCheckTimeOut)
	if not interval or interval <= 0 or interval ~= interval then
		return nil
	end
	return interval
end

local function warnMissingSocietyProvider()
	if warnedMissingSocietyProvider then
		return
	end
	warnedMissingSocietyProvider = true
	warn(
		"[QBCore.PaycheckService] Config.Money.PayCheckSociety is enabled, but no society-funds provider "
			.. "is registered. Paychecks will be skipped to avoid creating money without debiting a job account."
	)
end

-- Future society-account systems can register a callback with this signature:
--     provider(jobName, amount, playerObj) -> paid:boolean, errorMessage:string?
-- It must debit/approve the society account before returning true.
function PaycheckService.SetSocietyFundsProvider(provider)
	assert(provider == nil or type(provider) == "function", "society funds provider must be a function or nil")
	societyFundsProvider = provider
	warnedMissingSocietyProvider = false
end

function PaycheckService.ProcessPlayer(playerObj)
	if not playerObj or playerObj.Offline then
		return false, "player_unavailable"
	end

	local data = playerObj.PlayerData
	local job = type(data) == "table" and data.job or nil
	local grade = type(job) == "table" and job.grade or nil
	local money = type(data) == "table" and data.money or nil
	if type(job) ~= "table" or type(grade) ~= "table" or type(money) ~= "table" or money.bank == nil then
		return false, "invalid_player_data"
	end

	local config = moneyConfig()
	if config.PayCheckEnabled == false then
		return false, "disabled"
	end
	if config.PayCheckOnDutyOnly == true and job.onduty ~= true then
		return false, "off_duty"
	end

	local amount = tonumber(grade.payment)
	if not amount or amount <= 0 or amount ~= amount or amount == math.huge then
		return false, "no_payment"
	end
	amount = math.floor(amount)
	if amount <= 0 then
		return false, "no_payment"
	end

	if config.PayCheckSociety == true then
		if not societyFundsProvider then
			warnMissingSocietyProvider()
			return false, "society_provider_unavailable"
		end

		local ok, paid, providerError = pcall(societyFundsProvider, job.name, amount, playerObj)
		if not ok then
			warn(("[QBCore.PaycheckService] Society provider failed for job %s: %s"):format(
				tostring(job.name),
				tostring(paid)
			))
			return false, "society_provider_error"
		end
		if paid ~= true then
			return false, providerError or "insufficient_society_funds"
		end
	end

	if not playerObj:AddMoney("bank", amount, "paycheck") then
		warn(("[QBCore.PaycheckService] Could not deposit $%d for %s."):format(amount, playerObj:GetName()))
		return false, "deposit_failed"
	end

	playerObj:Notify(("Paycheck received: $%d deposited into your bank."):format(amount), "success", 5000)
	return true, amount
end

function PaycheckService.ProcessAll()
	local paidCount = 0
	for _, userId in ipairs(PlayerService.GetPlayers()) do
		local playerObj = PlayerService.GetPlayer(userId)
		local paid = PaycheckService.ProcessPlayer(playerObj)
		if paid then
			paidCount += 1
		end
	end
	return paidCount
end

function PaycheckService.Start()
	if started or moneyConfig().PayCheckEnabled == false then
		return
	end

	local interval = paycheckInterval()
	if not interval then
		warn("[QBCore.PaycheckService] PayCheckTimeOut must be a positive number; paycheck loop not started.")
		return
	end

	started = true
	loopGeneration += 1
	local generation = loopGeneration
	if moneyConfig().PayCheckSociety == true and not societyFundsProvider then
		warnMissingSocietyProvider()
	end

	task.spawn(function()
		while started and loopGeneration == generation do
			task.wait(interval)
			if started and loopGeneration == generation then
				PaycheckService.ProcessAll()
			end
		end
	end)
end

function PaycheckService.Stop()
	started = false
	loopGeneration += 1
end

return PaycheckService
