--[[

Sonoran Plugins

    tablet_config Plugin Configuration

    Put all needed configuration in this file.

]]

local config = {
    enabled = true,
    configVersion = "1.0",
    pluginName = "tablet_config", -- name your plugin here
    pluginAuthor = "Bushcowboy", -- author
    requiresPlugins = {}, -- required plugins for this plugin to work, separated by commas

    -- Auto-hide and access settings
    AutoHideOnVehicleExit = true, -- if true, the cad will automatically hide when the player exits a vehicle
    AllowMiniCadOnFoot = false, -- if true, player can access the cad while on foot

    AccessRestrictions = {
        RequireTabletItem = true, -- if true, player must have the tablet item to access the cad
        TabletItemName = "sonoran_tablet", -- name of the tablet item
        RestrictByJob = true, -- if true, player must have a job in the allowed jobs list to access the cad
        RestrictByVehicle = false, -- if true, player must be in a vehicle in the allowed vehicles list to access the cad
        AllowedJobs = {
            "lspd",
            "sheriff",
            "ambulance",
            "fire"
        },
        AllowedVehicles = {
            "police",
            "police2",
            "police3",
            "police4",
            "fbi",
            "fbi2",
            "ambulance",
            "firetruk"
        }
    }

}

if config.enabled then
    Config.RegisterPluginConfig(config.pluginName, config)
end