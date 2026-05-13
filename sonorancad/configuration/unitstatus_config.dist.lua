--[[
    Sonoran Plugins

    Plugin Configuration

    Put all needed configuration in this file.
]]
local config = {
    enabled = true,
    pluginName = "unitstatus", -- name your plugin here
    pluginAuthor = "SonoranCAD", -- author
    configVersion = "1.0",
    requiresPlugins = {}, -- required plugins for this plugin to work, separated by commas
    -- Optional notification override for this submodule only.
    -- Valid values: "none", "ox_lib", "lation_ui", "pnotify", "chat"
    notificationOverride = "none",
    setStatusCommand = "setstatus", -- user command for setting their own status, leave blank to not use
    -- put your configuration options below
    statusCodes = {
        ["UNAVAILABLE"] = 0,
        ["BUSY"] = 1,
        ["AVAILABLE"] = 2,
        ["ENROUTE"] = 3,
        ["ON_SCENE"] = 4
    },
    enableAceCheck = true -- restrict command via ace permission
}

if config.enabled then
    Config.RegisterPluginConfig(config.pluginName, config)
end
