local function decodeFileOperationResult(encoded, context)
    if type(encoded) ~= "string" or encoded == "" then
        return nil, context .. " returned no result"
    end
    local ok, decoded = pcall(json.decode, encoded)
    if not ok or type(decoded) ~= "table" then
        return nil, context .. " returned invalid JSON"
    end
    return decoded
end

function AugmentLocalFiveMConfigurationInventory(state)
    if type(state) ~= "table" then return state end
    local ok, encoded = pcall(function()
        return exports[GetCurrentResourceName()]:GetLegacyConfigurationFiles()
    end)
    if not ok then
        state.errors[#state.errors + 1] = "Unable to scan the configuration directory: " .. tostring(encoded)
        return state
    end

    local result, decodeError = decodeFileOperationResult(encoded, "Configuration scan")
    if not result then
        state.errors[#state.errors + 1] = decodeError
        return state
    end
    if result.error then
        state.errors[#state.errors + 1] = "Configuration scan failed: " .. tostring(result.error)
        return state
    end

    local seen = {}
    for _, path in ipairs(state.files or {}) do seen[path] = true end
    for _, path in ipairs(result.files or {}) do
        if not seen[path] then
            state.files[#state.files + 1] = path
            seen[path] = true
            if not path:find("configuration/config-backup/", 1, true) then
                state.errors[#state.errors + 1] = path .. ": no matching CAD configuration catalog entry"
            end
        end
    end
    table.sort(state.files)
    if #state.files > 0 then state.detected = true end
    return state
end

function DeleteLocalFiveMConfigurationFiles()
    local ok, encoded = pcall(function()
        return exports[GetCurrentResourceName()]:DeleteLegacyConfigurationFiles()
    end)
    if not ok then return nil, tostring(encoded) end
    local result, decodeError = decodeFileOperationResult(encoded, "Configuration cleanup")
    if not result then return nil, decodeError end
    if result.success ~= true then
        return nil, table.concat(result.errors or {"unknown file cleanup failure"}, "; ")
    end
    return result
end
