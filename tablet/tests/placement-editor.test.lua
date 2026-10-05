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
    local s={matrix=identity(),nui={},events={},exports={},messages={},threads={},timers={},frozen={},exists=true,destroyed=0,vehicle=0,
        hidden={},hideCalls=0,stopPointingCalls=0,ped=1,time=0,created=0,scriptCalls=0,
        renderingCam=-1,cameras={},logs={},fovWrites={},cameraWrites={},renderCalls=0}
    local noop=function() end
    local function scriptCall()
        s.scriptCalls=s.scriptCalls+1
    end
    local env=setmetatable({ vector3=v,
        print=function(message) s.logs[#s.logs+1]=tostring(message) end,
        GetEntityMatrix=function() local m=s.matrix; return m.f,m.r,m.u,m.p end,
        SetEntityMatrix=function(_,fx,fy,fz,rx,ry,rz,ux,uy,uz,px,py,pz)
            s.matrix={f=v(fx,fy,fz),r=v(rx,ry,rz),u=v(ux,uy,uz),p=v(px,py,pz)} end,
        GetEntityCoords=function() return s.matrix.p end,
        DoesEntityExist=function(entity) return entity==1 or s.exists end,
        PlayerPedId=function() return s.ped end, PlayerId=function() return 1 end,
        GetGameTimer=function() return s.time end,
        GetConvar=function() error('scripted placement must not read native FOV preferences') end,
        ExecuteCommand=function() error('scripted placement must not execute client convar commands') end,
        GetPedBoneCoords=function() error('the editor must not follow the animated player head') end,
        GetRenderingCam=function() return s.renderingCam end,
        DoesCamExist=function(cam) return s.cameras[cam]==true end,
        IsEntityDead=function() return s.dead end,IsPedRagdoll=function() return false end,
        IsPauseMenuActive=function() return false end,GetVehiclePedIsIn=function() return s.vehicle end,
        IsNuiFocused=function() return s.focus end,SetNuiFocus=function(focus) s.focus=focus end,
        SetNuiFocusKeepInput=noop, NetworkGetEntityIsNetworked=function() return s.networked end,
        NetworkHasControlOfEntity=function() return s.control end,
        IsEntityPositionFrozen=function(entity) return s.frozen[entity]==true end,
        FreezeEntityPosition=function(entity,frozen) s.frozen[entity]=frozen end,
        CreateCam=function() scriptCall();s.created=s.created+1;s.cameras[10]=true;return 10 end,
        DestroyCam=function(cam) scriptCall();s.destroyed=s.destroyed+1;s.cameras[cam]=nil end,
        SetCamCoord=function(_,x,y,z)
            scriptCall();s.camera=v(x,y,z);s.cameraWrites[#s.cameraWrites+1]={kind='position',values={x,y,z}}
        end,
        GetCamCoord=function() scriptCall();return s.camera end,
        SetCamRot=function(_,x,y,z)
            scriptCall();s.cameraRotation=v(x,y,z);s.cameraWrites[#s.cameraWrites+1]={kind='rotation',values={x,y,z}}
        end,
        GetCamRot=function()
            scriptCall()
            return s.cameraTarget and s.M.lookRotation(s.cameraTarget-s.camera,v(0,0,1)) or s.cameraRotation
        end,
        SetCamFov=function(_,fov)
            scriptCall();s.fovWrites[#s.fovWrites+1]=fov
            local nativeValue=fov
            if s.emulateNativeMarshalling and math.type(fov)=='integer' then
                nativeValue=string.unpack('f',string.pack('I4',fov))
            end
            s.fov=s.emulateNativeMarshalling and math.max(1,math.min(130,nativeValue)) or nativeValue
        end,
        GetCamFov=function() scriptCall();return s.fov end,
        GetAspectRatio=function() return s.aspect or 1 end,SetCamNearClip=scriptCall,
        PointCamAtCoord=function(_,x,y,z) scriptCall();s.cameraTarget=v(x,y,z) end,
        StopCamPointing=function() scriptCall();s.cameraTarget=nil; s.stopPointingCalls=s.stopPointingCalls+1 end,
        SetEntityLocallyInvisible=function(entity)
            assert(entity==1,'only the local player should be hidden by the editor')
            s.hidden[entity]=true; s.hideCalls=s.hideCalls+1
        end,
        SetEntityCoordsNoOffset=function(_,x,y,z) s.enginePosition=v(x,y,z) end,
        GetFinalRenderedCamCoord=function() return s.renderedPosition or v(0,-2,2) end,
        GetFinalRenderedCamRot=function() return s.renderedRotation or v(-45,0,0) end,
        GetFinalRenderedCamFov=function() return s.renderedFov or 70 end,
        RenderScriptCams=function(render)
            scriptCall();s.render=render;s.renderingCam=render and 10 or -1;s.renderCalls=s.renderCalls+1
        end,
        GetWorldCoordFromScreenCoord=function() error('pointer rays must use the editor script camera') end,
        GetScreenCoordFromWorldCoord=function() error('gizmo projection must use the editor script camera') end,
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
        self.nui.placementInput(data,function(response) replied=true;self.lastReply=response end)
        assert(replied)
    end
    function s:frame(elapsed)
        self.time=self.time+(elapsed or 16)
        -- This native lasts one frame; a stopped editor must not renew it.
        self.hidden={}
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
    near(s.matrix.p,v(.4*math.sqrt(8)*math.tan(math.rad(35)),0,0))
    near(s.enginePosition,s.matrix.p)
    s:input('cancel')
    near(s.matrix.p,v(0,0,0)); near(s.matrix.r,v(2,0,0)); near(s.matrix.u,v(0,0,3))
    assert(not s.focus and not s.frozen[1] and not s.frozen[2] and not s.result.accepted)
end)

test('camera rays match the selected script camera including roll and aspect',function()
    local s=harness()
    local origin,direction=s.M.cameraRay(v(10,20,30),v(0,0,90),90,2,.5,.5)
    near(origin,v(10,20,30)); near(direction,v(-1,0,0))
    local _,edge=s.M.cameraRay(v(0,0,0),v(0,0,0),90,2,1,.5)
    near(edge,s.M.unit(v(2,1,0)))
    local _,rolled=s.M.cameraRay(v(0,0,0),v(0,90,0),90,1,1,.5)
    near(rolled,s.M.unit(v(0,1,-1)))
end)

test('editor projection and pointer rays agree for translated rolled cameras and wide aspect ratios',function()
    local s=harness()
    for _,case in ipairs({
        {position=v(0,-2,2),rotation=v(-45,0,0),fov=65,aspect=1},
        {position=v(741,2681,41),rotation=v(-13,7,-42),fov=80,aspect=16/9},
        {position=v(-103,15,9),rotation=v(22,-18,130),fov=35,aspect=21/9}
    }) do
        for _,cursor in ipairs({{.5,.5},{.1,.2},{.9,.8}}) do
            local origin,direction=s.M.cameraRay(case.position,case.rotation,case.fov,case.aspect,cursor[1],cursor[2])
            local point=s.M.project(case.position,case.rotation,case.fov,case.aspect,origin+direction*4)
            assert(point and math.abs(point.x-cursor[1])<1e-6 and math.abs(point.y-cursor[2])<1e-6)
        end
        local forward=s.M.cameraBasis(case.rotation).f
        assert(not s.M.project(case.position,case.rotation,case.fov,case.aspect,case.position-forward))
    end
end)

test('look rotation aims the camera at the target and respects tilted up vectors',function()
    local s=harness()
    for _,case in ipairs({
        {direction=v(0,1,-.4),up=v(0,0,1)},
        {direction=v(-2,3,.7),up=v(.3,-.1,1)},
        {direction=v(0,0,1),up=v(0,1,0)}
    }) do
        local direction=s.M.unit(case.direction)
        local rotation=s.M.lookRotation(case.direction,case.up)
        assert(rotation)
        local camera=s.M.cameraBasis(rotation)
        near(camera.f,direction)
        near(camera.u,s.M.unit(case.up-direction*s.M.dot(case.up,direction)))
    end
    assert(s.M.lookRotation(v(0,0,0),v(0,0,1))==nil)
end)

test('drag can move a preview from outside to inside the vehicle in world coordinates',function()
    local s=harness()
    s.matrix.p=v(1856,3677,34)
    local start=s.matrix.p
    assert(s:start({view={position=start+v(0,-2,2),rotation=v(-45,0,0),fov=70}}))
    s:input('down',{handle='x',x=.75,y=.5})
    s:input('drag',{x=.25,y=.5});s:input('up')
    assert(s.matrix.p.x<start.x-1 and s.matrix.p.x>start.x-3)
    assert(s.matrix.p.y==start.y and s.matrix.p.z==start.z)
    near(s.enginePosition,s.matrix.p)
end)

test('camera pan preserves orientation and driver view restores its starting pose',function()
    local s=harness()
    local view={position=v(0,-.5,.4),rotation=v(-8,0,0),fov=65}
    assert(s:start({view=view}));near(s.camera,view.position)
    s:input('camera',{dx=.03,dy=.02,zoom=0,pan=true})
    assert(#(s.camera-view.position)>.01);near(s.cameraRotation,view.rotation)
    s:input('view');near(s.camera,view.position);near(s.cameraRotation,view.rotation)
end)

test('script camera natives receive floats for integer view settings and clamped FOV values',function()
    local s=harness();s.emulateNativeMarshalling=true
    local view={mode='cockpit',position=v(10,20,30),rotation=v(-8,0,35),fov=65}
    assert(math.type(view.fov)=='integer')
    assert(s:start({view=view}))
    assert(s.fov==65 and math.type(s.fovWrites[1])=='float','SetCamFov must receive the initial 65 degrees as a Lua float')
    for _=1,20 do s:input('camera',{dx=0,dy=0,zoom=1}) end
    assert(s.fov==85 and math.type(s.fovWrites[#s.fovWrites])=='float','upper FOV clamp must be marshalled as a float')
    for _=1,20 do s:input('camera',{dx=0,dy=0,zoom=-1}) end
    assert(s.fov==35 and math.type(s.fovWrites[#s.fovWrites])=='float','lower FOV clamp must be marshalled as a float')
    s:input('view')
    assert(s.fov==65 and math.type(s.fovWrites[#s.fovWrites])=='float','view reset must preserve float marshalling')
    for _,write in ipairs(s.cameraWrites) do
        for _,value in ipairs(write.values) do
            assert(math.type(value)=='float','camera '..write.kind..' values must be marshalled as floats')
        end
    end
end)

test('gizmos hide at or behind the camera near plane instead of projecting oversized handles',function()
    local s=harness()
    local view={mode='cockpit',position=v(0,0,0),rotation=v(0,0,0),fov=65}
    assert(s:start({view=view}))
    for _,depth in ipairs({-1,0,.01,.02}) do
        s.matrix.p=v(0,depth,0)
        for _,mode in ipairs({'move','rotate'}) do
            s:input('mode',{value=mode});s:frame()
            local frame=s.messages[#s.messages]
            assert(s.E.IsActive() and frame.type=='placement_frame' and #frame.handles==0,
                'handles must be hidden when the pivot is at or behind the near plane')
            assert(not frame.pivot,'the hidden gizmo must not leave a selectable center marker')
        end
    end
end)

test('gizmo screen size stays compact at close positive depths and narrow camera FOVs',function()
    local s=harness()
    assert(s:start({view={mode='cockpit',position=v(0,0,0),rotation=v(0,0,0),fov=65}}))
    for _,fov in ipairs({.5,35,65,85}) do
        s.fov=fov
        for _,depth in ipairs({.021,.03,.1,1,5}) do
            s.matrix.p=v(0,depth,0)
            for _,mode in ipairs({'move','rotate'}) do
                s:input('mode',{value=mode});s:frame()
                local frame=s.messages[#s.messages]
                assert(s.E.IsActive() and frame.pivot and #frame.handles==(mode=='move' and 6 or 4))
                for _,handle in ipairs(frame.handles) do
                    for _,point in ipairs(handle.points) do
                        assert(point and math.abs(point.x-.5)<.13 and math.abs(point.y-.5)<.13,
                            'positive-depth handles must keep a compact projected size without a world-size floor')
                    end
                end
            end
        end
    end
end)

test('cockpit look and zoom preserve the eye anchor and bound the field of view',function()
    local s=harness()
    local view={mode='cockpit',position=v(10,20,3),rotation=v(-8,0,35),fov=65}
    assert(s:start({view=view}))
    s:input('camera',{dx=.05,dy=-.03,zoom=0})
    near(s.camera,view.position)
    assert(#(s.env.GetCamRot()-view.rotation)>.1)
    assert(not s.cameraTarget and s.fov==65)
    local rotation=s.env.GetCamRot()
    for _=1,100 do s:input('camera',{dx=0,dy=0,zoom=-1}) end
    assert(s.fov==35); near(s.camera,view.position); near(s.env.GetCamRot(),rotation)
    for _=1,100 do s:input('camera',{dx=0,dy=0,zoom=1}) end
    assert(s.fov==85); near(s.camera,view.position); near(s.env.GetCamRot(),rotation)
    for _,direction in ipairs({-1,1}) do
        for _=1,100 do s:input('camera',{dx=.1,dy=direction*.1,zoom=0}) end
        local looked=s.env.GetCamRot()
        assert(math.abs(looked.x)<90 and looked.x*direction<0,'look must stop before flipping upside down')
        assert(looked.z>=-180 and looked.z<=180,'yaw must stay normalized after repeated look input')
        near(s.camera,view.position)
    end
    s:input('view')
    near(s.camera,view.position);near(s.env.GetCamRot(),view.rotation);assert(s.fov==65)
    assert(#s.fovWrites>2,'zoom must update the owned scripted camera FOV directly')
end)

test('fixed cockpit pose and gizmo remain stable as the gameplay camera and animated head move',function()
    local s=harness();s.vehicle=3;s.aspect=16/9
    local view={mode='cockpit',position=v(0,-.5,.4),rotation=v(-8,0,0),fov=65}
    s.matrix.p=v(0,.5,.1)
    assert(s:start({view=view,pivotOffset=v(0,0,.1)}));s:frame()
    local initialPivot=s.messages[#s.messages].pivot
    assert(initialPivot and s.created==1 and s.render and s.hideCalls==0)
    for i=1,10 do
        s.renderedPosition=v(20+i,30-i,40)
        s.renderedRotation=v(70,i*20,180);s.renderedFov=100
        s:frame()
        near(s.camera,view.position);near(s.env.GetCamRot(),view.rotation)
        assert(s.fov==65 and s.hideCalls==0 and s.E.IsActive())
        local pivot=s.messages[#s.messages].pivot
        assert(pivot and math.abs(pivot.x-initialPivot.x)<1e-6 and math.abs(pivot.y-initialPivot.y)<1e-6)
    end
    s:input('focus')
    near(s.camera,view.position)
    s:input('view')
    near(s.camera,view.position);near(s.env.GetCamRot(),view.rotation)
end)

test('the logged cabin geometry produces visible handles at the model center using the owned camera',function()
    local s=harness();s.aspect=16/9
    s.matrix.p=v(1610.588,1238.010,86.595)
    local offset=v(0,.05,.12)
    local center=s.matrix.p+offset
    local eye=v(1610.325,1237.315,86.961)
    local view={mode='cockpit',position=eye,rotation=s.M.lookRotation(center-eye),fov=65}
    -- The old gameplay camera data must not be used for editor projection or picking.
    s.renderedPosition=eye;s.renderedRotation=v(4,2.4,-.1);s.renderedFov=40.5
    assert(s:start({view=view,pivotOffset=offset,focusOffset=offset}));s:frame()
    local frame=s.messages[#s.messages]
    assert(frame.pivot and math.abs(frame.pivot.x-.5)<1e-6 and math.abs(frame.pivot.y-.5)<1e-6)
    assert(#frame.handles==6)
    for _,handle in ipairs(frame.handles) do
        for _,point in ipairs(handle.points) do assert(point and point.x>0 and point.x<1 and point.y>0 and point.y<1) end
    end
    local handle=frame.handles[1].points[2]
    s:input('down',{handle='x',x=handle.x,y=handle.y})
    s:input('drag',{x=handle.x+.05,y=handle.y});s:input('up')
    assert(s.matrix.p.x>1610.588 and math.abs(s.matrix.p.y-1238.010)<1e-6 and math.abs(s.matrix.p.z-86.595)<1e-6)
    near(s.camera,eye)
end)

test('plane dragging uses the displayed offset pivot and preserves origin-to-center displacement',function()
    local s=harness()
    s.matrix.r=v(2,0,0);s.matrix.f=v(0,3,0);s.matrix.u=v(0,0,.5)
    local offset=v(.2,-.1,.8)
    local center=s.matrix.p+s.matrix.r*offset.x+s.matrix.f*offset.y+s.matrix.u*offset.z
    local eye=center+v(0,-2,2)
    assert(s:start({view={position=eye,rotation=s.M.lookRotation(center-eye),fov=65},pivotOffset=offset}))
    local function pointer(point) return s.M.project(s.camera,s.cameraRotation,s.fov,1,point) end
    local start=pointer(center+v(.1,.1,0));local finish=pointer(center+v(.3,.2,0))
    s:input('down',{handle='xy',x=start.x,y=start.y});s:input('drag',{x=finish.x,y=finish.y});s:input('up')
    near(s.matrix.p,v(.2,.1,0))
    near(s.matrix.p+s.matrix.r*offset.x+s.matrix.f*offset.y+s.matrix.u*offset.z,center+v(.2,.1,0))
end)

for _,accept in ipairs({false,true}) do
    test('rotation around the model center preserves scale and '..(accept and 'saves the compensated origin' or 'cancels to the original pose'),function()
        local s=harness()
        s.matrix={r=v(2,0,0),f=v(0,3,0),u=v(0,0,.5),p=v(10,20,30)}
        local original=s.matrix
        local offset=v(.2,-.1,.3)
        local center=original.p+original.r*offset.x+original.f*offset.y+original.u*offset.z
        local eye=center+v(0,-2,2)
        assert(s:start({view={position=eye,rotation=s.M.lookRotation(center-eye),fov=65},pivotOffset=offset}))
        s:input('mode',{value='rotate'})
        local start=s.M.project(s.camera,s.cameraRotation,s.fov,1,center+v(.3,0,0))
        local finish=s.M.project(s.camera,s.cameraRotation,s.fov,1,center+v(0,.3,0))
        s:input('down',{handle='z',x=start.x,y=start.y});s:input('drag',{x=finish.x,y=finish.y});s:input('up')
        near(s.matrix.r,v(0,2,0));near(s.matrix.f,v(-3,0,0));near(s.matrix.u,v(0,0,.5))
        near(s.matrix.p+s.matrix.r*offset.x+s.matrix.f*offset.y+s.matrix.u*offset.z,center)
        assert(#(s.matrix.p-original.p)>.1,'rotating around the bounds center must compensate the entity origin')
        local placed=s.matrix
        s:input(accept and 'finish' or 'cancel',{choice='apply'})
        assert(s.result.accepted==accept)
        if accept then
            near(s.result.matrix.p,placed.p);near(s.result.matrix.r,placed.r);near(s.matrix.p,placed.p)
        else
            near(s.matrix.p,original.p);near(s.matrix.r,original.r);near(s.matrix.f,original.f);near(s.matrix.u,original.u)
        end
    end)
end

test('cockpit focus uses the transformed model bounds center without relocating the eye',function()
    local s=harness()
    s.matrix=s.M.rotate(identity(),v(0,0,1),math.pi/2)
    s.matrix.p=v(4,5,6);s.matrix.r=s.matrix.r*2;s.matrix.u=s.matrix.u*.5
    local view={mode='cockpit',position=v(3,4,7),rotation=v(0,0,0),fov=65,up=v(0,0,1)}
    local focus=v(.2,-.4,.8)
    assert(s:start({view=view,focusOffset=focus}))
    local function assertFocus()
        s:input('focus')
        local m=s.matrix
        local center=m.p+m.r*focus.x+m.f*focus.y+m.u*focus.z
        near(s.camera,view.position)
        near(s.M.cameraBasis(s.env.GetCamRot()).f,s.M.unit(center-view.position))
        assert(s.fov==65 and not s.cameraTarget)
    end
    assertFocus()
    s.matrix.p=s.matrix.p+v(.5,-.2,.3)
    assertFocus()
    s:input('camera',{dx=.05,dy=.02,zoom=0})
    near(s.camera,view.position)
    s:input('view')
    near(s.camera,view.position);near(s.env.GetCamRot(),view.rotation)
end)

test('cockpit lean stays within the eye anchor limit and view reset clears accumulated pan',function()
    local s=harness()
    local view={mode='cockpit',position=v(0,-.5,.4),rotation=v(-8,0,0),fov=65}
    assert(s:start({view=view}))
    s:input('camera',{dx=.03,dy=.02,zoom=0,pan=true})
    local first=s.camera
    assert(#(first-view.position)>0)
    for _=1,100 do s:input('camera',{dx=.1,dy=.1,zoom=0,pan=true}) end
    assert(#(s.camera-view.position)<=.120001)
    near(s.env.GetCamRot(),view.rotation)
    local leaned=s.camera
    s:input('camera',{dx=.05,dy=-.01,zoom=-1})
    near(s.camera,leaned)
    s:input('view')
    near(s.camera,view.position);near(s.env.GetCamRot(),view.rotation);assert(s.fov==65)
    s:input('camera',{dx=.03,dy=.02,zoom=0,pan=true})
    near(s.camera,first)
end)

test('generic station cameras still orbit and dolly with explicit rotations that reset',function()
    local s=harness()
    local view={position=v(0,-2,2),rotation=v(-45,0,0),fov=70}
    assert(s:start({view=view}))
    s:input('camera',{dx=.05,dy=.03,zoom=0})
    assert(#(s.camera-view.position)>.1 and not s.cameraTarget)
    near(s.M.cameraBasis(s.env.GetCamRot()).f,s.M.unit(s.matrix.p-s.camera))
    local distance=#(s.camera-s.matrix.p)
    s:input('camera',{dx=0,dy=0,zoom=1})
    assert(#(s.camera-s.matrix.p)>distance and s.fov==70)
    s:input('focus');assert(math.abs(#(s.camera-s.matrix.p)-.8)<1e-6)
    s:input('view')
    near(s.camera,view.position);near(s.env.GetCamRot(),view.rotation)
    assert(not s.cameraTarget and s.stopPointingCalls>0 and s.hideCalls==0)
end)

for _,action in ipairs({'cancel','finish'}) do
    test('cockpit local player hiding ends on '..action,function()
        local s=harness()
        assert(s:start({view={mode='cockpit',hidePlayer=true,position=v(0,-.5,.4),rotation=v(-8,0,0),fov=65}}))
        assert(s.hidden[1] and s.hideCalls==1)
        s:frame();assert(s.hidden[1] and s.hideCalls==2)
        s:input(action,{choice='apply'})
        local calls=s.hideCalls
        s:frame();s:frame()
        assert(not s.hidden[1] and s.hideCalls==calls and not s.E.IsActive())
    end)
end

test('gizmo has compact bidirectional handles and a view rotation ring',function()
    local s=harness();assert(s:start());s:frame()
    local frame=s.messages[#s.messages]
    assert(frame.pivot and #frame.handles==6)
    assert(frame.handles[1].points[1].x<.5 and frame.handles[1].points[2].x>.5)
    s:input('mode',{value='rotate'});s:frame()
    assert(s.messages[#s.messages].handles[4].id=='view')
    s:input('down',{handle='view',x=.7,y=.5});s:input('drag',{x=.5,y=.3})
    assert(#(s.matrix.r-v(1,0,0))>.01)
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
        assert(s:start({validate=function() return valid end,
            view={mode='cockpit',hidePlayer=true,position=v(0,-.5,.4),rotation=v(-8,0,0),fov=65}}))
        s:frame();assert(s.hidden[1])
        if reason=='death' then s.dead=true elseif reason=='vehicle exit' then s.vehicle=3
        elseif reason=='entity deletion' then s.exists=false
        elseif reason=='caller stop' then s.events.onResourceStop('consumer')
        elseif reason=='resource stop' then s.events.onResourceStop('sonorancad')
        else valid=false end
        s:frame()
        assert(not s.focus and not s.render and not s.frozen[1] and s.destroyed==1 and not s.result.accepted)
        local hideCalls=s.hideCalls
        s:frame()
        assert(not s.hidden[1] and s.hideCalls==hideCalls)
    end)
end

test('uncontrolled network entities and competing NUI are rejected',function()
    local s=harness(); s.networked=true
    assert(not s:start()); s.networked=false; s.focus=true; assert(not s:start())
end)

test('another scripted camera prevents taking placement ownership at entry',function()
    local s=harness();s.renderingCam=77;s.cameras[77]=true
    assert(not s:start())
    assert(s.created==0 and s.renderCalls==0 and s.renderingCam==77 and s.cameras[77])
end)

for _,queuedSave in ipairs({false,true}) do
    test('a foreign scripted camera cancels placement without disabling its renderer '..tostring(queuedSave),function()
        local s=harness();assert(s:start())
        s:input('down',{handle='x',x=.5,y=.5});s:input('drag',{x=.7,y=.5});s:input('up')
        assert(s.matrix.p.x>0)
        local renders=s.renderCalls
        s.renderingCam=77;s.cameras[77]=true
        if queuedSave then s:input('finish',{choice='apply'}) else s:frame() end
        assert(not s.E.IsActive() and not s.result.accepted and not s.focus)
        near(s.matrix.p,v(0,0,0))
        assert(s.renderCalls==renders and s.renderingCam==77 and s.cameras[77])
        assert(not s.cameras[10] and s.destroyed==1)
    end)
end

for _,queuedSave in ipairs({false,true}) do
    test('returning to gameplay cancels placement before '..(queuedSave and 'a queued save' or 'another gizmo frame'),function()
        local s=harness();assert(s:start());s:frame()
        s:input('down',{handle='x',x=.5,y=.5});s:input('drag',{x=.7,y=.5});s:input('up')
        assert(s.matrix.p.x>0 and s.cameras[10])
        s.renderingCam=-1 -- The scripted camera still exists, but it no longer renders.
        if queuedSave then s:input('finish',{choice='apply'}) else s:frame() end
        assert(not s.E.IsActive() and not s.result.accepted and not s.focus)
        near(s.matrix.p,v(0,0,0))
        assert(not s.cameras[10] and s.destroyed==1)
        local last=s.messages[#s.messages]
        assert(last.type=='placement_editor' and last.enabled==false)
        local messages=#s.messages;s:frame()
        assert(#s.messages==messages,'do not continue projecting handles over the gameplay camera')
    end)
end

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
