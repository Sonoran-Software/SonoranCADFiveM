--[[
    Sonaran CAD Plugins

    Plugin Name: calltemplates
    Creator: SonoranCAD
    Description: Adds chat suggestions for call template commands
]]
CreateThread(function()
    Config.LoadPlugin("calltemplates", function(pluginConfig)
        if not pluginConfig.enabled then return end

        CreateThread(function()
            for _, commandConfig in ipairs(pluginConfig.commands or {}) do
                if commandConfig.command ~= nil then
                    local suggestion = commandConfig.suggestionText or ("Create a CAD call with /%s"):format(commandConfig.command)
                    TriggerEvent('chat:addSuggestion', '/' .. commandConfig.command, suggestion, {
                        {name = "details", help = "Describe the call details to include in CAD"}
                    })
                    RegisterPlayerCommandHelp("calltemplates", commandConfig.command, suggestion, "[details]")
                end
            end
        end)
    end)
end)
