--[[
    Sonaran CAD Plugins

    Plugin Name: ersintegration
    Creator: Sonoran Software
    Description: Integrates Knight ERS callouts to SonoranCAD
]]
CreateThread(function() Config.LoadPlugin("ersintegration", function(pluginConfig)
    if not pluginConfig.enabled then return end
    RegisterNetEvent('night_ers:ERS_GetPedDataFromServer_cb', function(_, data)
        if type(data) == "table" then
            TriggerServerEvent('SonoranCAD::ErsIntegration::BuildChars', data)
        else
            warnLog("ERS_PAYLOAD_MALFORMED", "night_ers returned invalid character data.")
        end
    end)
    RegisterNetEvent('night_ers:receiveVehicleInformation', function(_, data)
        if type(data) == "table" then
            TriggerServerEvent('SonoranCAD::ErsIntegration::BuildVehs', data)
        else
            warnLog("ERS_PAYLOAD_MALFORMED", "night_ers returned invalid vehicle data.")
        end
    end)
    RegisterNetEvent('SonoranCAD::ErsIntegration::RequestCallout', function(calloutID)
        if GetResourceState('night_ers') ~= 'started' then
            warnLog("ERS_RESOURCE_NOT_STARTED", "A CAD callout was offered, but night_ers is not started on this client.")
            return
        end
        local ok, serviceType, onShift = pcall(function()
            return exports['night_ers']:getPlayerActiveServiceType(), exports['night_ers']:getIsPlayerOnShift()
        end)
        if not ok then
            warnLog("ERS_OFFER_FAILED", "Could not check the player's ERS shift and service; update night_ers and check its client exports.")
            return
        end
        if not onShift or serviceType == nil then
            debugLog("ERS callout skipped because the player is not on an ERS shift with an active service type.")
            return
        end
        if calloutID ~= nil then
            TriggerServerEvent('night_ers:requestCallout', serviceType, calloutID)
        end
    end)
end) end)
