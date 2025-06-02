--[[
    Sonaran CAD Plugins

    Plugin Name: ersintegration
    Creator: Sonoran Software
    Description: Integrates Knight ERS callouts to SonoranCAD
]]
local pluginConfig = Config.GetPluginConfig("ersintegration")
local postalConfig = Config.GetPluginConfig("postals")

if pluginConfig.enabled then
    function startErs()
        debugLog("Starting ERS Integration...")
        RegisterNetEvent('SonoranCAD::ErsIntegration::CalloutOffered')
        RegisterNetEvent('SonoranCAD::ErsIntegration::CalloutAccepted')
        RegisterNetEvent('SonoranCAD::ErsIntegration::BuildChars')
        RegisterNetEvent('SonoranCAD::ErsIntegration::BuildVehs')
        registerApiType('SET_AVAILABLE_CALLOUTS', 'emergency')
        registerApiType('NEW_CHARACTER', 'civilian')
        local processedCalloutOffered = {}
        local processedCalloutAccepted = {}
        local processedPedData = {}
        local processedVehData = {}
        local ersCallouts = {}

        --[[
        @function escapeSpaces
        @param string str
        @return string
        Used to escape spaces in strings by replacing them with underscores
        ]]
        local function escapeSpaces(str)
            return str:gsub(" ", "_")
        end
        --[[
        @function generateUniqueCalloutKey
        @param table callout
        @return string
        Used to generate the unique key for a callout creation for tracking
        ]]
        local function generateUniqueCalloutKey(callout)
            return string.format(
                "%s_%s_%.2f_%.2f_%.2f",
                callout.calloutId,
                escapeSpaces(callout.StreetName),
                callout.Coordinates.x,
                callout.Coordinates.y,
                callout.Coordinates.z
            )
        end
        --[[
        @function generateUniquePedDataKey
        @param table pedData
        @return string
        Used to generate the unique key for a ped data record creation for tracking
        ]]
        local function generateUniquePedDataKey(pedData)
            return string.format(
                "%s_%s_%s_%s",
                pedData.uniqueId,
                pedData.FirstName,
                pedData.LastName,
                escapeSpaces(pedData.Address)
            )
        end

        local function generateUniqueVehDataKey(vehData)
            return string.format(
                "%s_%s_%s_%s",
                escapeSpaces(vehData.license_plate),
                vehData.model,
                vehData.color,
                vehData.build_year
            )
        end
        --[[
        @function generateCallNote
        @param table callout
        @return string
        Used to generate the call note for a callout
        ]]
        function generateCallNote(callout)
            -- Start with basic callout information
            local note = ''

            -- Append potential weapons information
            if callout.PedWeaponData and #callout.PedWeaponData > 0 then
                note = note .. "Potential weapons: " .. table.concat(callout.PedWeaponData, ", ") .. ". "
            else
                note = note .. "No weapons reported. "
            end

            -- Determine the required units from the callout
            local requiredUnits = {}
            local units = callout.CalloutUnitsRequired or {}
            if units.policeRequired then table.insert(requiredUnits, "Police") end
            if units.ambulanceRequired then table.insert(requiredUnits, "Ambulance") end
            if units.fireRequired then table.insert(requiredUnits, "Fire") end
            if units.towRequired then table.insert(requiredUnits, "Tow") end

            if #requiredUnits > 0 then
                note = note .. "Required units: " .. table.concat(requiredUnits, ", ") .. "."
            else
                note = note .. "No additional units required."
            end

            return note
        end

        --[[
            @funciton generateReplaceValues
            @param table data
            @param table config
            @return table
            Generates the replacement values for a record creation based on the passed data and configuration
        ]]
        function generateReplaceValues(data, config)
            local replaceValues = {}
            for cadKey, source in pairs(config) do
                if type(source) == "function" then
                    replaceValues[cadKey] = source(data)
                elseif type(source) == "string" then
                    replaceValues[cadKey] = data[source]
                else
                    error("Invalid mapping configuration for key: " .. tostring(cadKey))
                end
            end
            return replaceValues
        end

        function generateLicenseReplaceValues(pedData, valueMap, extraContext)
            local result = {}
            for cadKey, ersKeyOrFunc in pairs(valueMap) do
                if type(ersKeyOrFunc) == "string" then
                    result[cadKey] = pedData[ersKeyOrFunc]
                elseif type(ersKeyOrFunc) == "function" then
                    result[cadKey] = ersKeyOrFunc(pedData, extraContext)
                end
            end
            return result
        end

        function mapFlagsToBoloOptions(flags)
            local boloFlags = {}

            -- Define what original flags count toward each BOLO category
            local mapping = {
                ["Armed"] = {
                    "armed_and_dangerous"
                },
                ["Violent"] = {
                    "assault",
                    "terrorism",
                    "homicide",
                    "kidnapping",
                    "gang_affiliation",
                    "wanted_person",
                    "active_warrant",
                    "sex_offense",
                    "burglary"
                },
                ["Mentally Ill"] = {
                    "mental_health_issues"
                }
            }

            -- Loop through the mapping and set BOLO categories if any matching flag is true
            for boloType, flagList in pairs(mapping) do
                for _, flagKey in ipairs(flagList) do
                    if flags[flagKey] then
                        if not boloFlags[boloType] then
                            table.insert(boloFlags, boloType)
                        end
                        break -- Stop after first true flag in this category
                    end
                end
            end

            return boloFlags
        end
        --[[
            911 CALL CREATION
        ]]
        if pluginConfig.create911Call then
            AddEventHandler('SonoranCAD::ErsIntegration::CalloutOffered', function(calloutData)
                local uniqueKey = generateUniqueCalloutKey(calloutData)
                debugLog('Generated unqiue key for callout: '.. uniqueKey)
                if processedCalloutOffered[uniqueKey] then
                    debugLog("Callout " .. calloutData.calloutId .. " already processed. Skipping 911 call.")
                else
                    local caller = calloutData.FirstName .. " " .. calloutData.LastName
                    local location = calloutData.StreetName
                    local description = calloutData.Description
                    local postal = ''
                    if calloutData.Postal == 'Unknown postal' then
                        if postalConfig.enabled then
                            postal = exports[postalConfig.nearestPostalResourceName]:getPostalServer({calloutData.Coordinates.x, calloutData.Coordinates.y}).code
                        else
                            postal = "Unknown postal"
                        end
                    else
                        postal = calloutData.Postal
                    end
                    local plate = ""
                    if calloutData.VehiclePlate ~= nil then
                        plate = calloutData.VehiclePlate
                    end
                    local data = {
                        ['serverId'] = Config.serverId,
                        ['isEmergency'] = true,
                        ['caller'] = caller,
                        ['location'] = location,
                        ['description'] = description,
                        ['metaData'] = {
                            ['x'] = calloutData.Coordinates.x,
                            ['y'] = calloutData.Coordinates.y,
                            ['plate'] = plate,
                            ['postal'] = postal
                        }
                    }
                    performApiRequest({data}, 'CALL_911', function(response)
                        local callId = string.match(response, "ID%s+(%d+)")
                        if callId then
                            processedCalloutOffered[uniqueKey] = callId
                            debugLog("Saved call ID: " .. processedCalloutOffered[uniqueKey])
                        else
                            debugLog("Could not extract call ID from response.")
                        end
                    end)
                end
            end)
        end
        --[[
            EMERGENCY CALL CREATION
        ]]
        if pluginConfig.createEmergencyCall then
            AddEventHandler('SonoranCAD::ErsIntegration::CalloutAccepted', function(calloutData)
                local uniqueKey = generateUniqueCalloutKey(calloutData)
                if processedCalloutAccepted[uniqueKey] then
                    debugLog("Callout " .. calloutData.calloutId .. " already processed. Skipping emergency call... adding new units")
                    if pluginConfig.autoAddCall then
                        local callId = processedCalloutAccepted[uniqueKey]
                        local unit = GetUnitByPlayerId(source)
                        if unit == nil then
                            debugLog("Unit not found for player ID: " .. source)
                            return
                        end
                        local unitId = unit.data.apiIds[1]
                        local data = {
                            ['serverId'] = Config.serverId,
                            ['callId'] = callId,
                            ['units'] = {unitId}
                        }
                        performApiRequest({data}, 'ATTACH_UNIT', function(response)
                            debugLog("Added unit to call: " .. response)
                        end)
                    end
                else
                    debugLog("Processing callout " .. calloutData.calloutId .. " for emergency call.")
                    local callCode = pluginConfig.callCodes[calloutData.CalloutName] or ""
                    local unit = GetUnitByPlayerId(source)
                    local unitId = ""
                    if unit == nil then
                        debugLog("Unit not found for player ID: " .. source)
                    else
                        unitId = unit.data.apiIds[1]
                    end
                    local postal = ''
                    if calloutData.Postal == 'Unknown postal' then
                        if postalConfig.enabled then
                            postal = exports[postalConfig.nearestPostalResourceName]:getPostalServer({calloutData.Coordinates.x, calloutData.Coordinates.y}).code
                        else
                            postal = "Unknown postal"
                        end
                    else
                        postal = calloutData.Postal
                    end
                    local data = {
                        ['serverId'] = Config.serverId,
                        ['origin'] = 0,
                        ['status'] = 1,
                        ['priority'] = pluginConfig.callPriority,
                        ['block'] = postal,
                        ['postal'] = postal,
                        ['address'] = calloutData.StreetName,
                        ['title'] = calloutData.CalloutName,
                        ['code'] = callCode,
                        ['description'] = calloutData.Description,
                        ['units'] = {unitId},
                        ['notes'] = {}, -- required
                        ['metaData'] = {
                            ['x'] = calloutData.Coordinates.x,
                            ['y'] = calloutData.Coordinates.y
                        }
                    }
                    registerApiType("NEW_DISPATCH", "emergency")
                    performApiRequest({data}, 'NEW_DISPATCH', function(response)
                        local callId = response:match("ID: {?(%w+)}?")
                        if callId then
                            -- Save the callId in the processedCalloutOffered table using the unique key
                            processedCalloutAccepted[uniqueKey] = callId
                            if processedCalloutOffered[uniqueKey] ~= nil then
                                local payload = { serverId = Config.serverId, callId = processedCalloutOffered[uniqueKey]}
                                performApiRequest({payload}, "REMOVE_911", function(resp)
                                    debugLog("Remove status: "..tostring(resp))
                                end)
                            end
                            debugLog("Call ID " .. callId .. " saved for unique key: " .. uniqueKey)
                        else
                            debugLog("Failed to extract callId from response: " .. response)
                        end
                    end)
                end
            end)
        end
        --[[
            CALLOUT, PED AND VEHICLE DATA CREATION
        ]]
        AddEventHandler('SonoranCAD::ErsIntegration::BuildChars', function(pedData)
            local uniqueKey = generateUniquePedDataKey(pedData)
            if processedPedData[uniqueKey] then
                debugLog("Ped " .. pedData.FirstName .. " " .. pedData.LastName .. " already processed.")
                return
            end
            -- CIVILIAN RECORD
            local data = {
                ['user'] = '00000000-0000-0000-0000-000000000000',
                ['useDictionary'] = true,
                ['recordTypeId'] = pluginConfig.customRecords.civilianRecordID,
                ['replaceValues'] = {}
            }
            data.replaceValues = generateReplaceValues(pedData, pluginConfig.customRecords.civilianValues)
            performApiRequest({data}, 'NEW_CHARACTER', function(response)
                local success, response = pcall(json.decode, response)
                if success and type(response) == "table" and response.id ~= nil then
                    local recordId = response.id
                    if recordId then
                        -- Save the recordId in the processedPedData table using the unique key
                        processedPedData[uniqueKey] = recordId
                        debugLog("Record ID " .. recordId .. " saved for unique key: " .. uniqueKey)
                    else
                        debugLog("Failed to extract recordId from response: " .. json.encode(response))
                    end
                else
                    warnLog("Invalid or missing 'id' in response")
                end
            end)
            -- LICENSE RECORD
            for _, v in pairs (pluginConfig.customRecords.licenseTypeConfigs) do
                if pedData[v.license] then
                    local licenseData = {
                        ['user'] = '00000000-0000-0000-0000-000000000000',
                        ['useDictionary'] = true,
                        ['recordTypeId'] = pluginConfig.customRecords.licenseRecordId
                    }
                    licenseData.replaceValues = generateLicenseReplaceValues(pedData, pluginConfig.customRecords.licenseRecordValues, v)
                    licenseData.replaceValues[pluginConfig.customRecords.licenseTypeField] = v.type
                    performApiRequest({licenseData}, 'NEW_RECORD', function(_)
                    end)
                end
            end
            -- WARRANT RECORD
            local hasWarrant = false
            for _, flag in pairs(pedData.FlagsOrMarkers) do
                if flag then
                    hasWarrant = true
                    break
                end
            end
            if hasWarrant then
                local boloData = {
                    ['user'] = '00000000-0000-0000-0000-000000000000',
                    ['useDictionary'] = true,
                    ['recordTypeId'] = pluginConfig.customRecords.warrantRecordID,
                    ['replaceValues'] = {}
                }
                local warrantTypes = mapFlagsToBoloOptions(pedData.FlagsOrMarkers)
                local pedReplaceData = generateReplaceValues(pedData, pluginConfig.customRecords.civilianValues)
                for k, v in pairs(pedReplaceData) do
                    boloData.replaceValues[k] = v
                end
                boloData.replaceValues[pluginConfig.customRecords.warrantDescription] = pedData.FlagsOrMarkers.flag_description or ""
                boloData.replaceValues[pluginConfig.customRecords.warrantFlags] = json.encode(warrantTypes)
                performApiRequest({boloData}, 'NEW_RECORD', function(res)
                end)
            end
        end)
        AddEventHandler('SonoranCAD::ErsIntegration::BuildVehs', function(vehData)
            local uniqueKey = generateUniqueVehDataKey(vehData)
            if processedVehData[uniqueKey] then
                debugLog("Vehicle " .. vehData.model .. " " .. vehData.license_plate .. " already processed.")
                return
            end
            local data = {
                ['user'] = '00000000-0000-0000-0000-000000000000',
                ['useDictionary'] = true,
                ['recordTypeId'] = pluginConfig.customRecords.vehicleRegistrationRecordID,
            }
            data.replaceValues = generateReplaceValues(vehData, pluginConfig.customRecords.vehicleRegistrationValues)
            performApiRequest({data}, 'NEW_RECORD', function(response)
                local success, response = pcall(json.decode, response)
                if success and type(response) == "table" and response.id ~= nil then
                    local recordId = response.id
                    if recordId then
                        -- Save the recordId in the processedPedData table using the unique key
                        processedVehData[uniqueKey] = recordId
                        debugLog("Record ID " .. recordId .. " saved for unique key: " .. uniqueKey)
                    else
                        debugLog("Failed to extract recordId from response: " .. json.encode(response))
                    end
                else
                    warnLog("Invalid or missing 'id' in response")
                end
            end)
            if vehData.bolo then
                local boloData = {
                    ['user'] = '00000000-0000-0000-0000-000000000000',
                    ['useDictionary'] = true,
                    ['recordTypeId'] = pluginConfig.customRecords.boloRecordID,
                    ['replaceValues'] = {}
                }
                boloData.replaceValues = generateReplaceValues(vehData, pluginConfig.customRecords.boloRecordValues)
                local vehReplaceData = generateReplaceValues(vehData, pluginConfig.customRecords.vehicleRegistrationValues)
                for k, v in pairs(vehReplaceData) do
                    boloData.replaceValues[k] = v
                end
                performApiRequest({boloData}, 'NEW_RECORD', function(res)
                end)
            end
        end)
        CreateThread(function()
            Wait(5000)
            debugLog('Loading ERS Callouts...')
            local calloutData = exports.night_ers.getCallouts()
            for uid, callout in pairs(calloutData) do
                -- Retain only the first description if it exists, otherwise set to an empty table
                if callout.CalloutDescriptions and #callout.CalloutDescriptions > 0 then
                    callout.CalloutDescriptions = { callout.CalloutDescriptions[1] }
                else
                    callout.CalloutDescriptions = {}
                end

                -- Set CalloutLocations to an empty array
                callout.CalloutLocations = {}

                local data = {}
                data.id = uid
                data.data = callout
                table.insert(ersCallouts, data)
            end
            local data = {
                ['serverId'] = Config.serverId,
                ['callouts'] = ersCallouts
            }
            debugLog('Loaded ' .. #ersCallouts .. ' ERS callouts.')
            performApiRequest(data, 'SET_AVAILABLE_CALLOUTS', function(response)
                debugLog('ERS callouts sent to CAD.')
            end)
        end)
        --[[
            PUSH EVENT HANDLER
        ]]
        TriggerEvent('SonoranCAD::RegisterPushEvent', 'EVENT_NEW_CALLOUT', function(data)
            local calloutData = data.data
            local locations = vec3(calloutData.callout.data.CalloutLocations[1].X, calloutData.callout.data.CalloutLocations[1].Y, 41.0)
            calloutData.callout.data.CalloutLocations = {[1] = vector3(locations.x, locations.y, locations.z)}
            local calloutID = exports.night_ers:createCallout(calloutData.callout)
            calloutData.callout.newId = calloutID.calloutId
            TriggerClientEvent('SonoranCAD::ErsIntegration::BuildCallout', -1, calloutData.callout)
            if calloutID then
                debugLog("Callout " .. calloutID.calloutId .. " created.")
                TriggerClientEvent('SonoranCAD::ErsIntegration::RequestCallout', -1, calloutID.calloutId)
            else
                debugLog("Failed to create callout.")
            end
        end)
    end
    if GetResourceState('night_ers') == 'started' then
        debugLog("night ERS resource is started.")
        startErs()
    else
        errorLog("Night ERS resource is not started. Please start the resource before using this submodule.")
    end
    AddEventHandler('onResourceStart', function(resourceName)
        if resourceName == 'night_ers' then
            debugLog("night ERS resource started.")
            startErs()
        end
    end)
end