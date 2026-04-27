local cadLinkUiOpen = false
local cadLinkForceOpen = false
local cadLinkAllowClose = true
local cadLinkUrl = nil
local cadLinkCode = nil
local cadLinkStatusText = "Waiting for account link..."
local cadLinkTitleText = "Press the button to link your CAD account to this FiveM server"
local cadLinkButtonText = "Link CAD"
local cadLinkLastPoll = 0
local cadLinkPollIntervalMs = 10000
local cadLinkCommandName = GetConvar("sonoran_linkCommand", "link")

if type(cadLinkCommandName) ~= "string" or cadLinkCommandName == "" then
    cadLinkCommandName = "link"
end

local function get_link_poll_interval_ms()
    local interval = tonumber((Config and Config.linkPollIntervalMs) or cadLinkPollIntervalMs) or 10000
    if interval < 1000 then
        interval = 1000
    end
    return math.floor(interval)
end

local function refresh_client_link_config(data)
    if type(data) == "table" then
        if type(data.pollIntervalMs) == "number" then
            cadLinkPollIntervalMs = math.max(1000, math.floor(data.pollIntervalMs))
        end
        if type(data.titleText) == "string" and data.titleText ~= "" then
            cadLinkTitleText = data.titleText
        end
        if type(data.buttonText) == "string" and data.buttonText ~= "" then
            cadLinkButtonText = data.buttonText
        end
        if type(data.allowClose) == "boolean" then
            cadLinkAllowClose = data.allowClose
        end
    end

    if Config ~= nil then
        if type(Config.linkPopupTitleText) == "string" and Config.linkPopupTitleText ~= "" then
            cadLinkTitleText = Config.linkPopupTitleText
        end
        if type(Config.linkButtonText) == "string" and Config.linkButtonText ~= "" then
            cadLinkButtonText = Config.linkButtonText
        end
        if type(Config.allowPopupCloseWhenUnlinked) == "boolean" and cadLinkForceOpen ~= true then
            cadLinkAllowClose = Config.allowPopupCloseWhenUnlinked
        end
        cadLinkPollIntervalMs = get_link_poll_interval_ms()
    end
end

local function send_link_status_update(linked, status_text)
    if type(status_text) == "string" and status_text ~= "" then
        cadLinkStatusText = status_text
    end
    SendNUIMessage({
        type = "updateLinkStatus",
        linked = linked == true,
        url = cadLinkUrl,
        code = cadLinkCode,
        statusText = cadLinkStatusText,
        titleText = cadLinkTitleText,
        buttonText = cadLinkButtonText,
        allowClose = cadLinkAllowClose,
        forceOpen = cadLinkForceOpen
    })
end

local function set_link_ui_state(open, force_open)
    cadLinkUiOpen = open == true
    if force_open ~= nil then
        cadLinkForceOpen = force_open == true
    end

    SetNuiFocus(cadLinkUiOpen, cadLinkUiOpen)
    SetNuiFocusKeepInput(false)

    if cadLinkUiOpen then
        SendNUIMessage({
            type = "openLinkMenu",
            forceOpen = cadLinkForceOpen,
            allowClose = cadLinkAllowClose,
            url = cadLinkUrl,
            code = cadLinkCode,
            statusText = cadLinkStatusText,
            titleText = cadLinkTitleText,
            buttonText = cadLinkButtonText
        })
        send_link_status_update(false, cadLinkStatusText)
    else
        SendNUIMessage({
            type = "closeLinkMenu"
        })
    end
end

local function open_link_ui(force_open)
    if force_open ~= nil then
        cadLinkForceOpen = force_open == true
    end
    refresh_client_link_config()
    debugLog(("[link] open UI requested (force=%s)"):format(tostring(cadLinkForceOpen)))
    TriggerServerEvent("SonoranCAD::links:Open")
end

local function close_link_ui(notify_server)
    if cadLinkForceOpen and cadLinkAllowClose == false then
        set_link_ui_state(true, true)
        return
    end

    set_link_ui_state(false, false)
    if notify_server ~= false then
        TriggerServerEvent("SonoranCAD::links:PopupClosed")
    end
end

RegisterCommand(cadLinkCommandName, function()
    open_link_ui(false)
end, false)

TriggerEvent("chat:addSuggestion", "/" .. cadLinkCommandName, "Open the Sonoran CAD account link window.")
RegisterPlayerCommandHelp("linking", cadLinkCommandName, "Open the Sonoran CAD account link window.")

RegisterNetEvent("SonoranCAD::links:OpenResult")
AddEventHandler("SonoranCAD::links:OpenResult", function(data)
    if type(data) ~= "table" or data.ok ~= true then
        local message = type(data) == "table" and data.message or "Failed to start the CAD link flow."
        TriggerEvent("chat:addMessage", {
            args = {"^0[ ^1SonoranCAD ^0] ", tostring(message)}
        })
        return
    end

    refresh_client_link_config(data)
    cadLinkUrl = data.url or cadLinkUrl
    cadLinkCode = data.code or cadLinkCode
    cadLinkLastPoll = GetGameTimer()
    cadLinkStatusText = data.statusText or "Waiting for account link..."
    set_link_ui_state(true, cadLinkForceOpen)
end)

RegisterNetEvent("SonoranCAD::links:Status")
AddEventHandler("SonoranCAD::links:Status", function(data)
    if type(data) ~= "table" then
        return
    end

    refresh_client_link_config(data)
    cadLinkUrl = data.url or cadLinkUrl
    cadLinkCode = data.code or cadLinkCode
    send_link_status_update(data.linked == true, data.statusText or (data.linked == true and "Linked successfully." or "Waiting for account link..."))

    if data.linked == true then
        debugLog("[link] player linked successfully")
        cadLinkForceOpen = false
        close_link_ui(true)
        TriggerEvent("chat:addMessage", {
            args = {"^0[ ^2SonoranCAD ^0] ", "Your CAD account is now linked."}
        })
    elseif cadLinkUiOpen then
        set_link_ui_state(true, cadLinkForceOpen)
    end
end)

RegisterNUICallback("cadLinkOpenExternal", function(_, cb)
    debugLog(("[link] open external browser url=%s"):format(tostring(cadLinkUrl)))
    SendNUIMessage({
        type = "openExternalLink",
        url = cadLinkUrl
    })
    if cb then
        cb({ok = cadLinkUrl ~= nil, url = cadLinkUrl})
    end
end)

RegisterNUICallback("cadLinkClose", function(_, cb)
    close_link_ui(true)
    if cb then
        cb({ok = true})
    end
end)

CreateThread(function()
    while true do
        if cadLinkUiOpen then
            local now = GetGameTimer()
            if now - cadLinkLastPoll >= cadLinkPollIntervalMs then
                cadLinkLastPoll = now
                send_link_status_update(false, "Checking link status...")
                TriggerServerEvent("SonoranCAD::links:Poll")
            end
            Wait(250)
        else
            Wait(1000)
        end
    end
end)

RegisterNetEvent("SonoranCAD::links:ForceOpen")
AddEventHandler("SonoranCAD::links:ForceOpen", function(force_open)
    if force_open ~= true then
        cadLinkForceOpen = false
        close_link_ui(true)
        return
    end

    cadLinkForceOpen = true
    cadLinkAllowClose = false
    open_link_ui(true)
end)
