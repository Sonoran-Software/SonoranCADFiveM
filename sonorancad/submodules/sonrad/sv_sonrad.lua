--[[
    Sonaran CAD Plugins

    Plugin Name: sonrad
    Creator: Sonoran Software Systems
    Description: Sonoran Radio integration plugin

    Put all server-side logic in this file.
]]

CreateThread(function() Config.LoadPlugin("sonrad", function(pluginConfig)

    if pluginConfig.enabled then

        local CallCache = {}
        local UnitCache = {}
        local TowerCache = {}


        if Config.apiVersion > 3 then
            BlipMan = {
                addBlip = function(coords, radius, colorHex, subType, toolTip, icon, dataTable, cb)
                    local data = {
                        ["serverId"] = tonumber(GetConvar("sonoran_serverId", 1)),
                        ["subType"] = subType,
                        ["coordinates"] = {
                            ["x"] = coords.x,
                            ["y"] = coords.y
                        },
                        ["radius"] = radius,
                        ["icon"] = icon,
                        ["color"] = colorHex,
                        ["tooltip"] = toolTip,
                        ["data"] = dataTable
                    }

                    local response = CadApiCreateBlips({data})
                    if not response.success then
                        CadApiLogFailure("ADD_BLIP", response, data)
                    elseif cb ~= nil then
                        cb(json.encode(response.data))
                    end
                end,

                addBlips = function(blips, cb)
                    local response = CadApiCreateBlips(blips)
                    if not response.success then
                        CadApiLogFailure("ADD_BLIP", response, blips)
                    elseif cb ~= nil then
                        cb(json.encode(response.data))
                    end
                end,

                removeBlip = function(ids, cb)
                    local payload = {["ids"] = ids}
                    local response = CadApiDeleteBlips(payload)
                    if not response.success then
                        CadApiLogFailure("REMOVE_BLIP", response, payload)
                    elseif cb ~= nil then
                        cb(tostring(response.data and json.encode(response.data) or "OK"))
                    end
                end,

                modifyBlips = function(dataTable, cb)
                    local response = CadApiUpdateBlips(dataTable)
                    if not response.success then
                        CadApiLogFailure("MODIFY_BLIP", response, dataTable)
                    elseif cb ~= nil then
                        cb(tostring(response.data and json.encode(response.data) or "OK"))
                    end
                end,

                getBlips = function(cb)
                    local response = CadApiGetBlips(tonumber(GetConvar("sonoran_serverId", 1)))
                    if not response.success then
                        CadApiLogFailure("GET_BLIPS", response,  tonumber(GetConvar("sonoran_serverId", 1)))
                    elseif cb ~= nil then
                        cb(json.encode(response.data or {}))
                    end
                end,

                removeWithSubtype = function(subType, cb)
                    BlipMan.getBlips(function(res)
                        local dres = json.decode(res)
                        local ids = {}
                        for _, v in ipairs(dres) do
                            if v.subType == subType then
                                table.insert(ids, #ids + 1, v.id)
                            end
                        end
                        if #ids < 1 then
                            if cb ~= nil then
                                cb("No blips found with subtype: " .. subType)
                            end
                            return
                        end
                        BlipMan.removeBlip(ids, cb)
                    end)
                end,
            }

            function GetTower(coords)
                for i = 1, #TowerCache do
                    if TowerCache[i].PropPosition == coords then
                        return TowerCache[i], i
                    end
                end
                return nil, nil
            end
            function GetTowerFromId(id)
                for i, t in ipairs(TowerCache) do
                    if t.Id == id then
                        return t, i
                    end
                end
            end
            function GetTowerCapacity(tower)
                if #tower.DishStatus < 1 then
                    return 1.0
                end

                local n = 0.0
                for i = 1, #tower.DishStatus do
                    if tower.DishStatus[i] == 'alive' then
                        n = n + 1.0
                    end
                end
                return n / #tower.DishStatus
            end

            RegisterNetEvent("SonoranCAD::sonrad:SyncTowers")
            AddEventHandler("SonoranCAD::sonrad:SyncTowers", function(Towers)
                BlipMan.removeWithSubtype("repeater", function(res)
                    debugLog(res)

                    TowerCache = Towers

                    local BlipQueue = {}

                    debugLog(json.encode(TowerCache))
                    for _,tower in ipairs(TowerCache) do

                        if tower.NotPhysical then
                            -- Handling for Mobile Repeaters
                            title = "Mobile Repeater"
                            color = "#ff00f6"
                            status = "MOBILE"
                        else
                            -- Handling for Stationary Repeaters
                            title = "Radio Tower"
                            color = "#00a6ff"
                            status = "HEALTHY"
                        end

                        local CurrentBlip = {
                            ["serverId"] = tonumber(GetConvar("sonoran_serverId", 1)),
                            ["subType"] = "repeater",
                            ["coordinates"] = {
                                ["x"] = tower.PropPosition.x,
                                ["y"] = tower.PropPosition.y
                            },
                            ["radius"] = tower.Range * 0.7937,
                            ["icon"] = "https://sonoransoftware.com/assets/images/icons/email/radio.png",
                            ["color"] = color,
                            ["tooltip"] =  title,
                            ["data"] = {
                                {
                                    ["title"] = "Status",
                                    ["text"] = status,
                                }
                            }
                        }

                        table.insert(BlipQueue, #BlipQueue + 1, CurrentBlip)
                    end
                    for i=1, #BlipQueue do
                        local queuedBlip = BlipQueue[i]
                        debugLog("Queueing blip for tower at coords: " .. queuedBlip.coordinates.x .. ", " .. queuedBlip.coordinates.y)
                        BlipMan.addBlip(queuedBlip.coordinates, queuedBlip.radius, queuedBlip.color, queuedBlip.subType, queuedBlip.tooltip, queuedBlip.icon, queuedBlip.data, function(res)
                            local createdBlips = json.decode(res)
                            local createdBlip = type(createdBlips) == "table" and createdBlips[1] or nil
                            if not createdBlip or not createdBlip.id then
                                warnLog("Failed to assign repeater blip ID for tower at coords: " .. queuedBlip.coordinates.x .. ", " .. queuedBlip.coordinates.y)
                                return
                            end
                            for towerIndex=1, #TowerCache do
                                if TowerCache[towerIndex].PropPosition.x == queuedBlip.coordinates.x and TowerCache[towerIndex].PropPosition.y == queuedBlip.coordinates.y then
                                    TowerCache[towerIndex].BlipID = createdBlip.id
                                    debugLog("Assigned blip ID " .. createdBlip.id .. " to tower at coords: " .. queuedBlip.coordinates.x .. ", " .. queuedBlip.coordinates.y)
                                end
                            end
                        end)
                    end
                end)
            end)

            CreateThread(function()
                while true do
                    Wait(5000)
                    for i=1, #TowerCache do
                        if TowerCache[i].Modified then
                            debugLog("Change found during batch... Sending")
                            TowerCache[i].Modified = false
                            local color = nil
                            local status = nil
                            local title = nil
                            if TowerCache[i].NotPhysical then
                                -- Handling for Mobile Repeaters
                                title = "Mobile Repeater"
                                color = "#ff00f6"
                                status = "MOBILE"
                            else
                                -- Handling for Stationary Repeaters
                                title = "Radio Tower"
                                color = "#00a6ff"
                                status = "HEALTHY"
                            end
                            local data = {{
                                ["id"] = TowerCache[i].BlipID,
                                ["subType"] = "repeater",
                                ["coordinates"] = {
                                    ["x"] = TowerCache[i].PropPosition.x,
                                    ["y"] = TowerCache[i].PropPosition.y
                                },
                                ["radius"] = TowerCache[i].Range * 0.7937,
                                ["icon"] = "https://sonoransoftware.com/assets/images/icons/email/radio.png",
                                ["color"] = color,
                                ["tooltip"] = title,
                                ["data"] = {
                                    {
                                        ["title"] = "Health",
                                        ["text"] = status
                                    }
                                }
                            }}
                            BlipMan.modifyBlips(data, function(res)
                                debugLog(res)
                            end)
                        else
                            --debugLog("No changes during batch... Ignoring")
                        end
                    end
                end
            end)

            RegisterNetEvent("SonoranCAD::sonrad:SyncOneTower")
            AddEventHandler("SonoranCAD::sonrad:SyncOneTower", function(towerId, newTower)
                local oldTower, towerIndex = GetTowerFromId(towerId)
                if not oldTower then
                    debugLog("Tower not found in cache... Ignoring")
                    return
                end
                local BlipID = oldTower.BlipID
                if not newTower or newTower == nil then
                    table.remove(TowerCache, towerIndex)
                    debugLog('New tower was nil... removing from TowerCache at index: '.. towerIndex)
                else
                    if oldTower.PropPosition.x == newTower.PropPosition.x and oldTower.PropPosition.y == newTower.PropPosition.y then
                        --debugLog("No Changes During Sync... Ignoring" .. towerIndex)
                    else
                        debugLog("Changes found during sync... Queuing" .. towerIndex)
                        TowerCache[towerIndex] = newTower
                        TowerCache[towerIndex].BlipID = BlipID
                        TowerCache[towerIndex].Modified = true
                    end
                end
            end)

            RegisterNetEvent("SonoranCAD::sonrad:SetDishStatus")
            AddEventHandler("SonoranCAD::sonrad:SetDishStatus", function(towerId, dishStatus)
                local tower = GetTowerFromId(towerId)
                if not tower then return end
                tower.DishStatus = dishStatus
                local pct = GetTowerCapacity(tower)
                local color = nil
                local status = nil
                if pct == 1 then
                    -- Tower is alive and well.
                    debugLog("TOWER IS HEALTHY")
                    color = "#00a6ff"
                    status = "HEALTHY"
                elseif pct == 0 then
                    -- Tower is offline
                    debugLog("TOWER IS OFFLINE")
                    color = "#ff0000"
                    status = "OFFLINE"
                else
                    -- Tower is degraded
                    debugLog("TOWER IS DEGRADED")
                    color = "#ff8c00"
                    status = "DEGRADED"
                end

                local data = {{
                    ["id"] = tower.BlipID,
                    ["subType"] = "repeater",
                    ["coordinates"] = {
                        ["x"] = tower.PropPosition.x,
                        ["y"] = tower.PropPosition.y
                    },
                    ["radius"] = tower.Range * 0.7937,
                    ["icon"] = "https://sonoransoftware.com/assets/images/icons/email/radio.png",
                    ["color"] = color,
                    ["tooltip"] =  "Radio Tower",
                    ["data"] = {
                        {
                            ["title"] = "Health",
                            ["text"] = status,
                        }
                    }
                }}
                BlipMan.modifyBlips(data, function(res)
                    debugLog(res)
                end)
            end)
        else
            debugLog("Disabling blip management, API version too low.")
        end


        CreateThread(function()
            while true do
                Wait(5000)
                CallCache = GetCallCache()
                UnitCache = GetUnitCache()
                for k, v in pairs(CallCache) do
                    v.dispatch.units = {}
                    if v.dispatch.idents then
                        for ka, va in pairs(v.dispatch.idents) do
                            local unit
                            local unitId = GetUnitById(va)
                            table.insert(v.dispatch.units, UnitCache[unitId])
                        end
                    end
                end
            end
        end)

        RegisterNetEvent('SonoranCAD::sonrad:GetCurrentCall')
        AddEventHandler('SonoranCAD::sonrad:GetCurrentCall', function()
            local playerid = source
            local unit = GetUnitByPlayerId(source)
            for k, v in pairs(CallCache) do
                if v.dispatch.idents then
                    for ka, va in pairs(v.dispatch.idents) do
                        if unit and unit.id == va then
                            TriggerClientEvent('SonoranCAD::sonrad:UpdateCurrentCall', source, v)
                            return
                        end
                    end
                end
            end

            TriggerClientEvent('SonoranCAD::sonrad:UpdateCurrentCall', source, nil)
        end)

        RegisterNetEvent("SonoranCAD::sonrad:RadioPanic")
        AddEventHandler("SonoranCAD::sonrad:RadioPanic", function()
            if not isPluginLoaded("callcommands") then
                errorLog("Cannot process radio panic as the required callcommands plugin is not present.")
                return
            end
            sendPanic(source, true)
        end)

        RegisterNetEvent("SonoranCAD::sonrad:GetUnitInfo")
        AddEventHandler("SonoranCAD::sonrad:GetUnitInfo", function()
            local unit = GetUnitByPlayerId(source)
            if unit then
                TriggerClientEvent("SonoranCAD::sonrad:GetUnitInfo:Return", source, unit)
            end
        end)

        if not pluginConfig.syncRadioName then
            pluginConfig.syncRadioName = {
                enabled = false, -- should the radio name be synced with the CAD?
                nameFormat = "{UNIT_NUMBER} | {UNIT_NAME}" -- format of the radio name | available variables: {UNIT_NUMBER}, {UNIT_NAME}
            }
            warnLog('Missing critial configuration for Sonrad. Missing syncRadioName configuration, using default values... Please update from sonrad_config.dist.lua')
        end
        AddEventHandler('SonoranCAD::pushevents:UnitLogin', function(unit)
            if pluginConfig.syncRadioName.enabled then
                local radioName = pluginConfig.syncRadioName.nameFormat
                radioName = radioName:gsub("{UNIT_NUMBER}", unit.data.unitNum)
                radioName = radioName:gsub("{UNIT_NAME}", unit.data.name)
                local postData = {
                    identity = unit.accId,
                    name = radioName
                }
                exports['sonoranradio']:serverNameChange(postData)
            end
        end)

    end

end) end)
