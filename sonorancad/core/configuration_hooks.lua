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

function MatchFiveMConfigHook(value, path)
    if hooks[path] and string.dump(value, true) == string.dump(hooks[path], true) then return 'builtin:' .. path end
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
