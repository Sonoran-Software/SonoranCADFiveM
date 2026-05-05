--[[
    Sonaran CAD Plugins

    Plugin Name: trafficstop
    Creator: SonoranCAD
    Description: Implements ts command
]]
CreateThread(function() Config.LoadPlugin("localcallers", function(pluginConfig)
    if pluginConfig.enabled then
        RegisterNetEvent("SonoranCAD::localcallers:Call911", function(street, message, coords)
            if street == '' then
                street = 'Unknown'
            end
            local postal = "Unknown"
            if isPluginLoaded("postals") then
                postal = getPostalFromVector3(coords)
            else
                postal = "Unknown"
            end
            local data = {
                ['serverId'] = tonumber(Config.serverId),
                ['isEmergency'] = true,
                ['caller'] = pluginConfig.language.caller,
                ['location'] = street,
                ['description'] = message,
                ['metaData'] = {
                    ['callerPlayerId'] = source,
                    ['callerCommunityUserId'] = GetPlayerCommunityUserId(source),
                    ['callerApiId'] = GetIdentifiers(source)[Config.primaryIdentifier],
                    ['postal'] = postal
                }
            }
            if pluginConfig.clearRecordsAfter ~= 0 then
                data.deleteAfterMinutes = pluginConfig.clearRecordsAfter
            end
            if LocationCache[source] ~= nil then
                data['metaData']['x'] = tostring(LocationCache[source].coordinates.x)
                data['metaData']['y'] = tostring(LocationCache[source].coordinates.y)
                data['metaData']['z'] = tostring(LocationCache[source].coordinates.z)
            elseif type(coords) == "vector3" then
                data['metaData']['x'] = tostring(coords.x)
                data['metaData']['y'] = tostring(coords.y)
                data['metaData']['z'] = tostring(coords.z)
            else
                debugLog("Warning: location cache was nil, not sending position")
            end
            debugLog(("perform local caller request %s"):format(json.encode(data)))
            local response = CadApiCreateEmergencyCall(data)
            if response.success then
                debugLog(json.encode(response.data or {}))
            else
                CadApiLogFailure("CALL_911", response, data)
            end
        end)
    end
end) end)
