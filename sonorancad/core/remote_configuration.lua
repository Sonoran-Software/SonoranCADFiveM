-- Loaded before configuration.lua. Never execute downloaded Lua or write credentials to cache.
local supportedSchema = 1
local restartPending = false

local function request(method, suffix)
    local pending = promise.new()
    local settled = false
    local base = Config.mode == 'development' and 'https://staging-api.dev.sonorancad.com/' or 'https://api.sonorancad.com/'
    local url = base .. 'v2/fivem/servers/' .. tostring(Config.serverId) .. '/configuration' .. (suffix or '')
    local function finish(value)
        if settled then return end
        settled = true
        pending:resolve(value)
    end
    SetTimeout(20000, function() finish(nil) end)
    PerformHttpRequest(url, function(status, body)
        if status ~= 200 then finish(nil) return end
        local ok, data = pcall(json.decode, body or '')
        finish(ok and data or nil)
    end, method, '', { ['Authorization'] = 'Bearer ' .. Config.apiKey, ['Content-Type'] = 'application/json' })
    return Citizen.Await(pending)
end

local function valid(data)
    return type(data) == 'table' and data.schemaVersion == supportedSchema
        and tonumber(data.serverId) == tonumber(Config.serverId)
        and type(data.revision) == 'number' and data.revision > 0
        and type(data.values) == 'table' and type(data.values.core) == 'table'
        and type(data.values.plugins) == 'table'
end

function LoadRemoteFiveMConfiguration()
    while true do
        local data = request('GET')
        if valid(data) then
            -- Retain the JSON-safe copy for clients; native vectors/functions are rebuilt locally.
            Config.remotePluginValues = data.values.plugins
            -- Resolve critical dependencies before any submodule can start, on both sides.
            local changed = true
            while changed do
                changed = false
                for _, plugin in pairs(Config.remotePluginValues) do
                    if plugin.enabled then
                        for _, dependency in ipairs(plugin.requiresPlugins or {}) do
                            local required = Config.remotePluginValues[dependency.name]
                            if dependency.critical and (not required or not required.enabled) then
                                plugin.enabled = false
                                plugin.disableReason = 'Missing dependency ' .. dependency.name
                                changed = true
                            end
                        end
                    end
                end
            end
            for key, value in pairs(data.values.core) do
                -- Defense in depth: bootstrap identity and executable members are never remotely replaced.
                if key ~= 'apiKey' and key ~= 'communityID' and key ~= 'serverId' and key ~= 'mode'
                    and key ~= 'plugins' and type(Config[key]) ~= 'function' then
                    Config[key] = value
                    SetConvar('sonoran_' .. key, tostring(value))
                end
            end
            Config.plugins = ResolveFiveMConfig(data.values.plugins)
            Plugins = {}
            for name, plugin in pairs(Config.plugins) do
                if plugin.enabled then Plugins[#Plugins + 1] = name end
            end
            Config.remoteRevision = data.revision
            Config.remoteTemplateRevision = data.templateRevision
            Config.remoteReady = true
            infoLog('Loaded CAD-managed FiveM configuration revision ' .. tostring(data.revision))
            return
        end
        warnLog('UNHANDLED_WARNING', 'CAD configuration is unavailable, not yet saved, or incompatible. Save settings in CAD > In-Game Integration > FiveM. Startup is waiting; retrying in 60 seconds.')
        Wait(60000)
    end
end

function AcknowledgeFiveMConfiguration()
    if Config.remoteReady and Config.remoteRevision > 0 then
        CreateThread(function()
            while not request('POST', '/acknowledge/' .. tostring(Config.remoteRevision)) do Wait(60000) end
        end)
    end
end

-- Called only by the authenticated push-event dispatcher, never a client net event.
function ApplyRemoteFiveMConfiguration(data)
    if restartPending or not Config.remoteReady or type(data) ~= 'table'
        or tonumber(data.serverId) ~= tonumber(Config.serverId)
        or data.schemaVersion ~= supportedSchema or type(data.revision) ~= 'number'
        or (data.revision == Config.remoteRevision and data.templateRevision == Config.remoteTemplateRevision)
        or data.revision < Config.remoteRevision then return false end
    restartPending = true
    CreateThread(function()
        local latest = request('GET')
        if valid(latest) and latest.revision == data.revision and latest.templateRevision == data.templateRevision then
            infoLog('CAD requested configuration revision ' .. tostring(data.revision) .. '. Restarting SonoranCAD in 5 seconds.')
            Wait(5000)
            ExecuteCommand('restart ' .. GetCurrentResourceName())
        else
            warnLog('UNHANDLED_WARNING', 'Configuration changed or is unavailable. Remote restart cancelled; use Apply again in CAD.')
        end
        restartPending = false
    end)
    return true
end
