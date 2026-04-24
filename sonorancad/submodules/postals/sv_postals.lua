--[[
    Sonaran CAD Plugins

    Plugin Name: postals
    Creator: SonoranCAD
    Description: Fetches nearest postal from client
]] -- Toggles Postal Sender
CreateThread(function()
	Config.LoadPlugin('postals', function(pluginConfig)
		local locationsConfig = Config.GetPluginConfig('locations')

		if pluginConfig.enabled and locationsConfig ~= nil then

			local postalFile = nil
			local postals
			local state = GetResourceState(pluginConfig.nearestPostalResourceName)
			local shouldStop = false
			if pluginConfig.mode and pluginConfig.mode == 'resource' then
				if state ~= 'started' then
					if state == 'missing' then
						logError('POSTAL_RESOURCE_MISSING', getErrorText('POSTAL_RESOURCE_MISSING'):format(pluginConfig.nearestPostalResourceName))
						shouldStop = true
					elseif state == 'stopped' then
						logError('POSTAL_RESOURCE_STOPPED', getErrorText('POSTAL_RESOURCE_STOPPED'):format(pluginConfig.nearestPostalResourceName, state))
					else
						logError('POSTAL_RESOURCE_BAD_STATE', getErrorText('POSTAL_RESOURCE_BAD_STATE'):format(pluginConfig.nearestPostalResourceName, state))
						shouldStop = true
					end
				else
					postalFile = LoadResourceFile(pluginConfig.nearestPostalResourceName, GetResourceMetadata(pluginConfig.nearestPostalResourceName, 'postal_file'))
					if postalFile == nil then
						logError('POSTAL_CUSTOM_RESOURCE_FILE_ERROR', getErrorText('POSTAL_CUSTOM_RESOURCE_FILE_ERROR'):format(pluginConfig.nearestPostalResourceName, pluginConfig.nearestPostalResourceName))
					end
				end
			elseif pluginConfig.mode and pluginConfig.mode == 'file' then
				postalFile = LoadResourceFile(GetCurrentResourceName(), ('/submodules/postals/%s'):format(pluginConfig.customPostalCodesFile))
				if postalFile == nil then
					logError('CUSTOM_POSTALS_FILE_NOT_FOUND', geterrorText('CUSTOM_POSTALS_FILE_NOT_FOUND'):format(pluginConfig.customPostalCodesFile))
					shouldStop = true
				end
			end
			if postalFile == nil then
				logError('POSTAL_FILE_READ_ERROR')
				shouldStop = true
			end
			if shouldStop then
				pluginConfig.enabled = false
				pluginConfig.disableReason = 'postal resource incorrect'
				errorLog('Force disabling plugin to prevent client errors.')
				return
			end

			postals = json.decode(postalFile)
			for i, postal in ipairs(postals) do
				postals[i] = {vec(postal.x, postal.y), code = postal.code}
			end

			PostalsCache = {}

			RegisterNetEvent('getShouldSendPostal')
			AddEventHandler('getShouldSendPostal', function()
				TriggerClientEvent('getShouldSendPostalResponse', source, locationsConfig.prefixPostal)
			end)

			RegisterNetEvent('cadClientPostal')
			AddEventHandler('cadClientPostal', function(postal)
				PostalsCache[source] = postal
			end)

			AddEventHandler('playerDropped', function(player)
				PostalsCache[player] = nil
			end)

			function getNearestPostal(player)
				return PostalsCache[player]
			end

			exports('cadGetNearestPostal', getNearestPostal)

			CreateThread(function()
				while Config.apiVersion == -1 or postals == nil do
					Wait(1000)
				end
				if Config.apiVersion < 4 then
					return
				elseif not Config.apiSendEnabled then
					errorLog('Config.apiSendEnabled disabled via convar or config, skipping postal sending. Check your config if this is unintentional.')
				end
				local response = CadApiSetPostals(json.decode(postalFile))
				if not response.success then
					CadApiLogFailure('SET_POSTALS', response, postals)
				end
			end)

			function getPostalFromVector3(coords)
				if not coords or postals == nil then
					return nil
				end
				local _total = #postals
				local _nearestIndex, _nearestD
				coords = vector2(coords.x, coords.y)

				for i = 1, _total do
					local D = #(coords - postals[i][1])
					if not _nearestD or D < _nearestD then
						_nearestIndex = i
						_nearestD = D
					end
				end

				return postals[_nearestIndex].code
			end

		elseif locationsConfig == nil then
			errorLog('ERROR: Postals plugin is loaded, but required locations plugin is not. This plugin will not function correctly!')
			pluginConfig.enabled = false
			pluginConfig.disableReason = 'locations plugin missing'
		end

	end)
end)
