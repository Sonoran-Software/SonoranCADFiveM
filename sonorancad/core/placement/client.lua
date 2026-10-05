-- Reusable, mouse-only transform editor. The caller owns persistence and permissions.
SonoranPlacementEditor = {}
local E, M = SonoranPlacementEditor, SonoranPlacementMath
local active, serial = nil, 0
local returning = {}
local axes = { x = vector3(1,0,0), y = vector3(0,1,0), z = vector3(0,0,1) }
local function pack(v) return { x = v.x, y = v.y, z = v.z } end
local function finite(n) return type(n) == 'number' and n == n and math.abs(n) < 1e8 end
local function basis(s, matrix)
    if s.space == 'world' then return axes end
    return { x = M.unit(matrix.r), y = M.unit(matrix.f), z = M.unit(matrix.u) }
end
local function foreignCamera(cam)
    local rendering=GetRenderingCam()
    return rendering~=cam and DoesCamExist(rendering)
end
local function ownsCamera(s)
    return DoesCamExist(s.cam) and GetRenderingCam()==s.cam
end
local function cameraRelease(cam, immediate)
    if foreignCamera(cam) then DestroyCam(cam,false); return end
    RenderScriptCams(false, not immediate, immediate and 0 or 250, true, true)
    if immediate then DestroyCam(cam,false) else
        returning[cam] = true
        SetTimeout(250,function()
            if returning[cam] then returning[cam] = nil; DestroyCam(cam,false) end
        end)
    end
end
local function finish(accepted, action, immediate, reason)
    local s = active
    if not s then return end
    active = nil
    local exists = DoesEntityExist(s.entity)
    local matrix = exists and M.capture(s.entity) or s.original
    if not accepted and exists then M.apply(s.entity,s.original) end
    if exists then FreezeEntityPosition(s.entity,s.entityFrozen) end
    if s.frozePed and DoesEntityExist(s.ped) then FreezeEntityPosition(s.ped,false) end
    SendNUIMessage({type='placement_editor', enabled=false, session=s.id})
    SetNuiFocus(false,false)
    cameraRelease(s.cam,immediate)
    if s.options.onFinish then
        local ok, err = pcall(s.options.onFinish, { accepted=accepted and exists, action=action,
            entity=s.entity, matrix=matrix, position=pack(matrix.p), rotation=pack(M.rotation(matrix,2)),reason=reason })
        if not ok then print('[placement] Completion callback failed: '..tostring(err)) end
    end
end
function E.IsActive() return active ~= nil end
function E.Cancel() finish(false,nil,true) end
local function cameraState(s)
    return {position=GetCamCoord(s.cam),rotation=GetCamRot(s.cam,2),fov=GetCamFov(s.cam)}
end
local function cameraRay(s,x,y)
    local camera=cameraState(s)
    return M.cameraRay(camera.position,camera.rotation,camera.fov,GetAspectRatio(false),x,y)
end
local function cameraPose(s,position,rotation,fov)
    -- PointCamAtCoord keeps an aim target active across later SetCamRot calls.
    -- Own the complete pose so pan and restoring the view cannot inherit that target.
    StopCamPointing(s.cam)
    -- The non-OAL Lua native bridge preserves integer bits instead of coercing
    -- them to floats. This also covers integer FOV limits returned by min/max.
    SetCamCoord(s.cam,position.x+0.0,position.y+0.0,position.z+0.0)
    SetCamRot(s.cam,rotation.x+0.0,rotation.y+0.0,rotation.z+0.0,2)
    if fov then SetCamFov(s.cam,fov+0.0) end
end
local function focusPoint(s)
    local m=M.capture(s.entity)
    local offset=s.options.focusOffset
    return offset and M.transformPoint(m,offset) or m.p
end
local function aimCamera(s,position,point)
    local rotation=M.lookRotation(point-position,s.view.up)
    if rotation then cameraPose(s,position,rotation) end
