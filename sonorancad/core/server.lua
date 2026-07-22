Plugins = {}

ApiUrls = {
    production = "https://api.sonorancad.com/",
    development = "https://staging-api.dev.sonorancad.com/"
}

function getApiUrl()
    if Config.mode == nil then
        return ApiUrls.production
    else
        if ApiUrls[Config.mode] ~= nil then
            return ApiUrls[Config.mode]
        else
            warnLog("INVALID_API_MODE")
            return ApiUrls.production
        end
    end
end

local function validateBundledCfgPermissions()
    local raw = LoadResourceFile(GetCurrentResourceName(), "sonorancad.cfg")
    if type(raw) ~= "string" or raw == "" then
        return
    end

    local requiredLines = {
        BODYCAM_F8_PERMISSION = {
            "add_ace builtin%.everyone command%.SonoranCAD::bodycam::Keybind allow",
            "add_ace builtin%.everyone command%.SonoranCAD::bodycam::RecordingKeybind allow"
        },
        CADDISPLAY_F8_PERMISSION = {
            "add_ace builtin%.everyone command%.SonoranCAD::caddisplay::Interact allow",
            "add_ace builtin%.everyone command%.SonoranCAD::caddisplay::AcceptRequest allow",
            "add_ace builtin%.everyone command%.SonoranCAD::caddisplay::DenyRequest allow"
        },
        PANIC_F8_PERMISSION = {
            "add_ace builtin%.everyone command%.panic allow"
        }
    }

    for errorKey, patterns in pairs(requiredLines) do
        for _, pattern in ipairs(patterns) do
            if not raw:find(pattern) then
                warnLog("UNHANDLED_WARNING", getWarningText(errorKey) or getErrorText(errorKey) or tostring(errorKey))
                break
            end
        end
    end
end

CreateThread(function()
    local ok, err = xpcall(function()
        infoLog("Starting SonoranCAD from "..GetResourcePath("sonorancad"))
        Config.apiUrl = getApiUrl()
        validateBundledCfgPermissions()

        local clear_ok, clear_err = pcall(function()
            exports['sonorancad']:clearScreenshotsFolder()
        end)
        if not clear_ok then
            warnLog("UNHANDLED_WARNING", ("Failed to clear screenshots folder on startup: %s"):format(tostring(clear_err)))
        end

        local versionResponse = CadApiGetVersion()
        if not versionResponse.success then
            CadApiLogFailure("GET_VERSION", versionResponse, {})
            logError("API_ERROR")
            Config.critError = true
            return
        end

        local result = tostring(versionResponse.data or "")
        Config.apiVersion = tonumber(string.sub(result, 1, 1)) or -1
        debugLog(("Set version %s from response %s"):format(Config.apiVersion, result))
        infoLog(("Loaded community ID %s with API URL: %s"):format(Config.communityID, Config.apiUrl))

        if Config.primaryIdentifier == "steam" and (GetConvar("steam_webapiKey", "none") == "none" or GetConvar("steam_webapiKey", "none") == "") then
            logError("STEAM_ERROR")
            Config.critError = true
        end

        local versionRaw = LoadResourceFile(GetCurrentResourceName(), "version.json")
        local versionfile = versionRaw and json.decode(versionRaw) or nil
        local fxversion = versionfile and versionfile.testedFxServerVersion or nil
        local currentFxVersion = getServerVersion()
        if currentFxVersion ~= nil and fxversion ~= nil then
            if tonumber(currentFxVersion) < tonumber(fxversion) then
                warnLog("OLD_FXSERVER_VERSION", ("SonoranCAD has been tested with FXServer version %s, but you're running %s. Please update ASAP."):format(fxversion, currentFxVersion))
            end
        end

        if GetResourceState("sonoran_updatehelper") == "started" then
            ExecuteCommand("stop sonoran_updatehelper")
        end

        manuallySetUnitCache() -- set unit cache on startup
    end, function(runtimeErr)
        return SanitizeErrorDetail(runtimeErr)
    end)

    if not ok then
        Config.critError = true
        errorLog("UNHANDLED_SERVER_ERROR", ("Startup initialization failed: %s"):format(SanitizeErrorDetail(err) or "unknown startup failure"))
    end
end)

