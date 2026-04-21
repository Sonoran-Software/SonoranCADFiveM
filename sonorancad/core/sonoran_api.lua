local ApiEndpoints = {
    ["UNIT_LOCATION"] = "emergency",
    ["CALL_911"] = "emergency",
    ["UNIT_PANIC"] = "emergency",
    ["GET_VERSION"] = "general",
    ["GET_SERVERS"] = "general",
    ["GET_LOGIN_PAGE"] = "general",
    ["GET_INFO"] = "general",
    ["ATTACH_UNIT"] = "emergency",
    ["DETACH_UNIT"] = "emergency",
    ["ADD_CALL_NOTE"] = "emergency",
    ["RECORD_ADD"] = "general",
    ["RECORD_UPDATE"] = "general",
    ["SET_SERVERS"] = "general",
    ["SET_PENAL_CODES"] = "general",
    ["GET_CHARACTERS"] = "civilian",
    ["EDIT_CHARACTER"] = "civilian",
    ["NEW_RECORD"] = "general",
    ["EDIT_RECORD"] = "general",
    ["REMOVE_RECORD"] = "general",
    ["GET_TEMPLATES"] = "general",
    ["LOOKUP_INT"] = "general",
    ["SET_STATIONS"] = "emergency",
    ["LOOKUP_VALUE"] = "general",
    ["GET_ACCOUNT"] = "general",
    ["GET_ACCOUNTS"] = "general",
    ["SET_ACCOUNT_PERMISSIONS"] = "general",
    ["SET_API_IDS"] = "general",
    ["VERIFY_SECRET"] = "general",
    ["SEND_PHOTO"] = "general",
    ["AUTH_STREET_SIGNS"] = "general",
    ["GET_CURRENT_CALL"] = "emergency",
    ["GET_IDENTIFIERS"] = "emergency",
    ["GET_ACCOUNT_UNITS"] = "emergency"
}

local cadV2Client = nil

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

    cadV2Client = Sonoran.createClient({
        apiKey = Config.apiKey,
        communityId = Config.communityID,
        apiUrl = resolve_api_url(),
        defaultServerId = tonumber(Config.serverId) or 1
    })

    return cadV2Client
end

function GetCadClient()
    return get_cad_client()
end

function registerApiType(type, endpoint)
    ApiEndpoints[type] = endpoint
end
exports("registerApiType", registerApiType)

local function unwrap_legacy_payload(post_data)
    if type(post_data) == "string" then
        local ok, decoded = pcall(json.decode, post_data)
        if ok and decoded ~= nil then
            return decoded
        end
        return post_data
    end

    if type(post_data) ~= "table" then
        return post_data
    end

    if #post_data == 1 and next(post_data, 1) == nil then
        return post_data[1]
    end

    return post_data
end

local function ensure_array(value)
    if type(value) ~= "table" then
        return {}
    end
    if #value > 0 then
        return value
    end
    return {value}
end

local function to_json_string(value)
    if value == nil then
        return "{}"
    end
    if type(value) == "string" then
        return value
    end
    return json.encode(value)
end

local function stringify_reason(value)
    if type(value) == "string" then
        return value
    end
    if value == nil then
        return "Unknown API error."
    end
    return json.encode(value)
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

local function get_v2_response_id(data)
    if type(data) ~= "table" then
        return nil
    end
    return data.id or data.callId or data.recordId or data.dispatchCallId
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

local function unwrap_named_collection(data, key)
    if type(data) == "table" and type(data[key]) == "table" then
        return data[key]
    end
    return data
end

