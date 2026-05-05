--[[
    SonoranCAD FiveM Integration

    Commands Module

    Provides /sonoran command for console control
]]

--[[ /sonoran
    debugmode - old caddebug toggle
    info - dump version info, configuration
    support - dump useful data for support staff
    verify - run hash checks to confirm all files are untampered
    plugin <name> - show info about a plugin (config)
    update - attempt to auto-update
]]

local function sanitizeForJson(value, seen)
    local valueType = type(value)
    if valueType == "nil" or valueType == "boolean" or valueType == "number" or valueType == "string" then
        return value
    end
    if valueType == "function" or valueType == "thread" or valueType == "userdata" then
        return ("<%s>"):format(valueType)
    end
    if valueType ~= "table" then
        return tostring(value)
    end

    seen = seen or {}
    if seen[value] then
        return "<recursive-table>"
    end
    seen[value] = true

    local sanitized = {}
    for k, v in pairs(value) do
        local sanitizedKey = sanitizeForJson(k, seen)
        if type(sanitizedKey) ~= "string" and type(sanitizedKey) ~= "number" then
            sanitizedKey = tostring(sanitizedKey)
        end
        sanitized[sanitizedKey] = sanitizeForJson(v, seen)
    end

    seen[value] = nil
    return sanitized
end

 function dumpInfo()
    local version = GetResourceMetadata(GetCurrentResourceName(), "version", 0)
    local pluginList, loadedPlugins, disabledPlugins = GetPluginLists()
    local pluginVersions = {}
    local cadVariables = { ["netPort"] = GetConvar("netPort", "Unknown")}
    local variableList = ""
    for k, v in pairs(cadVariables) do
        variableList = ("%s%s = %s\n"):format(variableList, k, v)
    end
    for k, v in pairs(pluginList) do
        if Config.plugins[v] then
            table.insert(pluginVersions, ("%s [%s/%s]"):format(v, Config.plugins[v].version, Config.plugins[v].latestVersion))
        end
    end
    local coreConfig = {}
    for k, v in pairs(Config) do
        if (k == "plugins") then goto continue end
        if type(v) == "function" then goto continue end
        if type(v) == "table" then
            local encoded = SafeJsonEncode(sanitizeForJson(v), ("support dump core config %s"):format(tostring(k)), "{}")
            table.insert(coreConfig, ("%s = %s"):format(k, encoded or "{}"))
            goto continue
        end
        if type(v) == "thread" then goto continue end
        table.insert(coreConfig, ("%s = %s"):format(k, v))
        coreConfig[k] = v
        ::continue::
    end
    return ([[
SonoranCAD
Version: %s - Latest: %s
FXS Version: %s
Available Submodules
%s
Loaded Submodules
%s
Disabled Submodules
%s
Relevant Variables
%s
Core Configuration
%s
    ]]):format(version, Config.latestVersion, getServerVersion(), table.concat(pluginVersions, ", "), table.concat(loadedPlugins, ", "), table.concat(disabledPlugins, ", "), variableList, table.concat(coreConfig, "\n"))
end

function dumpPlugin(name)
    local pluginDetail = {}
    if not Config.plugins[name] then
        print("Bad plugin: "..name)
        return nil
    end
    for k, v in pairs(Config.plugins[name]) do
        table.insert(pluginDetail, ("%s = %s"):format(k, v))
    end
    return ([[
Plugin: %s
Version: %s
Configuration:
    %s
    ]]):format(name, Config.plugins[name].version, table.concat(pluginDetail, "\n     "))
end

local function sendSupportLogs(key, requester)
    requester = tonumber(requester) or 0
    infoLog("Please wait, gathering required data...")
    local cadOutput = {}
    cadOutput.key = tonumber(key)
    if cadOutput.key == nil then
        if requester > 0 then
            sendClientError(requester, "SUPPORT_INVALID_ID")
        else
            logError("SUPPORT_INVALID_ID")
        end
        return false
    end
    local plugins = {}
    for name, config in pairs(Config.plugins) do
        local pluginData = {}
        pluginData.name = name
        pluginData.version = config.version
        pluginData.config = sanitizeForJson(config)
        table.insert(plugins, pluginData)
    end
    cadOutput.plugins = plugins
    cadOutput.errors = sanitizeForJson(getSupportErrorBuffer())
    local encodedErrors = "[]"
    if cadOutput.errors ~= nil then
        local ok, serialized = pcall(json.encode, cadOutput.errors)
        if ok and type(serialized) == "string" then
            encodedErrors = serialized
        end
    end
    cadOutput.logs = ([[
SonoranCAD Support Output
---------------------------------------
Configuration Information
---
%s

---------------------------------------
Structured Error Buffer
-----------------------
%s
---------------------------------------
Console Buffer
------
%s
---------------------------------------
Last 50 Debug Messages
----------------------
%s
    ]]):format(dumpInfo(), encodedErrors, GetConsoleBuffer(), table.concat(getDebugBuffer(), "\n"))
    Config.debugMode = false
    if SetCadClientLogLevel ~= nil then
        SetCadClientLogLevel()
    end
    local response = CadApiUploadSupportLogs(sanitizeForJson(cadOutput))
    local uploadSucceeded = response.success == true
    if uploadSucceeded then
        infoLog("Support logs have been successfully uploaded. Debug mode was disabled during the upload.")
        if requester > 0 then
            NotifyPlayer(requester, {
                title = "Support",
                message = formatErrorMessage("SUPPORT_UPLOAD_SUCCESS"),
                type = "success"
            })
        end
        return true
    elseif response.success then
        local message = ("%s Response: %s"):format(getErrorText("SUPPORT_UPLOAD_FAILED"), tostring(type(response.data) == "table" and (response.data.error or SafeJsonEncode(response.data, "support upload partial success", "{}")) or response.data))
        if requester > 0 then
            sendClientError(requester, "SUPPORT_UPLOAD_FAILED")
        else
            logError("SUPPORT_UPLOAD_FAILED", message)
        end
    else
        local message = ("%s Reason: %s"):format(getErrorText("SUPPORT_UPLOAD_FAILED"), CadApiReasonText(response.reason))
        if requester > 0 then
            sendClientError(requester, "SUPPORT_UPLOAD_FAILED")
        else
            logError("SUPPORT_UPLOAD_FAILED", message)
        end
    end
    return false
