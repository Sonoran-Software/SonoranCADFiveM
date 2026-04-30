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
            local uploadTokenBySource = {}
            local uploadSourceByToken = {}
            local httpUploadSessions = {}

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

            local function randomTokenPart(length)
                local chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
                local out = {}
                for i = 1, length do
                    local idx = math.random(1, #chars)
                    out[i] = chars:sub(idx, idx)
                end
                return table.concat(out)
            end

            local function ensureUploadToken(src)
                if uploadTokenBySource[src] ~= nil then
                    return uploadTokenBySource[src]
                end
                local token = ('bodycam-%s-%s-%s'):format(tostring(src), tostring(os.time()), randomTokenPart(24))
                uploadTokenBySource[src] = token
                uploadSourceByToken[token] = src
                return token
            end

            local function clearUploadToken(src)
                local token = uploadTokenBySource[src]
                if token ~= nil then
                    uploadSourceByToken[token] = nil
                    uploadTokenBySource[src] = nil
                end
            end

            local function sendBodycamUploadConfig(target)
                TriggerClientEvent('SonoranCAD::bodycam::UploadConfig', target, Config.proxyUrl, ensureUploadToken(target))
            end

            local function decodeUploadMetadata(rawMetadata)
                if type(rawMetadata) ~= 'string' or rawMetadata == '' then
                    return {}
                end
                local ok, decoded = pcall(json.decode, rawMetadata)
                if ok and type(decoded) == 'table' then
                    return decoded
                end
                return {}
            end

            local function cleanupHttpUploadSession(uploadId)
                local session = uploadId and httpUploadSessions[uploadId] or nil
                if session and session.filePath then
                    os.remove(session.filePath)
                end
                if uploadId then
                    httpUploadSessions[uploadId] = nil
                end
            end

            local function validateUploadToken(params, routePath)
                local token = params and params.token or nil
                local src = token and uploadSourceByToken[token] or nil
                if src == nil then
                    warnLog(('Bodycam upload rejected: invalid token path=%s token=%s'):format(
                        tostring(routePath or '/bodycam-upload'),
                        tostring(token or 'nil')
                    ))
                end
                return src
            end

            local function sendBodycamHttpResponse(res, statusCode, payload)
                res.writeHead(statusCode, {
                    ['Content-Type'] = 'application/json; charset=utf-8',
                    ['Access-Control-Allow-Origin'] = '*',
                    ['Access-Control-Allow-Methods'] = 'POST, OPTIONS',
                    ['Access-Control-Allow-Headers'] = 'Content-Type'
                })
                if statusCode == 204 then
                    res.send('')
                    return
                end
                res.send(json.encode(payload or {}))
            end

            RegisterPluginHttpRoute('OPTIONS', '/bodycam-upload/init', function(_, res)
                debugLog('Bodycam upload init route OPTIONS preflight received.')
                sendBodycamHttpResponse(res, 204, {})
            end)

            RegisterPluginHttpRoute('OPTIONS', '/bodycam-upload/chunk', function(_, res)
                debugLog('Bodycam upload chunk route OPTIONS preflight received.')
                sendBodycamHttpResponse(res, 204, {})
            end)

            RegisterPluginHttpRoute('OPTIONS', '/bodycam-upload/complete', function(_, res)
                debugLog('Bodycam upload complete route OPTIONS preflight received.')
                sendBodycamHttpResponse(res, 204, {})
            end)

            RegisterPluginHttpRoute('POST', '/bodycam-upload/init', function(_, res, body, params, routePath)
                local src = validateUploadToken(params, routePath)
                debugLog(('Bodycam upload init received: path=%s src=%s fileName=%s totalChunks=%s'):format(
                    tostring(routePath or '/bodycam-upload'),
                    tostring(src or 'nil'),
                    tostring(params and params.fileName or 'nil'),
                    tostring(params and params.totalChunks or 'nil')
                ))
                if src == nil then
                    sendBodycamHttpResponse(res, 401, {
                        ok = false,
                        reason = 'invalid_upload_token'
                    })
                    return
                end

                local totalChunks = tonumber(params and params.totalChunks or 0) or 0
                if totalChunks < 1 then
                    sendBodycamHttpResponse(res, 400, {
                        ok = false,
                        reason = 'invalid_total_chunks'
                    })
                    return
                end

                local uploadId = ('chunked-%s-%s-%s'):format(tostring(src), tostring(os.time()), randomTokenPart(8))
                local fileName = params and params.fileName or ('bodycam-%s.webm'):format(os.time())
                local filePath = exports[GetCurrentResourceName()]:CreateTempBodycamRecordingFile(uploadId, fileName)
                if type(filePath) ~= 'string' or filePath == '' then
                    errorLog(('Bodycam upload temp file creation failed: uploadId=%s fileName=%s'):format(
                        tostring(uploadId),
                        tostring(fileName)
                    ))
                    sendBodycamHttpResponse(res, 500, {
                        ok = false,
                        reason = 'temp_file_create_failed'
                    })
                    return
                end

                httpUploadSessions[uploadId] = {
                    src = src,
                    uploadId = uploadId,
                    fileName = fileName,
                    filePath = filePath,
                    totalChunks = totalChunks,
                    receivedChunks = 0,
                    durationMs = tonumber(params and params.durationMs or 0) or 0,
                    size = tonumber(params and params.size or 0) or 0,
                    sourceType = params and params.sourceType or 'manual',
                    trigger = params and params.trigger or nil,
                    stopReason = params and params.stopReason or nil,
                    metadata = decodeUploadMetadata(params and params.metadata or nil)
                }

                sendBodycamHttpResponse(res, 202, {
                    ok = true,
                    uploadId = uploadId
                })
            end)

            RegisterPluginHttpRoute('POST', '/bodycam-upload/chunk', function(_, res, body, params, routePath)
                local src = validateUploadToken(params, routePath)
                local uploadId = params and params.uploadId or nil
                local session = uploadId and httpUploadSessions[uploadId] or nil
                local chunkIndex = tonumber(params and params.chunkIndex or 0) or 0
                debugLog(('Bodycam upload chunk received: path=%s src=%s uploadId=%s chunkIndex=%s bodyBytes=%s'):format(
                    tostring(routePath or '/bodycam-upload/chunk'),
                    tostring(src or 'nil'),
                    tostring(uploadId or 'nil'),
                    tostring(chunkIndex),
                    tostring(type(body) == 'string' and #body or 0)
                ))
                if src == nil then
                    sendBodycamHttpResponse(res, 401, {
                        ok = false,
                        reason = 'invalid_upload_token'
                    })
                    return
                end
                if session == nil or session.src ~= src then
                    sendBodycamHttpResponse(res, 404, {
                        ok = false,
                        reason = 'unknown_upload'
                    })
                    return
                end
                if type(body) ~= 'string' or body == '' then
                    sendBodycamHttpResponse(res, 400, {
                        ok = false,
                        reason = 'missing_body'
                    })
                    return
                end

                local fileHandle = io.open(session.filePath, 'ab')
                if not fileHandle then
                    cleanupHttpUploadSession(uploadId)
                    errorLog(('Bodycam upload temp file append failed: uploadId=%s filePath=%s'):format(
                        tostring(uploadId),
                        tostring(session.filePath)
                    ))
                    sendBodycamHttpResponse(res, 500, {
                        ok = false,
                        reason = 'temp_file_open_failed'
                    })
                    return
                end
                fileHandle:write(body)
                fileHandle:close()

                session.receivedChunks = session.receivedChunks + 1
                sendBodycamHttpResponse(res, 202, {
                    ok = true,
                    uploadId = uploadId,
                    receivedChunks = session.receivedChunks
                })
            end)

            RegisterPluginHttpRoute('POST', '/bodycam-upload/complete', function(_, res, _, params, routePath)
                local src = validateUploadToken(params, routePath)
                local uploadId = params and params.uploadId or nil
                local session = uploadId and httpUploadSessions[uploadId] or nil
                debugLog(('Bodycam upload complete received: path=%s src=%s uploadId=%s receivedChunks=%s/%s'):format(
                    tostring(routePath or '/bodycam-upload/complete'),
                    tostring(src or 'nil'),
                    tostring(uploadId or 'nil'),
                    tostring(session and session.receivedChunks or 'nil'),
                    tostring(session and session.totalChunks or 'nil')
                ))
                if src == nil then
                    sendBodycamHttpResponse(res, 401, {
                        ok = false,
                        reason = 'invalid_upload_token'
                    })
                    return
                end
                if session == nil or session.src ~= src then
                    sendBodycamHttpResponse(res, 404, {
                        ok = false,
                        reason = 'unknown_upload'
                    })
                    return
                end
                if session.receivedChunks ~= session.totalChunks then
                    cleanupHttpUploadSession(uploadId)
                    sendBodycamHttpResponse(res, 400, {
                        ok = false,
                        reason = 'incomplete_upload',
                        receivedChunks = session.receivedChunks,
                        totalChunks = session.totalChunks
                    })
                    return
                end

                httpUploadSessions[uploadId] = nil
                TriggerEvent('SonoranCAD::bodycam::UploadSavedRecording', src, {
                    uploadId = uploadId,
                    fileName = session.fileName,
                    durationMs = session.durationMs,
                    size = session.size,
                    sourceType = session.sourceType,
                    trigger = session.trigger,
                    stopReason = session.stopReason,
                    metadata = session.metadata
                }, session.filePath)

                sendBodycamHttpResponse(res, 202, {
                    ok = true,
                    uploadId = uploadId
                })
            end)

            local function getTurnUserId()
                if turnUserId ~= nil then
                    return turnUserId
                end
                local serverId = tonumber(Config.serverId)
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
                local userId = urlEncode(getTurnUserId())
                return ("%sv2/general/turn?userId=%s"):format(base, userId)
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
                end, "GET", "", {
                    ["X-User-Agent"] = "SonoranCAD",
                    ["Authorization"] = "Bearer " .. tostring(Config.apiKey)
                })
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
                TriggerClientEvent('SonoranCAD::bodycam::Init', -1, 1, Config.apiVersion, Config.proxyUrl, nil)
                for _, playerId in ipairs(GetPlayers()) do
                    sendBodycamUploadConfig(tonumber(playerId))
                end
            end)
            RegisterCommand(pluginConfig.command, function(source, args, rawCommand)
                if pluginConfig.forceOffAce == nil then
                    pluginConfig.forceOffAce = "sonorancad.bodycam.forceoff"
                end
                if #args == 0 then
                    if pluginConfig.requireUnitDuty then
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
                    end
                    TriggerClientEvent('SonoranCAD::bodycam::CommandToggle', source)
                elseif args[1] == 'sound' then
                    TriggerClientEvent('SonoranCAD::bodycam::SetSoundLevel', source, args[2])
                elseif args[1] == 'anim' then
                    TriggerClientEvent('SonoranCAD::bodycam::ToggleAnimation', source)
                elseif args[1] == 'overlay' then
                    TriggerClientEvent('SonoranCAD::bodycam::ToggleOverlay', source)
                elseif args[1] == 'forceoff' then
                    if source ~= 0 and pluginConfig.forceOffAce ~= "" then
                        if not IsPlayerAceAllowed(source, pluginConfig.forceOffAce) then
                            TriggerClientEvent('chat:addMessage', source, {
                                args = {
                                    'Sonoran Bodycam',
                                    'You do not have permission to use forceoff.'
                                }
                            })
                            return
                        end
                    end
                    TriggerClientEvent('SonoranCAD::bodycam::Toggle', source, true, false, true)
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
                    local uploadToken = ensureUploadToken(source)
                    TriggerClientEvent('SonoranCAD::bodycam::Init', source, 1, Config.apiVersion, Config.proxyUrl, uploadToken)
                    sendBodycamUploadConfig(source)
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

            AddEventHandler('SonoranCAD::pushevents:UnitPanic', function(unit, identId, isPanic)
                if not isPanic or not unit then
                    return
                end
                local player = GetSourceByCadIdentity(GetUnitIdentityValues(unit))
                if player then
                    TriggerClientEvent('SonoranCAD::bodycam::AutoRecordTrigger', player, 'panic')
                end
            end)

            RegisterNetEvent('SonoranCAD::bodycam::RequestToggle', function(manualActivation, toggle)
                local unit = GetUnitByPlayerId(source)

                if not toggle then
                    TriggerClientEvent('SonoranCAD::bodycam::Toggle', source, manualActivation, false)
                    return
                end

                if pluginConfig.requireUnitDuty and unit == nil then
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
            end)

            AddEventHandler('playerDropped', function()
                for uploadId, session in pairs(httpUploadSessions) do
                    if session and session.src == source then
                        cleanupHttpUploadSession(uploadId)
                    end
                end
                clearUploadToken(source)
            end)
        end
    end)
end)
