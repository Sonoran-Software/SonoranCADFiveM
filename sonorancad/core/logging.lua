local MessageBuffer = {}
local DebugBuffer = {}
local ErrorBuffer = {}
local SupportErrorBuffer = {}
local ERROR_DOC_BASE_URL = "https://sonorancad.com/error/"
local SupportRefCounter = 0
local sendConsole

local WarningCodes = {
    ['INVALID_API_MODE'] = { code = "WRN-CORE-001", message = "An invalid SonoranCAD API mode was configured. The resource is falling back to production." },
    ['DEPRECATED_DEBUGPRINT'] = { code = "WRN-CORE-002", message = "The deprecated debugPrint function was used. Migrate callers to debugLog." },
    ['JSON_DECODE_FAILED'] = { code = "WRN-CORE-003", message = "A JSON payload could not be decoded cleanly." },
    ['JSON_ENCODE_FAILED'] = { code = "WRN-CORE-004", message = "A Lua table could not be encoded into JSON cleanly." },
    ['APIKEY_CONVAR_UNINITIALIZED'] = { code = "WRN-CORE-005", message = "The sonorancad.cfg convars were not initialized before SonoranCAD started." },
    ['OLD_FXSERVER_VERSION'] = { code = "WRN-CORE-006", message = "The running FXServer build is older than the version SonoranCAD was tested against." },
    ['PLAYER_IDENTIFIER_MISSING'] = { code = "WRN-CAD-101", message = "A player connected without the configured primary identifier." },
    ['LEGACY_HTTP_PUSH_EVENT'] = { code = "WRN-WS-101", message = "A legacy HTTP push event was received while WebSocket delivery is preferred." },
    ['UNHANDLED_WARNING'] = { code = "WRN-CORE-900", message = "A non-fatal warning occurred." },
}

