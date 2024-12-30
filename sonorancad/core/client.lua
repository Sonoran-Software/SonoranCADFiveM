Config = {plugins = {}}
Plugins = {}

bodyCamOn = false;
bodyCamFrequency = 2000;
local bodyCamConfigReady = false;

Config.RegisterPluginConfig = function(pluginName, configs)
    Config.plugins[pluginName] = {}
    for k, v in pairs(configs) do Config.plugins[pluginName][k] = v end
    table.insert(Plugins, pluginName)
end

--[[
    @function getApiMode
    @description Returns the API mode for the current server. 0 = Development, 1 = Production
    @returns int
]]
function getApiMode()
    if Config.mode == nil then
        return 1
    elseif Config.mode == 'development' then
        return 0
    else
        return 1
    end
end

exports('getApiMode', getApiMode)

Config.GetPluginConfig = function(pluginName)
    local correctConfig = nil
    if Config.plugins[pluginName] ~= nil then
        if Config.critError then
            Config.plugins[pluginName].enabled = false
            Config.plugins[pluginName].disableReason = 'startup aborted'
        elseif Config.plugins[pluginName].enabled == nil then
            Config.plugins[pluginName].enabled = true
        elseif Config.plugins[pluginName].enabled == false then
            Config.plugins[pluginName].disableReason = 'Disabled'
        end
        return Config.plugins[pluginName]
    else
        if pluginName == 'apicheck' or pluginName == 'livemap' or pluginName ==
            'smartsigns' then
            return {enabled = false, disableReason = 'deprecated plugin'}
        end
        correctConfig = LoadResourceFile(GetCurrentResourceName(),
                                         '/configuration/' .. pluginName ..
                                             '_config.lua')
        if not correctConfig then
            warnLog(
                ('Plugin %s is missing critical configuration. Please check our plugin install guide at https://info.sonorancad.com/integration-submodules/integration-submodules/plugin-installation for steps to properly install.'):format(
                    pluginName))
            Config.plugins[pluginName] = {
                enabled = false,
                disableReason = 'Missing configuration file'
            }
            return {
                enabled = false,
                disableReason = 'Missing configuration file'
            }
        else
            local configChunk = correctConfig:match("local config = {.-\n}") ..
                                    "\nreturn config"
            if not configChunk then
                errorLog("No config table found in the string.")
            end
            local tempEnv = {}
            setmetatable(tempEnv, {__index = _G}) -- Allow access to global functions if needed
            local loadedPlugin, pluginError =
                load(configChunk, 'config', 't', tempEnv)
            if loadedPlugin then
                -- Execute and capture the returned config table
                local success, res = pcall(loadedPlugin)
                if not success then
                    errorLog(
                        ('Plugin %s failed to load due to error: %s'):format(
                            pluginName, res))
                    Config.plugins[pluginName] = {
                        enabled = false,
                        disableReason = 'Failed to load'
                    }
                    return {enabled = false, disableReason = 'Failed to load'}
                end
                if res and type(res) == "table" then
                    -- Assign the extracted config to Config.plugins[pluginName]
                    Config.plugins[pluginName] = res
                else
                    -- Handle case where config is not available
                    errorLog(
                        ('Plugin %s did not define a valid config table.'):format(
                            pluginName))
                    Config.plugins[pluginName] = {
                        enabled = false,
                        disableReason = 'Invalid or missing config'
                    }
                    return {
                        enabled = false,
                        disableReason = 'Invalid or missing config'
                    }
                end
                if Config.critError then
                    Config.plugins[pluginName].enabled = false
                    Config.plugins[pluginName].disableReason = 'startup aborted'
                elseif Config.plugins[pluginName].enabled == nil then
                    Config.plugins[pluginName].enabled = true
                elseif Config.plugins[pluginName].enabled == false then
                    Config.plugins[pluginName].disableReason = 'Disabled'
                end
            else
                errorLog(('Plugin %s failed to load due to error: %s'):format(
                             pluginName, pluginError))
                Config.plugins[pluginName] = {
                    enabled = false,
                    disableReason = 'Failed to load'
                }
                return {enabled = false, disableReason = 'Failed to load'}
            end
            return Config.plugins[pluginName]
        end
        Config.plugins[pluginName] = {
            enabled = false,
            disableReason = 'Missing configuration file'
        }
        return {enabled = false, disableReason = 'Missing configuration file'}
    end
