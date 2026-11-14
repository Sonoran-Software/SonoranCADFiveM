-- Runtime helpers for the ERS field-mapping callbacks. Each configuration gets
-- its own bindings so DOBFormat stays local and helper code need not be saved in CAD.
function CreateErsDateHelpers(config)
    local function returnAgeFromDobString(dobString)
        dobString = tostring(dobString or "12/12/2000") -- Default DOB if none provided
        local day, month, year

        if config.DOBFormat == "en" then -- dd/mm/yyyy
            day = tonumber(dobString:sub(1,2))
            month = tonumber(dobString:sub(4,5))
            year = tonumber(dobString:sub(7,10))

        elseif config.DOBFormat == "us" then -- mm/dd/yyyy
            month = tonumber(dobString:sub(1,2))
            day = tonumber(dobString:sub(4,5))
            year = tonumber(dobString:sub(7,10))

        elseif config.DOBFormat == "iso" then -- yyyy/mm/dd
            year = tonumber(dobString:sub(1,4))
            month = tonumber(dobString:sub(6,7))
            day = tonumber(dobString:sub(9,10))
        else
            warnLog("UNHANDLED_WARNING", "Unsupported DOB format: " .. tostring(config.DOBFormat))
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

    local function generateDate(maxdays, before)
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
        local format_type = string.lower(config.DOBFormat or "")

        if format_type == "us" then
            format_string = "%m/%d/%Y"
        elseif format_type == "en" then
            format_string = "%d/%m/%Y"
        else -- Default to ISO
            format_string = "%Y/%m/%d"
        end

        return os.date(format_string, target_time)
    end

    return {returnAgeFromDobString = returnAgeFromDobString, generateDate = generateDate}
end
