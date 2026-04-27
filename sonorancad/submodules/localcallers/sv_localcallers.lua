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
                ['serverId'] = Config.serverId,
                ['isEmergency'] = true,
                ['caller'] = pluginConfig.language.caller,
                ['location'] = street,
                ['description'] = message,
                ['metaData'] = {
                    ['callerPlayerId'] = source,
                    ['callerApiId'] = GetIdentifiers(source)[Config.primaryIdentifier],
                    ['postal'] = postal
                }
            }
            if pluginConfig.clearRecordsAfter ~= 0 then
                data.deleteAfterMinutes = pluginConfig.clearRecordsAfter
            end
            if LocationCache[source] ~= nil then
                data['metaData']['x'] = LocationCache[source].coordinates.x
                data['metaData']['y'] = LocationCache[source].coordinates.y
                data['metaData']['z'] = LocationCache[source].coordinates.z
            elseif type(coords) == "vector3" then
                data['metaData']['x'] = coords.x
                data['metaData']['y'] = coords.y
                data['metaData']['z'] = coords.z
            else
                debugLog("Warning: location cache was nil, not sending position")
            end
            debugLog("sending call!")
            performApiRequest({data}, 'CALL_911', function(response)
            end)
        end)
    end
end) end)