end

Config.LoadPlugin = function(pluginName, cb)
    local correctConfig = nil
    while Config.apiVersion == -1 do Wait(1) end
    if Config.plugins[pluginName] ~= nil then
        if Config.critError then
            Config.plugins[pluginName].enabled = false
            Config.plugins[pluginName].disableReason = 'startup aborted'
        elseif Config.plugins[pluginName].enabled == nil then
            Config.plugins[pluginName].enabled = true
        elseif Config.plugins[pluginName].enabled == false then
            Config.plugins[pluginName].disableReason = 'Disabled'
        end
        return cb(Config.plugins[pluginName])
    else
        if pluginName == 'yourpluginname' then
            return cb({enabled = false, disableReason = 'Template plugin'})
        end
        correctConfig = LoadResourceFile(GetCurrentResourceName(),
                                         '/configuration/' .. pluginName ..
                                             '_config.lua')
        if not correctConfig then
            warnLog(
                ('Submodule %s is missing critical configuration. Please check our submodule install guide at https://info.sonorancad.com/integration-plugins/in-game-integration/fivem-installation/submodule-configuration#activating-a-submodule for steps to properly install.'):format(
                    pluginName))
            Config.plugins[pluginName] = {
                enabled = false,
                disableReason = 'Missing configuration file'
            }
            return {
                enabled = false,
                disableReason = 'Missing configuration file'
            }
        else
            local configChunk = correctConfig:match("local config = {.-\n}") ..
                                    "\nreturn config"
            if not configChunk then
                errorLog("No config table found in the string.")
            end
            local tempEnv = {}
            setmetatable(tempEnv, {__index = _G}) -- Allow access to global functions if needed
            local loadedPlugin, pluginError =
                load(configChunk, 'config', 't', tempEnv)
            if loadedPlugin then
                -- Execute and capture the returned config table
                local success, res = pcall(loadedPlugin)
                if not success then
                    errorLog(
                        ('Submodule %s failed to load due to error: %s'):format(
                            pluginName, res))
                    Config.plugins[pluginName] = {
                        enabled = false,
                        disableReason = 'Failed to load'
                    }
                    return {enabled = false, disableReason = 'Failed to load'}
                end
                if res and type(res) == "table" then
                    -- Assign the extracted config to Config.plugins[pluginName]
                    Config.plugins[pluginName] = res
                else
                    -- Handle case where config is not available
                    errorLog(
                        ('Submodule %s did not define a valid config table.'):format(
                            pluginName))
                    Config.plugins[pluginName] = {
                        enabled = false,
                        disableReason = 'Invalid or missing config'
                    }
                    return {
                        enabled = false,
                        disableReason = 'Invalid or missing config'
                    }
                end
                if Config.critError then
                    Config.plugins[pluginName].enabled = false
                    Config.plugins[pluginName].disableReason = 'startup aborted'
                elseif Config.plugins[pluginName].enabled == nil then
                    Config.plugins[pluginName].enabled = true
                elseif Config.plugins[pluginName].enabled == false then
                    Config.plugins[pluginName].disableReason = 'Disabled'
                end
            else
                errorLog(('Submodule %s failed to load due to error: %s'):format(
                             pluginName, pluginError))
                Config.plugins[pluginName] = {
                    enabled = false,
                    disableReason = 'Failed to load'
                }
                return {enabled = false, disableReason = 'Failed to load'}
            end
            return Config.plugins[pluginName]
        end
        Config.plugins[pluginName] = {
            enabled = false,
            disableReason = 'Missing configuration file'
        }
        return cb({
            enabled = false,
            disableReason = 'Missing configuration file'
        })
    end
end

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(1) end
    TriggerServerEvent('SonoranCAD::core:sendClientConfig')