local function resolve_community_user_id(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    if GetCommunityUserIdFromIdentifier == nil then
        return nil
    end
    return GetCommunityUserIdFromIdentifier(value)
end

local function resolve_community_user_ids(values)
    local resolved = {}
    for _, value in ipairs(values or {}) do
        local resolved_value = resolve_community_user_id(value)
        if resolved_value ~= nil then
            table.insert(resolved, resolved_value)
        end
    end
    return resolved
end

local function require_community_user_id(value)
    local resolved = resolve_community_user_id(value)
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
        local resolved, err = require_community_user_id(community_user_id_value)
        if resolved == nil then
            return nil, err
        end
        query.communityUserId = resolved
    end

    return query
end

local function perform_support_request(post_data, request_type, cb)
    local endpoint = ApiEndpoints[request_type]
    local payload = {
        id = Config.communityID,
        key = Config.apiKey,
        data = post_data,
        type = request_type
    }
    local url = "https://api.sonoransoftware.com/" .. tostring(endpoint) .. "/"

    PerformHttpRequestS(url, function(status_code, res)
        if status_code == 200 and res ~= nil then
            cb(res, true)
            return
        end
        errorLog(("CAD SUPPORT API ERROR (%s): status=%s response=%s payload=%s"):format(
            tostring(request_type),
            tostring(status_code),
            tostring(res),
            payload_preview(post_data)
        ))
        cb(res or ("HTTP " .. tostring(status_code)), false)
    end, "POST", json.encode(payload), {["Content-Type"] = "application/json"})
end

local function call_registered_legacy_api(request_type, post_data)
    local endpoint = ApiEndpoints[request_type]
    if type(endpoint) ~= "string" or endpoint == "" or endpoint == "support" then
        return nil, ("Unsupported v2 API request type: %s"):format(tostring(request_type))
    end

    local payload = {
        id = Config.communityID,
        key = Config.apiKey,
        data = post_data,
        type = request_type
    }
    local url = resolve_api_url():gsub("/+$", "") .. "/" .. tostring(endpoint) .. "/"
    local response_body = nil
    local response_ok = false
    local response_status = nil

    PerformHttpRequestS(url, function(status_code, res)
        response_status = status_code
        response_body = res
        response_ok = tonumber(status_code) == 200 and res ~= nil
    end, "POST", json.encode(payload), {["Content-Type"] = "application/json"})

    if response_ok then
        return response_body, true
    end

    return nil, ("HTTP %s: %s"):format(tostring(response_status), tostring(response_body))
end

local function call_v2_api(request_type, post_data)
    local client = get_cad_client()
    local data = unwrap_legacy_payload(post_data)
    local list = ensure_array(data)

    if request_type == "GET_VERSION" then
        local response = client:getVersionV2()
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        local version_data = response.data
        if type(version_data) == "table" then
            version_data = version_data.version or version_data.apiVersion or version_data.major or version_data[1]
        end
        return tostring(version_data or 0), true
    elseif request_type == "GET_SERVERS" then
        local response = client:getServersV2()
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(normalize_server_collection(response.data)), true
    elseif request_type == "GET_LOGIN_PAGE" then
        local payload = list[1] or {}
        local response = client:getLoginPageV2({
            url = payload.url,
            communityId = payload.communityId or payload.id or Config.communityID
        })
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {}), true
    elseif request_type == "GET_INFO" then
        local response = client:getInfoV2()
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {}), true
    elseif request_type == "SET_SERVERS" then
        local payload = data
        if type(payload) == "table" and payload.servers ~= nil then
            payload = payload.servers
        end
        local response = client:setServersV2(payload or {}, false)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {ok = true}), true
    elseif request_type == "HEARTBEAT" then
        local response = client:heartbeatV2((data and data.serverId) or Config.serverId, data and data.playerCount or 0)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return "OK", true
    elseif request_type == "SET_POSTALS" then
        local response = client:setPostalsV2(data)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return "OK", true
    elseif request_type == "SET_PENAL_CODES" then
        local payload = data
        if type(payload) == "table" and payload.codes ~= nil then
            payload = payload.codes
        end
        local response = client:setPenalCodesV2(payload or {})
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {ok = true}), true
    elseif request_type == "GET_ACCOUNT" then
        local payload = list[1] or {}
        local query, err = resolve_account_selector(payload, payload.communityUserId or payload.user)
        if query == nil then
            return nil, err
        end
        local response = client:getAccountV2(query)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {}), true
    elseif request_type == "GET_ACCOUNTS" then
        local payload = list[1] or {}
        local response = client:getAccountsV2({
            limit = payload.limit,
            offset = payload.offset,
            status = payload.status,
            username = payload.username
        })
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {}), true
    elseif request_type == "SET_ACCOUNT_PERMISSIONS" then
        local payload = list[1] or {}
        local request_payload, err = resolve_account_selector(payload, payload.communityUserId or payload.user)
        if request_payload == nil then
            return nil, err
        end
        request_payload.add = payload.add
        request_payload.remove = payload.remove
        request_payload.active = payload.active
        local response = client:setAccountPermissionsV2(request_payload)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {ok = true}), true
    elseif request_type == "SET_API_IDS" then
        local payload = list[1] or {}
        local request_payload, err = resolve_account_selector(payload, payload.communityUserId or payload.user)
        if request_payload == nil then
            return nil, err
        end
        request_payload.apiIds = payload.apiIds
        request_payload.pushNew = payload.pushNew
        local response = client:setApiIdsV2(request_payload)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {ok = true}), true
    elseif request_type == "VERIFY_SECRET" then
        local payload = list[1] or {}
        local response = client:verifySecretV2(payload.secret)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {ok = true}), true
    elseif request_type == "SEND_PHOTO" then
        local payload = list[1] or {}
        local community_user_id, err = require_community_user_id(payload.communityUserId or payload.user or payload.apiId)
        if community_user_id == nil then
            return nil, err
        end
        local response = client:sendPhotoV2({
            communityUserId = community_user_id,
            url = payload.url
        })
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {ok = true}), true
    elseif request_type == "AUTH_STREET_SIGNS" then
        local payload = list[1] or {}
        local response = client:authorizeStreetSignsV2(payload.serverId or Config.serverId)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {ok = true}), true
    elseif request_type == "GET_CHARACTERS" then
        local payload = list[1] or {}
        local query = {
            accountUuid = payload.accountUuid or payload.accountId or payload.uuid
        }
        if payload.communityUserId ~= nil or payload.user ~= nil then
            local err = nil
            query.communityUserId, err = require_community_user_id(payload.communityUserId or payload.user)
            if query.communityUserId == nil then
                return nil, err
            end
        end
        local response = client:getCharactersV2(query)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(unwrap_named_collection(response.data or {}, "characters") or {}), true
    elseif request_type == "UNIT_STATUS" then
        local payload = list[1] or {}
        local err = nil
        payload.communityUserId, err = require_community_user_id(payload.communityUserId)
        if payload.communityUserId == nil then
            return nil, err
        end
        local response = client:setUnitStatusV2(payload)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return "OK", true
    elseif request_type == "UNIT_PANIC" then
        local payload = list[1] or {}
        local err = nil
        payload.communityUserId, err = require_community_user_id(payload.communityUserId)
        if payload.communityUserId == nil then
            return nil, err
        end
        local response = client:setUnitPanicV2(payload)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return "OK", true
    elseif request_type == "KICK_UNIT" then
        for _, payload in ipairs(list) do
            local err = nil
            payload.communityUserId, err = require_community_user_id(payload.communityUserId)
            if payload.communityUserId == nil then
                return nil, err
            end
            local response = client:kickUnitV2(payload)
            if not response.success then
                return nil, stringify_reason(response.reason)
            end
        end
        return "OK", true
    elseif request_type == "UNIT_LOCATION" then
        local updates = {}
        for _, payload in ipairs(list) do
            local community_user_id, err = require_community_user_id(payload.communityUserId)
            if community_user_id == nil then
                return nil, err
            end
            updates[#updates + 1] = {
                communityUserId = community_user_id,
                location = payload.location,
                coordinates = payload.coordinates,
                vehicle = payload.vehicle,
                proxyUrl = payload.proxyUrl,
                peerId = payload.peerId
            }
        end
        local response = client:updateUnitLocationsV2({
            serverId = Config.serverId,
            updates = updates
        })
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return "OK", true
    elseif request_type == "GET_ACTIVE_UNITS" then
        local payload = list[1] or {}
        local response = client:getUnitsV2({
            serverId = payload.serverId or Config.serverId,
            onlyUnits = payload.unitsOnly,
            includeOffline = payload.includeOffline
        })
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(unwrap_named_collection(response.data or {}, "units") or {}), true
    elseif request_type == "GET_CALLS" then
        local payload = list[1] or {}
        local response = client:getCallsV2({
            serverId = payload.serverId or Config.serverId,
            type = payload.type,
            closedLimit = payload.closedLimit,
            closedOffset = payload.closedOffset
        })
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {}), true
    elseif request_type == "GET_CURRENT_CALL" then
        local payload = list[1] or {}
        local account_uuid = payload.accountUuid or payload.accountId or payload.uuid
        local response = client:getCurrentCallV2(account_uuid)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {}), true
    elseif request_type == "CALL_911" then
        local payload = list[1] or {}
        local response = client:createEmergencyCallV2(payload)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        local created_id = get_v2_response_id(response.data)
        if created_id ~= nil then
            return ("EMERGENCY CALL ADDED ID: %s"):format(created_id), true
        end
        return to_json_string(response.data or {ok = true}), true
    elseif request_type == "REMOVE_911" then
        local payload = list[1] or {}
        local response = client:deleteEmergencyCallV2(payload.callId, payload.serverId or Config.serverId)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return "OK", true
    elseif request_type == "GET_IDENTIFIERS" then
        local payload = list[1] or {}
        local account_uuid = payload.accountUuid or payload.accountId or payload.uuid
        local response = client:getIdentifiersV2(account_uuid)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(unwrap_named_collection(response.data or {}, "identifiers") or {}), true
    elseif request_type == "GET_ACCOUNT_UNITS" then
        local payload = list[1] or {}
        local response = client:getAccountUnitsV2({
            serverId = payload.serverId or Config.serverId,
            accountUuid = payload.accountUuid or payload.accountId or payload.uuid,
            onlyOnline = payload.onlyOnline,
            onlyUnits = payload.onlyUnits,
            limit = payload.limit,
            offset = payload.offset
        })
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(unwrap_named_collection(response.data or {}, "units") or {}), true
    elseif request_type == "NEW_DISPATCH" then
        local payload = list[1] or {}
        payload.units = resolve_community_user_ids(payload.units or {})
        local response = client:createDispatchCallV2(payload)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        local created_id = get_v2_response_id(response.data)
        if created_id ~= nil then
            return ("NEW DISPATCH CREATED - ID: %s"):format(created_id), true
        end
        return to_json_string(response.data or {ok = true}), true
    elseif request_type == "ATTACH_UNIT" then
        local payload = list[1] or {}
        payload.units = resolve_community_user_ids(payload.units or {})
        local call_id = payload.callId
        payload.callId = nil
        local response = client:attachUnitsToDispatchCallV2(call_id, payload)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return "OK", true
    elseif request_type == "DETACH_UNIT" then
        local payload = list[1] or {}
        payload.units = resolve_community_user_ids(payload.units or {})
        local response = client:detachUnitsFromDispatchCallV2(payload)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return "OK", true
    elseif request_type == "ADD_CALL_NOTE" then
        local payload = list[1] or {}
        local call_id = payload.callId
        payload.callId = nil
        local response = client:addDispatchNoteV2(call_id, payload)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return "OK", true
    elseif request_type == "SET_CALL_POSTAL" then
        local payload = list[1] or {}
        local response = client:setDispatchPostalV2(payload.callId, payload.postal, payload.serverId or Config.serverId)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return "OK", true
    elseif request_type == "LOOKUP" or request_type == "LOOKUP_INT" then
        local payload = list[1] or {}
        if payload.communityUserId ~= nil then
            local err = nil
            payload.communityUserId, err = require_community_user_id(payload.communityUserId)
            if payload.communityUserId == nil then
                return nil, err
            end
        end
        local response = client:lookupV2(payload)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {}), true
    elseif request_type == "LOOKUP_VALUE" then
        local payload = list[1] or {}
        if payload.communityUserId ~= nil then
            local err = nil
            payload.communityUserId, err = require_community_user_id(payload.communityUserId)
            if payload.communityUserId == nil then
                return nil, err
            end
        end
        local response = client:lookupByValueV2(payload)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {}), true
    elseif request_type == "NEW_RECORD" or request_type == "NEW_CHARACTER" or request_type == "RECORD_ADD" then
        local payload = list[1] or {}
        if payload.user ~= nil and payload.user ~= "" then
            local resolved_user = resolve_community_user_id(payload.user)
            if resolved_user ~= nil then
                payload.user = resolved_user
            end
        end
        local response = client:createRecordV2(payload)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {}), true
    elseif request_type == "REMOVE_RECORD" then
        local payload = list[1] or {}
        local record_id = payload.recordId or payload.id
        local response = client:removeRecordV2(record_id)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return "OK", true
    elseif request_type == "EDIT_RECORD" or request_type == "RECORD_UPDATE" then
        local payload = list[1] or {}
        local record_id = payload.recordId or payload.id
        payload.recordId = nil
        payload.id = nil
        local response = client:updateRecordV2(record_id, payload)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {ok = true}), true
    elseif request_type == "GET_TEMPLATES" then
        local payload = list[1] or {}
        local response = client:getTemplatesV2(payload.recordTypeId)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {}), true
    elseif request_type == "SET_AVAILABLE_CALLOUTS" then
        local payload = data
        if type(payload) == "table" and payload.callouts ~= nil then
            payload = payload.callouts
        end
        local response = client:setAvailableCalloutsV2(payload or {}, Config.serverId)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return "OK", true
    elseif request_type == "SET_STATIONS" then
        local payload = list[1] or {}
        local response = client:setStationsV2(payload.config or payload, payload.serverId or Config.serverId)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return "OK", true
    elseif request_type == "GET_BLIPS" then
        local payload = list[1] or {}
        local response = client:getBlipsV2(payload.serverId or Config.serverId)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(unwrap_named_collection(response.data or {}, "blips") or {}), true
    elseif request_type == "ADD_BLIP" then
        local created = {}
        for _, payload in ipairs(list) do
            local blip = payload.blip or payload
            local response = client:createBlipV2({
                serverId = payload.serverId or Config.serverId,
                blip = blip
            })
            if not response.success then
                return nil, stringify_reason(response.reason)
            end
            created[#created + 1] = response.data
        end
        return to_json_string(created), true
    elseif request_type == "MODIFY_BLIP" then
        for _, payload in ipairs(list) do
            local blip_id = payload.id or (payload.blip and payload.blip.id)
            local update = {}
            for key, value in pairs(payload) do
                if key ~= "id" and key ~= "serverId" then
                    update[key] = value
                end
            end
            local response = client:updateBlipV2(blip_id, {
                serverId = payload.serverId or Config.serverId,
                id = nil,
                subType = update.subType,
                coordinates = update.coordinates,
                radius = update.radius,
                icon = update.icon,
                color = update.color,
                tooltip = update.tooltip,
                data = update.data
            })
            if not response.success then
                return nil, stringify_reason(response.reason)
            end
        end
        return "OK", true
    elseif request_type == "REMOVE_BLIP" then
        local payload = list[1] or {}
        local response = client:deleteBlipsV2(payload.ids or {}, payload.serverId or Config.serverId)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return "OK", true
    elseif request_type == "APPLY_PERMISSION_KEY" then
        local payload = list[1] or {}
        local response = client:applyPermissionKeyV2(payload)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {ok = true}), true
    elseif request_type == "BAN_USER" then
        local payload = list[1] or {}
        local response = client:banUserV2(payload)
        if not response.success then
            return nil, stringify_reason(response.reason)
        end
        return to_json_string(response.data or {ok = true}), true
    end

    return call_registered_legacy_api(request_type, post_data)
