-- Run from the repository root: lua tablet/tests/display-session.test.lua
local function harness()
    local state = { time = 100, exists = true, frozen = false, dead = false,
        vehicle = 0, messages = {}, threads = {}, events = {}, exports = {}, destroyed = 0 }
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
        GetFinalRenderedCamCoord = function() return vector(0, -2, 1) end,
        GetFinalRenderedCamRot = function() return state.entryRotation or vector(0, 0, 0) end,
        GetFinalRenderedCamFov = function() return 70 end,
        GetCamCoord = function() return state.cameraPosition end,
        GetCamRot = function() return state.cameraRotation end,
        GetCamFov = function() return state.cameraFov end,
        GetGameplayCamCoord = function() return state.gameplayPosition or vector(0, -2, 1) end,
        GetGameplayCamRot = function() return state.gameplayRotation or vector(0, 0, 0) end,
        GetGameplayCamFov = function() return 70 end,
        SetCamFov = function(_, fov) state.cameraFov = fov end, SetCamNearClip = noop,
        SetCamCoord = function(_, x, y, z) state.cameraPosition = vector(x, y, z) end,
        SetCamRot = function(_, x, y, z) state.cameraRotation = vector(x, y, z) end,
        SetNuiFocusKeepInput = noop, DisablePlayerFiring = noop, DisableControlAction = noop,
        RenderScriptCams = function(render) state.rendering = render end,
        DisplayModule = function(_, visible) state.visible = visible end,
        SetFocused = function(focused) state.focused = focused end,
        SendNUIMessage = function(message) table.insert(state.messages, message) end,
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
    assert(not s.focused and not s.frozen and s.rendering)
    assert(s.closedKey == 'world:1')
    local messages = #s.messages
    s.time = 1000
    s:frame()
    assert(#s.messages == messages)
    assert(s.destroyed == 1 and not s.rendering)
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
        assert(not s.env.IsCadDisplayActive() and not s.focused)
        s.time = 1000
        s:frame()
        assert(not s.rendering and s.destroyed == 1)
    end)
end

test('resource stop immediately destroys a returning camera', function()
    local s = harness()
    assert(s.exports.OpenDisplay(s.options))
    s.env.CloseCadDisplay()
    s.events.onResourceStop('tablet')
    assert(s.destroyed == 1)
    s.time = 1000
    s:frame()
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
    s.time = 600
    s:frame()
    assert(s.cameraPosition.x > 1 and s.cameraPosition.y == 2)
    assert(math.abs(s.cameraPosition.z - 3.4) < 0.00001)
    assert(math.abs(s.cameraRotation.x) < 0.00001 and math.abs(s.cameraRotation.z - 90) < 0.00001)
    assert(s.messages[1].height == 853)
end)

