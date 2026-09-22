-- Trusted built-in transforms. Remote configuration is data, never Lua code.
function returnAgeFromDobString(dobString)
    dobString = tostring(dobString or "12/12/2000") -- Default DOB if none provided
    local day, month, year

    if (Config.plugins.ersintegration or {}).DOBFormat == "en" then -- dd/mm/yyyy
        day = tonumber(dobString:sub(1,2))
        month = tonumber(dobString:sub(4,5))
        year = tonumber(dobString:sub(7,10))

    elseif (Config.plugins.ersintegration or {}).DOBFormat == "us" then -- mm/dd/yyyy
        month = tonumber(dobString:sub(1,2))
        day = tonumber(dobString:sub(4,5))
        year = tonumber(dobString:sub(7,10))

    elseif (Config.plugins.ersintegration or {}).DOBFormat == "iso" then -- yyyy/mm/dd
        year = tonumber(dobString:sub(1,4))
        month = tonumber(dobString:sub(6,7))
        day = tonumber(dobString:sub(9,10))
    else
        warnLog("UNHANDLED_WARNING", "Unsupported DOB format: " .. tostring((Config.plugins.ersintegration or {}).DOBFormat))
    end

    if type(day) ~= "number" or type(month) ~= "number" or type(year) ~= "number" then
        warnLog("UNHANDLED_WARNING", "Invalid DOB in ERS config age calculation: " .. tostring(dobString) .. " | This invalid format will result in age being returned as blank in SonoranCAD, your character will still be added to SonoranCAD. Please ensure DOBFormat is set correctly and DOB is in the correct format in your custom ERS callout.")
        return ""
    end

    local today = os.date("*t")
    local age = today.year - year

    if today.month < month or (today.month == month and today.day < day) then
        age = age - 1
    end

    return tostring(age)
end

function generateDate(maxdays, before)
    local SECONDS_IN_DAY = 60 * 60 * 24
    local CURRENT_TIME = os.time()
    local OFFSET_SECONDS = math.random(1, maxdays) * SECONDS_IN_DAY

    local target_time
    if (before) then
        target_time = CURRENT_TIME - OFFSET_SECONDS
    else
        target_time = CURRENT_TIME + OFFSET_SECONDS
    end

    local format_string
    local format_type = string.lower((Config.plugins.ersintegration or {}).DOBFormat or "")

    if format_type == "us" then
        format_string = "%m/%d/%Y"
    elseif format_type == "en" then
        format_string = "%d/%m/%Y"
    else -- Default to ISO
        format_string = "%Y/%m/%d"
    end

    return os.date(format_string, target_time)
end


