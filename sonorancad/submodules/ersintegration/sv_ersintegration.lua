--[[
    Sonaran CAD Plugins

    Plugin Name: ersintegration
    Creator: Sonoran Software
    Description: Integrates Knight ERS callouts to SonoranCAD
]]
local pluginConfig = Config.GetPluginConfig("ersintegration") or {}
local postalConfig = Config.GetPluginConfig("postals") or {}

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
            return tostring(str or ""):gsub(" ", "_")
        end

        local function asTable(value)
            if type(value) == "table" then
                return value
            end

            return nil
        end

        local function safeString(value, default)
            if value == nil then
                return default or ""
            end

            return tostring(value)
        end

        local function getCoordinates(coords)
            if type(coords) ~= "table" then
                return nil
            end

            local x = tonumber(coords.x or coords.X)
            local y = tonumber(coords.y or coords.Y)
            local z = tonumber(coords.z or coords.Z)
            if x == nil or y == nil then
                return nil
            end

            return { x = x, y = y, z = z or 0.0 }
        end

        local function getPostal(calloutData)
            local postal = safeString(calloutData.Postal, "")
            if postal ~= "" and postal ~= "Unknown postal" then
                return postal
            end

            if not postalConfig.enabled then
                return "Unknown postal"
            end

            local coords = getCoordinates(calloutData.Coordinates)
            if coords == nil then
                return "Unknown postal"
            end

            local postalResource = exports[postalConfig.nearestPostalResourceName]
            if postalResource == nil or type(postalResource.getPostalServer) ~= "function" then
                return "Unknown postal"
            end

            local nearestPostal = postalResource:getPostalServer({coords.x, coords.y})
            if type(nearestPostal) ~= "table" or nearestPostal.code == nil then
                return "Unknown postal"
            end

            return tostring(nearestPostal.code)
        end
        --[[
        @function generateUniqueCalloutKey
        @param table callout
        @return string
        Used to generate the unique key for a callout creation for tracking
        ]]
        local function generateUniqueCalloutKey(callout)
            local coords = getCoordinates(callout and callout.Coordinates) or { x = 0.0, y = 0.0, z = 0.0 }
            return string.format(
                "%s_%s_%.2f_%.2f_%.2f",
                safeString(callout and callout.calloutId, "unknown"),
                escapeSpaces(callout and callout.StreetName),
                coords.x,
                coords.y,
                coords.z
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
                safeString(pedData and pedData.uniqueId, "unknown"),
                safeString(pedData and pedData.FirstName, "unknown"),
                safeString(pedData and pedData.LastName, "unknown"),
                escapeSpaces(pedData and pedData.Address)
            )
        end

        local function generateUniqueVehDataKey(vehData)
            return string.format(
                "%s_%s_%s_%s",
                escapeSpaces(vehData and vehData.license_plate),
                safeString(vehData and vehData.model, "unknown"),
                safeString(vehData and vehData.color, "unknown"),
                safeString(vehData and vehData.build_year, "unknown")
            )
        end
        --[[
        @function generateCallNote
        @param table callout
        @return string
        Used to generate the call note for a callout
        ]]
        function generateCallNote(callout)
            if type(callout) ~= "table" then
                return "No additional units required."
            end

            -- Start with basic callout information
            local note = ''

            -- Append potential weapons information
            if type(callout.PedWeaponData) == "table" and #callout.PedWeaponData > 0 then
                note = note .. "Potential weapons: " .. table.concat(callout.PedWeaponData, ", ") .. ". "
            else
                note = note .. "No weapons reported. "
            end

            -- Determine the required units from the callout
            local requiredUnits = {}
            local units = asTable(callout.CalloutUnitsRequired) or {}
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
                    local ok, value = pcall(source, data)
                    if ok then
                        replaceValues[cadKey] = value or ""
                    else
                        errorLog("ERS replace value mapping failed for key " .. tostring(cadKey) .. ": " .. tostring(value))
                        replaceValues[cadKey] = ""
                    end
                elseif type(source) == "string" then
                    replaceValues[cadKey] = data[source] or ""
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
                    result[cadKey] = pedData[ersKeyOrFunc] or ""
                elseif type(ersKeyOrFunc) == "function" then
                    local ok, value = pcall(ersKeyOrFunc, pedData, extraContext)
                    if ok then
                        result[cadKey] = value or ""
                    else
                        errorLog("ERS license mapping failed for key " .. tostring(cadKey) .. ": " .. tostring(value))
                        result[cadKey] = ""
                    end
                end
            end
            return result
        end

        function mapFlagsToBoloOptions(flags)
            local boloFlags = {}
            if type(flags) ~= "table" then
                return boloFlags
            end

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
                if type(calloutData) ~= "table" then
                    errorLog("ERS 911 callout payload was malformed.")
                    return
                end

                local coords = getCoordinates(calloutData.Coordinates)
                if coords == nil then
                    errorLog("ERS 911 callout missing valid coordinates.")
                    return
                end

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
                    debugLog("Callout " .. safeString(calloutData.calloutId, "unknown") .. " already processed. Skipping 911 call.")
                else
                    local caller = (safeString(calloutData.FirstName) .. " " .. safeString(calloutData.LastName)):gsub("^%s+", ""):gsub("%s+$", "")
                    local location = safeString(calloutData.StreetName)
                    local description = safeString(calloutData.Description)
                    local postal = getPostal(calloutData)
                    local plate = ""
                    if calloutData.VehiclePlate ~= nil then
                        plate = safeString(calloutData.VehiclePlate)
                    end
                    local data = {
                        ['serverId'] = tonumber(Config.serverId),
                        ['isEmergency'] = true,
                        ['caller'] = caller,
                        ['location'] = location,
                        ['description'] = description,
                        ['metaData'] = {
                            ['x'] = tostring(coords.x),
                            ['y'] = tostring(coords.y),
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
                if type(calloutData) ~= "table" then
                    errorLog("ERS accepted callout payload was malformed.")
                    return
                end

                local coords = getCoordinates(calloutData.Coordinates)
                if coords == nil then
                    errorLog("ERS accepted callout missing valid coordinates.")
                    return
                end

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
                    debugLog("Callout " .. safeString(calloutData.calloutId, "unknown") .. " already processed. Skipping emergency call... adding new units")
                    if pluginConfig.autoAddCall then
                        local existingCall = processedCalloutAccepted[uniqueKey]
                        local callId = tonumber(existingCall.id or existingCall)
                        if callId == nil then
                            errorLog("ERS accepted callout had an invalid saved call ID for key: " .. uniqueKey)
                            return
                        end
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
                    debugLog("Processing callout " .. safeString(calloutData.calloutId, "unknown") .. " for emergency call.")
                    local callCode = type(pluginConfig.callCodes) == "table" and (pluginConfig.callCodes[calloutData.CalloutName] or "") or ""
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
                    local postal = getPostal(calloutData)
                    local data = {
                        ['serverId'] = tonumber(Config.serverId),
                        ['origin'] = 0,
                        ['status'] = 1,
                        ['priority'] = pluginConfig.callPriority,
                        ['block'] = postal,
                        ['postal'] = postal,
                        ['communityUserIds'] = communityUserIds,
                        ['address'] = safeString(calloutData.StreetName),
                        ['title'] = safeString(calloutData.CalloutName),
                        ['code'] = callCode,
                        ['description'] = safeString(calloutData.Description),
                        ['units'] = {unitId},
                        ['notes'] = {}, -- required
                        ['metaData'] = {
                            ['x'] = tostring(coords.x),
                            ['y'] = tostring(coords.y)
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
                                local payload = { serverId = tonumber(Config.serverId), callId = tonumber(processedCalloutOffered[uniqueKey].id)}
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
            if type(pedData) ~= "table" then
                errorLog("ERS character payload was malformed.")
                return
            end

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
                debugLog("Ped " .. safeString(pedData.FirstName, "unknown") .. " " .. safeString(pedData.LastName, "unknown") .. " already processed.")
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
                local licenseValue = pedData[v.license]
                if licenseValue ~= nil and licenseValue ~= "" and licenseValue ~= "No license" then
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
            local flagsOrMarkers = asTable(pedData.FlagsOrMarkers) or {}
            for _, flag in pairs(flagsOrMarkers) do
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
                local warrantTypes = mapFlagsToBoloOptions(flagsOrMarkers)
                local pedReplaceData = generateReplaceValues(pedData, pluginConfig.customRecords.civilianValues)
                for k, v in pairs(pedReplaceData) do
                    boloData.replaceValues[k] = v
                end
                boloData.replaceValues[pluginConfig.customRecords.warrantDescription] = safeString(flagsOrMarkers.flag_description)
                boloData.replaceValues[pluginConfig.customRecords.warrantFlags] = json.encode(warrantTypes)
                local response = CadApiCreateRecord(boloData)
                if not response.success then
                    CadApiLogFailure("NEW_RECORD", response, boloData)
                end
            end
        end)
        AddEventHandler('SonoranCAD::ErsIntegration::BuildVehs', function(vehData)
            if type(vehData) ~= "table" then
                errorLog("ERS vehicle payload was malformed.")
                return
            end

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
                debugLog("Vehicle " .. safeString(vehData.model, "unknown") .. " " .. safeString(vehData.license_plate, "unknown") .. " already processed.")
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
            if type(calloutData) ~= "table" then
                errorLog("ERS callout list was malformed.")
                calloutData = {}
            end
            for uid, callout in pairs(calloutData) do
                if type(callout) ~= "table" then
                    warnLog("Skipping malformed ERS callout with id: " .. tostring(uid))
                    goto continue
                end
                -- Retain only the first description if it exists, otherwise set to an empty table
                if type(callout.CalloutDescriptions) == "table" and #callout.CalloutDescriptions > 0 then
                    callout.CalloutDescriptions = { callout.CalloutDescriptions[1] }
                else
                    callout.CalloutDescriptions = {}
                end

                -- Set CalloutLocations to an empty array
                callout.CalloutLocations = {}

                if type(callout.PedWeaponData) ~= "table" or #callout.PedWeaponData == 0 then
                    callout.PedWeaponData = {}
                end

                local data = {}
                data.id = uid
                data.data = callout
                table.insert(ersCallouts, data)
                ::continue::
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
            if type(data) ~= "table" or type(data.data) ~= "table" or type(data.data.callout) ~= "table" or type(data.data.callout.data) ~= "table" then
                errorLog("Push event callout payload was malformed.")
                return
            end

            local calloutData = data.data
            local locations = asTable(calloutData.callout.data.CalloutLocations)
            local firstLocation = locations and locations[1]
            local coords = getCoordinates(firstLocation)
            if coords == nil then
                errorLog("Push event callout was missing a valid location.")
                return
            end

            calloutData.callout.data.CalloutLocations = {[1] = vector3(coords.x, coords.y, 41.0)}
            local calloutID = exports.night_ers:createCallout(calloutData.callout)
            if type(calloutID) == "table" and calloutID.calloutId then
                calloutData.callout.newId = calloutID.calloutId
                TriggerClientEvent('ErsIntegration::BuildCallout', -1, calloutData.callout)
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
