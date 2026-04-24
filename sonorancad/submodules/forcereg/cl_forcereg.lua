--[[
    Sonaran CAD Plugins

    Plugin Name: forcereg
    Creator: Era#1337
    Description: Requires players to link their CAD account to a valid Sonoran account.

]]

local pluginConfig = Config.GetPluginConfig("forcereg")

if pluginConfig.enabled and Config.requireLink ~= false then

    local isNagging = false
    local isFreezePopup = false
    local isNoSpawn = false

    local function resolve_forcereg_text(value, fallback)
        if type(value) ~= "string" or value == "" then
            return fallback
        end
        return value
    end

    local function get_link_command()
        if type(Config.linkCommand) == "string" and Config.linkCommand ~= "" then
            return Config.linkCommand
        end
        return "link"
    end

    local function should_auto_open_popup()
        return Config.autoOpenLinkPopup ~= false
    end

    local function should_force_popup()
        if get_captive_option() == "freeze" then
            return true
        end
        if Config.freezeUntilLinked == true then
            return true
        end
        return Config.allowPopupCloseWhenUnlinked == false
    end

    local function get_captive_option()
        if Config.freezeUntilLinked == true then
            return "freeze"
        end
        if type(pluginConfig.captiveOption) ~= "string" then
            return "nag"
        end
        return pluginConfig.captiveOption:lower()
    end

    local function get_nag_draw_location()
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

    RegisterNetEvent("SonoranCAD::forcereg:PlayerReg")
    AddEventHandler("SonoranCAD::forcereg:PlayerReg", function(identifier, exists)
        if not exists then
            Wait(1)
            debugLog(("Forcereg blocked player identifier %s because no CAD link exists."):format(tostring(identifier)))

            local captiveOption = get_captive_option()
            isNagging = captiveOption == "nag"
            isFreezePopup = captiveOption == "freeze"
            isNoSpawn = captiveOption == "nospawn"

            if should_auto_open_popup() then
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

    TriggerServerEvent("SonoranCAD::forcereg:CheckPlayer")

    CreateThread(function()
        while true do
            if isNagging then
                if get_nag_draw_location() == "top" then
                    DrawText2D(captiveMessage, 0, 0, 0.305, 0.01, 0.3, 255, 255, 255, 150)
                    DrawText2D(instructionalMessage, 0, 0, 0.3, 0.03, 0.3, 255, 255, 255, 150)
                    DrawText2D(verifyMessage, 0, 0, 0.35, 0.06, 0.3, 255, 255, 255, 150)
                elseif get_nag_draw_location() == "center" then
                    DrawText2D(captiveMessage, 0, 0, 0.2, 0.4, 0.5, 255, 255, 255, 150)
                    DrawText2D(instructionalMessage, 0, 0, 0.195, 0.45, 0.5, 255, 255, 255, 150)
                    DrawText2D(verifyMessage, 0, 0, 0.265, 0.5, 0.5, 255, 255, 255, 150)
                end
                Wait(0)
            elseif isFreezePopup then
                DrawText2D(captiveMessage, 0, 0, 0.2, 0.4, 0.5, 255, 255, 255, 150)
                DrawText2D(instructionalMessage, 0, 0, 0.195, 0.45, 0.5, 255, 255, 255, 150)
                DrawText2D(verifyMessage, 0, 0, 0.265, 0.5, 0.5, 255, 255, 255, 150)
                Wait(0)
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
