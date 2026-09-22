-- CAD-managed configuration transport. Downloaded values are data only; Lua is never executed.
local supportedSchema = 1
local restartPending = false

local function apiBaseUrl()
    if Config.mode == "development" then return "https://staging-api.dev.sonorancad.com/" end
    return "https://api.sonorancad.com/"
end

local function request(method, suffix, payload)
    local pending = promise.new()
    local settled = false
    local url = apiBaseUrl() .. "v2/fivem/servers/" .. tostring(Config.serverId) .. "/configuration" .. (suffix or "")
    local encodedPayload = payload and json.encode(payload) or ""

    local function finish(value)
        if settled then return end
        settled = true
        pending:resolve(value)
    end

    SetTimeout(20000, function()
        finish({success = false, status = 408, reason = "request timed out"})
    end)
    PerformHttpRequest(url, function(status, body, headers)
        local numericStatus = tonumber(status) or 0
        local decoded = nil
        if type(body) == "string" and body ~= "" then
            local ok, parsed = pcall(json.decode, body)
            if ok then decoded = parsed end
        end
        finish({
            success = numericStatus >= 200 and numericStatus < 300,
            status = numericStatus,
            data = decoded,
            reason = decoded or body,
            headers = headers
        })
    end, method, encodedPayload, {
        ["Authorization"] = "Bearer " .. Config.apiKey,
        ["Accept"] = "application/json",
        ["Content-Type"] = "application/json"
    })
    return Citizen.Await(pending)
end

local function isInteger(value, minimum)
    return type(value) == "number" and value % 1 == 0 and value >= minimum
end

local function valid(data)
    return type(data) == "table"
        and data.schemaVersion == supportedSchema
        and tonumber(data.serverId) == tonumber(Config.serverId)
        and isInteger(data.revision, 0)
        and type(data.templateRevision) == "string" and data.templateRevision ~= ""
        and type(data.values) == "table"
        and type(data.values.core) == "table"
        and type(data.values.plugins) == "table"
end

local function loadDependencyCatalog()
    local raw = LoadResourceFile(GetCurrentResourceName(), "version.json")
    if not raw then return {} end
    local ok, version = pcall(json.decode, raw)
    if not ok or type(version) ~= "table" then return {} end
    return version.submoduleConfigs or {}
end

local function enforceCriticalDependencies(plugins)
    local catalog = loadDependencyCatalog()
    local changed = true
    while changed do
        changed = false
        for name, plugin in pairs(plugins) do
            if type(plugin) == "table" and plugin.enabled then
                local metadata = catalog[name] or {}
                for _, dependency in ipairs(metadata.requiresPlugins or plugin.requiresPlugins or {}) do
                    local required = plugins[dependency.name]
                    if dependency.critical and (type(required) ~= "table" or not required.enabled) then
                        plugin.enabled = false
                        plugin.disableReason = "Missing dependency " .. tostring(dependency.name)
                        changed = true
                    end
                end
            end
        end
    end
end

