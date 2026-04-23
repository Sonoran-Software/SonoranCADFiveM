local cadV2Client = nil
local sonoranModule = nil

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
        defaultServerId = tonumber(tonumber(Config.serverId)) or 1
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

function CadApiKickUnits(kicks)
    for _, payload in ipairs(kicks or {}) do
        local community_user_id, err = CadApiRequireCommunityUserId(payload.communityUserId)
        if community_user_id == nil then
            return {success = false, reason = err}
        end
        payload.communityUserId = community_user_id
        local response = get_cad_client():kickUnitV2(payload)
        if not response.success then
            return response
        end
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
        mi = tostring(payload.mi or "")
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
    return get_cad_client():setStationsV2(payload.config or payload, payload.serverId or tonumber(Config.serverId))
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
        local blip = payload.blip or payload
        local response = get_cad_client():createBlipV2({
            serverId = payload.serverId or tonumber(Config.serverId),
            blip = blip
        })
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

function CadApiCheckCommunityLink(payload)
    return get_cad_client():checkCommunityLinkV2(payload)
end