local ErrorCodes = {
    ['STEAM_ERROR'] = { code = "ERR-CORE-001", message = "You have set SonoranCAD to Steam mode, but have not configured a Steam Web API key. Please see FXServer documentation. SonoranCAD will not function in Steam mode without this set." },
    ['PORT_MISSING_ERROR'] = { code = "ERR-CORE-002", message = "Could not find valid server information for server ID %s. Ensure you have configured your server in the CAD before using the map or push events." },
    ['PORT_CONFIG_ERROR'] = { code = "ERR-CORE-003", message = "CONFIGURATION PROBLEM: Your current game server port (%s) does not match your CAD configuration (%s). Please ensure they match." },
    ['MAP_CONFIG_ERROR'] = { code = "ERR-CORE-004", message = "CONFIGURATION PROBLEM: Map port on the server (%s) does not match your CAD configuration (%s) for server ID (%s). Please ensure they match." },
    ['PORT_OUTBOUND_ERROR'] = { code = "ERR-CORE-005", message = "CONFIGURATION PROBLEM: Detected outbound IP (%s), but (%s) is configured in the CAD. They must match!" },
    ['PORT_OUTBOUND_MISMATCH'] = { code = "ERR-CORE-006", message = "CONFIGURATION PROBLEM: Detected IP (%s), but (%s) is configured in the CAD. They must match!" },
    ['CONFIG_ERROR'] = { code = "ERR-CORE-007", message = "Failed to load core configuration. Ensure config.json is present and is the correct format." },
    ['API_ERROR'] = { code = "ERR-CORE-008", message = "Failed to get version information. Is the API down? Please restart sonorancad." },
    ['ERROR_ABORT'] = { code = "ERR-CORE-010", message = "Aborted startup due to critical errors reported. Review logs for troubleshooting." },
    ['PLUGIN_DEPENDENCY_ERROR'] = { code = "ERR-CORE-011", message = "Submodule %s requires %s, which is not loaded! Skipping." },
    ['PLUGIN_VERSION_MISMATCH'] = { code = "ERR-CORE-012", message = "PLUGIN ERROR: Plugin %s requires %s at version %s or higher, but only %s was found. Use the command \"sonoran pluginupdate\" to check for updates." },
    ['PLUGIN_CONFIG_OUTDATED'] = { code = "ERR-CORE-013", message = "Plugin Updater: %s has a new configuration version (%s ~= %s). You should look at the template configuration file (%s_config.dist.lua) and update your configuration before using this plugin." },
    ['PLUGIN_CORE_OUTDATED'] = { code = "ERR-CORE-014", message = "PLUGIN ERROR: Plugin %s requires Core Version %s, but you have %s. Please update SonoranCAD to use this plugin. Force disabled." },
    ['CUSTOM_POSTALS_FILE_NOT_FOUND'] = { code = "ERR-CORE-015", message = "Your custom postals file %s could not be found in the /sonorancad/submodules/postals/ directory. Please ensure it exists and is not corrupted." },
    ['POSTAL_RESOURCE_MISSING'] = { code = "ERR-CORE-016", message = "The configured postals resource (%s) does not exist. Please check the name." },
    ['POSTAL_RESOURCE_STOPPED'] = { code = "ERR-CORE-017", message = "The postals resource (%s) is not started. Please ensure it's started before clients connect. This is only a warning." },
    ['POSTAL_RESOURCE_BAD_STATE'] = { code = "ERR-CORE-018", message = "The configured postals resource (%s) is in a bad state (%s). Please check it." },
    ['POSTAL_FILE_READ_ERROR'] = { code = "ERR-CORE-019", message = "Failed to open postals file for reading" },
    ['POSTAL_CUSTOM_RESOURCE_FILE_ERROR'] = { code = "ERR-CORE-020", message = "Failed to locate postal file from resource %s! Please ensure that it is defined in %s's fxmanifest.lua as 'postal_file'" },
    ['IDCARD_RESOURCE_NOT_STARTED'] = { code = "ERR-CORE-021", message = "The sonoran_idcard resource is installed but not started. Use exec sonorancad.cfg and make sure sonorancad.cfg contains 'ensure sonoran_idcard' before 'ensure sonorancad'." },
    ['IDCARD_RESOURCE_MISSING'] = { code = "ERR-CORE-022", message = "The sonoran_idcard resource is missing. Use the bundled sonorancad.cfg and make sure it contains 'ensure sonoran_idcard', then install the resource with the exact name 'sonoran_idcard'." },
    ['IDCARD_RESOURCE_BAD_STATE'] = { code = "ERR-CORE-023", message = "The sonoran_idcard resource is in a bad state. Use exec sonorancad.cfg, confirm it contains 'ensure sonoran_idcard', and review the sonoran_idcard startup errors." },
    ['INCORRECT_WKWARS2X_VERSION'] = { code = "ERR-CORE-024", message = "It appears that you are using an incorrect version of the resource wk_wars2x. Please ensure you install the version from our GitHub: https://github.com/Sonoran-Software/wk_wars2x. The version you are using is not compatible with SonoranCAD." },
    ['TABLET_RESOURCE_NOT_STARTED'] = { code = "ERR-CORE-030", message = "The tablet resource is installed but not started. Use exec sonorancad.cfg and make sure sonorancad.cfg contains 'ensure tablet' before 'ensure sonorancad'." },
    ['TABLET_RESOURCE_MISSING'] = { code = "ERR-CORE-031", message = "The tablet resource is missing. Use the bundled sonorancad.cfg and make sure it contains 'ensure tablet', then install the resource with the exact name 'tablet'." },
    ['TABLET_RESOURCE_BAD_STATE'] = { code = "ERR-CORE-032", message = "The tablet resource is in a bad state. Use exec sonorancad.cfg, confirm it contains 'ensure tablet', and review the tablet startup errors." },
    ['PLAYER_NOT_LINKED'] = { code = "ERR-CAD-101", message = "Your CAD account is not linked. Use /%s to link your account." },
    ['PLAYER_NOT_ONLINE'] = { code = "ERR-CAD-102", message = "You are not online in CAD. Log in to a Police, Fire, EMS, or civilian profile first." },
    ['PLAYER_NOT_IN_CAD'] = { code = "ERR-CAD-103", message = "You must be linked and online in CAD before using this feature." },
    ['SUPPORT_INVALID_ID'] = { code = "ERR-SUP-101", message = "The support request ID is invalid. Check the ID and try again." },
    ['SUPPORT_UPLOAD_FAILED'] = { code = "ERR-SUP-102", message = "Support logs could not be uploaded right now. Try again in a moment." },
    ['SUPPORT_UPLOAD_SUCCESS'] = { code = "ERR-SUP-103", message = "Support logs were uploaded successfully." },
    ['BODYCAM_FORCEOFF_PERMISSION'] = { code = "ERR-BC-101", message = "You do not have permission to use the bodycam force-off command." },
    ['BODYCAM_CHILD_PERMISSION'] = { code = "ERR-BC-102", message = "Bodycam recording cannot start because child-process permission is missing. Run exec sonorancad.cfg or add the required child-process permission for sonorancad." },
    ['BODYCAM_F8_PERMISSION'] = { code = "ERR-BC-104", message = "The bodycam keybind command is blocked by ACE permissions. Allow command.SonoranCAD::bodycam::Keybind and command.SonoranCAD::bodycam::RecordingKeybind for players." },
    ['BODYCAM_NOT_ON_DUTY'] = { code = "ERR-BC-105", message = "You must be online in CAD before toggling bodycam." },
    ['CADDISPLAY_F8_PERMISSION'] = { code = "ERR-CD-101", message = "The CAD display keybind commands are blocked by ACE permissions. Allow command.SonoranCAD::caddisplay::Interact, command.SonoranCAD::caddisplay::AcceptRequest, and command.SonoranCAD::caddisplay::DenyRequest for players." },
    ['CALL_MISSING_DETAILS'] = { code = "ERR-CALL-101", message = "You need to specify call details before sending this to CAD." },
    ['CALL_SEND_FAILED'] = { code = "ERR-CALL-102", message = "The call could not be sent to CAD." },
    ['CALL_TEMPLATE_INVALID'] = { code = "ERR-CALL-103", message = "The configured call template is missing or invalid." },
    ['PANIC_F8_PERMISSION'] = { code = "ERR-CALL-104", message = "The panic keybind command is blocked by ACE permissions. Allow command.panic for players." },
    ['CAD_API_DISABLED'] = { code = "ERR-CORE-025", message = "The SonoranCAD API is currently disabled by config or convar." },
    ['UPDATE_CHILD_PERMISSION'] = { code = "ERR-CORE-026", message = "Auto-update could not continue because sonorancad was not granted child-process permission. Run exec sonorancad.cfg instead of only ensure sonorancad." },
    ['INVALID_API_MODE'] = { code = "ERR-CORE-027", message = "An invalid SonoranCAD API mode was configured. Falling back to production." },
    ['FILE_WRITE_FAILED'] = { code = "ERR-CORE-028", message = "SonoranCAD could not write a required file to disk." },
    ['CAD_API_REQUEST_FAILED'] = { code = "ERR-CORE-029", message = "A CAD API request failed." },
    ['LOCAL_NETWORK_TIMEOUT'] = { code = "ERR-CORE-033", message = "The local server network timed out while connecting to SonoranCAD. Check the server host, firewall, proxy, or upstream network connection." },
    ['UNHANDLED_SERVER_ERROR'] = { code = "ERR-CORE-900", message = "An unexpected server error occurred." },
    ['UNHANDLED_WARNING'] = { code = "ERR-CORE-901", message = "A non-fatal warning occurred." },
    ['INVALID_COMMAND_ARGUMENT'] = { code = "ERR-CORE-902", message = "One or more command arguments were invalid." },
    ['FEATURE_UNAVAILABLE'] = { code = "ERR-CORE-903", message = "This feature is currently unavailable." },
    ['MALFORMED_PAYLOAD'] = { code = "ERR-CORE-904", message = "Received malformed or incomplete data." },
    ['PERMISSION_DENIED'] = { code = "ERR-CORE-905", message = "You do not have permission to use this feature." },
    ['CLIENT_RUNTIME_ERROR'] = { code = "ERR-CORE-906", message = "A client-side runtime error occurred." },
    ['PLUGIN_CONFIG_PARSE_FAILED'] = { code = "ERR-PLUG-109", message = "A plugin configuration file could not be parsed." },
    ['POSTALS_RESOURCE_UNAVAILABLE'] = { code = "ERR-LOC-104", message = "Nearest postal data is unavailable." },
    ['POSTALS_FILE_INVALID'] = { code = "ERR-LOC-105", message = "The configured postal file is missing or invalid." },
    ['FRAMEWORK_QUERY_INVALID'] = { code = "ERR-FW-103", message = "A framework database query or parameter set was invalid." },
    ['VEHREG_NO_CHARACTER'] = { code = "ERR-VR-101", message = "No CAD character was found. Make sure you are logged in to a CAD character first." },
    ['VEHREG_CREATE_FAILED'] = { code = "ERR-VR-102", message = "The vehicle registration record could not be created." },
    ['VEHREG_PLATE_TAKEN'] = { code = "ERR-VR-103", message = "That plate is already registered in CAD." },
    ['UNITSTATUS_INVALID_STATUS'] = { code = "ERR-US-101", message = "The requested unit status is invalid or not configured." },
    ['APIWS_DEPENDENCY_MISSING'] = { code = "ERR-WS-101", message = "The API WebSocket dependency is missing." },
    ['APIWS_AUTH_FAILED'] = { code = "ERR-WS-102", message = "Authentication with the API WebSocket hub failed." },
    ['APIWS_CONFIG_MISSING'] = { code = "ERR-WS-103", message = "The API WebSocket connection could not start because required config values are missing." },
    ['APIWS_CONNECTION_FAILED'] = { code = "ERR-WS-104", message = "The API WebSocket connection could not be established." },
    ['APIWS_RECONNECT_FAILED'] = { code = "ERR-WS-105", message = "The API WebSocket reconnect attempts are failing." },
    ['APIWS_PUSH_EVENT_FAILED'] = { code = "ERR-WS-106", message = "A push event received over API WebSocket could not be processed." },
    ['APIWS_SEND_FAILED'] = { code = "ERR-WS-107", message = "A message could not be sent over the API WebSocket connection." },
    ['PLUGIN_VERSION_FILE_LOAD_FAILED'] = { code = "ERR-PLUG-101", message = "The local plugin version file could not be loaded." },
    ['PLUGIN_VERSION_FILE_PARSE_FAILED'] = { code = "ERR-PLUG-102", message = "The local plugin version file could not be parsed." },
    ['PLUGIN_UPDATER_RESPONSE_INVALID'] = { code = "ERR-PLUG-103", message = "The plugin updater returned an invalid or unusable response." },
    ['PLUGIN_NOT_FOUND'] = { code = "ERR-PLUG-104", message = "The requested plugin or submodule could not be found." },
    ['PLUGIN_MANIFEST_ENTRY_MISSING'] = { code = "ERR-PLUG-105", message = "A submodule was missing from the remote updater manifest." },
    ['PLUGIN_MANIFEST_VERSION_MISSING'] = { code = "ERR-PLUG-106", message = "A submodule entry in the remote updater manifest did not include a version." },
    ['PLUGIN_CONFIG_VERSION_MISSING'] = { code = "ERR-PLUG-107", message = "A submodule config did not define its current version." },
    ['PLUGIN_CONFIG_BACKUP_FAILED'] = { code = "ERR-PLUG-108", message = "The plugin updater could not create a configuration backup file." },
    ['CIV_NO_CHARACTERS_FOUND'] = { code = "ERR-CIV-101", message = "No CAD characters were found for the player." },
    ['CIV_CUSTOM_IDS_DISABLED'] = { code = "ERR-CIV-102", message = "Custom IDs are disabled on this server." },
    ['CIV_REFRESH_DISABLED'] = { code = "ERR-CIV-103", message = "Character refresh is disabled on this server." },
    ['CIV_UNKNOWN_SUBCOMMAND'] = { code = "ERR-CIV-104", message = "The requested civilian ID subcommand is invalid." },
    ['CIV_NO_NEARBY_PLAYERS'] = { code = "ERR-CIV-105", message = "No nearby players were found for the civilian ID action." },
    ['CALL_CREATE_FAILED'] = { code = "ERR-CALL-105", message = "A dispatch call could not be created." },
    ['CALL_UNEXPECTED_RESPONSE'] = { code = "ERR-CALL-106", message = "A call request succeeded partially but returned an unexpected response." },
    ['DISPATCH_CALL_NOT_FOUND'] = { code = "ERR-DISP-101", message = "The requested dispatch call could not be found." },
    ['BODYCAM_UPLOAD_TOKEN_INVALID'] = { code = "ERR-BC-106", message = "The bodycam upload token is invalid or expired." },
    ['BODYCAM_UPLOAD_INIT_FAILED'] = { code = "ERR-BC-107", message = "Bodycam upload initialization failed." },
    ['BODYCAM_UPLOAD_CHUNK_FAILED'] = { code = "ERR-BC-108", message = "A bodycam upload chunk could not be written." },
    ['BODYCAM_UPLOAD_INCOMPLETE'] = { code = "ERR-BC-109", message = "The bodycam upload did not receive all expected chunks." },
    ['BODYCAM_TURN_FAILED'] = { code = "ERR-BC-110", message = "TURN credentials for bodycam streaming could not be retrieved." },
    ['BODYCAM_RECORDING_ACTIVE'] = { code = "ERR-BC-112", message = "A bodycam recording is already active." },
    ['BODYCAM_RECORDING_BLOCKED'] = { code = "ERR-BC-113", message = "Bodycam recording is blocked by the current state or privacy override." },
    ['BODYCAM_RECORDING_INACTIVE'] = { code = "ERR-BC-114", message = "No bodycam recording is currently active." },
    ['BODYCAM_RECORDING_FAILED'] = { code = "ERR-BC-115", message = "Bodycam recording could not be completed." },
    ['BODYCAM_NOT_WORN'] = { code = "ERR-BC-116", message = "A bodycam must be equipped before this action can be used." },
    ['BODYCAM_WATCH_ACTIVE'] = { code = "ERR-BC-117", message = "Bodycam cannot be turned off while it is being watched." },
    ['BODYCAM_SOUND_LEVEL_INVALID'] = { code = "ERR-BC-118", message = "The requested bodycam sound level is invalid." },
    ['BODYCAM_UPLOAD_FAILED'] = { code = "ERR-BC-119", message = "The bodycam recording upload failed." },
    ['ERS_MAPPING_FAILED'] = { code = "ERR-ERS-101", message = "ERS field mapping failed while transforming payload data." },
    ['ERS_PAYLOAD_MALFORMED'] = { code = "ERR-ERS-102", message = "An ERS payload was malformed or missing required fields." },
    ['ERS_COORDS_MISSING'] = { code = "ERR-ERS-103", message = "An ERS event was missing valid coordinates." },
    ['ERS_CALL_ID_INVALID'] = { code = "ERR-ERS-104", message = "ERS attempted to use an invalid saved call ID." },
    ['ERS_RESOURCE_NOT_STARTED'] = { code = "ERR-ERS-105", message = "The required Night ERS resource is not started." },
    ['FRAMEWORK_RESOURCE_MISSING'] = { code = "ERR-FW-101", message = "A required framework resource is not started." },
    ['FRAMEWORK_IDENTITY_MISSING'] = { code = "ERR-FW-102", message = "Framework identity data could not be retrieved for the player." },
    ['LOCATIONS_CONFIG_MISSING'] = { code = "ERR-LOC-101", message = "The locations/livemap configuration file is missing." },
    ['LOCATIONS_CONFIG_INVALID'] = { code = "ERR-LOC-102", message = "The locations/livemap configuration file is invalid." },
    ['LOCATIONS_CLIENT_ERROR'] = { code = "ERR-LOC-103", message = "A client reported a locations update error." },
    ['RECORDPRINTER_UNIT_MISSING'] = { code = "ERR-RP-101", message = "Record printer could not resolve the user to an active CAD unit." },
    ['RECORDPRINTER_DIRECTORY_FAILED'] = { code = "ERR-RP-102", message = "Record printer could not create or resolve its output directory." },
    ['RECORDPRINTER_SAVE_FAILED'] = { code = "ERR-RP-103", message = "Record printer could not save the generated PDF." },
    ['RECORDPRINTER_SHARE_INVALID'] = { code = "ERR-RP-104", message = "Record printer rejected an invalid share request." },
    ['SONRAD_CALLCOMMANDS_MISSING'] = { code = "ERR-SR-101", message = "The Sonrad module requires the callcommands submodule for this action." },
    ['SONRAD_CONFIG_MISSING'] = { code = "ERR-SR-102", message = "Critical Sonrad configuration is missing." },
    ['CADDISPLAY_FRAMEWORK_UNAVAILABLE'] = { code = "ERR-CD-102", message = "CAD display could not access the configured framework export." },
    ['CADDISPLAY_PLACEMENT_INVALID'] = { code = "ERR-CD-103", message = "CAD display placement data could not be loaded or parsed." },
    ['CADDISPLAY_VEHICLE_UNIDENTIFIED'] = { code = "ERR-CD-104", message = "CAD display could not identify the target vehicle." },
    ['KICK_QUEUE_UNAVAILABLE'] = { code = "ERR-KICK-101", message = "The kick module could not queue a CAD unit kick for this player." },
}

