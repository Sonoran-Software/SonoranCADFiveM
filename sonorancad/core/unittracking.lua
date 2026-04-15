local UnitCache = {}
local CallCache = {}
local EmergencyCache = {}
local PlayerUnitMapping = {}

ActiveDispatchers = ActiveDispatchers or {}
dispatchOnline = dispatchOnline or false

local function syncDispatchOnline()
    dispatchOnline = #ActiveDispatchers > 0
end

local function findActiveDispatcherIndex(id)
    if id == nil then
        return nil
    end
    for i, dispatcher in pairs(ActiveDispatchers) do
        if dispatcher ~= nil and dispatcher.id == id then
            return i
        end
    end
    return nil
end

local function addActiveDispatcher(id, isInGame)
    if id == nil then
        syncDispatchOnline()
        return
    end
    local idx = findActiveDispatcherIndex(id)
    if idx ~= nil then
        ActiveDispatchers[idx].isInGame = isInGame == true
        syncDispatchOnline()
        return
    end
    table.insert(ActiveDispatchers, {
        id = id,
        isInGame = isInGame == true
    })
    syncDispatchOnline()
end

local function removeActiveDispatcher(id)
    local idx = findActiveDispatcherIndex(id)
    if idx ~= nil then
        table.remove(ActiveDispatchers, idx)
    end
    syncDispatchOnline()
end

local function rebuildActiveDispatchers(units)
    ActiveDispatchers = {}
    for _, unit in pairs(units) do
        if unit ~= nil and unit.isDispatch then
            local playerId = GetSourceByCadIdentity(GetUnitIdentityValues(unit))
            table.insert(ActiveDispatchers, {
                id = unit.id,
                isInGame = playerId ~= nil
            })
        end
    end
    syncDispatchOnline()
end

function GetUnitIdentityValues(unit)
    if unit == nil then
        return {}
    end

    local data = unit.data or unit
    if type(data.communityUserIds) == "table" and #data.communityUserIds > 0 then
        return data.communityUserIds
    end
    if type(data.communityUserId) == "string" and data.communityUserId ~= "" then
        return {data.communityUserId}
    end
    if type(data.apiIds) == "table" and #data.apiIds > 0 then
        return data.apiIds
    end

    return {}
end

local function findUnitById(identIds)
    if identIds == nil then
        return nil
    end
    for k, v in pairs(UnitCache) do
        if type(identIds) == "number" then
            if identIds == v.id then
                return k
            end
        else
            local ids = GetUnitIdentityValues(v)
            for _, id in pairs(ids) do
                if has_value(identIds, id) then
                    return k
                end
            end
        end
    end
    return nil
end

function GetSourceByCadIdentity(identities)
    if identities == nil then return nil end
    for x=1, #identities do
        for i=0, GetNumPlayerIndices()-1 do
            local player = GetPlayerFromIndex(i)
            if player then
                local identifiers = GetIdentifiers(player)
                for type, id in pairs(identifiers) do
                    if id == identities[x] then
                        return player
                    end
                end
                local communityUserId = GetPlayerCommunityUserId ~= nil and GetPlayerCommunityUserId(player) or nil
                if communityUserId ~= nil and communityUserId == identities[x] then
                    return player
                end
            end
        end
    end
    return nil
end

function GetUnitCache(includeDispatchers)
    if includeDispatchers then
        return UnitCache, ActiveDispatchers
    end
    return UnitCache
end
function GetCallCache() return CallCache end
function GetEmergencyCache() return EmergencyCache end
function SetUnitCache(k, v)
    local key = findUnitById(k)
    if key ~= nil and UnitCache[key] ~= nil then
        UnitCache[key] = v
    else
        table.insert(UnitCache, v)
    end
end
function SetCallCache(k, v)
    CallCache[k] = v
    TriggerEvent('SonoranCAD::pushevents:CallCacheUpdated')
end
function SetEmergencyCache(k, v)
    EmergencyCache[k] = v
    TriggerEvent('SonoranCAD::pushevents:EmergencyCacheUpdated')
