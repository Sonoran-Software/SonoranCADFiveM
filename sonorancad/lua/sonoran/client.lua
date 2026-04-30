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

local function normalize_v2_target_aliases(value)
  if type(value) ~= "table" then
    return value
  end

  local copy = shallow_copy(value)

  if copy.communityUserId == nil and copy.apiId ~= nil then
    copy.communityUserId = copy.apiId
  end
  if copy.communityUserIds == nil and copy.apiIds ~= nil then
    copy.communityUserIds = copy.apiIds
  end
  if copy.notifyCommunityUserId == nil and copy.notifyApiId ~= nil then
    copy.notifyCommunityUserId = copy.notifyApiId
  end

  copy.apiId = nil
  copy.apiIds = nil
  copy.notifyApiId = nil

  return copy
end

local function stringify_table_values(value)
  if type(value) ~= "table" then
    return value
  end

  local copy = {}
  for key, entry in pairs(value) do
    if entry ~= nil then
      copy[key] = tostring(entry)
    end
  end
  return copy
end

local function normalize_replace_values(value, encode)
  if type(value) ~= "table" then
    return value
  end

  local copy = {}
  for key, entry in pairs(value) do
    if entry ~= nil then
      if type(entry) == "table" then
        copy[key] = encode(entry)
      else
        copy[key] = tostring(entry)
      end
    end
  end

  return copy
end

local function normalize_record_replace_values_body(body, encode)
  if type(body) ~= "table" or type(body.replaceValues) ~= "table" then
    return body
  end

  local copy = shallow_copy(body)
  copy.replaceValues = normalize_replace_values(body.replaceValues, encode)
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
local CAD_V2_RATE_LIMIT_MAX_AUTO_RETRY_DELAY_MS = 10000
local LOG_LEVELS = {
  OFF = "OFF",
  ERROR = "ERROR",
  DEBUG = "DEBUG"
}
local REDACTED_VALUE = "<redacted>"
local HTTP_MONTHS = {
  Jan = 1,
  Feb = 2,
  Mar = 3,
  Apr = 4,
  May = 5,
  Jun = 6,
  Jul = 7,
  Aug = 8,
  Sep = 9,
  Oct = 10,
  Nov = 11,
  Dec = 12
}
local SENSITIVE_KEYS = {
  ["authorization"] = true,
  ["api-key"] = true,
  ["apikey"] = true,
  ["api_key"] = true,
  ["x-api-key"] = true
}

