-- source: https://github.com/loaf-scripts/loaf_headshot_base64/blob/main/client.lua

local requests = {}
local handles = {}
local requestSequence = 0

local function headshotDebug(message)
    if type(debugLog) == "function" then debugLog("[civreg headshot] " .. message) end
end

local function releaseHeadshot(handle)
    if handles[handle] then
        handles[handle] = nil
        UnregisterPedheadshot(handle)
    end
end

local function GenerateId()
    requestSequence = requestSequence + 1
    local id = ""
    for i = 1, 15 do
        id = id .. (math.random(1, 2) == 1 and string.char(math.random(97, 122)) or tostring(math.random(0,9)))
    end
    return id .. "-" .. requestSequence
end

function GetHeadshot(ped)
    if not ped then ped = PlayerPedId() end
    if DoesEntityExist(ped) then
        local handle, timer = RegisterPedheadshot(ped), GetGameTimer() + 5000
        if not handle or handle == -1 then
            return {success=false, error="Could not register ped headshot."}
        end
        handles[handle] = true
        headshotDebug(("registered fresh headshot ped=%s handle=%s"):format(ped, handle))
        while not IsPedheadshotReady(handle) or not IsPedheadshotValid(handle) do
            Wait(50)
            if GetGameTimer() >= timer then
                releaseHeadshot(handle)
                headshotDebug(("headshot readiness timed out ped=%s handle=%s"):format(ped, handle))
                return {success=false, error="Could not load ped headshot."}
            end
        end

        local txd = GetPedheadshotTxdString(handle)
        local url = string.format("https://nui-img/%s/%s", txd, txd)
        return {success=true, url=url, txd=txd, handle=handle}
    end
end

function GetBase64(ped, onHeadshotReady)
    if not ped then ped = PlayerPedId() end
    local headshot = GetHeadshot(ped)
    if type(headshot) == "table" and headshot.success then
        -- The texture is ready; let callers restore the live ped before NUI conversion can wait.
        if type(onHeadshotReady) == "function" then
            local callbackOk, callbackResult = pcall(onHeadshotReady)
            if not callbackOk or callbackResult == false then
                releaseHeadshot(headshot.handle)
                return {success=false, error="Could not restore character appearance."}
            end
        end

        local requestId = GenerateId()
        local request = { handle = headshot.handle }
        requests[requestId] = request
        headshotDebug(("conversion started id=%s ped=%s handle=%s txd=%s"):format(
            requestId, ped, headshot.handle, headshot.txd))
        SendNUIMessage({
            type = "convert_base64",
            -- FiveM recycles texture names; a unique URL prevents a previous portrait being cached by NUI.
            img = headshot.url .. "?capture=" .. requestId,
            handle = headshot.handle,
            id = requestId
        })

        local timer = GetGameTimer() + 5000
        while not request.base64 do
            Wait(250)
            if GetGameTimer() >= timer then
                releaseHeadshot(headshot.handle)
                requests[requestId] = nil
                headshotDebug("conversion timed out id=" .. requestId)
                return {success=false, error="Waiting for base64 conversion timed out."}
            end
        end
        releaseHeadshot(headshot.handle)
        requests[requestId] = nil
        headshotDebug(("conversion complete id=%s imageBytes=%s"):format(requestId, #request.base64))
        return {success=true, base64=request.base64}
    else
        return type(headshot) == "table" and headshot or
            {success=false, error="Could not load ped headshot."}
    end
end

RegisterNUICallback("base64", function(data, cb)
    local request = type(data) == "table" and requests[data.id]
    if request and request.handle == data.handle and not request.base64 and
        type(data.base64) == "string" and data.base64 ~= "" then
        request.base64 = data.base64
    else
        -- A late conversion must never unregister a recycled handle belonging to a newer capture.
        headshotDebug("ignored stale or invalid conversion callback")
    end

    cb({ok=true})
end)

AddEventHandler("onClientResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        for handle in pairs(handles) do releaseHeadshot(handle) end
        requests = {}
    end
end)

exports("getBase64", GetBase64)
