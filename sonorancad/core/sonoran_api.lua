local cadV2Client = nil
local sonoranModule = nil
local communityLinkCheckCache = {}
local COMMUNITY_LINK_CHECK_CACHE_TTL_MS = 10 * 60 * 1000

local function load_sonoran_module()
    if sonoranModule ~= nil then
        return sonoranModule
    end

    local resource_name = GetCurrentResourceName and GetCurrentResourceName() or "sonorancad"
    local source = LoadResourceFile(resource_name, "lua/sonoran/init.lua")
    if not source then
        error("Unable to load lua/sonoran/init.lua")
    end

    local chunk, load_error = load(source, ("@@%s/%s"):format(resource_name, "lua/sonoran/init.lua"))
    if not chunk then
        error(load_error)
    end

    local loaded = chunk()
    if type(loaded) ~= "table" or type(loaded.createClient) ~= "function" then
        error("Sonoran client module did not return a valid client factory.")
    end

    sonoranModule = loaded
    return sonoranModule
end

local function resolve_api_url()
    if type(Config.apiUrl) == "string" and Config.apiUrl ~= "" then
        return Config.apiUrl
    end
    if Config.mode == "development" then
        return "https://staging-api.dev.sonorancad.com/"
    end
    return "https://api.sonorancad.com/"
end

local function get_cad_client()
    if cadV2Client ~= nil then
        return cadV2Client
    end

    local sonoran = nil
    if type(Sonoran) == "table" and type(Sonoran.createClient) == "function" then
        sonoran = Sonoran
    else
        sonoran = load_sonoran_module()
    end

    cadV2Client = sonoran.createClient({
        product = sonoran.productEnums and sonoran.productEnums.CAD or 0,
        apiKey = Config.apiKey,
        communityId = Config.communityID,
        apiUrl = resolve_api_url(),
        defaultServerId = tonumber(tonumber(Config.serverId)) or 1,
        setLogLevel = Config.debug and sonoran.logLevels.DEBUG or sonoran.logLevels.OFF
    })

    return cadV2Client
end

function GetCadClient()
    return get_cad_client()
end
exports("getCadClient", GetCadClient)

function registerApiType(_, endpoint)
    return endpoint
end
exports("registerApiType", registerApiType)

local legacyApiHandlers = {}

local function response_with_data(response, data)
    if response and response.success then
        response.data = data
    end
    return response
end

local function reason_from_http(status_code, body, content_type)
    return {
        status = tonumber(status_code) or 0,
        body = body,
        contentType = content_type
    }
end

local function unwrap_named_collection(data, key)
    if type(data) == "table" and type(data[key]) == "table" then
        return data[key]
    end
    return data
end

local function normalize_server_collection(data)
    if type(data) == "table" and data.servers ~= nil then
        return data
    end
    if type(data) == "table" and #data > 0 then
        return {servers = data}
    end
    return data
end

local function payload_preview(value)
    if value == nil then
        return "{}"
    end
    if type(value) == "string" then
        return value
    end
    local ok, encoded = pcall(json.encode, value)
    if ok and encoded ~= nil then
        return encoded
    end
    return tostring(value)
end

