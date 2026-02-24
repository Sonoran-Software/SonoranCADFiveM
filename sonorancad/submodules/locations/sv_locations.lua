--[[
    Sonaran CAD Plugins

    Plugin Name: locations
    Creator: SonoranCAD
    Description: Implements location updating for players
]]
CreateThread(function() Config.LoadPlugin("locations", function(pluginConfig)

    if pluginConfig.enabled then
        -- Pending location updates array
        LocationCache = {}
        local LastSend = 0
        local vehicleModelConfig = {}
        local vehicleModelConfigPath = "/configuration/livemap_vehicle_models.json"

        local function loadVehicleModelConfig()
            local raw = LoadResourceFile(GetCurrentResourceName(), vehicleModelConfigPath)
            if not raw or raw == "" then
                warnLog(("Livemap vehicle model config missing: %s"):format(vehicleModelConfigPath))
                vehicleModelConfig = {}
                return
            end
            local ok, data = pcall(json.decode, raw)
            if not ok or type(data) ~= "table" then
                warnLog(("Livemap vehicle model config invalid: %s"):format(vehicleModelConfigPath))
                vehicleModelConfig = {}
                return
            end
            vehicleModelConfig = data
        end

        local function cloneTable(src)
            if type(src) ~= "table" then
                return nil
            end
            local out = {}
            for k, v in pairs(src) do
                out[k] = v
            end
            return out
        end

        local function buildVehiclePayload(vehicleType, lightsOn)
            local entry = vehicleModelConfig[vehicleType]
            local payload = cloneTable(entry)
            if payload == nil then
                payload = { type = vehicleType }
            end
            if lightsOn ~= nil then
                payload.lights = lightsOn == true
            end
            return payload
        end

        -- Main api POST function
        local function SendLocations()
            while true do
                local cache = {}
                for k, v in pairs(LocationCache) do
                    if v.isUpdated ~= nil then
                        v.isUpdated = nil
                        table.insert(cache, v)
                    end
                end
                if #cache > 0 then
                    if GetGameTimer() > LastSend+5000 then
                        performApiRequest(cache, 'UNIT_LOCATION', function() end)
                        LastSend = GetGameTimer()
                    else
                        debugLog(("UNIT_LOCATION: Attempted to send data too soon. %s !> %s"):format(GetGameTimer(), LastSend+5000))
                    end
                end
                Wait(Config.postTime+500)
            end
        end

        function findPlayerLocation(playerSrc)
            if LocationCache[playerSrc] ~= nil then
                return LocationCache[playerSrc].location
            end
            return nil
        end

        -- Main update thread sending api location update POST requests per the postTime interval
        Citizen.CreateThread(function()
            Wait(1)
            SendLocations()
        end)

        loadVehicleModelConfig()

        -- Event from client when location changes occur
        RegisterServerEvent('SonoranCAD::locations:SendLocation')
        AddEventHandler('SonoranCAD::locations:SendLocation', function(currentLocation, position, vehicleType, lightsOn, bodycamPeerId)
            local source = source
            local identifier = GetIdentifiers(source)[Config.primaryIdentifier]
            if identifier == nil then
                debugLog(("user %s has no identifier for %s, skipped."):format(source, Config.primaryIdentifier))
                return
            end
            local vehiclePayload = buildVehiclePayload(vehicleType, lightsOn)
            if bodycamPeerId  then
                local payload = {['apiId'] = identifier, ['location'] = currentLocation, ['coordinates'] = position, ['vehicle'] = vehiclePayload, ['isUpdated'] = true, ['proxyUrl'] = Config.proxyUrl}
                if bodycamPeerId and bodycamPeerId ~= "" then
                    payload['peerId'] = bodycamPeerId
                end
                LocationCache[source] = payload
            else
                LocationCache[source] = {['apiId'] = identifier, ['location'] = currentLocation, ['coordinates'] = position, ['vehicle'] = vehiclePayload, ['isUpdated'] = true}
            end
        end)

        AddEventHandler("playerDropped", function()
            local source = source
            LocationCache[source] = nil
        end)

        RegisterNetEvent("SonoranCAD::locations:ErrorDetection")
        AddEventHandler("SonoranCAD::locations:ErrorDetection", function(isInitial)
            if isInitial then
                errorLog(("Player %s reported an error sending initial location data. Check client logs for errors. Did you set up the postals plugin correctly?"):format(source))
            else
                warnLog(("Player %s reported an error sending location data. Check client logs for errors."):format(source))
            end
        end)

    end
    end) end)
