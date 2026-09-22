--[[
    SonoranCAD FiveM Integration

    Plugin Loader

    Provides logic for checking loaded plugins after startup
]]

local function LoadVersionFile()
    local f = LoadResourceFile(GetCurrentResourceName(), ("version.json"))
    if f then
        return f
    else
        warnLog("UNHANDLED_WARNING", ("Failed to load version file from /sonorancad/version.json Check to see if the file exists."))
        return nil
    end
end

-- Module configuration versions are supplied by the backend catalog.
-- Local configuration-file update/backup checks are no longer applicable.
function CheckForPluginUpdate(name) end

CreateThread(function()
    Wait(5000)
    while Config.apiVersion == -1 do Wait(10) end
    if Config.critError then logError("ERROR_ABORT") end

    local versionFile = nil
    local vfile = LoadVersionFile()
    if vfile == nil then
        warnLog("UNHANDLED_WARNING", "Unable to load local plugin version file")
        goto skip
    end
    versionFile = json.decode(vfile)
    if versionFile == nil then
        warnLog("UNHANDLED_WARNING", "Unable to parse local plugin version file")
        goto skip
    end

    for k, v in pairs(Config.plugins) do
        if Config.critError then
            Config.plugins[k].enabled = false
            Config.plugins[k].disableReason = "Startup aborted"
            goto skip
        end
        if Config.plugins[k].enabled then
            if versionFile.submoduleConfigs[k] ~= nil and versionFile.submoduleConfigs[k].requiresPlugins ~= nil then
                for _, plugin in pairs(versionFile.submoduleConfigs[k].requiresPlugins) do
                    local isCritical = plugin.critical
                    if Config.plugins[plugin.name] == nil or not Config.plugins[plugin.name].enabled then
                        if isCritical then
                            logError("PLUGIN_DEPENDENCY_ERROR", getErrorText("PLUGIN_DEPENDENCY_ERROR"):format(k, plugin.name))
                            Config.plugins[k].enabled = false
                            Config.plugins[k].disableReason = ("Missing dependency %s"):format(plugin.name)
                        elseif plugin.name ~= "esxsupport" then
                            warnLog("UNHANDLED_WARNING", ("[submodule loader] submodule %s requires %s, but it is not installed. Some features may not work properly."):format(k, plugin.name))
                        end
                    end
                end
            end
        end
        CheckForPluginUpdate(k)
    end
    ::skip::
    local pluginList = {}
    local loadedPlugins = {}
    local disabledPlugins = {}
    local disableFormatted = {}
    for name, v in pairs(Config.plugins) do
        table.insert(pluginList, name)
        if v.enabled then
            table.insert(loadedPlugins, name)
        else
            if v.disableReason == nil then
                v.disableReason = "disabled in config"
            end
            disabledPlugins[name] = v.disableReason
        end
    end
    infoLog(("Available Submodules: %s"):format(table.concat(pluginList, ", ")))
    infoLog(("Loaded Submodules: %s"):format(table.concat(loadedPlugins, ", ")))
    for name, reason in pairs(disabledPlugins) do
        table.insert(disableFormatted, ("%s (%s)"):format(name, reason))
    end
    if #disableFormatted > 0 then
        infoLog(("Disabled Submodules: %s"):format(
                    table.concat(disableFormatted, ", ")))
    end
    SetQuietPrintStartupComplete(true)
end)
