Config = {
    communityID = nil,
    apiKey = nil,
    apiUrl = nil,
    postTime = nil,
    serverId = nil,
    linkCommand = "link",
    requireLink = true,
    autoOpenLinkPopup = true,
    freezeUntilLinked = false,
    allowPopupCloseWhenUnlinked = true,
    linkPollIntervalMs = 10000,
    linkPopupTitleText = "Press the button to link your CAD account to this FiveM server",
    linkButtonText = "Link CAD",
    primaryIdentifier = nil,
    apiSendEnabled = nil,
    debugMode = nil,
    notificationSystem = "auto",
    updateBranch = nil,
    enableCanary = false,
    latestVersion = '',
    apiVersion = -1,
    plugins = {}
}

updaterIgnore = {}

Config.RegisterPluginConfig = function(pluginName, configs)
    Config.plugins[pluginName] = {}
    for k, v in pairs(configs) do
        Config.plugins[pluginName][k] = v
        -- debugLog(("plugin %s set %s = %s"):format(pluginName, k, v))
    end
    table.insert(Plugins, pluginName)
end

local function CopyFile(old_path, new_path)
    local old_file = io.open(old_path, 'rb')
    local new_file = io.open(new_path, 'wb')
    if not old_file then
        warnLog("UNHANDLED_WARNING", 'Failed to open source file: ' .. old_path ..
                    ' - please check your folder permissions or rename file manually.')
        return false
    end
    if not new_file then
        warnLog("UNHANDLED_WARNING", 'Failed to create target file: ' .. new_path ..
                    ' - please check your folder permissions or rename file manually.')
        old_file:close()
        return false
    end

    local old_file_sz, new_file_sz
    while true do
        local block = old_file:read(2 ^ 13)
        if not block then
            old_file_sz = old_file:seek('end')
            break
        end
        new_file:write(block)
    end
    old_file:close()
    new_file_sz = new_file:seek('end')
    new_file:close()
    if new_file_sz ~= old_file_sz then
        print('File copy size mismatch')
        return false
    end
    return true
end

exports('GetPluginConfig', function(pluginName)
    return Config.GetPluginConfig(pluginName)
end)

Config.GetPluginConfig = function(pluginName)
    while not Config.remoteReady and not Config.critError do Wait(50) end
    if Config.critError then return {enabled = false, disableReason = 'Startup aborted'} end
    return Config.plugins[pluginName] or {enabled = false, disableReason = 'Unknown module'}
end

Config.LoadPlugin = function(pluginName, cb)
    while not Config.remoteReady or Config.apiVersion == -1 do
        if Config.critError then return cb({enabled = false, disableReason = 'Startup aborted'}) end
        Wait(50)
    end
    return cb(Config.GetPluginConfig(pluginName))
end

local updateIgnorePath = GetResourcePath(GetCurrentResourceName()) .. '/configuration/updateIgnore.json'
local defaultIgnorePath = GetResourcePath(GetCurrentResourceName()) .. '/configuration/updateIgnore.CHANGEME.json'

local updateIgnoreContent = LoadResourceFile(GetCurrentResourceName(), 'configuration/updateIgnore.json')

if not updateIgnoreContent then
    infoLog('No updateIgnore.json found... attempting to copy default template (updateIgnore.CHANGEME.json)')

    if not CopyFile(defaultIgnorePath, updateIgnorePath) then
        warnLog("UNHANDLED_WARNING", 'Failed to copy updateIgnore.CHANGEME.json to updateIgnore.json')
        warnLog("UNHANDLED_WARNING", 'Using default ignore list. Please manually copy updateIgnore.CHANGEME.json to updateIgnore.json to suppress this warning.')
        updateIgnoreContent = LoadResourceFile(GetCurrentResourceName(), 'configuration/updateIgnore.CHANGEME.json')
    else
        updateIgnoreContent = LoadResourceFile(GetCurrentResourceName(), 'configuration/updateIgnore.json')
    end