local function serialize_debug_value(value, seen)
  local value_type = type(value)
  if value_type == "string" then
    return string.format("%q", value)
  end

  if value_type == "number" or value_type == "boolean" or value_type == "nil" then
    return tostring(value)
  end

  if value_type ~= "table" then
    return string.format("<%s>", value_type)
  end

  seen = seen or {}
  if seen[value] then
    return "<cycle>"
  end

  seen[value] = true

  local parts = {}
  local array_keys = {}
  local map_keys = {}

  for key in pairs(value) do
    if type(key) == "number" and key >= 1 and key % 1 == 0 then
      array_keys[#array_keys + 1] = key
    else
      map_keys[#map_keys + 1] = key
    end
  end

  table.sort(array_keys)
  table.sort(map_keys, function(left, right)
    return tostring(left) < tostring(right)
  end)

  for _, key in ipairs(array_keys) do
    parts[#parts + 1] = serialize_debug_value(value[key], seen)
  end

  for _, key in ipairs(map_keys) do
    parts[#parts + 1] = string.format("[%s]=%s", serialize_debug_value(key, seen), serialize_debug_value(value[key], seen))
  end

  seen[value] = nil
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local function sanitize_key(key)
  return string.lower(tostring(key)):gsub("[_%-%s]", "")
end

local function should_redact_key(key)
  local normalized = sanitize_key(key)
  return SENSITIVE_KEYS[string.lower(tostring(key))] == true
    or normalized == "authorization"
    or normalized == "apikey"
    or normalized == "xapikey"
end

local function sanitize_value(value, seen)
  if type(value) ~= "table" then
    return value
  end

  seen = seen or {}
  if seen[value] then
    return "<cycle>"
  end

  seen[value] = true

  local copy = {}
  for key, entry in pairs(value) do
    if should_redact_key(key) and entry ~= nil then
      copy[key] = REDACTED_VALUE
    else
      copy[key] = sanitize_value(entry, seen)
    end
  end

  seen[value] = nil
  return copy
end

local function get_utc_offset_seconds(timestamp)
  local local_time = os.date("*t", timestamp)
  local utc_time = os.date("!*t", timestamp)
  local_time.isdst = false
  utc_time.isdst = false
  return os.difftime(os.time(local_time), os.time(utc_time))
end

local function utc_timegm(parts)
  local local_timestamp = os.time(parts)
  if local_timestamp == nil then
    return nil
  end

  return local_timestamp - get_utc_offset_seconds(local_timestamp)
end

local function parse_http_date(value)
  if type(value) ~= "string" then
    return nil
  end

  local day, month_name, year, hour, minute, second = value:match("^%a+,%s+(%d%d?)%s+(%a+)%s+(%d%d%d%d)%s+(%d%d):(%d%d):(%d%d)%s+GMT$")
  if day == nil then
    day, month_name, year, hour, minute, second = value:match("^%a+,%s+(%d%d?)%-(%a+)%-(%d%d)%s+(%d%d):(%d%d):(%d%d)%s+GMT$")
    if year ~= nil then
      local numeric_year = tonumber(year)
      if numeric_year ~= nil then
        year = numeric_year >= 70 and ("19" .. year) or ("20" .. year)
      end
    end
  end

  if day == nil then
    day, month_name, year, hour, minute, second = value:match("^%a+%s+(%a+)%s+(%d%d?)%s+(%d%d):(%d%d):(%d%d)%s+(%d%d%d%d)$")
    if day ~= nil then
      local rewritten_day = month_name
      month_name = day
      day = rewritten_day
    end
  end

  local month = HTTP_MONTHS[month_name]
  if month == nil then
    return nil
  end

  return utc_timegm({
    year = tonumber(year),
    month = month,
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(minute),
    sec = tonumber(second),
    isdst = false
  })
end

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
      return math.max(0, math.floor((retry_after_seconds * 1000) + 0.5)), "Retry-After"
    end

    local retry_after_timestamp = parse_http_date(retry_after)
    if retry_after_timestamp ~= nil then
      return math.max(0, math.floor((os.difftime(retry_after_timestamp, os.time()) * 1000) + 0.5)), "Retry-After"
    end
  end

  local rate_limit_reset = headers["ratelimit-reset"]
  if rate_limit_reset ~= nil then
    local reset_seconds = tonumber(rate_limit_reset)
    if reset_seconds ~= nil and reset_seconds >= 0 then
      return math.max(0, math.floor((reset_seconds * 1000) + 0.5)), "RateLimit-Reset"
    end
  end

  local x_rate_limit_reset = headers["x-ratelimit-reset"]
  if x_rate_limit_reset ~= nil then
    local reset_seconds = tonumber(x_rate_limit_reset)
    if reset_seconds ~= nil and reset_seconds >= 0 then
      if reset_seconds >= 1000000000 then
        return math.max(0, math.floor((os.difftime(reset_seconds, os.time()) * 1000) + 0.5)), "X-RateLimit-Reset"
      end

      return math.max(0, math.floor((reset_seconds * 1000) + 0.5)), "X-RateLimit-Reset"
    end
  end

  return math.min(CAD_V2_RATE_LIMIT_DEFAULT_DELAY_MS * (2 ^ attempt), CAD_V2_RATE_LIMIT_MAX_AUTO_RETRY_DELAY_MS), "exponential backoff"
end

function Client:_sleep_ms(delay_ms)
  if delay_ms <= 0 then
    return
  end

  if type(self._adapter.sleep) == "function" then
    self._adapter.sleep(delay_ms)
  end
end

function Client:_assert_log_level(level)
  if level ~= LOG_LEVELS.OFF and level ~= LOG_LEVELS.ERROR and level ~= LOG_LEVELS.DEBUG then
    error("logLevel must be OFF, ERROR, or DEBUG.")
  end

  return level
end

function Client:setLogLevel(level)
  self._config.logLevel = self:_assert_log_level(level or LOG_LEVELS.ERROR)
  return self
end

function Client:_is_debug_enabled()
  return self._config.logLevel == LOG_LEVELS.DEBUG
end

function Client:_is_error_enabled()
  return self._config.logLevel == LOG_LEVELS.ERROR or self._config.logLevel == LOG_LEVELS.DEBUG
end

function Client:_format_log_value(value)
  return serialize_debug_value(sanitize_value(value))
end

function Client:_debug_log_http_request(request_options, attempt)
  if not self:_is_debug_enabled() then
    return
  end

  print("[Sonoran.lua][DEBUG] HTTP request")
  print("[Sonoran.lua][DEBUG]   attempt: " .. tostring((attempt or 0) + 1))
  print("[Sonoran.lua][DEBUG]   method: " .. tostring(request_options.method))
  print("[Sonoran.lua][DEBUG]   url: " .. tostring(request_options.url))
  print("[Sonoran.lua][DEBUG]   headers: " .. self:_format_log_value(request_options.headers))
  print("[Sonoran.lua][DEBUG]   body: " .. self:_format_log_value(request_options.logBody))
end

function Client:_debug_log_http_response(response, attempt)
  if not self:_is_debug_enabled() then
    return
  end

  print("[Sonoran.lua][DEBUG] HTTP response")
  print("[Sonoran.lua][DEBUG]   attempt: " .. tostring((attempt or 0) + 1))
  print("[Sonoran.lua][DEBUG]   ok: " .. tostring(response and response.ok))
  print("[Sonoran.lua][DEBUG]   status: " .. tostring(response and response.status))
  print("[Sonoran.lua][DEBUG]   headers: " .. self:_format_log_value(response and response.headers))
  print("[Sonoran.lua][DEBUG]   body: " .. self:_format_log_value(response and response.body))
end

function Client:_error_log_http_failure(request_options, response, parsed, attempt, message)
  if not self:_is_error_enabled() then
    return
  end

  print("[Sonoran.lua][ERROR] " .. tostring(message))
  print("[Sonoran.lua][ERROR]   attempt: " .. tostring((attempt or 0) + 1))
  print("[Sonoran.lua][ERROR]   method: " .. tostring(request_options.method))
  print("[Sonoran.lua][ERROR]   url: " .. tostring(request_options.url))
  print("[Sonoran.lua][ERROR]   request headers: " .. self:_format_log_value(request_options.headers))
  print("[Sonoran.lua][ERROR]   request body: " .. self:_format_log_value(request_options.logBody))
  print("[Sonoran.lua][ERROR]   response status: " .. tostring(response and response.status))
  print("[Sonoran.lua][ERROR]   response headers: " .. self:_format_log_value(response and response.headers))
  print("[Sonoran.lua][ERROR]   response body: " .. self:_format_log_value(parsed ~= nil and parsed or response and response.body))
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
    logBody = body,
    timeoutMs = self._config.timeoutMs
  }

  for attempt = 0, CAD_V2_RATE_LIMIT_MAX_RETRIES do
    self:_debug_log_http_request(request_options, attempt)
    local response = self._adapter.request(request_options)
    self:_debug_log_http_response(response, attempt)
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
      local retry_delay_ms, retry_source = self:_resolve_retry_delay_ms(response, attempt)
      if retry_delay_ms > CAD_V2_RATE_LIMIT_MAX_AUTO_RETRY_DELAY_MS then
        self:_error_log_http_failure(
          request_options,
          response,
          parsed,
          attempt,
          string.format(
            "HTTP 429 rate limit received. Not retrying because %s requested %d ms, which exceeds the automatic retry limit of %d ms.",
            tostring(retry_source),
            retry_delay_ms,
            CAD_V2_RATE_LIMIT_MAX_AUTO_RETRY_DELAY_MS
          )
        )
      elseif retry_delay_ms > 0 and type(self._adapter.sleep) ~= "function" then
        self:_error_log_http_failure(
          request_options,
          response,
          parsed,
          attempt,
          string.format(
            "HTTP 429 rate limit received. Not retrying because the active adapter cannot wait %d ms from %s.",
            retry_delay_ms,
            tostring(retry_source)
          )
        )
      else
        self:_error_log_http_failure(
          request_options,
          response,
          parsed,
          attempt,
          string.format(
            "HTTP 429 rate limit received. Retrying after %d ms from %s.",
            retry_delay_ms,
            tostring(retry_source)
          )
        )
        self:_sleep_ms(retry_delay_ms)
      end

      if retry_delay_ms <= CAD_V2_RATE_LIMIT_MAX_AUTO_RETRY_DELAY_MS and (retry_delay_ms <= 0 or type(self._adapter.sleep) == "function") then
        -- Retry by falling through to the next loop iteration without returning.
      else
        return {
          success = false,
          reason = parsed ~= nil and parsed or "Request was rate limited."
        }
      end
    elseif tonumber(response and response.status) == 429 then
      self:_error_log_http_failure(request_options, response, parsed, attempt, "HTTP 429 rate limit received. Automatic retries have been exhausted.")
      return {
        success = false,
        reason = parsed ~= nil and parsed or "Request was rate limited."
      }
    else
      self:_error_log_http_failure(request_options, response, parsed, attempt, "HTTP request failed.")
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

  local product = config and config.product
  if product == nil then
    error("product is required when instancing.")
  end

  if product ~= 0 and product ~= 1 and product ~= 2 then
    error("Only productEnums.CAD, productEnums.CMS, and productEnums.RADIO are currently supported in Sonoran.lua.")
  end

  local instance = setmetatable({
    _adapter = adapter,
    _config = {
      apiKey = config and config.apiKey or nil,
      communityId = config and config.communityId or nil,
      apiUrl = trim_trailing_slashes(config and config.apiUrl or (product == 2 and "https://api.sonoranradio.com" or product == 1 and "https://api.sonorancms.com" or "https://api.sonorancad.com")),
      defaultServerId = config and config.defaultServerId or 1,
      headers = shallow_copy(config and config.headers or {}),
      timeoutMs = config and config.timeoutMs or 30000,
      logLevel = LOG_LEVELS.ERROR
    }
  }, Client)

  if config and config.logLevel ~= nil then
    instance:setLogLevel(config.logLevel)
  end

  local cad_proxy = setmetatable({}, {
    __index = function(_, key)
      local value = instance[key]
      if type(value) == "function" then
        return function(_, ...)
          return value(instance, ...)
        end
      end

      return value
    end
  })

  instance.cad = cad_proxy
  local cms_proxy = setmetatable({}, {
    __index = function(_, key)
      local value = instance[key]
      if type(value) == "function" then
        return function(_, ...)
          return value(instance, ...)
        end
      end

      return value
    end
  })

  instance.cms = cms_proxy
  instance.radio = cad_proxy

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

  instance.checkApiIdV2 = function(self, api_id)
    return self:_request("GET", "v2/general/api-ids/" .. self:_encode_path_segment(api_id))
  end
  instance.applyPermissionKeyV2 = function(self, data)
    return self:_request("POST", "v2/general/permission-keys/applications", { body = normalize_v2_target_aliases(data) })
  end
  instance.banUserV2 = function(self, data)
    return self:_request("POST", "v2/general/account-bans", { body = normalize_v2_target_aliases(data) })
  end
  instance.setPenalCodesV2 = function(self, codes)
    return self:_request("PUT", "v2/general/penal-codes", { body = { codes = codes } })
  end
  instance.setApiIdsV2 = function(self, data)
    return self:_request("PUT", "v2/general/api-ids", { body = data })
  end
  instance.getTemplatesV2 = function(self, record_type_id)
    if record_type_id ~= nil then
      self:_assert_positive_integer(record_type_id, "recordTypeId")
      return self:_request("GET", "v2/general/templates/" .. tostring(record_type_id))
    end
    return self:_request("GET", "v2/general/templates")
  end
  instance.createRecordV2 = function(self, data)
    return self:_request("POST", "v2/general/records", { body = normalize_v2_target_aliases(normalize_record_replace_values_body(data, self._adapter.encode)) })
  end
  instance.updateRecordV2 = function(self, record_id, data)
    self:_assert_positive_integer(record_id, "recordId")
    return self:_request("PATCH", "v2/general/records/" .. tostring(record_id), { body = normalize_v2_target_aliases(normalize_record_replace_values_body(data, self._adapter.encode)) })
  end
  instance.removeRecordV2 = function(self, record_id)
    self:_assert_positive_integer(record_id, "recordId")
    return self:_request("DELETE", "v2/general/records/" .. tostring(record_id))
  end
  instance.sendRecordDraftV2 = function(self, data)
    return self:_request("POST", "v2/general/record-drafts", { body = normalize_v2_target_aliases(normalize_record_replace_values_body(data, self._adapter.encode)) })
  end
  instance.lookupV2 = function(self, data)
    return self:_request("POST", "v2/general/lookups", { body = normalize_v2_target_aliases(data) })
  end
  instance.lookupByValueV2 = function(self, data)
    return self:_request("POST", "v2/general/lookups/by-value", { body = normalize_v2_target_aliases(data) })
  end
  instance.lookupCustomV2 = function(self, data)
    return self:_request("POST", "v2/general/lookups/custom", { body = data })
  end
  instance.getAccountV2 = function(self, query)
    return self:_request("GET", "v2/general/accounts/account", { query = normalize_v2_target_aliases(query or {}) })
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
    return self:_request("PATCH", "v2/general/accounts/permissions", { body = normalize_v2_target_aliases(data) })
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
  instance.getTurnCredentialsV2 = function(self, query)
    return self:_request("GET", "v2/general/turn", { query = query or {} })
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
    return self:_request("POST", "v2/general/photos", { body = normalize_v2_target_aliases(data) })
  end
  instance.getInfoV2 = function(self)
    return self:_request("GET", "v2/general/info")
  end

  instance.getCharactersV2 = function(self, query)
    return self:_request("GET", "v2/civilian/characters", { query = normalize_v2_target_aliases(query or {}) })
  end
  instance.removeCharacterV2 = function(self, character_id)
    self:_assert_positive_integer(character_id, "characterId")
    return self:_request("DELETE", "v2/civilian/characters/" .. tostring(character_id))
  end
  instance.setSelectedCharacterV2 = function(self, data)
    return self:_request("PUT", "v2/civilian/selected-character", { body = normalize_v2_target_aliases(data) })
  end
  instance.getCharacterLinksV2 = function(self, query)
    return self:_request("GET", "v2/civilian/character-links", { query = normalize_v2_target_aliases(query or {}) })
  end
  instance.addCharacterLinkV2 = function(self, sync_id, data)
    return self:_request("PUT", "v2/civilian/character-links/" .. self:_encode_path_segment(sync_id), { body = normalize_v2_target_aliases(data) })
  end
  instance.removeCharacterLinkV2 = function(self, sync_id, data)
    return self:_request("DELETE", "v2/civilian/character-links/" .. self:_encode_path_segment(sync_id), { body = normalize_v2_target_aliases(data) })
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
    local updates = {}
    for index, update in ipairs(data and data.updates or {}) do
      updates[index] = normalize_v2_target_aliases(update)
    end
    return self:_request("PATCH", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/unit-locations", {
      body = { updates = updates }
    })
  end
  instance.setUnitPanicV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    return self:_request("PATCH", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/units/panic", {
      body = normalize_v2_target_aliases(strip_keys(data, { "serverId" }))
    })
  end
  instance.setUnitStatusV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    return self:_request("PATCH", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/units/status", {
      body = normalize_v2_target_aliases(strip_keys(data, { "serverId" }))
    })
  end
  instance.kickUnitV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    local target = normalize_v2_target_aliases(data or {})
    return self:_request("POST", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/units/kick", {
      body = {
        communityUserId = target and target.communityUserId or nil,
        roblox = target and target.roblox or nil,
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
        body = normalize_v2_target_aliases(strip_keys(data, { "serverId", "groupName" }))
      }
    )
  end
  instance.createEmergencyCallV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    local body = normalize_v2_target_aliases(strip_keys(data, { "serverId" }))
    body.metaData = stringify_table_values(body.metaData)
    return self:_request("POST", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/calls/911", {
      body = body
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
      body = normalize_v2_target_aliases(strip_keys(data, { "serverId" }))
    })
  end
  instance.updateDispatchCallV2 = function(self, call_id, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    self:_assert_positive_integer(call_id, "callId")
    return self:_request("PATCH", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/dispatch-calls/" .. tostring(call_id), {
      body = normalize_v2_target_aliases(strip_keys(data, { "serverId" }))
    })
  end
  instance.attachUnitsToDispatchCallV2 = function(self, call_id, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    self:_assert_positive_integer(call_id, "callId")
    return self:_request("POST", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/dispatch-calls/" .. tostring(call_id) .. "/attachments", {
      body = normalize_v2_target_aliases(strip_keys(data, { "serverId" }))
    })
  end
  instance.detachUnitsFromDispatchCallV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    return self:_request("DELETE", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/dispatch-calls/attachments", {
      body = normalize_v2_target_aliases(strip_keys(data, { "serverId" }))
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
    return self:_request("POST", "v2/emergency/servers/" .. tostring(resolved_server_id) .. "/blips/delete", {
      body = { ids = ids }
    })
  end

  instance.getCommunityChannelsV2 = function(self, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    return self:_request("GET", "v2/servers/" .. tostring(resolved_server_id) .. "/channels")
  end
  instance.getConnectedUsersV2 = function(self, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    return self:_request("GET", "v2/servers/" .. tostring(resolved_server_id) .. "/connected-users")
  end
  instance.getConnectedUserV2 = function(self, room_id, identity, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    self:_assert_positive_integer(room_id, "roomId")
    return self:_request("GET", "v2/servers/" .. tostring(resolved_server_id) .. "/rooms/" .. tostring(room_id) .. "/users/" .. self:_encode_path_segment(identity))
  end
  instance.setUserChannelsV2 = function(self, room_id, identity, options, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    self:_assert_positive_integer(room_id, "roomId")
    return self:_request("PATCH", "v2/servers/" .. tostring(resolved_server_id) .. "/rooms/" .. tostring(room_id) .. "/users/" .. self:_encode_path_segment(identity) .. "/channels", {
      body = shallow_copy(options or {})
    })
  end
  instance.setUserDisplayNameV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    return self:_request("PATCH", "v2/servers/" .. tostring(resolved_server_id) .. "/users/display-name", {
      body = strip_keys(data, { "serverId" })
    })
  end
  instance.approveMembersV2 = function(self, acc_ids, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    return self:_request("POST", "v2/servers/" .. tostring(resolved_server_id) .. "/members/approve", {
      body = { accIds = acc_ids }
    })
  end
  instance.kickMembersV2 = function(self, acc_ids, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    return self:_request("POST", "v2/servers/" .. tostring(resolved_server_id) .. "/members/kick", {
      body = { accIds = acc_ids }
    })
  end
  instance.banMembersV2 = function(self, acc_ids, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    return self:_request("POST", "v2/servers/" .. tostring(resolved_server_id) .. "/members/ban", {
      body = { accIds = acc_ids }
    })
  end
  instance.setMemberDisplayNamesV2 = function(self, acc_nicknames, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    return self:_request("PATCH", "v2/servers/" .. tostring(resolved_server_id) .. "/members/display-names", {
      body = { accNicknames = acc_nicknames }
    })
  end
  instance.setMemberPermissionsV2 = function(self, user_perms, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    return self:_request("PATCH", "v2/servers/" .. tostring(resolved_server_id) .. "/members/permissions", {
      body = { userPerms = user_perms }
    })
  end
  instance.getServerSubscriptionFromIpV2 = function(self)
    return self:_request("GET", "v2/server-subscriptions/by-ip", {
      authenticated = false
    })
  end
  instance.setServerIpV2 = function(self, data)
    local resolved_server_id = self:_resolve_server_id(data and data.serverId)
    return self:_request("POST", "v2/servers/" .. tostring(resolved_server_id) .. "/server-ip", {
      body = strip_keys(data, { "serverId" })
    })
  end
  instance.setInGameSpeakerLocationsV2 = function(self, locations, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    return self:_request("PUT", "v2/servers/" .. tostring(resolved_server_id) .. "/speakers", {
      body = { locations = locations }
    })
  end
  instance.playToneV2 = function(self, room_id, tones, play_to, server_id)
    local resolved_server_id = self:_resolve_server_id(server_id)
    self:_assert_positive_integer(room_id, "roomId")
    return self:_request("POST", "v2/servers/" .. tostring(resolved_server_id) .. "/tones/play", {
      body = {
        roomId = room_id,
        tones = tones,
        playTo = play_to
      }
    })
  end

  instance.getCommunityV2 = function(self)
    return self:_request("GET", "v2/community")
  end
  instance.getSubVersionV2 = function(self)
    return self:_request("GET", "v2/community/sub-version")
  end
  instance.lookupCommunityV2 = function(self, query)
    return self:_request("GET", "v2/community/lookup", { query = query })
  end
  instance.getDepartmentsV2 = function(self)
    return self:_request("GET", "v2/community/departments")
  end
  instance.getProfileFieldsV2 = function(self)
    return self:_request("GET", "v2/community/profile-fields")
  end
  instance.getClockInTypesV2 = function(self)
    return self:_request("GET", "v2/community/clockin-types")
  end
  instance.getCustomLogTypesV2 = function(self)
    return self:_request("GET", "v2/community/custom-log-types")
  end
  instance.getPromotionFlowsV2 = function(self)
    return self:_request("GET", "v2/community/promotion-flows")
  end
  instance.triggerPromotionFlowsV2 = function(self, data)
    return self:_request("POST", "v2/community/promotion-flows/trigger", { body = data })
  end
  instance.undoRankChangeV2 = function(self, undo_id, data)
    return self:_request("POST", "v2/community/rank-changes/" .. self:_encode_path_segment(undo_id) .. "/undo", { body = data or {} })
  end
  instance.createShortUrlV2 = function(self, data)
    return self:_request("POST", "v2/community/short-urls", { body = data })
  end
  instance.getAccountsV2 = function(self, query)
    return self:_request("GET", "v2/community/accounts", { query = query })
  end
  instance.searchAccountsV2 = function(self, query)
    return self:_request("GET", "v2/community/accounts/search", { query = query })
  end
  instance.getAccountV2 = function(self, account_id)
    return self:_request("GET", "v2/community/accounts/" .. self:_encode_path_segment(account_id))
  end
  instance.getAccountRanksV2 = function(self, account_id)
    return self:_request("GET", "v2/community/accounts/" .. self:_encode_path_segment(account_id) .. "/ranks")
  end
  instance.getAccountIdentifiersV2 = function(self, account_id)
    return self:_request("GET", "v2/community/accounts/" .. self:_encode_path_segment(account_id) .. "/identifiers")
  end
  instance.registerAccountIdentifiersV2 = function(self, account_id, data)
    return self:_request("POST", "v2/community/accounts/" .. self:_encode_path_segment(account_id) .. "/identifiers", { body = data })
  end
  instance.setAccountNameV2 = function(self, account_id, data)
    return self:_request("PATCH", "v2/community/accounts/" .. self:_encode_path_segment(account_id) .. "/name", { body = data })
  end
  instance.setAccountRanksV2 = function(self, account_id, data)
    return self:_request("PATCH", "v2/community/accounts/" .. self:_encode_path_segment(account_id) .. "/ranks", { body = data })
  end
  instance.editProfileFieldsV2 = function(self, account_id, data)
    return self:_request("PATCH", "v2/community/accounts/" .. self:_encode_path_segment(account_id) .. "/profile-fields", { body = data })
  end
  instance.clockAccountV2 = function(self, account_id, data)
    return self:_request("POST", "v2/community/accounts/" .. self:_encode_path_segment(account_id) .. "/clock", { body = data })
  end
  instance.getCurrentClockInV2 = function(self, account_id)
    return self:_request("GET", "v2/community/accounts/" .. self:_encode_path_segment(account_id) .. "/clock/current")
  end
  instance.getLatestActivityV2 = function(self, account_id, query)
    return self:_request("GET", "v2/community/accounts/" .. self:_encode_path_segment(account_id) .. "/activity/latest", { query = query })
  end
  instance.forceSyncV2 = function(self, account_id, data)
    return self:_request("POST", "v2/community/accounts/" .. self:_encode_path_segment(account_id) .. "/sync", { body = data or {} })
  end
  instance.getServersV2 = function(self)
    return self:_request("GET", "v2/community/servers")
  end
  instance.setServersV2 = function(self, data)
    return self:_request("PUT", "v2/community/servers", { body = data })
  end
  instance.addServersV2 = function(self, data)
    return self:_request("POST", "v2/community/servers", { body = data })
  end
  instance.getAceConfigV2 = function(self, server_id)
    return self:_request("GET", "v2/community/servers/" .. tostring(self:_resolve_server_id(server_id)) .. "/ace-config")
  end
  instance.setAceConfigV2 = function(self, server_id, data)
    return self:_request("PATCH", "v2/community/servers/" .. tostring(self:_resolve_server_id(server_id)) .. "/ace-config", { body = data })
  end
  instance.setServerTypeV2 = function(self, server_id, data)
    return self:_request("PATCH", "v2/community/servers/" .. tostring(self:_resolve_server_id(server_id)) .. "/type", { body = data })
  end
  instance.verifyWhitelistV2 = function(self, server_id, data)
    return self:_request("POST", "v2/community/servers/" .. tostring(self:_resolve_server_id(server_id)) .. "/whitelist/check", { body = data })
  end
  instance.getWhitelistV2 = function(self, server_id)
    return self:_request("GET", "v2/community/servers/" .. tostring(self:_resolve_server_id(server_id)) .. "/whitelist")
  end
  instance.createActivityV2 = function(self, server_id, data)
    return self:_request("POST", "v2/community/servers/" .. tostring(self:_resolve_server_id(server_id)) .. "/activity", { body = data or {} })
  end
  instance.startActivityV2 = function(self, server_id, data)
    return self:_request("POST", "v2/community/servers/" .. tostring(self:_resolve_server_id(server_id)) .. "/activity/start", { body = data or {} })
  end
  instance.rsvpEventV2 = function(self, event_id, data)
    return self:_request("POST", "v2/community/events/" .. self:_encode_path_segment(event_id) .. "/rsvps", { body = data })
  end
  instance.changeFormStageV2 = function(self, form_id, data)
    return self:_request("PATCH", "v2/community/forms/" .. self:_encode_path_segment(form_id) .. "/stage", { body = data })
  end
  instance.getFormSubmissionsV2 = function(self, template_id, query)
    return self:_request("GET", "v2/community/forms/" .. self:_encode_path_segment(template_id) .. "/submissions", { query = query })
  end
  instance.getFormLockV2 = function(self, template_id)
    return self:_request("GET", "v2/community/forms/" .. self:_encode_path_segment(template_id) .. "/lock")
  end
  instance.setFormLockV2 = function(self, template_id, data)
    return self:_request("PATCH", "v2/community/forms/" .. self:_encode_path_segment(template_id) .. "/lock", { body = data })
  end
  instance.getSubmissionV2 = function(self, submission_id)
    return self:_request("GET", "v2/community/forms/submissions/" .. self:_encode_path_segment(submission_id))
  end
  instance.getRosterV2 = function(self, roster_id, query)
    return self:_request("GET", "v2/community/rosters/" .. self:_encode_path_segment(roster_id), { query = query })
  end
  instance.getDisciplinaryPointsV2 = function(self, account_id)
    return self:_request("GET", "v2/community/disciplinary/accounts/" .. self:_encode_path_segment(account_id) .. "/points")
  end
  instance.getDisciplinaryRecordsV2 = function(self, account_id)
    return self:_request("GET", "v2/community/disciplinary/accounts/" .. self:_encode_path_segment(account_id) .. "/records")
  end
  instance.addDisciplinaryRecordV2 = function(self, account_id, data)
    return self:_request("POST", "v2/community/disciplinary/accounts/" .. self:_encode_path_segment(account_id) .. "/records", { body = data })
  end
  instance.setDisciplinaryRecordPointsV2 = function(self, record_id, data)
    return self:_request("PATCH", "v2/community/disciplinary/records/" .. self:_encode_path_segment(record_id) .. "/points", { body = data })
  end
  instance.setDisciplinaryRecordReasonV2 = function(self, record_id, data)
    return self:_request("PATCH", "v2/community/disciplinary/records/" .. self:_encode_path_segment(record_id) .. "/reason", { body = data })
  end
  instance.setDisciplinaryRecordStatusV2 = function(self, record_id, data)
    return self:_request("PATCH", "v2/community/disciplinary/records/" .. self:_encode_path_segment(record_id) .. "/status", { body = data })
  end
  instance.getOnlinePlayersV2 = function(self, query)
    return self:_request("GET", "v2/community/erlc/players/online", { query = query })
  end
  instance.getPlayerQueueV2 = function(self, query)
    return self:_request("GET", "v2/community/erlc/players/queue", { query = query })
  end
  instance.addErlcRecordV2 = function(self, data)
    return self:_request("POST", "v2/community/erlc/records", { body = data })
  end
  instance.executeErlcCommandV2 = function(self, data)
    return self:_request("POST", "v2/community/erlc/commands", { body = data })
  end
  instance.lockTeamV2 = function(self, data)
    return self:_request("POST", "v2/community/erlc/teams/lock", { body = data })
  end
  instance.unlockTeamV2 = function(self, data)
    return self:_request("POST", "v2/community/erlc/teams/unlock", { body = data })
  end
  instance.getCurrentSessionV2 = function(self, server_id)
    return self:_request("GET", "v2/community/sessions/current", { query = { serverId = self:_resolve_server_id(server_id) } })
  end
  instance.startSessionV2 = function(self, data)
    return self:_request("POST", "v2/community/sessions", { body = data })
  end
  instance.stopSessionV2 = function(self, data)
    return self:_request("PATCH", "v2/community/sessions", { body = data })
  end
  instance.cancelSessionV2 = function(self, data)
    return self:_request("DELETE", "v2/community/sessions", { body = data })
  end

  return instance
end

return create_client
