-- Shared CAD helper functions with validation and clearer error handling for external consumers.

---@class CadCoords
---@field x number
---@field y number
---@field z number|nil

---@class CadBlipEntry
---@field id number
---@field subType string|number
---@field coordinates CadCoords
---@field icon string|number|nil
---@field color string|nil
---@field tooltip string|nil
---@field data table|nil

---@class CadBlipPayload
---@field serverId number
---@field blip CadBlipEntry

---@class CadCallMeta
---@field plate string|nil
---@field postal string|nil
---@field useCallLocation boolean|nil
---@field silenceAlert boolean|nil
---@field [string] any

---@class CadCallPayload
---@field serverId number
---@field isEmergency boolean
---@field caller string
---@field location string
---@field description string
---@field metaData CadCallMeta
---@field coords CadCoords|nil
---@field deleteAfter number|nil

---@class CadDispatchPayload
---@field id string
---@field key string
---@field type string
---@field serverId number
---@field origin number
---@field status number
---@field priority number
---@field block string
---@field address string
---@field postal string
---@field title string
---@field code string
---@field primary number
---@field trackPrimary boolean
---@field description string
---@field notes table
---@field metaData table
---@field units table

---@class CadUnit -- Minimal shape, contents are managed by unittracking
---@field id any
---@field playerId any
---@field [string] any

---@class CadCall -- Minimal call cache entry
---@field callId any
---@field [string] any

local isServer = IsDuplicityVersion and IsDuplicityVersion() or false

local function safeCb(cb)
	if cb ~= nil then
		return cb
	end
	return function() end
end

local function requireServer(context, cb)
	if isServer then
		return true
	end
	warnLog(("CAD API %s: This function is server-only."):format(context))
	safeCb(cb)(nil, false, "server_only")
	return false
end

local function requireClient(context, cb)
	if not isServer then
		return true
	end
	warnLog(("CAD API %s: This function is client-only."):format(context))
	safeCb(cb)(nil, false, "client_only")
	return false
end

local function logFailure(context, message, cb)
	local fullMessage = ("CAD API %s: %s"):format(context, message)
	warnLog(fullMessage)
	safeCb(cb)(nil, false, fullMessage)
	return false, fullMessage
end

local function resolveApiId(identifierOrPlayer)
	if type(identifierOrPlayer) == "number" then
		local ids = GetIdentifiers(identifierOrPlayer)
		if ids ~= nil then
			return ids[Config.primaryIdentifier]
		end
	elseif type(identifierOrPlayer) == "string" then
		return identifierOrPlayer
	end
	return nil
end

local function normalizePayload(raw)
	if type(raw) ~= "table" then
		return nil
	end
	if raw[1] == nil then
		return { raw }
	end
	return raw
end

local function ensureServerId(payload)
	local serverId = GetConvar('sonoran_serverId', 1)
	for _, entry in ipairs(payload) do
		if entry.serverId == nil then
			entry.serverId = serverId
		end
	end
end

local function validateCoords(coords)
	if type(coords) ~= "table" then
		return false
	end
	local x = tonumber(coords.x)
	local y = tonumber(coords.y)
	if x == nil or y == nil then
		return false
	end
	return true, { x = x, y = y, z = coords.z }
end

local function sendRequest(kind, payload, cb)
	if not isServer then
		return requireServer(kind, cb)
	end
	if payload == nil or type(payload) ~= "table" then
		return logFailure(kind, "Payload must be a table.", cb)
	end
	exports['sonorancad']:performApiRequest(payload, kind, safeCb(cb))
	return true
end

---@param pluginName string
---@return table|nil config
getPluginConfig = function(pluginName)
	if type(pluginName) ~= "string" or pluginName == "" then
		logFailure("GET_PLUGIN_CONFIG", "pluginName must be a non-empty string.")
		return nil
	end
	if Config and Config.GetPluginConfig then
		return Config.GetPluginConfig(pluginName)
	end
	if exports and exports['sonorancad'] and exports['sonorancad'].GetPluginConfig then
		return exports['sonorancad']:GetPluginConfig(pluginName)
	end
	return nil
