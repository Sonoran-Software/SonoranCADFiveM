--[[
    Sonoran CAD Plugins

    Plugin Name: caddisplay
    Description: CAD display placement/server persistence
]]

CreateThread(function()
    Config.LoadPlugin("caddisplay", function(pluginConfig)
        if pluginConfig.enabled then
            local placements = {}
            local nextId = 1
            local placementFile = "submodules/caddisplay/config/placements.json"
            local defaultPlacementFile = "submodules/caddisplay/config/placements.CHANGEME.json"
            local qbCore = nil
            local esx = nil
            local displayOwners = {}
            local pendingRequests = {}

            local function savePlacements()
                SaveResourceFile(GetCurrentResourceName(), placementFile, json.encode(placements), -1)
            end

            local function loadFramework()
                if pluginConfig.permissionMode ~= "framework" then
                    return
                end
                if pluginConfig.framework.frameworkType == "qb-core" and qbCore == nil then
                    local ok, obj = pcall(function() return exports["qb-core"]:GetCoreObject() end)
                    if ok then
                        qbCore = obj
                    else
                        warnLog(("[caddisplay] Unable to load qb-core export: %s"):format(tostring(obj)))
                    end
                elseif pluginConfig.framework.frameworkType == "esx" and esx == nil then
                    local ok, obj = pcall(function() return exports["es_extended"]:getSharedObject() end)
                    if ok then
                        esx = obj
                    else
                        warnLog(("[caddisplay] Unable to load es_extended export: %s"):format(tostring(obj)))
                    end
                end
            end

            local function isJobAllowed(jobName, list, invert)
                local matched = false
                for _, name in ipairs(list or {}) do
                    if jobName == name then
                        matched = true
                        break
                    end
                end
                if invert then
                    return not matched
                end
                return matched
            end

            local function checkPermissions(src)
                if not pluginConfig.commands.restricted then
                    return true, true
                end

                if pluginConfig.permissionMode == "ace" then
                    local isAdmin = IsPlayerAceAllowed(src, pluginConfig.acePerms.aceObjectAdminUseMenu)
                    local isAllowed = isAdmin or IsPlayerAceAllowed(src, pluginConfig.acePerms.aceObjectUseMenu)
                    return isAllowed, isAdmin
                elseif pluginConfig.permissionMode == "framework" then
                    loadFramework()
                    local job = nil
                    if pluginConfig.framework.frameworkType == "qb-core" and qbCore ~= nil then
                        local player = qbCore.Functions.GetPlayer(src)
                        if player and player.PlayerData and player.PlayerData.job then
                            job = player.PlayerData.job.name
                        end
                    elseif pluginConfig.framework.frameworkType == "esx" and esx ~= nil then
                        local xPlayer = esx.GetPlayerFromId(src)
                        if xPlayer and xPlayer.job then
                            job = xPlayer.job.name
                        end
                    end
                    if job == nil then
                        return false, false
                    end

                    local isAdmin = isJobAllowed(job, pluginConfig.framework.adminJobNames, false)
                    local isAllowed = isJobAllowed(job, pluginConfig.framework.civilianJobNames,
                                                pluginConfig.framework.useCivilianJobListAsBlacklist)
                    return isAllowed or isAdmin, isAdmin
                elseif pluginConfig.permissionMode == "custom" and pluginConfig.custom and
                    pluginConfig.custom.permissionCheck then
                    local ok = pluginConfig.custom.permissionCheck(src, 0)
                    return ok == true, ok == true
                end

                return true, true
            end

            local function loadPlacements()
                local stored = LoadResourceFile(GetCurrentResourceName(), placementFile)
                if not stored then
                    local defaultFile = LoadResourceFile(GetCurrentResourceName(), defaultPlacementFile)
                    if defaultFile then
                        infoLog("[caddisplay] No placements.json found, copying default template.")
                        SaveResourceFile(GetCurrentResourceName(), placementFile, defaultFile, -1)
                        stored = defaultFile
                    else
                        warnLog("[caddisplay] No placement data found; starting with empty placement list.")
                        placements = {}
                        return
                    end
                end

                local parsed = json.decode(stored)
                if not parsed or type(parsed) ~= "table" then
                    warnLog("[caddisplay] Failed to parse placement file; starting with empty placement list.")
                    placements = {}
                    return
                end

                placements = parsed
                nextId = 1
                for _, entry in ipairs(placements) do
                    local idNum = tonumber(entry.ID)
                    if idNum ~= nil and idNum >= nextId then
                        nextId = idNum + 1
                    end
                end
            end

            local function syncPlacements(target)
                TriggerClientEvent("SonoranCAD::caddisplay::SyncPlacements", target or -1, placements)
            end

            local function syncOwners(target)
                TriggerClientEvent("SonoranCAD::caddisplay::SyncOwners", target or -1, displayOwners)
            end

            local function clearPendingForPlayer(playerId)
                local changed = false
                for vehNet, req in pairs(pendingRequests) do
                    if req.owner == playerId or req.requester == playerId then
                        pendingRequests[vehNet] = nil
                        changed = true
                        if req.owner and req.owner ~= playerId then
                            TriggerClientEvent("SonoranCAD::caddisplay::ControlRequestExpired", req.owner, vehNet)
                        end
                        if req.requester and req.requester ~= playerId then
                            TriggerClientEvent("SonoranCAD::caddisplay::ControlRequestExpired", req.requester, vehNet)
                        end
                    end
                end
                return changed
            end

            local function upsertPlacement(data, src)
                local vehicleModel = string.upper(data.vehicle or "")
                if vehicleModel == "" then
                    if src then
                        TriggerClientEvent("chat:addMessage", src,
                            {args = {"CAD Display", "No vehicle model provided; placement not saved."}})
                    end
                    return
                end

                for i = #placements, 1, -1 do
                    if string.upper(placements[i].Vehicle) == vehicleModel then
                        table.remove(placements, i)
                    end
                end

                local placement = {
                    ID = tostring(nextId),
                    Vehicle = vehicleModel,
                    Bone = tonumber(data.bone) or -1,
                    Position = {
                        x = tonumber(data.position and data.position.x) or 0,
                        y = tonumber(data.position and data.position.y) or 0,
                        z = tonumber(data.position and data.position.z) or 0
                    },
                    Rotation = {
                        pitch = tonumber(data.rotation and data.rotation.x) or 0,
                        roll = tonumber(data.rotation and data.rotation.y) or 0,
                        yaw = tonumber(data.rotation and data.rotation.z) or 0
                    },
                    Scale = {
                        x = tonumber(data.scale and data.scale.x) or 1,
                        y = tonumber(data.scale and data.scale.y) or 1,
                        z = tonumber(data.scale and data.scale.z) or 1
                    },
                    Variant = tonumber(data.variant) or 1,
                    DisplayModel = data.displayModel
                }

                table.insert(placements, placement)
                nextId = nextId + 1
                savePlacements()
                syncPlacements()
            end

            RegisterCommand(pluginConfig.commands.cadDisplayMenu, function(source)
                local allowed, isAdmin = checkPermissions(source)
                if not allowed then
                    TriggerClientEvent("chat:addMessage", source,
                        {args = {"CAD Display", "You do not have permission to use this command."}})
                    return
                end
                TriggerClientEvent("SonoranCAD::caddisplay::OpenMenu", source, isAdmin)
            end, false)

            RegisterNetEvent("SonoranCAD::caddisplay::RequestPlacements", function()
                syncPlacements(source)
                syncOwners(source)
            end)

            RegisterNetEvent("SonoranCAD::caddisplay::SavePlacement", function(data)
                local src = source
                local allowed, isAdmin = checkPermissions(src)
                if not allowed or not isAdmin then
                    TriggerClientEvent("chat:addMessage", src,
                        {args = {"CAD Display", "You do not have permission to save placements."}})
                    return
                end
                upsertPlacement(data or {}, src)
            end)

            RegisterNetEvent("SonoranCAD::caddisplay::DeletePlacement", function(vehicleModel)
                local src = source
                local allowed, isAdmin = checkPermissions(src)
                if not allowed or not isAdmin then
                    TriggerClientEvent("chat:addMessage", src,
                        {args = {"CAD Display", "You do not have permission to delete placements."}})
                    return
                end
                local targetModel = string.upper(vehicleModel or "")
                local removed = false
                for i = #placements, 1, -1 do
                    if string.upper(placements[i].Vehicle) == targetModel then
                        table.remove(placements, i)
                        removed = true
                    end
                end
                if removed then
                    savePlacements()
                    syncPlacements()
                end
            end)

            RegisterNetEvent("SonoranCAD::caddisplay::ClaimDisplay", function(vehNet, claimedSeat)
                if not vehNet then
                    return
                end
                local src = source
                local veh = NetworkGetEntityFromNetworkId(vehNet)
                if veh == 0 or not DoesEntityExist(veh) then
                    TriggerClientEvent("chat:addMessage", src, {args = {"CAD Display", "Unable to identify this vehicle."}})
                    return
                end

                local seat = tonumber(claimedSeat)
                local owner = displayOwners[tostring(vehNet)]

                if owner == nil then
                    displayOwners[tostring(vehNet)] = src
                    syncOwners()
                    return
                end

                if owner == src then
                    return
                end

                -- Only driver (-1) or front passenger (0) can override an existing owner
                if seat == -1 or seat == 0 then
                    pendingRequests[vehNet] = {
                        requester = src,
                        owner = owner
                    }
                    TriggerClientEvent("SonoranCAD::caddisplay::ControlRequest", owner, {
                        vehNet = vehNet,
                        requester = src,
                        requesterName = GetPlayerName(src) or ("Player %s"):format(src)
                    })
                    TriggerClientEvent("chat:addMessage", src,
                        {args = {"CAD Display", "Control request sent to the current owner."}})
                    SetTimeout(10500, function()
                        if pendingRequests[vehNet] and pendingRequests[vehNet].requester == src then
                            pendingRequests[vehNet] = nil
                            TriggerClientEvent("SonoranCAD::caddisplay::ControlRequestExpired", owner, vehNet)
                            TriggerClientEvent("SonoranCAD::caddisplay::ControlRequestExpired", src, vehNet)
                        end
                    end)
                else
                    TriggerClientEvent("chat:addMessage", src,
                        {args = {"CAD Display", "Only the driver or front passenger can take control."}})
                end
            end)

            RegisterNetEvent("SonoranCAD::caddisplay::RespondToRequest", function(vehNet, requester, accepted)
                local src = source
                local req = pendingRequests[vehNet]
                if not req or req.owner ~= src or req.requester ~= requester then
                    return
                end
                pendingRequests[vehNet] = nil
                if not accepted then
                    TriggerClientEvent("chat:addMessage", requester,
                        {args = {"CAD Display", "Your control request was denied."}})
                    TriggerClientEvent("SonoranCAD::caddisplay::ControlRequestExpired", src, vehNet)
                    return
                end

                displayOwners[tostring(vehNet)] = requester
                syncOwners()
                TriggerClientEvent("chat:addMessage", requester,
                    {args = {"CAD Display", "You now have control of the CAD display."}})
                TriggerClientEvent("chat:addMessage", src,
                    {args = {"CAD Display", "You granted control of the CAD display."}})
            end)

            RegisterNetEvent("SonoranCAD::caddisplay::BroadcastCadScreenshot", function(vehNet, image)
                if not vehNet or not image or image == "" then
                    return
                end
                local netId = tonumber(vehNet)
                if not netId then
                    return
                end
                local owner = displayOwners[tostring(netId)]
                if owner ~= source then
                    return
                end
                TriggerClientEvent("SonoranCAD::caddisplay::UpdateDui", -1, {
                    type = "cad_image",
                    image = image
                })
            end)

            AddEventHandler("playerDropped", function()
                local changed = false
                for vehNet, owner in pairs(displayOwners) do
                    if owner == source then
                        displayOwners[vehNet] = nil
                        changed = true
                    end
                end
                if clearPendingForPlayer(source) then
                    changed = true
                end
                if changed then
                    syncOwners()
                end
            end)

            AddEventHandler("playerJoining", function(playerId)
                syncPlacements(playerId)
                syncOwners(playerId)
            end)
            loadPlacements()
            syncPlacements()
            syncOwners()
        end
    end)
end)