local hooks = {
    ["plugins.caddisplay.custom.permissionCheck"] = function(_, type) -- Always called server side.
            if type == 0 then -- Check permission to use the menu
                return true or false -- Return true if permitted, false otherwise
            elseif type == 1 then -- Check permission to manage station display placements
                return true or false -- Return true if permitted, false otherwise
            end
        end,
    ["plugins.ersintegration.customRecords.civilianValues.age"] = function(pedData)
                return returnAgeFromDobString(pedData.DOB)
            end,
    ["plugins.ersintegration.customRecords.licenseRecordValues.252c4250da9421cbd"] = function(pedData, ctx)
                return "APPROVED"
            end,
    ["plugins.ersintegration.customRecords.licenseRecordValues.878766af4964853a7"] = function(pedData, ctx)
                if (pedData[ctx.license]) == "Revoked" then
                    return "SUSPENDED"
                end

                if (pedData[ctx.license]) == "Expired" then
                    return "EXPIRED"
                end

                return pedData[ctx.is_valid] and "VALID" or "EXPIRED"
            end,
    ["plugins.ersintegration.customRecords.licenseRecordValues._54iz1scv7"] = function(pedData, ctx)
                if pedData[ctx.license] == "Expired" then
                    return generateDate(365, true)
                end

                return generateDate(365, false)
            end,
    ["plugins.ersintegration.customRecords.licenseRecordValues.age"] = function(pedData)
                return returnAgeFromDobString(pedData.DOB)
            end,
    ["plugins.ersintegration.customRecords.licenseRecordValues.mi"] = function(pedData)
                if (math.random() > 0.1) then
                    return ""
                end

                return string.char(math.random(65, 90))
            end,
    ["plugins.ersintegration.customRecords.vehicleRegistrationValues._imtoih149"] = function(vehicleData)
                if not vehicleData.mot then
                    return generateDate(365, true)
                end

                return generateDate(365, false)
            end,
    ["plugins.ersintegration.customRecords.vehicleRegistrationValues._wsakvwigt"] = function(vehicleData)
                return '1'
            end,
    ["plugins.ersintegration.customRecords.vehicleRegistrationValues.color"] = function(vehicleData)
                local primaryColor = tostring(vehicleData.color or "")
                local secondaryColor = tostring(vehicleData.color_secondary or "")
                if secondaryColor ~= "" then
                    return primaryColor .. ", " .. secondaryColor
                else
                    return primaryColor
                end
            end,
    ["plugins.ersintegration.customRecords.vehicleRegistrationValues.first"] = function(vehicleData)
                local ownerName = tostring(vehicleData.owner_name or "")
                return ownerName:match("^(%S+)") or ""
            end,
    ["plugins.ersintegration.customRecords.vehicleRegistrationValues.last"] = function(vehicleData)
                local ownerName = tostring(vehicleData.owner_name or "")
                return ownerName:match("%s(.+)$") or ""
            end,
    ["plugins.ersintegration.customRecords.vehicleRegistrationValues.status"] = function(vehicleData)
                if vehicleData.stolen then
                    return "STOLEN"
                elseif not vehicleData.mot then
                    return "EXPIRED"
                else
                    return "VALID"
                end
            end,
    ["plugins.ersintegration.customRecords.vehicleRegistrationValues.type"] = function(vehicleData)
                local classMap = {
                    [0] = "COMPACT", [1] = "SEDAN", [2] = "SUV", [3] = "COUPE",
                    [4] = "MUSCLE", [5] = "SPORTS", [6] = "SPORTS", [7] = "SPORTS",
                    [8] = "MOTORCYCLE", [9] = "OFFROAD", [10] = "COMMERCIAL",
                    [11] = "COMMERCIAL", [12] = "VAN", [13] = "CYCLE", [14] = "MARINE",
                    [15] = "AIRCRAFT", [16] = "AIRCRAFT", [17] = "COMMERCIAL",
                    [18] = "EMERGENCY", [19] = "MILITARY", [20] = "COMMERCIAL",
                    [21] = "RAIL", [22] = "SPORTS"
                }
                return classMap[vehicleData.vehicle_class] or "SEDAN"
            end,
}

local function hookFingerprint(value)
    local dumped = string.dump(value, true)
    -- Lua 5.4 keeps the prototype's line range even in a stripped chunk. Remove
    -- the two variable-length integers so identical functions from old config
    -- files compare independently of where they appeared in the source file.
    local position = 34
    for _ = 1, 2 do
        while position <= #dumped do
            local byte = dumped:byte(position)
            position = position + 1
            if byte >= 0x80 then break end
        end
    end
    return dumped:sub(1, 33) .. dumped:sub(position)
end

function MatchFiveMConfigHook(value, path)
    if not hooks[path] or type(value) ~= "function" then return nil end
    local leftOk, left = pcall(hookFingerprint, value)
    local rightOk, right = pcall(hookFingerprint, hooks[path])
    if leftOk and rightOk and left == right then return 'builtin:' .. path end
    return nil
end

function ResolveFiveMConfig(value, path)
    path = path or ""
    if type(value) == "string" and value:sub(1,8) == "builtin:"
        and (path:find('ersintegration.customRecords', 1, true) or path == '.caddisplay.custom.permissionCheck') then
        return hooks[value:sub(9)]
    end
    if type(value) ~= "table" then return value end
    local result = {}
    local valueMeta = getmetatable(value)
    if valueMeta then setmetatable(result, valueMeta) end
    for k,v in pairs(value) do
        local key = k
        if path:find('localcallers.clothingConfig', 1, true) or path:find('localcallers.weaponConfig.weaponResponses', 1, true) then key = tonumber(k) or k end
        result[key] = ResolveFiveMConfig(v, path .. '.' .. tostring(k))
    end
    if path:match('localcallers%.whitelistZones%.%d+%.center$') then
        return vector3(result.x, result.y, result.z)
    end
    return result
end

function unitDutyCustom(player) return false end

local bootstrapConfigKeys = {
    communityID = true,
    apiKey = true,
    serverId = true,
    mode = true
}

local function isArray(value)
    if type(value) ~= "table" then return false end
    local count = 0
    local highest = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        count = count + 1
        if key > highest then highest = key end
    end
    return count > 0 and highest == count
end

