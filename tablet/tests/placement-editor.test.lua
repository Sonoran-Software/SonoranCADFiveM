-- Run from the repository root: lua tablet/tests/placement-editor.test.lua
local v
local mt={__add=function(a,b) return v(a.x+b.x,a.y+b.y,a.z+b.z) end,
    __sub=function(a,b) return v(a.x-b.x,a.y-b.y,a.z-b.z) end,
    __mul=function(a,b) return v(a.x*b,a.y*b,a.z*b) end,
    __div=function(a,b) return v(a.x/b,a.y/b,a.z/b) end,
    __len=function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end}
v=function(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
local function near(a,b) assert(#(a-b)<1e-6,('vectors differ: %.5f'):format(#(a-b))) end
local function identity() return {r=v(1,0,0),f=v(0,1,0),u=v(0,0,1),p=v(0,0,0)} end
local function harness()
    local s={matrix=identity(),nui={},events={},exports={},messages={},threads={},timers={},frozen={},exists=true,destroyed=0,vehicle=0}
    local noop=function() end
    local env=setmetatable({ vector3=v,
        GetEntityMatrix=function() local m=s.matrix; return m.f,m.r,m.u,m.p end,
        SetEntityMatrix=function(_,fx,fy,fz,rx,ry,rz,ux,uy,uz,px,py,pz)
            s.matrix={f=v(fx,fy,fz),r=v(rx,ry,rz),u=v(ux,uy,uz),p=v(px,py,pz)} end,
        GetEntityCoords=function() return s.matrix.p end,
        DoesEntityExist=function(entity) return entity==1 or s.exists end,
        PlayerPedId=function() return 1 end, PlayerId=function() return 1 end,
        IsEntityDead=function() return s.dead end,IsPedRagdoll=function() return false end,
        IsPauseMenuActive=function() return false end,GetVehiclePedIsIn=function() return s.vehicle end,
        IsNuiFocused=function() return s.focus end,SetNuiFocus=function(focus) s.focus=focus end,
        SetNuiFocusKeepInput=noop, NetworkGetEntityIsNetworked=function() return s.networked end,
        NetworkHasControlOfEntity=function() return s.control end,
        IsEntityPositionFrozen=function(entity) return s.frozen[entity]==true end,
        FreezeEntityPosition=function(entity,frozen) s.frozen[entity]=frozen end,
        CreateCam=function() return 10 end,DestroyCam=function() s.destroyed=s.destroyed+1 end,
        SetCamCoord=function(_,x,y,z) s.camera=v(x,y,z) end, GetCamCoord=function() return s.camera end,
        SetCamRot=noop,SetCamFov=noop,SetCamNearClip=noop,PointCamAtCoord=noop,
        GetFinalRenderedCamCoord=function() return v(0,-2,2) end,
        GetFinalRenderedCamRot=function() return v(-45,0,0) end,GetFinalRenderedCamFov=function() return 70 end,
        RenderScriptCams=function(render) s.render=render end,
        GetWorldCoordFromScreenCoord=function(x,y) local d=v((x-.5)*2,2,-2+(0.5-y)*2); return v(0,-2,2),d/#d end,
        GetScreenCoordFromWorldCoord=function(x,y,z) return true,.5+x*.1,.5-z*.1 end,
        GetInvokingResource=function() return 'consumer' end, GetCurrentResourceName=function() return 'sonorancad' end,
        DisableAllControlActions=noop,DisablePlayerFiring=noop,
        SendNUIMessage=function(message) s.messages[#s.messages+1]=message end,
        RegisterNUICallback=function(name,callback) s.nui[name]=callback end,
        exports=function(name,callback) s.exports[name]=callback end,
        AddEventHandler=function(name,callback) s.events[name]=callback end,
        SetTimeout=function(_,callback) s.timers[#s.timers+1]=callback end,
        CreateThread=function(callback)
            local thread=coroutine.create(callback); s.threads[#s.threads+1]=thread; assert(coroutine.resume(thread)) end,
        Wait=coroutine.yield
    },{__index=_G})
    assert(loadfile('sonorancad/core/placement/math.lua','t',env))()
    assert(loadfile('sonorancad/core/placement/client.lua','t',env))()
    s.env,s.M,s.E=env,env.SonoranPlacementMath,env.SonoranPlacementEditor
    function s:start(extra)
        local options={entity=2,onFinish=function(result) self.result=result end}
        for k,value in pairs(extra or {}) do options[k]=value end
        return self.E.Start(options)
    end
    function s:input(action,extra)
        local data={session=self.messages[1].session,action=action}
        for k,value in pairs(extra or {}) do data[k]=value end
        local replied=false
        self.nui.placementInput(data,function() replied=true end)
        assert(replied)
    end
    function s:frame()
        for _,thread in ipairs(self.threads) do if coroutine.status(thread)~='dead' then assert(coroutine.resume(thread)) end end
    end
    return s
end
local count=0
local function test(name,callback) callback(); count=count+1; print('PASS '..name) end

test('world and attachment rotation decompositions round trip combined rotations',function()
    local s=harness()
    for _,order in ipairs({0,2}) do
        for _,angles in ipairs({v(23,-17,63),v(-42,31,-170),v(5,4,179)}) do
            local m=identity()
            local steps=order==0 and {{v(1,0,0),angles.x},{v(0,1,0),angles.y},{v(0,0,1),angles.z}}
                or {{v(0,1,0),angles.y},{v(1,0,0),angles.x},{v(0,0,1),angles.z}}
            for _,step in ipairs(steps) do m=s.M.rotate(m,step[1],math.rad(step[2])) end
            m.r,m.f,m.u=m.r*2,m.f*3,m.u*.5
            near(s.M.rotation(m,order),angles)
        end
    end
end)

test('relative transforms preserve bone offsets on tilted and rotated vehicles',function()
    local s=harness()
    local frame=s.M.rotate(identity(),s.M.unit(v(1,2,3)),.75)
    frame.p=v(100,200,30)
    local localPose=s.M.rotate(identity(),v(0,1,0),.4); localPose.p=v(.2,.3,.6)
    local function world(point) return frame.r*point.x+frame.f*point.y+frame.u*point.z end
    local placed={p=frame.p+world(localPose.p),r=world(localPose.r),f=world(localPose.f),u=world(localPose.u)}
    local restored=s.M.relative(frame,placed)
    near(restored.p,localPose.p); near(restored.r,localPose.r); near(restored.f,localPose.f); near(restored.u,localPose.u)
end)

test('parallel and backward pointer rays fail without moving the object',function()
    local s=harness()
    assert(not s.M.plane(v(0,0,1),v(1,0,0),v(0,0,0),v(0,0,1)))
    assert(not s.M.plane(v(0,0,1),v(0,0,1),v(0,0,0),v(0,0,1)))
end)

test('mouse axis drag changes only the selected world axis and cancel restores scale',function()
    local s=harness()
    s.matrix.r=s.matrix.r*2; s.matrix.u=s.matrix.u*3
    assert(s:start())
    s:input('down',{handle='x',x=.5,y=.5}); s:input('drag',{x=.7,y=.5}); s:input('up')
    near(s.matrix.p,v(.4,0,0))
    s:input('cancel')
    near(s.matrix.p,v(0,0,0)); near(s.matrix.r,v(2,0,0)); near(s.matrix.u,v(0,0,3))
    assert(not s.focus and not s.frozen[1] and not s.frozen[2] and not s.result.accepted)
end)

test('plane drag and snap stay in the selected plane',function()
    local s=harness(); assert(s:start())
    s:input('snap'); s:input('down',{handle='xy',x=.5,y=.5}); s:input('drag',{x=.617,y=.41})
    assert(math.abs(s.matrix.p.z)<1e-8 and s.matrix.p.x~=0 and s.matrix.p.y~=0)
    assert(math.abs(s.matrix.p.x*100-math.floor(s.matrix.p.x*100+.5))<1e-8)
end)

test('rotation ring rotates the basis without changing scale or origin',function()
    local s=harness(); s.matrix.r=s.matrix.r*2
    assert(s:start()); s:input('mode',{value='rotate'})
    s:input('down',{handle='z',x=1,y=.5}); s:input('drag',{x=.5,y=0})
    near(s.matrix.r,v(0,2,0)); near(s.matrix.f,v(-1,0,0)); near(s.matrix.p,v(0,0,0))
end)

test('local axes follow object orientation',function()
    local s=harness(); s.matrix=s.M.rotate(s.matrix,v(0,0,1),math.pi/2)
    assert(s:start()); s:input('down',{handle='x',x=.5,y=.5}); s:input('drag',{x=.5,y=.3})
    assert(math.abs(s.matrix.p.x)<1e-8 and math.abs(s.matrix.p.z)<1e-8 and math.abs(s.matrix.p.y)>.01)
end)

test('stale sessions, nonfinite input and unadvertised save actions are ignored',function()
    local s=harness(); assert(s:start())
    s:input('down',{handle='x',x=.5,y=.5}); s:input('drag',{x=0/0,y=.5})
    s:input('cancel',{session=-1}); s:input('finish',{choice='save'})
    assert(s.E.IsActive()); near(s.matrix.p,v(0,0,0))
    s:input('finish',{choice='apply'}); assert(s.result.accepted and not s.E.IsActive())
end)

test('maximum placement distance rejects runaway mouse drags',function()
    local s=harness(); assert(s:start({maxDistance=.1}))
    s:input('down',{handle='x',x=.5,y=.5}); s:input('drag',{x=.9,y=.5})
    near(s.matrix.p,v(0,0,0))
end)

for _,reason in ipairs({'death','vehicle exit','entity deletion','caller stop','resource stop','adapter invalidation'}) do
    test(reason..' cancels and restores focus and movement',function()
        local s=harness(); local valid=true
        assert(s:start({validate=function() return valid end}))
        if reason=='death' then s.dead=true elseif reason=='vehicle exit' then s.vehicle=3
        elseif reason=='entity deletion' then s.exists=false
        elseif reason=='caller stop' then s.events.onResourceStop('consumer')
        elseif reason=='resource stop' then s.events.onResourceStop('sonorancad')
        else valid=false end
        s:frame()
        assert(not s.focus and not s.render and not s.frozen[1] and s.destroyed==1 and not s.result.accepted)
    end)
end

test('uncontrolled network entities and competing NUI are rejected',function()
    local s=harness(); s.networked=true
    assert(not s:start()); s.networked=false; s.focus=true; assert(not s:start())
end)

test('network ownership loss cancels an active network entity edit',function()
    local s=harness(); s.networked=true; s.control=true
    assert(s:start()); s.control=false; s:frame()
    assert(not s.E.IsActive() and not s.result.accepted and not s.focus)
end)

test('return camera survives until easing ends and resource stop cleans it once',function()
    local s=harness(); s.frozen[1]=true; s.frozen[2]=true
    assert(s:start()); s:input('finish',{choice='apply'})
    assert(s.destroyed==0 and s.frozen[1] and s.frozen[2])
    s.events.onResourceStop('sonorancad'); s.timers[1]()
    assert(s.destroyed==1)
end)

print(('Passed %d placement tests'):format(count))