local function applyConfiguration(data, localState)
    local remoteCore = valid(data) and data.values.core or {}
    local remotePlugins = valid(data) and ResolveFiveMConfig(data.values.plugins) or {}
    local localCore = localState and localState.core or nil
    local localPlugins = localState and localState.plugins or nil
    local effectiveCore = type(localCore) == "table" and next(localCore) ~= nil
        and MergeFiveMConfig(remoteCore, localCore) or MergeFiveMConfig(remoteCore, nil)
    local effectivePlugins = type(localPlugins) == "table" and next(localPlugins) ~= nil
        and MergeFiveMConfig(remotePlugins, localPlugins) or MergeFiveMConfig(remotePlugins, nil)

    enforceCriticalDependencies(effectivePlugins)
    for key, value in pairs(effectiveCore) do
        if key ~= "apiKey" and key ~= "communityID" and key ~= "serverId" and key ~= "mode"
            and key ~= "plugins" and type(Config[key]) ~= "function" then
            Config[key] = value
            SetConvar("sonoran_" .. key, tostring(value))
        end
    end

    local serializationErrors = {}
    Config.plugins = effectivePlugins
    Config.remoteCoreValues = SerializeFiveMConfig(effectiveCore, "core", serializationErrors)
    Config.remotePluginValues = SerializeFiveMConfig(effectivePlugins, "plugins", serializationErrors)
    Config.localSerializationErrors = serializationErrors
    Config.remoteRevision = valid(data) and data.revision or 0
    Config.remoteTemplateRevision = valid(data) and data.templateRevision or nil
    Config.remoteReady = true

    Plugins = {}
    for name, plugin in pairs(Config.plugins) do
        if type(plugin) == "table" and plugin.enabled then Plugins[#Plugins + 1] = name end
    end
    table.sort(Plugins)

    if valid(data) then
        infoLog("Loaded CAD-managed FiveM configuration revision " .. tostring(data.revision))
    else
        warnLog("UNHANDLED_WARNING", "CAD configuration could not be loaded; continuing with detected local configuration while migration retries.")
    end
end

local function uploadLocalConfiguration()
    if not Config.localConfigurationDetected then return true end
    if #((Config.localConfiguration or {}).errors or {}) > 0 then
        warnLog("UNHANDLED_WARNING", "Local configuration migration is blocked until scan errors are resolved: " .. table.concat(Config.localConfiguration.errors, "; "))
        return false
    end
    if #(Config.localSerializationErrors or {}) > 0 then
        warnLog("UNHANDLED_WARNING", "Local configuration contains values that cannot be migrated: " .. table.concat(Config.localSerializationErrors, "; "))
        return false
    end

    local response = request("POST", "/migrate", {
        schemaVersion = supportedSchema,
        values = {
            core = Config.remoteCoreValues or {},
            plugins = Config.remotePluginValues or {}
        }
    })
    if response.success then
        Config.localMigrationUploaded = true
        infoLog("Uploaded local FiveM configuration to CAD for migration review.")
        return true
    end
    warnLog("UNHANDLED_WARNING", "Unable to upload local FiveM configuration for migration (HTTP " .. tostring(response.status) .. "). Retrying in 60 seconds.")
    return false
end

local function startMigrationUploadLoop()
    CreateThread(function()
        while Config.localConfigurationDetected and not Config.localMigrationUploaded do
            if uploadLocalConfiguration() then return end
            Wait(60000)
        end
    end)
end

local function startMigrationWarningLoop()
    CreateThread(function()
        while Config.localConfigurationDetected do
            logError("LOCAL_CONFIG_MIGRATION_REQUIRED", "Local configuration files were detected. Configuration is now managed in Sonoran CAD. Open In-Game Integration > FiveM to verify and finish migration: https://docs.sonoransoftware.com/cad/api-integration/websocket-api/fivem-configuration")
            Wait(60000)
        end
    end)
end

function LoadRemoteFiveMConfiguration(localState)
    localState = localState or {detected = false, core = {}, plugins = {}, files = {}, errors = {}}
    Config.localConfiguration = localState
    Config.localConfigurationDetected = localState.detected == true
    Config.localMigrationUploaded = false

    if Config.localConfigurationDetected then
        local response = request("GET")
        applyConfiguration(response.success and valid(response.data) and response.data or nil, localState)
        startMigrationUploadLoop()
        startMigrationWarningLoop()
        return
    end

    while true do
        local response = request("GET")
        if response.success and valid(response.data) and response.data.revision > 0 then
            applyConfiguration(response.data, localState)
            return
        end
        warnLog("UNHANDLED_WARNING", "CAD configuration is unavailable, not yet saved, or incompatible. Save settings in CAD > In-Game Integration > FiveM. Startup is waiting; retrying in 60 seconds.")
        Wait(60000)
    end
end

function AcknowledgeFiveMConfiguration()
    if not Config.remoteReady or not isInteger(Config.remoteRevision, 1) then return end
    CreateThread(function()
        while true do
            local response = request("POST", "/acknowledge/" .. tostring(Config.remoteRevision))
            if response.success then return end
            if response.status == 409 then
                warnLog("UNHANDLED_WARNING", "CAD configuration changed before revision " .. tostring(Config.remoteRevision) .. " could be acknowledged. Use Apply and restart in CAD to load the saved revision.")
                return
            end
            warnLog("UNHANDLED_WARNING", "Unable to acknowledge CAD configuration revision " .. tostring(Config.remoteRevision) .. "; retrying in 60 seconds.")
            Wait(60000)
        end
    end)
end

local function validPushData(data)
    return type(data) == "table"
        and tonumber(data.serverId) == tonumber(Config.serverId)
        and data.schemaVersion == supportedSchema
        and isInteger(data.revision, 1)
        and type(data.templateRevision) == "string" and data.templateRevision ~= ""
end

-- Called only by the authenticated websocket push-event dispatcher, never a client net event.
function ApplyRemoteFiveMConfiguration(data)
    if restartPending or not Config.remoteReady or not validPushData(data)
        or (data.revision == Config.remoteRevision and data.templateRevision == Config.remoteTemplateRevision)
        or data.revision < Config.remoteRevision then return false end

    restartPending = true
    CreateThread(function()
        local response = request("GET")
        local latest = response.data
        if response.success and valid(latest)
            and latest.revision == data.revision
            and latest.templateRevision == data.templateRevision then
            infoLog("CAD requested configuration revision " .. tostring(data.revision) .. ". Restarting SonoranCAD in 5 seconds.")
            Wait(5000)
            ExecuteCommand("restart " .. GetCurrentResourceName())
            return
        end
        warnLog("UNHANDLED_WARNING", "Configuration changed or is unavailable. Remote restart cancelled; use Apply again in CAD.")
        restartPending = false
    end)
    return true
end

-- The migration action is destructive, so re-fetch and verify the exact reviewed revision first.
function CompleteFiveMConfigurationMigration(data)
    if restartPending or not Config.localConfigurationDetected or not Config.localMigrationUploaded
        or not validPushData(data) then return false end

    restartPending = true
    CreateThread(function()
        local response = request("GET")
        local latest = response.data
        if not response.success or not valid(latest)
            or latest.revision ~= data.revision
            or latest.templateRevision ~= data.templateRevision then
            warnLog("UNHANDLED_WARNING", "Local configuration cleanup was cancelled because the reviewed CAD revision could not be verified. Review the settings and run migration again.")
            restartPending = false
            return
        end

        local result, cleanupError = DeleteLocalFiveMConfigurationFiles()
        if not result then
            logError("LOCAL_CONFIG_MIGRATION_CLEANUP_FAILED", tostring(cleanupError))
            restartPending = false
            return
        end

        Config.localConfigurationDetected = false
        infoLog("Removed migrated local configuration files: " .. table.concat(result.deleted or {}, ", "))
        infoLog("FiveM configuration migration complete. Restarting SonoranCAD in 5 seconds.")
        Wait(5000)
        ExecuteCommand("restart " .. GetCurrentResourceName())
    end)
    return true
end
