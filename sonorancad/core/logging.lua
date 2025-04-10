local MessageBuffer = {}
local DebugBuffer = {}
local ErrorBuffer = {}

local ErrorCodes = {
    ['STEAM_ERROR'] = "You have set SonoranCAD to Steam mode, but have not configured a Steam Web API key. Please see FXServer documentation. SonoranCAD will not function in Steam mode without this set.",
    ['PORT_MISSING_ERROR'] = "Could not find valid server information for server ID %s. Ensure you have configured your server in the CAD before using the map or push events.",
    ['PORT_CONFIG_ERROR'] = "CONFIGURATION PROBLEM: Your current game server port (%s) does not match your CAD configuration (%s). Please ensure they match.",
    ['MAP_CONFIG_ERROR'] = "CONFIGURATION PROBLEM: Map port on the server (%s) does not match your CAD configuration (%s) for server ID (%s). Please ensure they match.",
    ['PORT_OUTBOUND_ERROR'] = "CONFIGURATION PROBLEM: Detected outbound IP (%s), but (%s) is configured in the CAD. They must match!",
    ['PORT_OUTBOUND_MISMATCH'] = "CONFIGURATION PROBLEM: Detected IP (%s), but (%s) is configured in the CAD. They must match!",
    ['CONFIG_ERROR'] = "Failed to load core configuration. Ensure config.json is present and is the correct format.",
    ['API_ERROR'] = "Failed to get version information. Is the API down? Please restart sonorancad.",
    ['API_PAID_ONLY'] = "ERROR: Your community cannot use any plugins requiring the API. Please purchase a subscription of Standard or higher.",
    ['ERROR_ABORT'] = "Aborted startup due to critical errors reported. Review logs for troubleshooting.",
    ['PLUGIN_DEPENDENCY_ERROR'] = "Submodule %s requires %s, which is not loaded! Skipping.",
    ['PLUGIN_VERSION_MISMATCH'] = "PLUGIN ERROR: Plugin %s requires %s at version %s or higher, but only %s was found. Use the command \"sonoran pluginupdate\" to check for updates.",
    ['PLUGIN_CONFIG_OUTDATED'] = "Plugin Updater: %s has a new configuration version (%s ~= %s). You should look at the template configuration file (%s_config.dist.lua) and update your configuration before using this plugin.",
    ['PLUGIN_CORE_OUTDATED'] = "PLUGIN ERROR: Plugin %s requires Core Version %s, but you have %s. Please update SonoranCAD to use this plugin. Force disabled.",
    ['CUSTOM_POSTALS_FILE_NOT_FOUND'] = "Your custom postals file %s could not be found in the /sonorancad/submodules/postals/ directory. Please ensure it exists and is not corrupted.",
    ['POSTAL_RESOURCE_MISSING'] = "The configured postals resource (%s) does not exist. Please check the name.",
    ['POSTAL_RESOURCE_STOPPED'] = "The postals resource (%s) is not started. Please ensure it's started before clients connect. This is only a warning.",
    ['POSTAL_RESOURCE_BAD_STATE'] = "The configured postals resource (%s) is in a bad state (%s). Please check it.",
    ['POSTAL_FILE_READ_ERROR'] = "Failed to open postals file for reading",
    ['POSTAL_CUSTOM_RESOURCE_FILE_ERROR'] = "Failed to locate postal file from resource %s! Please ensure that it is defined in %s's fxmanifest.lua as 'postal_file'",
    ['IDCARD_RESOURCE_NOT_STARTED'] = "The sonoran_idcard resource seems to be stopped, this resource is required for the ID card UI to work. Attempting to start the resource. Please add it to your server.cfg to run by default.",
    ['IDCARD_RESOURCE_MISSING'] = "The sonoran_idcard resource seems to be missing, this resource is required for the the ID card UI to work. Please ensure the resource name is exactly: 'sonoran_idcard' or install it from our GitHub: https://github.com/Sonoran-Software/id_card_ui",
    ['IDCARD_RESOURCE_BAD_STATE'] = "The sonoran_idcard resource is in a bad state. Please check it.",
    ['INCORRECT_WKWARS2X_VERSION'] = "It appears that you are using an incorrect version of the resource wk_wars2x. Please ensure you install the version from our GitHub: https://github.com/Sonoran-Software/wk_wars2x. The version you are using is not compatible with SonoranCAD.",
}