test('zoom starts at the rendered view and eases in and out without overshoot', function()
    local s = harness()
    assert(s.exports.OpenDisplay(s.options))
    assert(#(s.cameraPosition - s.env.GetFinalRenderedCamCoord()) < 0.00001)
    assert(s.cameraFov == 70)
    local previous = 70
    for _, time in ipairs({ 145, 325, 505, 550 }) do
        s.time = time
        s:frame()
        assert(s.cameraFov <= previous and s.cameraFov >= 45)
        previous = s.cameraFov
        if time == 145 then assert(s.cameraFov > 69) end
        if time == 325 then assert(math.abs(s.cameraFov - 57.5) < 0.00001) end
        if time == 505 then assert(s.cameraFov < 46) end
    end
    assert(s.cameraFov == 45)
    local position = s.cameraPosition
    s.time = 1000
    s:frame()
    assert(#(s.cameraPosition - position) < 0.00001)
end)

test('zoom takes the short rotation path across the heading wrap', function()
    local s = harness()
    local v = s.env.vector3
    local angle = math.rad(190)
    s.entryRotation = v(0, 0, 170)
    s.env.GetEntityMatrix = function()
        return v(-math.sin(angle), math.cos(angle), 0), v(math.cos(angle), math.sin(angle), 0),
            v(0, 0, 1), v(0, 0, 0)
    end
    assert(s.exports.OpenDisplay(s.options))
    s.time = 325
    s:frame()
    assert(math.abs(s.cameraRotation.z - 180) < 0.00001)
end)

test('camera levels screens with combined pitch, roll, heading and scale', function()
    for _, angles in ipairs({ { 13, 7, 64 }, { -20, -12, -130 }, { 35, 28, 179 } }) do
        local s = harness()
        local v = s.env.vector3
        -- Independently rotate each model axis in ZXY order, then scale it.
        local function rotate(point)
            local x, y, z = point.x, point.y, point.z
            local pitch, roll, yaw = math.rad(angles[1]), math.rad(angles[2]), math.rad(angles[3])
            x, z = x * math.cos(roll) + z * math.sin(roll), -x * math.sin(roll) + z * math.cos(roll)
            y, z = y * math.cos(pitch) - z * math.sin(pitch), y * math.sin(pitch) + z * math.cos(pitch)
            x, y = x * math.cos(yaw) - y * math.sin(yaw), x * math.sin(yaw) + y * math.cos(yaw)
            return v(x, y, z)
        end
        s.env.GetEntityMatrix = function()
            return rotate(v(0, 2, 0)), rotate(v(3, 0, 0)), rotate(v(0, 0, 4)), v(0, 0, 0)
        end
        assert(s.exports.OpenDisplay(s.options))
        s.time = 600
        s:frame()
        assert(#(s.cameraRotation - v(angles[1], angles[2], angles[3])) < 0.00001)
    end
end)

test('exit eases pose and FOV to the moving gameplay camera before handing back control', function()
    local s = harness()
    local v = s.env.vector3
    assert(s.exports.OpenDisplay(s.options))
    s.time = 550
    s:frame()
    local position = s.cameraPosition
    s.env.CloseCadDisplay()
    assert(s.rendering and s.destroyed == 0 and not s.focused)
    assert(not s.exports.OpenDisplay(s.options))
    assert(#(s.cameraPosition - position) < 0.00001 and s.cameraFov == 45)
    for _, time in ipairs({ 595, 775, 955 }) do
        s.time = time
        s:frame()
        assert(s.rendering and s.destroyed == 0)
        if time == 595 then assert(s.cameraFov < 46) end
        if time == 775 then
            assert(math.abs(s.cameraFov - 57.5) < 0.00001)
            assert(#(s.cameraPosition - (position + s.env.GetGameplayCamCoord()) / 2) < 0.00001)
        end
        if time == 955 then assert(s.cameraFov > 69) end
    end
    s.gameplayPosition, s.gameplayRotation = v(3, -4, 2), v(-10, 5, 60)
    s.time = 1000
    s:frame()
    assert(not s.rendering and s.destroyed == 1 and s.cameraFov == 70)
    assert(#(s.cameraPosition - s.gameplayPosition) < 0.00001)
    assert(#(s.cameraRotation - s.gameplayRotation) < 0.00001)
    assert(s.exports.OpenDisplay(s.options))
end)

test('exit during entry starts at the current pose without jumping to the laptop', function()
    local s = harness()
    assert(s.exports.OpenDisplay(s.options))
    s.time = 325
    s:frame()
    local position, fov = s.cameraPosition, s.cameraFov
    s.env.CloseCadDisplay()
    s:frame()
    assert(#(s.cameraPosition - position) < 0.00001 and s.cameraFov == fov)
    s.time = 775
    s:frame()
    assert(not s.rendering and s.destroyed == 1)
end)

test('zero-duration entry immediately reaches the screen camera', function()
    local s = harness()
    s.options.transitionMs = 0
    assert(s.exports.OpenDisplay(s.options))
    assert(s.cameraFov == 45)
    s:frame()
    assert(s.messages[#s.messages].type == 'display_surface_frame')
    s.env.CloseCadDisplay()
    assert(not s.rendering and s.destroyed == 1)
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
    env.WarMenu = { OpenMenu = function(menu) s.openedMenu = menu end }
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

test('station administrators on foot open station management without a vehicle', function()
    local s = harness()
    withCadDisplay(s)
    s.events['SonoranCAD::caddisplay::OpenMenu'](false, true)
    assert(s.openedMenu == 'caddisplay_world_menu')
end)

test('station administrators in blocked vehicles can still manage station displays', function()
    local s = harness()
    withCadDisplay(s)
    s.vehicle = 3
    s.env.isVehicleBlocked = function() return true end
    s.events['SonoranCAD::caddisplay::OpenMenu'](false, true)
    assert(s.openedMenu == 'caddisplay_world_menu')
end)

test('compatible vehicles retain the main placement menu', function()
    local s = harness()
    withCadDisplay(s)
    s.vehicle = 3
    s.env.isVehicleBlocked = function() return false end
    s.events['SonoranCAD::caddisplay::OpenMenu'](true, false)
    assert(s.openedMenu == 'caddisplay_menu')
end)

test('missing station permissions report the configured ACE without granting access', function()
    local s = harness()
    withCadDisplay(s, function(config)
        config.acePerms.aceWorldDisplayAdmin = 'custom.station.admin'
        -- Existing local configurations do not contain the new language keys.
        config.lang.worldPermissionDenied = nil
        config.lang.worldPermissionRequiredAce = nil
    end)
    s.events['SonoranCAD::caddisplay::OpenMenu'](true, false)
    assert(not s.openedMenu)
    assert(s.notifications[#s.notifications]:find('Required ACE: custom.station.admin', 1, true))
end)

test('framework station denial does not recommend ACE permissions', function()
    local s = harness()
    withCadDisplay(s, function(config) config.permissionMode = 'framework' end)
    s.events['SonoranCAD::caddisplay::OpenMenu'](true, false)
    assert(not s.openedMenu)
    assert(s.notifications[#s.notifications] == 'You do not have permission to manage station CAD displays.')
end)

test('disabled station displays report their setting to players on foot', function()
    local s = harness()
    withCadDisplay(s, function(config) config.worldDisplays.enabled = false end)
    s.events['SonoranCAD::caddisplay::OpenMenu'](true, true)
    assert(not s.openedMenu)
    assert(s.notifications[#s.notifications] == 'Station CAD displays are disabled in the configuration.')
end)

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
        assert(not s.env.IsCadDisplayActive() and not s.focused)
        s.time = 1100
        s:frame()
        assert(not s.rendering)
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
