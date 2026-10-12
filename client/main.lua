local QBCore = exports['qb-core']:GetCoreObject()
local PlayerJob = {}
local CurrentMission
local CurrentBlip
local DropoffBlip
local MissionVehicle
local TowedVehicle
local SpawnedJobVehicle
local SpawningJobVehicle = false
local SpawnAttemptId = 0
local NextSpawnAttempt = 0
local TowBlipCreated = false

local function notify(message, messageType)
    QBCore.Functions.Notify(message, messageType or 'primary')
end

local function isTowEmployee()
    return PlayerJob.name == 'tow'
end

local function isNear(coords, distance)
    local position = GetEntityCoords(PlayerPedId())
    return #(position - vector3(coords.x, coords.y, coords.z)) <= distance
end

local function clearBlip(blip)
    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
    end
end

local function clearMissionBlips()
    clearBlip(CurrentBlip)
    clearBlip(DropoffBlip)
    CurrentBlip = nil
    DropoffBlip = nil
end

local function setRoute(coords, label, dropoff)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, dropoff and 68 or 477)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.75)
    SetBlipColour(blip, 3)
    SetBlipAsShortRange(blip, false)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, 3)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
    return blip
end

local function drawText3D(coords, text)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

local function showHelp(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

local function getVehicleInDirection(from, to)
    local ray = CastRayPointToPoint(from.x, from.y, from.z, to.x, to.y, to.z, 10, PlayerPedId(), 0)
    local _, _, _, _, vehicle = GetRaycastResult(ray)
    return vehicle
end

local function getTowVehicleModel(vehicle)
    if vehicle == 0 then return nil end
    local model = GetEntityModel(vehicle)
    for name in pairs(Config.Vehicles) do
        if model == joaat(name) then
            return name
        end
    end
end

local function getMissionVehicle()
    if not CurrentMission then return 0 end
    if MissionVehicle and DoesEntityExist(MissionVehicle) then
        return MissionVehicle
    end
    if CurrentMission.targetNetId then
        local vehicle = NetToVeh(CurrentMission.targetNetId)
        if vehicle ~= 0 and DoesEntityExist(vehicle) then
            MissionVehicle = vehicle
            return vehicle
        end
    end
    return 0
end

local function finishMission(targetVehicle, towVehicle)
    if not CurrentMission then return end
    local targetNetId = NetworkGetNetworkIdFromEntity(targetVehicle)
    local towNetId = towVehicle and NetworkGetNetworkIdFromEntity(towVehicle) or nil
    QBCore.Functions.TriggerCallback('qb-tow:server:CompleteContract', function(result)
        if not result or result.error then
            local key = result and result.error or 'invalid_contract'
            local errors = {
                wrong_location = Lang:t('error.wrong_location'),
                not_tow_vehicle = Lang:t('error.not_towing_vehicle'),
                invalid_vehicle = Lang:t('error.vehicle_not_correct'),
                cooldown = Lang:t('error.cooldown'),
                invalid_contract = Lang:t('error.invalid_contract'),
            }
            notify(errors[key] or Lang:t('error.failed'), 'error')
            return
        end

        local payment = result.payment
        local experience = result.experience
        clearMissionBlips()
        if DoesEntityExist(targetVehicle) then
            DeleteVehicle(targetVehicle)
        end
        CurrentMission = nil
        MissionVehicle = nil
        TowedVehicle = nil
        SpawnedJobVehicle = nil
        SpawningJobVehicle = false
        SpawnAttemptId = SpawnAttemptId + 1
        NextSpawnAttempt = 0
        notify(Lang:t('success.contract_complete', { value = payment, xp = experience }), 'success')
        if result.profile then
            notify(Lang:t('success.progress', { level = result.profile.level, xp = result.profile.experience }), 'primary')
        end
    end, CurrentMission.id, targetNetId, towNetId)
end

local function spawnMissionVehicle(mission)
    if mission.playerRequest or SpawnedJobVehicle or SpawningJobVehicle
        or not mission.location.model or GetGameTimer() < NextSpawnAttempt then return end
    SpawningJobVehicle = true
    SpawnAttemptId = SpawnAttemptId + 1
    local attemptId = SpawnAttemptId
    local coords = vector4(mission.location.x, mission.location.y, mission.location.z, mission.location.w or 0.0)
    QBCore.Functions.TriggerCallback('QBCore:Server:SpawnVehicle', function(netId)
        if attemptId ~= SpawnAttemptId then
            if netId then
                local staleVehicle = NetToVeh(netId)
                if staleVehicle ~= 0 and DoesEntityExist(staleVehicle) then DeleteVehicle(staleVehicle) end
            end
            return
        end
        if not netId then
            SpawningJobVehicle = false
            NextSpawnAttempt = GetGameTimer() + 5000
            notify(Lang:t('error.spawn_failed'), 'error')
            return
        end
        local vehicle = NetToVeh(netId)
        if vehicle == 0 or not DoesEntityExist(vehicle) then
            SpawningJobVehicle = false
            NextSpawnAttempt = GetGameTimer() + 5000
            notify(Lang:t('error.spawn_failed'), 'error')
            return
        end
        if not CurrentMission or CurrentMission.id ~= mission.id then
            SpawningJobVehicle = false
            NextSpawnAttempt = GetGameTimer() + 5000
            DeleteVehicle(vehicle)
            return
        end

        QBCore.Functions.TriggerCallback('qb-tow:server:RegisterContractVehicle', function(registered)
            if attemptId ~= SpawnAttemptId then
                if DoesEntityExist(vehicle) then DeleteVehicle(vehicle) end
                return
            end
            SpawningJobVehicle = false
            if not registered or not CurrentMission or CurrentMission.id ~= mission.id then
                if DoesEntityExist(vehicle) then DeleteVehicle(vehicle) end
                if not registered then notify(Lang:t('error.vehicle_not_correct'), 'error') end
                NextSpawnAttempt = GetGameTimer() + 5000
                return
            end

            NextSpawnAttempt = 0
            SpawnedJobVehicle = vehicle
            MissionVehicle = vehicle
            SetEntityAsMissionEntity(vehicle, true, true)
            SetVehicleDoorsLocked(vehicle, mission.objective == 'unlock' and 2 or 1)
            SetVehicleEngineOn(vehicle, false, true, true)
            if mission.objective == 'repair' or mission.contractKey == 'accident_cleanup' or mission.contractKey == 'heavy_recovery' then
                SetVehicleEngineHealth(vehicle, 250.0)
                SetVehicleBodyHealth(vehicle, 350.0)
            elseif mission.objective == 'tire' then
                SetVehicleTyreBurst(vehicle, math.random(0, 5), true, 1000.0)
            elseif mission.objective == 'jump' then
                SetVehicleEngineHealth(vehicle, 500.0)
            elseif mission.objective == 'fuel' then
                SetVehicleFuelLevel(vehicle, 0.0)
                if GetResourceState('LegacyFuel') == 'started' then
                    exports['LegacyFuel']:SetFuel(vehicle, 0.0)
                end
            end
        end, mission.id, netId)
    end, mission.location.model, coords, false)
end

local function startMission(assignment)
    CurrentMission = assignment
    MissionVehicle = nil
    TowedVehicle = nil
    SpawnedJobVehicle = nil
    SpawningJobVehicle = false
    SpawnAttemptId = SpawnAttemptId + 1
    NextSpawnAttempt = 0
    clearMissionBlips()
    CurrentBlip = setRoute(assignment.location, assignment.label, false)
    notify(Lang:t('mission.contract_accepted', { value = assignment.label }), 'success')
    notify(assignment.description, 'primary')
end

local function acceptContract(contractKey)
    if not isTowEmployee() then return end
    if not isNear(Config.Locations.main.coords, 12.0) then
        notify(Lang:t('error.must_be_at_hq'), 'error')
        return
    end
    QBCore.Functions.TriggerCallback('qb-tow:server:AcceptContract', function(result)
        if not result or result.error then
            local key = result and result.error or 'failed'
            local errors = {
                not_tow = Lang:t('error.not_tow'),
                active_contract = Lang:t('error.finish_work'),
                invalid_contract = Lang:t('error.invalid_contract'),
                locked = Lang:t('error.contract_locked'),
                wrong_location = Lang:t('error.must_be_at_hq'),
            }
            notify(errors[key] or Lang:t('error.failed'), 'error')
            return
        end
        startMission(result.assignment)
    end, contractKey)
end

local function openContractBoard()
    if not isTowEmployee() then return end
    if not isNear(Config.Locations.main.coords, 12.0) then
        notify(Lang:t('error.must_be_at_hq'), 'error')
        return
    end

    QBCore.Functions.TriggerCallback('qb-tow:server:GetProfile', function(profile)
        if not profile then
            notify(Lang:t('error.not_tow'), 'error')
            return
        end
        local menu = {
            {
                header = Lang:t('menu.contract_board'),
                txt = Lang:t('menu.progress', { level = profile.level, xp = profile.experience, completed = profile.completed }),
                isMenuHeader = true,
            },
        }
        for contractKey, contract in pairs(Config.Contracts) do
            local locked = profile.level < contract.minLevel
            menu[#menu + 1] = {
                header = contract.label,
                txt = locked and Lang:t('menu.locked', { level = contract.minLevel })
                    or ('%s<br>Base pay: $%s-$%s | XP: %s'):format(contract.description, contract.reward.min, contract.reward.max, contract.experience),
                disabled = locked,
                params = {
                    event = 'qb-tow:client:SelectContract',
                    args = { contractKey = contractKey },
                },
            }
        end
        menu[#menu + 1] = {
            header = Lang:t('menu.close_menu'),
            params = { event = 'qb-menu:client:closeMenu' },
        }
        exports['qb-menu']:openMenu(menu)
    end)
end

local function openVehicleMenu()
    if not isTowEmployee() then return end
    local menu = { { header = Lang:t('menu.header'), isMenuHeader = true } }
    for model, label in pairs(Config.Vehicles) do
        menu[#menu + 1] = {
            header = label,
            params = {
                event = 'qb-tow:client:TakeOutVehicle',
                args = { vehicle = model },
            },
        }
    end
    menu[#menu + 1] = {
        header = Lang:t('menu.close_menu'),
        params = { event = 'qb-menu:client:closeMenu' },
    }
    exports['qb-menu']:openMenu(menu)
end

local function openServiceRequests()
    if not isTowEmployee() then return end
    QBCore.Functions.TriggerCallback('qb-tow:server:GetServiceRequests', function(requests)
        local menu = { { header = Lang:t('menu.service_requests'), isMenuHeader = true } }
        for _, request in ipairs(requests) do
            menu[#menu + 1] = {
                header = Lang:t('menu.request_from', { value = request.requesterName }),
                txt = Lang:t('menu.request_vehicle', { value = request.vehicleName }),
                params = {
                    event = 'qb-tow:client:AcceptServiceRequest',
                    args = { requestId = request.id },
                },
            }
        end
        if #requests == 0 then
            menu[#menu + 1] = { header = Lang:t('menu.no_requests'), isMenuHeader = true }
        end
        menu[#menu + 1] = {
            header = Lang:t('menu.close_menu'),
            params = { event = 'qb-menu:client:closeMenu' },
        }
        exports['qb-menu']:openMenu(menu)
    end)
end

local function runServiceObjective(vehicle)
    local objective = CurrentMission.objective
    local playerPed = PlayerPedId()
    local actions = {
        repair = Lang:t('mission.repairing'),
        tire = Lang:t('mission.changing_tire'),
        jump = Lang:t('mission.jump_starting'),
        fuel = Lang:t('mission.delivering_fuel'),
        unlock = Lang:t('mission.unlocking'),
    }
    QBCore.Functions.Progressbar('tow_service_action', actions[objective] or Lang:t('mission.repairing'), Config.ContractSettings.actionDuration, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {
        animDict = 'mini@repair',
        anim = 'fixing_a_ped',
        flags = 16,
    }, {}, {}, function()
        StopAnimTask(playerPed, 'mini@repair', 'fixing_a_ped', 1.0)
        if not DoesEntityExist(vehicle) or not CurrentMission then return end

        if objective == 'repair' then
            SetVehicleFixed(vehicle)
            SetVehicleDeformationFixed(vehicle)
        elseif objective == 'tire' then
            for tire = 0, 7 do
                SetVehicleTyreFixed(vehicle, tire)
            end
        elseif objective == 'jump' then
            SetVehicleEngineHealth(vehicle, 1000.0)
            SetVehicleUndriveable(vehicle, false)
            SetVehicleEngineOn(vehicle, true, true, false)
        elseif objective == 'fuel' then
            SetVehicleFuelLevel(vehicle, 25.0)
            if GetResourceState('LegacyFuel') == 'started' then
                exports['LegacyFuel']:SetFuel(vehicle, 25.0)
            end
        elseif objective == 'unlock' then
            SetVehicleDoorsLocked(vehicle, 1)
            SetVehicleDoorsLockedForAllPlayers(vehicle, false)
        end

        finishMission(vehicle)
    end, function()
        StopAnimTask(playerPed, 'mini@repair', 'fixing_a_ped', 1.0)
        notify(Lang:t('error.failed'), 'error')
    end)
end

local function towOrUntowVehicle()
    if not isTowEmployee() then return end
    if not CurrentMission then
        notify(Lang:t('error.no_active_contract'), 'error')
        return
    end
    if CurrentMission.objective ~= 'tow' then
        notify(Lang:t('error.not_tow_contract'), 'error')
        return
    end

    local ped = PlayerPedId()
    local towVehicle = GetVehiclePedIsIn(ped, true)
    local towModel = getTowVehicleModel(towVehicle)
    if not towModel then
        notify(Lang:t('error.not_towing_vehicle'), 'error')
        return
    end

    if TowedVehicle and DoesEntityExist(TowedVehicle) then
        QBCore.Functions.Progressbar('untowing_vehicle', Lang:t('mission.untowing_vehicle'), Config.ContractSettings.actionDuration, false, true, {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        }, {
            animDict = 'mini@repair',
            anim = 'fixing_a_ped',
            flags = 16,
        }, {}, {}, function()
            StopAnimTask(ped, 'mini@repair', 'fixing_a_ped', 1.0)
            local vehicle = TowedVehicle
            FreezeEntityPosition(vehicle, false)
            DetachEntity(vehicle, true, true)
            SetVehicleOnGroundProperly(vehicle)
            TowedVehicle = nil
            if isNear(Config.Locations.dropoff.coords, Config.ContractSettings.dropoffRadius) then
                finishMission(vehicle, towVehicle)
            else
                notify(Lang:t('mission.goto_depot'), 'primary')
            end
        end, function()
            StopAnimTask(ped, 'mini@repair', 'fixing_a_ped', 1.0)
            notify(Lang:t('error.failed'), 'error')
        end)
        return
    end

    if IsPedInAnyVehicle(ped, false) then
        notify(Lang:t('error.exit_tow_vehicle'), 'error')
        return
    end
    local from = GetEntityCoords(ped)
    local to = GetOffsetFromEntityInWorldCoords(ped, 0.0, 6.0, 0.0)
    local targetVehicle = getVehicleInDirection(from, to)
    if targetVehicle == 0 or targetVehicle == towVehicle or not DoesEntityExist(targetVehicle) then
        notify(Lang:t('error.vehicle_not_correct'), 'error')
        return
    end

    local assignedVehicle = getMissionVehicle()
    if assignedVehicle == 0 or targetVehicle ~= assignedVehicle then
        notify(Lang:t('error.vehicle_not_correct'), 'error')
        return
    end
    local offset = Config.TowOffsets[towModel] or Config.TowOffsets.default or { x = 0.0, y = -2.0, z = 1.0, rotation = 0.0 }
    if #(GetEntityCoords(towVehicle) - GetEntityCoords(targetVehicle)) > 12.0 then
        notify(Lang:t('error.too_far_away'), 'error')
        return
    end

    QBCore.Functions.Progressbar('towing_vehicle', Lang:t('mission.towing_vehicle'), Config.ContractSettings.actionDuration, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {
        animDict = 'mini@repair',
        anim = 'fixing_a_ped',
        flags = 16,
    }, {}, {}, function()
        StopAnimTask(ped, 'mini@repair', 'fixing_a_ped', 1.0)
        if not DoesEntityExist(targetVehicle) or not DoesEntityExist(towVehicle) then return end
        NetworkRequestControlOfEntity(targetVehicle)
        AttachEntityToEntity(targetVehicle, towVehicle, GetEntityBoneIndexByName(towVehicle, 'bodyshell'),
            offset.x, offset.y, offset.z, 0.0, 0.0, offset.rotation, false, false, true, false, 20, true)
        FreezeEntityPosition(targetVehicle, true)
        TowedVehicle = targetVehicle
        clearBlip(CurrentBlip)
        CurrentBlip = nil
        DropoffBlip = setRoute(Config.Locations.dropoff.coords, Lang:t('mission.dropoff'), true)
        notify(Lang:t('mission.goto_depot'), 'primary')
    end, function()
        StopAnimTask(ped, 'mini@repair', 'fixing_a_ped', 1.0)
        notify(Lang:t('error.failed'), 'error')
    end)
end

RegisterNetEvent('qb-tow:client:SelectContract', function(data)
    if data and data.contractKey then acceptContract(data.contractKey) end
end)

RegisterNetEvent('qb-tow:client:OpenContractBoard', openContractBoard)
RegisterNetEvent('jobs:client:ToggleNpc', openContractBoard)
RegisterNetEvent('qb-tow:client:TowVehicle', towOrUntowVehicle)
RegisterNetEvent('qb-tow:client:OpenServiceRequests', openServiceRequests)

RegisterNetEvent('qb-tow:client:AcceptServiceRequest', function(data)
    if not data or not data.requestId then return end
    QBCore.Functions.TriggerCallback('qb-tow:server:AcceptServiceRequest', function(result)
        if not result or result.error then
            notify(Lang:t('error.request_unavailable'), 'error')
            return
        end
        startMission(result.assignment)
        MissionVehicle = NetToVeh(result.assignment.targetNetId)
    end, data.requestId)
end)

RegisterNetEvent('qb-tow:client:ServiceRequestCreated', function(request)
    notify(Lang:t('info.new_service_request', {
        name = request.requesterName,
        vehicle = request.vehicleName,
    }), 'primary')
end)

RegisterNetEvent('qb-tow:client:ServiceRequestCompleted', function()
    notify(Lang:t('success.request_completed'), 'success')
end)

RegisterNetEvent('qb-tow:client:RequestService', function()
    if not Config.PlayerRequests.enabled then return end
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        local from = GetEntityCoords(ped)
        vehicle = getVehicleInDirection(from, GetOffsetFromEntityInWorldCoords(ped, 0.0, 6.0, 0.0))
    end
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        notify(Lang:t('error.vehicle_not_correct'), 'error')
        return
    end

    TriggerServerEvent('qb-tow:server:CreateServiceRequest', NetworkGetNetworkIdFromEntity(vehicle))
end)

RegisterNetEvent('qb-tow:client:TakeOutVehicle', function(data)
    if not data or not data.vehicle or not Config.Vehicles[data.vehicle] then return end
    if not isNear(Config.Locations.vehicle.coords, 8.0) then
        notify(Lang:t('error.too_far_away'), 'error')
        return
    end
    TriggerServerEvent('qb-tow:server:DoBail', true, data.vehicle)
end)

RegisterNetEvent('qb-tow:client:SpawnVehicle', function(vehicleModel)
    if not isTowEmployee() or not Config.Vehicles[vehicleModel] then return end
    local coords = Config.Locations.vehicle.coords
    QBCore.Functions.TriggerCallback('QBCore:Server:SpawnVehicle', function(netId)
        if not netId then
            notify(Lang:t('error.spawn_failed'), 'error')
            TriggerServerEvent('qb-tow:server:DoBail', false)
            return
        end
        local vehicle = NetToVeh(netId)
        if vehicle == 0 or not DoesEntityExist(vehicle) then
            notify(Lang:t('error.spawn_failed'), 'error')
            return
        end
        SetVehicleNumberPlateText(vehicle, 'TOWR' .. tostring(math.random(1000, 9999)))
        SetEntityHeading(vehicle, coords.w)
        if GetResourceState('LegacyFuel') == 'started' then
            exports['LegacyFuel']:SetFuel(vehicle, 100.0)
        end
        SetEntityAsMissionEntity(vehicle, true, true)
        TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
        TriggerEvent('vehiclekeys:client:SetOwner', QBCore.Functions.GetPlate(vehicle))
        SetVehicleEngineOn(vehicle, true, true)
        for extra = 1, 9 do
            SetVehicleExtra(vehicle, extra, 0)
        end
        exports['qb-menu']:closeMenu()
    end, vehicleModel, coords, false)
end)

RegisterNetEvent('qb-tow:client:Vehicle', function()
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 and getTowVehicleModel(vehicle) then
        if CurrentMission then
            notify(Lang:t('error.finish_work'), 'error')
            return
        end
        DeleteVehicle(vehicle)
        TriggerServerEvent('qb-tow:server:DoBail', false)
    else
        openVehicleMenu()
    end
end)

RegisterNetEvent('qb-tow:client:OpenBossMenu', function()
    local playerData = QBCore.Functions.GetPlayerData()
    if not playerData.job or playerData.job.name ~= 'tow' or not (playerData.job.grade and playerData.job.grade.isboss) then
        notify(Lang:t('error.no_boss_access'), 'error')
        return
    end
    if not isNear(Config.Locations.main.coords, 8.0) then
        notify(Lang:t('error.must_be_at_hq'), 'error')
        return
    end

    if GetResourceState('qb-management') == 'started' then
        TriggerEvent('qb-bossmenu:client:OpenMenu')
    elseif GetResourceState('qb-bossmenu') == 'started' then
        TriggerEvent('qb-bossmenu:client:OpenMenu')
    else
        notify(Lang:t('error.boss_menu_unavailable'), 'error')
    end
end)

RegisterNetEvent('qb-tow:client:CancelContract', function()
    if not CurrentMission then return end
    TriggerServerEvent('qb-tow:server:CancelContract', CurrentMission.id)
    if TowedVehicle and DoesEntityExist(TowedVehicle) then
        FreezeEntityPosition(TowedVehicle, false)
        DetachEntity(TowedVehicle, true, true)
        SetVehicleOnGroundProperly(TowedVehicle)
    end
    if SpawnedJobVehicle and DoesEntityExist(SpawnedJobVehicle) then
        DeleteVehicle(SpawnedJobVehicle)
    end
    clearMissionBlips()
    CurrentMission = nil
    MissionVehicle = nil
    TowedVehicle = nil
    SpawnedJobVehicle = nil
    SpawningJobVehicle = false
    SpawnAttemptId = SpawnAttemptId + 1
    NextSpawnAttempt = 0
    notify(Lang:t('success.contract_cancelled'), 'primary')
end)

local function createBlips()
    if TowBlipCreated then return end
    TowBlipCreated = true

    local office = Config.Locations.main.coords
    local officeBlip = AddBlipForCoord(office.x, office.y, office.z)
    SetBlipSprite(officeBlip, 477)
    SetBlipDisplay(officeBlip, 4)
    SetBlipScale(officeBlip, 0.65)
    SetBlipAsShortRange(officeBlip, true)
    SetBlipColour(officeBlip, 15)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Config.Locations.main.label)
    EndTextCommandSetBlipName(officeBlip)

    local garage = Config.Locations.vehicle.coords
    local garageBlip = AddBlipForCoord(garage.x, garage.y, garage.z)
    SetBlipSprite(garageBlip, 326)
    SetBlipDisplay(garageBlip, 4)
    SetBlipScale(garageBlip, 0.65)
    SetBlipAsShortRange(garageBlip, true)
    SetBlipColour(garageBlip, 15)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Config.Locations.vehicle.label)
    EndTextCommandSetBlipName(garageBlip)
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerJob = QBCore.Functions.GetPlayerData().job or {}
    if isTowEmployee() then createBlips() end
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(jobInfo)
    PlayerJob = jobInfo
    if isTowEmployee() then
        createBlips()
    elseif CurrentMission then
        TriggerEvent('qb-tow:client:CancelContract')
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    Wait(1000)
    PlayerJob = QBCore.Functions.GetPlayerData().job or {}
    if isTowEmployee() then createBlips() end