function getErrorText(err)
    return ErrorCodes[err]
end

local function LocalTime()
	local _, _, _, h, m, s = GetLocalTime()
	return '' .. h .. ':' .. m .. ':' .. s
end

local function sendConsole(level, color, message)
    local debugging = true
    if Config ~= nil then
        debugging = (Config.debugMode == true and Config.debugMode ~= "false")
    end
    local time = os and os.date("%X") or LocalTime()
    local info = debug.getinfo(3, 'S')
    local source = "."
    if info.source:find("@@sonorancad") then
        source = info.source:gsub("@@sonorancad/","")..":"..info.linedefined
    end
    local msg = ("[%s][%s:%s%s^7]%s %s^0"):format(time, debugging and source or "SonoranCAD", color, level, color, message)
    if (debugging and level == "DEBUG") or level ~= "DEBUG" then
        print(msg)
    end
    if (level == "ERROR" or level == "WARNING") and IsDuplicityVersion() then
        table.insert(ErrorBuffer, 1, msg)
    end
    if level == "DEBUG" and IsDuplicityVersion() then
        if #DebugBuffer > 50 then
            table.remove(DebugBuffer)
        end
        table.insert(DebugBuffer, 1, msg)
    else
        if not IsDuplicityVersion() then
            if #MessageBuffer > 10 then
                table.remove(MessageBuffer)
            end
            table.insert(MessageBuffer, 1, msg)
        end
    end
end

function getDebugBuffer()
    return DebugBuffer
end

function getErrorBuffer()
    return ErrorBuffer
end

function debugLog(message)
    if Config == nil then
        return
    end
    sendConsole("DEBUG", "^7", message)
end

function debugPrint(message)
    debugLog(message)
end

function logError(err, msg)
    local o = ""
    if msg == nil then
        o = ("ERR %s: %s - See https://sonoran.software/errorcodes for more information."):format(err, ErrorCodes[err])
    else
        o = ("ERR %s: %s - See https://sonoran.software/errorcodes for more information."):format(err, msg)
    end
    sendConsole("ERROR", "^1", o)
end

function errorLog(message)
    sendConsole("ERROR", "^1", message)
end

function warnLog(message)
    sendConsole("WARNING", "^3", message)
end

function infoLog(message)
    sendConsole("INFO", "^5", message)
end

--RegisterServerEvent("SonoranCAD::core:writeLog")
AddEventHandler("SonoranCAD::core:writeLog", function(level, message)
    if level == "debug" then
        debugLog(message)
    elseif level == "info" then
        infoLog(message)
    elseif level == "error" then
        errorLog(message)
    elseif level == "warn" then
        warnLog(message)
    else
        debugLog(message)
    end
end)

RegisterNetEvent("SonoranCAD::core:RequestLogBuffer")
AddEventHandler("SonoranCAD::core:RequestLogBuffer", function()
    if not IsDuplicityVersion() then
        TriggerServerEvent("SonoranCAD::core:LogBuffer", MessageBuffer)
        print("log buffer requested")
    end
end)

print(("^5%s^0"):format([[
    _____                                    _________    ____
   / ___/____  ____  ____  _________ _____  / ____/   |  / __ \
   \__ \/ __ \/ __ \/ __ \/ ___/ __ `/ __ \/ /   / /| | / / / /
  ___/ / /_/ / / / / /_/ / /  / /_/ / / / / /___/ ___ |/ /_/ /
 /____/\____/_/ /_/\____/_/   \__,_/_/ /_/\____/_/  |_/_____/

]]))
infoLog("Starting up...")