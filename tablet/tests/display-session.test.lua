-- Run from the repository root: lua tablet/tests/display-session.test.lua
local function harness()
    local state = { time = 100, exists = true, frozen = false, dead = false,
        vehicle = 0, messages = {}, threads = {}, timers = {}, events = {}, exports = {}, destroyed = 0 }
    local vector
    local mt = {
        __add = function(a, b) return vector(a.x + b.x, a.y + b.y, a.z + b.z) end,
        __sub = function(a, b) return vector(a.x - b.x, a.y - b.y, a.z - b.z) end,
        __mul = function(a, b) return vector(a.x * b, a.y * b, a.z * b) end,
        __div = function(a, b) return vector(a.x / b, a.y / b, a.z / b) end,
        __len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
    }
    vector = function(x, y, z) return setmetatable({ x = x, y = y, z = z }, mt) end
    local noop = function() end
    local env = setmetatable({
        vector3 = vector, nuiFocused = false, usingTablet = false,
        exports = function(name, callback) state.exports[name] = callback end,
        AddEventHandler = function(name, callback) state.events[name] = callback end,
        TriggerEvent = function(name, key)
            state.closedKey = key
            if state.events[name] then state.events[name](key) end
        end,
        GetGameTimer = function() return state.time end,
        DoesEntityExist = function(entity) return entity ~= 0 and state.exists end,
        PlayerPedId = function() return 1 end, PlayerId = function() return 1 end,
        GetVehiclePedIsIn = function() return state.vehicle end,
        IsEntityDead = function() return state.dead end,
        IsPedRagdoll = function() return false end, IsPauseMenuActive = function() return false end,
        GetEntityCoords = function() return vector(0, 0, 0) end,
        GetEntityMatrix = function()
            return vector(0, 1, 0), vector(1, 0, 0), vector(0, 0, 1), vector(0, 0, 0)
        end,
        GetAspectRatio = function() return 16 / 9 end,
        IsEntityPositionFrozen = function() return state.frozen end,
        FreezeEntityPosition = function(_, frozen) state.frozen = frozen end,
        CreateCam = function() return 10 end,
        DestroyCam = function() state.destroyed = state.destroyed + 1 end,
        SetCamFov = noop, SetCamNearClip = noop,
        SetCamCoord = function(_, x, y, z) state.cameraPosition = vector(x, y, z) end,
        PointCamAtCoord = function(_, x, y, z) state.cameraTarget = vector(x, y, z) end,
        SetNuiFocusKeepInput = noop, DisablePlayerFiring = noop, DisableControlAction = noop,
        RenderScriptCams = function(render) state.rendering = render end,
        DisplayModule = function(_, visible) state.visible = visible end,
        SetFocused = function(focused) state.focused = focused end,
        SendNUIMessage = function(message) table.insert(state.messages, message) end,
        SetTimeout = function(_, callback) table.insert(state.timers, callback) end,
        CreateThread = function(callback)
            local thread = coroutine.create(callback)
            table.insert(state.threads, thread)
            assert(coroutine.resume(thread))
        end,
        Wait = coroutine.yield,
        GetScreenCoordFromWorldCoord = function() return true, .5, .5 end,
        GetCurrentResourceName = function() return 'tablet' end
    }, { __index = _G })
    assert(loadfile('tablet/cl_display.lua', 't', env))()
    state.env = env
    state.options = { entity = 2, key = 'world:1', range = 1.5, transitionMs = 450, profile = { corners = {
        { x = -.2, y = 0, z = .2 }, { x = .2, y = 0, z = .2 },
        { x = .2, y = 0, z = 0 }, { x = -.2, y = 0, z = 0 }
    } } }
    function state:frame()
        for _, thread in ipairs(self.threads) do
            if coroutine.status(thread) ~= 'dead' then assert(coroutine.resume(thread)) end
        end
    end
    return state
end

local count = 0
local function test(name, callback)
    callback()
    count = count + 1
    print('PASS ' .. name)
end

