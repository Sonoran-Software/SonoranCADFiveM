-- Run from the repository root: lua tablet/tests/display-calibration.test.lua
local vector
local mt = {
    __add = function(a, b) return vector(a.x + b.x, a.y + b.y, a.z + b.z) end,
    __sub = function(a, b) return vector(a.x - b.x, a.y - b.y, a.z - b.z) end,
    __mul = function(a, b) return vector(a.x * b, a.y * b, a.z * b) end,
    __div = function(a, b) return vector(a.x / b, a.y / b, a.z / b) end,
    __len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
}
vector = function(x, y, z) return setmetatable({ x = x, y = y, z = z }, mt) end
local function points()
    return { { x = -.2, y = 0, z = .2 }, { x = .2, y = 0, z = .2 },
        { x = .2, y = 0, z = 0 }, { x = -.2, y = 0, z = 0 } }
end
local function harness()
    local s = { events = {}, threads = {}, pressed = {}, held = {}, vehicle = 0, frozen = false,
        exists = true, messages = {}, prints = {}, distance = 0, rayStatus = 1, rayEntity = 2 }
    local noop = function() end
    local env = setmetatable({ vector3 = vector,
        GetEntityMatrix = function() return vector(0, 1, 0), vector(1, 0, 0), vector(0, 0, 1), vector(0, 0, 0) end,
        GetEntityCoords = function(entity) return vector(entity == 1 and s.distance or 0, 0, 0) end,
        DoesEntityExist = function() return s.exists end,
        PlayerPedId = function() return 1 end, PlayerId = function() return 1 end,
        IsEntityDead = function() return s.dead end, IsPedRagdoll = function() return false end,
        IsPauseMenuActive = function() return false end, IsNuiFocused = function() return s.nui end,
        GetVehiclePedIsIn = function() return s.vehicle end,
        GetEntitySpeed = function() return s.speed or 0 end,
        IsEntityPositionFrozen = function() return s.frozen end,
        FreezeEntityPosition = function(_, value) s.frozen = value end,
        GetFinalRenderedCamCoord = function() return vector(0, -2, 1) end,
        GetFinalRenderedCamRot = function() return vector(0, 0, 0) end,
        GetFrameTime = function() return .02 end,
        GetScreenCoordFromWorldCoord = function() return true, .5, .5 end,
        IsDisabledControlJustPressed = function(_, key) return s.pressed[key] end,
        IsDisabledControlPressed = function(_, key) return s.held[key] end,
        StartShapeTestLosProbe = function() return 42 end,
        GetShapeTestResult = function() return s.rayStatus, true, s.rayPoint, vector(0, -1, 0), s.rayEntity end,
        DisableControlAction = noop, DisablePlayerFiring = noop, DrawLine = noop, DrawRect = noop,
        SetTextFont = noop, SetTextScale = noop, SetTextColour = noop, SetTextOutline = noop,
        BeginTextCommandDisplayText = noop, AddTextComponentSubstringPlayerName = noop, EndTextCommandDisplayText = noop,
        AddEventHandler = function(name, callback) s.events[name] = callback end,
        GetCurrentResourceName = function() return 'sonorancad' end,
        print = function(message) s.prints[#s.prints + 1] = message end,
        CreateThread = function(callback)
            local thread = coroutine.create(callback)
            s.threads[#s.threads + 1] = thread
            assert(coroutine.resume(thread))
        end, Wait = coroutine.yield
    }, { __index = _G })
    assert(loadfile('sonorancad/submodules/caddisplay/cl_caddisplay_calibration.lua', 't', env))()
    s.env, s.tool = env, env.CadDisplayCalibration
    s.options = { entity = 2, model = 363555755, profile = { corners = points() },
        notify = function(message) s.messages[#s.messages + 1] = message end,
        apply = function(profile) s.applied = profile end }
    function s:frame(pressed, held)
        self.pressed, self.held = pressed or {}, held or {}
        for _, thread in ipairs(self.threads) do
            if coroutine.status(thread) ~= 'dead' then assert(coroutine.resume(thread)) end
        end
    end
    return s
end
local count = 0
local function test(name, callback)
    callback()
    count = count + 1
    print('PASS ' .. name)
end

test('model/world conversion round trips rotated and nonuniformly scaled entities', function()
    local s = harness()
    s.env.GetEntityMatrix = function()
        return vector(-2, 0, 0), vector(0, .5, 0), vector(0, 0, 3), vector(100, -200, 30)
    end
    local p = points()
    local world = s.tool.ToWorld(2, p)
    for i, point in ipairs(world) do
        local result = s.tool.ToLocal(2, point)
        assert(math.abs(result.x - p[i].x) < 1e-8 and math.abs(result.y - p[i].y) < 1e-8
            and math.abs(result.z - p[i].z) < 1e-8)
    end
end)

test('validation rejects nonfinite, collapsed, folded and nonplanar surfaces', function()
    local s = harness()
    assert(s.tool.Validate(points()))
    for _, change in ipairs({ function(p) p[1].x = 0/0 end,
        function(p) p[2] = p[1] end, function(p) p[2], p[3] = p[3], p[2] end,
        function(p) p[4].y = .1 end }) do
        local p = points()
        change(p)
        assert(not s.tool.Validate(p))
    end
end)

test('prop and vehicle exports are valid Lua with the original model coordinates', function()
    local s = harness()
    local prop = assert(load('return { ' .. s.tool.Format(points(), 363555755, false) .. ' }'))()
    local named = assert(load('return { ' .. s.tool.Format(points(), 'prop_laptop_jimmy', false) .. ' }'))()
    local vehicle = assert(load('return { ' .. s.tool.Format(points(), 'POLICE', true) .. ' }'))()
    assert(prop[363555755].corners[1].x == -.2 and vehicle.interaction.corners[3].z == 0)
    assert(named.prop_laptop_jimmy.corners[1].x == -.2)
end)

test('cancel restores movement and leaves the profile unchanged', function()
    local s = harness()
    assert(s.tool.Start(s.options) and s.frozen)
    s:frame({}, { [175] = true })
    s:frame({ [177] = true })
    assert(not s.tool.IsActive() and not s.frozen and not s.applied)
    assert(s.options.profile.corners[1].x == -.2)
end)

test('fine adjustment and apply create an isolated profile for local preview', function()
    local s = harness()
    assert(s.tool.Start(s.options))
    s:frame({}, { [175] = true, [21] = true, [36] = true })
    s:frame({ [201] = true })
    assert(s.applied and not s.tool.IsActive() and not s.frozen)
    assert(math.abs(s.applied.corners[1].x - (-.2 + .0002)) < 1e-8)
    assert(s.options.profile.corners[1].x == -.2 and #s.prints == 1)
end)

test('raycast waits for completion and updates the selected model-local corner', function()
    local s = harness()
    assert(s.tool.Start(s.options))
    s:frame({ [24] = true })
    s.rayPoint, s.rayStatus = vector(-.21, 0, .2), 2
    s:frame()
    s:frame({ [201] = true })
    assert(s.applied.corners[1].x == -.21)
end)

test('clicking unrelated collision never changes the target profile', function()
    local s = harness()
    assert(s.tool.Start(s.options))
    s.rayPoint, s.rayStatus, s.rayEntity = vector(20, 20, 20), 2, 99
    s:frame({ [24] = true })
    s:frame({ [201] = true })
    assert(s.applied.corners[1].x == -.2 and #s.messages == 2)
end)

test('export waits for a pending click and reset discards its stale result', function()
    local s = harness()
    assert(s.tool.Start(s.options))
    s:frame({ [24] = true })
    s:frame({ [201] = true })
    assert(not s.applied)
    s.rayPoint, s.rayStatus = vector(-.21, 0, .2), 2
    s:frame({ [45] = true })
    s:frame({ [201] = true })
    assert(s.applied.corners[1].x == -.2)
end)

test('invalid depth can be flattened and exported', function()
    local s = harness()
    assert(s.tool.Start(s.options))
    for _ = 1, 3 do s:frame({ [37] = true }) end
    for _ = 1, 5 do s:frame({}, { [10] = true }) end
    s:frame({ [201] = true })
    assert(not s.applied and s.tool.IsActive())
    s:frame({ [23] = true })
    s:frame({ [201] = true })
    assert(s.applied and s.applied.corners[4].y == 0)
end)

test('missing profiles start with editable camera-facing seed corners', function()
    local s = harness()
    s.options.profile = nil
    assert(s.tool.Start(s.options))
    s:frame({ [201] = true })
    assert(s.applied and s.tool.Validate(s.applied.corners))
end)

for _, reason in ipairs({ 'resource stop', 'death', 'deletion', 'distance', 'vehicle exit', 'movement', 'NUI focus' }) do
    test(reason .. ' cancels without applying or leaving the player frozen', function()
        local s = harness()
        if reason == 'vehicle exit' or reason == 'movement' then s.vehicle = 3 end
        assert(s.tool.Start(s.options))
        if reason == 'resource stop' then s.events.onResourceStop('sonorancad')
        elseif reason == 'death' then s.dead = true
        elseif reason == 'deletion' then s.exists = false
        elseif reason == 'distance' then s.distance = 10
        elseif reason == 'vehicle exit' then s.vehicle = 0
        elseif reason == 'movement' then s.speed = 1
        else s.nui = true end
        s:frame()
        assert(not s.tool.IsActive() and not s.applied)
        if s.exists then assert(not s.frozen) end
    end)
end

test('preexisting freeze survives cancellation', function()
    local s = harness()
    s.frozen = true
    assert(s.tool.Start(s.options))
    s:frame({ [177] = true })
    assert(s.frozen)
end)

local function serverHarness(permissions)
    local s = { commands = {}, events = {}, messages = {}, notifications = {}, writes = 0 }
    local config
    local noop = function() end
    local env = setmetatable({
        Config = { RegisterPluginConfig = function(_, value) config = value end,
            LoadPlugin = function(_, callback) callback(config) end },
        CreateThread = function(callback) callback() end,
        RegisterCommand = function(name, callback) s.commands[name] = callback end,
        RegisterNetEvent = function(name, callback) s.events[name] = callback end,
        AddEventHandler = noop,
        IsPlayerAceAllowed = function(_, permission) return permissions[permission] == true end,
        TriggerClientEvent = function(...) s.messages[#s.messages + 1] = { ... } end,
        NotifyPlayer = function(_, payload) s.notifications[#s.notifications + 1] = payload end,
        ApplyPluginNotificationOverrides = function(_, payload) return payload end,
        GetCurrentResourceName = function() return 'sonorancad' end,
        LoadResourceFile = function() return '[]' end,
        SaveResourceFile = function() s.writes = s.writes + 1 end,
        json = { decode = function() return {} end, encode = function() return '[]' end },
        infoLog = noop, warnLog = noop
    }, { __index = _G })
    assert(loadfile('sonorancad/configuration/caddisplay_config.dist.lua', 't', env))()
    assert(loadfile('sonorancad/submodules/caddisplay/sv_caddisplay.lua', 't', env))()
    s.messages = {}
    return s, env
end

test('server denies calibration to ordinary menu users', function()
    local s = serverHarness({ ['sonoran.caddisplay'] = true })
    s.commands.caddisplay(1, { 'calibrate' })
    assert(#s.messages == 0 and #s.notifications == 1 and s.writes == 0)
end)

test('server dispatches the exact station and vehicle admin permissions', function()
    for _, kind in ipairs({ 'world', 'admin' }) do
        local s = serverHarness({ ['sonoran.caddisplay'] = true, ['sonoran.caddisplay.' .. kind] = true })
        s.commands.caddisplay(1, { 'calibrate' })
        local message = s.messages[1]
        assert(message[1] == 'SonoranCAD::caddisplay::Calibrate' and message[2] == 1)
        assert(message[3] == (kind == 'admin') and message[4] == (kind == 'world'))
        assert(s.writes == 0)
    end
end)

test('calibration does not grant server placement write permissions', function()
    local s, env = serverHarness({ ['sonoran.caddisplay'] = true })
    env.source = 1
    s.events['SonoranCAD::caddisplay::SaveWorldPlacement']({})
    s.events['SonoranCAD::caddisplay::DeleteWorldPlacement'](1)
    s.events['SonoranCAD::caddisplay::SavePlacement']({})
    assert(s.writes == 0 and #s.notifications == 3)
end)

print(('Passed %d calibration tests'):format(count))
