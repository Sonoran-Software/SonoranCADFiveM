--[[
    Sonaran CAD Plugins

    Plugin Name: civintegration
    Creator: civintegration
    Description: Describe your plugin here

    Put all client-side logic in this file.
]]

local pluginConfig = Config.GetPluginConfig("civintegration")

if pluginConfig.enabled then
    if type(pluginConfig.commandName) ~= "string" or pluginConfig.commandName == "" then
        pluginConfig.commandName = "civid"
    end

    AddTextEntry("ENTER_NAME", "Enter first and last name")
    AddTextEntry("ENTER_DOB", "Enter character date of birth in format month/day/year")
    TriggerEvent("chat:addSuggestion", "/" .. pluginConfig.commandName, "Show or manage your civilian ID.", {
        { name = "action", help = "Subcommand: show, set, reset, refresh, or help" }
    })
    RegisterPlayerCommandHelp("civintegration", pluginConfig.commandName,
        "Show or manage your civilian ID.", "<show|set|reset|refresh|help>")

    local customId = {
        ['first'] = nil,
        ['last'] = nil,
        ['dob'] = nil,
        ['img'] = nil
    }

    RegisterNetEvent("SonoranCAD::civintegration:SetCustomId")
    AddEventHandler("SonoranCAD::civintegration:SetCustomId", function()
        TriggerEvent("chat:addMessage", {args = {"^0[ ^3ID ^0] ", "Prompt 1/2: enter first and last name."}})
        DisplayOnscreenKeyboard(1, "ENTER_NAME", "", customId.first ~= nil and ("%s %s"):format(customId.first, customId.last), "", "", "", 50)
        while (UpdateOnscreenKeyboard() == 0) do
            DisableAllControlActions(0);
            Wait(0);
        end
        if (GetOnscreenKeyboardResult()) then
            local result = GetOnscreenKeyboardResult()
            customId.first = stringsplit(result, " ")[1]
            customId.last = stringsplit(result, " ")[2]
            TriggerEvent("chat:addMessage", {args = {"^0[ ^3ID ^0] ", "Prompt 2/2: enter DOB as month/day/year."}})
            DisplayOnscreenKeyboard(1, "ENTER_DOB", "", customId.dob ~= nil and customId.dob or "", "", "", "", 50)
            while (UpdateOnscreenKeyboard() == 0) do
                DisableAllControlActions(0);
                Wait(0);
            end
            if (GetOnscreenKeyboardResult()) then
                local result = GetOnscreenKeyboardResult()
                customId.dob = result
            end
        end
        TriggerServerEvent("SonoranCAD::civintegration:SetCustomId", customId)
        TriggerEvent("chat:addMessage", {args = {"^0[ ^3ID ^0] ", "Custom name and DOB set. Use /id show to display it nearby or /id reset to remove it."}})
    end)

end
