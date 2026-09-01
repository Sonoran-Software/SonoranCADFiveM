--[[
    Sonoran Plugins

    Plugin Configuration

    Put all needed configuration in this file.
]]
local config = {
    enabled = true,
    pluginName = "locations", -- name your plugin here
    pluginAuthor = "SonoranCAD", -- author
    configVersion = "1.2", -- version of your plugin
    requiresPlugins = {},
    -- put your configuration options below
    -- checkTime = 5000, -- how frequently to send locations to the server | DEPRECIATED
    clientCheckTime = 250, -- how often the client will check for a location update
    prefixPostal = true, -- prefix postal code on locations sent, requires postal plugin
    customStreetNames = {
        enabled = false,
        -- Optional street-name overrides used by location updates. This is useful when
        -- a HUD keeps its custom names private instead of updating game text entries.
        -- If your HUD can update game text entries globally, use that option instead;
        -- the normal FiveM street-name natives will then return the custom names.
        -- Copy the same street hash/name pairs from the HUD's configuration here.
        -- Numeric, signed decimal, and quoted hexadecimal hashes are supported.
        names = {
            -- [0xAC9F694E] = "Custom Freeway Name",
            -- ["0x10A6E7C9"] = "Custom Street Name"
        }
    }
}

if config.enabled then
    Config.RegisterPluginConfig(config.pluginName, config)
end
