--[[
    Sonoran Plugins

    Plugin Configuration

    Put all needed configuration in this file.
]]
local config = {
    enabled = true,
    pluginName = "calltemplates", -- name your plugin here
    pluginAuthor = "SonoranCAD", -- author
    requiresPlugins = {
        {name = "locations", critical = true},
        {name = "postals", critical = false}
    }, -- required plugins for this plugin to work, separated by commas
    configVersion = "2.0.0",

    -- Path containing exported call type JSON templates
    callTypeDirectory = "submodules/calltemplates/calltypes",

    -- Defaults used if the template does not specify them
    defaultOrigin = 2, -- 0 = CALLER / 1 = RADIO DISPATCH / 2 = OBSERVED / 3 = WALK_UP
    defaultStatus = 1, -- 0 = PENDING / 1 = ACTIVE / 2 = CLOSED
    defaultPriority = 1, -- 1, 2, or 3

    -- When true, templates are re-read every command execution (useful while editing files)
    reloadTemplatesOnEachUse = false,

    -- Command to template mappings
    commands = {
        {
            command = "ts",
            callTypeFile = "traffic_stop.json",
            descriptionPrefix = "Traffic Stop -",
            suggestionText = "Create a Traffic Stop dispatch call",
            includeWraithPlate = true, -- attach locked plate from wraithv2 if available
            includePlayerUnit = true,
            useAcePermissions = true -- requires ace permission "command.ts"
        },
        {
            command = "towreq",
            callTypeFile = "tow_request.json",
            descriptionPrefix = "Tow Request -",
            suggestionText = "Request a tow using the tow call type template",
            includePlayerUnit = true,
            useAcePermissions = true -- requires ace permission "command.towreq"
        }
    }
}

if config.enabled then Config.RegisterPluginConfig(config.pluginName, config) end