end


-- Global function wrapper
function GetUnitById(ids) return findUnitById(ids) end

function GetUnitObjectById(id)
    if UnitCache[id] ~= nil then
        return UnitCache[id]
    else
        return nil
    end
end

function GetUnitByPlayerId(player)
    local identifiers = GetIdentifiers(player)
    local ids = {}
    for k, v in pairs(identifiers) do
        table.insert(ids, v)
    end
    local communityUserId = GetPlayerCommunityUserId ~= nil and GetPlayerCommunityUserId(player) or nil
    if communityUserId ~= nil then
        table.insert(ids, communityUserId)
    end
    local index = findUnitById(ids)
    if index then
        return UnitCache[index]
    end
    return nil
end

exports('GetUnitByPlayerId', GetUnitByPlayerId)
exports('GetUnitCache', GetUnitCache)
exports('GetCallCache', GetCallCache)
exports('GetEmergencyCache', GetEmergencyCache)
exports('GetUnitById', GetUnitById)


AddEventHandler("playerDropped", function()
    local id = GetUnitByPlayerId(source)
    local unit = findUnitById(id)
    if unit then
        if UnitCache[unit].isDispatch then
            addActiveDispatcher(UnitCache[unit].id, false)
        end
        TriggerEvent("SonoranCAD::core:RemovePlayer", source, UnitCache[unit])
        UnitCache[unit] = nil
    end
end)

AddEventHandler("SonoranCAD::pushevents:UnitLogin", function(unit)
    local playerId = GetSourceByCadIdentity(GetUnitIdentityValues(unit))
    if unit.isDispatch then
        addActiveDispatcher(unit.id, playerId ~= nil)
    end
    if playerId then
        PlayerUnitMapping[playerId] = unit.id
        TriggerEvent("SonoranCAD::core:AddPlayer", playerId, unit)
        TriggerClientEvent("SonoranCAD::core:AddPlayer", playerId, unit)
    else
        debugLog(("Unknown unit %s and player %s"):format(json.encode(unit), playerId))
    end
end)

AddEventHandler("SonoranCAD::pushevents:UnitLogout", function(id)
    removeActiveDispatcher(id)
    if Config.noUnitTimer then
        local key = findUnitById(id)
        debugLog(("unitlogout key %s"):format(key))
        if key then
            local playerId = GetSourceByCadIdentity(GetUnitIdentityValues(UnitCache[key]))
            if playerId then
                debugLog(("Triggering RemovePlayer on ID %s"):format(playerId))
                TriggerEvent("SonoranCAD::core:RemovePlayer", playerId, UnitCache[key])
                TriggerClientEvent("SonoranCAD::core:RemovePlayer", playerId)
                PlayerUnitMapping[playerId] = nil
            end
        end
        SetUnitCache(id, nil)
    end
end)