end)

RegisterNetEvent('SonoranCAD::core:recvClientConfig')
AddEventHandler('SonoranCAD::core:recvClientConfig', function(config)
    for k, v in pairs(config) do Config[k] = v end
    Config.inited = true
    debugLog('Configuration received')
    debugLog('Bodycam config ready')
end)

--[[
	SonoranCAD Bodycam Callback if unit is not found in CAD
]]
RegisterNetEvent('SonoranCAD::core::ScreenshotOff', function()
    if Config.bodycamEnabled then
        bodyCamOn = false
        if Config.bodycamOverlayEnabled then
            SendNUIMessage({type = 'toggleGif'})
        end
        TriggerEvent('chat:addMessage', {
            args = {
                'Sonoran Bodycam',
                'Bodycam disabled - You must be in CAD to enable bodycam'
            }
        })
    end
end)

RegisterNetEvent('SonoranCAD::Core::InitBodycam', function(isReady)
    if isReady == 0 then
        CreateThread(function()
            -- still waiting, request again in 10s
            debugLog('Bodycam not ready, retrying in 10s')
            Wait(10000)
            TriggerServerEvent('SonoranCAD::Core::RequestBodycam')
        end)
        return
    end
    if Config.bodycamEnabled then
        print('Bodycam init')
        -- Command to toggle bodycam on and off
        RegisterCommand(Config.bodycamCommandToggle,
                        function(source, args, rawCommand)
            if Config.apiVersion < 4 then
                errorLog('Bodycam is only enabled with Sonoran CAD Pro.')
                TriggerEvent('chat:addMessage', {
                    args = {
                        'Sonoran Bodycam',
                        'Bodycam is only enabled with Sonoran CAD Pro.'
                    }
                })
                return
            end
            if bodyCamOn then
                bodyCamOn = false
                TriggerServerEvent('SonoranCAD::core::bodyCamOff')
                TriggerEvent('chat:addMessage',
                             {args = {'Sonoran Bodycam', 'Bodycam disabled.'}})
                if Config.bodycamOverlayEnabled then
                    SendNUIMessage({
                        type = 'toggleGif',
                        location = Config.bodycamOverlayLocation
                    })
                end
            else
                bodyCamOn = true
                TriggerEvent('chat:addMessage',
                             {args = {'Sonoran Bodycam', 'Bodycam enabled.'}})
                if Config.bodycamOverlayEnabled then
                    SendNUIMessage({
                        type = 'toggleGif',
                        location = Config.bodycamOverlayLocation
                    })
                end
            end
        end, false)
        -- Command to change the frequency of bodycam screenshots
        RegisterCommand(Config.bodycamCommandChangeFrequncy,
                        function(source, args, rawCommand)
            if Config.apiVersion < 4 then
                errorLog('Bodycam is only enabled with Sonoran CAD Pro.')
                TriggerEvent('chat:addMessage', {
                    args = {
                        'Sonoran Bodycam',
                        'Bodycam is only enabled with Sonoran CAD Pro.'
                    }
                })
                return
            end
            if args[1] then
                args[1] = tonumber(args[1])
                if not args[1] or args[1] <= 0 or args[1] > 10 then
                    errorLog(
                        'Frequency must a number greater than 0 and less than than 10 seconds.')
                    TriggerEvent('chat:addMessage', {
                        args = {
                            'Sonoran Bodycam',
                            'Frequency must a number greater than 0 and less than than 10 seconds.'
                        }
                    })
                    return
                end
                bodyCamFrequency = (tonumber(args[1]) * 1000)
                TriggerEvent('chat:addMessage', {
                    args = {
                        'Sonoran Bodycam',
                        ('Frequency set to %s.'):format(
                            (bodyCamFrequency / 1000))
                    }
                })
            else
                TriggerEvent('chat:addMessage', {
                    args = {
                        'Sonoran Bodycam',
                        ('Current bodycam frequency is %s.'):format(
                            (bodyCamFrequency / 1000))
                    }
                })
            end
        end, false)
        -- Add suggestions to the chat
        TriggerEvent('chat:addSuggestion', '/' .. Config.bodycamCommandToggle,
                     'Enable or disable bodycam mode.')
        TriggerEvent('chat:addSuggestion',
                     '/' .. Config.bodycamCommandChangeFrequncy,
                     'Change the frequency of bodycam screenshots.',
                     {{name = 'frequency', help = 'Frequency in seconds.'}})
    end
end)