end
RegisterCommand("sonorancad", function(source, args, rawCommand)
    if source ~= 0 then
        handlePlayerSonoranCommand(source, args)
        return
    end
    if not args[1] then
        print("Missing command. Try \"sonorancad help\" for help.")
        return
    end
    if args[1] == "help" then
        print([[
SonoranCAD Help
    debugmode - Toggles debugging mode
    info - dump version info, configuration
    support - dump useful data for support staff
    errors - display all error/warning messages since last startup
    plugin <name> - show info about a plugin (config)
    update - Run core updater
    viewcaches - View the current unit and call cache, for troubleshooting
    getclientlog <playerId> - Get a log buffer from a given client
    dumpconsole - Dumps current console buffer to file
]])
    elseif args[1] == "debugmode" then
        Config.debugMode = not Config.debugMode
        local convarString = ""
        if Config.debugMode then
            convarString = "true"
        else
            convarString = "false"
        end
        SetConvar("sonoran_debugMode", convarString)
        if SetCadClientLogLevel ~= nil then
            SetCadClientLogLevel()
        end
        infoLog(("Debug mode toggled to %s"):format(convarString))
        TriggerClientEvent("SonoranCAD::core:debugModeToggle", -1, Config.debugMode)
        local sonoran = sonoranModule or load_sonoran_module()
        GetCadClient():setLogLevel(get_sonoran_log_level(sonoran))
    elseif args[1] == "info" then
        print(dumpInfo())
    elseif args[1] == "support" and args[2] ~= nil then
        sendSupportLogs(args[2], 0)
    elseif args[1] == "plugin" and args[2] then
        if Config.plugins[args[2]] then
            print(dumpPlugin(args[2]))
        else
            errorLog("INVALID_COMMAND_ARGUMENT", "Invalid plugin.")
        end
    elseif args[1] == "update" then --update - attempt to auto-update
        infoLog("Checking for core update...")
        RunAutoUpdater(true)
    elseif args[1] == "dumpconsole" then
        local savePath = GetResourcePath(GetCurrentResourceName()).."/buffer.log"
        local f, openErr = io.open(savePath, 'wb')
        if not f then
            logError("FILE_WRITE_FAILED", ("Failed to open console dump path %s: %s"):format(savePath, tostring(openErr)))
            return
        end
        local ok, writeErr = pcall(function()
            f:write(GetConsoleBuffer())
            f:close()
        end)
        if not ok then
            logError("FILE_WRITE_FAILED", ("Failed to write console dump path %s: %s"):format(savePath, tostring(writeErr)))
            return
        end
        infoLog("Wrote buffer to "..savePath)
    elseif args[1] == "pluginupdate" then
        infoLog("Scanning for plugin updates...")
        for k, v in pairs(Config.plugins) do
            CheckForPluginUpdate(k, true)
        end
    elseif args[1] == "viewcaches" then
        local units = GetUnitCache()
        local calls = GetCallCache()
        print(("Units: %s\r\nCalls: %s"):format(json.encode(units), json.encode(calls)))
        print("Done")
    elseif args[1] == "getclientlog" then
        if args[2] then
            if GetPlayerName(args[2]) ~= nil then
                TriggerClientEvent("SonoranCAD::core:RequestLogBuffer", args[2])
                infoLog("Requested log buffer. Please wait...")
            else
                errorLog("INVALID_COMMAND_ARGUMENT", "Invalid player ID.")
            end
        else
            errorLog("INVALID_COMMAND_ARGUMENT", "Invalid argument.")
        end
    elseif args[1] == "errors" then
        print("----ERROR/WARNING BUFFER START----")
        local buf = getErrorBuffer()
        for i=1, #buf do
            print(buf[i])
        end
        print("----ERROR/WARNING BUFFER END----")
    else
        print("Missing command. Try \"sonorancad help\" for help.")
    end
end, false)

function GetPluginLists()
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
    for name, reason in pairs(disabledPlugins) do
        table.insert(disableFormatted, ("%s (%s)"):format(name, reason))
    end
    return pluginList, loadedPlugins, disableFormatted
end

-- Support Push Event

AddEventHandler("SonoranCAD::pushevents:SendSupportLogs", function(key)
    infoLog("Support has requested logs to be uploaded. Collecting now...")
    sendSupportLogs(key, 0)
end)

RegisterNetEvent("SonoranCAD::core:UploadSupportLogs")
AddEventHandler("SonoranCAD::core:UploadSupportLogs", function(key)
    sendSupportLogs(key, source)
end)

RegisterNetEvent("SonoranCAD::core:LogBuffer")
AddEventHandler("SonoranCAD::core:LogBuffer", function(buffer)
    infoLog(("Incoming log buffer from player %s"):format(source))
    for i=1, #buffer do
        print((": %s"):format(buffer[i]))
    end
    infoLog("End of buffer")
end)