exports("getCadVersion", function()
    return Config.apiVersion
end)

-- Toggles API sender.
RegisterServerEvent("cadToggleApi")
AddEventHandler("cadToggleApi", function()
    Config.apiSendEnabled = not Config.apiSendEnabled
    if Config.apiSendEnabled then
        infoLog("API sending has been enabled.")
    else
        errorLog("CAD_API_DISABLED", "API sending has been disabled via cadToggleApi.")
    end
end)

-- Metrics
CreateThread(function()
    while true do
        -- Wait a few seconds for server startup
        Wait(5000)
        local coreVersion = GetResourceMetadata(GetCurrentResourceName(), "version", 0)
        SetConvarServerInfo("SonoranCADVersion", coreVersion)
        local plugins = {}
        local playerCount = GetNumPlayerIndices()
        for k, v in pairs(Config.plugins) do
            table.insert(plugins, {["name"] = k, ["version"] = v.version, ["latest"] = v.latestVersion, ["enabled"] = v.enabled})
        end
        local payload = {
            coreVersion = coreVersion,
            commId = Config.communityID,
            playerCount = playerCount,
            serverId = tonumber(tonumber(Config.serverId)),
            fxVersion = getServerVersion(),
            plugins = plugins,
            ingressUrl = GetConvar("web_baseUrl", "")
        }
        local response = CadApiHeartbeat(payload)
        if not response.success then
            CadApiLogFailure("HEARTBEAT", response, payload)
        end
        Wait(1000*60*60)
    end
end)

if Config.devHiddenSwitch then
    RegisterCommand("cc", function()
        TriggerClientEvent("chat:clear", -1)
    end)
end

-- Missing identifier detection
RegisterNetEvent("SonoranCAD::core:PlayerReady")
AddEventHandler("SonoranCAD::core:PlayerReady", function()
    local ids = GetIdentifiers(source)
    if ids[Config.primaryIdentifier] == nil then
        warnLog("PLAYER_IDENTIFIER_MISSING", ("Player %s connected, but did not have an %s ID."):format(source, Config.primaryIdentifier))
    end
end)

-- Jordan - Add universal handler for 911 calls
--[[
    SonoranCAD API Handler - 911 Calls
    @param caller string
    @param location string
    @param description string
    @param postal number
    @param plate string (optional)
    @param cb function
    @param silenceAlert boolean
    @param useCallLocation boolean
]]
function call911(caller, location, description, postal, plate, cb, silenceAlert, useCallLocation, deleteAfter)
    if not silenceAlert then
        silenceAlert = false
    end
    if not useCallLocation then
        useCallLocation = false
    end
    local data = {
        ['serverId'] = GetConvar('sonoran_serverId', 1),
        ['isEmergency'] = true,
        ['caller'] = caller,
        ['location'] = location,
        ['description'] = description,
        ['metaData'] = {
            ['plate'] = plate or "",
            ['postal'] = postal or "",
            ['useCallLocation'] = useCallLocation,
            ['silenceAlert'] = silenceAlert
        }
    }
    if deleteAfter then
        data['deleteAfter'] = deleteAfter
    end
    local response = CadApiCreateEmergencyCall(data)
    if cb ~= nil then
        local result = response.callId ~= nil and ("EMERGENCY CALL ADDED ID: %s"):format(response.callId)
            or (response.success and json.encode(response.data or {}) or CadApiSupportErrorText("CALL_911", response))
        cb(result, response.success == true)
    elseif not response.success then
        CadApiLogFailure('CALL_911', response, data)
    end
end

RegisterNetEvent('SonoranScripts::Call911', function(caller, location, description, postal, plate, cb, silenceAlert, useCallLocation, deleteAfter)
	call911(caller, location, description, postal, plate, function(response)
		json.encode(response) -- Not, CB's can only be used on the server side, so we just print this here for you to see.
	end, silenceAlert, useCallLocation, deleteAfter)
end)

-- Jordan - CAD Utils
dispatchOnline = false
ActiveDispatchers = {}

