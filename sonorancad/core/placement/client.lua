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
local function cameraRelease(cam, immediate)
    RenderScriptCams(false, not immediate, immediate and 0 or 250, true, true)
    if immediate then DestroyCam(cam,false) else
        returning[cam] = true
        SetTimeout(250,function()
            if returning[cam] then returning[cam] = nil; DestroyCam(cam,false) end
        end)
    end
end
local function finish(accepted, action, immediate)
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
            entity=s.entity, matrix=matrix, position=pack(matrix.p), rotation=pack(M.rotation(matrix,2)) })
        if not ok then print('[placement] Completion callback failed: '..tostring(err)) end
    end
end
function E.IsActive() return active ~= nil end
function E.Cancel() finish(false,nil,true) end
local function projected(point)
    local visible,x,y = GetScreenCoordFromWorldCoord(point.x,point.y,point.z)
    return visible and finite(x) and finite(y) and {x=x,y=y} or false
end
local function frame(s)
    local matrix = M.capture(s.entity)
    local b = basis(s,matrix)
    local size = math.max(.08,math.min(1.5,#(GetCamCoord(s.cam)-matrix.p)*.22))
    local handles = {}
    if s.mode == 'move' then
        for _, key in ipairs({'x','y','z'}) do
            handles[#handles+1] = { id=key, kind='axis', points={projected(matrix.p),projected(matrix.p+b[key]*size)} }
        end
        for _, pair in ipairs({'xy','xz','yz'}) do
            local a,c = b[pair:sub(1,1)],b[pair:sub(2,2)]
            local points = {}
            for _, v in ipairs({{.18,.18},{.4,.18},{.4,.4},{.18,.4}}) do
                points[#points+1] = projected(matrix.p + (a*v[1]+c*v[2])*size)
            end
            handles[#handles+1] = {id=pair,kind='plane',points=points}
        end
    else
        for _, key in ipairs({'x','y','z'}) do
            local a = b[key == 'x' and 'y' or 'x']
            local c = M.cross(b[key],a)
            local points = {}
            for i=0,48 do
                local angle = i*math.pi/24
                points[#points+1] = projected(matrix.p+(a*math.cos(angle)+c*math.sin(angle))*size)
            end
            handles[#handles+1] = {id=key,kind='ring',points=points}
        end
    end
    SendNUIMessage({type='placement_frame',session=s.id,handles=handles, mode=s.mode,space=s.space,
        snap=s.snap,position=pack(matrix.p),rotation=pack(M.rotation(matrix,2))})
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
    serial = serial+1
    local matrix = M.capture(options.entity)
    local s = { id=serial,entity=options.entity,original=matrix,options=options,owner=GetInvokingResource(),
        ped=ped,vehicle=GetVehiclePedIsIn(ped,false),mode='move',space='local',snap=false,
        actions=options.actions or {{id='apply',label='Apply'}},
        entityFrozen=IsEntityPositionFrozen(options.entity),cam=CreateCam('DEFAULT_SCRIPTED_CAMERA',true) }
    local p,r = GetFinalRenderedCamCoord(),GetFinalRenderedCamRot(2)
    SetCamCoord(s.cam,p.x,p.y,p.z); SetCamRot(s.cam,r.x,r.y,r.z,2)
    SetCamFov(s.cam,GetFinalRenderedCamFov()); SetCamNearClip(s.cam,.01)
    s.frozePed = s.vehicle == 0 and not IsEntityPositionFrozen(ped)
    if s.frozePed then FreezeEntityPosition(ped,true) end
    FreezeEntityPosition(s.entity,true)
    active = s
    RenderScriptCams(true,false,0,true,true)
    SendNUIMessage({type='placement_editor',enabled=true,session=s.id,title=options.title or 'Object placement',actions=s.actions})
    SetNuiFocus(true,true)
    SetNuiFocusKeepInput(false)
    CreateThread(function()
        local ok,err = xpcall(function()
            while active == s do
                Wait(0)
                if active ~= s then break end
                if not validSession(s) then finish(false,nil,true); break end
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
        if data.action == 'cancel' then finish(false)
        elseif data.action == 'finish' then
            for _, action in ipairs(s.actions) do
                if data.choice == action.id and validSession(s) then finish(true,action.id); break end
            end
        elseif data.action == 'mode' and (data.value == 'move' or data.value == 'rotate') then s.mode=data.value; s.drag=nil
        elseif data.action == 'space' then s.space=s.space == 'local' and 'world' or 'local'; s.drag=nil
        elseif data.action == 'snap' then s.snap=not s.snap
        elseif data.action == 'reset' then M.apply(s.entity,s.original); s.drag=nil
        elseif data.action == 'up' then s.drag=nil
        elseif data.action == 'down' and pointer(data) and type(data.handle) == 'string' then
            local m = M.capture(s.entity)
            local b = basis(s,m)
            local a = b[data.handle:sub(1,1)]
            if not a then return end
            local origin,direction = GetWorldCoordFromScreenCoord(data.x,data.y)
            local normal,kind
            if s.mode == 'rotate' and #data.handle == 1 then normal=a; kind='rotate'
            elseif s.mode == 'move' and #data.handle == 1 then normal=M.unit(direction-a*M.dot(direction,a)); kind='axis'
            elseif s.mode == 'move' and ({xy=true,xz=true,yz=true})[data.handle] then
                normal=M.cross(a,b[data.handle:sub(2,2)]); kind='plane'
            else return end
            local hit=M.plane(origin,direction,m.p,normal)
            if hit and #normal > .001 then s.drag={matrix=m,axis=a,normal=normal,hit=hit,kind=kind} end
        elseif data.action == 'drag' and s.drag and pointer(data) then
            local d=s.drag
            local origin,direction=GetWorldCoordFromScreenCoord(data.x,data.y)
            local hit=M.plane(origin,direction,d.matrix.p,d.normal)
            if not hit then return end
            local m=d.matrix
            if d.kind == 'rotate' then
                local angle=M.angle(M.unit(d.hit-m.p),M.unit(hit-m.p),d.axis)
                angle=M.snap(angle,s.snap and math.rad(5) or 0)
                m=M.rotate(m,d.axis,angle)
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
        elseif data.action == 'focus' or (data.action == 'camera' and finite(data.dx) and finite(data.dy) and finite(data.zoom)) then
            if data.action == 'focus' then data.dx,data.dy,data.zoom=0,0,0 end
            s.drag=nil
            local center=GetEntityCoords(s.entity)
            local offset=GetCamCoord(s.cam)-center
            local radius=math.max(.15,#offset)
            local yaw=math.atan(offset.y,offset.x)-math.max(-.1,math.min(.1,data.dx))*4
            local pitch=math.asin(math.max(-1,math.min(1,offset.z/radius)))+math.max(-.1,math.min(.1,data.dy))*3
            pitch=math.max(-1.4,math.min(1.4,pitch))
            radius=math.max(.15,math.min(10,radius*math.exp(math.max(-1,math.min(1,data.zoom))*.12)))
            if data.action == 'focus' then radius=.8 end
            local p=center+vector3(math.cos(yaw)*math.cos(pitch),math.sin(yaw)*math.cos(pitch),math.sin(pitch))*radius
            SetCamCoord(s.cam,p.x,p.y,p.z); PointCamAtCoord(s.cam,center.x,center.y,center.z)
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
