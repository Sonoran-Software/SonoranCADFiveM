-- Shared helpers used by both client and server.

local isServer = IsDuplicityVersion and IsDuplicityVersion() or false

---@generic T
---@param orig T
---@return T
function shallowcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

---@param inputstr string
---@param sep string|nil
---@return table
function stringsplit(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t={} ; i=1
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        t[i] = str
        i = i + 1
    end
    return t
end

-- Helper function to determine index of given identifier
---@param identifier any
---@return number|nil
function findIndex(identifier)
    for i,loc in ipairs(LocationCache) do
        if loc.apiId == identifier then
            return i
        end
    end
end

---@param player number
---@return table
function GetIdentifiers(player)
    if not isServer then
        warnLog("GetIdentifiers is server-only.")
        return {}
    end
    local ids = {}
    for _, id in ipairs(GetPlayerIdentifiers(player)) do
        local split = stringsplit(id, ":")
        ids[split[1]] = split[2]
    end
    --debugLog("Returning "..json.encode(ids))
    return ids
end

---@param pluginName string
---@return boolean
function isPluginLoaded(pluginName)
    for k, v in pairs(Plugins) do
        if v == pluginName then
            return true
        end
    end
    return false
end

exports('isPluginLoaded', isPluginLoaded)

function PerformHttpRequestS(url, cb, method, data, headers)
    if not data then
        data = ""
    end
    if not headers then
        headers = {["X-User-Agent"] = "SonoranCAD"}
    end
    exports["sonorancad"]:HandleHttpRequest(url, cb, method, data, headers)
end

---@param tab table
---@param val any
---@return boolean
function has_value(tab, val)
    if tab == nil then
        debugLog("nil passed to has_value, ignore")
        return false
    end
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

---@return string
function getServerVersion()
    local s = GetConvar("version", "")
    local v = s:find("v1.0.0.")
    local e = string.gsub(s:sub(v),"v1.0.0.","")
    local i = e:sub(1, string.len(e) - e:find(" "))
    return i
end

---@param version1 string
---@param version2 string
---@return table
function compareVersions(version1, version2)
    local v1, v2, v3 = version1:match("(%d+)%.(%d*)%.?(%d*)")
    local r1, r2, r3 = version2:match("(%d+)%.(%d*)%.?(%d*)")

    -- Convert to numbers and default to 0 for minor and patch if missing
    v1, v2, v3 = tonumber(v1) or 0, tonumber(v2) or 0, tonumber(v3) or 0
    r1, r2, r3 = tonumber(r1) or 0, tonumber(r2) or 0, tonumber(r3) or 0

    -- Calculate parsed versions with proper weights
    local parsedVersion1 = v1 * 10000 + v2 * 100 + v3
    local parsedVersion2 = r1 * 10000 + r2 * 100 + r3

    -- Create debug log table
    local tbl = {
        result = (parsedVersion2 < parsedVersion1),
        parsedVersion1 = parsedVersion1,
        parsedVersion2 = parsedVersion2,
        version1 = version1,
        version2 = version2
    }
    debugLog(json.encode(tbl))

    return tbl
end
