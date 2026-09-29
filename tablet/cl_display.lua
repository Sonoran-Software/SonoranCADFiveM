-- The live CAD stays in its existing NUI iframe; only its presentation changes.
local displaySession
local closingUntil = 0
local returningCameras = {}

function IsCadDisplayActive()
    return displaySession ~= nil
end

function CloseCadDisplay(immediate)
    local session = displaySession
    if not session then return end
    displaySession = nil
    SendNUIMessage({ type = "display_surface", enabled = false })
    DisplayModule("cad", false)
    SetFocused(false)
    if session.frozePed and DoesEntityExist(session.ped) then
        FreezeEntityPosition(session.ped, false)
    end
    local duration = immediate and 0 or session.duration
    closingUntil = GetGameTimer() + duration
    RenderScriptCams(false, duration > 0, duration, true, true)
    -- Keep the camera alive until the return interpolation has finished.
    if duration == 0 then
        DestroyCam(session.cam, false)
    else
        returningCameras[session.cam] = true
        SetTimeout(duration, function()
            if returningCameras[session.cam] then
                returningCameras[session.cam] = nil
                DestroyCam(session.cam, false)
            end
        end)
    end
    TriggerEvent("SonoranCAD::Tablet::DisplayClosed", session.key)
end

local function worldCorners(session)
    -- FiveM returns forward, right, up, position (including entity scale).
    local forward, right, up, position = GetEntityMatrix(session.entity)
    local corners = {}
    for i, point in ipairs(session.corners) do
        corners[i] = position + right * point.x + forward * point.y + up * point.z
    end
    return corners
end

local function updateCamera(session, corners)
    local horizontal = corners[2] - corners[1]
    local vertical = corners[1] - corners[4]
    local normal = vector3(horizontal.y * vertical.z - horizontal.z * vertical.y,
        horizontal.z * vertical.x - horizontal.x * vertical.z,
        horizontal.x * vertical.y - horizontal.y * vertical.x)
    if #normal < 0.00001 then return false end
    local center = (corners[1] + corners[2] + corners[3] + corners[4]) / 4
    local aspect = GetAspectRatio(false)
    local distance = math.max(#vertical, #horizontal / aspect) / (2 * math.tan(math.rad(45 / 2))) * 1.3
    local position = center + normal / #normal * math.max(distance, 0.2)
    SetCamCoord(session.cam, position.x, position.y, position.z)
    PointCamAtCoord(session.cam, center.x, center.y, center.z)
    return true
end

exports("OpenDisplay", function(options)
    if displaySession then return false, "A CAD display is already open." end
    if GetGameTimer() < closingUntil then return false, "Wait for the camera to return, then press the interaction key again." end
    if nuiFocused or usingTablet then return false, "Close the handheld tablet before using the laptop." end
    if type(options) ~= "table" or not DoesEntityExist(options.entity or 0) then
        return false, "The CAD display no longer exists."
    end
    local profile = options.profile
    if type(profile) ~= "table" or type(profile.corners) ~= "table" or #profile.corners ~= 4 then
        return false, "This screen needs four configured interaction corners."
    end
    for _, point in ipairs(profile.corners) do
        if type(point) ~= "table" then return false, "Invalid screen corner configuration." end
        for _, axis in ipairs({ "x", "y", "z" }) do
            local value = point[axis]
            if type(value) ~= "number" or value ~= value or math.abs(value) > 100 then
                return false, "Invalid screen corner coordinates."
            end
        end
    end
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedRagdoll(ped) then return false, "You cannot use a display in this state." end
    local session = {
        key = options.key, entity = options.entity, corners = profile.corners,
        ped = ped, vehicle = GetVehiclePedIsIn(ped, false),
        range = tonumber(options.range) or 1.5,
        duration = math.floor(math.max(0, math.min(1500, tonumber(options.transitionMs) or 450))),
        cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    }
    SetCamFov(session.cam, 45.0)
    SetCamNearClip(session.cam, 0.01)
    local corners = worldCorners(session)
    if not updateCamera(session, corners) then
        DestroyCam(session.cam, false)
        return false, "The configured screen corners form an invalid surface."
    end
    displaySession = session
    session.frozePed = session.vehicle == 0 and not IsEntityPositionFrozen(ped)
    if session.frozePed then FreezeEntityPosition(ped, true) end
    DisplayModule("cad", false)
    local height = math.floor(1280 * #(corners[1] - corners[4]) / #(corners[2] - corners[1]))
    SendNUIMessage({ type = "display_surface", enabled = true,
        width = 1280, height = math.max(256, math.min(2048, height)) })
    SetFocused(true)
    SetNuiFocusKeepInput(false)
    RenderScriptCams(true, session.duration > 0, session.duration, true, true)
    session.readyAt = GetGameTimer() + session.duration
    CreateThread(function()
        while displaySession == session do
            Wait(0)
            if displaySession ~= session then break end
            if not DoesEntityExist(session.entity) or PlayerPedId() ~= session.ped
                or IsEntityDead(session.ped) or IsPedRagdoll(session.ped) or IsPauseMenuActive()
                or GetVehiclePedIsIn(session.ped, false) ~= session.vehicle
                or #(GetEntityCoords(session.ped) - GetEntityCoords(session.entity)) > session.range + 0.5 then
                CloseCadDisplay()
                break
            end
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 75, true)
            local corners = worldCorners(session)
            if not updateCamera(session, corners) then
                CloseCadDisplay()
                break
            end
            if GetGameTimer() >= session.readyAt then
                local projected = {}
                for i, point in ipairs(corners) do
                    local visible, x, y = GetScreenCoordFromWorldCoord(point.x, point.y, point.z)
                    if not visible or x < 0 or x > 1 or y < 0 or y > 1 then break end
                    projected[i] = { x = x, y = y }
                end
                if #projected ~= 4 then
                    CloseCadDisplay()
                    break
                end
                SendNUIMessage({ type = "display_surface_frame", corners = projected })
            end
        end
    end)
    return true
end)

exports("CloseDisplay", CloseCadDisplay)

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() or resource == "sonorancad" then
        CloseCadDisplay(true)
        for cam in pairs(returningCameras) do
            RenderScriptCams(false, false, 0, true, true)
            DestroyCam(cam, false)
            returningCameras[cam] = nil
        end
    end
end)
