--[[
    Sonoran Plugins

    Plugin Configuration

    Put all needed configuration in this file.
]]
local config = {
    enabled = true,
    pluginName = "kick", -- name your plugin here
    pluginAuthor = "TaylorMade#4860", -- author
    configVersion = "1.0", -- version of the plugin
    requiresPlugins = {}, -- required plugins for this plugin to work, separated by commas
    -- Optional notification override for this submodule only.
    -- Valid values: "none", "ox_lib", "lation_ui", "pnotify", "chat"
    notificationOverride = "none",

    -- put your configuration options below

}

if config.enabled then
    Config.RegisterPluginConfig(config.pluginName, config)
end