end
local function frame(s)
    local matrix = M.capture(s.entity)
    local b = basis(s,matrix)
    local view=cameraState(s)
    local camera=M.cameraBasis(view.rotation)
    local pivot=s.options.pivotOffset and M.transformPoint(matrix,s.options.pivotOffset) or matrix.p
    local function projected(point) return M.project(view.position,view.rotation,view.fov,GetAspectRatio(false),point) end
    local depth=M.dot(pivot-view.position,camera.f)
    -- Keep the apparent size constant, including when the prop is close to the
    -- camera. A minimum world size balloons the handles at small depths/FOVs.
    local size=depth*math.tan(math.rad(view.fov)*.5)*.18
    local handles = {}
    if depth>.02 and s.mode == 'move' then
        for _, key in ipairs({'x','y','z'}) do
            handles[#handles+1] = { id=key, kind='axis', points={projected(pivot-b[key]*size),projected(pivot+b[key]*size)} }
        end
        for _, pair in ipairs({'xy','xz','yz'}) do
            local a,c = b[pair:sub(1,1)],b[pair:sub(2,2)]
            local points = {}
            for _, v in ipairs({{.18,.18},{.4,.18},{.4,.4},{.18,.4}}) do
                points[#points+1] = projected(pivot + (a*v[1]+c*v[2])*size)
            end
            handles[#handles+1] = {id=pair,kind='plane',points=points}
        end
    elseif depth>.02 then
        for _, key in ipairs({'x','y','z','view'}) do
            local normal=key=='view' and camera.f or b[key]
            local a = key=='view' and camera.r or b[key == 'x' and 'y' or 'x']
            local c = M.cross(normal,a)
            local radius=key=='view' and size*1.15 or size
            local points = {}
            for i=0,48 do
                local angle = i*math.pi/24
                points[#points+1] = projected(pivot+(a*math.cos(angle)+c*math.sin(angle))*radius)
            end
            handles[#handles+1] = {id=key,kind='ring',points=points}
        end
    end
    if s.cockpit and not s.loggedCamera then
        s.loggedCamera=true
        print(('[placement] Cabin view ready: camera=%.3f/%.3f/%.3f rotation=%.1f/%.1f/%.1f fov=%.1f requestedFov=%.1f pivotDepth=%.3f')
            :format(view.position.x,view.position.y,view.position.z,view.rotation.x,view.rotation.y,view.rotation.z,
                view.fov,s.view.fov,depth))
    end
    SendNUIMessage({type='placement_frame',session=s.id,handles=handles,ready=true,
        cameraZoom=true,cameraOrbit=s.orbit,mode=s.mode,space=s.space,
        snap=s.snap,selected=s.drag and s.drag.handle,pivot=depth>.02 and projected(pivot) or false,
        position=pack(matrix.p),rotation=pack(M.rotation(matrix,2))})
end
local function validSession(s)
    if not DoesEntityExist(s.entity) or PlayerPedId() ~= s.ped or IsEntityDead(s.ped)
        or IsPedRagdoll(s.ped) or IsPauseMenuActive() or GetVehiclePedIsIn(s.ped,false) ~= s.vehicle then return false end
    if NetworkGetEntityIsNetworked(s.entity) and not NetworkHasControlOfEntity(s.entity) then return false end
    if s.options.validate and not s.options.validate() then return false end
    return true
end
function E.Start(options)
    if active or next(returning) then return false,'Finish the current placement first.' end
    if type(options) ~= 'table' or not DoesEntityExist(options.entity or 0) then return false,'Placement entity is missing.' end
    if IsNuiFocused() then return false,'Close the tablet or other windows first.' end
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedRagdoll(ped) then return false,'You cannot place objects in this state.' end
    if NetworkGetEntityIsNetworked(options.entity) and not NetworkHasControlOfEntity(options.entity) then
        return false,'You do not control this placement entity.'
    end
    if foreignCamera(nil) then return false,'Close the other scripted camera before placing the display.' end
    local vehicle=GetVehiclePedIsIn(ped,false)
    serial = serial+1
    local matrix = M.capture(options.entity)
    local s = { id=serial,entity=options.entity,original=matrix,options=options,owner=GetInvokingResource(),
        ped=ped,vehicle=vehicle,mode='move',space='local',snap=false,
        actions=options.actions or {{id='apply',label='Apply'}},
        entityFrozen=IsEntityPositionFrozen(options.entity) }
    local view=options.view
    local p,r = view and view.position or GetFinalRenderedCamCoord(),view and view.rotation or GetFinalRenderedCamRot(2)
    s.view={position=p,rotation=r,fov=view and view.fov or GetFinalRenderedCamFov(),up=view and view.up}
    s.cockpit=view and view.mode=='cockpit'
    s.hidePlayer=s.cockpit and view.hidePlayer==true
    s.orbit=false
    s.lookAnchor=p
    s.lean=vector3(0,0,0)
    s.cam=CreateCam('DEFAULT_SCRIPTED_CAMERA',true)
    cameraPose(s,p,r,s.view.fov); SetCamNearClip(s.cam,.01)
    s.frozePed = s.vehicle == 0 and not IsEntityPositionFrozen(ped)
    if s.frozePed then FreezeEntityPosition(ped,true) end
    FreezeEntityPosition(s.entity,true)
    active = s
    if s.hidePlayer then SetEntityLocallyInvisible(s.ped) end
    RenderScriptCams(true,false,0,true,true)
    SendNUIMessage({type='placement_editor',enabled=true,session=s.id,title=options.title or 'Object placement',actions=s.actions,
        ready=true,cameraZoom=true,cameraOrbit=s.orbit,cameraMode=s.cockpit and 'cockpit' or 'orbit'})
    SetNuiFocus(true,true)
    SetNuiFocusKeepInput(false)
    CreateThread(function()
        local ok,err = xpcall(function()
            while active == s do
                Wait(0)
                if active ~= s then break end
                if not validSession(s) then finish(false,nil,true); break end
                if not ownsCamera(s) then
                    finish(false,nil,true,'Placement cancelled because another camera took control.'); break
                end
                -- Local, current-frame visibility only; nothing to restore on exit/resource stop.
                if s.hidePlayer then SetEntityLocallyInvisible(s.ped) end
                DisableAllControlActions(0)
                DisablePlayerFiring(PlayerId(),true)
                frame(s)
            end
        end,debug.traceback)
        if not ok then
            if active == s then finish(false,nil,true) end
            print('[placement] Editor stopped: '..tostring(err))
        end
    end)
    return true
end
local function pointer(data)
    return finite(data.x) and finite(data.y) and data.x >= 0 and data.x <= 1 and data.y >= 0 and data.y <= 1
end
RegisterNUICallback('placementInput',function(data,cb)
    local s = active
    if type(data) ~= 'table' or not s or data.session ~= s.id then cb({ok=false}); return end
    local ok,err = pcall(function()
        if data.action=='cancel' then finish(false); return end
        if not ownsCamera(s) then
            finish(false,nil,true,'Placement cancelled because another camera took control.'); return
        end
        if data.action == 'finish' then
            for _, action in ipairs(s.actions) do
                if data.choice == action.id and validSession(s) then finish(true,action.id); break end
            end
        elseif data.action == 'mode' and (data.value == 'move' or data.value == 'rotate') then s.mode=data.value; s.drag=nil
        elseif data.action == 'space' then s.space=s.space == 'local' and 'world' or 'local'; s.drag=nil
        elseif data.action == 'snap' then s.snap=not s.snap
        elseif data.action == 'orbit' and s.cockpit then
            s.orbit=not s.orbit
            s.drag=nil
            -- Switching controls must not return an orbited camera to the seat.
            s.lookAnchor=GetCamCoord(s.cam)
            s.lean=vector3(0,0,0)
        elseif data.action == 'reset' then M.apply(s.entity,s.original); s.drag=nil
        elseif data.action == 'up' then s.drag=nil
        elseif data.action == 'down' and pointer(data) and type(data.handle) == 'string' then
            local m = M.capture(s.entity)
            local b = basis(s,m)
            local a = data.handle=='view' and M.cameraBasis(cameraState(s).rotation).f or b[data.handle:sub(1,1)]
            if not a then return end
            local origin,direction = cameraRay(s,data.x,data.y)
            local normal,kind
            if s.mode == 'rotate' and (#data.handle == 1 or data.handle=='view') then normal=a; kind='rotate'
            elseif s.mode == 'move' and #data.handle == 1 then normal=M.unit(direction-a*M.dot(direction,a)); kind='axis'
            elseif s.mode == 'move' and ({xy=true,xz=true,yz=true})[data.handle] then
                normal=M.cross(a,b[data.handle:sub(2,2)]); kind='plane'
            else return end
            local pivot=s.options.pivotOffset and M.transformPoint(m,s.options.pivotOffset) or m.p
            local hit=M.plane(origin,direction,pivot,normal)
            if hit and #normal > .001 then s.drag={matrix=m,pivot=pivot,axis=a,normal=normal,hit=hit,kind=kind,handle=data.handle} end
        elseif data.action == 'drag' and s.drag and pointer(data) then
            local d=s.drag
            local origin,direction=cameraRay(s,data.x,data.y)
            local hit=M.plane(origin,direction,d.pivot,d.normal)
            if not hit then return end
            local m=d.matrix
            if d.kind == 'rotate' then
                local angle=M.angle(M.unit(d.hit-d.pivot),M.unit(hit-d.pivot),d.axis)
                angle=M.snap(angle,s.snap and math.rad(5) or 0)
                m=M.rotate(m,d.axis,angle,d.pivot)
            else
                local delta=hit-d.hit
                if d.kind == 'axis' then delta=d.axis*M.snap(M.dot(delta,d.axis),s.snap and .01 or 0) end
                if d.kind == 'plane' and s.snap then
                    local tangent=M.cross(d.normal,d.axis)
                    delta=d.axis*M.snap(M.dot(delta,d.axis),.01)+tangent*M.snap(M.dot(delta,tangent),.01)
                end
                if #delta > (s.options.maxDistance or 10) then return end
                m={r=m.r,f=m.f,u=m.u,p=m.p+delta}
            end
            if #(m.p-s.original.p) <= (s.options.maxDistance or 10) then M.apply(s.entity,m) end
        elseif data.action == 'view' then
            s.drag=nil
            local view=s.view
            s.orbit=false
            s.lookAnchor=view.position
            s.lean=vector3(0,0,0)
            cameraPose(s,view.position,view.rotation,view.fov)
        elseif data.action == 'focus' or (data.action == 'camera' and finite(data.dx) and finite(data.dy) and finite(data.zoom)) then
            if data.action == 'focus' then data.dx,data.dy,data.zoom=0,0,0 end
            s.drag=nil
            local center=focusPoint(s)
            local offset=GetCamCoord(s.cam)-center
            local radius=math.max(.15,#offset)
            if s.cockpit then
                if data.action=='focus' then
                    -- Re-aim from the current position without moving the camera.
                    aimCamera(s,GetCamCoord(s.cam),center)
                    return
                end
                local rotation=GetCamRot(s.cam,2)
                local fov=math.max(35,math.min(85,GetCamFov(s.cam)*math.exp(math.max(-1,math.min(1,data.zoom))*.08)))
                if s.orbit and not data.pan and (data.dx~=0 or data.dy~=0) then
                    -- Orbit the current display center from the current camera position.
                    -- Lens-only input never moves or re-aims the camera.
                    if #offset>.02 then
                        local up=M.unit(s.view.up or axes.z)
                        local pose=M.cameraBasis(rotation)
                        pose.p=GetCamCoord(s.cam)
                        pose=M.rotate(pose,up,-math.max(-.1,math.min(.1,data.dx))*4,center)
                        local direction=M.unit(pose.p-center)
                        local elevation=math.asin(math.max(-1,math.min(1,M.dot(direction,up))))
                        local pitchAxis=M.cross(direction,up)
                        if #pitchAxis<.0001 then
                            pitchAxis=M.cross(math.abs(up.z)<.9 and axes.z or axes.y,up)
                        end
                        local limit=math.rad(80)
                        local pitch=math.max(-limit,math.min(limit,elevation+math.max(-.1,math.min(.1,data.dy))*3))
                        pose=M.rotate(pose,M.unit(pitchAxis),pitch-elevation,center)
                        rotation=M.lookRotation(center-pose.p,up) or rotation
                        s.lookAnchor=pose.p
                        s.lean=vector3(0,0,0)
                    end
                elseif data.pan then
                    local b=M.cameraBasis(rotation)
                    local height=math.min(radius,1)*math.tan(math.rad(GetCamFov(s.cam))*.5)*2
                    local lean=s.lean-b.r*(math.max(-.1,math.min(.1,data.dx))*height*GetAspectRatio(false))
                        +b.u*(math.max(-.1,math.min(.1,data.dy))*height)
                    -- Bound lean around the seat or most recent orbit position.
                    s.lean=#lean>.12 and M.unit(lean)*.12 or lean
                elseif not s.orbit then
                    rotation=vector3(math.max(-80,math.min(80,rotation.x-data.dy*120)),rotation.y,
                        (rotation.z-data.dx*180+180)%360-180)
                end
                cameraPose(s,s.lookAnchor+s.lean,rotation,fov)
                return
            end
            if data.pan then
                local b=M.cameraBasis(GetCamRot(s.cam,2))
                local height=radius*math.tan(math.rad(GetCamFov(s.cam))*.5)*2
                local p=GetCamCoord(s.cam)-b.r*(math.max(-.1,math.min(.1,data.dx))*height*GetAspectRatio(false))
                    +b.u*(math.max(-.1,math.min(.1,data.dy))*height)
                cameraPose(s,p,GetCamRot(s.cam,2))
                return
            end
            local yaw=math.atan(offset.y,offset.x)-math.max(-.1,math.min(.1,data.dx))*4
            local pitch=math.asin(math.max(-1,math.min(1,offset.z/radius)))+math.max(-.1,math.min(.1,data.dy))*3
            pitch=math.max(-1.4,math.min(1.4,pitch))
            radius=math.max(.15,math.min(10,radius*math.exp(math.max(-1,math.min(1,data.zoom))*.12)))
            if data.action == 'focus' then radius=.8 end
            local p=center+vector3(math.cos(yaw)*math.cos(pitch),math.sin(yaw)*math.cos(pitch),math.sin(pitch))*radius
            aimCamera(s,p,center)
        end
    end)
    if not ok then finish(false,nil,true); print('[placement] Input failed: '..tostring(err)) end
    cb({ok=ok})
end)
exports('StartPlacementEditor',E.Start)
exports('CancelPlacementEditor',E.Cancel)
AddEventHandler('onResourceStop',function(resource)
    if active and (resource == GetCurrentResourceName() or resource == active.owner) then finish(false,nil,true) end
    if resource == GetCurrentResourceName() then
        for cam in pairs(returning) do DestroyCam(cam,false); returning[cam]=nil end
    end
end)