end

---@return number|nil mode -- 0 development, 1 production
getApiModeShared = function()
	if not requireClient("GET_API_MODE", nil) then return nil end
	if Config and Config.mode then
		return (Config.mode == 'development') and 0 or 1
	end
	if exports and exports['sonorancad'] and exports['sonorancad'].getApiMode then
		return exports['sonorancad']:getApiMode()
	end
	return nil
end

---@param apiIdOrPlayer string|number
---@param cb fun(exists:boolean)|nil
---@return boolean
cadIsPlayerLinked = function(apiIdOrPlayer, cb)
	if not requireServer("CHECK_APIID", cb) then return false end
	local apiId = resolveApiId(apiIdOrPlayer)
	if not apiId or apiId == "" then
		return logFailure("CHECK_APIID", "Missing API ID to check.", cb)
	end
	exports['sonorancad']:CadIsPlayerLinked(apiId, function(exists)
		if cb then cb(exists) end
	end)
	return true
end

---@param player number
---@return CadUnit|nil
getUnitByPlayerId = function(player)
	if type(player) ~= "number" then
		logFailure("GET_UNIT", "player must be a server id number.")
		return nil
	end
	if not requireServer("GET_UNIT", nil) then return nil end
	return exports['sonorancad']:GetUnitByPlayerId(player)
end

---@param unitId any
---@return CadUnit|nil
getUnitById = function(unitId)
	if unitId == nil then
		logFailure("GET_UNIT", "unitId is required.")
		return nil
	end
	if not requireServer("GET_UNIT", nil) then return nil end
	return exports['sonorancad']:GetUnitById(unitId)
end

---@return CadUnit[]|table
getUnitCache = function()
	if not requireServer("GET_UNIT_CACHE", nil) then return {} end
	return exports['sonorancad']:GetUnitCache()
end

---@return CadCall[]|table
getCallCache = function()
	if not requireServer("GET_CALL_CACHE", nil) then return {} end
	return exports['sonorancad']:GetCallCache()
end

---@return table
getEmergencyCache = function()
	if not requireServer("GET_EMERGENCY_CACHE", nil) then return {} end
	return exports['sonorancad']:GetEmergencyCache()
end

---@return boolean ok
registerEndpoints = function()
	if not requireServer("REGISTER_ENDPOINTS", nil) then return false end
	local function register(typeKey, endpoint)
		if type(registerApiType) == "function" then
			return registerApiType(typeKey, endpoint)
		end
		return exports['sonorancad']:registerApiType(typeKey, endpoint)
	end
	if type(registerApiType) ~= "function" and (exports == nil or exports['sonorancad'] == nil) then
		return logFailure("REGISTER_ENDPOINTS", "registerApiType is not available.")
	end
	register('MODIFY_BLIP', 'emergency')
	register('ADD_BLIP', 'emergency')
	register('REMOVE_BLIP', 'emergency')
	register('GET_BLIPS', 'emergency')
	register('MODIFY_BLIP', 'emergency')
	register('CALL_911', 'emergency')
	register('ADD_CALL_NOTE', 'emergency')
	register('REMOVE_911', 'emergency')
	register('LOOKUP', 'general')
	register('SET_CALL_POSTAL', 'emergency')
	register('GET_ACTIVE_UNITS', 'emergency')
	return true
end