local function buildErrorDocUrl(code)
    local resolvedCode = tostring(code or "ERR-CORE-900")
    return ERROR_DOC_BASE_URL .. string.lower(resolvedCode)
end

local function normalize_log_entry(level, err)
    local codeTable = level == "WARNING" and WarningCodes or ErrorCodes
    local entry = codeTable[err] or ErrorCodes[err]
    if type(entry) == "string" then
        return {
            key = err,
            code = err,
            message = entry,
            shortlink = buildErrorDocUrl(err)
        }
    end
    if type(entry) == "table" then
        local resolvedCode = entry.code or err
        return {
            key = err,
            code = resolvedCode,
            message = entry.message or entry.text or "",
            shortlink = entry.shortlink or buildErrorDocUrl(resolvedCode)
        }
    end
    if type(err) == "string" then
        local inlinePrefix, inlineCode, inlineMessage, inlineDocs = err:match("^(.-)((?:ERR|WRN)%-%u+%-%d+)%s*:?%s*(.-)%s+More:%s+(https?://%S+)$")
        if inlineCode ~= nil then
            local resolvedMessage = inlineMessage ~= "" and inlineMessage or "A SonoranCAD log event occurred."
            inlinePrefix = inlinePrefix and inlinePrefix:gsub("%s+$", "") or ""
            if inlinePrefix ~= "" then
                resolvedMessage = ("%s %s"):format(inlinePrefix, resolvedMessage)
            end
            return {
                key = inlineCode,
                code = inlineCode,
                message = resolvedMessage,
                shortlink = inlineDocs or buildErrorDocUrl(inlineCode)
            }
        end

        local urlCode = err:match("/error/((?:ERR|WRN)%-%u+%-%d+)")
        local prefixCode = err:match("(?:ERR|WRN)%-%u+%-%d+")
        local resolvedCode = prefixCode or urlCode
        if resolvedCode ~= nil then
            local trimmedMessage = err
            trimmedMessage = trimmedMessage:gsub("^.-" .. resolvedCode:gsub("%-", "%%-") .. "%s*:?%s*", "")
            trimmedMessage = trimmedMessage:gsub("%s+More:%s+https?://%S+$", "")
            trimmedMessage = trimmedMessage:gsub("^%s+", ""):gsub("%s+$", "")
            if trimmedMessage == "" then
                trimmedMessage = "A SonoranCAD log event occurred."
            end
            return {
                key = resolvedCode,
                code = resolvedCode,
                message = trimmedMessage,
                shortlink = buildErrorDocUrl(resolvedCode)
            }
        end
    end
    if type(err) == "table" then
        local resolvedCode = err.code or err.key or "ERR-CORE-900"
        if err.shortlink == nil then
            err.shortlink = buildErrorDocUrl(resolvedCode)
        end
        return err
    end
    return nil