registerEndpoints = function()
end
addBlip = function(coords, colorHex, subType, toolTip, icon, dataTable, cb)
	local data = {
		{
			['serverId'] = GetConvar('sonoran_serverId', 1),
            ['id'] = -1,
            ['subType'] = subType,
            ['coordinates'] = {
                ['x'] = coords.x,
                ['y'] = coords.y
            },
            ['icon'] = icon,
            ['color'] = colorHex,
            ['tooltip'] = toolTip,
            ['data'] = dataTable
		}
    }
    local response = CadApiCreateBlips(data)
    if cb ~= nil then
        cb(response.success and json.encode(response.data or {}) or CadApiSupportErrorText("ADD_BLIP", response))
    elseif not response.success then
        CadApiLogFailure('ADD_BLIP', response, data)
    end
end
addBlips = function(blips, cb)
    local response = CadApiCreateBlips(blips)
    if cb ~= nil then
        cb(response.success and json.encode(response.data or {}) or CadApiSupportErrorText("ADD_BLIP", response))
    elseif not response.success then
        CadApiLogFailure('ADD_BLIP', response, blips)
    end
end
removeBlip = function(ids, cb)
    local payload = { ['ids'] = ids }
    local response = CadApiDeleteBlips(payload)
    if cb ~= nil then
        cb(response.success and "OK" or CadApiSupportErrorText("REMOVE_BLIP", response))
    elseif not response.success then
        CadApiLogFailure('REMOVE_BLIP', response, payload)
    end
end
modifyBlipd = function(blipId, dataTable)
    local payload = {{
        ['id'] = blipId,
        ['data'] = dataTable
    }}
    local response = CadApiUpdateBlips(payload)
    if not response.success then
        CadApiLogFailure('MODIFY_BLIP', response, payload)
    end
end
getBlips = function(cb)
    local response = CadApiGetBlips({
        ['serverId'] = GetConvar('sonoran_serverId', 1)
    })
    if cb ~= nil then
        cb(response.success and json.encode(response.data or {}) or CadApiSupportErrorText("GET_BLIPS", response))
    elseif not response.success then
        CadApiLogFailure('GET_BLIPS', response, { serverId = GetConvar('sonoran_serverId', 1) })
    end
