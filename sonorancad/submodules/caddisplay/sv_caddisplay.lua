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
            local worldPlacements = {}
            local nextWorldId = 1
            local worldPlacementFile = "submodules/caddisplay/config/world_placements.json"
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

            local function isWorldDisplayEnabled()
                return not (pluginConfig.worldDisplays and pluginConfig.worldDisplays.enabled == false)
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

            local function checkWorldPlacementPermission(src)
                if not pluginConfig.commands.restricted then
                    return true
                end

                if pluginConfig.permissionMode == "ace" then
                    local perm = pluginConfig.acePerms and pluginConfig.acePerms.aceWorldDisplayAdmin
                    if perm == nil or perm == "" then
                        perm = pluginConfig.acePerms and pluginConfig.acePerms.aceObjectAdminUseMenu
                    end
                    if perm == nil or perm == "" then
                        return false
                    end
                    return IsPlayerAceAllowed(src, perm)
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
                        return false
                    end
                    return isJobAllowed(job, pluginConfig.framework.adminJobNames, false)
                elseif pluginConfig.permissionMode == "custom" and pluginConfig.custom and
                    pluginConfig.custom.permissionCheck then
                    local ok = pluginConfig.custom.permissionCheck(src, 1)
                    return ok == true
                end

                return true
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

            local function normalizeWorldPlacement(entry)
                local idNum = tonumber(entry.ID or entry.id)
                if idNum == nil then
                    idNum = nextWorldId
                end
                local label = entry.Label or entry.label or entry.name or ("Station Display " .. tostring(idNum))
                local pos = entry.Position or entry.position or {}
                local rot = entry.Rotation or entry.rotation or {}
                local scale = entry.Scale or entry.scale or {}
                return {
                    ID = tostring(idNum),
                    Label = label,
                    Position = {
                        x = tonumber(pos.x) or 0,
                        y = tonumber(pos.y) or 0,
                        z = tonumber(pos.z) or 0
                    },
                    Rotation = {
                        pitch = tonumber(rot.pitch or rot.x) or 0,
                        roll = tonumber(rot.roll or rot.y) or 0,
                        yaw = tonumber(rot.yaw or rot.z) or 0
                    },
                    Scale = {
                        x = tonumber(scale.x) or 1,
                        y = tonumber(scale.y) or 1,
                        z = tonumber(scale.z) or 1
                    },
                    DisplayModel = entry.DisplayModel or entry.displayModel
                }
            end

            local function saveWorldPlacements()
                SaveResourceFile(GetCurrentResourceName(), worldPlacementFile, json.encode(worldPlacements), -1)
            end

            local function loadWorldPlacements()
                if not isWorldDisplayEnabled() then
                    worldPlacements = {}
                    return
                end

                local stored = LoadResourceFile(GetCurrentResourceName(), worldPlacementFile)
                if stored then
                    local parsed = json.decode(stored)
                    if parsed and type(parsed) == "table" then
                        worldPlacements = {}
                        nextWorldId = 1
                        for _, entry in ipairs(parsed) do
                            local normalized = normalizeWorldPlacement(entry or {})
                            table.insert(worldPlacements, normalized)
                            local idNum = tonumber(normalized.ID)
                            if idNum ~= nil and idNum >= nextWorldId then
                                nextWorldId = idNum + 1
                            end
                        end
                        return
                    end
                    warnLog("[caddisplay] Failed to parse world placement file; using config defaults.")
                end

                local defaults = pluginConfig.worldDisplays and pluginConfig.worldDisplays.defaultPlacements or {}
                worldPlacements = {}
                nextWorldId = 1
                for _, entry in ipairs(defaults or {}) do
                    local normalized = normalizeWorldPlacement(entry or {})
                    table.insert(worldPlacements, normalized)
                    local idNum = tonumber(normalized.ID)
                    if idNum ~= nil and idNum >= nextWorldId then
                        nextWorldId = idNum + 1
                    else
                        nextWorldId = nextWorldId + 1
                    end
                end

                if #worldPlacements > 0 then
                    infoLog("[caddisplay] No world_placements.json found, seeding from config defaults.")
                    saveWorldPlacements()
                end
            end

            local function syncPlacements(target)
                TriggerClientEvent("SonoranCAD::caddisplay::SyncPlacements", target or -1, placements)
            end

            local function syncWorldPlacements(target)
                local payload = worldPlacements
                if not isWorldDisplayEnabled() then
                    payload = {}
                end
                TriggerClientEvent("SonoranCAD::caddisplay::SyncWorldPlacements", target or -1, payload)
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

            local function upsertWorldPlacement(data, src)
                if not isWorldDisplayEnabled() then
                    return
                end
                local targetId = tonumber(data.id)
                local label = data.label or data.Label
                local pos = data.position or data.Position or {}
                local rot = data.rotation or data.Rotation or {}
                local scale = data.scale or data.Scale or {}
                local model = data.displayModel or data.DisplayModel

                local placement = {
                    ID = tostring(targetId or nextWorldId),
                    Label = label or ("Station Display " .. tostring(targetId or nextWorldId)),
                    Position = {
                        x = tonumber(pos.x) or 0,
                        y = tonumber(pos.y) or 0,
                        z = tonumber(pos.z) or 0
                    },
                    Rotation = {
                        pitch = tonumber(rot.pitch or rot.x) or 0,
                        roll = tonumber(rot.roll or rot.y) or 0,
                        yaw = tonumber(rot.yaw or rot.z) or 0
                    },
                    Scale = {
                        x = tonumber(scale.x) or 1,
                        y = tonumber(scale.y) or 1,
                        z = tonumber(scale.z) or 1
                    },
                    DisplayModel = model
                }

                local replaced = false
                if targetId ~= nil then
                    for i = #worldPlacements, 1, -1 do
                        if tonumber(worldPlacements[i].ID) == targetId then
                            worldPlacements[i] = placement
                            replaced = true
                            break
                        end
                    end
                end

                if not replaced then
                    table.insert(worldPlacements, placement)
                    nextWorldId = nextWorldId + 1
                end

                saveWorldPlacements()
                syncWorldPlacements()
            end

            RegisterCommand(pluginConfig.commands.cadDisplayMenu, function(source)
                local allowed, isAdmin = checkPermissions(source)
                if not allowed then
                    TriggerClientEvent("chat:addMessage", source,
                        {args = {"CAD Display", "You do not have permission to use this command."}})
                    return
                end
                local worldAdmin = checkWorldPlacementPermission(source)
                TriggerClientEvent("SonoranCAD::caddisplay::OpenMenu", source, isAdmin, worldAdmin)
            end, false)

            RegisterNetEvent("SonoranCAD::caddisplay::RequestPlacements", function()
                syncPlacements(source)
                syncWorldPlacements(source)
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

            RegisterNetEvent("SonoranCAD::caddisplay::SaveWorldPlacement", function(data)
                local src = source
                if not checkWorldPlacementPermission(src) then
                    TriggerClientEvent("chat:addMessage", src,
                        {args = {"CAD Display", "You do not have permission to save station displays."}})
                    return
                end
                upsertWorldPlacement(data or {}, src)
            end)

            RegisterNetEvent("SonoranCAD::caddisplay::DeleteWorldPlacement", function(displayId)
                local src = source
                if not checkWorldPlacementPermission(src) then
                    TriggerClientEvent("chat:addMessage", src,
                        {args = {"CAD Display", "You do not have permission to delete station displays."}})
                    return
                end
                local targetId = tonumber(displayId)
                if targetId == nil then
                    return
                end
                local removed = false
                for i = #worldPlacements, 1, -1 do
                    if tonumber(worldPlacements[i].ID) == targetId then
                        table.remove(worldPlacements, i)
                        removed = true
                    end
                end
                if removed then
                    local key = ("world:%s"):format(targetId)
                    if displayOwners[key] ~= nil then
                        displayOwners[key] = nil
                        syncOwners()
                    end
                    saveWorldPlacements()
                    syncWorldPlacements()
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

            RegisterNetEvent("SonoranCAD::caddisplay::ClaimWorldDisplay", function(displayId)
                if not isWorldDisplayEnabled() then
                    return
                end
                local targetId = tonumber(displayId)
                if targetId == nil then
                    return
                end
                local key = ("world:%s"):format(targetId)
                local src = source
                local owner = displayOwners[key]

                if owner == nil then
                    displayOwners[key] = src
                    syncOwners()
                    return
                end

                if owner == src then
                    return
                end

                pendingRequests[key] = {
                    requester = src,
                    owner = owner
                }
                TriggerClientEvent("SonoranCAD::caddisplay::ControlRequest", owner, {
                    vehNet = key,
                    requester = src,
                    requesterName = GetPlayerName(src) or ("Player %s"):format(src)
                })
                TriggerClientEvent("chat:addMessage", src,
                    {args = {"CAD Display", "Control request sent to the current owner."}})
                SetTimeout(10500, function()
                    if pendingRequests[key] and pendingRequests[key].requester == src then
                        pendingRequests[key] = nil
                        TriggerClientEvent("SonoranCAD::caddisplay::ControlRequestExpired", owner, key)
                        TriggerClientEvent("SonoranCAD::caddisplay::ControlRequestExpired", src, key)
                    end
                end)
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
                local veh = NetworkGetEntityFromNetworkId(netId)
                if veh == 0 or not DoesEntityExist(veh) then
                    return
                end

                local vehCoords = GetEntityCoords(veh)
                local updateRadius = 15.0
                local updateRadiusSq = updateRadius * updateRadius
                for _, playerId in ipairs(GetPlayers()) do
                    local ped = GetPlayerPed(playerId)
                    if ped ~= 0 and DoesEntityExist(ped) then
                        local pedCoords = GetEntityCoords(ped)
                        if #(pedCoords - vehCoords) <= updateRadius then
                            TriggerLatentClientEvent("SonoranCAD::caddisplay::UpdateDui", playerId, 0, {
                                type = "cad_image",
                                image = image
                            })
                        end
                    end
                end
            end)

            RegisterNetEvent("SonoranCAD::caddisplay::BroadcastWorldCadScreenshot", function(displayId, image)
                if not displayId or not image or image == "" then
                    return
                end
                local targetId = tonumber(displayId)
                if targetId == nil then
                    return
                end
                local key = ("world:%s"):format(targetId)
                local owner = displayOwners[key]
                if owner ~= source then
                    return
                end

                local placement = nil
                for _, entry in ipairs(worldPlacements) do
                    if tonumber(entry.ID) == targetId then
                        placement = entry
                        break
                    end
                end
                if placement == nil then
                    return
                end

                local pos = placement.Position or {}
                local displayCoords = vector3(tonumber(pos.x) or 0, tonumber(pos.y) or 0, tonumber(pos.z) or 0)
                local updateRadius = 15.0
                for _, playerId in ipairs(GetPlayers()) do
                    local ped = GetPlayerPed(playerId)
                    if ped ~= 0 and DoesEntityExist(ped) then
                        local pedCoords = GetEntityCoords(ped)
                        if #(pedCoords - displayCoords) <= updateRadius then
                            TriggerLatentClientEvent("SonoranCAD::caddisplay::UpdateDui", playerId, 0, {
                                type = "cad_image",
                                image = image
                            })
                        end
                    end
                end
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
                syncWorldPlacements(playerId)
                syncOwners(playerId)
            end)
            loadPlacements()
            loadWorldPlacements()
            syncPlacements()
            syncWorldPlacements()
            syncOwners()
        end
    end)
end)