local function cloneConfigValue(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    local valueMeta = getmetatable(value)
    if valueMeta then setmetatable(copy, valueMeta) end
    seen[value] = copy
    for key, entry in pairs(value) do copy[key] = cloneConfigValue(entry, seen) end
    return copy
end

function MergeFiveMConfig(base, override)
    if type(override) ~= "table" then
        return override ~= nil and override or cloneConfigValue(base)
    end
    if next(override) == nil then
        local cleared = cloneConfigValue(override)
        local baseMeta = type(base) == "table" and getmetatable(base) or nil
        if baseMeta and not getmetatable(cleared) then setmetatable(cleared, baseMeta) end
        return cleared
    end
    if isArray(override) then return cloneConfigValue(override) end

    local result = type(base) == "table" and cloneConfigValue(base) or {}
    for key, value in pairs(override) do
        if type(value) == "table" and not isArray(value) and type(result[key]) == "table" and not isArray(result[key]) then
            result[key] = MergeFiveMConfig(result[key], value)
        else
            result[key] = cloneConfigValue(value)
        end
    end
    return result
end

local function readJsonFile(path)
    local raw = LoadResourceFile(GetCurrentResourceName(), path)
    if not raw or raw == "" then return nil end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= "table" then return nil end
    return decoded
end

local function loadLegacyPluginConfig(name, path, source)
    local proxyConfig = setmetatable({
        RegisterPluginConfig = function() end
    }, {__index = Config})
    local env = setmetatable({Config = proxyConfig}, {
        __index = _G,
        -- Preserve trusted customer-defined hooks exactly as the old manifest did.
        __newindex = _G
    })
    local chunk, loadError = load(source .. "\nreturn config", "@@" .. path, "t", env)
    if not chunk then return nil, loadError end
    local ok, loaded = pcall(chunk)
    if not ok then return nil, loaded end
    if type(loaded) ~= "table" then return nil, name .. " did not return a config table" end
    return loaded
end

function LoadLocalFiveMConfiguration()
    local state = {
        detected = false,
        core = {},
        plugins = {},
        files = {},
        errors = {}
    }

    local localCore = readJsonFile("configuration/config.json")
    if localCore then
        for key, value in pairs(localCore) do
            if not bootstrapConfigKeys[key] then
                state.detected = true
                state.core[key] = value
            end
        end
    end

    local version = readJsonFile("version.json") or {}
    local pluginNames = {}
    for name in pairs(version.submoduleConfigs or {}) do pluginNames[#pluginNames + 1] = name end
    table.sort(pluginNames)

    for _, name in ipairs(pluginNames) do
        local normalPath = "configuration/" .. name .. "_config.lua"
        local distPath = "configuration/" .. name .. "_config.dist.lua"
        local path = normalPath
        local source = LoadResourceFile(GetCurrentResourceName(), normalPath)
        if not source then
            path = distPath
            source = LoadResourceFile(GetCurrentResourceName(), distPath)
        end
        if source then
            state.detected = true
            state.files[#state.files + 1] = path
            local plugin, loadError = loadLegacyPluginConfig(name, path, source)
            if plugin then
                state.plugins[name] = plugin
            else
                state.errors[#state.errors + 1] = path .. ": " .. tostring(loadError)
            end
        end
    end

    local models = readJsonFile("configuration/livemap_vehicle_models.json")
    if models then
        state.detected = true
        state.files[#state.files + 1] = "configuration/livemap_vehicle_models.json"
        state.plugins.locations = state.plugins.locations or {}
        state.plugins.locations.vehicleModels = models
    end

    return state
end

local function appendSerializationError(errors, path, message)
    if type(errors) == "table" then errors[#errors + 1] = path .. ": " .. message end
end

function SerializeFiveMConfig(value, path, errors, seen)
    path = path or ""
    local kind = type(value)
    if kind == "function" then
        local hook = MatchFiveMConfigHook(value, path)
        if hook then return hook end
        appendSerializationError(errors, path, "custom Lua function requires a reviewed named hook")
        return nil
    end
    if kind == "vector2" or kind == "vector3" or kind == "vector4" then
        local serialized = {x = value.x, y = value.y}
        if value.z ~= nil then serialized.z = value.z end
        if value.w ~= nil then serialized.w = value.w end
        return serialized
    end
    if kind ~= "table" then return value end

    seen = seen or {}
    if seen[value] then
        appendSerializationError(errors, path, "cyclic table is not supported")
        return nil
    end
    seen[value] = true

    local result = {}
    local valueMeta = getmetatable(value)
    if valueMeta then setmetatable(result, valueMeta) end
    if isArray(value) then
        for index, entry in ipairs(value) do
            result[index] = SerializeFiveMConfig(entry, path .. "." .. tostring(index), errors, seen)
        end
    else
        for key, entry in pairs(value) do
            local serialized = SerializeFiveMConfig(entry, path .. "." .. tostring(key), errors, seen)
            if serialized ~= nil then result[tostring(key)] = serialized end
        end
    end
    seen[value] = nil
    return result
end
