-- Run from the repository root with Lua 5.4 or newer.
-- Exercise actual ERS event handlers with FiveM-style throwing export lookups.
local passed = 0
local failed = 0

local function runCase(name, resource, expected, suppliedPostal, enabled)
    for _, event in ipairs({'ErsIntegration::OnIsOfferedCallout', 'ErsIntegration::OnAcceptedCalloutOffer'}) do
        local ok, err = pcall(function()
            local events, calls = {}, {}
            local plugin = {enabled = true, create911Call = true, createEmergencyCall = true,
                clearRecordsAfter = 30, callPriority = 2, callCodes = {}}
            local postals = {enabled = enabled ~= false, nearestPostalResourceName = 'nearest-postal'}
            local env = setmetatable({source = 1}, {__index = _G})
            local coords = {x = 100, y = 200, z = 30}
            env.type = function(value) return value == coords and 'vector3' or type(value) end
            env.Config = {serverId = 1, GetPluginConfig = function(name)
                return name == 'postals' and postals or plugin
            end}
            env.GetResourceState = function() return 'started' end
            env.GetResourceMetadata = function() return '1.8.16' end
            env.compareVersions = function() return {result = false} end
            env.RegisterNetEvent = function() end
            env.TriggerEvent = function() end
            env.AddEventHandler = function(name, handler) events[name] = handler end
            env.CreateThread = function() end -- Background catalog loading is unrelated.
            env.debugLog = function() end
            env.errorLog = function(_, message) error(message) end
            env.exports = {['nearest-postal'] = resource}
            env.getPlayerCadStatus = function() return {success = true, link = 'unit-1'} end
            env.CadApiCreateEmergencyCall = function(data)
                calls[#calls + 1] = data
                return {success = true, callId = 123}
            end
            env.CadApiCreateDispatchCall = env.CadApiCreateEmergencyCall
            assert(loadfile('sonorancad/submodules/ersintegration/sv_ersintegration.lua', 't', env))()
            events[event]({CalloutName = 'Traffic stop', calloutId = 42, StreetName = 'Test street',
                Description = 'Test call', Coordinates = coords, Postal = suppliedPostal})
            assert(#calls == 1, 'Expected one CAD call')
            local actual = calls[1].postal or calls[1].metaData.postal
            assert(actual == expected, 'Expected postal ' .. expected .. ', got ' .. tostring(actual))
            assert(calls[1].metaData.x == '100' and calls[1].metaData.y == '200', 'Lost call coordinates')
        end)
        if ok then
            passed = passed + 1
            print('PASS ' .. name .. ': ' .. event)
        else
            failed = failed + 1
            print('FAIL ' .. name .. ': ' .. event .. ': ' .. tostring(err))
        end
    end
end

local missingExport = setmetatable({}, {__index = function()
    error('No such export getPostalServer in resource nearest-postal')
end})
runCase('missing export', missingExport, 'Unknown postal')
runCase('export throws', {getPostalServer = function() error('resource stopped') end}, 'Unknown postal')
runCase('missing resource', nil, 'Unknown postal')
runCase('valid export', {getPostalServer = function(_, coords)
    assert(coords[1] == 100 and coords[2] == 200)
    return {code = 1234}
end}, '1234')
runCase('nil export result', {getPostalServer = function() return nil end}, 'Unknown postal')
runCase('malformed export result', {getPostalServer = function() return '1234' end}, 'Unknown postal')
runCase('missing postal code', {getPostalServer = function() return {} end}, 'Unknown postal')
runCase('supplied postal bypasses export', missingExport, '5678', '5678')
runCase('unknown postal falls back', missingExport, 'Unknown postal', 'Unknown postal')
runCase('disabled postals bypass export', missingExport, 'Unknown postal', nil, false)
assert(failed == 0, tostring(failed) .. ' failed; ' .. tostring(passed) .. ' passed')
print(tostring(passed) .. ' tests passed')
