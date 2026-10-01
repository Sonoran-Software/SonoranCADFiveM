-- Run from the repository root with Lua 5.4 or newer.
local events, pushEvents, threads, errors, uploads = {}, {}, {}, {}, {}
local recordFailures = {}
local state = 'started'
local exportCalls, handlerRegistrations = 0, 0
local plugin = {enabled = true, create911Call = true, createEmergencyCall = false, clearRecordsAfter = 30}
local nightErs = {}

function nightErs:getCallouts()
    exportCalls = exportCalls + 1
    if exportCalls == 1 then error('callouts are still loading') end
    return {armed = {CalloutName = 'Armed suspect', CalloutDescriptions = {'First', 'Second'}, CalloutLocations = {{x = 1, y = 2}}}}
end
function nightErs:createCallout(callout)
    assert(callout.data.CalloutLocations[1].x == 10)
    return {calloutId = 55}
end

local env = setmetatable({}, {__index = _G})
env.Config = {serverId = 1, GetPluginConfig = function(name)
    return name == 'ersintegration' and plugin or {enabled = false}
end}
env.GetResourceState = function() return state end
env.GetResourceMetadata = function() return '1.8.16' end
env.compareVersions = function() return {result = false} end
env.RegisterNetEvent = function() end
env.AddEventHandler = function(name, handler)
    handlerRegistrations = handlerRegistrations + 1
    events[name] = handler
end
env.TriggerEvent = function(name, eventName, handler)
    assert(name == 'SonoranCAD::RegisterPushEvent')
    pushEvents[eventName] = handler
end
env.TriggerClientEvent = function() end
env.CreateThread = function(handler) threads[#threads + 1] = handler end
env.Wait = function() end
env.debugLog = function() end
env.warnLog = function() end
env.errorLog = function(code, message) errors[#errors + 1] = {code, message} end
env.exports = {night_ers = nightErs}
env.vector3 = function(x, y, z) return {x = x, y = y, z = z} end
env.CadApiSetAvailableCallouts = function(data)
    uploads[#uploads + 1] = data
    if #uploads == 1 then return {success = false, reason = 'CAD starting'} end
    return {success = true}
end
env.CadApiLogFailure = function(name) recordFailures[#recordFailures + 1] = name end
env.CadApiCreateEmergencyCall = function() return {success = true, callId = 42} end
env.CadApiReasonText = function(reason) return tostring(reason) end
env.json = {encode = function() return '{}' end}

assert(loadfile('sonorancad/submodules/ersintegration/sv_ersintegration.lua', 't', env))()
assert(env.GetErsIntegrationDiagnostics().ready)
assert(env.GetErsIntegrationDiagnostics().features.create911Call)
assert(not env.GetErsIntegrationDiagnostics().features.createDispatchCallOnAcceptance)
assert(#threads == 1)
threads[1]()
assert(exportCalls == 3, 'catalog should retry a throwing ERS export and CAD failure')
assert(#uploads == 2 and #uploads[2].callouts == 1, 'catalog should sync once ready')
assert(uploads[2].callouts[1].data.CalloutDescriptions[1] == 'First')
assert(env.GetErsIntegrationDiagnostics().catalog.status == 'synced to CAD')

pushEvents.EVENT_NEW_CALLOUT({data = {callout = {data = {
    CalloutLocations = {{x = 10, y = 20, z = 30}}
}}}})
assert(env.GetErsIntegrationDiagnostics().counters.cadCallouts == 1, 'table coordinates should create the CAD callout')

local registrations = handlerRegistrations
events.onResourceStop('night_ers')
state = 'stopped'
assert(not env.GetErsIntegrationDiagnostics().ready)
events['ErsIntegration::OnIsOfferedCallout']({Coordinates = {x = 1, y = 2}})
assert(env.GetErsIntegrationDiagnostics().counters.offered == 0, 'events should not run while ERS is stopped')
state = 'started'
events.onResourceStart('night_ers')
assert(handlerRegistrations == registrations, 'resource restart must not register duplicate handlers')
assert(#threads == 2, 'resource restart should resync the catalog')
threads[2]()
assert(#uploads == 3)
assert(env.GetErsIntegrationDiagnostics().ready)
assert(env.GetErsIntegrationDiagnostics().lastFailure.resolvedAt, 'restart should mark the stop failure resolved')
assert(#errors == 0, 'unexpected ERS errors')
events['SonoranCAD::ErsIntegration::BuildChars']({FirstName = 'Test'})
assert(errors[#errors][1] == 'ERS_CONFIG_INVALID', 'missing record config should produce an actionable error')
plugin.customRecords = {
    vehicleRegistrationRecordID = 5,
    vehicleRegistrationValues = {plate = 'license_plate'},
    boloRecordID = 6,
    boloRecordValues = {}
}
env.CadApiCreateRecord = function() return {success = false, status = 409, reason = 'duplicate plate'} end
events['SonoranCAD::ErsIntegration::BuildVehs']({license_plate = 'TEST123', model = 'sedan'})
assert(recordFailures[#recordFailures] == 'CREATE_RECORD', 'record failures must use the request name recognized by CAD error classification')
assert(env.GetErsIntegrationDiagnostics().lastFailure.reason:find('check unique fields', 1, true), '409 should explain the record template conflict')
plugin.enabled = false
assert(not env.GetErsIntegrationDiagnostics().ready, 'late config disable must be reflected in diagnostics')
plugin.enabled = true

local oldEnv = setmetatable({
    GetResourceMetadata = function() return '1.8.15' end,
    compareVersions = function() return {result = true} end,
    CreateThread = function() error('outdated ERS must not start catalog sync') end,
    errorLog = function(code) assert(code == 'ERS_VERSION_TOO_OLD') end
}, {__index = env})
assert(loadfile('sonorancad/submodules/ersintegration/sv_ersintegration.lua', 't', oldEnv))()
assert(not oldEnv.GetErsIntegrationDiagnostics().ready, 'outdated ERS must be blocked')
print('ERS reliability tests passed')