end
removeWithSubtype = function(subType, cb)
	getBlips(function(res)
		local dres = SafeJsonDecode(res, "removeWithSubtype blip response", nil)
		local ids = {}
		if type(dres) == 'table' then
			for _, v in ipairs(dres) do
				if v.subType == subType then
					table.insert(ids, #ids + 1, v.id)
				end
			end
            if #ids > 0 then
			    removeBlip(ids, cb)
            end
		else
			warnLog('FEATURE_UNAVAILABLE', 'No blips were returned.')
		end
	end)
end
call911 = function(caller, location, description, postal, plate, cb, coords, customMeta)
    -- Base payload
    local payload = {
        ['serverId'] = GetConvar('sonoran_serverId', 1),
        ['isEmergency'] = true,
        ['caller'] = caller,
        ['location'] = location,
        ['description'] = description,
        ['metaData'] = {
            ['plate'] = plate,
            ['postal'] = postal
        }
    }

    -- If coords is a table with x/y/z, add it to the payload
    if coords and type(coords) == "table" and coords.x and coords.y then
        payload['coords'] = coords
    end

    -- If customMeta is a table, merge it into the metaData
    if customMeta and type(customMeta) == "table" then
        for k, v in pairs(customMeta) do
            payload.metaData[k] = v
        end
    end

    -- Send the API request
    local response = CadApiCreateEmergencyCall(payload)
    if cb ~= nil then
        local result = response.callId ~= nil and ("EMERGENCY CALL ADDED ID: %s"):format(response.callId)
            or (response.success and json.encode(response.data or {}) or CadApiSupportErrorText("CALL_911", response))
        cb(result, response.success == true)
    elseif not response.success then
        CadApiLogFailure('CALL_911', response, payload)
    end
end

createDispatchCall = function(origin, status, priority, block, address, postal, title, code, primary, trackPrimary, description, notes, metaData, units, cb)
    local payload = {
        serverId = GetConvar('sonoran_serverId', 1),
        origin = origin or 0,
        status = status or 0,
        priority = priority or 1,
        block = block or "",
        address = address or "",
        postal = postal or "",
        title = title or "New Call",
        code = code or "",
        primary = primary or 0,
        trackPrimary = trackPrimary == nil and false or trackPrimary,
        description = description or "",
        notes = notes or {},
        metaData = metaData or {},
        units = units or {}
    }
    local response = CadApiCreateDispatchCall(payload)
    if cb ~= nil then
        local result = response.callId ~= nil and ("NEW DISPATCH CREATED - ID: %s"):format(response.callId)
            or (response.success and json.encode(response.data or {}) or CadApiSupportErrorText("NEW_DISPATCH", response))
        cb(result, response.success == true)
    elseif not response.success then
        CadApiLogFailure("NEW_DISPATCH", response, payload)
    end
end

addTempBlipData = function(blipId, blipData, waitSeconds, returnToData)
    local firstPayload = {{
        ['id'] = blipId,
        ['data'] = blipData
    }}
    local response = CadApiUpdateBlips(firstPayload)
    if not response.success then
        CadApiLogFailure('MODIFY_BLIP', response, firstPayload)
    end

	Citizen.CreateThread(function()
		Citizen.Wait(waitSeconds * 1000)
        local payload = {{
            ['id'] = blipId,
            ['data'] = returnToData
        }}
        local delayedResponse = CadApiUpdateBlips(payload)
        if not delayedResponse.success then
            CadApiLogFailure('MODIFY_BLIP', delayedResponse, payload)
        end
	end)
end
addTempBlipColor = function(blipId, color, waitSeconds, returnToColor)
    local firstPayload = {{
        ['id'] = blipId,
        ['color'] = color
    }}
    local response = CadApiUpdateBlips(firstPayload)
    if not response.success then
        CadApiLogFailure('MODIFY_BLIP', response, firstPayload)
    end

	Citizen.CreateThread(function()
		Citizen.Wait(waitSeconds * 1000)
        local payload = {{
            ['id'] = blipId,
            ['color'] = returnToColor
        }}
        local delayedResponse = CadApiUpdateBlips(payload)
        if not delayedResponse.success then
            CadApiLogFailure('MODIFY_BLIP', delayedResponse, payload)
        end
	end)
end
remove911 = function(callId)
    local response = CadApiDeleteEmergencyCall(callId, GetConvar('sonoran_serverId', 1))
    if not response.success then
        CadApiLogFailure('REMOVE_911', response, { serverId = GetConvar('sonoran_serverId', 1), callId = callId })
    end
end
addCallNote = function(callId, caller)
    local payload = {
        ['serverId'] = GetConvar('sonoran_serverId', 1),
        ['callId'] = callId,
        ['note'] = caller
    }
    local response = CadApiAddDispatchNote(payload)
    if not response.success then
        CadApiLogFailure('ADD_CALL_NOTE', response, payload)
    end
end
setCallPostal = function(callId, postal)
    local payload = {
        ['serverId'] = GetConvar('sonoran_serverId', 1),
        ['callId'] = callId,
        ['postal'] = postal
    }
    local response = CadApiSetDispatchPostal(payload)
    if not response.success then
        CadApiLogFailure('SET_CALL_POSTAL', response, payload)
    end
end
performLookup = function(plate, cb, options)
	local data = {
		['plate'] = plate,
		['partial'] = false,
		['first'] = '',
		['last'] = '',
		['mi'] = ''
	}
	if type(options) == "table" then
		if options.types ~= nil then
			data.types = options.types
		elseif #options > 0 then
			data.types = options
		end
		if options.partial ~= nil then
			data.partial = options.partial
		end
		if options.first ~= nil then
			data.first = options.first
		end
		if options.last ~= nil then
			data.last = options.last
		end
		if options.mi ~= nil then
			data.mi = options.mi
		end
	end
	if data.types == nil then
		data.types = {2, 3, 4, 5}
	end
    local response = CadApiLookup(data)
    if cb ~= nil then
        cb(response.success and json.encode(response.data or {}) or CadApiSupportErrorText("LOOKUP", response))
    elseif not response.success then
        CadApiLogFailure('LOOKUP', response, data)
    end
end
local function normalizeLookupStatusValue(status)
	if status == nil then
		return nil
	end
	if type(status) == "number" then
		return status
	end
	if type(status) == "string" then
		local normalized = status:lower()
		if normalized == "open" or normalized == "active" then
			return 0
		elseif normalized == "closed" or normalized == "inactive" then
			return 1
		elseif normalized == "pending" then
			return 2
		elseif normalized == "approved" then
			return 3
		elseif normalized == "rejected" then
			return 4
		end
		local number = tonumber(status)
		if number ~= nil then
			return number
		end
	end
	return nil
end
local function normalizeLookupStatuses(statuses)
	local normalized = {}
	local seen = {}
	if type(statuses) ~= "table" then
		statuses = {statuses}
	end
	for _, status in ipairs(statuses) do
		local value = normalizeLookupStatusValue(status)
		if value ~= nil and not seen[value] then
			seen[value] = true
			table.insert(normalized, value)
		end
	end
	if #normalized == 0 then
		normalized = {0, 1}
	end
	return normalized
end
-- Fetch all BOLO and warrant records using LOOKUP_VALUE with pagination.
getAllWarrantsAndBolos = function(options, cb)
	if type(options) == "function" then
		cb = options
		options = {}
	end
	if cb == nil then
		cb = function() end
	end
	options = options or {}

	local limit = tonumber(options.limit or options.pageSize) or 100
	limit = math.max(1, math.floor(limit))

	local offset = tonumber(options.offset) or 0
	offset = math.max(0, math.floor(offset))

	local page = tonumber(options.page)
	if page ~= nil and page > 0 then
		offset = (math.floor(page) - 1) * limit
	end

	local maxPages = tonumber(options.maxPages or options.pageLimit or options.pages)
	if maxPages ~= nil then
		maxPages = math.max(1, math.floor(maxPages))
	end

	local statuses = normalizeLookupStatuses(options.statuses or options.status)
	local types = options.types
	if type(types) ~= "table" or #types == 0 then
		types = {2, 3}
	end

	local results = {}
	local pagesFetched = 0
	local statusIndex = 1

	local function fetchNextPage(currentOffset)
		local payload = {
			searchType = 2, -- ACTIVE_STATUS
			value = statuses[statusIndex],
			types = types,
			limit = limit,
			offset = currentOffset
		}
        local response = CadApiLookupByValue(payload)
        if not response.success then
            cb(nil, {ok = false, error = CadApiSupportErrorText("LOOKUP_BY_VALUE", response)})
            return
        end
        local decoded = response.data or {}
			local records = decoded
			if type(decoded) ~= "table" then
				records = {}
			elseif decoded.records ~= nil and type(decoded.records) == "table" then
				records = decoded.records
			end
			for _, record in ipairs(records) do
				table.insert(results, record)
			end
			pagesFetched = pagesFetched + 1

			local hasMore = #records >= limit
			if maxPages ~= nil and pagesFetched >= maxPages then
				cb(results, {ok = true, pages = pagesFetched, limit = limit, offset = offset, statuses = statuses, truncated = true})
				return
			end
			if hasMore then
				fetchNextPage(currentOffset + limit)
				return
			end
			statusIndex = statusIndex + 1
			if statusIndex <= #statuses then
				fetchNextPage(offset)
			else
				cb(results, {ok = true, pages = pagesFetched, limit = limit, offset = offset, statuses = statuses})
			end
	end

	fetchNextPage(offset)
end
checkCADSubscriptionType = function()
	while exports['sonorancad']:getCadVersion() == nil or exports['sonorancad']:getCadVersion() == -1 do
		Citizen.Wait(100)
	end
	local version = exports['sonorancad']:getCadVersion()
	if version ~= 4 and version == 3 then
		errorLog("UNHANDLED_SERVER_ERROR", 'The live map blip feature require the Pro plan for the CAD. It will be disabled for this run.'
						                           .. ' We recommend either upgrading your plan or disabling this feature in the config file.')
		Config.integration.SonoranCAD_integration.addLiveMapBlips = false
		Config.modified = true
		TriggerClientEvent(GetCurrentResourceName() .. '::ModifiedConfig', -1, Config)
	elseif version ~= 4 and version ~= 3 and version ~= 5 and version ~= 6 then
		errorLog("UNHANDLED_SERVER_ERROR", 'SonoranCAD integration with this script requires at least a Plus plan for the CAD. It will be'
						                           .. ' disabled for this run. We recommend either upgrading your plan or disabling this' .. ' feature in the config file.')
		Config.integration.SonoranCAD_integration.use = false
		Config.modified = true
		TriggerClientEvent(GetCurrentResourceName() .. '::ModifiedConfig', -1, Config)
	end
end
getDispatchStatus = function(_)
	return dispatchOnline
end

exports('registerEndpoints', registerEndpoints)
exports('addBlip', addBlip)
exports('addBlips', addBlips)
exports('removeBlip', removeBlip)
exports('modifyBlipd', modifyBlipd)
exports('getBlips', getBlips)
exports('removeWithSubtype', removeWithSubtype)
exports('call911', call911)
exports('addTempBlipData', addTempBlipData)
exports('addTempBlipColor', addTempBlipColor)
exports('remove911', remove911)
exports('addCallNote', addCallNote)
exports('setCallPostal', setCallPostal)
exports('performLookup', performLookup)
exports('getAllWarrantsAndBolos', getAllWarrantsAndBolos)
exports('checkCADSubscriptionType', checkCADSubscriptionType)
exports('getDispatchStatus', getDispatchStatus)
exports('createDispatchCall', createDispatchCall)
-- Jordan - CAD Utils

function isPlayerInCAD(source)
    local communityUserId = GetPlayerCommunityUserId(source)
    local unit = GetUnitByPlayerId(source)
    return {
        linked = communityUserId ~= nil,
        online = unit ~= nil,
        success = communityUserId ~= nil and unit ~= nil,
        communityUserId = communityUserId,
        unit = unit
    }
end

exports('isPlayerInCAD', isPlayerInCAD)

local function get_player_error_context(source)
    local playerName = GetPlayerName(source) or "unknown"
    return playerName, ("Player ID: %s, Username: %s"):format(tostring(source), tostring(playerName))
end

local function get_error_message_with_player_context(errorKey, playerContext)
    local errorText = getErrorText(errorKey) or errorKey or "Unknown error."
    return ("%s (%s)"):format(errorText, playerContext)
end

-- Addition Server Functions --
-- Gets a player's CAD status for a given submodule, checking for link and/or unit as specified in the checks parameter. Returns an object with hasLink, hasUnit and messages array.
-- @param source - the player's server ID
-- @param submodule - the submodule name to include in messages
-- @param checks - an object specifying which checks to perform: { link = true/false, unit = true/false }
-- @returns response - an object containing hasLink (boolean), hasUnit (boolean), and messages (array of strings)
function getPlayerCadStatus(source, submodule, checks)
    local checkForLink = checks and checks.link or false
    local checkForUnit = checks and checks.unit or false
    local chatLinkCommand = Config.linkCommand or "link"
    local cadState = isPlayerInCAD(source)
    local response = {
        hasLink = cadState.linked,
        hasUnit = cadState.online,
        success = true,
        link = cadState.communityUserId,
        unit = cadState.unit
    }
    if checkForLink then
        if not response.hasLink then
            local _, playerContext = get_player_error_context(source)
            debugLog(("[cad-status] %s link check failed for %s"):format(submodule, playerContext))
            sendClientError(source, "PLAYER_NOT_LINKED", get_error_message_with_player_context("PLAYER_NOT_LINKED", playerContext), chatLinkCommand)
        end
    end
    if checkForUnit then
        if not response.hasUnit then
            local _, playerContext = get_player_error_context(source)
            debugLog(("[cad-status] %s unit check failed for %s"):format(submodule, playerContext))
            if response.hasLink then
                sendClientError(source, "PLAYER_NOT_ONLINE")
            else
                sendClientError(source, "PLAYER_NOT_IN_CAD", get_error_message_with_player_context("PLAYER_NOT_IN_CAD", playerContext))
            end
        end
    end
    if not response.hasLink and checkForLink then
        response.success = false
    end
    if not response.hasUnit and checkForUnit then
        response.success = false
    end
    return response
end
