CreateThread(function()
    Config.LoadPlugin("bodycam", function(pluginConfig)
        if pluginConfig.enabled then
            RegisterCommand(pluginConfig.command, function(source, args, rawCommand)
                if Config.apiVersion < 4 then
                    errorLog('Bodycam is only enabled with SonoranCAD Pro.')
                    TriggerClientEvent('chat:addMessage', source, {
                        args = {
                            'Sonoran Bodycam',
                            'Bodycam is only enabled with SonoranCAD Pro.'
                        }
                    })
                    return
                end
                local unit = GetUnitByPlayerId(source)
                if unit == nil then
                    TriggerClientEvent('chat:addMessage', source, {
                        args = {
                            'Sonoran Bodycam',
                            'You must be onduty in CAD to use this command.'
                        }
                    })
                    return
                end
                if #args == 0 then
                    TriggerClientEvent('SonoranCAD::bodycam::Toggle', source, true)
                end
                if args[1] == 'freq' then
                    TriggerClientEvent('SonoranCAD::bodycam::SetScreenshotFrequency', source, args[2])
                elseif args[1] == 'sound' then
                    TriggerClientEvent('SonoranCAD::bodycam::SetSoundLevel', source, args[2])
                elseif args[1] == 'anim' then
                    TriggerClientEvent('SonoranCAD::bodycam::ToggleAnimation', source)
                elseif args[1] == 'overlay' then
                    TriggerClientEvent('SonoranCAD::bodycam::ToggleOverlay', source)
                end
            end, false)

            RegisterNetEvent('SonoranCAD::bodycam::Request', function()
                if not Config.proxyUrl or Config.proxyUrl == '' then
                    -- tell client we're not ready
                    TriggerClientEvent('SonoranCAD::bodycam::Init', source, 0, Config.apiVersion)
                else
                    -- tell client we're ready
                    if Config.apiVersion == -1 then
                        debugLog('API version not set, waiting for it to be set...')
                        while Config.apiVersion == -1 do Wait(1000) end
                    end
                    TriggerClientEvent('SonoranCAD::bodycam::Init', source, 1, Config.apiVersion)
                end
            end)

            RegisterNetEvent('SonoranCAD::core::PlayerReady', function()
                if not Config.proxyUrl or Config.proxyUrl == '' then
                    TriggerClientEvent('SonoranCAD::bodycam:Init', source, 0, Config.apiVersion)
                else
                    if Config.apiVersion == -1 then
                        debugLog('API Version not set, waiting for it to be set...')
                        while Config.apiVersion == -1 do Wait(1000) end
                    end
                    TriggerClientEvent('SonoranCAD::bodycam:Init', source, 0, Config.apiVersion)
                end
            end)

            RegisterNetEvent('SonoranCAD::bodycam::RequestSound', function()
                local source = source
                TriggerClientEvent('SonoranCAD::bodycam::GiveSound', -1, source, GetEntityCoords(GetPlayerPed(source)))
            end)
            RegisterNetEvent('SonoranCAD::bodycam::RequestToggle', function(manualActivation, toggle)
                if pluginConfig.requireUnitDuty then
                    local unit = GetUnitByPlayerId(source)
                    if unit == nil and toggle then
                        if manualActivation then
                            TriggerClientEvent('chat:addMessage', source, {
                                args = {
                                    'Sonoran Bodycam',
                                    'You must be onduty in CAD to use this command.'
                                }
                            })
                        end
                        return
                    end
                    TriggerClientEvent('SonoranCAD::bodycam::Toggle', source, manualActivation, toggle)
                else
                    TriggerClientEvent('SonoranCAD::bodycam::Toggle', source, manualActivation, toggle)
                end
            end)
        end
    end)
end)
