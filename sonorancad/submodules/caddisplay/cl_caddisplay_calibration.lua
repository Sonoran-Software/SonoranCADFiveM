-- Local screen calibration. Saving prints config; no server placements are changed.
CadDisplayCalibration = {}
local editor
local labels = { "1 Top-left", "2 Top-right", "3 Bottom-right", "4 Bottom-left" }
local controls = { 10, 11, 21, 23, 24, 25, 30, 31, 36, 37, 44, 45, 75, 172, 173, 174, 175, 177, 200, 201 }
local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function cross(a, b)
    return vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end
local function copy(points)
    local result = {}
    for i, p in ipairs(points) do result[i] = { x = p.x, y = p.y, z = p.z } end
    return result
end

function CadDisplayCalibration.ToLocal(entity, point)
    local forward, right, up, origin = GetEntityMatrix(entity)
    local delta = point - origin
    if #right < 0.00001 or #forward < 0.00001 or #up < 0.00001 then return nil end
    -- Invert each orthogonal, scaled entity axis rather than losing prop scale.
    return { x = dot(delta, right) / dot(right, right),
        y = dot(delta, forward) / dot(forward, forward), z = dot(delta, up) / dot(up, up) }
end

function CadDisplayCalibration.ToWorld(entity, points)
    local forward, right, up, origin = GetEntityMatrix(entity)
    local result = {}
    for i, p in ipairs(points) do result[i] = origin + right * p.x + forward * p.y + up * p.z end
    return result
end

function CadDisplayCalibration.Validate(points)
    if type(points) ~= "table" or #points ~= 4 then return false, "Four corners are required." end
    local p = {}
    for i, point in ipairs(points) do
        if type(point) ~= "table" then return false, "Invalid corner." end
        for _, axis in ipairs({ "x", "y", "z" }) do
            local value = point[axis]
            if type(value) ~= "number" or value ~= value or math.abs(value) > 100 then
                return false, "Corner coordinates must be finite and within 100 model metres."
            end
        end
        p[i] = vector3(point.x, point.y, point.z)
    end
    local normal = cross(p[2] - p[1], p[3] - p[2])
    if #normal < 0.00001 then return false, "Corners must form a screen with nonzero area." end
    normal = normal / #normal
    if math.abs(dot(p[4] - p[1], normal)) > 0.002 then
        return false, "Corners are not flat. Press F to flatten corner 4 onto the plane of corners 1-3."
    end
    for i = 1, 4 do
        local a, b, c = p[i], p[i % 4 + 1], p[(i + 1) % 4 + 1]
        if #(b - a) < 0.005 or dot(cross(b - a, c - b), normal) <= 0.00001 then
            return false, "Use top-left, top-right, bottom-right, bottom-left order; edges cannot cross."
        end
    end
    return true
end