end)

CreateThread(function()
    while true do
        local waitTime = 1000
        local playerCoords = GetEntityCoords(PlayerPedId())
        if isTowEmployee() then
            local hq = Config.Locations.main.coords
            local garage = Config.Locations.vehicle.coords
            local hqDistance = #(playerCoords - vector3(hq.x, hq.y, hq.z))
            local garageDistance = #(playerCoords - vector3(garage.x, garage.y, garage.z))

            if hqDistance < 15.0 then
                waitTime = 0
                DrawMarker(2, hq.x, hq.y, hq.z + 0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.2, 40, 150, 255, 180, false, false, false, true, false, false, false)
                if hqDistance < 2.0 then
                    showHelp(Lang:t('info.open_contract_board'))
                    if IsControlJustReleased(0, 38) then openContractBoard() end
                end
            end

            if garageDistance < 20.0 then
                waitTime = 0
                DrawMarker(2, garage.x, garage.y, garage.z + 0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.2, 40, 150, 255, 180, false, false, false, true, false, false, false)
                if garageDistance < 3.0 then
                    showHelp(Lang:t('info.vehicle_garage'))
                    if IsControlJustReleased(0, 38) then TriggerEvent('qb-tow:client:Vehicle') end
                end
            end
        end

        if CurrentMission then
            waitTime = 0
            local coords = CurrentMission.location
            local missionPosition = vector3(coords.x, coords.y, coords.z)
            local distance = #(playerCoords - missionPosition)
            if not CurrentMission.playerRequest and distance < 50.0 and not SpawnedJobVehicle then
                spawnMissionVehicle(CurrentMission)
            end

            if CurrentMission.objective ~= 'tow' and distance < Config.ContractSettings.interactionDistance + 1.0 then
                DrawMarker(2, coords.x, coords.y, coords.z + 0.3, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.35, 0.35, 0.25, 40, 220, 120, 180, false, false, false, true, false, false, false)
                showHelp(Lang:t('info.perform_service', { value = CurrentMission.label }))
                if IsControlJustReleased(0, 38) then
                    local vehicle = getMissionVehicle()
                    if vehicle ~= 0 and #(GetEntityCoords(vehicle) - missionPosition) <= Config.ContractSettings.serviceRadius then
                        runServiceObjective(vehicle)
                    else
                        notify(Lang:t('error.vehicle_not_correct'), 'error')
                    end
                end
            end
        end
        Wait(waitTime)
    end
end)
