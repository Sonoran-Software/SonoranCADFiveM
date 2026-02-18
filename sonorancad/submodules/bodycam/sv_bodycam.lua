CreateThread(function()
    Config.LoadPlugin("bodycam", function(pluginConfig)
        if pluginConfig.enabled then
            local turnCache = {
                iceServers = nil,
                ttl = 0,
                expiresAt = 0,
                fetching = false,
                waiters = {},
                refreshTimerActive = false
            }
            local TURN_REFRESH_SECONDS = 60 * 60
            local TURN_MIN_REFRESH_SECONDS = 60
            local TURN_EXPIRY_BUFFER_SECONDS = 60
            local turnUserId = nil
            local turnHostOverride = nil
            local turnPortOverride = nil

            local peerStreamConfig = pluginConfig.peerStream or {}
            if type(peerStreamConfig) == "table" then
                if peerStreamConfig.turnHostOverride and peerStreamConfig.turnHostOverride ~= "" then
                    turnHostOverride = tostring(peerStreamConfig.turnHostOverride)
                end
                if peerStreamConfig.turnPortOverride and tostring(peerStreamConfig.turnPortOverride) ~= "" then
                    turnPortOverride = tostring(peerStreamConfig.turnPortOverride)
                end
            end

            local function urlEncode(value)
                if value == nil then
                    return ""
                end
                return tostring(value):gsub("([^%w%-_%.~])", function(c)
                    return string.format("%%%02X", string.byte(c))
                end)
            end

            local function getTurnUserId()
                if turnUserId ~= nil then
                    return turnUserId
                end
                local serverId = Config.serverId
                if serverId == nil or tostring(serverId) == "" then
                    serverId = GetConvar("sonoran_serverId", "server")
                end
                turnUserId = ("server-%s"):format(tostring(serverId))
                return turnUserId
            end

            local function buildTurnUrl()
                local base = getApiUrl()
                if base:sub(-1) ~= "/" then
                    base = base .. "/"
                end
                local communityId = urlEncode(Config.communityID)
                local apiKey = urlEncode(Config.apiKey)
                local userId = urlEncode(getTurnUserId())
                return ("%sapi/turn?id=%s&key=%s&userId=%s"):format(base, communityId, apiKey, userId)
            end

            local function replaceUrlHost(url)
                if type(url) ~= "string" then
                    return url
                end
                if not turnHostOverride and not turnPortOverride then
                    return url
                end
                local scheme, rest = url:match("^(%w+):(.*)$")
                if not scheme or not rest then
                    return url
                end
                local prefix = ""
                if rest:sub(1, 2) == "//" then
                    prefix = "//"
                    rest = rest:sub(3)
                end
                local hostPort, query = rest:match("^([^?]+)(.*)$")
                if not hostPort then
                    return url
                end
                local host, port = hostPort:match("^([^:]+):?(%d*)$")
                if not host then
                    return url
                end
                if turnHostOverride and turnHostOverride ~= "" then
                    host = turnHostOverride
                end
                if turnPortOverride and turnPortOverride ~= "" then
                    port = turnPortOverride
                end
                local hostOut = host
                if port and port ~= "" then
                    hostOut = hostOut .. ":" .. port
                end
                return scheme .. ":" .. prefix .. hostOut .. query
            end

            local function applyTurnOverrides(iceServers)
                if type(iceServers) ~= "table" then
                    return iceServers
                end
                for _, server in ipairs(iceServers) do
                    if type(server) == "table" and server.urls ~= nil then
                        if type(server.urls) == "string" then
                            server.urls = replaceUrlHost(server.urls)
                        elseif type(server.urls) == "table" then
                            local rewritten = {}
                            for _, url in ipairs(server.urls) do
                                table.insert(rewritten, replaceUrlHost(url))
                            end
                            server.urls = rewritten
                        end
                    end
                end
                return iceServers
            end

            local fetchTurnCredentials

            local function scheduleTurnRefresh()
                if turnCache.refreshTimerActive then
                    return
                end
                local ttl = tonumber(turnCache.ttl) or TURN_REFRESH_SECONDS
                local refreshSeconds = math.min(ttl, TURN_REFRESH_SECONDS)
                if refreshSeconds < TURN_MIN_REFRESH_SECONDS then
                    refreshSeconds = TURN_MIN_REFRESH_SECONDS
                end
                turnCache.refreshTimerActive = true
                SetTimeout(refreshSeconds * 1000, function()
                    turnCache.refreshTimerActive = false
                    -- Force refresh so credentials stay warm for reconnects.
                    fetchTurnCredentials(true)
                end)
            end

            fetchTurnCredentials = function(force, cb)
                if Config.critError then
                    if cb then
                        cb(false, nil)
                    end
                    return
                end
                if not Config.communityID or not Config.apiKey then
                    if cb then
                        cb(false, nil)
                    end
                    return
                end

                local now = os.time()
                if not force and turnCache.iceServers ~= nil and now < (turnCache.expiresAt - TURN_EXPIRY_BUFFER_SECONDS) then
                    if cb then
                        cb(true, turnCache)
                    end
                    return
                end

                if turnCache.fetching then
                    if cb then
                        table.insert(turnCache.waiters, cb)
                    end
                    return
                end

                turnCache.fetching = true
                local url = buildTurnUrl()
                PerformHttpRequest(url, function(statusCode, res, headers)
                    local ok = false
                    if statusCode == 200 and res and res ~= "" then
                        local parsed = json.decode(res)
                        if type(parsed) == "table" and type(parsed.iceServers) == "table" then
                            local ttl = tonumber(parsed.ttl) or TURN_REFRESH_SECONDS
                            if ttl < TURN_MIN_REFRESH_SECONDS then
                                ttl = TURN_MIN_REFRESH_SECONDS
                            end
                            turnCache.iceServers = applyTurnOverrides(parsed.iceServers)
                            turnCache.ttl = ttl
                            turnCache.expiresAt = os.time() + ttl
                            ok = true
                        end
                    end
                    turnCache.fetching = false
                    scheduleTurnRefresh()
                    local waiters = turnCache.waiters
                    turnCache.waiters = {}
                    for _, waiter in ipairs(waiters) do
                        waiter(ok, turnCache)
                    end
                    if cb then
                        cb(ok, turnCache)
                    end
                end, "GET", "", { ["X-User-Agent"] = "SonoranCAD" })
            end

            RegisterNetEvent("SonoranCAD::bodycam::RequestTurnCredentials", function(requestId)
                local src = source
                fetchTurnCredentials(false, function(ok, cache)
                    TriggerClientEvent("SonoranCAD::bodycam::TurnCredentials", src, requestId, {
                        ok = ok == true,
                        iceServers = cache and cache.iceServers or nil,
                        ttl = cache and cache.ttl or nil,
                        expiresAt = cache and cache.expiresAt or nil,
                        userId = getTurnUserId()
                    })
                end)
            end)

            CreateThread(function()
                -- attempt to fetch web_baseUrl
                local baseUrl = ''
                local counter = 0
                while baseUrl == '' do
                    Wait(1000)
                    baseUrl = GetConvar('web_baseUrl', '')

                    -- Every 60 seconds, log a warning
                    counter = counter + 1
                    if counter % 60 == 0 then
                        warnLog('Still waiting for web_baseUrl convar to be set...bodycam will not work until this is set.')
                    end
                end
                Config.proxyUrl = ('https://%s/sonorancad/'):format(GetConvar('web_baseUrl',''))
                debugLog(('Set proxyUrl to %s'):format(Config.proxyUrl))
                TriggerClientEvent('SonoranCAD::bodycam::Init', -1, 1, Config.apiVersion)
            end)
            RegisterCommand(pluginConfig.command, function(source, args, rawCommand)
                if Config.apiVersion < 4 then
                    errorLog('Bodycam is only enabled with SonoranCAD Pro.')
                    TriggerClientEvent('chat:addMessage', source, {
                        args = {
                            'Sonoran Bodycam',
                            'Bodycam is only enabled with SonoranCAD Pro.'
                        }
                    })
                    return
                end
                local unit = GetUnitByPlayerId(source)
                if unit == nil then
                    TriggerClientEvent('chat:addMessage', source, {
                        args = {
                            'Sonoran Bodycam',
                            'You must be onduty in CAD to use this command.'
                        }
                    })
                    return
                end
                if #args == 0 then
                    TriggerClientEvent('SonoranCAD::bodycam::CommandToggle', source)
                end
                if args[1] == 'freq' then
                    TriggerClientEvent('SonoranCAD::bodycam::SetScreenshotFrequency', source, args[2])
                elseif args[1] == 'sound' then
                    TriggerClientEvent('SonoranCAD::bodycam::SetSoundLevel', source, args[2])
                elseif args[1] == 'anim' then
                    TriggerClientEvent('SonoranCAD::bodycam::ToggleAnimation', source)
                elseif args[1] == 'overlay' then
                    TriggerClientEvent('SonoranCAD::bodycam::ToggleOverlay', source)
                end
            end, false)

            RegisterNetEvent('SonoranCAD::bodycam::Request', function()
                if not Config.proxyUrl or Config.proxyUrl == '' then
                    -- tell client we're not ready
                    TriggerClientEvent('SonoranCAD::bodycam::Init', source, 0, Config.apiVersion)
                else
                    -- tell client we're ready
                    if Config.apiVersion == -1 then
                        debugLog('API version not set, waiting for it to be set...')
                        while Config.apiVersion == -1 do Wait(1000) end
                    end
                    TriggerClientEvent('SonoranCAD::bodycam::Init', source, 1, Config.apiVersion)
                end
            end)

            RegisterNetEvent('SonoranCAD::core::PlayerReady', function()
                if not Config.proxyUrl or Config.proxyUrl == '' then
                    TriggerClientEvent('SonoranCAD::bodycam:Init', source, 0, Config.apiVersion)
                else
                    if Config.apiVersion == -1 then
                        debugLog('API Version not set, waiting for it to be set...')
                        while Config.apiVersion == -1 do Wait(1000) end
                    end
                    TriggerClientEvent('SonoranCAD::bodycam:Init', source, 0, Config.apiVersion)
                end
            end)

            RegisterNetEvent('SonoranCAD::bodycam::RequestSound', function()
                local source = source
                TriggerClientEvent('SonoranCAD::bodycam::GiveSound', -1, source, GetEntityCoords(GetPlayerPed(source)))
            end)
            RegisterNetEvent('SonoranCAD::bodycam::RequestToggle', function(manualActivation, toggle)
                if pluginConfig.requireUnitDuty then
                    local unit = GetUnitByPlayerId(source)
                    if not toggle then
                        TriggerClientEvent('SonoranCAD::bodycam::Toggle', source, manualActivation, false)
                        return
                    end
                    if unit == nil then
                        if manualActivation then
                            TriggerClientEvent('chat:addMessage', source, {
                                args = {
                                    'Sonoran Bodycam',
                                    'You must be onduty in CAD to use this command.'
                                }
                            })
                        end
                        return
                    end
                    TriggerClientEvent('SonoranCAD::bodycam::Toggle', source, manualActivation, toggle)
                else
                    TriggerClientEvent('SonoranCAD::bodycam::Toggle', source, manualActivation, toggle)
                end
            end)
        end
    end)
end)
