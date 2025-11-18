CreateThread(function()
	Config.LoadPlugin('vehreg', function(pluginConfig)
		if pluginConfig.enabled then
			local civData = {}
			local notSetConfig = false
			local placeholderReplace = function(message, placeholderTable)
				for k, v in pairs(placeholderTable) do
					message = message:gsub(k, v)
				end
				return message
			end
			RegisterNetEvent(GetCurrentResourceName() .. '::registerVeh',
				function(primary, plate, class, realName, make, year)
					local source = source
					exports['sonorancad']:registerApiType('NEW_RECORD', 'general')
					exports['sonorancad']:registerApiType('GET_CHARACTERS', 'civilian')
					exports['sonorancad']:performApiRequest({
						{
							['apiId'] = GetIdentifiers(source)[Config.primaryIdentifier]
						}
					}, 'GET_CHARACTERS', function(res, err)
						if err == 404 then
							TriggerClientEvent('chat:addMessage', source, {
								color = {
									255,
									0,
									0
								},
								multiline = true,
								args = {
									'[CAD - ERROR] ',
									pluginConfig.language.noApiId
								}
							})
							return;
						else
							res = json.decode(res)
							if not res or type(res) ~= 'table' then
								TriggerClientEvent('chat:addMessage', source, {
									color = {
										255,
										0,
										0
									},
									multiline = true,
									args = {
										'[CAD - ERROR] ',
										pluginConfig.language.noCharFound or
										"No character found. Please ensure you are logged in to a character."
									}
								})
								return;
							end
							if #res < 1 then
								TriggerClientEvent('chat:addMessage', source, {
									color = {
										255,
										0,
										0
									},
									multiline = true,
									args = {
										'[CAD - ERROR] ',
										pluginConfig.language.noCharFound or
										"No character found. Please ensure you are logged in to a character."
									}
								})
								return;
							end
							for iterator, table in pairs(res[1].sections) do
								if table.category == 0 then
									for iterator, field in pairs(table.fields) do
										civData[field.uid] = field.value
									end
								end
							end
						end
					end)
					Citizen.Wait(1000)
					if not pluginConfig.recordData then
						notSetConfig = true
						pluginConfig.recordData = {
							colorUid = "color",
							plateUid = "plate",
							typeUid = "type",
							modelUid = "model",
							makeUid = "make",
							yearUid = "year",
							statusUid = "status",
							expiresUid = "_imtoih149",
						}
						warnLog(
							'Record data not found in configuration. Using default values. Please update your configuration using the vehreg_config.dist.lua file located in the configuration folder')
					end
					if notSetConfig then
						warnLog(
							'Record data not found in configuration. Using default values. Please update your configuration using the vehreg_config.dist.lua file located in the configuration folder')
					end
					local replaceValues = {
						[pluginConfig.recordData.colorUid] = primary,
						[pluginConfig.recordData.plateUid] = plate,
						[pluginConfig.recordData.typeUid] = class,
						[pluginConfig.recordData.modelUid] = realName,
						[pluginConfig.recordData.makeUid] = make,
						[pluginConfig.recordData.yearUid] = year,
						[pluginConfig.recordData.statusUid] = pluginConfig.defaultRegStatus,
						[pluginConfig.recordData.expiresUid] = pluginConfig.defaultRegExpire
					}
					for k, v in pairs(civData) do
						replaceValues[k] = v
					end
					exports['sonorancad']:performApiRequest({
						{
							['user'] = GetIdentifiers(source)[Config.primaryIdentifier],
							['useDictionary'] = true,
							['recordTypeId'] = 5,
							['replaceValues'] = replaceValues
						}
					}, 'NEW_RECORD', function(res)
						res = tostring(res)
						if string.find(res, 'taken') ~= nil then
							TriggerClientEvent('chat:addMessage', source, {
								color = {
									255,
									0,
									0
								},
								multiline = true,
								args = {
									'[CAD - ERROR] ',
									pluginConfig.language.plateAlrRegisted
								}
							})
						else
							local placeHolders = {
								['{{PLATE}}'] = plate,
								['{{FIRST}}'] = civData.first,
								['{{LAST}}'] = civData.last
							}
							TriggerClientEvent('chat:addMessage', source, {
								color = {
									0,
									255,
									0
								},
								multiline = true,
								args = {
									'[CAD - SUCCESS] ',
									placeholderReplace(pluginConfig.language.successReg, placeHolders)
								}
							})
						end
					end)
				end)
		end
	end)
end)
