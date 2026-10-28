-- Run from the repository root with Lua 5.4 or newer.
local function harness(initialState)
    local events, threads, records, uploads, errors = {}, {}, {}, {}, {}
    local state = initialState
    local registrations = 0
    local plugin = {
        enabled = true, create911Call = false, createEmergencyCall = false, clearRecordsAfter = 30,
        customRecords = {
            civilianRecordID = 7, civilianValues = {first = 'FirstName', last = 'LastName'},
            licenseRecordId = 4, licenseTypeField = 'licenseType', licenseTypeConfigs = {}, licenseRecordValues = {},
            warrantRecordID = 8, warrantDescription = 'description', warrantFlags = 'flags',
            vehicleRegistrationRecordID = 5, vehicleRegistrationValues = {plate = 'license_plate'},
            boloRecordID = 6, boloRecordValues = {}
        }
    }
    local env = setmetatable({}, {__index = _G})
    env.Config = {serverId = 1, GetPluginConfig = function(name)
        return name == 'ersintegration' and plugin or {enabled = false}
    end}
    env.GetResourceState = function() return state end
    env.GetResourceMetadata = function() return '1.8.16' end
    env.compareVersions = function() return {result = false} end
    env.RegisterNetEvent = function() end
    env.AddEventHandler = function(name, handler)
        registrations = registrations + 1
        events[name] = events[name] or {}
        table.insert(events[name], handler)
    end
    env.TriggerEvent = function() end
    env.CreateThread = function(handler) threads[#threads + 1] = handler end
    env.Wait = function() end
    env.debugLog = function() end
    env.warnLog = function(_, message) error(message) end
    env.errorLog = function(code, message) errors[#errors + 1] = {code = code, message = message} end
    env.exports = {night_ers = {getCallouts = function()
        return {traffic = {CalloutName = 'Traffic stop', CalloutDescriptions = {'Test callout'}}}
    end}}
    env.CadApiSetAvailableCallouts = function(data)
        uploads[#uploads + 1] = data
        return {success = true}
    end
    env.CadApiCreateRecord = function(data)
        records[#records + 1] = data
        return {success = true, recordId = #records}
    end
    env.CadApiLogFailure = function(_, response) error(tostring(response.reason)) end
    env.CadApiReasonText = tostring

    local function emit(name, ...)
        for _, handler in ipairs(events[name] or {}) do handler(...) end
    end
    assert(loadfile('sonorancad/submodules/ersintegration/sv_ersintegration.lua', 't', env))()
    return {
        health = env.GetErsIntegrationDiagnostics,
        emit = emit,
        setState = function(value) state = value end,
        registrations = function() return registrations end,
        pendingThreads = function() return #threads end,
        runCatalog = function()
            assert(#threads > 0, 'successful startup should schedule the callout catalog')
            table.remove(threads, 1)()
        end,
        start = function()
            -- FiveM emits onResourceStart synchronously while the resource is still starting.
            state = 'starting'
            emit('onResourceStart', 'night_ers')
            assert(not env.GetErsIntegrationDiagnostics().ready, 'starting ERS must not initialize early')
            -- onServerResourceStart is queued after the resource has entered the started state.
            state = 'started'
            emit('onServerResourceStart', 'night_ers')
        end,
        records = records, uploads = uploads, errors = errors
    }
end

local ped = {uniqueId = 'ped-1', FirstName = 'Test', LastName = 'Person', Address = 'Main St'}
local vehicle = {license_plate = 'TEST123', model = 'sedan'}
local function interact(test)
    test.emit('SonoranCAD::ErsIntegration::BuildChars', ped)
    test.emit('SonoranCAD::ErsIntegration::BuildVehs', vehicle)
end

-- server.cfg executes @sonorancad/sonorancad.cfg (which starts CAD), then starts night_ers.
local delayed = harness('stopped')
assert(not delayed.health().ready and delayed.health().catalog.attempts == 0)
assert(delayed.errors[1].code == 'ERS_RESOURCE_NOT_STARTED')
delayed.emit('onResourceStart', 'unrelated')
delayed.emit('onServerResourceStart', 'unrelated')
assert(not delayed.health().ready and delayed.health().catalog.attempts == 0,
    'unrelated resource starts must not initialize ERS')
delayed.start()
assert(delayed.health().nightErsState == 'started' and delayed.health().ready,
    'ERS started after CAD must become ready after its queued start event')
delayed.runCatalog()
assert(delayed.health().catalog.status == 'synced to CAD' and #delayed.uploads == 1)
delayed.emit('onServerResourceStart', 'night_ers')
assert(delayed.pendingThreads() == 0 and #delayed.uploads == 1,
    'a duplicate queued start must not restart a completed catalog sync')
interact(delayed)
assert(#delayed.records == 2, 'late ERS startup must allow new civilian and vehicle records')
assert(delayed.records[1].recordTypeId == 7 and delayed.records[1].replaceValues.first == 'Test')
assert(delayed.records[2].recordTypeId == 5 and delayed.records[2].replaceValues.plate == 'TEST123')
interact(delayed)
assert(#delayed.records == 2, 'repeated interactions must reuse records before a restart')

local registrations = delayed.registrations()
delayed.setState('stopped')
delayed.emit('onResourceStop', 'night_ers')
interact(delayed)
assert(not delayed.health().ready and #delayed.records == 2, 'stopped ERS must not create records')
delayed.start()
assert(delayed.health().ready, 'queued resource restart must restore readiness')
assert(delayed.registrations() == registrations, 'restart must not register duplicate handlers')
delayed.runCatalog()
assert(#delayed.uploads == 2, 'restart must resync the callout catalog')
interact(delayed)
assert(#delayed.records == 4, 'restart must clear civilian and vehicle deduplication caches')
assert(delayed.health().counters.characters == 3 and delayed.health().counters.vehicles == 3)

local immediate = harness('started')
assert(immediate.health().ready, 'ERS already started before CAD must initialize immediately')
assert(#immediate.errors == 0, 'already-started ERS should not log startup errors')
immediate.runCatalog()
interact(immediate)
assert(#immediate.uploads == 1 and #immediate.records == 2)
local immediateRegistrations = immediate.registrations()
immediate.emit('onServerResourceStart', 'unrelated')
assert(immediate.health().ready and immediate.registrations() == immediateRegistrations)
immediate.emit('onServerResourceStart', 'night_ers')
interact(immediate)
assert(#immediate.records == 2, 'a queued start after initial startup must preserve record caches')
assert(immediate.registrations() == immediateRegistrations,
    'a queued start after initial startup must not register duplicate handlers')
assert(immediate.pendingThreads() == 0 and #immediate.uploads == 1,
    'a queued start after initial startup must not schedule another catalog sync')
print('ERS startup ordering tests passed')
