CallCache = {}
EmergencyCache = {}
local tabletScreens = {}
local function isCadDisplayEnabled()
    local ok, cfg = pcall(function()
        return exports["sonorancad"]:GetPluginConfig("caddisplay")
    end)
    if not ok or type(cfg) ~= "table" then
        return false
    end
    return cfg.enabled == true
end

CreateThread(function()
    while GetResourceState("sonorancad") ~= "started" do
        print("Waiting for sonorancad resource to start... (current state: "..GetResourceState("sonorancad")..")")
        Wait(5000)
    end

    local function debounce(fn, time)
        local i = 0
        return function()
            i = i + 1
            local iCopy = i
            Citizen.CreateThread(function()
                Wait(time)
                -- invoke if 'i' hasn't been incremented since this thread was created
                if i == iCopy then fn() end
            end)
        end
    end
    -- safely remove keys of an object based on a predicate
    local function removeKeyAt(obj, predicate)
        local kToRemove = {}
        for k, v in pairs(obj) do
            if predicate(k, v) then
                table.insert(kToRemove, k)
            end
        end
        for _, k in ipairs(kToRemove) do
            obj[k] = nil
        end
        return obj
    end

    local function miniCadCallSync()
        local callCache = exports['sonorancad']:GetCallCache()
        local unitCache = exports['sonorancad']:GetUnitCache()
        removeKeyAt(callCache, function(k, v)
            -- only include active calls
            -- Jordan 11/5 - This is causing pending calls to not show up in the mini cad
            -- if v.dispatch.status ~= 1 then return true end

            -- add unit info to the call (idk if this is really needed)
            v.dispatch.units = {}
            if v.dispatch.idents then
                for _, va in pairs(v.dispatch.idents) do
                    local unitId = exports['sonorancad']:GetUnitById(va)
                    table.insert(v.dispatch.units, unitCache[unitId])
                end
            end
            return false
        end)
        CallCache = callCache

        -- the cache already removes stale 911 calls, no need to use removeKeyAt
        EmergencyCache = exports["sonorancad"]:GetEmergencyCache()

        -- TODO: only send to active units
        TriggerClientEvent("SonoranCAD::mini:CallSync", -1, CallCache, EmergencyCache)
    end
    local miniCadCallSyncDebounced = debounce(miniCadCallSync, 1000)
    miniCadCallSyncDebounced() -- call immediately for sync

    -- watch for calls and emergencies
    -- NOTE: debounce because these can come through in quick succession
    AddEventHandler('SonoranCAD::pushevents:CallCacheUpdated', miniCadCallSyncDebounced)
    AddEventHandler('SonoranCAD::pushevents:EmergencyCacheUpdated', miniCadCallSyncDebounced)

    RegisterNetEvent("SonoranCAD::mini:CallSync_S")
    AddEventHandler("SonoranCAD::mini:CallSync_S", function()
        TriggerClientEvent("SonoranCAD::mini:CallSync", source, CallCache, EmergencyCache)
    end)

    AddEventHandler("SonoranCAD::pushevents:DispatchNote", function(data)
        TriggerClientEvent("SonoranCAD::mini:NewNote", -1, data)
    end)

    local function getLinkedUnitContext(player)
        local ident = exports["sonorancad"]:GetUnitByPlayerId(player)
        if ident == nil or ident.data == nil then
            return nil, nil
        end

        local communityUserId = exports["sonorancad"].getPlayerCommunityUserId
            and exports["sonorancad"]:getPlayerCommunityUserId(player)
            or nil
        if communityUserId == nil or communityUserId == "" then
            return ident, nil
        end

        return ident, communityUserId
    end

    RegisterServerEvent("SonoranCAD::mini:OpenMini")
    AddEventHandler("SonoranCAD::mini:OpenMini", function ()
        local ident, communityUserId = getLinkedUnitContext(source)
        if ident == nil then TriggerClientEvent("SonoranCAD::mini:OpenMini:Return", source, false) return end
        if communityUserId == nil then TriggerClientEvent("SonoranCAD::mini:OpenMini:Return", source, false) return end
        TriggerClientEvent("SonoranCAD::mini:CallSync", source, CallCache, EmergencyCache)
        TriggerClientEvent("SonoranCAD::mini:OpenMini:Return", source, true, ident.id)
    end)

    RegisterServerEvent("SonoranCAD::mini:AttachToCall")
    AddEventHandler("SonoranCAD::mini:AttachToCall", function(callId)
        local ident, communityUserId = getLinkedUnitContext(source)
        if ident ~= nil and communityUserId ~= nil then
            local data = {callId = callId, units = {communityUserId}, serverId = tonumber(GetConvar("sonoran_serverId", 1))}
            exports["sonorancad"]:performApiRequest({data}, "ATTACH_UNIT", function(res)
                --print("Attach OK: " .. tostring(res))
            end)
        else
            --print("Unable to attach... if the CAD account is linked properly, try relogging into CAD.")
        end
    end)

    RegisterServerEvent("SonoranCAD::mini:DetachFromCall")
    AddEventHandler("SonoranCAD::mini:DetachFromCall", function(callId)
        local ident, communityUserId = getLinkedUnitContext(source)
        if ident ~= nil and communityUserId ~= nil then
            local data = {callId = callId, units = {communityUserId}, serverId = tonumber(GetConvar("sonoran_serverId", 1))}
            exports["sonorancad"]:performApiRequest({data}, "DETACH_UNIT", function(res)
                --print("Detach OK: " .. tostring(res))
            end)
        else
            --print("Unable to detach... if the CAD account is linked properly, try relogging into CAD.")
        end
    end)

    RegisterNetEvent("SonoranCAD::tabletDisplay::BroadcastCadScreenshot", function(image)
        if not image or image == "" then
            return
        end
        if not isCadDisplayEnabled() then
            return
        end
        local src = source
        tabletScreens[src] = image
        local srcPed = GetPlayerPed(src)
        if srcPed == 0 or not DoesEntityExist(srcPed) then
            return
        end
        local srcCoords = GetEntityCoords(srcPed)
        local updateRadius = 15.0
        local updateRadiusSq = updateRadius * updateRadius
        for _, playerId in ipairs(GetPlayers()) do
            local ped = GetPlayerPed(playerId)
            if ped ~= 0 and DoesEntityExist(ped) then
                local pedCoords = GetEntityCoords(ped)
                if #(pedCoords - srcCoords) <= updateRadius then
                    TriggerLatentClientEvent("SonoranCAD::tabletDisplay::UpdateDui", playerId, 0, src, image)
                end
            end
        end
    end)

    AddEventHandler("playerDropped", function()
        tabletScreens[source] = nil
    end)

    RegisterNetEvent("SonoranCAD::tabletDisplay::RequestConfig", function()
        TriggerClientEvent("SonoranCAD::tabletDisplay::Config", source, {
            enabled = isCadDisplayEnabled()
        })
    end)

    AddEventHandler("playerJoining", function(playerId)
        if not isCadDisplayEnabled() then
            return
        end
        local joinPed = GetPlayerPed(playerId)
        if joinPed == 0 or not DoesEntityExist(joinPed) then
            return
        end
        local joinCoords = GetEntityCoords(joinPed)
        local updateRadius = 15.0
        local updateRadiusSq = updateRadius * updateRadius
        for owner, image in pairs(tabletScreens) do
            local ownerPed = GetPlayerPed(owner)
            if ownerPed ~= 0 and DoesEntityExist(ownerPed) then
                local ownerCoords = GetEntityCoords(ownerPed)
                local dx = ownerCoords.x - joinCoords.x
                local dy = ownerCoords.y - joinCoords.y
                local dz = ownerCoords.z - joinCoords.z
                if (dx * dx + dy * dy + dz * dz) <= updateRadiusSq then
                    TriggerLatentClientEvent("SonoranCAD::tabletDisplay::UpdateDui", playerId, 0, owner, image)
                end
            end
        end
    end)
end)

