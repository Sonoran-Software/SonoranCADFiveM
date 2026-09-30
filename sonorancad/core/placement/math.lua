-- Transform math shared by the placement editor and its resource adapters.
SonoranPlacementMath = {}
local M = SonoranPlacementMath
function M.dot(a, b) return a.x*b.x + a.y*b.y + a.z*b.z end
function M.cross(a, b) return vector3(a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x) end
function M.unit(v) return #v > 1e-8 and v / #v or vector3(0, 0, 0) end
function M.capture(entity)
    local f, r, u, p = GetEntityMatrix(entity)
    return { r = r, f = f, u = u, p = p }
end
function M.apply(entity, m)
    -- Update the engine position as well as the render matrix, including frozen props.
    SetEntityCoordsNoOffset(entity, m.p.x,m.p.y,m.p.z, false,false,false)
    SetEntityMatrix(entity, m.f.x,m.f.y,m.f.z, m.r.x,m.r.y,m.r.z, m.u.x,m.u.y,m.u.z, m.p.x,m.p.y,m.p.z)
end
function M.cameraBasis(rotation)
    local m = {r=vector3(1,0,0),f=vector3(0,1,0),u=vector3(0,0,1),p=vector3(0,0,0)}
    m=M.rotate(m,vector3(0,1,0),math.rad(rotation.y))
    m=M.rotate(m,vector3(1,0,0),math.rad(rotation.x))
    return M.rotate(m,vector3(0,0,1),math.rad(rotation.z))
end
function M.cameraRay(position, rotation, fov, aspect, x, y)
    local b=M.cameraBasis(rotation)
    local height=math.tan(math.rad(fov)*.5)
    return position, M.unit(b.f+b.r*((x*2-1)*height*aspect)+b.u*((1-y*2)*height))
end
function M.relative(frame, m)
    local function localVector(v)
        return vector3(M.dot(v,frame.r)/M.dot(frame.r,frame.r),
            M.dot(v,frame.f)/M.dot(frame.f,frame.f), M.dot(v,frame.u)/M.dot(frame.u,frame.u))
    end
    return { p = localVector(m.p-frame.p), r = localVector(m.r), f = localVector(m.f), u = localVector(m.u) }
end
function M.rotation(m, order)
    local r, f, u = M.unit(m.r), M.unit(m.f), M.unit(m.u)
    local clamp = function(v) return math.max(-1, math.min(1, v)) end
    if order == 0 then -- ZYX, used by existing vehicle attachments.
        local y = math.asin(clamp(-r.z))
        if math.abs(math.cos(y)) < 1e-6 then return vector3(0, math.deg(y), math.deg(math.atan(-f.x, f.y))) end
        return vector3(math.deg(math.atan(f.z,u.z)), math.deg(y), math.deg(math.atan(r.y,r.x)))
    end
    local x = math.asin(clamp(f.z)) -- ZXY, used by world entities.
    if math.abs(math.cos(x)) < 1e-6 then return vector3(math.deg(x),0,math.deg(math.atan(r.y,r.x))) end
    return vector3(math.deg(x),math.deg(math.atan(-r.z,u.z)),math.deg(math.atan(-f.x,f.y)))
end
function M.plane(origin, direction, point, normal)
    local d = M.dot(direction,normal)
    if math.abs(d) < 0.0001 then return nil end
    local t = M.dot(point-origin,normal)/d
    if t < 0 then return nil end
    return origin + direction*t
end
function M.rotate(m, axis, angle)
    local c, s = math.cos(angle), math.sin(angle)
    local function rotate(v) return v*c + M.cross(axis,v)*s + axis*(M.dot(axis,v)*(1-c)) end
    return { p = m.p, r = rotate(m.r), f = rotate(m.f), u = rotate(m.u) }
end
function M.angle(a, b, normal)
    return math.atan(M.dot(normal,M.cross(a,b)), M.dot(a,b))
end
function M.snap(value, increment)
    return increment > 0 and math.floor(value/increment+0.5)*increment or value
end