end
if updateIgnoreContent then
    local parsed = SafeJsonDecode(updateIgnoreContent, "updateIgnore", nil)
    if parsed and type(parsed) == "table" then
        updaterIgnore = parsed
    else
        warnLog("UNHANDLED_WARNING", 'updateIgnore file exists but is not valid JSON. Defaulting to empty list.')
    end
else
    warnLog("UNHANDLED_WARNING", 'Unable to load any updateIgnore content.')
end


local conf = LoadResourceFile(GetCurrentResourceName(),
                              'configuration/config.json')
if conf == nil then
    logError('CONFIG_ERROR',
        'Unable to load configuration file. Ensure the file is named correctly (config.json). Check for extra extensions (like config.json.json).')
    Config.critError = true
    Config.apiSendEnabled = false
    return
end
local parsedConfigOk, parsedConfig = pcall(json.decode, conf)
if not parsedConfigOk then
    parsedConfig = nil
end
if parsedConfig == nil then
    logError('CONFIG_ERROR',
        'Unable to parse configuration file. Ensure it is valid JSON.')
    Config.critError = true
    Config.apiSendEnabled = false
    return
end
local function bootstrapValue(key)
    local fileValue = parsedConfig[key]
    local convar = GetConvar('sonoran_' .. key, 'NONE')
    if key == 'apiKey' and convar == 'protection_initialized' then return fileValue end
    if convar ~= 'NONE' and convar ~= 'protection_initialized' then return convar end
    return fileValue
end

for _, k in ipairs({'communityID', 'apiKey', 'serverId', 'mode'}) do
    Config[k] = bootstrapValue(k)
end
Config.serverId = tonumber(Config.serverId) or 1
Config.mode = Config.mode or 'production'
if type(Config.apiKey) ~= 'string' or Config.apiKey == '' or type(Config.communityID) ~= 'string' or Config.communityID == '' then
    Config.critError = true
    errorLog('CONFIG_ERROR', 'A community ID and API key are required in configuration/config.json.')
    return
end
SetConvar('sonoran_apiKey', Config.apiKey)
SetConvar('sonoran_communityID', Config.communityID)
SetConvar('sonoran_serverId', tostring(Config.serverId))
SetConvar('sonoran_mode', Config.mode)
local localConfiguration = LoadLocalFiveMConfiguration()
AugmentLocalFiveMConfigurationInventory(localConfiguration)
for _, migrationError in ipairs(localConfiguration.errors or {}) do
    warnLog('UNHANDLED_WARNING', 'Local configuration migration scan: ' .. tostring(migrationError))
end
LoadRemoteFiveMConfiguration(localConfiguration)

