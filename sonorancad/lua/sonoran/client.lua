local function trim_trailing_slashes(value)
  return (tostring(value):gsub("/+$", ""))
end

local function starts_with(value, prefix)
  return value:sub(1, #prefix) == prefix
end

local function is_positive_integer(value)
  return type(value) == "number" and value >= 1 and value % 1 == 0
end

local function is_array(value)
  if type(value) ~= "table" then
    return false
  end

  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false
    end

    count = count + 1
  end

  return count == #value
end

local function shallow_copy(value)
  if type(value) ~= "table" then
    return value
  end

  local copy = {}
  for key, entry in pairs(value) do
    copy[key] = entry
  end

  return copy
end

local function strip_keys(value, keys)
  local copy = shallow_copy(value or {})
  for _, key in ipairs(keys) do
    copy[key] = nil
  end
  return copy
end

local function normalize_headers(headers)
  local normalized = {}
  for key, value in pairs(headers or {}) do
    normalized[string.lower(tostring(key))] = value
  end
  return normalized
end

local function append_query_parts(parts, encode, key, value)
  if value == nil then
    return
  end

  if type(value) == "table" and is_array(value) then
    for _, entry in ipairs(value) do
      append_query_parts(parts, encode, key, entry)
    end
    return
  end

  parts[#parts + 1] = string.format("%s=%s", encode(key), encode(tostring(value)))
end

local function build_url(base_url, path, query, encode)
  local url = string.format("%s/%s", trim_trailing_slashes(base_url), tostring(path):gsub("^/+", ""))
  if type(query) ~= "table" then
    return url
  end

  local parts = {}
  local keys = {}
  for key in pairs(query) do
    keys[#keys + 1] = tostring(key)
  end
  table.sort(keys)

  for _, key in ipairs(keys) do
    local value = query[key]
    append_query_parts(parts, encode, tostring(key), value)
  end

  if #parts == 0 then
    return url
  end

  return url .. "?" .. table.concat(parts, "&")
end

local CAD_V2_RATE_LIMIT_MAX_RETRIES = 2
local CAD_V2_RATE_LIMIT_DEFAULT_DELAY_MS = 1000
local CAD_V2_RATE_LIMIT_MAX_DELAY_MS = 10000

local Client = {}
Client.__index = Client

function Client:_assert_positive_integer(value, label)
  if not is_positive_integer(value) then
    error(string.format("%s must be a positive integer.", label))
  end

  return value
end

function Client:_resolve_server_id(server_id)
  local resolved = server_id
  if resolved == nil then
    resolved = self._config.defaultServerId
  end

  if type(resolved) == "string" then
    resolved = tonumber(resolved)
  end

  self:_assert_positive_integer(resolved, "serverId")
  return resolved
end

function Client:_encode_path_segment(value)
  if value == nil or value == "" then
    error("Path segment is required.")
  end

  return self._adapter.encodeURIComponent(tostring(value))
end

function Client:_parse_response(response)
  local status = tonumber(response and response.status) or 0
  if status == 204 then
    return nil
  end

  local raw_body = response and response.body
  if raw_body == nil or raw_body == "" then
    return nil
  end

  local headers = normalize_headers(response and response.headers)
  local content_type = tostring(headers["content-type"] or "")
  if starts_with(string.lower(content_type), "application/json") then
    local ok, parsed = pcall(self._adapter.decode, raw_body)
    if ok then
      return parsed
    end
  end

  return raw_body
end

function Client:_resolve_retry_delay_ms(response, attempt)
  local headers = normalize_headers(response and response.headers)
  local retry_after = headers["retry-after"]

  if retry_after ~= nil then
    local retry_after_seconds = tonumber(retry_after)
    if retry_after_seconds ~= nil and retry_after_seconds >= 0 then
      return math.min(math.floor((retry_after_seconds * 1000) + 0.5), CAD_V2_RATE_LIMIT_MAX_DELAY_MS)
    end
  end

  return math.min(CAD_V2_RATE_LIMIT_DEFAULT_DELAY_MS * (2 ^ attempt), CAD_V2_RATE_LIMIT_MAX_DELAY_MS)
end

function Client:_sleep_ms(delay_ms)
  if delay_ms <= 0 then
    return
  end

  if type(self._adapter.sleep) == "function" then
    self._adapter.sleep(delay_ms)
  end
end

function Client:_request(method, path, options)
  options = options or {}

  local headers = shallow_copy(self._config.headers)
  headers["Accept"] = "application/json"

  local authenticated = options.authenticated ~= false
  if authenticated then
    if not self._config.apiKey or self._config.apiKey == "" then
      error("apiKey is required for authenticated requests.")
    end

    headers["Authorization"] = "Bearer " .. self._config.apiKey
  end

  local body = options.body
  local encoded_body
  if body ~= nil then
    headers["Content-Type"] = "application/json"
    encoded_body = self._adapter.encode(body)
  end

  local request_options = {
    method = method,
    url = build_url(self._config.apiUrl, path, options.query, self._adapter.encodeURIComponent),
    headers = headers,
    body = encoded_body,
    timeoutMs = self._config.timeoutMs
  }

  for attempt = 0, CAD_V2_RATE_LIMIT_MAX_RETRIES do
    local response = self._adapter.request(request_options)
    local parsed = self:_parse_response(response or {})
    local ok = response and response.ok
    if ok == nil then
      local status = tonumber(response and response.status) or 0
      ok = status >= 200 and status < 300
    end

    if ok then
      return {
        success = true,
        data = parsed
      }
    end

    if tonumber(response and response.status) == 429 and attempt < CAD_V2_RATE_LIMIT_MAX_RETRIES then
      self:_sleep_ms(self:_resolve_retry_delay_ms(response, attempt))
    else
      return {
        success = false,
        reason = parsed
      }
    end
  end

  return {
    success = false,
    reason = "Request was rate limited."
  }
end

local function create_client(config, adapter)
  if type(adapter) ~= "table" then
    error("An adapter instance is required.")
  end

  if type(adapter.encode) ~= "function" or type(adapter.decode) ~= "function" or type(adapter.request) ~= "function" or type(adapter.encodeURIComponent) ~= "function" then
    error("Adapter is missing one or more required functions.")
  end

  local instance = setmetatable({
    _adapter = adapter,
    _config = {
      apiKey = config and config.apiKey or nil,
      communityId = config and config.communityId or nil,
      apiUrl = trim_trailing_slashes(config and config.apiUrl or "https://api.sonorancad.com"),
      defaultServerId = config and config.defaultServerId or 1,
      headers = shallow_copy(config and config.headers or {}),
      timeoutMs = config and config.timeoutMs or 30000
    }
  }, Client)

  instance.getLoginPageV2 = function(self, params)
    params = params or {}
    return self:_request("GET", "v2/general/login-page", {
      authenticated = false,
      query = {
        url = params.url,
        communityId = params.communityId or self._config.communityId
      }
    })
  end

  instance.applyPermissionKeyV2 = function(self, data)
    return self:_request("POST", "v2/general/permission-keys/applications", { body = data })
  end
  instance.banUserV2 = function(self, data)
    return self:_request("POST", "v2/general/account-bans", { body = data })
  end
  instance.setPenalCodesV2 = function(self, codes)
    return self:_request("PUT", "v2/general/penal-codes", { body = { codes = codes } })
  end
  instance.getTemplatesV2 = function(self, record_type_id)
    if record_type_id ~= nil then
      self:_assert_positive_integer(record_type_id, "recordTypeId")
      return self:_request("GET", "v2/general/templates/" .. tostring(record_type_id))
    end
    return self:_request("GET", "v2/general/templates")
  end
  instance.createRecordV2 = function(self, data)
    return self:_request("POST", "v2/general/records", { body = data })
  end
  instance.updateRecordV2 = function(self, record_id, data)
    self:_assert_positive_integer(record_id, "recordId")
    return self:_request("PATCH", "v2/general/records/" .. tostring(record_id), { body = data })
  end
  instance.removeRecordV2 = function(self, record_id)
    self:_assert_positive_integer(record_id, "recordId")
    return self:_request("DELETE", "v2/general/records/" .. tostring(record_id))
  end
  instance.sendRecordDraftV2 = function(self, data)
    return self:_request("POST", "v2/general/record-drafts", { body = data })
  end
  instance.lookupV2 = function(self, data)
    return self:_request("POST", "v2/general/lookups", { body = data })
  end
  instance.lookupByValueV2 = function(self, data)
    return self:_request("POST", "v2/general/lookups/by-value", { body = data })
  end
  instance.lookupCustomV2 = function(self, data)
    return self:_request("POST", "v2/general/lookups/custom", { body = data })
  end
  instance.getAccountV2 = function(self, query)
    return self:_request("GET", "v2/general/accounts/account", { query = query or {} })
  end
  instance.getAccountsV2 = function(self, query)
    return self:_request("GET", "v2/general/accounts", { query = query or {} })
  end
  instance.createCommunityLinkV2 = function(self, data)
    return self:_request("POST", "v2/general/links", { body = data })
  end
  instance.checkCommunityLinkV2 = function(self, data)
    return self:_request("POST", "v2/general/links/check", { body = data })
  end
  instance.setAccountPermissionsV2 = function(self, data)
    return self:_request("PATCH", "v2/general/accounts/permissions", { body = data })
  end
  instance.heartbeatV2 = function(self, server_id, player_count)
    local resolved_server_id = self:_resolve_server_id(server_id)
    return self:_request("POST", "v2/general/servers/" .. tostring(resolved_server_id) .. "/heartbeat", {
      body = { playerCount = player_count }
    })
  end
  instance.getVersionV2 = function(self)
    return self:_request("GET", "v2/general/version")
  end
  instance.getServersV2 = function(self)
    return self:_request("GET", "v2/general/servers")
  end
  instance.setServersV2 = function(self, servers, deploy_map)
    return self:_request("PUT", "v2/general/servers", {
      body = {
        servers = servers,
        deployMap = deploy_map == true
      }
    })
  end
  instance.verifySecretV2 = function(self, secret)
    return self:_request("POST", "v2/general/secrets/verify", { body = { secret = secret } })
  end
  instance.authorizeStreetSignsV2 = function(self, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    return self:_request("POST", "v2/general/servers/" .. tostring(resolved_server_id) .. "/street-sign-auth")
  end
  instance.setPostalsV2 = function(self, postals)
    return self:_request("PUT", "v2/general/postals", { body = { postals = postals } })
  end
  instance.sendPhotoV2 = function(self, data)
    return self:_request("POST", "v2/general/photos", { body = data })
  end
  instance.getInfoV2 = function(self)
    return self:_request("GET", "v2/general/info")
  end

  instance.getCharactersV2 = function(self, query)
    return self:_request("GET", "v2/civilian/characters", { query = query or {} })
  end
  instance.removeCharacterV2 = function(self, character_id)
    self:_assert_positive_integer(character_id, "characterId")
    return self:_request("DELETE", "v2/civilian/characters/" .. tostring(character_id))
  end
  instance.setSelectedCharacterV2 = function(self, data)
    return self:_request("PUT", "v2/civilian/selected-character", { body = data })
  end
  instance.getCharacterLinksV2 = function(self, query)
    return self:_request("GET", "v2/civilian/character-links", { query = query or {} })
  end
  instance.addCharacterLinkV2 = function(self, sync_id, data)
    return self:_request("PUT", "v2/civilian/character-links/" .. self:_encode_path_segment(sync_id), { body = data })
  end
  instance.removeCharacterLinkV2 = function(self, sync_id, data)
    return self:_request("DELETE", "v2/civilian/character-links/" .. self:_encode_path_segment(sync_id), { body = data })
  end

  instance.getUnitsV2 = function(self, query)
    query = query or {}
    local resolved_server_id = self:_resolve_server_id(query.serverId)
    return self:_request("GET", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/units", {
      query = {
        includeOffline = query.includeOffline,
        onlyUnits = query.onlyUnits,
        limit = query.limit,
        offset = query.offset
      }
    })
  end
  instance.getCallsV2 = function(self, query)
    query = query or {}
    local resolved_server_id = self:_resolve_server_id(query.serverId)
    return self:_request("GET", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/calls", {
      query = {
        closedLimit = query.closedLimit,
        closedOffset = query.closedOffset,
        type = query.type
      }
    })
  end
  instance.getCurrentCallV2 = function(self, account_uuid)
    return self:_request("GET", "v2/emergency/accounts/" .. self:_encode_path_segment(account_uuid) .. "/current-call")
  end
  instance.updateUnitLocationsV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    return self:_request("PATCH", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/unit-locations", {
      body = { updates = data and data.updates or nil }
    })
  end
  instance.setUnitPanicV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    return self:_request("PATCH", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/units/panic", {
      body = strip_keys(data, { "serverId" })
    })
  end
  instance.setUnitStatusV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    return self:_request("PATCH", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/units/status", {
      body = strip_keys(data, { "serverId" })
    })
  end
  instance.kickUnitV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    return self:_request("DELETE", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/units/kick", {
      body = {
        communityUserId = data and data.communityUserId or nil,
        reason = data and data.reason or nil
      }
    })
  end
  instance.getIdentifiersV2 = function(self, account_uuid)
    return self:_request("GET", "v2/emergency/accounts/" .. self:_encode_path_segment(account_uuid) .. "/identifiers")
  end
  instance.getAccountUnitsV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    return self:_request(
      "GET",
      "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/accounts/" .. self:_encode_path_segment(data.accountUuid) .. "/units",
      {
        query = {
          onlyOnline = data.onlyOnline,
          onlyUnits = data.onlyUnits,
          limit = data.limit,
          offset = data.offset
        }
      }
    )
  end
  instance.selectIdentifierV2 = function(self, account_uuid, ident_id)
    return self:_request("PUT", "v2/emergency/accounts/" .. self:_encode_path_segment(account_uuid) .. "/selected-identifier", {
      body = { identId = ident_id }
    })
  end
  instance.createIdentifierV2 = function(self, account_uuid, data)
    return self:_request("POST", "v2/emergency/accounts/" .. self:_encode_path_segment(account_uuid) .. "/identifiers", { body = data })
  end
  instance.updateIdentifierV2 = function(self, account_uuid, ident_id, data)
    self:_assert_positive_integer(ident_id, "identId")
    return self:_request("PATCH", "v2/emergency/accounts/" .. self:_encode_path_segment(account_uuid) .. "/identifiers/" .. tostring(ident_id), {
      body = data
    })
  end
  instance.deleteIdentifierV2 = function(self, account_uuid, ident_id)
    self:_assert_positive_integer(ident_id, "identId")
    return self:_request("DELETE", "v2/emergency/accounts/" .. self:_encode_path_segment(account_uuid) .. "/identifiers/" .. tostring(ident_id))
  end
  instance.addIdentifiersToGroupV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    return self:_request(
      "PUT",
      "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/identifier-groups/" .. self:_encode_path_segment(data.groupName),
      {
        body = strip_keys(data, { "serverId", "groupName" })
      }
    )
  end
  instance.createEmergencyCallV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    return self:_request("POST", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/calls/911", {
      body = strip_keys(data, { "serverId" })
    })
  end
  instance.deleteEmergencyCallV2 = function(self, call_id, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    self:_assert_positive_integer(call_id, "callId")
    return self:_request("DELETE", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/calls/911/" .. tostring(call_id))
  end
  instance.createDispatchCallV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    return self:_request("POST", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/dispatch-calls", {
      body = strip_keys(data, { "serverId" })
    })
  end
  instance.updateDispatchCallV2 = function(self, call_id, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    self:_assert_positive_integer(call_id, "callId")
    return self:_request("PATCH", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/dispatch-calls/" .. tostring(call_id), {
      body = strip_keys(data, { "serverId" })
    })
  end
  instance.attachUnitsToDispatchCallV2 = function(self, call_id, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    self:_assert_positive_integer(call_id, "callId")
    return self:_request("POST", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/dispatch-calls/" .. tostring(call_id) .. "/attachments", {
      body = strip_keys(data, { "serverId" })
    })
  end
  instance.detachUnitsFromDispatchCallV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    return self:_request("DELETE", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/dispatch-calls/attachments", {
      body = strip_keys(data, { "serverId" })
    })
  end
  instance.setDispatchPostalV2 = function(self, call_id, postal, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    self:_assert_positive_integer(call_id, "callId")
    return self:_request("PATCH", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/dispatch-calls/" .. tostring(call_id) .. "/postal", {
      body = { postal = postal }
    })
  end
  instance.setDispatchPrimaryV2 = function(self, call_id, ident_id, track_primary, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    self:_assert_positive_integer(call_id, "callId")
    self:_assert_positive_integer(ident_id, "identId")
    return self:_request("PATCH", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/dispatch-calls/" .. tostring(call_id) .. "/primary", {
      body = {
        identId = ident_id,
        trackPrimary = track_primary == true
      }
    })
  end
  instance.addDispatchNoteV2 = function(self, call_id, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    self:_assert_positive_integer(call_id, "callId")
    return self:_request("POST", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/dispatch-calls/" .. tostring(call_id) .. "/notes", {
      body = strip_keys(data, { "serverId" })
    })
  end
  instance.closeDispatchCallsV2 = function(self, call_ids, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    return self:_request("POST", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/dispatch-calls/close", {
      body = { callIds = call_ids }
    })
  end
  instance.updateStreetSignsV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    return self:_request("PATCH", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/street-signs", {
      body = strip_keys(data, { "serverId" })
    })
  end
  instance.setStreetSignConfigV2 = function(self, signs, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    return self:_request("PUT", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/street-sign-config", {
      body = { signs = signs }
    })
  end
  instance.setAvailableCalloutsV2 = function(self, callouts, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    return self:_request("PUT", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/callouts", {
      body = { callouts = callouts }
    })
  end
  instance.getPagerConfigV2 = function(self, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    return self:_request("GET", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/pager-config")
  end
  instance.setPagerConfigV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    return self:_request("PUT", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/pager-config", {
      body = strip_keys(data, { "serverId" })
    })
  end
  instance.setStationsV2 = function(self, config_value, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    return self:_request("PUT", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/stations", {
      body = { config = config_value }
    })
  end
  instance.getBlipsV2 = function(self, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    return self:_request("GET", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/blips")
  end
  instance.createBlipV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    return self:_request("POST", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/blips", {
      body = strip_keys(data, { "serverId" })
    })
  end
  instance.updateBlipV2 = function(self, blip_id, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    self:_assert_positive_integer(blip_id, "blipId")
    return self:_request("PATCH", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/blips/" .. tostring(blip_id), {
      body = strip_keys(data, { "serverId" })
    })
  end
  instance.deleteBlipsV2 = function(self, ids, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    return self:_request("DELETE", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/blips", {
      body = { ids = ids }
    })
  end

  return instance
end

return create_client
