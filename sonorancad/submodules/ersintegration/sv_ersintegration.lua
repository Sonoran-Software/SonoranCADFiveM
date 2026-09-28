--[[
    Sonaran CAD Plugins

    Plugin Name: ersintegration
    Creator: Sonoran Software
    Description: Integrates Knight ERS callouts to SonoranCAD
]]
local pluginConfig = Config.GetPluginConfig("ersintegration") or {}
local postalConfig = Config.GetPluginConfig("postals") or {}
local ERS_MINIMUM_VERSION = "1.8.16"
local ersHealth = {
    enabled = pluginConfig.enabled == true,
    ready = false,
    status = pluginConfig.enabled and "waiting for night_ers" or (pluginConfig.disableReason or "disabled in config"),
    minimumVersion = ERS_MINIMUM_VERSION,
    catalog = {status = "not started", attempts = 0, count = 0},
    postal = {fallbacks = 0},
    counters = {offered = 0, accepted = 0, characters = 0, vehicles = 0, cadCallouts = 0}
}

function GetErsIntegrationDiagnostics()
    local currentConfig = Config.plugins and Config.plugins.ersintegration or pluginConfig
    local currentPostals = Config.plugins and Config.plugins.postals or postalConfig
    local postalResource = currentPostals.nearestPostalResourceName
    return {
        enabled = currentConfig.enabled == true,
        ready = ersHealth.ready and currentConfig.enabled == true,
        status = currentConfig.enabled == false and (currentConfig.disableReason or "disabled in config") or ersHealth.status,
        nightErsState = GetResourceState('night_ers'),
        detectedVersion = ersHealth.detectedVersion,
        versionStatus = ersHealth.versionStatus,
        minimumVersion = ersHealth.minimumVersion,
        features = {
            create911Call = currentConfig.create911Call == true,
            createDispatchCallOnAcceptance = currentConfig.createEmergencyCall == true,
            autoAttachAcceptingUnit = currentConfig.autoAddCall == true,
            createNpcRecordsOnInteraction = currentConfig.enabled == true
        },
        catalog = ersHealth.catalog,
        postal = {
            mode = currentPostals.mode or "resource",
            configured = currentPostals.enabled == true,
            resource = postalResource,
            resourceState = (currentPostals.mode == nil or currentPostals.mode == "resource") and
                (type(postalResource) == "string" and postalResource ~= "" and GetResourceState(postalResource) or "not configured") or "not used in this mode",
            cadCoordinateLookupAvailable = type(getPostalFromVector3) == "function",
            fallbacks = ersHealth.postal.fallbacks,
            lastReason = ersHealth.postal.lastReason,
            lastSource = ersHealth.postal.lastSource
        },
        counters = ersHealth.counters,
        lastFailure = ersHealth.lastFailure,
        lastSuccess = ersHealth.lastSuccess,
        configIssues = ersHealth.configIssues
    }
end

local function ersFailure(stage, reason)
    ersHealth.lastFailure = {stage = stage, reason = tostring(reason):sub(1, 300), at = os.date('!%Y-%m-%dT%H:%M:%SZ')}
end

local function ersSuccess(stage)
    local at = os.date('!%Y-%m-%dT%H:%M:%SZ')
    ersHealth.lastSuccess = {stage = stage, at = at}
    if ersHealth.lastFailure and (ersHealth.lastFailure.stage == stage or
        (stage == "startup" and ersHealth.lastFailure.stage == "runtime")) then
        ersHealth.lastFailure.resolvedAt = at
    end
end