end

local function normalize_error_entry(err)
    return normalize_log_entry("ERROR", err)
end

local function normalize_warning_entry(err)
    return normalize_log_entry("WARNING", err)
end

function RegisterErrorCode(key, code, message, shortlink)
    ErrorCodes[key] = {
        code = code,
        message = message,
        shortlink = shortlink or buildErrorDocUrl(code or key)
    }
end

function RegisterWarningCode(key, code, message, shortlink)
    WarningCodes[key] = {
        code = code,
        message = message,
        shortlink = shortlink or buildErrorDocUrl(code or key)
    }
end

function getErrorText(err)
    local entry = normalize_error_entry(err)
    return entry and entry.message or nil
end

function getErrorMeta(err)
    return normalize_error_entry(err)
end

function getWarningText(err)
    local entry = normalize_warning_entry(err)
    return entry and entry.message or nil
end

function getWarningMeta(err)
    return normalize_warning_entry(err)
end

local function nextSupportReference()
    SupportRefCounter = (SupportRefCounter % 9999) + 1
    local timestamp = os and os.date("%Y%m%d%H%M%S") or tostring(GetGameTimer and GetGameTimer() or 0)
    return ("SC-%s-%04d"):format(timestamp, SupportRefCounter)
end

local function safeStringFormat(template, ...)
    if select("#", ...) == 0 then
        return template
    end
    local ok, formatted = pcall(string.format, template, ...)
    if ok then
        return formatted
    end
    return template