---@param payloadOrCoords CadBlipPayload|CadCoords|table
---@param colorHex string|nil
---@param subType string|number
---@param toolTip string|nil
---@param icon string|number|nil
---@param dataTable table|nil
---@param cb fun(res:any, ok:boolean, err:string|nil)|nil
---@return boolean
addBlip = function(payloadOrCoords, colorHex, subType, toolTip, icon, dataTable, cb)
	if type(payloadOrCoords) == "table" and (payloadOrCoords[1] ~= nil or payloadOrCoords.blip ~= nil) then
		local payload = normalizePayload(payloadOrCoords)
		if payload == nil then
			return logFailure("ADD_BLIP", "Invalid payload supplied (expected table or array).", cb)
		end
		ensureServerId(payload)
		return sendRequest('ADD_BLIP', payload, cb)
	end

	local coordsOk, coords = validateCoords(payloadOrCoords)
	if not coordsOk then
		return logFailure("ADD_BLIP", "Missing coords table with numeric x/y.", cb)
	end
	if subType == nil then
		return logFailure("ADD_BLIP", "Missing blip subtype.", cb)
	end

	local payload = {
		{
			['serverId'] = GetConvar('sonoran_serverId', 1),
			['blip'] = {
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
	}
	return sendRequest('ADD_BLIP', payload, cb)
end

---@param blips CadBlipPayload[]|table
---@param cb fun(res:any, ok:boolean, err:string|nil)|nil
---@return boolean
addBlips = function(blips, cb)
	if type(blips) ~= "table" or next(blips) == nil then
		return logFailure("ADD_BLIP", "Payload must be a non-empty array of blips.", cb)
	end
	local payload = normalizePayload(blips)
	if payload == nil then
		return logFailure("ADD_BLIP", "Invalid blip payload supplied.", cb)
	end
	ensureServerId(payload)
	return sendRequest('ADD_BLIP', payload, cb)
end

---@param idsOrPayload number|table
---@param cb fun(res:any, ok:boolean, err:string|nil)|nil
---@return boolean
removeBlip = function(idsOrPayload, cb)
	local payload = nil
	if type(idsOrPayload) == "table" then
		if idsOrPayload[1] ~= nil and type(idsOrPayload[1]) ~= "table" and idsOrPayload.ids == nil then
			payload = { { ['ids'] = idsOrPayload } }
		else
			payload = normalizePayload(idsOrPayload)
		end
	elseif idsOrPayload ~= nil then
		payload = { { ['ids'] = { idsOrPayload } } }
	end

	if payload == nil then
		return logFailure("REMOVE_BLIP", "Missing ids payload.", cb)
	end
	return sendRequest('REMOVE_BLIP', payload, cb)
end

---@param payloadOrId number|CadBlipEntry|CadBlipEntry[]
---@param dataTable table|nil
---@param cb fun(res:any, ok:boolean, err:string|nil)|nil
---@return boolean
modifyBlipd = function(payloadOrId, dataTable, cb)
	local payload = nil
	if type(payloadOrId) == "table" then
		payload = normalizePayload(payloadOrId)
	elseif payloadOrId ~= nil and dataTable ~= nil then
		payload = { { ['id'] = payloadOrId, ['data'] = dataTable } }
	end

	if payload == nil then
		return logFailure("MODIFY_BLIP", "Missing blip id or payload.", cb)
	end
	return sendRequest('MODIFY_BLIP', payload, cb)
end

---@param cb fun(res:any, ok:boolean, err:string|nil)|nil
---@return boolean
getBlips = function(cb)
	local data = {
		{
			['serverId'] = GetConvar('sonoran_serverId', 1)
		}
	}
	return sendRequest('GET_BLIPS', data, cb)
end

---@param subType string|number
---@param cb fun(res:any, ok:boolean, err:string|nil)|nil
removeWithSubtype = function(subType, cb)
	if subType == nil then
		return logFailure("REMOVE_BLIP", "Missing subtype to remove.", cb)
	end
	getBlips(function(res)
		local decoded = res
		if type(res) == "string" then
			local ok, parsed = pcall(json.decode, res)
			if ok then
				decoded = parsed
			end
		end
		if type(decoded) ~= "table" then
			return logFailure("REMOVE_BLIP", "Response did not contain a valid blip table.", cb)
		end
		local ids = {}
		for _, v in ipairs(decoded) do
			if v.subType == subType then
				table.insert(ids, v.id)
			end
		end
		if #ids == 0 then
			warnLog(("REMOVE_BLIP: No blips found for subtype %s."):format(tostring(subType)))
			if cb then
				cb(nil, true)
			end
			return
		end
		removeBlip(ids, cb)
	end)
end

local function parseCallOptions(arg7, arg8, arg9, arg10, arg11)
	if type(arg7) == "table" then
		return arg7
	end
	return {
		silenceAlert = arg7,
		useCallLocation = arg8,
		deleteAfter = arg9,
		coords = arg10,
		metaData = arg11
	}
end

---@param dataOrCaller CadCallPayload|CadCallPayload[]|string
---@param location string|nil
---@param description string|nil
---@param postal string|nil
---@param plate string|nil
---@param cb fun(res:any, ok:boolean, err:string|nil)|nil
---@param arg7 any
---@param arg8 any
---@param arg9 any
---@param arg10 any
---@param arg11 any
---@return boolean
call911 = function(dataOrCaller, location, description, postal, plate, cb, arg7, arg8, arg9, arg10, arg11)
	if type(dataOrCaller) == "table" then
		local payload = normalizePayload(dataOrCaller)
		if payload == nil then
			return logFailure("CALL_911", "Invalid payload supplied (expected table or array).", cb)
		end
		for _, entry in ipairs(payload) do
			if entry.caller == nil or entry.location == nil or entry.description == nil then
				return logFailure("CALL_911", "Payload missing caller, location, or description.", cb)
			end
		end
		ensureServerId(payload)
		return sendRequest('CALL_911', payload, cb)
	end

	if not dataOrCaller or not location or not description then
		return logFailure("CALL_911", "Missing caller, location, or description.", cb)
	end

	local opts = parseCallOptions(arg7, arg8, arg9, arg10, arg11)
	local coordsOk, coords = validateCoords(opts.coords or {})
	if opts.coords ~= nil and not coordsOk then
		return logFailure("CALL_911", "coords provided but missing numeric x/y.", cb)
	end

	local payload = {
		{
			['serverId'] = GetConvar('sonoran_serverId', 1),
			['isEmergency'] = true,
			['caller'] = dataOrCaller,
			['location'] = location,
			['description'] = description,
			['metaData'] = {
				['plate'] = plate,
				['postal'] = postal,
				['useCallLocation'] = opts.useCallLocation or false,
				['silenceAlert'] = opts.silenceAlert or false
			}
		}
	}

	if opts.deleteAfter then
		payload[1]['deleteAfter'] = opts.deleteAfter
	end
	if opts.coords and coordsOk then
		payload[1]['coords'] = coords
	end
	if opts.metaData and type(opts.metaData) == "table" then
		for k, v in pairs(opts.metaData) do
			payload[1].metaData[k] = v
		end
	end

	return sendRequest('CALL_911', payload, cb)
end

RegisterNetEvent('SonoranScripts::Call911', function(caller, location, description, postal, plate, cb, silenceAlert, useCallLocation, deleteAfter)
	call911(caller, location, description, postal, plate, function(response)
	json.encode(response) -- Server-side only callbacks; retain output for debugging.
	end, silenceAlert, useCallLocation, deleteAfter)
end)

---@param origin CadDispatchPayload|CadDispatchPayload[]|number|nil
---@param status number|nil
---@param priority number|nil
---@param block string|nil
---@param address string|nil
---@param postal string|nil
---@param title string|nil
---@param code string|nil
---@param primary number|nil
---@param trackPrimary boolean|nil
---@param description string|nil
---@param notes table|nil
---@param metaData table|nil
---@param units table|nil
---@param cb fun(res:any, ok:boolean, err:string|nil)|nil
---@return boolean
createDispatchCall = function(origin, status, priority, block, address, postal, title, code, primary, trackPrimary, description, notes, metaData, units, cb)
	if type(origin) == "table" then
		local payload = normalizePayload(origin)
		if payload == nil then
			return logFailure("NEW_DISPATCH", "Invalid payload supplied (expected table or array).", cb)
		end
		ensureServerId(payload)
		return sendRequest("NEW_DISPATCH", payload, cb)
	end

	if not address then
		return logFailure("NEW_DISPATCH", "Missing address for dispatch call.", cb)
	end

	local payload = {
		{
			id = GetConvar("sonoran_community_id", "YOUR_COMMUNITY_ID"),
			key = GetConvar("sonoran_api_key", "YOUR_API_KEY"),
			type = "NEW_DISPATCH",
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
	}
	return sendRequest("NEW_DISPATCH", payload, cb)
end

---@param blipIdOrPayload number|CadBlipEntry|CadBlipEntry[]
---@param blipData table|nil
---@param waitSeconds number
---@param returnToData table|nil
---@return boolean
addTempBlipData = function(blipIdOrPayload, blipData, waitSeconds, returnToData)
	local payload = nil
	if type(blipIdOrPayload) == "table" then
		payload = normalizePayload(blipIdOrPayload)
	elseif blipIdOrPayload ~= nil and blipData ~= nil then
		payload = { { ['id'] = blipIdOrPayload, ['data'] = blipData } }
	end
	if payload == nil then
		return logFailure("MODIFY_BLIP", "Missing id or payload for temporary blip data.", nil)
	end

	local waitMs = tonumber(waitSeconds) and (tonumber(waitSeconds) * 1000) or nil
	if waitMs == nil then
		return logFailure("MODIFY_BLIP", "waitSeconds must be numeric for temporary blip.", nil)
	end

	sendRequest('MODIFY_BLIP', payload)

	Citizen.CreateThread(function()
		Citizen.Wait(waitMs)
		local restorePayload = nil
		if type(returnToData) == "table" then
			restorePayload = normalizePayload(returnToData)
		elseif blipIdOrPayload ~= nil and returnToData ~= nil then
			restorePayload = { { ['id'] = blipIdOrPayload, ['data'] = returnToData } }
		end
		if restorePayload == nil then
			return logFailure("MODIFY_BLIP", "No restore payload provided for temporary blip.", nil)
		end
		if isServer then
			sendRequest('MODIFY_BLIP', restorePayload)
		end
	end)
	return true
end

---@param blipIdOrPayload number|CadBlipEntry|CadBlipEntry[]
---@param color string|nil
---@param waitSeconds number
---@param returnToColor any
---@return boolean
addTempBlipColor = function(blipIdOrPayload, color, waitSeconds, returnToColor)
	local payload = nil
	if type(blipIdOrPayload) == "table" then
		payload = normalizePayload(blipIdOrPayload)
	elseif blipIdOrPayload ~= nil and color ~= nil then
		payload = { { ['id'] = blipIdOrPayload, ['color'] = color } }
	end

	if payload == nil then
		return logFailure("MODIFY_BLIP", "Missing id or payload for temporary blip color.", nil)
	end

	local waitMs = tonumber(waitSeconds) and (tonumber(waitSeconds) * 1000) or nil
	if waitMs == nil then
		return logFailure("MODIFY_BLIP", "waitSeconds must be numeric for temporary color.", nil)
	end

	sendRequest('MODIFY_BLIP', payload)

	Citizen.CreateThread(function()
		Citizen.Wait(waitMs)
		local restorePayload = nil
		if type(returnToColor) == "table" then
			restorePayload = normalizePayload(returnToColor)
		elseif blipIdOrPayload ~= nil and returnToColor ~= nil then
			restorePayload = { { ['id'] = blipIdOrPayload, ['color'] = returnToColor } }
		end
		if restorePayload == nil then
			return logFailure("MODIFY_BLIP", "No restore payload provided for temporary color.", nil)
		end
		if isServer then
			sendRequest('MODIFY_BLIP', restorePayload)
		end
	end)
	return true
end

---@param callIdOrPayload number|table
---@param cb fun(res:any, ok:boolean, err:string|nil)|nil
---@return boolean
remove911 = function(callIdOrPayload, cb)
	local payload = nil
	if type(callIdOrPayload) == "table" then
		payload = normalizePayload(callIdOrPayload)
	elseif callIdOrPayload ~= nil then
		payload = { { ['serverId'] = GetConvar('sonoran_serverId', 1), ['callId'] = callIdOrPayload } }
	end
	if payload == nil then
		return logFailure("REMOVE_911", "Missing callId for removal.", cb)
	end
	ensureServerId(payload)
	return sendRequest('REMOVE_911', payload, cb)
end

---@param callIdOrPayload number|table
---@param caller string|nil
---@param cb fun(res:any, ok:boolean, err:string|nil)|nil
---@return boolean
addCallNote = function(callIdOrPayload, caller, cb)
	local payload = nil
	if type(callIdOrPayload) == "table" then
		payload = normalizePayload(callIdOrPayload)
	elseif callIdOrPayload ~= nil and caller ~= nil then
		payload = { { ['serverId'] = GetConvar('sonoran_serverId', 1), ['callId'] = callIdOrPayload, ['note'] = caller } }
	end
	if payload == nil then
		return logFailure("ADD_CALL_NOTE", "Missing callId or note.", cb)
	end
	ensureServerId(payload)
	return sendRequest('ADD_CALL_NOTE', payload, cb)
end

---@param callIdOrPayload number|table
---@param postal string|nil
---@param cb fun(res:any, ok:boolean, err:string|nil)|nil
---@return boolean
setCallPostal = function(callIdOrPayload, postal, cb)
	local payload = nil
	if type(callIdOrPayload) == "table" then
		payload = normalizePayload(callIdOrPayload)
	elseif callIdOrPayload ~= nil and postal ~= nil then
		payload = { { ['serverId'] = GetConvar('sonoran_serverId', 1), ['callId'] = callIdOrPayload, ['postal'] = postal } }
	end
	if payload == nil then
		return logFailure("SET_CALL_POSTAL", "Missing callId or postal.", cb)
	end
	ensureServerId(payload)
	return sendRequest('SET_CALL_POSTAL', payload, cb)
end

---@param payloadOrPlate string|table
---@param cb fun(res:any, ok:boolean, err:string|nil)|nil
---@return boolean
performLookup = function(payloadOrPlate, cb)
	local payload = nil
	if type(payloadOrPlate) == "table" then
		payload = normalizePayload(payloadOrPlate)
	elseif payloadOrPlate ~= nil then
		payload = {
			{
				['types'] = {
					2,
					3
				},
				['plate'] = payloadOrPlate,
				['partial'] = false,
				['first'] = '',
				['last'] = '',
				['mi'] = ''
			}
		}
	end

	if payload == nil then
		return logFailure("LOOKUP", "Missing plate or payload for lookup.", cb)
	end
	return sendRequest('LOOKUP', payload, cb)
end

dispatchOnline = dispatchOnline or false
ActiveDispatchers = ActiveDispatchers or {}

---@return boolean
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
exports('getDispatchStatus', getDispatchStatus)
exports('createDispatchCall', createDispatchCall)
exports('getPluginConfig', getPluginConfig)
exports('getApiModeShared', getApiModeShared)
exports('cadIsPlayerLinked', cadIsPlayerLinked)
exports('getUnitByPlayerId', getUnitByPlayerId)
exports('getUnitById', getUnitById)
exports('getUnitCache', getUnitCache)
exports('getCallCache', getCallCache)
exports('getEmergencyCache', getEmergencyCache)