if pluginConfig.enabled then
    local handlersRegistered = false
    local catalogGeneration = 0
    local syncCatalog

    local function isReady()
        return ersHealth.ready and pluginConfig.enabled == true and GetResourceState('night_ers') == 'started'
    end

    local function validateConfiguration()
        local issues = {}
        local fatal = false
        if tonumber(Config.serverId) == nil then
            issues[#issues + 1] = "CAD serverId is missing or invalid"
            fatal = true
        end
        local minutes = tonumber(pluginConfig.clearRecordsAfter)
        if minutes == nil or minutes < 0 or minutes % 1 ~= 0 then
            issues[#issues + 1] = "clearRecordsAfter must be zero or a positive whole number"
            fatal = true
        else
            pluginConfig.clearRecordsAfter = minutes
        end
        if pluginConfig.createEmergencyCall then
            local priority = tonumber(pluginConfig.callPriority)
            if priority == nil or priority < 1 or priority > 3 or priority % 1 ~= 0 then
                issues[#issues + 1] = "callPriority must be 1, 2, or 3"
                fatal = true
            else
                pluginConfig.callPriority = priority
            end
        end
        local records = pluginConfig.customRecords
        if type(records) ~= "table" then
            issues[#issues + 1] = "customRecords is missing; ERS record lookups will fail"
        else
            for _, field in ipairs({"civilianRecordID", "civilianValues", "licenseRecordId", "licenseTypeField", "licenseTypeConfigs", "licenseRecordValues", "vehicleRegistrationRecordID", "vehicleRegistrationValues", "boloRecordID", "boloRecordValues", "warrantRecordID", "warrantDescription", "warrantFlags"}) do
                local expectedTable = field:find("Values") or field == "licenseTypeConfigs"
                if records[field] == nil or (expectedTable and type(records[field]) ~= "table") then
                    issues[#issues + 1] = "customRecords." .. field .. " is missing or invalid"
                end
            end
        end
        ersHealth.configIssues = issues
        if #issues > 0 then
            warnLog("ERS_CONFIG_INVALID", "ERS configuration issues: " .. table.concat(issues, "; "))
        end
        return not fatal
    end

    local function checkErsVersion()
        local metadataOk, currentVersion = pcall(GetResourceMetadata, "night_ers", "version", 0)
        ersHealth.detectedVersion = metadataOk and tostring(currentVersion or "unavailable") or "metadata lookup failed"
        ersHealth.versionStatus = "unverified"
        local normalizedVersion

        if metadataOk and type(currentVersion) == "string" then
            local major, minor, patch = currentVersion:match("^%s*(%d+)%.(%d+)%.(%d+)%s*$")
            if major ~= nil then
                normalizedVersion = ("%s.%s.%s"):format(major, minor, patch)
            end
        end

        if normalizedVersion == nil then
            local detectedVersion
            if not metadataOk then
                detectedVersion = "metadata lookup failed: " .. tostring(currentVersion)
            elseif currentVersion == nil then
                detectedVersion = "unavailable"
            elseif type(currentVersion) ~= "string" then
                detectedVersion = "malformed (" .. type(currentVersion) .. ")"
            elseif currentVersion == "" then
                detectedVersion = "empty"
            else
                detectedVersion = currentVersion
            end

            errorLog("ERS_VERSION_TOO_OLD", ("The night_ers version could not be verified (detected version: %s; required version: %s). The ERS integration may not work."):format(
                detectedVersion,
                ERS_MINIMUM_VERSION
            ))
            -- Some custom ERS builds omit metadata. Keep the integration available and surface the uncertainty.
            return true
        end

        local comparisonOk, comparison = pcall(compareVersions, ERS_MINIMUM_VERSION, normalizedVersion)
        if not comparisonOk or type(comparison) ~= "table" or type(comparison.result) ~= "boolean" then
            errorLog("ERS_VERSION_TOO_OLD", ("The night_ers version could not be verified (detected version: %s; required version: %s). The ERS integration may not work."):format(
                normalizedVersion,
                ERS_MINIMUM_VERSION
            ))
            return true
        end

        if comparison.result then
            ersHealth.versionStatus = "unsupported"
            errorLog("ERS_VERSION_TOO_OLD", ("Detected night_ers version %s, but required version is %s or newer. The old version may cause the ERS integration not to work."):format(
                normalizedVersion,
                ERS_MINIMUM_VERSION
            ))
            return false
        end
        ersHealth.versionStatus = "supported"
        return true
    end

    local function startErs()
        if GetResourceState('night_ers') ~= 'started' then
            ersHealth.ready = false
            ersHealth.status = "night_ers is not started; start it to initialize ERS integration"
            ersFailure("startup", ersHealth.status)
            errorLog("ERS_RESOURCE_NOT_STARTED", ersHealth.status)
            return
        end
        if not checkErsVersion() then
            ersHealth.ready = false
            ersHealth.status = "night_ers version is below " .. ERS_MINIMUM_VERSION
            ersFailure("startup", ersHealth.status)
            return
        end
        if not validateConfiguration() then
            ersHealth.ready = false
            ersHealth.status = "invalid ERS configuration; check configIssues in support diagnostics"
            ersFailure("startup", ersHealth.status)
            return
        end
        ersHealth.ready = true
        if #ersHealth.configIssues > 0 then
            ersHealth.status = "running with record configuration issues"
        elseif ersHealth.versionStatus == "unverified" then
            ersHealth.status = "running; night_ers version could not be verified"
        else
            ersHealth.status = "running"
        end
        ersSuccess("startup")
        if handlersRegistered then
            syncCatalog()
            return
        end
        debugLog("Starting ERS Integration...")
        RegisterNetEvent('ErsIntegration::OnIsOfferedCallout')
        RegisterNetEvent('ErsIntegration::OnAcceptedCalloutOffer')
        RegisterNetEvent('SonoranCAD::ErsIntegration::BuildChars')
        RegisterNetEvent('SonoranCAD::ErsIntegration::BuildVehs')
        local processedCalloutOffered = {}
        local processedCalloutAccepted = {}
        local processedPedData = {}
        local processedVehData = {}
        local cadDispatchCallouts = {}

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

        local function getStablePlayerIdentity(playerSource, unit)
            local communityUserId = GetPlayerCommunityUserId(playerSource)
            if type(communityUserId) == "string" and communityUserId ~= "" then
                return communityUserId
            end

            local identities = GetUnitIdentityValues(unit)
            for _, identity in ipairs(identities) do
                if tonumber(GetSourceByCadIdentity({identity})) == tonumber(playerSource) then
                    return tostring(identity)
                end
            end

            return nil
        end

        local function rememberCadDispatchCall(callId, calloutData, playerIdentity, existingEntry)
            local normalizedCallId = tonumber(callId)
            local calloutId = safeString(calloutData and calloutData.calloutId)
            if normalizedCallId == nil or calloutId == "" then
                return existingEntry
            end

            local entry = existingEntry or {
                id = tostring(normalizedCallId),
                timestamp = os.time()
            }
            entry.calloutId = calloutId
            entry.acceptedIdentities = entry.acceptedIdentities or {}
            entry.requestedIdentities = entry.requestedIdentities or {}

            if type(playerIdentity) == "string" and playerIdentity ~= "" then
                entry.acceptedIdentities[playerIdentity] = true
                entry.requestedIdentities[playerIdentity] = nil
            end

            cadDispatchCallouts[tostring(normalizedCallId)] = entry
            return entry
        end

        local function getCadDispatchCallId(call)
            if type(call) ~= "table" then
                return nil
            end

            local dispatch = type(call.dispatch) == "table" and call.dispatch or call
            return tonumber(dispatch.callId or dispatch.id)
        end

        local function getCoordinates(coords)
            -- ERS native events use vector3; CAD websocket JSON decodes to a table.
            if type(coords) ~= "vector3" and type(coords) ~= "table" then
                return nil
            end
            local x = tonumber(coords.x or coords.X or coords[1])
            local y = tonumber(coords.y or coords.Y or coords[2])
            local z = tonumber(coords.z or coords.Z or coords[3])
            if x == nil or y == nil or x ~= x or y ~= y or math.abs(x) == math.huge or math.abs(y) == math.huge then
                return nil
            end
            if z == nil or z ~= z or math.abs(z) == math.huge then z = 0.0 end

            return { x = x, y = y, z = z }
        end

        local function getPostal(calloutData)
            ersHealth.postal.lastReason = nil
            local suppliedPostal = safeString(calloutData.Postal, "")
            local coords = getCoordinates(calloutData.Coordinates)
            if postalConfig.enabled and coords and type(getPostalFromVector3) == "function" then
                -- Use the same postal dataset CAD uses for unit locations, including file mode.
                local lookupOk, code = pcall(getPostalFromVector3, coords)
                if lookupOk and code ~= nil and tostring(code) ~= "" then
                    ersHealth.postal.lastSource = "CAD postals"
                    return tostring(code)
                end
                ersHealth.postal.lastReason = lookupOk and "CAD postal lookup returned no code" or "CAD postal lookup failed"
            end
            if postalConfig.enabled and coords and (postalConfig.mode == nil or postalConfig.mode == "resource") then
                -- Older postal setups may not have initialized CAD's lookup yet.
                local postalOk, nearestPostal = pcall(function()
                    return exports[postalConfig.nearestPostalResourceName]:getPostalServer({coords.x, coords.y})
                end)
                if postalOk and type(nearestPostal) == "table" and nearestPostal.code ~= nil then
                    ersHealth.postal.lastSource = "postal resource"
                    return tostring(nearestPostal.code)
                end
                ersHealth.postal.lastReason = postalOk and "postal export returned no code" or "postal resource or export unavailable"
            end
            ersHealth.postal.fallbacks = ersHealth.postal.fallbacks + 1
            if suppliedPostal ~= "" and suppliedPostal ~= "Unknown postal" then
                ersHealth.postal.lastSource = "night_ers fallback"
                ersHealth.postal.lastReason = ersHealth.postal.lastReason or "CAD postals unavailable"
                return suppliedPostal
            end
            ersHealth.postal.lastSource = "unknown fallback"
            ersHealth.postal.lastReason = ersHealth.postal.lastReason or (coords and "no postal source configured" or "no valid coordinates for postal lookup")
            return "Unknown postal"
        end

        local function requireRecordConfig(recordKind, required)
            local records = pluginConfig.customRecords
            if type(records) ~= "table" then
                ersFailure(recordKind, "customRecords is missing from ersintegration_config.lua")
                errorLog("ERS_CONFIG_INVALID", "ERS customRecords is missing; restore or update ersintegration_config.lua.")
                return nil
            end
            for _, field in ipairs(required) do
                if records[field] == nil or ((field:find("Values") or field == "licenseTypeConfigs") and type(records[field]) ~= "table") then
                    ersFailure(recordKind, "customRecords." .. field .. " is missing or invalid")
                    errorLog("ERS_CONFIG_INVALID", "ERS customRecords." .. field .. " is missing or invalid in ersintegration_config.lua.")
                    return nil
                end
            end
            return records
        end

        local function callCad(stage, fn, ...)
            local ok, response = pcall(fn, ...)
            if ok and type(response) == "table" and type(response.success) == "boolean" then
                if not response.success then
                    local reason = CadApiReasonText(response.reason)
                    local status = tonumber(response.status) or
                        (type(response.reason) == "table" and tonumber(response.reason.status))
                    if (stage:find("record", 1, true) or stage == "vehicle BOLO") and status == 409 then
                        reason = reason .. "; check unique fields in the matching CAD record template for duplicate values"
                    end
                    ersFailure(stage, reason)
                end
                return response
            end
            local reason = ok and "CAD returned an invalid response" or tostring(response)
            ersFailure(stage, reason)
            return {success = false, reason = reason}
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
                        ersFailure("record mapping", "customRecords mapping failed for " .. tostring(cadKey))
                        errorLog("ERS_MAPPING_FAILED", "ERS replace value mapping failed for key " .. tostring(cadKey) .. ": " .. tostring(value))
                        replaceValues[cadKey] = ""
                    end
                elseif type(source) == "string" then
                    replaceValues[cadKey] = data[source] or ""
                else
                    ersFailure("record mapping", "customRecords mapping has an invalid value for " .. tostring(cadKey))
                    errorLog("ERS_MAPPING_FAILED", "Invalid ERS mapping configuration for key: " .. tostring(cadKey))
                    replaceValues[cadKey] = ""
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
                        ersFailure("license mapping", "customRecords license mapping failed for " .. tostring(cadKey))
                        errorLog("ERS_MAPPING_FAILED", "ERS license mapping failed for key " .. tostring(cadKey) .. ": " .. tostring(value))
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
                if not isReady() then return end
                ersHealth.counters.offered = ersHealth.counters.offered + 1
                if type(calloutData) ~= "table" then
                    ersFailure("911 call", "ERS offered callout payload was malformed")
                    errorLog("ERS_PAYLOAD_MALFORMED", "ERS 911 callout payload was malformed.")
                    return
                end

                local coords = getCoordinates(calloutData.Coordinates)
                if coords == nil then
                    ersFailure("911 call", "ERS callout coordinates are missing or invalid")
                    errorLog("ERS_COORDS_MISSING", "ERS 911 callout missing valid coordinates.")
                    return
                end

                local uniqueKey = generateUniqueCalloutKey(calloutData)
                debugLog('Generated unqiue key for callout: '.. uniqueKey)
                if processedCalloutOffered[uniqueKey] then
                    local entry   = processedCalloutOffered[uniqueKey]
                    local ageSecs = os.time() - entry.timestamp
                    local expiry = entry.id == nil and 5 or pluginConfig.clearRecordsAfter
                    if expiry ~= 0 and ageSecs >= (expiry * 60) then
                        debugLog(("Expiring callout %s after %d minutes."):format(uniqueKey, expiry))
                        processedCalloutOffered[uniqueKey] = nil
                    end
                end
                if processedCalloutOffered[uniqueKey] then
                    debugLog("Callout " .. safeString(calloutData.calloutId, "unknown") .. " already processed. Skipping 911 call.")
                else
                    processedCalloutOffered[uniqueKey] = {timestamp = os.time(), pending = true}
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
                    local response = callCad("911 call", CadApiCreateEmergencyCall, data)
                    if not response.success then
                        processedCalloutOffered[uniqueKey] = nil
                        ersFailure("911 call", CadApiReasonText(response.reason))
                        errorLog("ERS_CAD_REQUEST_FAILED", "ERS emergency call creation failed: " .. CadApiReasonText(response.reason))
                        return
                    end
                    local callId = tonumber(response.callId)
                    if callId and callId > 0 then
                            processedCalloutOffered[uniqueKey] = {id = tostring(callId), timestamp = os.time()}
                            ersSuccess("911 call")
                            debugLog("Saved call ID: " .. processedCalloutOffered[uniqueKey].id)
                    else
                        processedCalloutOffered[uniqueKey] = {timestamp = os.time()}
                        ersFailure("911 call", "CAD returned success without a call ID")
                        errorLog("ERS_CALL_ID_INVALID", "CAD reported an ERS emergency call as created without returning its ID. Repeated events are suppressed for five minutes to avoid duplicate calls.")
                    end
                end
            end)
        end
        --[[
            EMERGENCY CALL CREATION
        ]]
        if pluginConfig.createEmergencyCall then
            AddEventHandler('ErsIntegration::OnAcceptedCalloutOffer', function(calloutData)
                if not isReady() then return end
                ersHealth.counters.accepted = ersHealth.counters.accepted + 1
                local playerSource = tonumber(source)
                if playerSource == nil or playerSource <= 0 then
                    ersFailure("dispatch call", "ERS accepted callout did not identify an in-game player")
                    errorLog("ERS_PAYLOAD_MALFORMED", "ERS accepted callout did not identify an in-game player.")
                    return
                end
                if type(calloutData) ~= "table" then
                    ersFailure("dispatch call", "ERS accepted callout payload was malformed")
                    errorLog("ERS_PAYLOAD_MALFORMED", "ERS accepted callout payload was malformed.")
                    return
                end

                local coords = getCoordinates(calloutData.Coordinates)
                if coords == nil then
                    ersFailure("dispatch call", "ERS callout coordinates are missing or invalid")
                    errorLog("ERS_COORDS_MISSING", "ERS accepted callout missing valid coordinates.")
                    return
                end

                local uniqueKey = generateUniqueCalloutKey(calloutData)
                if processedCalloutAccepted[uniqueKey] then
                    local entry   = processedCalloutAccepted[uniqueKey]
                    local ageSecs = os.time() - entry.timestamp
                    local expiry = entry.id == nil and 5 or pluginConfig.clearRecordsAfter
                    if expiry ~= 0 and ageSecs >= (expiry * 60) then
                        debugLog(("Expiring callout %s after %d minutes."):format(uniqueKey, expiry))
                        processedCalloutAccepted[uniqueKey] = nil
                    end
                end
                if processedCalloutAccepted[uniqueKey] then
                    if processedCalloutAccepted[uniqueKey].pending then
                        local pending = processedCalloutAccepted[uniqueKey]
                        pending.pendingPlayers = pending.pendingPlayers or {}
                        pending.pendingPlayers[playerSource] = true
                        debugLog("ERS dispatch creation is already in progress; queued the accepting unit.")
                        return
                    end
                    debugLog("Callout " .. safeString(calloutData.calloutId, "unknown") .. " already processed. Skipping emergency call... adding new units")
                    local existingCall = processedCalloutAccepted[uniqueKey]
                    local callId = tonumber(existingCall.id or existingCall)
                    if callId == nil then
                        ersFailure("dispatch call", "Saved CAD call ID is invalid")
                        errorLog("ERS_CALL_ID_INVALID", "ERS accepted callout had an invalid saved call ID for key: " .. uniqueKey)
                        return
                    end
                    local playerIdentity = getStablePlayerIdentity(playerSource, GetUnitByPlayerId(playerSource))
                    rememberCadDispatchCall(callId, calloutData, playerIdentity, existingCall)
                    if pluginConfig.autoAddCall then
                        local unitData = getPlayerCadStatus(playerSource, "ERS Integration", { unit = true, link = true })
                        if not unitData.success then
                            ersFailure("attach unit", unitData.hasLink and "player has no active CAD unit; clock in before accepting ERS calls" or "player is not linked to CAD; use the link command before accepting ERS calls")
                            return
                        end
                        local data = {
                            ['serverId'] = tonumber(Config.serverId),
                            ['callId'] = callId,
                            ['communityUserIds'] = {unitData.link}
                        }
                        local response = callCad("attach unit", CadApiAttachUnitsToDispatchCall, data)
                        if not response.success then
                            CadApiLogFailure("ATTACH_UNIT", response, data)
                        else
                            ersSuccess("attach unit")
                            debugLog("Added unit to call: OK")
                        end
                    end
                else
                    debugLog("Processing callout " .. safeString(calloutData.calloutId, "unknown") .. " for emergency call.")
                    local callCode = type(pluginConfig.callCodes) == "table" and (pluginConfig.callCodes[calloutData.CalloutName] or "") or ""
                    local unitData = getPlayerCadStatus(playerSource, "ERS Integration", { unit = true, link = true })
                    if not unitData.success then
                        ersFailure("dispatch call", unitData.hasLink and "player has no active CAD unit; clock in before accepting ERS calls" or "player is not linked to CAD; use the link command before accepting ERS calls")
                        return
                    end
                    processedCalloutAccepted[uniqueKey] = {timestamp = os.time(), pending = true}
                    local postal = getPostal(calloutData)
                    local data = {
                        ['serverId'] = tonumber(Config.serverId),
                        ['origin'] = 0,
                        ['status'] = 1,
                        ['priority'] = pluginConfig.callPriority,
                        ['block'] = postal,
                        ['postal'] = postal,
                        ['communityUserIds'] = { unitData.link },
                        ['address'] = safeString(calloutData.StreetName),
                        ['title'] = safeString(calloutData.CalloutName),
                        ['code'] = callCode,
                        ['description'] = safeString(calloutData.Description),
                        ['notes'] = {}, -- required
                        ['metaData'] = {
                            ['x'] = tostring(coords.x),
                            ['y'] = tostring(coords.y)
                        }
                    }
                    if pluginConfig.clearRecordsAfter ~= 0 then
                        data.deleteAfterMinutes = pluginConfig.clearRecordsAfter
                    end
                    local response = callCad("dispatch call", CadApiCreateDispatchCall, data)
                    if not response.success then
                        processedCalloutAccepted[uniqueKey] = nil
                        ersFailure("dispatch call", CadApiReasonText(response.reason))
                        errorLog("ERS_CAD_REQUEST_FAILED", "ERS dispatch creation failed: " .. CadApiReasonText(response.reason))
                        return
                    end
                    local callId = tonumber(response.callId)
                    if callId and callId > 0 then
                            local pendingPlayers = processedCalloutAccepted[uniqueKey].pendingPlayers or {}
                            processedCalloutAccepted[uniqueKey] = rememberCadDispatchCall(callId, calloutData, unitData.link)
                            ersSuccess("dispatch call")
                            if pluginConfig.autoAddCall then
                                for pendingSource in pairs(pendingPlayers) do
                                    if pendingSource ~= playerSource then
                                        local queuedUnit = getPlayerCadStatus(pendingSource, "ERS Integration", {unit = true, link = true})
                                        if queuedUnit.success then
                                            local attachData = {serverId = tonumber(Config.serverId), callId = callId, communityUserIds = {queuedUnit.link}}
                                            local attachResponse = callCad("attach unit", CadApiAttachUnitsToDispatchCall, attachData)
                                            if attachResponse.success then
                                                rememberCadDispatchCall(callId, calloutData, queuedUnit.link, processedCalloutAccepted[uniqueKey])
                                                ersSuccess("attach unit")
                                            else
                                                CadApiLogFailure("ATTACH_UNIT", attachResponse, attachData)
                                            end
                                        end
                                    end
                                end
                            end
                            if processedCalloutOffered[uniqueKey] ~= nil then
                                local offeredId = tonumber(processedCalloutOffered[uniqueKey].id)
                                if offeredId ~= nil then
                                    local payload = { serverId = tonumber(Config.serverId), callId = offeredId}
                                    local removeResponse = callCad("remove 911 call", CadApiDeleteEmergencyCall, payload.callId, payload.serverId)
                                    if not removeResponse.success then
                                        CadApiLogFailure("REMOVE_911", removeResponse, payload)
                                    else
                                        debugLog("Remove status: OK")
                                    end
                                end
                            end
                            debugLog("Call ID " .. callId .. " saved for unique key: " .. uniqueKey)
                    else
                        processedCalloutAccepted[uniqueKey] = {timestamp = os.time()}
                        ersFailure("dispatch call", "CAD returned success without a call ID")
                        errorLog("ERS_CALL_ID_INVALID", "CAD reported an ERS dispatch call as created without returning its ID. Repeated events are suppressed for five minutes to avoid duplicate calls.")
                    end
                end
            end)

            AddEventHandler('SonoranCAD::pushevents:UnitAttach', function(call, unit)
                local callId = getCadDispatchCallId(call)
                if callId == nil or type(unit) ~= "table" then
                    return
                end

                local calloutEntry = cadDispatchCallouts[tostring(callId)]
                if calloutEntry == nil then
                    return
                end

                if pluginConfig.clearRecordsAfter ~= 0 and os.time() - calloutEntry.timestamp >= (pluginConfig.clearRecordsAfter * 60) then
                    cadDispatchCallouts[tostring(callId)] = nil
                    return
                end

                local playerSource = tonumber(GetSourceByCadIdentity(GetUnitIdentityValues(unit)))
                if playerSource == nil or playerSource <= 0 then
                    ersFailure("assign CAD unit", "The attached CAD unit is not currently in game")
                    warnLog("ERS_OFFER_FAILED", ("ERS callout %s was attached to a CAD unit that is not currently in game."):format(calloutEntry.calloutId))
                    return
                end

                local playerIdentity = getStablePlayerIdentity(playerSource, unit)
                if playerIdentity == nil then
                    ersFailure("assign CAD unit", "The player has no matching CAD identity")
                    warnLog("ERS_OFFER_FAILED", ("ERS callout %s was attached to a player without a matching CAD identity."):format(calloutEntry.calloutId))
                    return
                end

                local requestedAt = calloutEntry.requestedIdentities[playerIdentity]
                if calloutEntry.acceptedIdentities[playerIdentity] or
                    (requestedAt and os.time() - requestedAt < 30) then
                    return
                end
                -- A lost ERS offer can be retried if CAD sends another attachment update later.
                calloutEntry.requestedIdentities[playerIdentity] = os.time()

                CreateThread(function()
                    if GetResourceState('night_ers') ~= 'started' then
                        calloutEntry.requestedIdentities[playerIdentity] = nil
                        ersFailure("assign CAD unit", "night_ers stopped before the callout offer")
                        errorLog("ERS_RESOURCE_NOT_STARTED", "Could not assign the CAD unit to ERS because night_ers is not started.")
                        return
                    end

                    local requestOk, offerResult, reason = pcall(function()
                        return exports['night_ers']:SendCalloutOfferToPlayer(playerSource, calloutEntry.calloutId)
                    end)
                    if not requestOk then
                        calloutEntry.requestedIdentities[playerIdentity] = nil
                        ersFailure("assign CAD unit", offerResult)
                        errorLog("ERS_OFFER_FAILED", ("Failed to assign player %s to ERS callout %s: %s"):format(
                            playerSource,
                            calloutEntry.calloutId,
                            tostring(offerResult)
                        ))
                        return
                    end

                    if offerResult == false then
                        calloutEntry.requestedIdentities[playerIdentity] = nil
                        ersFailure("assign CAD unit", "night_ers declined the callout offer: " .. tostring(reason or "no reason returned"))
                        warnLog("ERS_OFFER_FAILED", ("night_ers did not assign player %s to callout %s: %s"):format(
                            playerSource,
                            calloutEntry.calloutId,
                            tostring(reason or "no reason returned")
                        ))
                        return
                    end

                    debugLog(("Requested ERS callout %s for CAD-attached player %s."):format(calloutEntry.calloutId, playerSource))
                end)
            end)

            AddEventHandler('SonoranCAD::pushevents:DispatchEvent', function(call)
                if type(call) ~= "table" or call.dispatch_type ~= "CALL_CLOSE" then
                    return
                end

                local callId = getCadDispatchCallId(call)
                if callId ~= nil then
                    cadDispatchCallouts[tostring(callId)] = nil
                end
            end)
        end
        --[[
            CALLOUT, PED AND VEHICLE DATA CREATION
        ]]
        AddEventHandler('SonoranCAD::ErsIntegration::BuildChars', function(pedData)
            if not isReady() then return end
            ersHealth.counters.characters = ersHealth.counters.characters + 1
            if type(pedData) ~= "table" then
                ersFailure("character record", "ERS character payload was malformed")
                errorLog("ERS_PAYLOAD_MALFORMED", "ERS character payload was malformed.")
                return
            end
            if not requireRecordConfig("character record", {"civilianRecordID", "civilianValues", "licenseRecordId", "licenseTypeField", "licenseTypeConfigs", "licenseRecordValues", "warrantRecordID", "warrantDescription", "warrantFlags"}) then return end

            local uniqueKey = generateUniquePedDataKey(pedData)
            if processedPedData[uniqueKey] then
                local entry   = processedPedData[uniqueKey]
                local ageSecs = os.time() - entry.timestamp
                local expiry = entry.id == nil and 5 or pluginConfig.clearRecordsAfter
                if expiry ~= 0 and ageSecs >= (expiry * 60) then
                    debugLog(("Expiring character data %s after %d minutes."):format(uniqueKey, expiry))
                    processedPedData[uniqueKey] = nil
                end
            end
            if processedPedData[uniqueKey] then
                debugLog("Ped " .. safeString(pedData.FirstName, "unknown") .. " " .. safeString(pedData.LastName, "unknown") .. " already processed.")
                return
            end
            processedPedData[uniqueKey] = {timestamp = os.time(), pending = true}
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
            local characterResponse = callCad("character record", CadApiCreateRecord, data)
            if characterResponse.success and characterResponse.recordId ~= nil then
                local recordId = characterResponse.recordId
                processedPedData[uniqueKey] = {id = recordId, timestamp = os.time()}
                ersSuccess("character record")
                debugLog("Record ID " .. recordId .. " saved for unique key: " .. uniqueKey)
            elseif characterResponse.success then
                processedPedData[uniqueKey] = {timestamp = os.time()}
                ersFailure("character record", "CAD returned success without a record ID")
                warnLog("ERS_RECORD_ID_INVALID", "CAD created an ERS character record without returning its ID. Repeat lookups are suppressed for five minutes to avoid duplicates.")
            else
                processedPedData[uniqueKey] = nil
                CadApiLogFailure("CREATE_RECORD", characterResponse, data)
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
                    local response = callCad("license record", CadApiCreateRecord, licenseData)
                    if not response.success then
                        CadApiLogFailure("CREATE_RECORD", response, licenseData)
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
                local response = callCad("warrant record", CadApiCreateRecord, boloData)
                if not response.success then
                    CadApiLogFailure("CREATE_RECORD", response, boloData)
                end
            end
        end)
        AddEventHandler('SonoranCAD::ErsIntegration::BuildVehs', function(vehData)
            if not isReady() then return end
            ersHealth.counters.vehicles = ersHealth.counters.vehicles + 1
            if type(vehData) ~= "table" then
                ersFailure("vehicle record", "ERS vehicle payload was malformed")
                errorLog("ERS_PAYLOAD_MALFORMED", "ERS vehicle payload was malformed.")
                return
            end
            if not requireRecordConfig("vehicle record", {"vehicleRegistrationRecordID", "vehicleRegistrationValues", "boloRecordID", "boloRecordValues"}) then return end

            local uniqueKey = generateUniqueVehDataKey(vehData)
            if processedVehData[uniqueKey] then
                local entry   = processedVehData[uniqueKey]
                local ageSecs = os.time() - entry.timestamp
                local expiry = entry.id == nil and 5 or pluginConfig.clearRecordsAfter
                if expiry ~= 0 and ageSecs >= (expiry * 60) then
                    debugLog(("Expiring vehicle data %s after %d minutes."):format(uniqueKey, expiry))
                    processedVehData[uniqueKey] = nil
                end
            end
            if processedVehData[uniqueKey] then
                debugLog("Vehicle " .. safeString(vehData.model, "unknown") .. " " .. safeString(vehData.license_plate, "unknown") .. " already processed.")
                return
            end
            processedVehData[uniqueKey] = {timestamp = os.time(), pending = true}
            local data = {
                ['user'] = '00000000-0000-0000-0000-000000000000',
                ['useDictionary'] = true,
                ['recordTypeId'] = pluginConfig.customRecords.vehicleRegistrationRecordID,
            }
            if pluginConfig.clearRecordsAfter ~= 0 then
                data.deleteAfterMinutes = pluginConfig.clearRecordsAfter
            end
            data.replaceValues = generateReplaceValues(vehData, pluginConfig.customRecords.vehicleRegistrationValues)
            local recordResponse = callCad("vehicle record", CadApiCreateRecord, data)
            if recordResponse.success and recordResponse.recordId ~= nil then
                local recordId = recordResponse.recordId
                processedVehData[uniqueKey] = {id = recordId, timestamp = os.time()}
                ersSuccess("vehicle record")
                debugLog("Record ID " .. recordId .. " saved for unique key: " .. uniqueKey)
            elseif recordResponse.success then
                processedVehData[uniqueKey] = {timestamp = os.time()}
                ersFailure("vehicle record", "CAD returned success without a record ID")
                warnLog("ERS_RECORD_ID_INVALID", "CAD created an ERS vehicle record without returning its ID. Repeat lookups are suppressed for five minutes to avoid duplicates.")
            else
                processedVehData[uniqueKey] = nil
                CadApiLogFailure("CREATE_RECORD", recordResponse, data)
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
                local response = callCad("vehicle BOLO", CadApiCreateRecord, boloData)
                if not response.success then
                    CadApiLogFailure("CREATE_RECORD", response, boloData)
                end
            end
        end)
        syncCatalog = function()
            catalogGeneration = catalogGeneration + 1
            local generation = catalogGeneration
            ersHealth.catalog.status = "waiting for night_ers callouts"
            ersHealth.catalog.attempts = 0
            CreateThread(function()
                -- ERS can report no callouts briefly after its resource starts.
                local attempt = 0
                local emptyPublished = false
                while generation == catalogGeneration do
                    attempt = attempt + 1
                    Wait(attempt == 1 and 1000 or (attempt <= 6 and 2000 or 30000))
                    if generation ~= catalogGeneration or not isReady() then return end
                    ersHealth.catalog.attempts = attempt
                    local ok, calloutData = pcall(function() return exports.night_ers:getCallouts() end)
                    if ok and type(calloutData) == "table" then
                        local list = {}
                        for uid, callout in pairs(calloutData) do
                            if type(callout) == "table" then
                                local copy = {}
                                for key, value in pairs(callout) do copy[key] = value end
                                copy.CalloutDescriptions = type(callout.CalloutDescriptions) == "table" and
                                    {callout.CalloutDescriptions[1]} or {}
                                if copy.CalloutDescriptions[1] == nil then copy.CalloutDescriptions = {} end
                                copy.CalloutLocations = {}
                                if type(copy.PedWeaponData) ~= "table" then copy.PedWeaponData = {} end
                                list[#list + 1] = {id = uid, data = copy}
                            else
                                warnLog("ERS_PAYLOAD_MALFORMED", "Skipping malformed ERS callout with id: " .. tostring(uid))
                            end
                        end
                        ersHealth.catalog.count = #list
                        if #list > 0 or (attempt >= 6 and not emptyPublished) then
                            local data = {serverId = tonumber(Config.serverId), callouts = list}
                            local uploadOk, response = pcall(CadApiSetAvailableCallouts, data)
                            if uploadOk and type(response) == "table" and response.success then
                                ersHealth.catalog.status = #list > 0 and "synced to CAD" or "no callouts configured in night_ers"
                                ersHealth.catalog.syncedAt = os.date('!%Y-%m-%dT%H:%M:%SZ')
                                ersSuccess("callout catalog")
                                debugLog(('ERS callout catalog synced to CAD (%d entries).'):format(#list))
                                if #list > 0 then return end
                                emptyPublished = true
                            else
                                local reason = uploadOk and CadApiReasonText(response and response.reason) or tostring(response)
                                ersHealth.catalog.status = "CAD catalog upload failed"
                                ersFailure("callout catalog", reason)
                                if uploadOk then CadApiLogFailure('SET_AVAILABLE_CALLOUTS', response, data) end
                            end
                        end
                    else
                        ersHealth.catalog.status = "night_ers getCallouts failed"
                        ersFailure("callout catalog", ok and "getCallouts returned invalid data" or calloutData)
                    end
                    if attempt == 6 and not emptyPublished then
                        errorLog("ERS_CATALOG_FAILED", "ERS callouts have not synced after six attempts; retrying every 30 seconds. Run 'sonorancad ers' for the current failure.")
                    end
                end
            end)
        end
        --[[
            PUSH EVENT HANDLER
        ]]
        TriggerEvent('SonoranCAD::RegisterPushEvent', 'EVENT_NEW_CALLOUT', function(data)
            if type(data) ~= "table" or type(data.data) ~= "table" or type(data.data.callout) ~= "table" or type(data.data.callout.data) ~= "table" then
                ersFailure("CAD callout", "CAD push payload was malformed")
                errorLog("ERS_PAYLOAD_MALFORMED", "Push event callout payload was malformed.")
                return
            end

            local calloutData = data.data
            local locations = asTable(calloutData.callout.data.CalloutLocations)
            local firstLocation = locations and locations[1]
            local coords = getCoordinates(firstLocation)
            if coords == nil then
                ersFailure("CAD callout", "CAD push had no valid location")
                errorLog("ERS_COORDS_MISSING", "Push event callout was missing a valid location.")
                return
            end

            calloutData.callout.data.CalloutLocations = {[1] = vector3(coords.x, coords.y, 41.0)}
            if not isReady() then
                ersFailure("CAD callout", "night_ers is not ready")
                errorLog("ERS_RESOURCE_NOT_STARTED", "CAD callout could not be created because night_ers is not ready.")
                return
            end
            ersHealth.counters.cadCallouts = ersHealth.counters.cadCallouts + 1
            local createOk, calloutID = pcall(function() return exports.night_ers:createCallout(calloutData.callout) end)
            if not createOk then
                ersFailure("CAD callout", calloutID)
                errorLog("ERS_CALLOUT_CREATE_FAILED", "night_ers createCallout export failed: " .. tostring(calloutID))
                return
            end
            if type(calloutID) == "table" and calloutID.calloutId then
                calloutData.callout.newId = calloutID.calloutId
                ersSuccess("CAD callout")
                TriggerClientEvent('ErsIntegration::BuildCallout', -1, calloutData.callout)
                debugLog("Callout " .. calloutID.calloutId .. " created.")
                TriggerClientEvent('SonoranCAD::ErsIntegration::RequestCallout', -1, calloutID.calloutId)
            else
                ersFailure("CAD callout", "night_ers did not return a callout ID")
                errorLog("ERS_CALLOUT_CREATE_FAILED", "night_ers did not return a callout ID for the CAD callout.")
            end
        end)
        handlersRegistered = true
        syncCatalog()
    end
    if GetResourceState('night_ers') == 'started' then
        debugLog("night ERS resource is started.")
        startErs()
    else
        ersHealth.status = "night_ers is not started; start it to initialize ERS integration"
        ersFailure("startup", ersHealth.status)
        errorLog("ERS_RESOURCE_NOT_STARTED", ersHealth.status)
    end
    AddEventHandler('onResourceStart', function(resourceName)
        if resourceName == 'night_ers' then
            debugLog("night ERS resource started.")
            startErs()
        end
    end)
    AddEventHandler('onResourceStop', function(resourceName)
        if resourceName == 'night_ers' then
            catalogGeneration = catalogGeneration + 1
            ersHealth.ready = false
            ersHealth.status = "night_ers stopped; waiting for restart"
            ersHealth.catalog.status = "night_ers stopped"
            ersFailure("runtime", "night_ers stopped")
        end
    end)
end