end

local function sanitizeErrorDetail(value)
    if value == nil then
        return nil
    end
    local text = tostring(value):gsub("\r", " "):gsub("\n", " ")
    text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    if #text > 400 then
        text = text:sub(1, 397) .. "..."
    end
    return text
end

function SanitizeErrorDetail(value)
    return sanitizeErrorDetail(value)
end

local function buildErrorReport(level, err, msg, ...)
    local fallbackKey = level == "WARNING" and "UNHANDLED_WARNING" or "UNHANDLED_SERVER_ERROR"
    local entry = normalize_log_entry(level, err)
    local rawDetail = nil

    if entry == nil and type(err) == "string" and msg == nil then
        rawDetail = err
        entry = normalize_log_entry(level, fallbackKey)
    elseif entry == nil then
        rawDetail = tostring(err)
        entry = normalize_log_entry(level, fallbackKey)
    end

    local template = msg or (entry and entry.message) or tostring(err)
    local formatted = safeStringFormat(template, ...)
    local sanitizedDetail = sanitizeErrorDetail(rawDetail)
    local supportRef = nextSupportReference()
    local userMessage = ("%s Support ref: %s Docs: %s"):format(formatted, supportRef, entry.shortlink)
    local logMessage = ("%s: %s Support ref: %s Docs: %s"):format(entry.code, formatted, supportRef, entry.shortlink)
    if sanitizedDetail ~= nil and sanitizedDetail ~= formatted then
        logMessage = ("%s Details: %s"):format(logMessage, sanitizedDetail)
    end

    return {
        level = level,
        entry = entry,
        formatted = formatted,
        sanitizedDetail = sanitizedDetail,
        supportRef = supportRef,
        userMessage = userMessage,
        logMessage = logMessage
    }