CreateThread(function()
    while not Config.inited do Wait(10) end
    if Config.devHiddenSwitch then
        debugLog('Spawned discord thread')
        SetDiscordAppId(867548404724531210)
        SetDiscordRichPresenceAsset('icon')
        SetDiscordRichPresenceAssetSmall('icon')
        while true do
            SetRichPresence('Developing SonoranCAD!')
            Wait(5000)
            SetRichPresence('sonorancad.com')
            Wait(5000)
        end
    end
end)

local inited = false
AddEventHandler('playerSpawned', function()
    TriggerServerEvent('SonoranCAD::core:PlayerReady')
    inited = true
    TriggerServerEvent('SonoranCAD::Core::RequestBodycam')
end)

RegisterNetEvent('SonoranCAD::core:debugModeToggle')
AddEventHandler('SonoranCAD::core:debugModeToggle',
                function(toggle) Config.debugMode = toggle end)

RegisterNetEvent('SonoranCAD::core:AddPlayer')
RegisterNetEvent('SonoranCAD::core:RemovePlayer')

--[[
    SonoranCAD Bodycam Plugin
]]

-- Main bodycam loops
CreateThread(function()
    while true do
        Wait(1)
        if bodyCamOn then
            TriggerServerEvent('SonoranCAD::core:TakeScreenshot')
            Wait(bodyCamFrequency)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1)
        if Config.bodycamPlayBeeps then
            if bodyCamOn then
                SendNUIMessage({
                    type = 'playSound',
                    transactionFile = 'sounds/beeps.mp3',
                    transactionVolume = 0.3
                })
                Wait(Config.bodycamBeepFrequency)
            end
        end
    end
end)

RegisterCommand('time', function()
    local hours = GetClockHours()
    local minutes = GetClockMinutes()
    TriggerEvent('chat:addMessage', {
        args = {
            'SonoranCAD',
            ('Current time: %s:%s'):format(hours, minutes)
        }
    })
end)

-- Jordan - Time Utils
local isSendingTime = false

local function getFormattedGameTime()
    -- Get in-game date and time
    local year, month, day = GetClockYear(), GetClockMonth(), GetClockDayOfMonth()
    local hour, minute, second = GetClockHours(), GetClockMinutes(), GetClockSeconds()

    -- Format the in-game time as "YYYY-MM-DD HH:MM:SS"
    return string.format("%04d-%02d-%02d %02d:%02d:%02d", year, month, day, hour, minute, second)
end

local function getSecondsPerInGameHour()
    -- Get milliseconds per in-game minute
    local msPerMinute = GetMillisecondsPerGameMinute()

    -- Convert to seconds per in-game hour
    local secondsPerHour = (msPerMinute / 1000) * 60
    return secondsPerHour
end

-- Event to start sending time to the server
RegisterNetEvent("SonoranCad:time:requestSendTime", function()
    debugLog("You have been selected to send the time.")
    isSendingTime = true

    Citizen.CreateThread(function()
        while isSendingTime do
            local inGameTime = getFormattedGameTime()
            local secondsPerHour = getSecondsPerInGameHour()
            local timeData = {
                currentGame = inGameTime,
                secondsPerHour = secondsPerHour
            }
            TriggerServerEvent("SonoranCad:time:sendTime", timeData)
            debugLog("Time sent to server: " .. json.encode(timeData))
            Citizen.Wait(60000) -- Wait 60 seconds before sending again
        end
    end)
end)

-- Event to stop sending time (optional cleanup)
RegisterNetEvent("SonoranCad:time:stopSendingTime", function()
    debugLog("You are no longer required to send the time.")
    isSendingTime = false
end)