registerApiType("GET_ACTIVE_UNITS", "emergency")
Citizen.CreateThread(function()
    Wait(500)
    while Config.apiVersion == -1 do
        Wait(1000)
    end
    if (Config.noUnitTimer == "true" or Config.noUnitTimer == true) or Config.apiVersion < 3 then
        debugLog("Disabling active units routine")
        return
    elseif not Config.apiSendEnabled then
        errorLog("Config.apiSendEnabled disabled via convar or config, skipping unit caching. Check your config if this is unintentional.")
        return
    end
    while true do
        local OldUnits = {}
        local NewUnits = {}
        for k, v in pairs(UnitCache) do
            OldUnits[k] = v
        end
        if GetNumPlayerIndices() > 0 then
            local payload = { serverId = Config.serverId, unitsOnly = false }
            performApiRequest({payload}, "GET_ACTIVE_UNITS", function(runits)
                local allUnits = json.decode(runits)
                if allUnits ~= nil then
                    rebuildActiveDispatchers(allUnits)
                    for k, v in pairs(allUnits) do
                        local playerId = GetSourceByCadIdentity(GetUnitIdentityValues(v))
                        if playerId then
                            PlayerUnitMapping[playerId] = v.id
                            table.insert(NewUnits, v)
                            TriggerEvent("SonoranCAD::core:AddPlayer", playerId, v)
                        else
                            debugLog(("Couldn't find unit, not adding %s (%s)"):format(playerId, json.encode(GetUnitIdentityValues(v))))
                        end
                    end
                end
                for k, v in pairs(OldUnits) do
                    local exists = false
                    for _, n in pairs(NewUnits) do
                        if n.id == v.id then
                            exists = true
                        end
                    end
                    if not exists then
                        debugLog(("Removing player %s, not on units list"):format(k))
                        PlayerUnitMapping[k] = nil
                        TriggerEvent("SonoranCAD::core:RemovePlayer", k, v)
                        TriggerClientEvent("SonoranCAD::core:RemovePlayer", k, v)
                    end
                end
                UnitCache = {}
                for k, v in pairs(NewUnits) do
                    debugLog("Insert unit "..json.encode(v))
                    table.insert(UnitCache, v)
                end
                if allUnits == nil then
                    rebuildActiveDispatchers({})
                end
            end)
        end
        Citizen.Wait(60000)
    end
end)

registerApiType("GET_CALLS", "emergency")
CreateThread(function()
    Wait(1000)
    while Config.apiVersion == -1 do
        Wait(10)
    end
    if Config.apiVersion < 3 then
        debugLog("Too low version or API disabled, skip call caching")
        return
    elseif not Config.apiSendEnabled then
        errorLog("Config.apiSendEnabled disabled via convar or config, skipping call caching. Check your config if this is unintentional.")
        return
    end
    local payload = { serverId = Config.serverId}
    while true do
        performApiRequest({payload},"GET_CALLS",function(response)
            local calls = json.decode(response)
            for k, v in pairs(calls.activeCalls) do
                CallCache[v.callId] = { dispatch = v }
            end
            for k, v in pairs(calls.emergencyCalls) do
                EmergencyCache[v.callId] = v
            end
        end)
        Citizen.Wait(60 * 1000)
    end
end)


function manuallySetUnitCache()
    local OldUnits = {}
    local NewUnits = {}
    for k, v in pairs(UnitCache) do
        OldUnits[k] = v
    end
    if GetNumPlayerIndices() > 0 then
        local payload = { serverId = Config.serverId, unitsOnly = false }
        performApiRequest({payload}, "GET_ACTIVE_UNITS", function(runits)
            local allUnits = json.decode(runits)
            if allUnits ~= nil then
                rebuildActiveDispatchers(allUnits)
                for _, v in pairs(allUnits) do
                    local playerId = GetSourceByCadIdentity(GetUnitIdentityValues(v))
                    if playerId then
                        PlayerUnitMapping[playerId] = v.id
                        table.insert(NewUnits, v)
                        TriggerEvent("SonoranCAD::core:AddPlayer", playerId, v)
                    else
                        debugLog(("Couldn't find unit, not adding %s (%s)"):format(playerId, json.encode(GetUnitIdentityValues(v))))
                    end
                end
            end
            for k, v in pairs(OldUnits) do
                local exists = false
                for _, n in pairs(NewUnits) do
                    if n.id == v.id then
                        exists = true
                    end
                end
                if not exists then
                    debugLog(("Removing player %s, not on units list"):format(k))
                    PlayerUnitMapping[k] = nil
                    TriggerEvent("SonoranCAD::core:RemovePlayer", k, v)
                    TriggerClientEvent("SonoranCAD::core:RemovePlayer", k, v)
                end
            end
            UnitCache = {}
            for _, v in pairs(NewUnits) do
                debugLog("Insert unit "..json.encode(v))
                table.insert(UnitCache, v)
            end
            if allUnits == nil then
                rebuildActiveDispatchers({})
            end
        end)
    end
end

exports('ManuallySetUnitCache', manuallySetUnitCache())