end

local function appendSupportError(report)
    if not IsDuplicityVersion() or type(report) ~= "table" or type(report.entry) ~= "table" then
        return
    end

    local sourceName = "SonoranCAD"
    local info = debug.getinfo(4, 'S')
    if info ~= nil and type(info.source) == "string" and info.source:find("@@sonorancad") then
        sourceName = info.source:gsub("@@sonorancad/", "")
        if info.linedefined ~= nil then
            sourceName = ("%s:%s"):format(sourceName, tostring(info.linedefined))
        end
    end

    table.insert(SupportErrorBuffer, 1, {
        timestamp = os and os.date("!%Y-%m-%dT%H:%M:%SZ") or tostring(GetGameTimer and GetGameTimer() or 0),
        level = report.level,
        key = report.entry.key,
        code = report.entry.code,
        message = report.formatted,
        supportRef = report.supportRef,
        docs = report.entry.shortlink,
        details = report.sanitizedDetail,
        source = sourceName
    })

    if #SupportErrorBuffer > 250 then
        table.remove(SupportErrorBuffer)
    end
end

function formatErrorMessage(err, msg, ...)
    local entry = normalize_error_entry(err)
    local template = msg or (entry and entry.message) or tostring(err)
    local formatted = safeStringFormat(template, ...)
    if entry == nil then
        return formatted
    end
    return ("%s: %s More: %s"):format(entry.code, formatted, entry.shortlink)
