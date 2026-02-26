--[[
    Sonaran CAD Plugins

    Plugin Name: locations
    Creator: SonoranCAD
    Description: Implements location updating for players
]]
CreateThread(function() Config.LoadPlugin("locations", function(pluginConfig)

    if pluginConfig.enabled then

        local currentLocation = ''
        local lastLocation = 'none'
        local lastSentTime = nil
        local lastCoords = { x = 0, y = 0, z = 0, w = 0 }
        local lastLightsOn = nil

        local function resolveVehicleType(ped, veh)
            if not ped then
                return "foot"
            end
            if not IsPedInAnyVehicle(ped, false) then
                return "foot"
            end
            if not veh or veh == 0 then
                return "foot"
            end
            local vehClass = GetVehicleClass(veh)
            if vehClass == 15 then
                return "helicoper"
            end
            if vehClass == 16 then
                return "plane"
            end
            if vehClass == 13 then
                return "bicycle"
            end
            if vehClass == 8 then
                return "motorcycle"
            end
            if vehClass == 14 then
                return "boat"
            end
            if vehClass == 18 then
                local modelName = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
                modelName = string.upper(modelName or "")
                if string.find(modelName, "FIRE", 1, true) then
                    return "fire"
                end
                if string.find(modelName, "AMBUL", 1, true) or string.find(modelName, "EMS", 1, true) then
                    return "ems"
                end
                return "police"
            end
            return "car"
        end

        local function sendLocation()
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local heading = GetEntityHeading(ped)
            local pos4 = vector4(pos.x, pos.y, pos.z, heading)
            local veh = GetVehiclePedIsIn(ped, false)
            local var1, var2 = GetStreetNameAtCoord(pos.x, pos.y, pos.z, Citizen.ResultAsInteger(), Citizen.ResultAsInteger())
            local postal = nil
            if isPluginLoaded("postals") then
                postal = getNearestPostal()
            else
                pluginConfig.prefixPostal = false
            end
            local l1 = GetStreetNameFromHashKey(var1)
            local l2 = GetStreetNameFromHashKey(var2)
            if l2 ~= '' then
                currentLocation = l1 .. ' / ' .. l2
            else
                currentLocation = l1
            end
            local lightsOn = veh ~= 0 and IsVehicleSirenOn(veh) == 1
            if (bodyCamOn or currentLocation ~= lastLocation or vector3(pos.x, pos.y, pos.z) ~= vector3(lastCoords.x, lastCoords.y, lastCoords.z) or lightsOn ~= lastLightsOn)  then
                -- Location changed, continue
                local toSend = currentLocation
                local vehicleType = resolveVehicleType(ped, veh)
                if pluginConfig.prefixPostal and postal ~= nil then
                    toSend = "["..tostring(postal).."] "..currentLocation
                elseif postal == nil and pluginConfig.prefixPostal == true then
                    debugLog("Unable to send postal because I got a null response from getNearestPostal()?!")
                end
                if bodyCamOn then
                    TriggerServerEvent('SonoranCAD::locations:SendLocation', toSend, pos4, vehicleType, lightsOn, BodycamPeerId)
                else
                    TriggerServerEvent('SonoranCAD::locations:SendLocation', toSend, pos4, vehicleType, lightsOn)
                end
                lastCoords = pos4
                lastLightsOn = lightsOn
                debugLog(("Locations different, sending. (%s ~= %s) SENT: %s (POS: %s)"):format(currentLocation, lastLocation, toSend, json.encode(lastCoords)))
                lastSentTime = GetGameTimer()
                lastLocation = currentLocation
            end
        end

        Citizen.CreateThread(function()
            -- Wait for plugins to settle
            Wait(5000)
            while true do
                while not NetworkIsPlayerActive(PlayerId()) do
                    Wait(10)
                end
                sendLocation()
                -- Wait (1000ms) before checking for an updated unit location
                if not pluginConfig.clientCheckTime then
                    pluginConfig.clientCheckTime = 250
                end
                Citizen.Wait(pluginConfig.clientCheckTime)
            end
        end)

        Citizen.CreateThread(function()
            while lastSentTime == nil do
                while not NetworkIsPlayerActive(PlayerId()) do
                    Wait(10)
                end
                Wait(15000)
                if lastSentTime == nil then
                    TriggerServerEvent("SonoranCAD::locations:ErrorDetection", true)
                    warnLog("Warning: No location data has been sent yet. Check for errors.")
                end
                Wait(30000)
            end
        end)

    end

    end) end)
