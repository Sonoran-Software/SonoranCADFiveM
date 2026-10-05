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
    env.GetHashKey = function(model) assert(type(model) == 'string'); return model end
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
    env.WarMenu = { OpenMenu = function(menu) s.openedMenu = menu end,
        CloseMenu = function() s.openedMenu = nil end }
    env.exports = { tablet = {
        OpenDisplay = function(_, options)
            s.lastDisplayOptions = options
            return s.exports.OpenDisplay(options)
        end,
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

for _, missing in ipairs({ 'section', 'models' }) do
    test('hardcoded laptop corners work without the interaction ' .. missing, function()
        local s = harness()
        local interact, syncOwners = withCadDisplay(s, function(config)
            if missing == 'section' then config.interaction = nil else config.interaction.models = nil end
        end)
        syncOwners({ ['world:7'] = 42 })
        interact()
        assert(s.env.IsCadDisplayActive())
        local p = s.lastDisplayOptions.profile.corners
        assert(p[1].x == -.162 and p[1].y == .0774 and p[1].z == .236)
        assert(p[3].x == .158 and p[3].y == .0316 and p[3].z == .046)
        s.time = 999
        s:frame()
        assert(s.messages[#s.messages].type == 'display_surface')
        s.time = 1000
        s:frame()
        assert(s.messages[#s.messages].type == 'display_surface_frame')
    end)
end

test('calibration applies a prop profile locally for the next G interaction', function()
    local s = harness()
    local interact, syncOwners = withCadDisplay(s)
    local options
    s.env.CadDisplayCalibration = { IsActive = function() return false end,
        Start = function(value) options = value; return true end }
    s.events['SonoranCAD::caddisplay::Calibrate'](false, true)
    assert(options.entity == 2 and not options.builtin)
    local profile = { corners = s.options.profile.corners }
    options.apply(profile)
    syncOwners({ ['world:7'] = 42 })
    interact()
    assert(s.lastDisplayOptions.profile == profile)
end)

test('exported numeric model keys load as configured interaction profiles', function()
    local s = harness()
    local profile = { corners = s.options.profile.corners }
    local interact, syncOwners = withCadDisplay(s, function(config)
        config.interaction.models[123456] = profile
    end)
    s.env.GetEntityModel = function() return 123456 end
    syncOwners({ ['world:7'] = 42 })
    interact()
    assert(s.env.IsCadDisplayActive() and s.lastDisplayOptions.profile == profile)
end)

test('station calibration rejects vehicle-only administrators', function()
    local s = harness()
    withCadDisplay(s)
    s.env.CadDisplayCalibration = { Start = function() error('unauthorized calibration') end }
    s.events['SonoranCAD::caddisplay::Calibrate'](true, false)
    assert(s.notifications[#s.notifications]:find('Station display administration', 1, true))
end)

test('built-in vehicle calibration updates that screen profile for G', function()
    local s = harness()
    local interact, syncOwners = withCadDisplay(s)
    s.vehicle = 3
    s.env.trackDisplayForVehicle(3, 3)
    local builtin, options = { model = 'POLICE' }
    s.env.getBuiltinScreenConfig = function() return builtin end
    s.env.CadDisplayCalibration = { IsActive = function() return false end,
        Start = function(value) options = value; return true end }
    s.events['SonoranCAD::caddisplay::Calibrate'](true, false)
    assert(options.entity == 3 and options.builtin and options.model == 'POLICE' and not options.profile)
    local profile = { corners = s.options.profile.corners }
    options.apply(profile)
    syncOwners({ ['100'] = 42 })
    interact()
    assert(s.lastDisplayOptions.profile == profile and builtin.interaction == profile)
end)

test('G and the placement menu are blocked while calibrating', function()
    local s = harness()
    local interact = withCadDisplay(s)
    s.env.CadDisplayCalibration = { IsActive = function() return true end }
    interact()
    s.events['SonoranCAD::caddisplay::OpenMenu'](true, true)
    assert(not s.env.IsCadDisplayActive() and not s.openedMenu and #s.claims == 0)
end)

test('station mouse placement sends the final world transform only on Save', function()
    local s = harness()
    withCadDisplay(s)
    local editor, deleted
    s.env.GetEntityHeading = function() return 0 end
    s.env.GetEntityRotation = function() return s.env.vector3(0,0,0) end
    s.env.spawnWorldDisplay = function() return 2 end
    s.env.DeleteObject = function(entity) deleted = entity end
    s.env.SonoranPlacementEditor = {IsActive=function() return false end,
        Start=function(options) editor=options; return true end}
    s.env.beginWorldEdit(nil,true)
    assert(editor.entity==2 and #s.claims==0)
    editor.onFinish({accepted=true,position={x=1,y=2,z=3},rotation={x=4,y=5,z=6}})
    assert(s.claims[1][1]=='SonoranCAD::caddisplay::SaveWorldPlacement')
    assert(s.claims[1][2].position.x==1 and s.claims[1][2].rotation.z==6 and deleted==2)
end)

test('cancelling an existing station gizmo does not delete or save it', function()
    local s = harness()
    withCadDisplay(s)
    local editor
    s.env.GetEntityRotation = function() return s.env.vector3(0,0,0) end
    s.env.spawnWorldDisplay = function() return 2 end
    s.env.DeleteObject = function() error('existing station deleted') end
    s.env.SonoranPlacementEditor = {IsActive=function() return false end,
        Start=function(options) editor=options; return true end}
    s.env.beginWorldEdit({ID=7,Position={x=0,y=0,z=0},Rotation={pitch=0,roll=0,yaw=0}},false)
    editor.onFinish({accepted=false})
    assert(#s.claims==0)
end)

for _,mode in ipairs({'save','cancel','new_cancel'}) do
    local accept, isNew = mode=='save', mode=='new_cancel'
    test('vehicle gizmo '..mode..' preserves the expected attachment and preview lifecycle',function()
        local s = harness()
        withCadDisplay(s)
        s.vehicle=3
        local env=s.env
        env.trackDisplayForVehicle(3,2)
        env.isVehicleBlocked=function() return false end
        s.events['SonoranCAD::caddisplay::OpenMenu'](true,true)
        local editor,created,deleted,attached= nil,9,{},{}
        local v=env.vector3
        env.GetEntityType=function() return 3 end
        env.GetEntitySpeed=function() return 0 end
        env.GetEntityRotation=function() return env.vector3(0,0,30) end
        local headReads=0
        env.GetPedBoneCoords=function()
            headReads=headReads+1
            return v(-.35,.1,1.2)
        end
        env.GetModelDimensions=function(model)
            assert(model=='prop_laptop_jimmy')
            return v(-.4,-.1,-.2),v(.2,.5,.6)
        end
        env.NetworkGetEntityIsNetworked=function() return false end
        env.GetEntityBoneIndexByName=function(_,name) return name=='chassis' and 12 or -1 end
        env.GetDisplayNameFromVehicleModel=function() return 'POLICE' end
        env.CreateObjectNoOffset=function() created=created+1; return created end
        env.DeleteObject=function(entity) deleted[entity]=true end
        env.SetEntityCollision=function() end; env.SetEntityVisible=function() end
        env.SetEntityLocallyInvisible=function() end; env.SetEntityMatrix=function() end
        env.SetEntityCoordsNoOffset=function() end
        env.AttachEntityToEntity=function(...) attached[#attached+1]={...} end
        env.GetEntityMatrix=function(entity)
            return env.vector3(0,1,0),env.vector3(1,0,0),env.vector3(0,0,1),env.vector3(entity==11 and 10 or 0,0,0)
        end
        assert(loadfile('sonorancad/core/placement/math.lua','t',env))()
        env.SonoranPlacementEditor={IsActive=function() return false end,
            Start=function(options) editor=options; return true end}
        env.beginVehiclePlacementEditor(isNew)
        s:frame()
        assert(editor and editor.entity==10 and #editor.actions==2 and #attached==1 and attached[1][1]==11)
        assert(editor.view and editor.view.mode=='cockpit' and editor.view.fov==65 and not editor.view.hidePlayer)
        assert(#(editor.view.position-v(0,-.15,1.23))<1e-6,'missing seat bones must use the vehicle centerline')
        assert(#(editor.focusOffset-v(-.1,.2,.2))<1e-6)
        assert(#(editor.pivotOffset-editor.focusOffset)<1e-6)
        assert(headReads==1)
        editor.onFinish({accepted=accept,action='save',matrix={p=env.vector3(11,2,3),r=env.vector3(1,0,0),f=env.vector3(0,1,0),u=env.vector3(0,0,1)}})
        assert(deleted[10] and deleted[11] and (deleted[2] == true) == isNew)
        if accept then
            assert(#attached==2 and attached[2][1]==2 and attached[2][3]==12)
            assert(s.claims[1][1]=='SonoranCAD::caddisplay::SavePlacement' and s.claims[1][2].position.x==1)
        else assert(#attached==1 and #s.claims==0) end
    end)
end

test('vehicle placement captures a fixed camera between the front seats for either side of rotated cabins',function()
    local s=harness();withCadDisplay(s);s.vehicle=3
    local env=s.env
    local v=env.vector3
    assert(loadfile('sonorancad/core/placement/math.lua','t',env))()
    local M=env.SonoranPlacementMath
    env.trackDisplayForVehicle(3,2);env.isVehicleBlocked=function() return false end
    s.events['SonoranCAD::caddisplay::OpenMenu'](true,true)
    local editor,head,headReads,parent,object,seatCase,created
    created=9
    env.GetEntityType=function() return 3 end
    env.GetEntitySpeed=function() return 0 end
    env.GetEntityRotation=function() return v(0,0,0) end
    env.GetPedBoneCoords=function(ped,bone,x,y,z)
        assert(ped==1 and bone==31086 and x==0 and y==0 and z==0)
        headReads=headReads+1;return head
    end
    env.GetGameplayCamCoord=function() error('fixed cabin camera must not use the gameplay viewpoint') end
    env.GetModelDimensions=function() return v(-.4,-.1,-.2),v(.2,.5,.6) end
    env.NetworkGetEntityIsNetworked=function() return false end
    env.GetDisplayNameFromVehicleModel=function() return 'POLICE' end
    env.GetEntityBoneIndexByName=function(_,name)
        if name=='chassis' then return 12 end
        if seatCase=='missing' then return -1 end
        if seatCase=='same bone' then return 20 end
        return name=='seat_dside_f' and 20 or 21
    end
    env.GetWorldPositionOfEntityBone=function(_,bone)
        if (seatCase=='zero driver position' and bone==20) or (seatCase=='zero passenger position' and bone==21) then
            return v(0,0,0)
        end
        local x=bone==20 and -.55 or .75
        if seatCase=='coincident positions' then x=.1 end
        return parent.p+parent.r*x+parent.f*.2+parent.u*.3
    end
    env.CreateObjectNoOffset=function() created=created+1;return created end
    env.DeleteObject=function() end
    env.SetEntityCollision=function() end;env.SetEntityVisible=function() end
    env.SetEntityLocallyInvisible=function(entity) assert(entity==2,'the seated player must stay visible') end
    env.SetEntityMatrix=function() end;env.SetEntityCoordsNoOffset=function() end
    env.AttachEntityToEntity=function() end
    env.GetEntityMatrix=function(entity)
        local m=entity==3 and parent or object
        return m.f,m.r,m.u,m.p
    end
    env.SonoranPlacementEditor={IsActive=function() return false end,
        Start=function(options) editor=options;return true end}
    for _,yaw in ipairs({45,-120}) do
        parent=M.cameraBasis(v(6,4,yaw));parent.p=v(100,200,30)
        object=M.cameraBasis(v(0,0,yaw));object.p=parent.p+parent.f*.9+parent.u*.7
        for _,side in ipairs({-1,1}) do
            for _,case in ipairs({'valid','missing','same bone','coincident positions','zero driver position','zero passenger position'}) do
                seatCase=case;headReads=0
                head=parent.p+parent.r*(side*.4)+parent.f*.3+parent.u*1.1
                env.beginVehiclePlacementEditor(false);s:frame()
                assert(editor and editor.view.mode=='cockpit' and editor.view.fov==65 and not editor.view.hidePlayer)
                local localEye=editor.view.position-parent.p
                assert(math.abs(M.dot(localEye,parent.r)-(case=='valid' and .1 or 0))<1e-6)
                assert(math.abs(M.dot(localEye,parent.f)-.05)<1e-6)
                assert(math.abs(M.dot(localEye,parent.u)-1.13)<1e-6)
                local center=object.p+object.r*editor.focusOffset.x+object.f*editor.focusOffset.y+object.u*editor.focusOffset.z
                assert(#(M.cameraBasis(editor.view.rotation).f-M.unit(center-editor.view.position))<1e-6)
                assert(#(editor.view.up-parent.u)<1e-6 and #(editor.pivotOffset-editor.focusOffset)<1e-6)
                local fixed=editor.view.position
                head=head+v(4,5,6)
                assert(editor.validate() and editor.validate() and editor.validate())
                assert(headReads==1 and #(editor.view.position-fixed)<1e-6,'the head is sampled once, never followed')
                editor.onFinish({accepted=false})
            end
        end
    end
end)

local function previewHarness()
    local s=harness()
    local interact,syncOwners=withCadDisplay(s)
    local env=s.env
    assert(loadfile('sonorancad/core/placement/math.lua','t',env))()
    syncOwners({['world:7']=42});interact()
    local corners=s.lastDisplayOptions.profile.corners
    env.CloseCadDisplay(true)
    local v,M=env.vector3,env.SonoranPlacementMath
    local topLeft=v(corners[1].x,corners[1].y,corners[1].z)
    local topRight=v(corners[2].x,corners[2].y,corners[2].z)
    local bottomRight=v(corners[3].x,corners[3].y,corners[3].z)
    local bottomLeft=v(corners[4].x,corners[4].y,corners[4].z)
    -- Derive the visible screen side from the real interaction profile, not a heading convention.
    local localNormal=M.unit(M.cross(topRight-topLeft,topLeft-bottomLeft))
    local localCenter=(topLeft+bottomRight)/2
    function s:assertScreenFaces(point,heading,viewer)
        local basis=M.cameraBasis(v(0,0,heading))
        local function worldVector(value) return basis.r*value.x+basis.f*value.y+basis.u*value.z end
        local screenCenter=point+worldVector(localCenter)
        local screenNormal=worldVector(localNormal)
        assert(M.dot(screenNormal,M.unit(viewer-screenCenter))>.75,'the screen front must face the viewer, not its back')
    end
    return s
end

test('new vehicle previews face either seated viewer and clear their head in rotated cabin axes',function()
    local s=previewHarness();s.vehicle=3
    local env=s.env
    local v,M=env.vector3,env.SonoranPlacementMath
    env.GetGameplayCamCoord=function() error('exterior camera used to spawn seated preview') end
    for _,yaw in ipairs({0,90,-135}) do
        local frame=M.cameraBasis(v(7,-4,yaw));frame.p=v(10,20,30)
        env.GetEntityMatrix=function() return frame.f,frame.r,frame.u,frame.p end
        env.GetEntityHeading=function(entity) assert(entity==3);return yaw end
        for _,side in ipairs({-1,1}) do
            local head=frame.p+frame.r*(side*.45)+frame.u*.9
            env.GetPedBoneCoords=function(ped,bone,x,y,z)
                assert(ped==1 and bone==31086 and x==0 and y==0 and z==0)
                return head
            end
            local point,heading=env.getDisplayPreviewTransform()
            point=v(point.x,point.y,point.z)
            local delta=point-head
            assert(M.dot(delta,frame.f)>.65 and M.dot(delta,frame.f)<.9,'preview should sit forward near the dashboard')
            assert(M.dot(delta,frame.r)*side<-.2 and M.dot(delta,frame.r)*side>-.4,'preview should move toward the cabin center')
            assert(M.dot(delta,frame.u)<-.25 and M.dot(delta,frame.u)>-.45,'preview should sit below eye level')
            assert(#delta>.8 and #delta<1,'preview must clear the seated viewer rather than fill the camera')
            s:assertScreenFaces(point,heading,head)
        end
    end
end)

test('on-foot preview shows the screen front from the gameplay camera',function()
    local s=previewHarness()
    local env=s.env
    local v,M=env.vector3,env.SonoranPlacementMath
    local eye=v(10,20,30)
    for _,yaw in ipairs({0,90,-135}) do
        local rotation=v(-12,0,yaw)
        env.GetGameplayCamCoord=function() return eye end
        env.GetGameplayCamRot=function() return rotation end
        local point,heading=env.getDisplayPreviewTransform()
        point=v(point.x,point.y,point.z)
        assert(M.dot(point-eye,M.cameraBasis(rotation).f)>.7)
        s:assertScreenFaces(point,heading,eye)
    end
end)

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