local function clone_table(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = entry
    end
    return copy
end

local function get_cache_time_ms()
    if type(GetGameTimer) == "function" then
        return GetGameTimer()
    end
    return math.floor(os.time() * 1000)
end

local function get_community_link_cache_key(payload)
    if type(payload) ~= "table" then
        return tostring(payload)
    end

    local community_user_id = payload.communityUserId or ""
    local account_uuid = payload.accountUuid or payload.accountId or payload.uuid or ""
    local code = payload.code or payload.linkCode or payload.link_code or ""
    if community_user_id ~= "" or account_uuid ~= "" or code ~= "" then
        return ("%s|%s|%s"):format(tostring(community_user_id), tostring(account_uuid), tostring(code))
    end

    return payload_preview(payload)
end

local function clone_api_response(response)
    if type(response) ~= "table" then
        return response
    end

    local copy = clone_table(response)
    if type(response.data) == "table" then
        copy.data = clone_table(response.data)
    end
    if type(response.reason) == "table" then
        copy.reason = clone_table(response.reason)
    end
    return copy
end

local function read_cached_community_link_response(payload, ttl_ms)
    local cache_key = get_community_link_cache_key(payload)
    local cached = communityLinkCheckCache[cache_key]
    if type(cached) ~= "table" or type(cached.cachedAt) ~= "number" then
        return nil
    end

    if (get_cache_time_ms() - cached.cachedAt) >= ttl_ms then
        return nil
    end

    return clone_api_response(cached.response)
end

local function write_cached_community_link_response(payload, response)
    communityLinkCheckCache[get_community_link_cache_key(payload)] = {
        cachedAt = get_cache_time_ms(),
        response = clone_api_response(response)
    }
end

function CadApiReasonText(value)
    if type(value) == "string" then
        return value
    end
    if value == nil then
        return "Unknown API error."
    end
    local ok, encoded = pcall(json.encode, value)
    if ok and encoded ~= nil then
        return encoded
    end
    return tostring(value)
end

function CadApiLogFailure(request_name, response, payload)
    errorLog(("CAD API ERROR (%s): %s payload=%s"):format(
        tostring(request_name),
        CadApiReasonText(response and response.reason),
        payload_preview(payload)
    ))
end

local function get_v2_response_id(data)
    if type(data) ~= "table" then
        return nil
    end
    return data.id or data.callId or data.recordId or data.dispatchCallId
end

local function get_legacy_request_payload(data)
    if type(data) ~= "table" then
        return {}
    end

    if data[1] ~= nil and type(data[1]) == "table" then
        return clone_table(data[1])
    end

    return clone_table(data)
end

local function get_legacy_request_payloads(data)
    if type(data) ~= "table" then
        return {}
    end

    if data[1] ~= nil then
        return data
    end

    return {clone_table(data)}
end

local function format_legacy_success(response)
    local payload = response and response.data

    if type(payload) == "table" then
        payload = clone_table(payload)
    elseif payload == nil then
        payload = {}
    end

    if type(payload) == "table" then
        if response.callId ~= nil and payload.callId == nil then
            payload.callId = response.callId
        end
        if response.recordId ~= nil and payload.recordId == nil then
            payload.recordId = response.recordId
        end
    end

    return payload
end

local function invoke_legacy_handler(request_type, data)
    local handler = legacyApiHandlers[tostring(request_type or ""):upper()]
    if handler == nil then
        return {
            success = false,
            reason = ("Unsupported legacy API request type: %s"):format(tostring(request_type))
        }
    end

    local ok, response = pcall(handler, data)
    if not ok then
        return {
            success = false,
            reason = response
        }
    end

    return response
end

local function isCallbackValid(value)
    if type(value) == "function" then return true end
    if type(value) == "table" and rawget(value, "__cfx_functionReference") then return true end

    return false
end

function performApiRequest(data, request_type, callback)
    local response = invoke_legacy_handler(request_type, data)

    if isCallbackValid(callback) then
        if response and response.success then
            callback(format_legacy_success(response), true, response)
        else
            callback(CadApiReasonText(response and response.reason), false, response)
        end
    end

    return response
end
exports("performApiRequest", performApiRequest)

function CadApiResolveCommunityUserId(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    if GetCommunityUserIdFromIdentifier == nil then
        return nil
    end
    return GetCommunityUserIdFromIdentifier(value)
end

function CadApiResolveCommunityUserIds(values)
    local resolved = {}
    for _, value in ipairs(values or {}) do
        local resolved_value = CadApiResolveCommunityUserId(value) or value
        if resolved_value ~= nil and resolved_value ~= "" then
            table.insert(resolved, resolved_value)
        end
    end
    return resolved
end

function CadApiRequireCommunityUserId(value)
    local resolved = CadApiResolveCommunityUserId(value) or value
    if type(resolved) ~= "string" or resolved == "" then
        return nil, "Player is not linked to CAD."
    end
    return resolved
end

local function resolve_account_selector(payload, community_user_id_value)
    local query = {
        accountUuid = payload.accountUuid or payload.accountId or payload.uuid,
        username = payload.username
    }

    if community_user_id_value ~= nil then
        local resolved, err = CadApiRequireCommunityUserId(community_user_id_value)
        if resolved == nil then
            return nil, err
        end
        query.communityUserId = resolved
    end

    return query
end

function CadApiGetVersion()
    local response = get_cad_client():getVersionV2()
    if not response.success then
        return response
    end

    local version_data = response.data
    if type(version_data) == "table" then
        version_data = version_data.version or version_data.apiVersion or version_data.major or version_data[1]
    end
    return response_with_data(response, tostring(version_data or 0))
end

function CadApiGetServers()
    local response = get_cad_client():getServersV2()
    if not response.success then
        return response
    end
    return response_with_data(response, normalize_server_collection(response.data))
end

function CadApiSetServers(payload)
    local servers = payload
    if type(servers) == "table" and servers.servers ~= nil then
        servers = servers.servers
    end
    return get_cad_client():setServersV2(servers or {}, false)
end

function CadApiHeartbeat(payload)
    payload = payload or {}
    return get_cad_client():heartbeatV2(payload.serverId or tonumber(Config.serverId), payload.playerCount or 0)
end

function CadApiSetPostals(postals)
    return get_cad_client():setPostalsV2(postals)
end

function CadApiGetCharacters(payload)
    payload = payload or {}
    local query = {
        accountUuid = payload.accountUuid or payload.accountId or payload.uuid
    }
    if payload.communityUserId ~= nil or payload.user ~= nil then
        local resolved, err = CadApiRequireCommunityUserId(payload.communityUserId or payload.user)
        if resolved == nil then
            return {success = false, reason = err}
        end
        query.communityUserId = resolved
    end

    local response = get_cad_client():getCharactersV2(query)
    if not response.success then
        return response
    end
    return response_with_data(response, unwrap_named_collection(response.data or {}, "characters") or {})
end

function CadApiSetUnitStatus(payload)
    payload = payload or {}
    local community_user_id, err = CadApiRequireCommunityUserId(payload.communityUserId)
    if community_user_id == nil then
        return {success = false, reason = err}
    end
    payload.communityUserId = community_user_id
    return get_cad_client():setUnitStatusV2(payload)
end

function CadApiSetUnitPanic(payload)
    payload = payload or {}
    local community_user_id, err = CadApiRequireCommunityUserId(payload.communityUserId)
    if community_user_id == nil then
        return {success = false, reason = err}
    end
    payload.communityUserId = community_user_id
    return get_cad_client():setUnitPanicV2(payload)
end

function CadApiKickUnits(payload)
    local community_user_id, err = CadApiRequireCommunityUserId(payload.communityUserId)
    if community_user_id == nil then
        return {success = false, reason = err}
    end
    payload.communityUserId = community_user_id
    local response = get_cad_client():kickUnitV2(payload)
    if not response.success then
        return response
    end
    return {success = true, data = {ok = true}}
end

function CadApiGetActiveUnits(payload)
    payload = payload or {}
    local response = get_cad_client():getUnitsV2({
        serverId = payload.serverId or tonumber(Config.serverId),
        onlyUnits = payload.unitsOnly,
        includeOffline = payload.includeOffline
    })
    if not response.success then
        return response
    end
    return response_with_data(response, unwrap_named_collection(response.data or {}, "units") or {})
end

function CadApiGetCalls(payload)
    payload = payload or {}
    local response = get_cad_client():getCallsV2({
        serverId = payload.serverId or tonumber(Config.serverId),
        type = payload.type,
        closedLimit = payload.closedLimit,
        closedOffset = payload.closedOffset
    })
    if not response.success then
        return response
    end
    return response_with_data(response, response.data or {})
end

local function normalize_emergency_call_payload(payload)
    payload = payload or {}

    local normalized = {}
    for key, value in pairs(payload) do
        normalized[key] = value
    end

    normalized.serverId = normalized.serverId or tonumber(Config.serverId)
    normalized.isEmergency = normalized.isEmergency == true
    normalized.caller = tostring(normalized.caller or "")
    normalized.location = tostring(normalized.location or "Unknown")
    normalized.description = tostring(normalized.description or "")

    if normalized.deleteAfterMinutes == nil and normalized.deleteAfter ~= nil then
        normalized.deleteAfterMinutes = normalized.deleteAfter
    end
    normalized.deleteAfter = nil

    local metaData = {}
    if type(normalized.metaData) == "table" then
        for key, value in pairs(normalized.metaData) do
            metaData[key] = value
        end
    end

    if type(normalized.coords) == "table" then
        if metaData.x == nil then metaData.x = normalized.coords.x end
        if metaData.y == nil then metaData.y = normalized.coords.y end
        if metaData.z == nil then metaData.z = normalized.coords.z end
    end
    normalized.coords = nil

    if metaData.silentAlert == nil and metaData.silenceAlert ~= nil then
        metaData.silentAlert = metaData.silenceAlert
    end
    metaData.silenceAlert = nil

    if metaData.useCallLocation == nil then
        metaData.useCallLocation = false
    end
    if metaData.silentAlert == nil then
        metaData.silentAlert = false
    end
    if metaData.postal == nil then
        metaData.postal = ""
    end
    if metaData.plate == nil then
        metaData.plate = ""
    end

    normalized.metaData = metaData
    return normalized
end

function CadApiCreateEmergencyCall(payload)
    local normalized_payload = normalize_emergency_call_payload(payload)
    local response = get_cad_client():createEmergencyCallV2(normalized_payload)
    if response.success then
        response.callId = get_v2_response_id(response.data)
    end
    return response
end

function CadApiDeleteEmergencyCall(call_id, server_id)
    return get_cad_client():deleteEmergencyCallV2(call_id, server_id or tonumber(Config.serverId))
end

function CadApiCreateDispatchCall(payload)
    payload = payload or {}
    payload.units = CadApiResolveCommunityUserIds(payload.units or {})
    local response = get_cad_client():createDispatchCallV2(payload)
    if response.success then
        response.callId = get_v2_response_id(response.data)
    end
    return response
end

function CadApiAttachUnitsToDispatchCall(payload)
    payload = payload or {}
    local call_id = payload.callId
    local request_payload = {}
    for key, value in pairs(payload) do
        if key ~= "callId" then
            request_payload[key] = value
        end
    end
    request_payload.units = CadApiResolveCommunityUserIds(request_payload.units or {})
    return get_cad_client():attachUnitsToDispatchCallV2(call_id, request_payload)
end

function CadApiDetachUnitsFromDispatchCall(payload)
    payload = payload or {}
    payload.units = CadApiResolveCommunityUserIds(payload.units or {})
    return get_cad_client():detachUnitsFromDispatchCallV2(payload)
end

function CadApiAddDispatchNote(payload)
    payload = payload or {}
    local call_id = payload.callId
    local request_payload = {}
    for key, value in pairs(payload) do
        if key ~= "callId" then
            request_payload[key] = value
        end
    end
    return get_cad_client():addDispatchNoteV2(call_id, request_payload)
end

function CadApiSetDispatchPostal(payload)
    payload = payload or {}
    return get_cad_client():setDispatchPostalV2(payload.callId, payload.postal, payload.serverId or tonumber(Config.serverId))
end

function CadApiLookup(payload)
    payload = payload or {}

    local request_payload = {
        types = payload.types or {2, 3, 4, 5},
        plate = tostring(payload.plate or ""),
        partial = payload.partial == true,
        first = tostring(payload.first or ""),
        last = tostring(payload.last or ""),
        mi = tostring(payload.mi or ""),
    }

    if payload.notifyCommunityUserId ~= nil and tostring(payload.notifyCommunityUserId) ~= "" then
        request_payload.notifyCommunityUserId = tostring(payload.notifyCommunityUserId)
    elseif payload.apiId ~= nil and tostring(payload.apiId) ~= "" then
        request_payload.notifyCommunityUserId = tostring(payload.apiId)
    end
    if payload.account ~= nil and tostring(payload.account) ~= "" then
        request_payload.account = tostring(payload.account)
    end
    if payload.agency ~= nil and tostring(payload.agency) ~= "" then
        request_payload.agency = tostring(payload.agency)
    end
    if payload.department ~= nil and tostring(payload.department) ~= "" then
        request_payload.department = tostring(payload.department)
    end
    if payload.subdivision ~= nil and tostring(payload.subdivision) ~= "" then
        request_payload.subdivision = tostring(payload.subdivision)
    end
    return get_cad_client():lookupV2(request_payload)
end

function CadApiLookupByValue(payload)
    payload = payload or {}
    if payload.communityUserId ~= nil then
        local resolved, err = CadApiRequireCommunityUserId(payload.communityUserId)
        if resolved == nil then
            return {success = false, reason = err}
        end
        payload.communityUserId = resolved
    end
    return get_cad_client():lookupByValueV2(payload)
end

function CadApiCreateRecord(payload)
    payload = payload or {}
    if payload.user ~= nil and payload.user ~= "" then
        local resolved_user = CadApiResolveCommunityUserId(payload.user)
        if resolved_user ~= nil then
            payload.user = resolved_user
        end
    end
    local response = get_cad_client():createRecordV2(payload)
    if response.success then
        response.recordId = get_v2_response_id(response.data)
    end
    return response
end

function CadApiGetAccount(payload)
    payload = payload or {}
    local query, err = resolve_account_selector(payload, payload.communityUserId or payload.user)
    if query == nil then
        return {success = false, reason = err}
    end
    return get_cad_client():getAccountV2(query)
end

function CadApiGetAccounts(payload)
    payload = payload or {}
    return get_cad_client():getAccountsV2({
        limit = payload.limit,
        offset = payload.offset,
        status = payload.status,
        username = payload.username
    })
end

function CadApiSetAccountPermissions(payload)
    payload = payload or {}
    local request_payload, err = resolve_account_selector(payload, payload.communityUserId or payload.user)
    if request_payload == nil then
        return {success = false, reason = err}
    end
    request_payload.add = payload.add
    request_payload.remove = payload.remove
    request_payload.active = payload.active
    return get_cad_client():setAccountPermissionsV2(request_payload)
end

function CadApiSetApiIds(payload)
    payload = payload or {}
    local request_payload, err = resolve_account_selector(payload, payload.communityUserId or payload.user)
    if request_payload == nil then
        return {success = false, reason = err}
    end
    request_payload.apiIds = payload.apiIds
    request_payload.pushNew = payload.pushNew
    return get_cad_client():setApiIdsV2(request_payload)
end

function CadApiVerifySecret(secret)
    return get_cad_client():verifySecretV2(secret)
end

function CadApiSendPhoto(payload)
    payload = payload or {}
    local community_user_id, err = CadApiRequireCommunityUserId(payload.communityUserId or payload.user or payload.apiId)
    if community_user_id == nil then
        return {success = false, reason = err}
    end
    return get_cad_client():sendPhotoV2({
        communityUserId = community_user_id,
        url = payload.url
    })
end

function CadApiAuthorizeStreetSigns(server_id)
    return get_cad_client():authorizeStreetSignsV2(server_id or tonumber(Config.serverId))
end

function CadApiGetCurrentCall(payload)
    payload = payload or {}
    return get_cad_client():getCurrentCallV2(payload.accountUuid or payload.accountId or payload.uuid)
end

function CadApiGetIdentifiers(payload)
    payload = payload or {}
    local response = get_cad_client():getIdentifiersV2(payload.accountUuid or payload.accountId or payload.uuid)
    if not response.success then
        return response
    end
    return response_with_data(response, unwrap_named_collection(response.data or {}, "identifiers") or {})
end

function CadApiGetAccountUnits(payload)
    payload = payload or {}
    local response = get_cad_client():getAccountUnitsV2({
        serverId = payload.serverId or tonumber(Config.serverId),
        accountUuid = payload.accountUuid or payload.accountId or payload.uuid,
        onlyOnline = payload.onlyOnline,
        onlyUnits = payload.onlyUnits,
        limit = payload.limit,
        offset = payload.offset
    })
    if not response.success then
        return response
    end
    return response_with_data(response, unwrap_named_collection(response.data or {}, "units") or {})
end

function CadApiGetTemplates(payload)
    payload = payload or {}
    return get_cad_client():getTemplatesV2(payload.recordTypeId)
end

function CadApiSetAvailableCallouts(payload)
    local callouts = payload
    if type(callouts) == "table" and callouts.callouts ~= nil then
        callouts = callouts.callouts
    end
    return get_cad_client():setAvailableCalloutsV2(callouts or {}, tonumber(Config.serverId))
end

function CadApiSetStations(payload)
    payload = payload or {}
    local config = payload.config or payload

    if type(config) == "string" and config ~= "" then
        local ok, decoded = pcall(json.decode, config)
        if ok and type(decoded) == "table" then
            config = decoded
        end
    end

    if type(config) == "table" and config[1] ~= nil and type(config[1]) == "table" and config.locations == nil then
        config = clone_table(config[1])
    end

    return get_cad_client():setStationsV2(config, payload.serverId or tonumber(Config.serverId))
end

function CadApiGetBlips(payload)
    local server_id = payload
    if type(payload) == "table" then
        server_id = payload.serverId
    end
    local response = get_cad_client():getBlipsV2(server_id or tonumber(Config.serverId))
    if not response.success then
        return response
    end
    return response_with_data(response, unwrap_named_collection(response.data or {}, "blips") or {})
end

function CadApiCreateBlips(payloads)
    local created = {}
    for _, payload in ipairs(payloads or {}) do
        local response = get_cad_client():createBlipV2(payload)
        if not response.success then
            return response
        end
        created[#created + 1] = response.data
    end
    return {success = true, data = created}
end

function CadApiUpdateBlips(payloads)
    for _, payload in ipairs(payloads or {}) do
        local blip_id = payload.id or (payload.blip and payload.blip.id)
        local update = {}
        for key, value in pairs(payload) do
            if key ~= "id" and key ~= "serverId" and key ~= "blip" then
                update[key] = value
            end
        end
        local response = get_cad_client():updateBlipV2(blip_id, {
            serverId = payload.serverId or tonumber(Config.serverId),
            subType = update.subType,
            coordinates = update.coordinates,
            radius = update.radius,
            icon = update.icon,
            color = update.color,
            tooltip = update.tooltip,
            data = update.data
        })
        if not response.success then
            return response
        end
    end
    return {success = true, data = {ok = true}}
end

function CadApiDeleteBlips(ids, server_id)
    local blip_ids = ids
    local resolved_server_id = server_id or tonumber(Config.serverId)
    if type(ids) == "table" and ids.ids ~= nil then
        blip_ids = ids.ids
        resolved_server_id = ids.serverId or resolved_server_id
    end
    return get_cad_client():deleteBlipsV2(blip_ids or {}, resolved_server_id)
end

function CadApiApplyPermissionKey(payload)
    return get_cad_client():applyPermissionKeyV2(payload or {})
end

function CadApiBanUser(payload)
    return get_cad_client():banUserV2(payload or {})
end

function CadApiUploadSupportLogs(payload)
    local request_payload = {
        id = Config.communityID,
        key = Config.apiKey,
        data = {payload},
        type = "UPLOAD_LOGS"
    }
    local url = "https://api.sonoransoftware.com/support/"
    local response_body = nil
    local response_status = nil

    PerformHttpRequestS(url, function(status_code, res)
        response_status = status_code
        response_body = res
    end, "POST", json.encode(request_payload), {["Content-Type"] = "application/json"})

    if tonumber(response_status) == 200 and response_body ~= nil then
        return {success = true, data = response_body}
    end

    return {
        success = false,
        reason = reason_from_http(response_status, response_body, "application/json")
    }
end

function CadApiCreateCommunityLink(payload)
    return get_cad_client():createCommunityLinkV2(payload)
end

function CadApiCheckCommunityLink(payload, options)
    payload = payload or {}
    options = options or {}

    local ttl_ms = tonumber(options.ttlMs) or COMMUNITY_LINK_CHECK_CACHE_TTL_MS
    if ttl_ms < 0 then
        ttl_ms = 0
    end

    if options.forceRefresh ~= true and ttl_ms > 0 then
        local cached = read_cached_community_link_response(payload, ttl_ms)
        if cached ~= nil then
            return cached
        end
    end

    local response = get_cad_client():checkCommunityLinkV2(payload)
    if ttl_ms > 0 then
        write_cached_community_link_response(payload, response)
    end

    return response
end

legacyApiHandlers = {
    GET_VERSION = function()
        return CadApiGetVersion()
    end,
    GET_SERVERS = function()
        return CadApiGetServers()
    end,
    SET_SERVERS = function(data)
        return CadApiSetServers(get_legacy_request_payload(data))
    end,
    HEARTBEAT = function(data)
        return CadApiHeartbeat(get_legacy_request_payload(data))
    end,
    SET_POSTALS = function(data)
        return CadApiSetPostals(data or {})
    end,
    GET_CHARACTERS = function(data)
        return CadApiGetCharacters(get_legacy_request_payload(data))
    end,
    SET_UNIT_STATUS = function(data)
        return CadApiSetUnitStatus(get_legacy_request_payload(data))
    end,
    SET_UNIT_PANIC = function(data)
        return CadApiSetUnitPanic(get_legacy_request_payload(data))
    end,
    PANIC = function(data)
        return CadApiSetUnitPanic(get_legacy_request_payload(data))
    end,
    KICK_UNIT = function(data)
        return CadApiKickUnits(get_legacy_request_payload(data))
    end,
    GET_ACTIVE_UNITS = function(data)
        return CadApiGetActiveUnits(get_legacy_request_payload(data))
    end,
    GET_CALLS = function(data)
        return CadApiGetCalls(get_legacy_request_payload(data))
    end,
    CREATE_EMERGENCY_CALL = function(data)
        return CadApiCreateEmergencyCall(get_legacy_request_payload(data))
    end,
    CREATE_911_CALL = function(data)
        return CadApiCreateEmergencyCall(get_legacy_request_payload(data))
    end,
    DELETE_EMERGENCY_CALL = function(data)
        local payload = get_legacy_request_payload(data)
        return CadApiDeleteEmergencyCall(payload.callId or payload.id, payload.serverId)
    end,
    DELETE_911_CALL = function(data)
        local payload = get_legacy_request_payload(data)
        return CadApiDeleteEmergencyCall(payload.callId or payload.id, payload.serverId)
    end,
    CREATE_DISPATCH_CALL = function(data)
        return CadApiCreateDispatchCall(get_legacy_request_payload(data))
    end,
    CREATE_CALL = function(data)
        return CadApiCreateDispatchCall(get_legacy_request_payload(data))
    end,
    UPDATE_DISPATCH_CALL = function(data)
        local payload = get_legacy_request_payload(data)
        local call_id = payload.callId or payload.id
        return get_cad_client():updateDispatchCallV2(call_id, payload)
    end,
    ATTACH_UNIT = function(data)
        return CadApiAttachUnitsToDispatchCall(get_legacy_request_payload(data))
    end,
    DETACH_UNIT = function(data)
        return CadApiDetachUnitsFromDispatchCall(get_legacy_request_payload(data))
    end,
    ADD_DISPATCH_NOTE = function(data)
        return CadApiAddDispatchNote(get_legacy_request_payload(data))
    end,
    ADD_CALL_NOTE = function(data)
        return CadApiAddDispatchNote(get_legacy_request_payload(data))
    end,
    SET_CALL_POSTAL = function(data)
        return CadApiSetDispatchPostal(get_legacy_request_payload(data))
    end,
    AUTH_STREETSIGNS = function(data)
        local payload = get_legacy_request_payload(data)
        return CadApiAuthorizeStreetSigns(payload.serverId or payload)
    end,
    SET_STREETSIGN_CONFIG = function(data)
        local payload = get_legacy_request_payload(data)
        return get_cad_client():setStreetSignConfigV2(payload.signConfig or payload.signs or {}, payload.serverId)
    end,
    UPDATE_STREETSIGN = function(data)
        return get_cad_client():updateStreetSignsV2(get_legacy_request_payload(data))
    end,
    LOOKUP = function(data)
        return CadApiLookup(get_legacy_request_payload(data))
    end,
    LOOKUP_BY_VALUE = function(data)
        return CadApiLookupByValue(get_legacy_request_payload(data))
    end,
    CREATE_RECORD = function(data)
        return CadApiCreateRecord(get_legacy_request_payload(data))
    end,
    GET_ACCOUNT = function(data)
        return CadApiGetAccount(get_legacy_request_payload(data))
    end,
    GET_ACCOUNTS = function(data)
        return CadApiGetAccounts(get_legacy_request_payload(data))
    end,
    SET_ACCOUNT_PERMISSIONS = function(data)
        return CadApiSetAccountPermissions(get_legacy_request_payload(data))
    end,
    SET_API_IDS = function(data)
        return CadApiSetApiIds(get_legacy_request_payload(data))
    end,
    VERIFY_SECRET = function(data)
        local payload = get_legacy_request_payload(data)
        return CadApiVerifySecret(payload.secret or payload)
    end,
    SEND_PHOTO = function(data)
        return CadApiSendPhoto(get_legacy_request_payload(data))
    end,
    AUTHORIZE_STREET_SIGNS = function(data)
        local payload = get_legacy_request_payload(data)
        return CadApiAuthorizeStreetSigns(payload.serverId or payload)
    end,
    GET_CURRENT_CALL = function(data)
        return CadApiGetCurrentCall(get_legacy_request_payload(data))
    end,
    GET_IDENTIFIERS = function(data)
        return CadApiGetIdentifiers(get_legacy_request_payload(data))
    end,
    GET_ACCOUNT_UNITS = function(data)
        return CadApiGetAccountUnits(get_legacy_request_payload(data))
    end,
    GET_TEMPLATES = function(data)
        return CadApiGetTemplates(get_legacy_request_payload(data))
    end,
    SET_AVAILABLE_CALLOUTS = function(data)
        return CadApiSetAvailableCallouts(get_legacy_request_payload(data))
    end,
    SET_STATIONS = function(data)
        return CadApiSetStations(get_legacy_request_payload(data))
    end,
    GET_BLIPS = function(data)
        return CadApiGetBlips(get_legacy_request_payload(data))
    end,
    CREATE_BLIPS = function(data)
        return CadApiCreateBlips(get_legacy_request_payloads(data))
    end,
    UPDATE_BLIPS = function(data)
        return CadApiUpdateBlips(get_legacy_request_payloads(data))
    end,
    DELETE_BLIPS = function(data)
        return CadApiDeleteBlips(get_legacy_request_payload(data))
    end,
    APPLY_PERMISSION_KEY = function(data)
        return CadApiApplyPermissionKey(get_legacy_request_payload(data))
    end,
    BAN_USER = function(data)
        return CadApiBanUser(get_legacy_request_payload(data))
    end,
    UPLOAD_LOGS = function(data)
        return CadApiUploadSupportLogs(get_legacy_request_payload(data))
    end,
    CREATE_COMMUNITY_LINK = function(data)
        return CadApiCreateCommunityLink(get_legacy_request_payload(data))
    end,
    CHECK_COMMUNITY_LINK = function(data)
        return CadApiCheckCommunityLink(get_legacy_request_payload(data))
    end
}

-- Alias for v1 API endpoints
legacyApiHandlers.UNIT_PANIC = legacyApiHandlers.PANIC
legacyApiHandlers.CALL_911 = legacyApiHandlers.CREATE_911_CALL
legacyApiHandlers.LOOKUP_VALUE = legacyApiHandlers.LOOKUP_BY_VALUE
