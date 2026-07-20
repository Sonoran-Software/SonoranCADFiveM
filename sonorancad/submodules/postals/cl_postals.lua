--[[
    Sonaran CAD Plugins

    Plugin Name: postals
    Creator: SonoranCAD
    Description: Fetches nearest postal from client
]]

CreateThread(function()
	Config.LoadPlugin('postals', function(pluginConfig)
		local lastPostal = nil
		local eventPostal = nil
		local lastPostalErrorCode = nil
		local postalResourceReady = true
		local postalResourceRetryCount = 3
		local postalResourceRetryDelay = 100

		local function reportPostalFailure(code, msg)
			if lastPostalErrorCode ~= code then
				showClientError(code, msg)
				lastPostalErrorCode = code
			end
		end

		local function clearPostalFailure()
			lastPostalErrorCode = nil
		end

		local function isPostalResourceMode()
			return pluginConfig.mode and pluginConfig.mode == 'resource'
		end

		local function isPostalResourceStarted()
			return not isPostalResourceMode() or GetResourceState(pluginConfig.nearestPostalResourceName) == 'started'
		end

		if isPostalResourceMode() then
			postalResourceReady = isPostalResourceStarted()
			AddEventHandler('onClientResourceStop', function(resourceName)
				if resourceName == pluginConfig.nearestPostalResourceName then
					postalResourceReady = false
					lastPostal = nil
					clearPostalFailure()
				end
			end)
			AddEventHandler('onClientResourceStart', function(resourceName)
				if resourceName == pluginConfig.nearestPostalResourceName then
					postalResourceReady = true
					lastPostal = nil
					clearPostalFailure()
				end
			end)
		end

		if pluginConfig.enabled then
			-- Don't touch this!
			function getNearestPostal()
				local ok, postalOrErr = pcall(function()
					if pluginConfig.mode and pluginConfig.mode == 'event' then
						return eventPostal
					elseif pluginConfig.mode and pluginConfig.mode == 'file' then
						local postalFile = LoadResourceFile(GetCurrentResourceName(), ('submodules/postals/%s'):format(pluginConfig.customPostalCodesFile))
						if postalFile == nil then
							reportPostalFailure('POSTALS_FILE_INVALID', 'Custom postal file not found.')
							return nil
						end

						local postalData = SafeJsonDecode(postalFile, 'custom postal file', nil)
						if type(postalData) ~= 'table' or #postalData == 0 then
							reportPostalFailure('POSTALS_FILE_INVALID', 'Custom postal file is invalid.')
							return nil
						end

						for i, postal in ipairs(postalData) do
							if postal == nil or postal.x == nil or postal.y == nil or postal.code == nil then
								reportPostalFailure('POSTALS_FILE_INVALID', 'Custom postal file contains invalid entries.')
								return nil
							end
							postalData[i] = { vec(postal.x, postal.y), code = postal.code }
						end

						local coords = GetEntityCoords(PlayerPedId())
						local _nearestIndex, _nearestD
						coords = vec(coords[1], coords[2])
						local _total = #postalData
						for i = 1, _total do
							local D = #(coords - postalData[i][1])
							if not _nearestD or D < _nearestD then
								_nearestIndex = i
								_nearestD = D
							end
						end

						if _nearestIndex == nil then
							reportPostalFailure('POSTALS_LOOKUP_FAILED', 'Custom postal lookup returned no result.')
							return nil
						end

						return postalData[_nearestIndex].code
					else
						if not isPostalResourceStarted() then
							postalResourceReady = false
							reportPostalFailure('POSTALS_RESOURCE_UNAVAILABLE', 'Required postal resource is not ready. Retrying automatically.')
							return nil
						end

						for attempt = 1, postalResourceRetryCount do
							local resourceOk, postal = pcall(function()
								return exports[pluginConfig.nearestPostalResourceName]:getPostal()
							end)
							if resourceOk then
								postalResourceReady = true
								return postal
							end
							postalResourceReady = false
							if attempt < postalResourceRetryCount then
								Wait(postalResourceRetryDelay)
							end
						end

						reportPostalFailure('POSTALS_RESOURCE_UNAVAILABLE', 'Required postal resource export is not ready. Retrying automatically.')
						return nil
					end
				end)

				if not ok then
					if isPostalResourceMode() and not postalResourceReady then
						reportPostalFailure('POSTALS_RESOURCE_UNAVAILABLE', 'Required postal resource is not ready. Retrying automatically.')
					else
						reportPostalFailure('POSTALS_LOOKUP_FAILED', ('Nearest postal lookup failed: %s'):format(tostring(postalOrErr)))
					end
					return nil
				end

				if postalOrErr ~= nil and postalOrErr ~= '' then
					clearPostalFailure()
				end

				return postalOrErr
			end
			if pluginConfig.mode and pluginConfig.nearestPostalEvent and pluginConfig.mode == 'event' then
				AddEventHandler(pluginConfig.nearestPostalEvent, function(postal)
					eventPostal = postal
				end)
			end
			local function sendPostalData()
				local postal = getNearestPostal()
				if postal ~= nil and postal ~= lastPostal then
					TriggerServerEvent('cadClientPostal', postal)
					lastPostal = postal
				end
			end
			CreateThread(function()
				while not NetworkIsPlayerActive(PlayerId()) or pluginConfig.sendTimer == nil do
					Wait(10)
				end
				TriggerServerEvent('getShouldSendPostal')
				while true do
					if pluginConfig.shouldSendPostalData then
						sendPostalData()
					end
					Wait(pluginConfig.sendTimer)
				end
			end)
			RegisterNetEvent('getShouldSendPostalResponse')
			AddEventHandler('getShouldSendPostalResponse', function(toggle)
				pluginConfig.shouldSendPostalData = toggle
			end)
		end
	end)
end)