end

function formatWarningMessage(err, msg, ...)
    local entry = normalize_warning_entry(err)
    local template = msg or (entry and entry.message) or tostring(err)
    local formatted = safeStringFormat(template, ...)
    if entry == nil then
        return formatted
    end
    return ("%s: %s More: %s"):format(entry.code, formatted, entry.shortlink)
end

function BuildSupportErrorMessage(err, msg, ...)
    local report = buildErrorReport("ERROR", err, msg, ...)
    return ("%s: %s"):format(report.entry.code, report.userMessage), report
end

function sendClientError(target, err, msg, ...)
    local report = buildErrorReport("ERROR", err, msg, ...)
    appendSupportError(report)
    local notification = {
        title = "Error",
        message = ("%s: %s"):format(report.entry.code, report.userMessage),
        type = "error",
        chatPrefix = "^0[ ^1Error ^0] "
    }
    if type(NotifyPlayer) == "function" then
        NotifyPlayer(target, notification)
    else
        TriggerClientEvent("chat:addMessage", target, {
            args = {notification.chatPrefix, notification.message}
        })
    end
    sendConsole("ERROR", "^1", report.logMessage)
end

function showClientError(err, msg, ...)
    local report = buildErrorReport("ERROR", err, msg, ...)
    if IsDuplicityVersion() then
        return sendClientError(-1, err, msg, ...)
    end
    local notification = {
        title = "Error",
        message = ("%s: %s"):format(report.entry.code, report.userMessage),
        type = "error",
        chatPrefix = "^0[ ^1Error ^0] "
    }
    if type(NotifyClient) == "function" then
        NotifyClient(notification)
    else
        TriggerEvent("chat:addMessage", {
            args = {notification.chatPrefix, notification.message}
        })
    end
    sendConsole("ERROR", "^1", report.logMessage)
