Config = {
    communityID = nil,
    apiKey = nil,
    apiUrl = nil,
    postTime = nil,
    serverId = nil,
    freezeUntilLinked = false,
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
for key, value in pairs(CadLinkDefaults) do Config[key] = value end


-- The only customer-facing local settings are API key and server ID. Legacy
-- credentials are read only until an existing installation has migrated.
local resource = GetCurrentResourceName()
local function decode(raw)
    local ok, value = pcall(json.decode, raw or '')
    if ok and type(value) == 'table' then return value end
end
local rootRaw = LoadResourceFile(resource, 'config.json')
local rootEmpty = rootRaw == nil or rootRaw:match('^%s*$') ~= nil
local bootstrap = not rootEmpty and decode(rootRaw) or nil
local bootstrapError
if not rootEmpty then
    if not bootstrap or not rootRaw:match('^%s*{') then bootstrapError = 'config.json must contain a valid JSON object.'
    else
        for key in pairs(bootstrap) do
            if key ~= 'apiKey' and key ~= 'serverId' then bootstrapError = 'config.json may contain only apiKey and serverId.' end
        end
    end
end
if not bootstrapError and (not bootstrap or bootstrap.apiKey == nil or bootstrap.apiKey == '') then
    local legacy = decode(LoadResourceFile(resource, 'configuration/config.json')) or
        decode(LoadResourceFile(resource, 'configuration_old/config.json'))
    if legacy then bootstrap = {apiKey = legacy.apiKey, serverId = tonumber(legacy.serverId)} end
end
bootstrap = bootstrap or {}
if type(bootstrap.apiKey) ~= 'string' or bootstrap.apiKey == '' or type(bootstrap.serverId) ~= 'number' or
    bootstrap.serverId < 1 or bootstrap.serverId % 1 ~= 0 then
    bootstrapError = bootstrapError or 'Set apiKey and a positive numeric serverId in the resource-root config.json.'
end
Config.apiKey, Config.serverId = bootstrap.apiKey, bootstrap.serverId
Config.bootstrapError = bootstrapError
if not bootstrapError then
    SetConvar('sonoran_apiKey', Config.apiKey)
    SetConvar('sonoran_serverId', tostring(Config.serverId))
end
Config.configurationReady = false
Plugins = {}
updaterIgnore = {ignore = {}}
local activeDocument
local cacheable = false
local mock = GetConvar('sonoran_configurationMock', 'false') == 'true'
local cacheScope = exports[resource]:GetCadConfigurationScope(Config.apiKey, Config.serverId, GetCadConfigurationBootstrapUrl(), mock)
Config.configurationScope = cacheScope
local cachePath = '.configuration-cache.json'

local function warn(message) warnLog('UNHANDLED_WARNING', '[configuration] ' .. message) end
local function fail(message) errorLog('CONFIG_ERROR', '[configuration] ' .. message) end
local function disabled(reason) return {enabled = false, disableReason = reason} end

local coreTypes = {
    postTime='number', primaryIdentifier='string', apiSendEnabled='boolean', debugMode='boolean',
    notificationSystem='string', updateBranch='string', enableCanary='boolean',
    statusLabels='table', allowAutoUpdate='boolean', autoUpdateUrl='string', allowUpdateWithPlayers='boolean',
    noUnitTimer='boolean', enablePushEventForwarding='boolean', pushEventForwardUrl='string',
    disableOverride='boolean', devHiddenSwitch='boolean', communityID='string', mode='string'
}
local legacyCoreTypes = {freezeUntilLinked = 'boolean'}
for key, expected in pairs(coreTypes) do legacyCoreTypes[key] = expected end
for key, value in pairs(CadLinkDefaults) do legacyCoreTypes[key] = type(value) end
local function validate(document, phase)
    local migrating = phase == 'migration'
    local allowPartial = migrating or phase == 'legacy'
    if type(document) ~= 'table' or type(document.core) ~= 'table' or type(document.plugins) ~= 'table' then
        return nil, 'Expected a complete core/plugins configuration document.'
    end
    if not migrating and (type(document.core.communityID) ~= 'string' or document.core.communityID == '') then
        return nil, 'CAD response is missing a valid core.communityID.'
    end
    if not migrating and document.core.mode ~= 'production' and document.core.mode ~= 'development' then
        return nil, 'CAD response must include core.mode set to production or development.'
    end
    -- These required core values cannot come from old files or convar overrides.
    if not migrating and (type(document.core.primaryIdentifier) ~= 'string' or document.core.primaryIdentifier == '' or
        type(document.core.postTime) ~= 'number' or document.core.postTime <= 0 or
        type(document.core.apiSendEnabled) ~= 'boolean') then
        return nil, 'Missing or invalid primaryIdentifier, postTime or apiSendEnabled.'
    end
    for key, value in pairs(document.core) do
        if legacyCoreTypes[key] == nil or type(value) ~= legacyCoreTypes[key] then
            return nil, 'Unsupported or invalid core setting: ' .. tostring(key)
        end
    end
    if type(document.updaterIgnore) ~= 'table' or type(document.updaterIgnore.ignore) ~= 'table' or
        type(document.vehicleModels) ~= 'table' or type(document.callTemplates) ~= 'table' then
        return nil, 'Missing updaterIgnore, vehicleModels or callTemplates configuration.'
    end
    NormalizeCadLinkConfiguration(document)
    local parsed, errors = {}, {}
    for name, value in pairs(document.plugins) do
        if type(name) ~= 'string' or not name:match('^[%w_-]+$') then return nil, 'Invalid plugin name.' end
        local settings, err = ParseCadPluginConfiguration(name, value, allowPartial)
        if not settings then errors[#errors + 1] = err end
        parsed[name] = settings or disabled(err)
    end
    local templates = parsed.calltemplates
    if templates and templates.enabled then
        for _, command in pairs(templates.commands or {}) do
            if type(command) ~= 'table' or type(command.callTypeFile) ~= 'string' or
                type(document.callTemplates[command.callTypeFile]) ~= 'table' then
                local message = 'Missing or invalid call template in CAD configuration.'
                errors[#errors + 1] = message
                parsed.calltemplates = disabled(message)
                break
            end
        end
    end
    return parsed, #errors > 0 and table.concat(errors, '; ') or nil
end

Config.GetPluginConfig = function(name)
    while not Config.configurationReady or (Config.apiVersion == -1 and not Config.critError) do Wait(25) end
    if Config.critError then return disabled('Configuration startup aborted') end
    return Config.plugins[name] or disabled('Missing CAD configuration; configure this plugin in CAD')
end
Config.LoadPlugin = function(name, callback)
    local settings = Config.GetPluginConfig(name)
    if settings.enabled ~= true then return end
    return callback(settings)
end
-- Old config scripts must never register over authoritative settings.
Config.RegisterPluginConfig = function() warn('Local plugin configuration registration ignored. Manage settings in CAD.') end
exports('GetPluginConfig', function(name) return Config.GetPluginConfig(name) end)
exports('GetResolvedConfig', function()
    return json.encode({ready = Config.configurationReady and not Config.critError,
        communityID = Config.communityID, serverId = Config.serverId,
        mode = Config.mode, apiUrl = Config.apiUrl, apiSendEnabled = Config.apiSendEnabled})
end)

Config.SaveConfigurationCache = function(apiVersion, document)
    document = document or activeDocument
    if not document or (document == activeDocument and not cacheable) then return false end
    local ok, content = pcall(json.encode, {version = 1, scope = cacheScope,
        apiVersion = apiVersion or Config.cachedApiVersion, configuration = document})
    local saved = ok and exports[resource]:WriteCadConfiguration('cache', content)
    if not saved then warn('Unable to save the configuration cache; the previous cache was preserved.') end
    return saved
end
local function readCache()
    local cached = decode(LoadResourceFile(resource, cachePath))
    if not cached or cached.version ~= 1 or cached.scope ~= cacheScope then return nil end
    if type(cached.configuration) == 'table' and type(cached.configuration.core) == 'table' then
        cached.configuration.core = NormalizeCadCoreConfiguration(cached.configuration.core)
    end
    -- Older caches stored a second copy inside the client-visible plugin settings.
    local callTemplatesPlugin = type(cached.configuration) == 'table' and
        type(cached.configuration.plugins) == 'table' and cached.configuration.plugins.calltemplates
    if type(callTemplatesPlugin) == 'table' then callTemplatesPlugin.templates = nil end
    local parsed, err = validate(cached.configuration)
    if not parsed or err then return nil end
    local tier = tonumber(cached.apiVersion)
    cached.apiVersion = tier and tier >= 0 and tier <= 9 and tier % 1 == 0 and tier or nil
    return cached, parsed
end

Config.EnsureBootstrapConfig = function()
    local saved = exports[resource]:WriteCadBootstrapConfiguration(Config.apiKey, Config.serverId)
    if not saved then warn('Could not save the two-field config.json. Existing files were preserved; check write permissions.') end
    return saved
end

local function applyConfiguration(document, parsed)
    for key, value in pairs(document.core) do Config[key] = value end
    Config.apiUrl = GetCadApiUrl(Config.mode)
    SetConvar('sonoran_apiKey', Config.apiKey)
    SetConvar('sonoran_serverId', tostring(Config.serverId))
    SetConvar('sonoran_communityID', Config.communityID)
    SetConvar('sonoran_mode', Config.mode)
    Config.plugins = parsed
    for name, settings in pairs(parsed) do
        if settings.enabled then Plugins[#Plugins + 1] = name end
    end
    updaterIgnore = document.updaterIgnore
    Config.vehicleModels = document.vehicleModels
    Config.callTemplates = document.callTemplates
    activeDocument = document
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
            warnLog("UNHANDLED_WARNING", ("Invalid notificationSystem value \"%s\" in CAD configuration. Defaulting to auto."):format(tostring(Config.notificationSystem)))
        end
        normalizedNotificationSystem = "auto"
    end
    Config.notificationSystem = normalizedNotificationSystem

    -- These runtime mirrors serve the core link flow and existing integrations;
    -- the editable values belong only to Force Reg.
    local linkSettings = Config.plugins.forcereg or {}
    for key, default in pairs(CadLinkDefaults) do
        local value = linkSettings[key]
        if value == nil then value = document.core[key] end -- Pre-migration Lua.
        if type(value) ~= type(default) or (type(value) == 'string' and value == '') then value = default end
        Config[key] = value
    end
    Config.linkPollIntervalMs = math.max(1000, math.floor(Config.linkPollIntervalMs))
    local captiveOption = linkSettings.captiveOption or (document.core.freezeUntilLinked and 'freeze')
    Config.freezeUntilLinked = linkSettings.enabled == true and Config.requireLink and
        type(captiveOption) == 'string' and captiveOption:lower() == 'freeze'
    if Config.freezeUntilLinked then Config.allowPopupCloseWhenUnlinked = false end

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


    -- Publish resolved settings for existing integrations; never read these as overrides.
    for key, value in pairs(document.core) do
        if type(value) ~= 'table' then SetConvar('sonoran_' .. key, tostring(Config[key])) end
    end
end

local function migrationWarning(localError)
    warningNotice('Configuration migration required. ' ..
        (localError and ('Local settings could not be loaded: ' .. localError .. ' ') or '') ..
        'Run: sonorancad migrate. https://sonoran.link/migrate')
end

local collectLegacy
local function loadLegacyConfiguration()
    local document, err = collectLegacy(true)
    if not document then return false, err end
    local parsed, issues = validate(document, 'legacy')
    if not parsed then return false, issues end
    cacheable = false -- Legacy settings must never become a last-known-good CAD cache.
    applyConfiguration(document, parsed)
    Config.configurationSource = 'legacy'
    Config.migrationRequired = true
    if issues then warn('Invalid legacy plugin settings disabled: ' .. issues) end
    migrationWarning()
    return true
end

local function resolveConfiguration()
    local ok = pcall(function()
        if Config.bootstrapError then Config.critError = true; fail(Config.bootstrapError); return end
        if mock then warn('MOCK configuration API enabled. Changes are local test data, not uploaded to CAD.') end
        local response = CadConfigurationRequest('get')
        local parsed, err, unavailableWarning
        if response.status == 200 then
            parsed, err = validate(response.data)
            if parsed then
                local prior = readCache()
                Config.cachedApiVersion = prior and tonumber(prior.apiVersion)
                cacheable = err == nil
                if err then warn('Incomplete plugin settings disabled: ' .. err .. '. Cache was preserved.') end
                applyConfiguration(response.data, parsed)
                Config.configurationSource = 'cad'
                Config.SaveConfigurationCache()
                Config.EnsureBootstrapConfig()
                return
            end
        elseif response.status == 404 and response.migrationPending ~= false then
            -- Empty/older endpoint 404s can also mean migration is pending. Only
            -- explicit invalid-server responses should prevent local startup.
            Config.migrationRequired = true
            local loaded, legacyError = loadLegacyConfiguration()
            if loaded then return end
            local cached, cachedPlugins = readCache()
            if cached then
                cacheable = false -- Preserve the cache until CAD returns valid settings.
                applyConfiguration(cached.configuration, cachedPlugins)
                Config.cachedApiVersion = tonumber(cached.apiVersion)
                Config.configurationSource = 'cache'
                migrationWarning()
            else
                -- Keep migration commands available, but never start plugins with
                -- missing settings or emit diagnostic stacks for a pending migration.
                Config.critError = true
                migrationWarning(tostring(legacyError))
            end
            return
        elseif response.status > 0 and response.status < 500 then
            if response.status ~= 404 and not readCache() then
                local loaded, legacyError = loadLegacyConfiguration()
                if loaded then return end
                warn('Legacy startup unavailable: ' .. tostring(legacyError))
            end
            fail('CAD configuration request rejected (HTTP ' .. response.status .. '). Check credentials and backend configuration.')
            Config.critError = true
            return
        else
            unavailableWarning = response.message or ('CAD configuration unavailable (HTTP ' .. response.status .. ').')
        end
        local cached, cachedPlugins = readCache()
        if cached then
            if response.status == 200 then warn('Invalid CAD configuration: ' .. tostring(err) .. ' The previous cache was preserved.') end
            if unavailableWarning then warn(unavailableWarning) end
            cacheable = true
            applyConfiguration(cached.configuration, cachedPlugins)
            Config.cachedApiVersion = tonumber(cached.apiVersion)
            Config.configurationSource = 'cache'
            Config.EnsureBootstrapConfig()
            warn('Using the last-known-good cached configuration while CAD is unavailable.')
        else
            -- Existing installations can continue during the rollout before their
            -- first migration. A malformed 200 never causes a legacy override.
            if response.status ~= 200 then
                local loaded, legacyError = loadLegacyConfiguration()
                if loaded then return end
                warn('Legacy startup unavailable: ' .. tostring(legacyError))
            end
            if unavailableWarning then warn(unavailableWarning) end
            fail((response.status == 200 and ('Invalid CAD configuration: ' .. tostring(err)) or
                'CAD configuration is unavailable.') ..
                ' No valid configuration cache is available. Check the CAD configuration and restart sonorancad.')
            Config.critError = true
        end
    end)
    if not ok then Config.critError = true; fail('Unable to resolve configuration; initialization has been stopped.') end
    if Config.critError then Config.apiSendEnabled = false; Config.apiVersion = 0 end
    Config.configurationReady = true
    if not Config.critError then TriggerEvent('SonoranCAD::core:configurationReady') end
end

-- Client plugins receive only their configuration, never the server API key.
RegisterNetEvent('SonoranCAD::core:requestPluginConfig')
AddEventHandler('SonoranCAD::core:requestPluginConfig', function(name)
    local player = source
    if type(name) ~= 'string' or #name > 100 then return end
    local settings = Config.GetPluginConfig(name)
    local entry = settings.enabled and activeDocument and activeDocument.plugins[name]
    TriggerClientEvent('SonoranCAD::core:receivePluginConfig', player, name, entry or disabled('Missing CAD configuration'))
end)

-- Tokenize only to locate complete function bodies. Strings, comments and Cfx
-- hash literals must not be mistaken for Lua block delimiters.
local function legacyTokens(source)
    local tokens, i = {}, 1
    while i <= #source do
        local start, c = i, source:sub(i, i)
        if c:match('%s') then i = i + 1
        elseif c == '"' or c == "'" or c == '`' then
            i = i + 1
            while i <= #source do
                local char = source:sub(i, i); i = i + 1
                if char == '\\' then i = i + 1 elseif char == c then break end
            end
        else
            local comment = source:sub(i, i + 1) == '--'
            local opening = comment and i + 2 or i
            local equals = source:sub(opening):match('^%[(=*)%[')
            if equals then
                local _, last = source:find(']' .. equals .. ']', opening + #equals + 2, true)
                assert(last, 'Unclosed long string/comment'); i = last + 1
            elseif comment then i = (source:find('\n', i, true) or #source) + 1
            else
                local word = source:sub(i):match('^[%a_][%w_]*') or c
                i = i + #word
                tokens[#tokens + 1] = {word = word, first = start, last = i - 1}
            end
        end
    end
    return tokens
end

local function jsonSettings(value, seen)
    local kind = type(value)
    if kind:match('^vector[234]$') then
        local position = {x = value.x, y = value.y}
        if kind ~= 'vector2' then position.z = value.z end
        if kind == 'vector4' then position.w = value.w end
        return position
    elseif kind == 'table' then
        assert(not seen[value], 'Cyclic configuration'); seen[value] = true
        local count, array = 0, true
        for key in pairs(value) do count = count + 1; if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then array = false end end
        array = array and count == #value
        local copy = {}
        for key, item in pairs(value) do
            assert(type(key) == 'number' or type(key) == 'string', 'Unsupported configuration key')
            copy[array and key or tostring(key)] = jsonSettings(item, seen)
        end
        seen[value] = nil
        return copy
    end
    assert(kind == 'string' or kind == 'number' or kind == 'boolean', 'Unsupported configuration value')
    return value
end

function ExportLegacyPluginConfiguration(name, source)
    local ok, config = pcall(function()
        local tokens, pieces, helpers, cursor, i = legacyTokens(source), {}, {}, 1, 1
        while i <= #tokens do
            local token = tokens[i]
            if token.word ~= 'function' then i = i + 1
            else
                local stack, j = {{close = 'end'}}, i + 1
                while #stack > 0 and j <= #tokens do
                    local word = tokens[j].word
                    if word == 'function' or word == 'if' then stack[#stack + 1] = {close = 'end'}
                    elseif word == 'for' or word == 'while' then stack[#stack + 1] = {close = 'end', needsDo = true}
                    elseif word == 'do' then
                        if stack[#stack].needsDo then stack[#stack].needsDo = nil else stack[#stack + 1] = {close = 'end'} end
                    elseif word == 'repeat' then stack[#stack + 1] = {close = 'until'}
                    elseif word == 'end' or word == 'until' then
                        assert(stack[#stack].close == word, 'Invalid Lua block'); table.remove(stack)
                    end
                    j = j + 1
                end
                assert(#stack == 0, 'Unclosed callback')
                local text = source:sub(token.first, tokens[j - 1].last)
                local helper = text:match('^function%s+([%w_]+)%s*%(')
                assert(helper or text:match('^function%s*%('), 'Unsupported callback declaration')
                pieces[#pieces + 1] = source:sub(cursor, token.first - 1)
                pieces[#pieces + 1] = (helper and helper .. ' = ' or '') .. string.format('%q', text)
                if helper then helpers[helper] = text end
                cursor, i = tokens[j - 1].last + 1, j
            end
        end
        pieces[#pieces + 1] = source:sub(cursor)
        local registered
        local env = setmetatable({Config = {RegisterPluginConfig = function(_, value) registered = value end}}, {__index = _G})
        local chunk = assert(load(table.concat(pieces) .. '\nreturn config', '@legacy-config/' .. name, 't', env))
        local value = chunk() or registered
        assert(type(value) == 'table', 'Missing configuration table')
        for key, text in pairs(helpers) do
            assert(value[key] == nil or value[key] == text, 'Helper conflicts with a setting'); value[key] = text
        end
        return jsonSettings(value, {})
    end)
    if not ok then return nil, 'Cannot export ' .. name .. ' as JSON. Check its Lua settings/callbacks; legacy files were preserved.' end
    return config
end

collectLegacy = function(startup)
    local inventory = decode(exports[resource]:ListLegacyCadConfiguration())
    if not inventory or inventory.error then return nil, inventory and inventory.error or 'Unable to discover legacy configuration.' end
    local document = {core = decode(LoadResourceFile(resource, 'configuration/config.json')), plugins = {},
        updaterIgnore = {ignore = {}}, vehicleModels = {}, callTemplates = {}}
    if not document.core then return nil, 'Missing or invalid configuration/config.json.' end
    if startup and (document.core.apiKey ~= Config.apiKey or tonumber(document.core.serverId) ~= Config.serverId) then
        return nil, 'Legacy credentials/server do not match the active config.json.'
    end
    document.core.communityID = document.core.communityID or document.core.commId
    local legacyMode = GetConvar('sonoran_mode', 'NONE')
    local modeSetter = GetConvar('sonoran_mode_setter', 'NONE')
    if (legacyMode == 'development' or legacyMode == 'production') and (modeSetter == 'NONE' or modeSetter == 'server') then
        -- Honor existing server.cfg overrides only in the legacy transition.
        document.core.mode = legacyMode
    end
    document.core.mode = document.core.mode or document.core.branch or
        (GetCadConfigurationBootstrapUrl():find('staging', 1, true) and 'development' or 'production')
    document.core = NormalizeCadCoreConfiguration(document.core)
    for key, expected in pairs(legacyCoreTypes) do
        local value = GetConvar('sonoran_' .. key, 'NONE')
        local setter = GetConvar('sonoran_' .. key .. '_setter', 'NONE')
        if key ~= 'communityID' and key ~= 'mode' and value ~= 'NONE' and (setter == 'NONE' or setter == 'server') then
            if expected == 'number' then value = tonumber(value)
            elseif expected == 'boolean' then
                if value == 'true' then value = true elseif value == 'false' then value = false else value = nil end
            elseif expected == 'table' then value = decode(value) end
            if value == nil then return nil, 'Invalid legacy convar: sonoran_' .. key end
            document.core[key] = value
        end
    end
    local selected = {}
    for _, file in ipairs(inventory.files) do
        local name = file:match('^(.-)_config%.lua$')
        local default = file:match('^(.-)_config%.dist%.lua$')
        if name then selected[name] = file
        elseif default and not selected[default] then selected[default] = file
        elseif file:match('%.lua$') and not startup then return nil, 'Unrecognized legacy configuration file: ' .. file
        elseif not startup and file:match('%.json$') and file ~= 'config.json' and file ~= 'config.CHANGEME.json' and
            file ~= 'updateIgnore.json' and file ~= 'updateIgnore.CHANGEME.json' and file ~= 'livemap_vehicle_models.json' then
            return nil, 'Unrecognized legacy configuration file: ' .. file
        end
    end
    -- Keep the original Lua for pre-migration runtime behavior, including closures.
    -- Only the explicit migration command converts it into JSON settings.
    for name, file in pairs(selected) do
        local source = LoadResourceFile(resource, 'configuration/' .. file)
        if startup then
            document.plugins[name] = source or disabled('Cannot read legacy configuration: ' .. file)
        else
            if not source then return nil, 'Cannot read ' .. file end
            local settings, err = ExportLegacyPluginConfiguration(name, source)
            if not settings then return nil, err end
            document.plugins[name] = settings
        end
    end
    for _, name in ipairs(inventory.plugins or {}) do
        if not document.plugins[name] then
            document.plugins[name] = startup and disabled('No legacy configuration') or {enabled = false}
        end
    end
    for _, item in ipairs({{'updateIgnore.json', 'updaterIgnore'}, {'livemap_vehicle_models.json', 'vehicleModels'}}) do
        local raw = LoadResourceFile(resource, 'configuration/' .. item[1])
        if not raw and item[2] == 'updaterIgnore' then raw = LoadResourceFile(resource, 'configuration/updateIgnore.CHANGEME.json') end
        if raw then
            local parsed = decode(raw)
            if parsed then document[item[2]] = parsed
            elseif startup then warn('Ignoring invalid legacy JSON for startup: ' .. item[1])
            else return nil, 'Invalid JSON in ' .. item[1] end
        end
    end
    local function readCallTemplates()
        if not document.plugins.calltemplates then return true end
        local settings, err = ParseCadPluginConfiguration('calltemplates', document.plugins.calltemplates, true)
        if not settings then return nil, err end
        if not settings.enabled and settings.commands == nil then return true end
        -- File discovery is only for existing installations before their migration.
        if settings.callTypeDirectory ~= nil and type(settings.callTypeDirectory) ~= 'string' then
            return nil, 'Invalid legacy call template directory.'
        end
        local directory = settings.callTypeDirectory or 'submodules/calltemplates/calltypes'
        local templates = decode(exports[resource]:ListLegacyCadConfiguration(directory))
        if not templates or templates.error then return nil, 'Cannot discover call templates in ' .. directory end
        for _, name in ipairs(templates.files) do
            if name:match('%.json$') then
                local template = decode(LoadResourceFile(resource, directory .. '/' .. name))
                if not template then return nil, 'Invalid call template: ' .. name end
                document.callTemplates[name] = template
            end
        end
        for _, command in pairs(settings.commands or {}) do
            if type(command) ~= 'table' or type(command.callTypeFile) ~= 'string' then return nil, 'Invalid call template command.' end
            local path = directory .. '/' .. command.callTypeFile
            local template = decode(LoadResourceFile(resource, path))
            if not template then return nil, 'Missing or invalid call template: ' .. path end
            document.callTemplates[command.callTypeFile] = template
        end
        return true
    end
    local templatesOk, templateError = readCallTemplates()
    if not templatesOk then
        if not startup then return nil, templateError end
        document.plugins.calltemplates = disabled(templateError)
        document.callTemplates = {}
        warn('Call Templates disabled for legacy startup: ' .. tostring(templateError))
    end
    if startup then return document end
    local parsed, err = validate(document, 'migration')
    if not parsed or err then return nil, err end
    return document
end

-- All legacy readers are defined before the first request can complete.
CreateThread(resolveConfiguration)

local migrating = false
local acceptedThisSession = false
local function diagnosticText(value, limit)
    local text = tostring(value)
    if type(Config.apiKey) == 'string' and Config.apiKey ~= '' then
        text = text:gsub(Config.apiKey:gsub('([^%w])', '%%%1'), '[redacted]')
    end
    text = text:gsub('[Bb]earer%s+[%w%._%-]+', 'Bearer [redacted]')
    text = text:gsub('[%c]', function(char) return ('\\x%02X'):format(char:byte()) end)
    return #text > limit and (text:sub(1, limit) .. '...') or text
end
local function configurationDifferences(expected, actual, path, differences)
    differences = differences or {}
    path = path or ''
    if #differences > 10 then return differences end
    local same = expected == actual
    if type(expected)=='number' and type(actual)=='number' and not same then
        -- JSON round trips can change the last decimal bits. Scale the tolerance,
        -- but cap it so large settings/IDs cannot hide a meaningful value change.
        local tolerance = math.min(1e-9, 1e-12 * math.max(1, math.abs(expected), math.abs(actual)))
        same = math.abs(expected-actual) <= tolerance
    end
    if type(expected) ~= type(actual) or (type(expected) ~= 'table' and not same) then
        differences[#differences + 1] = {path=path, expected=expected, actual=actual}
    elseif type(expected) == 'table' then
        local keys = {}; for key in pairs(expected) do keys[#keys + 1] = key end
        table.sort(keys, function(a,b) return type(a)..tostring(a) < type(b)..tostring(b) end)
        for _, key in ipairs(keys) do
            local child = type(key)=='string' and key:match('^[%a_][%w_]*$') and
                ((path=='' and '' or path..'.')..key) or (path..('['..string.format('%q',diagnosticText(key,64))..']'))
            configurationDifferences(expected[key], actual[key], child, differences)
            if #differences > 10 then break end
        end
    end
    return differences
end
local function differenceValue(value, path)
    local kind = type(value)
    if kind == 'nil' then return 'missing' end
    local key = path:lower():gsub('[^%w]', '')
    for _, sensitive in ipairs({'apikey','password','secret','token','authorization','webhook','credential'}) do
        if key:find(sensitive,1,true) then return kind .. ' [redacted]' end
    end
    if kind == 'string' then
        if value:match('^%s*function[%s%(]') then return ('Lua source (%s bytes)'):format(#value) end
        return 'string "' .. diagnosticText(value,100) .. '"'
    end
    if kind == 'number' then return 'number ' .. (math.type(value)=='integer' and tostring(value) or ('%.17g'):format(value)) end
    if kind == 'boolean' then return 'boolean ' .. tostring(value) end
    return kind
end
local function logMigrationDifferences(differences)
    for i=1,math.min(#differences,10) do
        local diff = differences[i]
        warningNotice(('[configuration] Difference at %s: local=%s; CAD=%s.'):format(
            diff.path=='' and '<configuration>' or diagnosticText(diff.path,180),
            differenceValue(diff.expected,diff.path), differenceValue(diff.actual,diff.path)))
        if type(diff.expected)=='string' and type(diff.actual)=='string' and diff.expected:match('^%s*function[%s%(]') then
            local offset=1
            while offset<=math.min(#diff.expected,#diff.actual) and diff.expected:byte(offset)==diff.actual:byte(offset) do offset=offset+1 end
            warningNotice(('[configuration] Lua source first differs at byte %s (local=%s bytes; CAD=%s bytes).'):format(offset,#diff.expected,#diff.actual))
        end
    end
    if #differences > 10 then warningNotice('[configuration] Additional differences omitted (limit: 10).') end
end
local function logReadbackFailure(fetched, status, invalid, differences)
    warningNotice(('[configuration] Migration readback failed for server %s (upload=%s; GET HTTP %s). Legacy files and cache were preserved.'):format(
        Config.serverId, status, fetched.status))
    if fetched.message then warningNotice('[configuration] GET detail: '..diagnosticText(fetched.message,400)) end
    if invalid then warningNotice('[configuration] Validation: '..diagnosticText(invalid,600)) end
    logMigrationDifferences(differences or {})
end
function MigrateCadConfiguration()
    if migrating then warn('A migration is already in progress.'); return end
    migrating = true
    CreateThread(function()
        local ok = pcall(function()
            while not Config.configurationReady do Wait(25) end
            if Config.bootstrapError then fail(Config.bootstrapError); return end
            -- An update can introduce an empty root config. Prepare its credentials
            -- before contacting CAD so a failed/ambiguous upload is still retryable.
            if not Config.EnsureBootstrapConfig() then
                fail('Cannot prepare config.json. Check its contents/write permissions and retry; legacy files were preserved.')
                return
            end
            -- Always check CAD first, including after an ambiguous upload timeout.
            local existing = CadConfigurationRequest('get')
            if existing.status == 200 or acceptedThisSession then
                if existing.status == 200 then
                    local parsed, invalid = validate(existing.data)
                    local localDocument = collectLegacy()
                    local differences = localDocument and configurationDifferences(localDocument, existing.data) or {}
                    if parsed and not invalid then
                        if #differences > 0 then
                            warningNotice('[configuration] Existing CAD settings differ from local files. CAD edits may be intentional; no upload was sent.')
                            logMigrationDifferences(differences)
                        end
                        Config.SaveConfigurationCache(Config.apiVersion, existing.data); Config.EnsureBootstrapConfig()
                    else logReadbackFailure(existing, 'alreadyMigrated', invalid, differences) end
                else
                    logReadbackFailure(existing, 'previouslyAccepted')
                end
                warningNotice('[configuration] Configuration has already migrated. No upload was sent. Manage settings in CAD and restart this resource.')
                return
            end
            if existing.status ~= 404 or existing.migrationPending == false then
                fail('Cannot confirm migration state (HTTP ' .. existing.status .. '). Check connectivity/credentials and retry. Legacy files were preserved.')
                return
            end
            local document, err = collectLegacy()
            if not document then fail('Migration stopped: ' .. tostring(err)); return end
            local response = CadConfigurationRequest('migrate', document)
            local result = response.data
            if response.status ~= 200 or type(result) ~= 'table' or result.serverId ~= Config.serverId or
                (result.status ~= 'saved' and result.status ~= 'alreadyMigrated') then
                fail('Migration upload failed (HTTP ' .. response.status .. '). ' .. tostring(response.message or '') ..
                    ' Check credentials, payload and connectivity, then retry. Legacy files were preserved.')
                return
            end
            acceptedThisSession = true
            local fetched = CadConfigurationRequest('get')
            local parsed, invalid
            if fetched.status == 200 then parsed, invalid = validate(fetched.data) end
            local differences = result.status == 'saved' and fetched.status == 200 and
                configurationDifferences(document, fetched.data) or {}
            if not parsed or invalid or #differences > 0 then
                logReadbackFailure(fetched, result.status, invalid, differences)
                return
            end
            -- All plugins retain references to their startup tables. Keep this process
            -- consistent and require a resource restart rather than mixing live sources.
            if not Config.SaveConfigurationCache(Config.apiVersion, fetched.data) then
                warn('CAD accepted the migration, but caching failed. Legacy files were preserved. Restart after fixing write permissions.')
                return
            end
            if not Config.EnsureBootstrapConfig() then
                warn('CAD accepted the migration. The legacy directory was kept until config.json can be saved safely.')
                return
            end
            if result.status == 'alreadyMigrated' then
                warn('CAD already had saved configuration. Existing CAD edits were preserved and cached. Restart the resource; legacy files were kept.')
                return
            end
            infoLog('Configuration migration successful. All settings ' .. (mock and 'were saved to the MOCK API.' or 'have been uploaded to SonoranCAD.'))
            infoLog('Manage future resource and plugin settings through the CAD interface. Restart the sonorancad resource to activate the migrated configuration.')
            -- Final migration mutation, deliberately nonfatal and never overwriting an archive.
            local archiveOk, archived = pcall(function() return exports[resource]:ArchiveLegacyCadConfiguration() end)
            if archiveOk and archived then
                infoLog('Legacy configuration archived as configuration_old.')
            else
                warn('Migration succeeded; legacy directory could not be archived. Existing files were preserved.')
            end
        end)
        migrating = false
        if not ok then fail('Migration could not finish. Check CAD before retrying; legacy files have been preserved unless already archived.') end
    end)
end

RegisterNetEvent('SonoranCAD::core:sendClientConfig')
AddEventHandler('SonoranCAD::core:sendClientConfig', function()
    local player = source
    while not Config.configurationReady or (Config.apiVersion == -1 and not Config.critError) do Wait(25) end
    local pluginStates = {}
    for name, settings in pairs(Config.plugins) do pluginStates[name] = not Config.critError and settings.enabled == true end
    local config = {
        pluginStates = pluginStates,
        configurationSource = Config.configurationSource,
        critError = Config.critError == true,
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
    TriggerClientEvent('SonoranCAD::core:recvClientConfig', player, config)
end)

CreateThread(function()
    while not Config.configurationReady do Wait(25) end
    Wait(2000) -- wait for server to settle
    if Config.critError then return end
    local serverId = tonumber(Config.serverId)
    while Config.apiVersion == -1 and not Config.critError do Wait(10) end
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
    while Config.apiVersion == -1 and not Config.critError do Wait(100) end
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
