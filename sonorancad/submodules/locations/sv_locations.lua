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
        local PendingQueue = {}
        local LastSent = {}
        local MinimumSendInterval = 200 -- WS hub enforces a 200ms minimum.
        local SendIntervalMs = 250
        local MaxBatchSize = 25
        local CoordinateThreshold = 2.0
        local HeadingThreshold = 10.0
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

        local function headingDelta(a, b)
            if a == nil or b == nil then
                return 999
            end
            local diff = (a - b + 180) % 360
            diff = diff - 180
            return math.abs(diff)
        end

        local function coordsDistance(a, b)
            if not a or not b then
                return 999
            end
            local dx = (a.x or 0) - (b.x or 0)
            local dy = (a.y or 0) - (b.y or 0)
            local dz = (a.z or 0) - (b.z or 0)
            return math.sqrt(dx * dx + dy * dy + dz * dz)
        end

        local function findPendingIndex(apiId)
            if apiId == nil then
                return nil
            end
            for i, entry in ipairs(PendingQueue) do
                if entry.apiId == apiId then
                    return i
                end
            end
            return nil
        end

        local function enqueueUpdate(payload)
            local existingIndex = findPendingIndex(payload.apiId)
            if existingIndex ~= nil then
                PendingQueue[existingIndex] = payload
            else
                table.insert(PendingQueue, payload)
            end
        end

        -- Main api POST function
        local function SendLocations()
            while true do
                local sendInterval = SendIntervalMs
                if sendInterval < MinimumSendInterval then
                    sendInterval = MinimumSendInterval
                end
                if #PendingQueue > 0 then
                    local batch = {}
                    local batchSize = math.min(MaxBatchSize, #PendingQueue)
                    for i = 1, batchSize do
                        table.insert(batch, PendingQueue[i])
                    end
                    for i = batchSize, 1, -1 do
                        table.remove(PendingQueue, i)
                    end
                    exports['sonorancad']:sendUnitLocations(batch)
                    for _, entry in ipairs(batch) do
                        if entry and entry.apiId then
                            LastSent[entry.apiId] = {
                                coordinates = entry.coordinates,
                                heading = entry.coordinates and entry.coordinates.w or nil,
                                peerId = entry.peerId
                            }
                        end
                    end
                end
                Wait(sendInterval)
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
            local lastSent = LastSent[identifier]
            local lastCoords = lastSent and lastSent.coordinates or nil
            local lastHeading = lastSent and lastSent.heading or nil
            local lastPeerId = lastSent and lastSent.peerId or nil
            local distance = coordsDistance(position, lastCoords)
            local headingDiff = headingDelta(position and position.w or nil, lastHeading)
            local currentPeerId = (bodycamPeerId and bodycamPeerId ~= "") and bodycamPeerId or nil
            local bodycamChanged = currentPeerId ~= lastPeerId
            if distance <= CoordinateThreshold and headingDiff <= HeadingThreshold and not bodycamChanged then
                return
            end

            local payload = {
                ['apiId'] = identifier,
                ['location'] = currentLocation,
                ['coordinates'] = position,
                ['vehicle'] = vehiclePayload
            }
            if bodycamPeerId then
                payload['proxyUrl'] = Config.proxyUrl
                if bodycamPeerId ~= "" then
                    payload['peerId'] = bodycamPeerId
                end
            end
            LocationCache[source] = payload
            enqueueUpdate(payload)
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