function CadDisplayCalibration.Format(points, model, builtin)
    local key = type(model) == "number" and tostring(model) or ("%q"):format(model)
    local lines = { builtin and ("-- In builtinScreens entry for vehicle %s:"):format(tostring(model))
        or "-- In interaction.models (numeric model hashes are supported):",
        builtin and "interaction = {" or ("[%s] = {"):format(key), "    corners = {" }
    for _, p in ipairs(points) do
        lines[#lines + 1] = ("        { x = %.5f, y = %.5f, z = %.5f },"):format(p.x, p.y, p.z)
    end
    lines[#lines + 1] = "    }"
    lines[#lines + 1] = "},"
    return table.concat(lines, "\n")
end

function CadDisplayCalibration.IsActive() return editor ~= nil end

function CadDisplayCalibration.Stop()
    local session = editor
    editor = nil
    if session and session.frozePed and DoesEntityExist(session.ped) then
        FreezeEntityPosition(session.ped, false)
    end
end

local function textAt(x, y, text)
    SetTextFont(0)
    SetTextScale(0.0, 0.32)
    SetTextColour(255, 255, 255, 255)
    SetTextOutline()
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function cameraRay()
    local origin, rotation = GetFinalRenderedCamCoord(), GetFinalRenderedCamRot(2)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local forward = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    return origin, forward, vector3(math.cos(yaw), math.sin(yaw), 0)
end

function CadDisplayCalibration.Start(options)
    if editor then return false, "Finish or cancel the current calibration first." end
    if not DoesEntityExist(options.entity) then return false, "Display no longer exists." end
    if IsNuiFocused() then return false, "Close the tablet or other menus before calibrating." end
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedRagdoll(ped) then return false, "You cannot calibrate in this state." end
    local points = options.profile and options.profile.corners
    if not CadDisplayCalibration.Validate(points) then
        -- A visible starting rectangle for screens without a profile/collision.
        -- It is only a seed; the administrator adjusts it to the actual bezel.
        local origin, forward, right = cameraRay()
        local up, center = cross(right, forward), origin + forward * 0.65
        points = {}
        for i, pair in ipairs({ { -1, 1 }, { 1, 1 }, { 1, -1 }, { -1, -1 } }) do
            points[i] = CadDisplayCalibration.ToLocal(options.entity, center + right * (pair[1] * 0.16) + up * (pair[2] * 0.1))
        end
        if #points ~= 4 then return false, "This entity has invalid scale." end
    end
    local session = { entity = options.entity, ped = ped, vehicle = GetVehiclePedIsIn(ped, false),
        points = copy(points), original = copy(points), selected = 1, notify = options.notify,
        range = options.range or 3.0, options = options }
    session.frozePed = session.vehicle == 0 and not IsEntityPositionFrozen(ped)
    if session.frozePed then FreezeEntityPosition(ped, true) end
    editor = session
    CreateThread(function()
        while editor == session do
            Wait(0)
            if editor ~= session then break end
            if not DoesEntityExist(session.entity) or PlayerPedId() ~= ped or IsEntityDead(ped)
                or IsPedRagdoll(ped) or IsPauseMenuActive() or IsNuiFocused()
                or GetVehiclePedIsIn(ped, false) ~= session.vehicle
                or #(GetEntityCoords(ped) - GetEntityCoords(session.entity)) > session.range
                or (session.vehicle ~= 0 and GetEntitySpeed(session.vehicle) > 0.2) then
                CadDisplayCalibration.Stop()
                session.notify("Calibration cancelled. Stay near the screen in a stationary vehicle or on foot.")
                break
            end
            for _, control in ipairs(controls) do DisableControlAction(0, control, true) end
            DisablePlayerFiring(PlayerId(), true)
            if IsDisabledControlJustPressed(0, 177) then CadDisplayCalibration.Stop(); break end
            if IsDisabledControlJustPressed(0, 37) then session.selected = session.selected % 4 + 1 end
            if IsDisabledControlJustPressed(0, 45) then
                session.points, session.ray = copy(session.original), nil
            end
            local step = math.min(GetFrameTime(), 0.05) * (IsDisabledControlPressed(0, 21) and 0.01 or 0.1)
            local delta = { x = 0, y = 0, z = 0 }
            for _, binding in ipairs({ { 174, "x", -1 }, { 175, "x", 1 }, { 172, "z", 1 },
                { 173, "z", -1 }, { 10, "y", 1 }, { 11, "y", -1 } }) do
                if IsDisabledControlPressed(0, binding[1]) then delta[binding[2]] = delta[binding[2]] + step * binding[3] end
            end
            for i, p in ipairs(session.points) do
                if i == session.selected or IsDisabledControlPressed(0, 36) then
                    p.x, p.y, p.z = p.x + delta.x, p.y + delta.y, p.z + delta.z
                end
            end
            if IsDisabledControlJustPressed(0, 23) then
                local p = session.points
                local a, b, c, d = vector3(p[1].x, p[1].y, p[1].z), vector3(p[2].x, p[2].y, p[2].z),
                    vector3(p[3].x, p[3].y, p[3].z), vector3(p[4].x, p[4].y, p[4].z)
                local n = cross(b - a, c - a)
                if #n > 0.00001 then
                    n = n / #n
                    d = d - n * dot(d - a, n)
                    p[4] = { x = d.x, y = d.y, z = d.z }
                end
            end
            if IsDisabledControlJustPressed(0, 24) and not session.ray then
                local origin, forward = cameraRay()
                local target = origin + forward * 10
                session.ray = StartShapeTestLosProbe(origin.x, origin.y, origin.z, target.x, target.y, target.z, 19, ped, 7)
                session.rayCorner = session.selected
            end
            if session.ray then
                local status, hit, point, _, entity = GetShapeTestResult(session.ray)
                if status ~= 1 then
                    session.ray = nil
                    if status == 2 and (hit == true or hit == 1) and entity == session.entity then
                        local picked = CadDisplayCalibration.ToLocal(session.entity, point)
                        if picked then session.points[session.rayCorner] = picked end
                    else
                        session.notify("Aim at this display's collision, or use the arrow/Page keys to position its corners manually.")
                    end
                end
            end
            local world = CadDisplayCalibration.ToWorld(session.entity, session.points)
            for i, p in ipairs(world) do
                local q = world[i % 4 + 1]
                DrawLine(p.x, p.y, p.z, q.x, q.y, q.z, 0, 220, 255, 255)
                local visible, x, y = GetScreenCoordFromWorldCoord(p.x, p.y, p.z)
                if visible then textAt(x, y, (i == session.selected and "~y~" or "~w~") .. labels[i]) end
            end
            DrawRect(0.5, 0.5, 0.003, 0.005, 255, 255, 255, 220)
            textAt(0.02, 0.12, "CAD screen corners: " .. labels[session.selected])
            textAt(0.02, 0.15, "Mouse: aim | Click: place on collision | Tab: next corner")
            textAt(0.02, 0.18, "Arrows: model X/Z | Page Up/Down: model Y | Shift: fine | Ctrl: move all")
            textAt(0.02, 0.21, "F: flatten corner 4 | R: reset | Enter: apply locally + print config | Backspace: cancel")
            local p = session.points[session.selected]
            textAt(0.02, 0.24, ("Model coordinates: x %.5f   y %.5f   z %.5f"):format(p.x, p.y, p.z))
            if IsDisabledControlJustPressed(0, 201) and not session.ray then
                local valid, reason = CadDisplayCalibration.Validate(session.points)
                local facing = cross(world[2] - world[1], world[1] - world[4])
                if valid and dot(facing, GetFinalRenderedCamCoord() - world[1]) <= 0 then
                    valid, reason = false, "Corners face away from you. Select TL, TR, BR, BL as viewed from the front."
                end
                if valid then
                    local profile = { corners = copy(session.points) }
                    CadDisplayCalibration.Stop()
                    options.apply(profile)
                    print("[caddisplay] Screen calibration - copy the following into caddisplay_config.lua:\n"
                        .. CadDisplayCalibration.Format(profile.corners, options.model, options.builtin))
                    session.notify("Applied for your client until restart. Press G to test. Copy the F8 config to keep it for everyone.")
                    break
                else
                    session.notify(reason)
                end
            end
        end
    end)
    return true
end

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() or resource == "tablet" then CadDisplayCalibration.Stop() end
end)
