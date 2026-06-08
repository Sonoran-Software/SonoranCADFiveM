local function encode_uri_component(value)
  return tostring(value):gsub("([^%w%-%._~])", function(char)
    return string.format("%%%02X", string.byte(char))
  end)
end

local function perform_request(options, callback)
  PerformHttpRequest(
    options.url,
    callback,
    options.method or "GET",
    options.body,
    options.headers or {}
  )
end

return function()
  return {
    encode = function(value)
      return json.encode(value)
    end,
    decode = function(value)
      return json.decode(value)
    end,
    encodeURIComponent = encode_uri_component,
    sleep = function(delay_ms)
      local deferred = promise.new()
      local resolved = false

      local function finish()
        if resolved then
          return
        end

        resolved = true
        deferred:resolve(true)
      end

      if SetTimeout and tonumber(delay_ms) and tonumber(delay_ms) > 0 then
        SetTimeout(tonumber(delay_ms), finish)
      else
        finish()
      end

      return Citizen.Await(deferred)
    end,
    request = function(options)
      local deferred = promise.new()
      local settled = false
      local timeout_ms = tonumber(options.timeoutMs) or 30000

      local function settle(result)
        if settled then
          return
        end

        settled = true
        deferred:resolve(result)
      end

      if SetTimeout and timeout_ms > 0 then
        SetTimeout(timeout_ms, function()
          settle({
            ok = false,
            status = 408,
            headers = {},
            body = "Request timed out."
          })
        end)
      end

      perform_request(
        options,
        function(status_code, body, headers)
          settle({
            ok = type(status_code) == "number" and status_code >= 200 and status_code < 300,
            status = status_code or 0,
            headers = headers or {},
            body = body
          })
        end
      )

      return Citizen.Await(deferred)
    end
  }
end
