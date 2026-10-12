local QBCore = exports['qb-core']:GetCoreObject()
local ActiveContracts = {}
local ServiceRequests = {}
local Bail = {}
local LastCompletion = {}
local LastRequest = {}

local function getPlayerLevel(Player)
    local progress = Player.Functions.GetMetaData(Config.Progression.metadataKey)
    local experience = type(progress) == 'table' and tonumber(progress.experience) or 0
    local level = 1

    for _, tier in ipairs(Config.Progression.levels) do
        if experience >= tier.experience then
            level = tier.level
        end
    end

    return experience, level
end

local function isTowEmployee(Player)
    return Player and Player.PlayerData.job.name == 'tow'
end

local function isNear(source, coords, distance)
    local ped = GetPlayerPed(source)
    if ped == 0 then return false end
    local position = GetEntityCoords(ped)
    return #(position - vector3(coords.x, coords.y, coords.z)) <= distance
end

local function normalizeNetworkId(value)
    local networkId = tonumber(value)
    if not networkId or networkId ~= networkId or networkId == math.huge or networkId == -math.huge
        or networkId <= 0 or networkId % 1 ~= 0 then
        return nil
    end
    return networkId
end

local function getContractLocation()
    local spots = Config.Locations.towspots
    local spot = spots[math.random(1, #spots)]
    return {
        x = spot.coords.x,
        y = spot.coords.y,
        z = spot.coords.z,
        model = spot.model,
    }
end

local function createContractId(source)
    return ('%s-%s-%s'):format(source, os.time(), math.random(100000, 999999))
end

local function getTowProfile(Player)
    local experience, level = getPlayerLevel(Player)
    local progress = Player.Functions.GetMetaData(Config.Progression.metadataKey)
    return {
        experience = experience,
        level = level,
        completed = type(progress) == 'table' and tonumber(progress.completed) or 0,
    }
end

QBCore.Functions.CreateCallback('qb-tow:server:GetProfile', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not isTowEmployee(Player) then
        cb(false)
        return
    end
    cb(getTowProfile(Player))
end)

QBCore.Functions.CreateCallback('qb-tow:server:AcceptContract', function(source, cb, contractKey)
    local Player = QBCore.Functions.GetPlayer(source)
    if not isTowEmployee(Player) then
        cb({ error = 'not_tow' })
        return
    end
    if not isNear(source, Config.Locations.main.coords, 8.0) then
        cb({ error = 'wrong_location' })
        return
    end
    if ActiveContracts[source] then
        cb({ error = 'active_contract' })
        return
    end

    local contract = Config.Contracts[contractKey]
    if not contract then
        cb({ error = 'invalid_contract' })
        return
    end

    local _, level = getPlayerLevel(Player)
    if level < contract.minLevel then
        cb({ error = 'locked' })
        return
    end

    local location = getContractLocation()
    if contractKey == 'motorcycle_recovery' then
        location.model = 'bati'
    end

    local assignment = {
        id = createContractId(source),
        contractKey = contractKey,
        label = contract.label,
        description = contract.description,
        objective = contract.objective,
        reward = math.random(contract.reward.min, contract.reward.max),
        experience = contract.experience,
        location = location,
        issuedAt = os.time(),
    }
    ActiveContracts[source] = assignment
    cb({ assignment = assignment })
end)

QBCore.Functions.CreateCallback('qb-tow:server:RegisterContractVehicle', function(source, cb, contractId, netId)
    local assignment = ActiveContracts[source]
    netId = normalizeNetworkId(netId)
    if not assignment or assignment.id ~= contractId or assignment.playerRequest or not netId then
        cb(false)
        return
    end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2
        or GetEntityModel(vehicle) ~= joaat(assignment.location.model) then
        cb(false)
        return
    end
    local vehicleCoords = GetEntityCoords(vehicle)
    if #(vehicleCoords - vector3(assignment.location.x, assignment.location.y, assignment.location.z)) > 30.0 then
        cb(false)
        return
    end

    assignment.targetNetId = netId
    cb(true)
end)

QBCore.Functions.CreateCallback('qb-tow:server:GetServiceRequests', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not isTowEmployee(Player) then
        cb({})
        return
    end

    local requests = {}
    local now = os.time()
    for requestId, request in pairs(ServiceRequests) do
        if request.expiresAt > now and not request.assignedTo then
            requests[#requests + 1] = {
                id = requestId,
                requesterName = request.requesterName,
                vehicleName = request.vehicleName,
                coords = request.coords,
            }
        end
    end
    cb(requests)
end)

QBCore.Functions.CreateCallback('qb-tow:server:AcceptServiceRequest', function(source, cb, requestId)
    local Player = QBCore.Functions.GetPlayer(source)
    local request = ServiceRequests[requestId]
    if not isTowEmployee(Player) then
        cb({ error = 'not_tow' })
        return
    end
    if ActiveContracts[source] then
        cb({ error = 'active_contract' })
        return
    end
    if not request or request.expiresAt <= os.time() or request.assignedTo then
        cb({ error = 'request_unavailable' })
        return
    end
    local vehicle = NetworkGetEntityFromNetworkId(request.vehicleNetId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
        ServiceRequests[requestId] = nil
        cb({ error = 'request_unavailable' })
        return
    end

    request.assignedTo = source
    local contract = Config.Contracts.vehicle_recovery
    local assignment = {
        id = requestId,
        contractKey = 'player_tow_request',
        label = 'Player Tow Request',
        description = ('Assist %s with their %s.'):format(request.requesterName, request.vehicleName),
        objective = 'tow',
        reward = math.random(contract.reward.min, contract.reward.max),
        experience = contract.experience,
        location = request.coords,
        targetNetId = request.vehicleNetId,
        targetModel = request.vehicleModel,
        playerRequest = true,
        issuedAt = os.time(),
    }
    ActiveContracts[source] = assignment
    cb({ assignment = assignment })
end)

RegisterNetEvent('qb-tow:server:CreateServiceRequest', function(vehicleNetId)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    if not Config.PlayerRequests.enabled or not Player then return end
    if not Config.PlayerRequests.allowTowJobRequests and Player.PlayerData.job.name == 'tow' then
        TriggerClientEvent('QBCore:Notify', source, Lang:t('error.tow_cannot_request'), 'error')
        return
    end
    for _, request in pairs(ServiceRequests) do
        if request.requester == source and request.expiresAt > os.time() then
            TriggerClientEvent('QBCore:Notify', source, Lang:t('error.request_pending'), 'error')
            return
        end
    end
    if LastRequest[source] and os.time() - LastRequest[source] < Config.ContractSettings.requestCooldown then
        TriggerClientEvent('QBCore:Notify', source, Lang:t('error.request_cooldown'), 'error')
        return
    end

    vehicleNetId = normalizeNetworkId(vehicleNetId)
    if not vehicleNetId then
        TriggerClientEvent('QBCore:Notify', source, Lang:t('error.vehicle_required'), 'error')
        return
    end
    local vehicle = vehicleNetId and NetworkGetEntityFromNetworkId(vehicleNetId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
        TriggerClientEvent('QBCore:Notify', source, Lang:t('error.vehicle_required'), 'error')
        return
    end

    local coords = GetEntityCoords(vehicle)
    if not isNear(source, coords, Config.ContractSettings.serviceRadius) then
        TriggerClientEvent('QBCore:Notify', source, Lang:t('error.move_closer'), 'error')
        return
    end

    local requestId = createContractId(source)
    local firstName = Player.PlayerData.charinfo.firstname or 'Unknown'
    local lastName = Player.PlayerData.charinfo.lastname or ''
    local requesterName = (firstName .. ' ' .. lastName):gsub('[^%w%s%-%.]', ''):sub(1, 48)
    local vehicleName = 'roadside vehicle'
    local request = {
        requester = source,
        requesterName = requesterName,
        vehicleNetId = vehicleNetId,
        vehicleModel = GetEntityModel(vehicle),
        vehicleName = 'roadside vehicle',
        coords = { x = coords.x, y = coords.y, z = coords.z },
        expiresAt = os.time() + Config.ContractSettings.requestExpiry,
    }
    ServiceRequests[requestId] = request
    LastRequest[source] = os.time()

    for _, id in ipairs(QBCore.Functions.GetPlayers()) do
        local TowPlayer = QBCore.Functions.GetPlayer(id)
        if isTowEmployee(TowPlayer) then
            TriggerClientEvent('qb-tow:client:ServiceRequestCreated', id, {
                id = requestId,
                requesterName = request.requesterName,
                vehicleName = vehicleName,
            })
        end
    end
    TriggerClientEvent('QBCore:Notify', source, 'Your tow request has been sent to available operators.', 'success')
end)

QBCore.Functions.CreateCallback('qb-tow:server:CompleteContract', function(source, cb, contractId, targetNetId, towNetId)
    local Player = QBCore.Functions.GetPlayer(source)
    local assignment = ActiveContracts[source]
    if not isTowEmployee(Player) or not assignment or assignment.id ~= contractId then
        cb({ error = 'invalid_contract' })
        return
    end
    if LastCompletion[source] and os.time() - LastCompletion[source] < Config.ContractSettings.completionCooldown then
        cb({ error = 'cooldown' })
        return
    end

    if assignment.objective == 'tow' then
        local dropoff = Config.Locations.dropoff.coords
        local dropoffCoords = { x = dropoff.x, y = dropoff.y, z = dropoff.z }
        if not isNear(source, dropoffCoords, Config.ContractSettings.dropoffRadius) then
            cb({ error = 'wrong_location' })
            return
        end

        towNetId = normalizeNetworkId(towNetId)
        local towVehicle = towNetId and NetworkGetEntityFromNetworkId(towNetId)
        local validTowVehicle = false
        if towVehicle and towVehicle ~= 0 and DoesEntityExist(towVehicle) and GetEntityType(towVehicle) == 2 then
            for model in pairs(Config.Vehicles) do
                if GetEntityModel(towVehicle) == joaat(model) then
                    validTowVehicle = true
                    break
                end
            end
        end
        if not validTowVehicle then
            cb({ error = 'not_tow_vehicle' })
            return
        end
        local towCoords = GetEntityCoords(towVehicle)
        if #(towCoords - vector3(dropoff.x, dropoff.y, dropoff.z)) > Config.ContractSettings.dropoffRadius then
            cb({ error = 'wrong_location' })
            return
        end

        targetNetId = normalizeNetworkId(targetNetId)
        local targetVehicle = targetNetId and NetworkGetEntityFromNetworkId(targetNetId)
        if not targetVehicle or targetVehicle == 0 or not DoesEntityExist(targetVehicle) or GetEntityType(targetVehicle) ~= 2 then
            cb({ error = 'invalid_vehicle' })
            return
        end
        if assignment.targetNetId and assignment.targetNetId ~= targetNetId then
            cb({ error = 'invalid_vehicle' })
            return
        end
        if not assignment.targetNetId then
            cb({ error = 'invalid_vehicle' })
            return
        end
        if assignment.targetModel and GetEntityModel(targetVehicle) ~= assignment.targetModel then
            cb({ error = 'invalid_vehicle' })
            return
        end
        if not assignment.playerRequest and GetEntityModel(targetVehicle) ~= joaat(assignment.location.model) then
            cb({ error = 'invalid_vehicle' })
            return
        end
        local targetCoords = GetEntityCoords(targetVehicle)
        if #(targetCoords - vector3(dropoff.x, dropoff.y, dropoff.z)) > Config.ContractSettings.dropoffRadius then
            cb({ error = 'wrong_location' })
            return
        end
    else
        if os.time() - assignment.issuedAt < math.ceil(Config.ContractSettings.actionDuration / 1000) then
            cb({ error = 'cooldown' })
            return
        end
        if not isNear(source, assignment.location, Config.ContractSettings.serviceRadius + 2.0) then
            cb({ error = 'wrong_location' })
            return
        end
        targetNetId = normalizeNetworkId(targetNetId)
        local targetVehicle = targetNetId and NetworkGetEntityFromNetworkId(targetNetId)
        if not targetVehicle or targetVehicle == 0 or not DoesEntityExist(targetVehicle) or GetEntityType(targetVehicle) ~= 2 then
            cb({ error = 'invalid_vehicle' })
            return
        end
        if GetEntityModel(targetVehicle) ~= joaat(assignment.location.model) then
            cb({ error = 'invalid_vehicle' })
            return
        end
        if assignment.targetNetId ~= targetNetId then
            cb({ error = 'invalid_vehicle' })
            return
        end
    end

    local progress = Player.Functions.GetMetaData(Config.Progression.metadataKey)
    if type(progress) ~= 'table' then
        progress = { experience = 0, completed = 0 }
    end
    progress.experience = (tonumber(progress.experience) or 0) + assignment.experience
    progress.completed = (tonumber(progress.completed) or 0) + 1
    Player.Functions.SetMetaData(Config.Progression.metadataKey, progress)

    local tax = math.floor(assignment.reward * Config.ContractSettings.paymentTax / 100)
    local payment = assignment.reward - tax
    Player.Functions.AddMoney('bank', payment, 'tow-contract-payment')
    LastCompletion[source] = os.time()

    if assignment.playerRequest then
        local request = ServiceRequests[assignment.id]
        if request then
            TriggerClientEvent('qb-tow:client:ServiceRequestCompleted', request.requester)
            ServiceRequests[assignment.id] = nil
        end
    end
    ActiveContracts[source] = nil
    cb({
        payment = payment,
        experience = assignment.experience,
        profile = getTowProfile(Player),
    })
end)

RegisterNetEvent('qb-tow:server:CancelContract', function(contractId)
    local source = source
    local assignment = ActiveContracts[source]
    if assignment and assignment.id == contractId then
        if assignment.playerRequest then
            local request = ServiceRequests[assignment.id]
            if request then request.assignedTo = nil end
        end
        ActiveContracts[source] = nil
    end
end)

RegisterNetEvent('qb-tow:server:DoBail', function(rent, vehicleModel)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    if not isTowEmployee(Player) then return end

    local citizenId = Player.PlayerData.citizenid
    if rent then
        if type(vehicleModel) ~= 'string' or not Config.Vehicles[vehicleModel] then return end
        local coords = Config.Locations.vehicle.coords
        if not isNear(source, coords, 8.0) or Bail[citizenId] then return end

        local price = Config.BailPrice
        local account = Player.PlayerData.money.cash >= price and 'cash'
            or (Player.PlayerData.money.bank >= price and 'bank' or nil)
        if not account then
            TriggerClientEvent('QBCore:Notify', source, Lang:t('error.no_deposit', { value = price }), 'error')
            return
        end
        Player.Functions.RemoveMoney(account, price, 'tow-paid-bail')
        Bail[citizenId] = { amount = price, account = account }
        TriggerClientEvent('qb-tow:client:SpawnVehicle', source, vehicleModel)
        TriggerClientEvent('QBCore:Notify', source, Lang:t(account == 'cash' and 'success.paid_with_cash' or 'success.paid_with_bank', { value = price }), 'success')
    else
        local deposit = Bail[citizenId]
        if not deposit or not isNear(source, Config.Locations.vehicle.coords, 8.0) then return end
        Player.Functions.AddMoney(deposit.account, deposit.amount, 'tow-bail-refund')
        Bail[citizenId] = nil
        TriggerClientEvent('QBCore:Notify', source, Lang:t('success.refund_to_cash', { value = deposit.amount }), 'success')
    end
end)

AddEventHandler('playerDropped', function()
    local source = source
    local assignment = ActiveContracts[source]
    if assignment and assignment.playerRequest then
        local request = ServiceRequests[assignment.id]
        if request then request.assignedTo = nil end
    end
    ActiveContracts[source] = nil
    for requestId, request in pairs(ServiceRequests) do
        if request.requester == source then
            ServiceRequests[requestId] = nil
        end
    end
    LastCompletion[source] = nil
    LastRequest[source] = nil
end)

QBCore.Commands.Add('tow', Lang:t('info.tow'), {}, false, function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if isTowEmployee(Player) then
        TriggerClientEvent('qb-tow:client:TowVehicle', source)
    end
end)

QBCore.Commands.Add('towcontracts', 'Open the tow contract board', {}, false, function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if isTowEmployee(Player) then
        TriggerClientEvent('qb-tow:client:OpenContractBoard', source)
    end
end)

QBCore.Commands.Add('towrequests', 'View open player tow requests', {}, false, function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if isTowEmployee(Player) then
        TriggerClientEvent('qb-tow:client:OpenServiceRequests', source)
    end
end)

QBCore.Commands.Add('towrequest', 'Request a tow for your nearby vehicle', {}, false, function(source)
    TriggerClientEvent('qb-tow:client:RequestService', source)
end)

QBCore.Commands.Add('towcancel', 'Cancel your active tow contract', {}, false, function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if isTowEmployee(Player) then
        TriggerClientEvent('qb-tow:client:CancelContract', source)
    end
end)

QBCore.Commands.Add('towboss', 'Open the towing company boss menu', {}, false, function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if isTowEmployee(Player) then
        TriggerClientEvent('qb-tow:client:OpenBossMenu', source)
    end
end)

QBCore.Commands.Add('npc', Lang:t('info.toggle_npc'), {}, false, function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if isTowEmployee(Player) then
        TriggerClientEvent('qb-tow:client:OpenContractBoard', source)
    end
end)
