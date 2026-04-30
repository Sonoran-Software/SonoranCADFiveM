--[[
    Sonaran CAD Plugins

    Plugin Name: wraithv2
    Creator: SonoranCAD
    Description: Implements plate auto-lookup for the wraithv2 plate reader by WolfKnight

    Put all server-side logic in this file.
]] local pluginConfig = Config.GetPluginConfig('wraithv2')

if pluginConfig.enabled then

	local wk_wars2xVersion = GetResourceMetadata('wk_wars2x', 'version')
	if not string.find(wk_wars2xVersion:lower(), "sonoran") then
		logError('INCORRECT_WKWARS2X_VERSION')
		Config.plugins['wraithv2'].enabled = false
		Config.plugins['wraithv2'].disableReason = 'incorrect wk_wars2x version'
		return
	end
	if pluginConfig.useExpires == nil then
		pluginConfig.useExpires = true
	end
	if pluginConfig.useMiddleInitial == nil then
		pluginConfig.useMiddleInitial = true
	end

	if pluginConfig.notificationTimers == nil then
		warnLog('Notification timers are not set in the wraithv2 configuration. Using defaults. Please update your configuration using the wraithv2_config.dist.lua file located in the configuration folder.')
		pluginConfig.notificationTimers = {
			validReg = 20000,
			warrant = 20000,
			bolo = 20000,
			noReg = 5000
		}
	end
	if pluginConfig.customFields == nil then
		pluginConfig.customFields = {}
	end
	wraithLastPlates = {locked = nil, scanned = nil}

	exports('cadGetLastPlates', function()
		return wraithLastPlates
	end)

	local function isInArray(array, value)
		for i = 1, #array do
			if array[i] == value then
				return true
			end
		end
		return false
	end

	local function formatCustomFieldLines(record)
		if record == nil or pluginConfig.customFields == nil or #pluginConfig.customFields == 0 then
			return ''
		end
		local lines = {}
		local labels = record.__fieldLabels or {}
		for _, fieldId in ipairs(pluginConfig.customFields) do
			local value = record[fieldId]
			if value ~= nil and value ~= '' then
				local label = labels[fieldId] or fieldId
				table.insert(lines, ('%s: %s'):format(label, value))
			end
		end
		if #lines > 0 then
			return table.concat(lines, '<br/>') .. '<br/>'
		end
		return ''
	end

	RegisterNetEvent('wk:onPlateLocked')
	AddEventHandler('wk:onPlateLocked', function(cam, plate, index, vehicle, cbType, returnEvent)
		debugLog(('plate lock: %s - %s - %s - %s - %s'):format(cam, plate, index, cbType, returnEvent))
		local source = source
		local communityUserId = GetPlayerCommunityUserId(source)
		plate = plate:match('^%s*(.-)%s*$')
		wraithLastPlates.locked = {cam = cam, plate = plate, index = index, vehicle = cam.vehicle}
		cadGetInformation(plate, function(regData, vehData, charData, boloData, warrantData)
			if cam == 'front' then
				camCapitalized = 'Front'
			elseif cam == 'rear' then
				camCapitalized = 'Rear'
			end
			if returnEvent ~= nil then
				if cbType == 'client' then
					TriggerClientEvent(returnEvent, source, {['regData'] = regData, ['vehData'] = vehData, ['charData'] = charData, ['boloData'] = boloData, ['warrantData'] = warrantData, ['plate'] = plate, ['cam'] = cam, ['index'] = index})
				elseif cbType == 'server' then
					TriggerServerEvent(returnEvent, source, {['regData'] = regData, ['vehData'] = vehData, ['charData'] = charData, ['boloData'] = boloData, ['warrantData'] = warrantData, ['plate'] = plate, ['cam'] = cam, ['index'] = index})
				else
					warnLog('The provided cbType for wk:onPlateLocked was invalid!')
				end
			end
			if #vehData < 1 then
				debugLog('No data returned')
				return
			end
			local reg = false
			for _, veh in pairs(vehData) do
				if veh.plate:lower() == plate:lower() then
					reg = veh
					break
				end
			end
			if #charData < 1 then
				debugLog('Invalid registration')
				reg = false
			end
			if reg then
				local person = charData[1]
				TriggerEvent('SonoranCAD::wraithv2:PlateLocked', source, reg, cam, plate, index)
				local plate = reg.plate
				if regData == nil then
					debugLog('regData is nil, skipping plate lock.')
					return
				end
				if regData[1] == nil then
					debugLog('regData is empty, skipping')
					return
				end
				if regData[1].status == nil then
					warnLog(('Plate %s was scanned by %s, but status was nil. Record: %s'):format(plate, source, json.encode(regData[1])))
					return
				end
				local plate = reg.plate
				local statusUid = pluginConfig.statusUid ~= nil and pluginConfig.statusUid or 'status'
				local expiresUid = pluginConfig.expiresUid ~= nil and pluginConfig.expiresUid or 'expiration'
				local status = regData[1][statusUid]
				local expires = (regData[1][expiresUid] and pluginConfig.useExpires) and ('Expires: %s<br/>'):format(regData[1][expiresUid]) or ''
				local owner = (pluginConfig.useMiddleInitial and person.mi ~= '') and ('%s %s, %s'):format(person.first, person.last, person.mi) or ('%s %s'):format(person.first, person.last)
				local customFieldsText = formatCustomFieldLines(regData[1])
				TriggerClientEvent('pNotify:SendNotification', source,
				                   {text = ('<b style=\'color:yellow\'>' .. camCapitalized .. ' ALPR</b><br/>Plate: %s<br/>Status: %s<br/>%s%sOwner: %s'):format(plate:upper(), status, expires, customFieldsText, owner),
					type = 'success', queue = 'alpr', timeout = pluginConfig.notificationTimers.validReg, layout = 'centerLeft'})
				if #boloData > 0 then
					local flags = table.concat(boloData, ',')
					TriggerClientEvent('pNotify:SendNotification', source, {text = ('<b style=\'color:red\'>BOLO ALERT!<br/>Plate: %s<br/>Flags: %s'):format(plate:upper(), flags), type = 'error', queue = 'bolo',
						timeout = pluginConfig.notificationTimers.bolo, layout = 'centerLeft'})
					TriggerEvent('SonoranCAD::wraithv2:BoloAlert', plate, flags)
					TriggerClientEvent('SonoranCAD::wraithv2:PlaySound', source, 'bolo')
				end
				if #warrantData > 0 then
					local warrants = table.concat(warrantData, ',')
					TriggerClientEvent('pNotify:SendNotification', source, {text = ('<b style=\'color:red\'>WARRANT ALERT!<br/>Plate: %s<br/>Flags: %s'):format(plate:upper(), warrants), type = 'error', queue = 'warrant',
						timeout = pluginConfig.notificationTimers.warrant, layout = 'centerLeft'})
					TriggerEvent('SonoranCAD::wraithv2:WarrantAlert', plate, warrants)
					TriggerClientEvent('SonoranCAD::wraithv2:PlaySound', source, 'warrant')
				end
			else
				if pluginConfig.alertNoRegistration then
					TriggerClientEvent('pNotify:SendNotification', source,
					                   {text = '<b style=\'color:yellow\'>' .. camCapitalized .. ' ALPR</b><br/>Plate: ' .. plate:upper() .. '<br/>Status: Not Registered', type = 'warning', queue = 'alpr',
						timeout = pluginConfig.notificationTimers.noReg, layout = 'centerLeft'})
					TriggerEvent('SonoranCAD::wraithv2:NoRegAlert', plate)
					TriggerClientEvent('SonoranCAD::wraithv2:PlaySound', source, 'registration')
				end
			end
		end, communityUserId)
	end)

	RegisterNetEvent('wk:onPlateScanned')
	AddEventHandler('wk:onPlateScanned', function(cam, plate, index, vehicle, cbType, returnEvent)
		local vehicleClass = tonumber(vehicle.class)
		if isInArray(pluginConfig.vehTypeFilter, vehicleClass) then
			debugLog(('Vehicle type %s is filtered, skipping plate scan'):format(vehicleClass))
			return
		end
		if cam == 'front' then
			camCapitalized = 'Front'
		elseif cam == 'rear' then
			camCapitalized = 'Rear'
		end
		debugLog(('plate scan: %s - %s - %s - %s - %s'):format(cam, plate, index, cbType, returnEvent))
		local source = source
		local communityUserId = GetPlayerCommunityUserId(source)
		plate = plate:match('^%s*(.-)%s*$')
		wraithLastPlates.scanned = {cam = cam, plate = plate, index = index, vehicle = cam.vehicle}
		TriggerEvent('SonoranCAD::wraithv2:PlateScanned', source, reg, cam, plate, index)
		cadGetInformation(plate, function(regData, vehData, charData, boloData, warrantData)
			if returnEvent ~= nil then
				if cbType == 'client' then
					TriggerClientEvent(returnEvent, source, {['regData'] = regData, ['vehData'] = vehData, ['charData'] = charData, ['boloData'] = boloData, ['warrantData'] = warrantData, ['plate'] = plate, ['cam'] = cam, ['index'] = index})
				elseif cbType == 'server' then
					TriggerServerEvent(returnEvent, source, {['regData'] = regData, ['vehData'] = vehData, ['charData'] = charData, ['boloData'] = boloData, ['warrantData'] = warrantData, ['plate'] = plate, ['cam'] = cam, ['index'] = index})
				else
					warnLog('The provided cbType for wk:onPlateLocked was invalid!')
				end
			end
			if cam == 'front' then
				camCapitalized = 'Front'
			elseif cam == 'rear' then
				camCapitalized = 'Rear'
			end
			local reg = false
			for _, veh in pairs(vehData) do
				if veh.plate:lower() == plate:lower() then
					reg = veh
					break
				end
			end
			local person = {}
			if #charData > 0 then
				person = charData[1]
			end
			if reg then
				TriggerEvent('SonoranCAD::wraithv2:PlateLocked', source, reg, cam, plate, index)
				local plate = reg.plate
				if regData == nil then
					debugLog('regData is nil, skipping plate lock.')
					return
				end
				if regData[1] == nil then
					debugLog('regData is empty, skipping')
					return
				end
				if regData[1].status == nil then
					warnLog(('Plate %s was scanned by %s, but status was nil. Record: %s'):format(plate, source, json.encode(regData[1])))
					return
				end
				local statusUid = pluginConfig.statusUid ~= nil and pluginConfig.statusUid or 'status'
				local expiresUid = pluginConfig.expiresUid ~= nil and pluginConfig.expiresUid or 'expiration'
				local flagStatuses = pluginConfig.flagOnStatuses ~= nil and pluginConfig.flagOnStatuses or {'STOLEN', 'EXPIRED', 'PENDING', 'SUSPENDED'}
				local status = regData[1][statusUid]
				local expires = (regData[1][expiresUid] and pluginConfig.useExpires) and ('Expires: %s<br/>'):format(regData[1][expiresUid]) or ''
				local owner = (pluginConfig.useMiddleInitial and person.mi ~= '') and ('%s %s, %s'):format(person.first, person.last, person.mi) or ('%s %s'):format(person.first, person.last)
				local customFieldsText = formatCustomFieldLines(regData[1])
				if status ~= nil and has_value(flagStatuses, status) then
					TriggerClientEvent('pNotify:SendNotification', source,
									{text = ('<b style=\'color:yellow\'>' .. camCapitalized .. ' ALPR</b><br/>Plate: %s<br/>Status: %s<br/>%s%sOwner: %s'):format(plate:upper(), status, expires, customFieldsText, owner),
						type = 'success', queue = 'alpr', timeout = pluginConfig.notificationTimers.validReg, layout = 'centerLeft'})
				end
				if #boloData > 0 then
					local flags = table.concat(boloData, ',')
					TriggerClientEvent('pNotify:SendNotification', source, {text = ('<b style=\'color:red\'>BOLO ALERT!<br/>Plate: %s<br/>Flags: %s'):format(plate:upper(), flags), type = 'error', queue = 'bolo',
						timeout = pluginConfig.notificationTimers.bolo, layout = 'centerLeft'})
					TriggerEvent('SonoranCAD::wraithv2:BoloAlert', plate, flags)
					TriggerClientEvent('SonoranCAD::wraithv2:PlaySound', source, 'bolo')
				end
				if #warrantData > 0 then
					local warrants = table.concat(warrantData, ',')
					TriggerClientEvent('pNotify:SendNotification', source, {text = ('<b style=\'color:red\'>WARRANT ALERT!<br/>Plate: %s<br/>Flags: %s'):format(plate:upper(), warrants), type = 'error', queue = 'warrant',
						timeout = pluginConfig.notificationTimers.warrant, layout = 'centerLeft'})
					TriggerEvent('SonoranCAD::wraithv2:WarrantAlert', plate, warrants)
					TriggerClientEvent('SonoranCAD::wraithv2:PlaySound', source, 'warrant')
				end
			else
				if pluginConfig.alertNoRegistration then
					TriggerClientEvent('pNotify:SendNotification', source,
									{text = '<b style=\'color:yellow\'>' .. camCapitalized .. ' ALPR</b><br/>Plate: ' .. plate:upper() .. '<br/>Status: Not Registered', type = 'warning', queue = 'alpr',
						timeout = pluginConfig.notificationTimers.noReg, layout = 'centerLeft'})
					TriggerEvent('SonoranCAD::wraithv2:NoRegAlert', plate)
					TriggerClientEvent('SonoranCAD::wraithv2:PlaySound', source, 'registration')
				end
			end
		end )
	end)

end