test('close during entry restores focus and movement, and cancels stale frames', function()
    local s = harness()
    assert(s.exports.OpenDisplay(s.options))
    assert(s.focused and s.frozen and s.rendering)
    assert(not s.exports.OpenDisplay(s.options))
    s.env.CloseCadDisplay()
    assert(not s.focused and not s.frozen and not s.rendering)
    assert(s.closedKey == 'world:1')
    local messages = #s.messages
    s.time = 1000
    s:frame()
    assert(#s.messages == messages)
    s.timers[1]()
    assert(s.destroyed == 1)
end)

test('projection starts only after camera entry completes', function()
    local s = harness()
    assert(s.exports.OpenDisplay(s.options))
    s:frame()
    assert(s.messages[#s.messages].type == 'display_surface')
    s.time = 600
    s:frame()
    assert(s.messages[#s.messages].type == 'display_surface_frame')
end)

for _, reason in ipairs({ 'death', 'vehicle exit', 'entity deletion' }) do
    test(reason .. ' closes the session', function()
        local s = harness()
        assert(s.exports.OpenDisplay(s.options))
        if reason == 'death' then s.dead = true
        elseif reason == 'vehicle exit' then s.vehicle = 3
        else s.exists = false end
        s:frame()
        assert(not s.env.IsCadDisplayActive() and not s.focused and not s.rendering)
    end)
end

test('resource stop immediately destroys a returning camera', function()
    local s = harness()
    assert(s.exports.OpenDisplay(s.options))
    s.env.CloseCadDisplay()
    s.events.onResourceStop('tablet')
    assert(s.destroyed == 1)
    s.timers[1]()
    assert(s.destroyed == 1)
end)

test('pre-existing player freeze is preserved', function()
    local s = harness()
    s.frozen = true
    assert(s.exports.OpenDisplay(s.options))
    s.env.CloseCadDisplay(true)
    assert(s.frozen)
end)

test('busy tablet and malformed profiles do not take the camera', function()
    local s = harness()
    s.env.nuiFocused = true
    assert(not s.exports.OpenDisplay(s.options))
    s.env.nuiFocused = false
    s.options.profile.corners[1].x = 0 / 0
    assert(not s.exports.OpenDisplay(s.options))
    assert(not s.rendering)
end)

test('rotated and scaled entity axes drive camera position and CAD aspect ratio', function()
    local s = harness()
    local v = s.env.vector3
    s.env.GetEntityMatrix = function()
        return v(-2, 0, 0), v(0, 3, 0), v(0, 0, 4), v(1, 2, 3)
    end
    assert(s.exports.OpenDisplay(s.options))
    assert(s.cameraPosition.x > 1 and s.cameraPosition.y == 2)
    assert(math.abs(s.cameraPosition.z - 3.4) < 0.00001)
    assert(#(s.cameraTarget - v(1, 2, 3.4)) < 0.00001)
    assert(s.messages[#s.messages].height == 853)
end)

test('leaving interaction range restores the player', function()
    local s = harness()
    assert(s.exports.OpenDisplay(s.options))
    s.env.GetEntityCoords = function(entity) return s.env.vector3(entity == 1 and 10 or 0, 0, 0) end
    s:frame()
    assert(not s.focused and not s.frozen and not s.env.IsCadDisplayActive())
end)

-- Exercise the actual G command and ownership handlers against the tablet export,
-- without running unrelated placement/menu polling threads.
local function withCadDisplay(s, configure)
    local env = s.env
    local config, setup
    local noop = function() end
    s.commands, s.claims, s.notifications, s.keymaps = {}, {}, {}, {}
    env.Config = {
        RegisterPluginConfig = function(_, value) config = value end,
        LoadPlugin = function(_, callback) callback(config) end
    }
    assert(loadfile('sonorancad/configuration/caddisplay_config.dist.lua', 't', env))()
    if configure then configure(config) end
    env.print = function(message) table.insert(s.notifications, message) end
    env.GetHashKey = function(model) return model end
    env.GetEntityModel = function() return 'prop_laptop_jimmy' end
    env.GetResourceState = function() return 'started' end
    env.GetPlayerServerId = function() return 42 end
    env.GetVehicleMaxNumberOfPassengers = function() return 3 end
    env.GetPedInVehicleSeat = function(_, seat) return seat == -1 and 1 or 0 end
    env.VehToNet = function() return 100 end
    env.ApplyPluginNotificationOverrides = function(_, payload) return payload end
    env.NotifyClient = function(payload) table.insert(s.notifications, payload.message) end
    env.RegisterNetEvent = function(name, callback) s.events[name] = callback end
    env.RegisterCommand = function(name, callback) s.commands[name] = callback end
    env.RegisterKeyMapping = function(name, _, _, key) s.keymaps[name] = key end
    env.RegisterPlayerCommandHelp = noop
    env.TriggerServerEvent = function(name, ...) table.insert(s.claims, { name, ... }) end
    env.WarMenu = {}
    env.exports = { tablet = {
        OpenDisplay = function(_, options) return s.exports.OpenDisplay(options) end,
        CloseDisplay = function(_, immediate) return s.exports.CloseDisplay(immediate) end
    } }
    local createThread = env.CreateThread
    env.CreateThread = function(callback) setup = callback end
    assert(loadfile('sonorancad/submodules/caddisplay/cl_caddisplay.lua', 't', env))()
    env.CreateThread = noop
    setup()
    env.CreateThread = createThread
    env.getClosestWorldDisplay = function() return 7, 2, 0.5 end
    s.claims = {}
    return s.commands['SonoranCAD::caddisplay::Interact'], s.events['SonoranCAD::caddisplay::SyncOwners']
end

for _, target in ipairs({ 'station', 'vehicle' }) do
    test('G starts the ' .. target .. ' laptop camera on ownership grant and on reuse', function()
        local s = harness()
        local interact, syncOwners = withCadDisplay(s)
        local key = 'world:7'
        if target == 'vehicle' then
            s.vehicle = 3
            s.env.trackDisplayForVehicle(3, 2)
            key = '100'
        end
        assert(s.keymaps['SonoranCAD::caddisplay::Interact'] == 'G')
        interact()
        assert(#s.claims == 1 and not s.rendering)
        syncOwners({ [key] = 42 })
        assert(s.rendering and s.focused and s.env.IsCadDisplayActive())
        assert(s.messages[#s.messages].type == 'display_surface')
        s.env.CloseCadDisplay(true)
        interact()
        assert(#s.claims == 1 and s.rendering and s.focused)
        syncOwners({ [key] = 99 })
        assert(not s.rendering and not s.focused)
    end)
end

test('G reports a busy handheld tablet instead of silently failing', function()
    local s = harness()
    local interact, syncOwners = withCadDisplay(s)
    syncOwners({ ['world:7'] = 42 })
    s.env.usingTablet = true
    interact()
    assert(not s.rendering)
    assert(s.notifications[#s.notifications] == 'Close the handheld tablet before using the laptop.')
end)

test('G with disabled interaction reports the setting without opening the handheld tablet', function()
    local s = harness()
    local interact, syncOwners = withCadDisplay(s, function(config) config.interaction.enabled = false end)
    local handheldOpened = false
    s.events['SonoranCAD::Tablet::OpenCad'] = function() handheldOpened = true end
    syncOwners({ ['world:7'] = 42 })
    interact()
    assert(not handheldOpened and not s.rendering)
    assert(s.notifications[#s.notifications]:find('interaction.enabled = true', 1, true))
end)

test('G with an unknown model reports its hash without substituting the handheld tablet', function()
    local s = harness()
    local interact, syncOwners = withCadDisplay(s)
    s.env.GetEntityModel = function() return 123456 end
    local handheldOpened = false
    s.events['SonoranCAD::Tablet::OpenCad'] = function() handheldOpened = true end
    syncOwners({ ['world:7'] = 42 })
    interact()
    assert(not handheldOpened and not s.rendering)
    assert(s.notifications[#s.notifications]:find('model 123456', 1, true))
end)
print(('Passed %d display session tests'):format(count))
