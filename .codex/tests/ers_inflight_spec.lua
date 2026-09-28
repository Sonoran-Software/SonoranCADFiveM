-- Run from the repository root with Lua 5.4 or newer.
local events = {}
local offeredRequests, dispatchRequests, attachRequests, recordRequests = 0, 0, 0, 0
local plugin = {
    enabled = true, create911Call = true, createEmergencyCall = true,
    autoAddCall = true, clearRecordsAfter = 30, callPriority = 2,
    customRecords = {vehicleRegistrationRecordID = 5, vehicleRegistrationValues = {plate = 'license_plate'},
        boloRecordID = 6, boloRecordValues = {}}
}
local env = setmetatable({source = 1}, {__index = _G})
env.Config = {serverId = 1, GetPluginConfig = function(name)
    return name == 'ersintegration' and plugin or {enabled = false}
end}
env.GetResourceState = function() return 'started' end
env.GetResourceMetadata = function() return '1.8.16' end
env.compareVersions = function() return {result = false} end
env.RegisterNetEvent = function() end
env.AddEventHandler = function(name, handler) events[name] = handler end
env.TriggerEvent = function() end
env.CreateThread = function() end
env.debugLog = function() end
env.warnLog = function() end
env.errorLog = function(_, message) error(message) end
env.getPlayerCadStatus = function(player)
    return {success = true, hasLink = true, hasUnit = true, link = 'unit-' .. player}
end
env.CadApiReasonText = function(reason) return tostring(reason) end
env.CadApiLogFailure = function(_, response) error(tostring(response.reason)) end

local callout = {calloutId = 42, CalloutName = 'Traffic stop', StreetName = 'Test street',
    Coordinates = {x = 100, y = 200, z = 30}}
env.CadApiCreateEmergencyCall = function()
    offeredRequests = offeredRequests + 1
    if offeredRequests == 1 then events['ErsIntegration::OnIsOfferedCallout'](callout) end
    return {success = true, callId = 123}
end
env.CadApiCreateDispatchCall = function()
    dispatchRequests = dispatchRequests + 1
    if dispatchRequests == 1 then
        env.source = 2
        events['ErsIntegration::OnAcceptedCalloutOffer'](callout)
        env.source = 1
    end
    return {success = true, callId = 456}
end
env.CadApiAttachUnitsToDispatchCall = function(data)
    attachRequests = attachRequests + 1
    assert(data.callId == 456 and data.communityUserIds[1] == 'unit-2')
    return {success = true}
end
env.CadApiDeleteEmergencyCall = function() return {success = true} end
env.CadApiCreateRecord = function()
    recordRequests = recordRequests + 1
    if recordRequests == 1 then
        events['SonoranCAD::ErsIntegration::BuildVehs']({license_plate = 'TEST123', model = 'sedan'})
    end
    return {success = true, recordId = 789}
end

assert(loadfile('sonorancad/submodules/ersintegration/sv_ersintegration.lua', 't', env))()
events['ErsIntegration::OnIsOfferedCallout'](callout)
assert(offeredRequests == 1, 'duplicate offered events must share one in-flight CAD call')
events['ErsIntegration::OnAcceptedCalloutOffer'](callout)
assert(dispatchRequests == 1, 'concurrent acceptance must share one dispatch call')
assert(attachRequests == 1, 'second accepting unit must be attached after dispatch creation')
events['SonoranCAD::ErsIntegration::BuildVehs']({license_plate = 'TEST123', model = 'sedan'})
assert(recordRequests == 1, 'duplicate vehicle events must share one in-flight record')
print('ERS in-flight deduplication tests passed')
