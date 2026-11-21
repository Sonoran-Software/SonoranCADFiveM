-- Run from the repository root with Lua 5.4 or newer.
local passed = 0
local function test(name, run)
    local ok, err = pcall(run)
    assert(ok, name .. ': ' .. tostring(err))
    passed = passed + 1
    print('PASS ' .. name)
end

local function loadPostals(options)
    options = options or {}
    local logs, reads, exports = {}, {}, {}
    local config = {enabled = true, mode = options.mode or 'resource',
        nearestPostalResourceName = options.name or 'nearest-postal', customPostalCodesFile = 'custom.json'}
    local env = setmetatable({}, {__index = _G})
    env.Config = {LoadPlugin = function(_, callback) callback(config) end,
        GetPluginConfig = function() return {} end}
    local threads = 0
    env.CreateThread = function(callback)
        threads = threads + 1
        if threads == 1 then callback() end -- Do not run the background API publisher.
    end
    env.GetResourceState = function() return options.state or 'started' end
    env.GetCurrentResourceName = function() return 'sonorancad' end
    env.GetResourcePath = function(name)
        if name == 'sonorancad' then return options.cadPath or '/resources/[sonorancad]/sonorancad' end
        return options.path or '/resources/[sonorancad]/nearest-postal'
    end
    env.GetResourceMetadata = function() return options.metadata end
    env.LoadResourceFile = function(resource, filename)
        assert(type(filename) == 'string', 'Native called with nil filename')
        reads[#reads + 1] = filename
        if options.unreadable then return nil end
        return '[]'
    end
    env.json = {decode = function() return {{x = 1, y = 2, code = '123'}} end}
    env.vec = function(x, y) return {x, y} end
    env.RegisterNetEvent = function() end
    env.AddEventHandler = function() end
    env.exports = function(name, callback) exports[name] = callback end
    local function log(key, message) logs[key] = message or true end
    env.warnLog, env.logError, env.errorLog = log, log, log
    env.getErrorText = function() return '%s' end
    assert(loadfile('sonorancad/submodules/postals/sv_postals.lua', 't', env))()
    return config, logs, reads, exports
end

test('missing metadata disables postals with an actionable error, not a native crash', function()
    local config, logs, reads = loadPostals()
    assert(not config.enabled and #reads == 0)
    assert(logs.POSTAL_CUSTOM_RESOURCE_FILE_ERROR:find('/resources/[sonorancad]/nearest-postal', 1, true))
    assert(logs.POSTAL_CUSTOM_RESOURCE_FILE_ERROR:find('duplicate', 1, true))
end)
test('empty metadata never reaches LoadResourceFile', function()
    local config, _, reads = loadPostals({metadata = '  '})
    assert(not config.enabled and #reads == 0)
end)
test('compatible external copy warns with both paths and still initializes', function()
    local config, logs, reads, exports = loadPostals({metadata = 'new-postals.json', path = '/resources/[scripts]/nearest-postal'})
    assert(config.enabled and #reads == 1 and exports.cadGetNearestPostal)
    assert(logs.POSTAL_RESOURCE_EXTERNAL_PATH:find('/resources/[scripts]/nearest-postal', 1, true))
    assert(logs.POSTAL_RESOURCE_EXTERNAL_PATH:find('/resources/[sonorancad]/nearest-postal', 1, true))
end)
test('bundled copy initializes without an external-path warning', function()
    local config, logs, _, exports = loadPostals({metadata = 'new-postals.json'})
    assert(config.enabled and exports.cadGetNearestPostal and not logs.POSTAL_RESOURCE_EXTERNAL_PATH)
end)
test('Windows and repeated path separators are normalized', function()
    local _, logs = loadPostals({metadata = 'new-postals.json', cadPath = 'C:\\resources\\[cad]\\sonorancad\\', path = 'C:/resources//[cad]/nearest-postal/'})
    assert(not logs.POSTAL_RESOURCE_EXTERNAL_PATH)
end)
test('explicit custom resource names do not trigger bundled-path assumptions', function()
    local config, logs = loadPostals({metadata = 'custom.json', name = 'my-postals', path = '/resources/custom/my-postals'})
    assert(config.enabled and not logs.POSTAL_RESOURCE_EXTERNAL_PATH)
end)
test('file mode does not require resource metadata or path checks', function()
    local config, logs = loadPostals({mode = 'file', path = '/elsewhere/nearest-postal'})
    assert(config.enabled and not logs.POSTAL_RESOURCE_EXTERNAL_PATH)
end)
test('unreadable postal file produces the registered error', function()
    local config, logs = loadPostals({metadata = 'missing.json', unreadable = true})
    assert(not config.enabled and logs.POSTAL_CUSTOM_RESOURCE_FILE_ERROR)
end)
test('missing custom file uses the existing registered error', function()
    local config, logs = loadPostals({mode = 'file', unreadable = true})
    assert(not config.enabled and logs.CUSTOM_POSTALS_FILE_NOT_FOUND)
end)

for _, lookup in ipairs({false, function() return nil end, function() return '123' end}) do
    test('local caller reaches CAD when postal lookup is ' .. tostring(lookup), function()
        local handler, sent
        local env = setmetatable({source = 1, LocationCache = {}}, {__index = _G})
        env.Config = {serverId = 1, primaryIdentifier = 'license', LoadPlugin = function(_, callback)
            callback({enabled = true, clearRecordsAfter = 0, language = {caller = 'Caller'}})
        end}
        env.CreateThread = function(callback) callback() end
        env.RegisterNetEvent = function(_, callback) handler = callback end
        env.isPluginLoaded = function() return true end
        env.getPostalFromVector3 = lookup or nil
        env.GetPlayerCommunityUserId = function() return 'test-unit' end
        env.GetIdentifiers = function() return {license = 'test-license'} end
        env.json = {encode = function() return '{}' end}
        env.debugLog = function() end
        env.CadApiCreateEmergencyCall = function(data) sent = data; return {success = true} end
        assert(loadfile('sonorancad/submodules/localcallers/sv_localcallers.lua', 't', env))()
        handler('Test street', 'Test call', nil)
        assert(sent and sent.metaData.postal == (lookup and lookup() or 'Unknown'))
    end)
end
print(passed .. ' tests passed')