local validNotificationSystems = {
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
    if normalized == "oxlib" then
        normalized = "ox_lib"
    elseif normalized == "pnotify" then
        normalized = "pnotify"
    end
    return normalized
end

local normalizedNotificationSystem = normalizeNotificationSystem(Config.notificationSystem)
if normalizedNotificationSystem == nil or not validNotificationSystems[normalizedNotificationSystem] then
    if Config.notificationSystem ~= nil then
        warnLog("UNHANDLED_WARNING", ("Invalid notificationSystem value \"%s\" in config.json. Defaulting to auto."):format(tostring(Config.notificationSystem)))
    end
    normalizedNotificationSystem = "auto"
end
Config.notificationSystem = normalizedNotificationSystem

if type(Config.linkCommand) ~= "string" or Config.linkCommand == "" then
    Config.linkCommand = "link"
end

if type(Config.requireLink) ~= "boolean" then
    Config.requireLink = true
end

if type(Config.autoOpenLinkPopup) ~= "boolean" then
    Config.autoOpenLinkPopup = true
end

if type(Config.freezeUntilLinked) ~= "boolean" then
    Config.freezeUntilLinked = false
end

if type(Config.allowPopupCloseWhenUnlinked) ~= "boolean" then
    Config.allowPopupCloseWhenUnlinked = true
end

Config.linkPollIntervalMs = tonumber(Config.linkPollIntervalMs) or 10000
if Config.linkPollIntervalMs < 1000 then
    Config.linkPollIntervalMs = 1000
end

if type(Config.linkPopupTitleText) ~= "string" or Config.linkPopupTitleText == "" then
    Config.linkPopupTitleText = "Press the button to link your CAD account to this FiveM server"
end

if type(Config.linkButtonText) ~= "string" or Config.linkButtonText == "" then
    Config.linkButtonText = "Link CAD"
end

local function resolve_forcereg_link_settings()
    local pluginConfig = Config.plugins.forcereg
    if pluginConfig == nil then
        pluginConfig = Config.GetPluginConfig('forcereg')
    end
    if type(pluginConfig) ~= "table" or pluginConfig.enabled ~= true then
        return
    end

    if type(pluginConfig.requireLink) == "boolean" then
        Config.requireLink = pluginConfig.requireLink
    end

    if type(pluginConfig.autoOpenLinkPopup) == "boolean" then
        Config.autoOpenLinkPopup = pluginConfig.autoOpenLinkPopup
    end

    if type(pluginConfig.linkCommand) == "string" and pluginConfig.linkCommand ~= "" then
        Config.linkCommand = pluginConfig.linkCommand
    end

    if tonumber(pluginConfig.linkPollIntervalMs) ~= nil then
        Config.linkPollIntervalMs = tonumber(pluginConfig.linkPollIntervalMs)
    end

    if type(pluginConfig.linkPopupTitleText) == "string" and pluginConfig.linkPopupTitleText ~= "" then
        Config.linkPopupTitleText = pluginConfig.linkPopupTitleText
    end

    if type(pluginConfig.linkButtonText) == "string" and pluginConfig.linkButtonText ~= "" then
        Config.linkButtonText = pluginConfig.linkButtonText
    end

    local captiveOption = type(pluginConfig.captiveOption) == "string" and pluginConfig.captiveOption:lower() or "nag"
    if captiveOption == "freeze" then
        Config.freezeUntilLinked = true
        Config.allowPopupCloseWhenUnlinked = false
    else
        Config.freezeUntilLinked = false
        if type(pluginConfig.allowPopupCloseWhenUnlinked) == "boolean" then
            Config.allowPopupCloseWhenUnlinked = pluginConfig.allowPopupCloseWhenUnlinked
        else
            Config.allowPopupCloseWhenUnlinked = true
        end
    end
end

resolve_forcereg_link_settings()

Config.linkPollIntervalMs = tonumber(Config.linkPollIntervalMs) or 10000
if Config.linkPollIntervalMs < 1000 then
    Config.linkPollIntervalMs = 1000
end

local function applyFrameworkConvar(key, value)
    if key == "apiKey" or value == nil then
        return
    end
    SetConvar('sonoran_' .. key, tostring(value))
    if GetConvar('sonoran_' .. key .. '_setter', 'NONE') == 'NONE' then
        SetConvar('sonoran_' .. key .. '_setter', 'framework')
    end
end

applyFrameworkConvar('linkCommand', Config.linkCommand)
applyFrameworkConvar('requireLink', Config.requireLink)
applyFrameworkConvar('autoOpenLinkPopup', Config.autoOpenLinkPopup)
applyFrameworkConvar('freezeUntilLinked', Config.freezeUntilLinked)
applyFrameworkConvar('allowPopupCloseWhenUnlinked', Config.allowPopupCloseWhenUnlinked)
applyFrameworkConvar('linkPollIntervalMs', Config.linkPollIntervalMs)
applyFrameworkConvar('linkPopupTitleText', Config.linkPopupTitleText)
applyFrameworkConvar('linkButtonText', Config.linkButtonText)
applyFrameworkConvar('notificationSystem', Config.notificationSystem)

if Config.updateBranch == nil then Config.updateBranch = 'master' end

RegisterNetEvent('SonoranCAD::core:sendClientConfig')
AddEventHandler('SonoranCAD::core:sendClientConfig', function()
    if not Config.remoteReady or Config.apiVersion == -1 then return end
    local config = {
        plugins = Config.remotePluginValues,
        communityID = Config.communityID,
        postTime = Config.postTime,
        serverId = tonumber(Config.serverId),
        linkCommand = Config.linkCommand,
        requireLink = Config.requireLink,
        autoOpenLinkPopup = Config.autoOpenLinkPopup,
        freezeUntilLinked = Config.freezeUntilLinked,
        allowPopupCloseWhenUnlinked = Config.allowPopupCloseWhenUnlinked,
        linkPollIntervalMs = Config.linkPollIntervalMs,
        linkPopupTitleText = Config.linkPopupTitleText,
        linkButtonText = Config.linkButtonText,
        primaryIdentifier = Config.primaryIdentifier,
        apiSendEnabled = Config.apiSendEnabled,
        debugMode = Config.debugMode,
        notificationSystem = Config.notificationSystem,
        devHiddenSwitch = Config.devHiddenSwitch,
        statusLabels = Config.statusLabels,
        apiVersion = Config.apiVersion,
        mode = Config.mode
    }
    TriggerClientEvent('SonoranCAD::core:recvClientConfig', source, config)
end)

CreateThread(function()
    Wait(2000) -- wait for server to settle
    if Config.critError then return end
    local serverId = tonumber(Config.serverId)
    while Config.apiVersion == -1 do Wait(10) end
    if not Config.apiSendEnabled then
        errorLog("CAD_API_DISABLED", 'Config.apiSendEnabled disabled via convar or config, skipping server registration. Check your config if this is unintentional.')
        return
    end
    local serversResponse = CadApiGetServers()
    if not serversResponse.success then
        CadApiLogFailure('GET_SERVERS', serversResponse, {})
        return
    end
    local info = serversResponse.data
    for k, v in pairs(info.servers or {}) do
        if tostring(v.id) == tostring(serverId) then
            ServerInfo = v
            break
        end
    end
    local needSetup = false
    local serverObj = {}
    if ServerInfo == nil then
        needSetup = true
        serverObj = {
            id = serverId,
            name = 'Server ' .. serverId,
            description = 'Server ' .. serverId,
            signal = '',
            listenerPort = GetConvar('netPort', '0'),
            mapIp = '',
            differingOutbound = false,
            outboundIp = '',
            enableMap = true,
            mapType = 'NORMAL'
        }
    else
        serverObj = ServerInfo
    end
    local existingServerInfo = ServerInfo or {
        listenerPort = '',
        mapIp = '',
        differingOutbound = false,
        outboundIp = ''
    }
    if serverObj.name == '' then
        serverObj.name = 'Server ' .. tostring(serverId)
    end
    if existingServerInfo.listenerPort ~= GetConvar('netPort', '0') then
        infoLog(
            ('Configuration information doesn\'t match, will attempt to auto-correct game port from %s to %s.'):format(
                existingServerInfo.listenerPort, GetConvar('netPort', '0')))
        serverObj.listenerPort = GetConvar('netPort', '0')
        needSetup = true
    end
    PerformHttpRequest('https://api.ipify.org?format=json',
                       function(errorCode, resultData, resultHeaders)
        local r = SafeJsonDecode(resultData, "ipify lookup", nil)
        if r ~= nil and r.ip ~= nil then
            debugLog(
                ('IP DETECT - IP: %s - Detected: %s - Outbound set: %s - Outbound IP: %s'):format(
                    existingServerInfo.mapIp, r.ip, existingServerInfo.differingOutbound,
                    existingServerInfo.outboundIp))
            if serverObj.mapIp == '' or serverObj.mapIp == nil then
                serverObj.mapIp = r.ip
                needSetup = true
            end
            if existingServerInfo.mapIp ~= r.ip then
                if existingServerInfo.differingOutbound and existingServerInfo.outboundIp ==
                    r.ip then
                    infoLog(
                        'Detected proper differing outbound IP configuration.')
                else
                    if existingServerInfo.differingOutbound then
                        needSetup = true
                        serverObj.outboundIp = r.ip
                    else
                        needSetup = true
                        serverObj.outboundIp = r.ip
                        serverObj.differingOutbound = true
                    end
                end
            end
        end
        local disableOverride = (Config.disableOverride ~= nil and
                                    Config.disableOverride or false)
        if needSetup and not disableOverride then
            local payload = nil
            if ServerInfo == nil then
                payload = {['servers'] = {serverObj}}
            else
                payload = info
                for k, v in pairs(payload) do
                    if v.id == serverId then
                        payload[k] = serverObj
                    end
                end
            end
            debugLog(('Send payload: %s'):format(json.encode(payload)))
            local setServersResponse = CadApiSetServers(payload)
            if not setServersResponse.success then
                CadApiLogFailure('SET_SERVERS', setServersResponse, payload)
            else
                debugLog('SET_SERVERS: ' .. tostring(setServersResponse.data and json.encode(setServersResponse.data) or 'OK'))
            end
        elseif disableOverride and not needSetup then
            warnLog("UNHANDLED_WARNING", 'disableOverride is true or there is no additional setup required, skipping any potential auto-IP/port fixing')
        end
    end, 'GET', nil, nil)

    if isPluginLoaded('livemap') then
        warnLog("UNHANDLED_WARNING", 'The livemap plugin is no longer being used due to the map being native to the CAD. You can remove this plugin.')
    end
end)

CreateThread(function()
    while Config.apiVersion == -1 do Wait(100) end
    if Config.critError then return end
    if isPluginLoaded('wraithv2') then
        if GetResourceState('wk_wars2x') ~= 'started' then
            warnLog("UNHANDLED_WARNING", ('Warning: wk_wars2x resource in bad start (%s). Ensure it is started to use the wraithv2 resource.'):format(
                    GetResourceState('wk_wars2x')))
        end
        local wraithConfig = Config.GetPluginConfig('wraithv2') or {}
        local notification = ApplyPluginNotificationOverrides(wraithConfig, {})
        local notificationSystem = ResolveNotificationSystem(notification.system)
        local notificationResources = {
            ox_lib = 'ox_lib',
            lation_ui = 'lation_ui',
            pnotify = 'pNotify'
        }
        local notificationResource = notificationResources[notificationSystem]
        if notificationResource ~= nil and GetResourceState(notificationResource) ~= 'started' then
            warnLog("UNHANDLED_WARNING", ('Warning: %s is configured for wraithv2 notifications but the resource is in bad start (%s). Ensure it is started or set notificationSystem/notificationOverride to auto/chat.'):format(
                    notificationResource, GetResourceState(notificationResource)))
        end
    end
    if isPluginLoaded('smartsigns') then
        warnLog("UNHANDLED_WARNING", 'smartsigns is now a standalone resource. Please update.')
    end
    local smartSignsHelperState = GetResourceState('smartsigns_sonoran_helper')
    if smartSignsHelperState == 'started' or smartSignsHelperState == 'starting' then
        errorLog("SMARTSIGNS_HELPER_STARTED", ("smartsigns_sonoran_helper is currently %s. Remove it from your server startup config; it should only be used internally by Smart Signs."):format(tostring(smartSignsHelperState)))
    end
    -- smartsigns improper install check
    if file_exists(('%s/submodules/smartsigns/sv_smartsigns.lua'):format(
                       GetResourcePath(GetCurrentResourceName()))) or
        file_exists(
            ('%s/submodules/smartsigns/smartsigns/sv_smartsigns.lua'):format(
                GetResourcePath(GetCurrentResourceName()))) then
        errorLog("UNHANDLED_SERVER_ERROR", '-----------------------')
        errorLog("UNHANDLED_SERVER_ERROR", 'Smartsigns incorrect installation detected. This should be installed a standalone resource. If you still have the plugin, you MUST update! You will recieve a parse error in this state.')
        errorLog("UNHANDLED_SERVER_ERROR", '-----------------------')
    end
end)

function file_exists(name)
    local f = io.open(name, 'r')
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
end