end

local function LocalTime()
	local _, _, _, h, m, s = GetLocalTime()
	return '' .. h .. ':' .. m .. ':' .. s
end

sendConsole = function(level, color, message)
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

function getSupportErrorBuffer()
    return SupportErrorBuffer
end

function debugLog(message)
    if Config == nil then
        return
    end
    sendConsole("DEBUG", "^7", message)
end

--[[
    This function is depreciated and will be removed in a future version.
    Please use the debugLog function instead.
    Reason: This function prevents correct information from being sent to the console.
    It is recommended to use the debugLog function instead.
]]
function debugPrint(message)
    warnLog("DEPRECATED_DEBUGPRINT", "The function debugPrint is deprecated and will be removed in a future version. Please use the debugLog function instead.")
    debugLog(message)
end

function logError(err, msg, ...)
    local report = buildErrorReport("ERROR", err, msg, ...)
    appendSupportError(report)
    sendConsole("ERROR", "^1", report.logMessage)
end

function errorLog(err, msg, ...)
    local report
    if msg ~= nil or normalize_error_entry(err) ~= nil then
        report = buildErrorReport("ERROR", err, msg, ...)
    else
        report = buildErrorReport("ERROR", err)
    end
    appendSupportError(report)
    sendConsole("ERROR", "^1", report.logMessage)
end

function warnLog(err, msg, ...)
    local report
    if msg ~= nil or normalize_warning_entry(err) ~= nil or normalize_error_entry(err) ~= nil then
        report = buildErrorReport("WARNING", err, msg, ...)
    else
        report = buildErrorReport("WARNING", err)
    end
    appendSupportError(report)
    sendConsole("WARNING", "^3", report.logMessage)
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
