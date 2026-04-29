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
        RegisterNetEvent('ErsIntegration::OnIsOfferedCallout')
        RegisterNetEvent('ErsIntegration::OnAcceptedCalloutOffer')
        RegisterNetEvent('SonoranCAD::ErsIntegration::BuildChars')
        RegisterNetEvent('SonoranCAD::ErsIntegration::BuildVehs')
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
            AddEventHandler('ErsIntegration::OnIsOfferedCallout', function(calloutData)
                local uniqueKey = generateUniqueCalloutKey(calloutData)
                debugLog('Generated unqiue key for callout: '.. uniqueKey)
                if pluginConfig.clearRecordsAfter ~= 0 and processedCalloutOffered[uniqueKey] then
                    local entry   = processedCalloutOffered[uniqueKey]
                    local ageSecs = os.time() - entry.timestamp
                    if ageSecs >= (pluginConfig.clearRecordsAfter * 60) then
                        debugLog(("Expiring callout %s after %d minutes."):format(uniqueKey, pluginConfig.clearRecordsAfter))
                        processedCalloutOffered[uniqueKey] = nil
                    end
                end
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
                        ['serverId'] = tonumber(Config.serverId),
                        ['isEmergency'] = true,
                        ['caller'] = caller,
                        ['location'] = location,
                        ['description'] = description,
                        ['metaData'] = {
                            ['x'] = tostring(calloutData.Coordinates.x),
                            ['y'] = tostring(calloutData.Coordinates.y),
                            ['plate'] = tostring(plate),
                            ['postal'] = tostring(postal)
                        }
                    }
                    if pluginConfig.clearRecordsAfter ~= 0 then
                        data.deleteAfterMinutes = pluginConfig.clearRecordsAfter
                    end
                    local response = CadApiCreateEmergencyCall(data)
                    if not response.success then
                        errorLog("ERS emergency call creation failed: " .. CadApiReasonText(response.reason))
                        return
                    end
                    local callId = response.callId
                    if callId then
                            processedCalloutOffered[uniqueKey] = {id = tostring(callId), timestamp = os.time()}
                            debugLog("Saved call ID: " .. processedCalloutOffered[uniqueKey].id)
                    else
                        debugLog("Could not extract call ID from response.")
                    end
                end
            end)
        end
        --[[
            EMERGENCY CALL CREATION
        ]]
        if pluginConfig.createEmergencyCall then
            AddEventHandler('ErsIntegration::OnAcceptedCalloutOffer', function(calloutData)
                local uniqueKey = generateUniqueCalloutKey(calloutData)
                if pluginConfig.clearRecordsAfter ~= 0 and processedCalloutAccepted[uniqueKey] then
                    local entry   = processedCalloutAccepted[uniqueKey]
                    local ageSecs = os.time() - entry.timestamp
                    if ageSecs >= (pluginConfig.clearRecordsAfter * 60) then
                        debugLog(("Expiring callout %s after %d minutes."):format(uniqueKey, pluginConfig.clearRecordsAfter))
                        processedCalloutAccepted[uniqueKey] = nil
                    end
                end
                if processedCalloutAccepted[uniqueKey] then
                    debugLog("Callout " .. calloutData.calloutId .. " already processed. Skipping emergency call... adding new units")
                    if pluginConfig.autoAddCall then
                        local callId = processedCalloutAccepted[uniqueKey]
                        local unit = GetUnitByPlayerId(source)
                        if unit == nil then
                            debugLog("Unit not found for player ID: " .. source)
                            return
                        end
                        local unitId = GetPlayerCommunityUserId(source)
                        if unitId == nil then
                            debugLog("Unit is not linked to CAD for player ID: " .. source)
                            return
                        end
                        local data = {
                            ['serverId'] = tonumber(Config.serverId),
                            ['callId'] = callId,
                            ['units'] = {unitId}
                        }
                        local response = CadApiAttachUnitsToDispatchCall(data)
                        if not response.success then
                            CadApiLogFailure("ATTACH_UNIT", response, data)
                        else
                            debugLog("Added unit to call: OK")
                        end
                    end
                else
                    debugLog("Processing callout " .. calloutData.calloutId .. " for emergency call.")
                    local callCode = pluginConfig.callCodes[calloutData.CalloutName] or ""
                    local unit = GetUnitByPlayerId(source)
                    local unitId = ""
                    local communityUserIds = {}
                    if unit == nil then
                        debugLog("Unit not found for player ID: " .. source)
                    else
                        unitId = GetPlayerCommunityUserId(source) or ""
                        if unitId ~= "" then
                            communityUserIds = { unitId }
                        end
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
                        ['serverId'] = tonumber(Config.serverId),
                        ['origin'] = 0,
                        ['status'] = 1,
                        ['priority'] = pluginConfig.callPriority,
                        ['block'] = postal,
                        ['postal'] = postal,
                        ['communityUserIds'] = communityUserIds,
                        ['address'] = calloutData.StreetName,
                        ['title'] = calloutData.CalloutName,
                        ['code'] = callCode,
                        ['description'] = calloutData.Description,
                        ['units'] = {unitId},
                        ['notes'] = {}, -- required
                        ['metaData'] = {
                            ['x'] = tostring(calloutData.Coordinates.x),
                            ['y'] = tostring(calloutData.Coordinates.y)
                        }
                    }
                    if pluginConfig.clearRecordsAfter ~= 0 then
                        data.deleteAfterMinutes = pluginConfig.clearRecordsAfter
                    end
                    local response = CadApiCreateDispatchCall(data)
                    if not response.success then
                        errorLog("ERS dispatch creation failed: " .. CadApiReasonText(response.reason))
                        return
                    end
                    local callId = response.callId
                    if callId then
                            -- Save the callId in the processedCalloutOffered table using the unique key
                            processedCalloutAccepted[uniqueKey] = {id = tostring(callId), timestamp = os.time()}
                            if processedCalloutOffered[uniqueKey] ~= nil then
                                local payload = { serverId = tonumber(Config.serverId), callId = processedCalloutOffered[uniqueKey].id}
                                local removeResponse = CadApiDeleteEmergencyCall(payload.callId, payload.serverId)
                                if not removeResponse.success then
                                    CadApiLogFailure("REMOVE_911", removeResponse, payload)
                                else
                                    debugLog("Remove status: OK")
                                end
                            end
                            debugLog("Call ID " .. callId .. " saved for unique key: " .. uniqueKey)
                    else
                        debugLog("Failed to extract callId from response: " .. json.encode(response.data or {}))
                    end
                end
            end)
        end
        --[[
            CALLOUT, PED AND VEHICLE DATA CREATION
        ]]
        AddEventHandler('SonoranCAD::ErsIntegration::BuildChars', function(pedData)
            local uniqueKey = generateUniquePedDataKey(pedData)
            if pluginConfig.clearRecordsAfter ~= 0 and processedPedData[uniqueKey] then
                local entry   = processedPedData[uniqueKey]
                local ageSecs = os.time() - entry.timestamp
                if ageSecs >= (pluginConfig.clearRecordsAfter * 60) then
                    debugLog(("Expiring character data %s after %d minutes."):format(uniqueKey, pluginConfig.clearRecordsAfter))
                    processedPedData[uniqueKey] = nil
                end
            end
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
            if pluginConfig.clearRecordsAfter ~= 0 then
                data.deleteAfterMinutes = pluginConfig.clearRecordsAfter
            end
            data.replaceValues = generateReplaceValues(pedData, pluginConfig.customRecords.civilianValues)
            local characterResponse = CadApiCreateRecord(data)
            if characterResponse.success and characterResponse.recordId ~= nil then
                local recordId = characterResponse.recordId
                processedPedData[uniqueKey] = {id = recordId, timestamp = os.time()}
                debugLog("Record ID " .. recordId .. " saved for unique key: " .. uniqueKey)
            elseif characterResponse.success then
                warnLog("Invalid or missing 'id' in response")
            else
                CadApiLogFailure("NEW_CHARACTER", characterResponse, data)
            end
            -- LICENSE RECORD
            for _, v in pairs (pluginConfig.customRecords.licenseTypeConfigs) do
                if pedData[v.license] ~= "No license" then
                    local licenseData = {
                        ['user'] = '00000000-0000-0000-0000-000000000000',
                        ['useDictionary'] = true,
                        ['recordTypeId'] = pluginConfig.customRecords.licenseRecordId
                    }
                    if pluginConfig.clearRecordsAfter ~= 0 then
                        licenseData.deleteAfterMinutes = pluginConfig.clearRecordsAfter
                    end
                    licenseData.replaceValues = generateLicenseReplaceValues(pedData, pluginConfig.customRecords.licenseRecordValues, v)
                    licenseData.replaceValues[pluginConfig.customRecords.licenseTypeField] = v.type
                    local response = CadApiCreateRecord(licenseData)
                    if not response.success then
                        CadApiLogFailure("NEW_RECORD", response, licenseData)
                    end
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
                if pluginConfig.clearRecordsAfter ~= 0 then
                    boloData.deleteAfterMinutes = pluginConfig.clearRecordsAfter
                end
                local warrantTypes = mapFlagsToBoloOptions(pedData.FlagsOrMarkers)
                local pedReplaceData = generateReplaceValues(pedData, pluginConfig.customRecords.civilianValues)
                for k, v in pairs(pedReplaceData) do
                    boloData.replaceValues[k] = v
                end
                boloData.replaceValues[pluginConfig.customRecords.warrantDescription] = pedData.FlagsOrMarkers.flag_description or ""
                boloData.replaceValues[pluginConfig.customRecords.warrantFlags] = json.encode(warrantTypes)
                local response = CadApiCreateRecord(boloData)
                if not response.success then
                    CadApiLogFailure("NEW_RECORD", response, boloData)
                end
            end
        end)
        AddEventHandler('SonoranCAD::ErsIntegration::BuildVehs', function(vehData)
            local uniqueKey = generateUniqueVehDataKey(vehData)
            if pluginConfig.clearRecordsAfter ~= 0 and processedVehData[uniqueKey] then
                local entry   = processedVehData[uniqueKey]
                local ageSecs = os.time() - entry.timestamp
                if ageSecs >= (pluginConfig.clearRecordsAfter * 60) then
                    debugLog(("Expiring vehicle data %s after %d minutes."):format(uniqueKey, pluginConfig.clearRecordsAfter))
                    processedVehData[uniqueKey] = nil
                end
            end
            if processedVehData[uniqueKey] then
                debugLog("Vehicle " .. vehData.model .. " " .. vehData.license_plate .. " already processed.")
                return
            end
            local data = {
                ['user'] = '00000000-0000-0000-0000-000000000000',
                ['useDictionary'] = true,
                ['recordTypeId'] = pluginConfig.customRecords.vehicleRegistrationRecordID,
            }
            if pluginConfig.clearRecordsAfter ~= 0 then
                data.deleteAfterMinutes = pluginConfig.clearRecordsAfter
            end
            data.replaceValues = generateReplaceValues(vehData, pluginConfig.customRecords.vehicleRegistrationValues)
            local recordResponse = CadApiCreateRecord(data)
            if recordResponse.success and recordResponse.recordId ~= nil then
                local recordId = recordResponse.recordId
                processedVehData[uniqueKey] = {id = recordId, timestamp = os.time()}
                debugLog("Record ID " .. recordId .. " saved for unique key: " .. uniqueKey)
            elseif recordResponse.success then
                warnLog("Invalid or missing 'id' in response")
            else
                CadApiLogFailure("NEW_RECORD", recordResponse, data)
            end
            if vehData.bolo then
                local boloData = {
                    ['user'] = '00000000-0000-0000-0000-000000000000',
                    ['useDictionary'] = true,
                    ['recordTypeId'] = pluginConfig.customRecords.boloRecordID,
                    ['replaceValues'] = {}
                }
                if pluginConfig.clearRecordsAfter ~= 0 then
                    boloData.deleteAfterMinutes = pluginConfig.clearRecordsAfter
                end
                boloData.replaceValues = generateReplaceValues(vehData, pluginConfig.customRecords.boloRecordValues)
                local vehReplaceData = generateReplaceValues(vehData, pluginConfig.customRecords.vehicleRegistrationValues)
                for k, v in pairs(vehReplaceData) do
                    boloData.replaceValues[k] = v
                end
                local response = CadApiCreateRecord(boloData)
                if not response.success then
                    CadApiLogFailure("NEW_RECORD", response, boloData)
                end
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

                if callout.PedWeaponData == nil or #callout.PedWeaponData == 0 then
                    callout.PedWeaponData = {}
                end

                local data = {}
                data.id = uid
                data.data = callout
                table.insert(ersCallouts, data)
            end
            local data = {
                ['serverId'] = tonumber(Config.serverId),
                ['callouts'] = ersCallouts
            }
            debugLog('Loaded ' .. #ersCallouts .. ' ERS callouts.')
            local response = CadApiSetAvailableCallouts(data)
            if response.success then
                debugLog('ERS callouts sent to CAD.')
            else
                CadApiLogFailure('SET_AVAILABLE_CALLOUTS', response, data)
            end
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
            TriggerClientEvent('ErsIntegration::BuildCallout', -1, calloutData.callout)
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
