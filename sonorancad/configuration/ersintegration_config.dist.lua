--[[
    Sonoran Plugins

    Plugin Configuration

    Put all needed configuration in this file.
]]
local config = {
    enabled = false,
    pluginName = "ersintegration", -- name your plugin here
    pluginAuthor = "SonoranCAD", -- author
    configVersion = "1.4",
    -- put your configuration options below
    DOBFormat = "en", -- Make sure this matches | en: dd/mm/yyyy | us: mm/dd/yyyy | iso: yyyy/mm/dd
    clearRecordsAfter = 30, -- Clear records after this many minutes (0 = never)
    create911Call = true, -- Create a 911 call when an ERS callout is created
    createEmergencyCall = true, -- Create an emergency call when an ERS callout is accepted
    callPriority = 2, -- Priority of the call created in CAD (1-3) | Only used if createEmergencyCall is true
    callCodes = {
        ['Stolen_motorbike'] = '10-22'
    }, -- Call codes for each ERS callout type | Only used if createEmergencyCall is true
    autoAddCall = true, -- Automatically add members to the call when an ERS callout is accepted
    customRecords = {
        civilianRecordID = 7, -- Record ID for civilian records
        civilianValues = {
            -- Configurable mapping for SonoranCAD replaceValues.
            -- The key is what SonoranCAD expects and the value is either:
            --    • A string that matches a key in pedData, or
            --    • A function that returns a value based on pedData.
            --    • Left side of mapping is the SonoranCAD field mapping ID from Custom Records, right side is the ERS field.
            ["first"] = "FirstName",
            ["last"] = "LastName",
            ["dob"] = "DOB",
            ["age"] = function(pedData)
                return returnAgeFromDobString(pedData.DOB)
            end,
            ["sex"] = "Gender",
            ["residence"] = "Address",
            ["zip"] = "PostalCode",
            ["phone"] = "Phone",
            ["skin"] = "Nationality",
            ["img"] = "ProfilePicture"
            -- Add more keys as needed:
            -- email = "Email"  -- Example: if pedData.Email exists.
        },
        vehicleRegistrationRecordID = 5, -- Record ID for vehicle registration records
        vehicleRegistrationValues = {
            -- Configurable mapping for SonoranCAD replaceValues.
            -- The key is what SonoranCAD expects and the value is either:
            --    • A string that matches a key in pedData, or
            --    • A function that returns a value based on pedData.
            --    • Left side of mapping is the SonoranCAD field mapping ID from Custom Records, right side is the ERS field.
            -- Registration Information
            ["status"] = function(vehicleData)
                if vehicleData.stolen then
                    return "STOLEN"
                elseif not vehicleData.mot then
                    return "EXPIRED"
                else
                    return "VALID"
                end
            end,
            ["_wsakvwigt"] = function(vehicleData)
                return '1'
            end,
            ["_imtoih149"] = function(vehicleData)
                if not vehicleData.mot then
                    return generateDate(365, true)
                end

                return generateDate(365, false)
            end,
            -- Civilian Information
            ["first"] = function(vehicleData)
                local ownerName = tostring(vehicleData.owner_name or "")
                return ownerName:match("^(%S+)") or ""
            end,
            ["last"] = function(vehicleData)
                local ownerName = tostring(vehicleData.owner_name or "")
                return ownerName:match("%s(.+)$") or ""
            end,
            -- Vehicle Information
            ["plate"] = "license_plate",
            ["make"] = "make",
            ["model"] = "model",
            ["color"] = function(vehicleData)
                local primaryColor = tostring(vehicleData.color or "")
                local secondaryColor = tostring(vehicleData.color_secondary or "")
                if secondaryColor ~= "" then
                    return primaryColor .. ", " .. secondaryColor
                else
                    return primaryColor
                end
            end,
            ["year"] = "build_year",
            ["type"] = function(vehicleData)
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
            ["img"] = "vehicle_picture_url",
        -- Add more keys as needed:
        -- owner = "Owner"  -- Example: if pedData.Owner exists.
        },
        licenseRecordId = 4, -- Record ID for license records
        licenseTypeField = "7eddab31daf4a0182", -- Field ID for license type
        licenseTypeConfigs = {
            DRIVER = {
                type = "DRIVER",
                is_valid = "License_Car_Is_Valid",
                license = "License_Car",
            },
            MOTORCYCLE = {
                type = "MOTORCYCLE",
                is_valid = "License_Bike_Is_Valid",
                license = "License_Bike",
            },
            BOAT = {
                type = "BOAT",
                is_valid = "License_Boat_Is_Valid",
                license = "License_Boat",
            },
            PILOT = {
                type = "PILOT",
                is_valid = "License_Pilot_Is_Valid",
                license = "License_Pilot",
            },
            CDL = {
                type = "CDL",
                is_valid = "License_Truck_Is_Valid",
                license = "License_Truck",
            },
        },
        licenseRecordValues = {
            -- License Information
            ["252c4250da9421cbd"] = function(pedData, ctx)
                return "APPROVED"
            end,
            ["878766af4964853a7"] = function(pedData, ctx)
                if (pedData[ctx.license]) == "Revoked" then
                    return "SUSPENDED"
                end

                if (pedData[ctx.license]) == "Expired" then
                    return "EXPIRED"
                end

                return pedData[ctx.is_valid] and "VALID" or "EXPIRED"
            end,
            ["_54iz1scv7"] = function(pedData, ctx)
                if pedData[ctx.license] == "Expired" then
                    return generateDate(365, true)
                end

                return generateDate(365, false)
            end,
            -- Civilian Information
            ["first"] = "FirstName",
            ["last"] = "LastName",
            ["mi"] = function(pedData)
                if (math.random() > 0.1) then
                    return ""
                end

                return string.char(math.random(65, 90))
            end,
            ["dob"] = "DOB",
            ["age"] = function(pedData)
                return returnAgeFromDobString(pedData.DOB)
            end,
            ["sex"] = "Gender",
            ["residence"] = "Address",
            ["zip"] = "PostalCode",
        },
        boloRecordID = 3, -- Record ID for BOLO records
        boloRecordValues = {
            ['_olgxdruc3'] = 'bolo_description'
        },
        warrantRecordID = 2, -- Record ID for warrant records
        warrantDescription = '_avb6wvgyi', -- Field ID for warrant description
        warrantFlags = '_hlshajq0f' -- Field ID for warrant flags
    }

}

if config.enabled then Config.RegisterPluginConfig(config.pluginName, config) end

function returnAgeFromDobString(dobString)
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
        warnLog("Unsupported DOB format: " .. tostring(config.DOBFormat))
    end

    if type(day) ~= "number" or type(month) ~= "number" or type(year) ~= "number" then
        warnLog("Invalid DOB in ERS config age calculation: " .. tostring(dobString) .. " | This invalid format will result in age being returned as blank in SonoranCAD, your character will still be added to SonoranCAD. Please ensure DOBFormat is set correctly and DOB is in the correct format in your custom ERS callout.")
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
