--[[
    Sonoran Plugins

    Plugin Configuration

    Put all needed configuration in this file.
]]
local config = {
    enabled = true,
    pluginName = "wraithv2", -- name your plugin here
    pluginAuthor = "SonoranCAD", -- author
    configVersion = "1.7",
    requiresPlugins = {{name = "lookups", critical = true}}, -- required plugins for this plugin to work, separated by commas
    -- use vehicle registration expirations, or not
    useExpires = true,
    -- use middle initials?
    useMiddleInitial = true,
    -- alert if no registration was found on scan?
    alertNoRegistration = true,
    -- if your custom vehicle record is different, change the below
    statusUid = "status",
    expiresUid = "expiration",
    -- statuses to flag on when scanned
    flagOnStatuses = {"STOLEN", "EXPIRED", "PENDING", "SUSPENDED"}
    -- set to the field IDs you want appended to the ALPR notifications (order preserved)
    ,customFields = {
        -- Example: insurance expiration field ID (Mapping ID from SonoranCAD admin --> Customization --> Custom Records)
        -- "_jlnnn2uwe",
    }
    -- Vehicle classes that will NOT get ran through CAD | Classes: https://docs.fivem.net/natives/?_0x29439776AAA00A62
    ,vehTypeFilter = { 13, 14, 15, 16, 21, 22 }
    ,notificationTimers = {
        validReg = 30000, -- 30 seconds for valid registration
        warrant = 20000, -- 20 seconds for warrant
        bolo = 20000, -- 20 seconds for bolo
        noReg = 5000, -- 5 seconds for no registration
    }
}

if config.enabled then Config.RegisterPluginConfig(config.pluginName, config) end
