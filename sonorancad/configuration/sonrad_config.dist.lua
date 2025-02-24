--[[
    Sonoran Plugins

    Plugin Configuration

    Put all needed configuration in this file.

]]
local config = {
    enabled = false,
    configVersion = "1.0",
    pluginName = "sonrad", -- name your plugin here
    pluginAuthor = "SonoranCAD", -- author
    requiresPlugins = {},
    -- put your configuration options below

    -- Should radio panics generate CAD calls?
    addPanicCall = true,
    syncRadioName = {
        enabled = true, -- should the radio name be synced with the CAD?
        nameFormat = "{UNIT_NUMBER} | {UNIT_NAME}" -- format of the radio name | available variables: {UNIT_NUMBER}, {UNIT_NAME}
    }

}

if config.enabled then
    Config.RegisterPluginConfig(config.pluginName, config)
end