--[[
    Sonaran CAD Plugins

    Plugin Name: forcereg
    Creator: Era#1337
    Description: Requires players to link their CAD account to a valid Sonoran account.

]]

local pluginConfig = Config.GetPluginConfig("forcereg")

if pluginConfig.enabled and pluginConfig.requireLink ~= false then

    local isNagging = false
    local isFreezePopup = false
    local isNoSpawn = false

    function resolve_forcereg_text(value, fallback)
        if type(value) ~= "string" or value == "" then
            return fallback
        end
        return value
    end

    function get_link_command()
        if type(pluginConfig.linkCommand) == "string" and pluginConfig.linkCommand ~= "" then
            return pluginConfig.linkCommand
        end
        if type(Config.linkCommand) == "string" and Config.linkCommand ~= "" then
            return Config.linkCommand
        end
        return "link"
    end

    function should_auto_open_popup()
        if type(pluginConfig.autoOpenLinkPopup) == "boolean" then
            return pluginConfig.autoOpenLinkPopup
        end
        return Config.autoOpenLinkPopup ~= false
    end

    function should_allow_popup_close_when_unlinked()
        local captiveOption = get_captive_option()
        if captiveOption == "freeze" then
            return false
        end
        if type(pluginConfig.allowPopupCloseWhenUnlinked) == "boolean" then
            return pluginConfig.allowPopupCloseWhenUnlinked
        end
        return true
    end

    function should_force_popup()
        return get_captive_option() == "freeze" or should_allow_popup_close_when_unlinked() == false
    end

    function get_captive_option()
        if type(pluginConfig.captiveOption) ~= "string" then
            return "nag"
        end
        return pluginConfig.captiveOption:lower()
    end

    function get_nag_draw_location()
        if type(pluginConfig.nagDrawTextLocation) ~= "string" then
            return "top"
        end
        return pluginConfig.nagDrawTextLocation:lower()
    end

    local linkCommand = get_link_command()
    local captiveMessage = resolve_forcereg_text(
        pluginConfig.captiveMessage,
        "You must link your CAD account before playing."
    )
    local instructionalMessage = resolve_forcereg_text(
        pluginConfig.instructionalMessage,
        ("Run /%s, press Link CAD, and finish the link in your browser."):format(linkCommand)
    )
    local verifyMessage = resolve_forcereg_text(
        pluginConfig.verifyMessage,
        ("Type /%s if you need to reopen the CAD link window."):format(linkCommand)
    )

    function draw_forcereg_message(location)
        if location == "top" then
            DrawText2D(captiveMessage, 0, true, 0.5, 0.035, 0.42, 255, 255, 255, 150)
            DrawText2D(instructionalMessage, 0, true, 0.5, 0.060, 0.36, 255, 255, 255, 150)
            DrawText2D(verifyMessage, 0, true, 0.5, 0.085, 0.36, 255, 255, 255, 150)
            return
        end

        DrawText2D(captiveMessage, 0, true, 0.5, 0.420, 0.52, 255, 255, 255, 150)
        DrawText2D(instructionalMessage, 0, true, 0.5, 0.455, 0.40, 255, 255, 255, 150)
        DrawText2D(verifyMessage, 0, true, 0.5, 0.490, 0.40, 255, 255, 255, 150)
    end

    RegisterNetEvent("SonoranCAD::forcereg:PlayerReg")
    AddEventHandler("SonoranCAD::forcereg:PlayerReg", function(identifier, exists)
        if not exists then
            Wait(1)
            debugLog(("Forcereg blocked player identifier %s because no CAD link exists."):format(tostring(identifier)))

            local captiveOption = get_captive_option()
            isNagging = captiveOption == "nag"
            isFreezePopup = captiveOption == "freeze"
            isNoSpawn = captiveOption == "nospawn"

            if isFreezePopup then
                TriggerEvent("SonoranCAD::links:ForceOpen", true)
            elseif should_auto_open_popup() then
                TriggerEvent("SonoranCAD::links:ForceOpen", should_force_popup())
            end
            return
        end

        debugLog(("Forcereg cleared restrictions for %s"):format(tostring(identifier)))
        isNagging = false
        isFreezePopup = false
        isNoSpawn = false
        TriggerEvent("SonoranCAD::links:ForceOpen", false)
    end)

    RegisterNetEvent("SonoranCAD::links:Status")
    AddEventHandler("SonoranCAD::links:Status", function(data)
        if type(data) ~= "table" or data.linked ~= true then
            return
        end

        if isNagging or isFreezePopup or isNoSpawn then
            debugLog("Forcereg cleared restrictions after client link status updated to linked.")
        end
        isNagging = false
        isFreezePopup = false
        isNoSpawn = false
    end)

    TriggerServerEvent("SonoranCAD::forcereg:CheckPlayer")

    CreateThread(function()
        while true do
            if isNagging then
                if get_nag_draw_location() == "top" then
                    draw_forcereg_message("top")
                elseif get_nag_draw_location() == "center" then
                    draw_forcereg_message("center")
                end
                Wait(0)
            elseif isFreezePopup then
                Wait(100)
            elseif isNoSpawn then
                Wait(250)
            else
                Wait(100)
            end
        end
    end)

end

local AspectRatio
local ScreenWidth
local ScreenHeight

Citizen.CreateThread(function()
    AspectRatio = GetAspectRatio(false)
    ScreenWidth = 1080 * AspectRatio
    ScreenHeight = 1080
end)

function DrawText2D(text, font, centre, px, py, scale, r, g, b, a, labelGen)
    if labelGen then
        AddTextEntry(labelGen, text)
    end
    SetTextFont(font)
    SetTextProportional(0)
    SetTextScale(scale, scale)
    SetTextColour(r or 255, g or 255, b or 255, a or 255)
    SetTextDropShadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 255)
    SetTextCentre(centre)
    SetTextEntry(labelGen or "STRING")
    AddTextComponentString(text)
    local x = px + (scale / 2.0) / ScreenWidth
    local y = py + (scale / 2.0) / ScreenHeight
    DrawText(x, y)
end
