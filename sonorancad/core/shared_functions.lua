function shallowcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function SafeJsonDecode(raw, context, defaultValue)
    if type(raw) ~= "string" or raw == "" then
        return defaultValue, "empty"
    end

    local ok, decoded = pcall(json.decode, raw)
    if ok then
        return decoded, nil
    end

    if context ~= nil then
        warnLog("JSON_DECODE_FAILED", ("%s JSON decode failed: %s"):format(tostring(context), tostring(decoded)))
    end
    return defaultValue, decoded
end

function SafeJsonEncode(value, context, defaultValue)
    local ok, encoded = pcall(json.encode, value)
    if ok then
        return encoded, nil
    end

    if context ~= nil then
        warnLog("JSON_ENCODE_FAILED", ("%s JSON encode failed: %s"):format(tostring(context), tostring(encoded)))
    end
    return defaultValue, encoded
end

function stringsplit(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t={} ; i=1
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        t[i] = str
        i = i + 1
    end
    return t
end

-- Helper function to determine index of given identifier
function findIndex(identifier)
    for i,loc in ipairs(LocationCache) do
        if loc.communityUserId == identifier then
            return i
        end
    end
end


function GetIdentifiers(player)
    local ids = {}
    for _, id in ipairs(GetPlayerIdentifiers(player)) do
        local split = stringsplit(id, ":")
        ids[split[1]] = split[2]
    end
    --debugLog("Returning "..json.encode(ids))
    return ids
end

function isPluginLoaded(pluginName)
    local settings = Config and Config.plugins and Config.plugins[pluginName]
    if settings then return settings.enabled == true end
    return Config ~= nil and Config.pluginStates ~= nil and Config.pluginStates[pluginName] == true
end

exports('isPluginLoaded', isPluginLoaded)

-- Required top-level settings from the currently shipped plugins. Missing settings
-- disable that plugin; they never cause local templates to be merged into CAD data.
local cadPluginFields = {
    bodycam = "autoEnableWithLights:boolean autoEnableWithWeapons:boolean beepFrequency:number beepRange:number beepType:string clothing:table command:string defaultKeybind:string enableAnimation:boolean enableBeeps:boolean enableOverlay:boolean enablePadShake:boolean forceOffAce:string overlayLocation:string peerStream:table recording:table requireUnitDuty:boolean weapons:table",
    caddisplay = "acePerms:table allowlistedCars:table builtinScreens:table commands:table custom:table framework:table general:table interactControl:number interactKey:string interactRange:number interaction:table lang:table permissionMode:string requestAcceptKey:string requestDenyKey:string worldDisplays:table",
    callcommands = "addPanicCall:boolean callTypes:table enablePanic:boolean useCallLocation:boolean usePositionForMetadata:boolean",
    calltemplates = "callTypeDirectory:string commands:table defaultOrigin:number defaultPriority:number defaultStatus:number reloadTemplatesOnEachUse:boolean",
    civintegration = "allowCustomIds:boolean allowPurge:boolean cacheTime:number commandName:string enableCommands:boolean enableIDCardUI:boolean showNearbyDistance:number",
    civreg = "autofillFieldIds:table commandName:string databaseSync:table language:table maxSelfieBytes:number templateCacheSeconds:number templateId:number",
    dispatchnotify = "addNoteSubcommand:string addPlateSubcommand:string callTitle:string civilCallType:string commandName:string dispatchDisablesSelfResponse:boolean dispatchDisablesUnitNotify:boolean dotCallType:string emergencyCallType:string enableAddNote:boolean enableAddPlate:boolean enableCallerNotify:boolean enableUnitNotify:boolean enableUnitNotifyToggleCommand:boolean enableUnitResponse:boolean esxJobsAllowed:table gpsToggleSubcommand:string incomingCallMessage:string incomingCallMessageNoResponse:string noteMessage:string notifyMessage:string onSceneHandler:boolean onSceneIndex:number respondSubcommandName:string sendNotesToUnits:boolean unitDutyMethod:string unitNotifyToggleAce:string unitNotifyToggleSubcommand:string unitStatusAttachedMessage:string unitStatusDetachedMessage:string waypointFallbackEnabled:boolean waypointType:string",
    ersintegration = "DOBFormat:string autoAddCall:boolean callCodes:table callPriority:number clearRecordsAfter:number create911Call:boolean createEmergencyCall:boolean customRecords:table",
    forcereg = "allowPopupCloseWhenUnlinked:boolean autoOpenLinkPopup:boolean captiveMessage:string captiveOption:string instructionalMessage:string linkButtonText:string linkCommand:string linkPollIntervalMs:number linkPopupTitleText:string nagDrawTextLocation:string requireLink:boolean verifyMessage:string whitelist:table",
    frameworksupport = "fineNotify:boolean fineableForms:table identityType:string issueFines:boolean legacyESX:boolean qbFineMessage:string qbManagementAccountNames:table qbNotifyFinedPlayer:boolean usePrefix:boolean usingQBCore:boolean usingQBManagement:boolean",
    localcallers = "callCoolDown:number callTimers:table callTypes:table clearRecordsAfter:number clothingConfig:table language:table localRunTime:number weaponConfig:table whitelistZones:table",
    locations = "clientCheckTime:number customStreetNames:table prefixPostal:boolean",
    lookups = "autoLookupEnabled:boolean maxCacheTime:number stalePurgeTimer:number",
    postals = "customPostalCodesFile:string mode:string nearestPostalEvent:string nearestPostalResourceName:string sendTimer:number shouldSendPostalData:boolean",
    recordPrinter = "acceptShareCommand:string clearPrintQueueCommand:string commandPrefix:string frameworks:table interactRadius:number maxPrintsPerQueue:number printCommand:string printQueueCommand:string printerCoords:table printerObjects:table recordPurgeDays:number shareCommand:string translations:table vehicleConfig:table",
    sonrad = "addPanicCall:boolean syncRadioName:table",
    unitstatus = "enableAceCheck:boolean setStatusCommand:string statusCodes:table",
    vehreg = "customData:table defaultRegExpire:string defaultRegStatus:string language:table recordData:table reigsterCommand:string",
    wraithv2 = "alertNoRegistration:boolean customFields:table expiresUid:string flagOnStatuses:table notificationTimers:table statusUid:string useExpires:boolean useMiddleInitial:boolean vehTypeFilter:table",
}

-- Evaluate callback source from JSON in one plugin environment, so helpers retain
-- access to config and to one another. Object keys are otherwise left untouched.
local function decodeCadSettings(value, env)
    if type(value) == 'string' and (value:match('^%s*function%s*%(') or value:match('^%s*function%s+[%w_]+%s*%(')) then
        local source = value:gsub('^(%s*function)%s+[%w_]+%s*%(', '%1(', 1)
        local chunk = assert(load('return ' .. source, '@cad-callback', 't', env))
        return chunk()
    elseif type(value) == 'table' then
        local copy = {}
        for key, item in pairs(value) do copy[key] = decodeCadSettings(item, env) end
        return copy
    end
    return value
end

-- Never read a local file here: CAD and its cache use this parser on both sides.
function ParseCadPluginConfiguration(pluginName, value, migrating)
    local config = value
    if type(value) == 'string' then
        local registered
        local env = {Config = {RegisterPluginConfig = function(_, settings) registered = settings end}}
        setmetatable(env, {__index = _G})
        local chunk = load(value .. '\nreturn config', '@cad-config/' .. pluginName, 't', env)
        if not chunk then return nil, 'Invalid Lua configuration for ' .. pluginName end
        local ok, result = pcall(chunk)
        if not ok then return nil, 'Unable to evaluate configuration for ' .. pluginName end
        config = result or registered
        if type(config) == 'table' and env.unitDutyCustom then
            config.unitDutyCustom = env.unitDutyCustom
        end
    end
    if type(value) == 'table' then
        local env = setmetatable({}, {__index = _G})
        local ok, settings = pcall(decodeCadSettings, value, env)
        if not ok then return nil, 'Invalid callback source for ' .. pluginName end
        config = settings
        env.config = config
        for name, setting in pairs(config) do
            if type(setting) == 'function' then env[name] = setting end
        end
        -- JSON carries coordinates as objects and hashed dictionary keys as strings.
        if pluginName == 'localcallers' then
            if config.whitelistZones ~= nil and type(config.whitelistZones) ~= 'table' then return nil, 'Invalid whitelist zones' end
            for _, zone in pairs(config.whitelistZones or {}) do
                if type(zone) ~= 'table' then return nil, 'Invalid whitelist zone' end
                if type(zone.center) == 'table' then
                    local c = zone.center
                    if type(c.x) ~= 'number' or type(c.y) ~= 'number' or type(c.z) ~= 'number' then return nil, 'Invalid whitelist zone coordinates' end
                    zone.center = vector3(c.x, c.y, c.z)
                end
            end
            if config.weaponConfig ~= nil and type(config.weaponConfig) ~= 'table' then return nil, 'Invalid weapon settings' end
            local responses = config.weaponConfig and config.weaponConfig.weaponResponses
            if type(responses) == 'table' then
                local normalized = {}
                for key, response in pairs(responses) do
                    local hash = tonumber(key)
                    if not hash and type(key) == 'string' and type(GetHashKey) == 'function' then hash = GetHashKey(key) end
                    normalized[hash or key] = response
                end
                config.weaponConfig.weaponResponses = normalized
            end
        end
    end
    if type(config) ~= 'table' or (config.pluginName ~= nil and config.pluginName ~= pluginName) or
        (config.enabled ~= nil and type(config.enabled) ~= 'boolean') then
        return nil, 'Invalid settings for ' .. pluginName
    end
    -- Empty/partial entries must not start a plugin using accidental defaults.
    if config.enabled ~= false and (config.pluginName ~= pluginName or
        type(config.configVersion or config.pluginVersion) ~= 'string') then
        return nil, 'Missing plugin metadata for ' .. pluginName
    end
    if config.enabled ~= false then
        -- The printer indexes this table immediately, including in older files.
        if pluginName == 'recordPrinter' and type(config.frameworks) ~= 'table' then
            return nil, 'Missing or invalid recordPrinter.frameworks'
        end
        for key, expected in (cadPluginFields[pluginName] or ''):gmatch('([%w_]+):(%w+)') do
            -- Older local files can omit options added later. CAD supplies their
            -- catalog defaults after migration; provided values still keep their types.
            if (config[key] ~= nil or not migrating) and type(config[key]) ~= expected then
                return nil, 'Missing or invalid ' .. pluginName .. '.' .. key
            end
        end
    end
    if config.enabled == nil then config.enabled = true end
    return config
end

function PerformHttpRequestS(url, cb, method, data, headers)
    if not data then
        data = ""
    end
    if not headers then
        headers = {["X-User-Agent"] = "SonoranCAD"}
    end
    PerformHttpRequest(url, cb, method, data, headers)
end

function has_value(tab, val)
    if tab == nil then
        debugLog("nil passed to has_value, ignore")
        return false
    end
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

function getServerVersion()
    local s = GetConvar("version", "")
    local v = s:find("v1.0.0.")
    local e = string.gsub(s:sub(v),"v1.0.0.","")
    local i = e:sub(1, string.len(e) - e:find(" "))
    return i
end

function compareVersions(version1, version2)
    local v1, v2, v3 = version1:match("(%d+)%.(%d*)%.?(%d*)")
    local r1, r2, r3 = version2:match("(%d+)%.(%d*)%.?(%d*)")

    -- Convert to numbers and default to 0 for minor and patch if missing
    v1, v2, v3 = tonumber(v1) or 0, tonumber(v2) or 0, tonumber(v3) or 0
    r1, r2, r3 = tonumber(r1) or 0, tonumber(r2) or 0, tonumber(r3) or 0

    -- Calculate parsed versions with proper weights
    local parsedVersion1 = v1 * 10000 + v2 * 100 + v3
    local parsedVersion2 = r1 * 10000 + r2 * 100 + r3

    -- Create debug log table
    local tbl = {
        result = (parsedVersion2 < parsedVersion1),
        parsedVersion1 = parsedVersion1,
        parsedVersion2 = parsedVersion2,
        version1 = version1,
        version2 = version2
    }
    debugLog(json.encode(tbl))

    return tbl
end

local NotificationSystemPriority = {"ox_lib", "lation_ui", "pnotify", "chat"}
local ValidNotificationSystems = {
    auto = true,
    ox_lib = true,
    lation_ui = true,
    pnotify = true,
    chat = true
}

local function normalizeNotificationSystem(value)
    if type(value) ~= "string" then
        return nil
    end
    local normalized = value:lower():gsub("%s+", "")
    if normalized == "pnotify" then
        return "pnotify"
    end
    if normalized == "oxlib" then
        return "ox_lib"
    end
    return normalized
end

local function normalizeNotificationType(value)
    local normalized = type(value) == "string" and value:lower() or "info"
    if normalized == "inform" then
        normalized = "info"
    elseif normalized == "warn" then
        normalized = "warning"
    end
    if normalized ~= "success" and normalized ~= "error" and normalized ~= "warning" then
        normalized = "info"
    end
    return normalized
end

local function stripHtmlForText(message)
    local text = tostring(message or "")
    text = text:gsub("<br%s*/?>", "\n")
    text = text:gsub("</p>", "\n")
    text = text:gsub("</li>", "\n")
    text = text:gsub("<li>", "- ")
    text = text:gsub("<.->", "")
    text = text:gsub("&nbsp;", " ")
    text = text:gsub("&amp;", "&")
    text = text:gsub("&lt;", "<")
    text = text:gsub("&gt;", ">")
    return text
end

local function getConfiguredNotificationSystem()
    local configured = normalizeNotificationSystem(Config and Config.notificationSystem or nil)
    if configured == nil or not ValidNotificationSystems[configured] then
        return "auto"
    end
    return configured
end

function ResolveNotificationSystem(preferredSystem)
    local configured = normalizeNotificationSystem(preferredSystem) or getConfiguredNotificationSystem()
    if configured ~= "auto" then
        return configured
    end

    for _, resourceName in ipairs(NotificationSystemPriority) do
        local stateName = resourceName == "pnotify" and "pNotify" or resourceName
        if resourceName == "chat" or GetResourceState(stateName) == "started" then
            return resourceName
        end
    end

    return "chat"
end

local function getChatPrefix(notification)
    if type(notification.chatPrefix) == "string" and notification.chatPrefix ~= "" then
        return notification.chatPrefix
    end

    local prefixColor = "5"
    local notificationType = normalizeNotificationType(notification.type)
    if notificationType == "success" then
        prefixColor = "2"
    elseif notificationType == "warning" then
        prefixColor = "3"
    elseif notificationType == "error" then
        prefixColor = "1"
    end

    local title = tostring(notification.title or "SonoranCAD")
    return ("^0[ ^%s%s ^0] "):format(prefixColor, title)
end

local function buildNotificationPayload(input)
    if type(input) == "table" then
        return input
    end
    return {message = tostring(input or "")}
end

function ApplyPluginNotificationOverrides(pluginConfig, input)
    local notification = buildNotificationPayload(input)
    if type(pluginConfig) ~= "table" or notification.system ~= nil then
        return notification
    end

    local configured = nil
    if pluginConfig.notificationOverride ~= nil then
        local override = normalizeNotificationSystem(pluginConfig.notificationOverride)
        if override ~= nil and override ~= "auto" and override ~= "none" and ValidNotificationSystems[override] then
            configured = override
        end
    elseif pluginConfig.notificationSystem ~= nil then
        local legacy = normalizeNotificationSystem(pluginConfig.notificationSystem)
        if legacy ~= nil and ValidNotificationSystems[legacy] then
            configured = legacy
        end
    end

    if configured ~= nil then
        notification.system = configured
    end

    return notification
end

function NotifyClient(input)
    local notification = buildNotificationPayload(input)
    local notificationType = normalizeNotificationType(notification.type)
    local title = tostring(notification.title or "SonoranCAD")
    local duration = tonumber(notification.duration or notification.timeout) or 10000
    local richMessage = notification.htmlMessage or notification.message or notification.description or ""
    local plainMessage = notification.plainMessage or stripHtmlForText(notification.message or notification.description or richMessage)
    local chatMessage = notification.chatMessage or plainMessage
    local system = ResolveNotificationSystem(notification.system)

    if system == "ox_lib" and GetResourceState("ox_lib") == "started" then
        TriggerEvent("ox_lib:notify", {
            title = title,
            description = plainMessage,
            duration = duration,
            type = notificationType
        })
        return
    end

    if system == "lation_ui" and GetResourceState("lation_ui") == "started" then
        TriggerEvent("lation_ui:notify", {
            title = title,
            message = plainMessage,
            duration = duration,
            type = notificationType
        })
        return
    end

    if system == "pnotify" and GetResourceState("pNotify") == "started" then
        TriggerEvent("pNotify:SendNotification", {
            text = richMessage ~= "" and richMessage or plainMessage,
            type = notificationType,
            layout = notification.layout or "bottomcenter",
            timeout = duration,
            queue = notification.queue
        })
        return
    end

    TriggerEvent("chat:addMessage", {
        color = notification.color,
        multiline = true,
        args = {getChatPrefix(notification), chatMessage}
    })
end

RegisterNetEvent("SonoranCAD::core:Notify")
AddEventHandler("SonoranCAD::core:Notify", function(notification)
    NotifyClient(notification)
end)

if IsDuplicityVersion() then
    function NotifyPlayer(target, input)
        TriggerClientEvent("SonoranCAD::core:Notify", target, buildNotificationPayload(input))
    end
end

function isCallbackValid(value)
    if type(value) == "function" then return true end
    if type(value) == "table" and rawget(value, "__cfx_functionReference") then return true end

    return false
end