end

function performApiRequest(postData, request_type, cb)
    if not cb then
        cb = function() end
    end
    assert(request_type ~= nil, "No type specified, invalid request.")

    if Config.critError then
        return
    elseif not Config.apiSendEnabled then
        errorLog("Config.apiSendEnabled disabled via convar or config, skipping API request. Check your config if this is unintentional.")
        return
    end

    if ApiEndpoints[request_type] == nil then
        return warnLog(("API request failed: endpoint %s is not registered. Use the registerApiType function to register this endpoint with the appropriate type."):format(request_type))
    end

    if request_type == "UPLOAD_LOGS" then
        return perform_support_request(postData, request_type, cb)
    end

    local ok, result_or_error, success = pcall(call_v2_api, request_type, postData)
    if not ok then
        errorLog(("CAD API ERROR (%s): %s payload=%s"):format(
            tostring(request_type),
            tostring(result_or_error),
            payload_preview(postData)
        ))
        cb(tostring(result_or_error), false)
        return
    end

    if success ~= true then
        errorLog(("CAD API ERROR (%s): %s payload=%s"):format(
            tostring(request_type),
            tostring(result_or_error),
            payload_preview(postData)
        ))
    end

    cb(result_or_error, success == true)
end
exports("performApiRequest", performApiRequest)

function CadApiCreateCommunityLink(payload)
    return get_cad_client():createCommunityLinkV2(payload)
end

function CadApiCheckCommunityLink(payload)
    return get_cad_client():checkCommunityLinkV2(payload)
end
