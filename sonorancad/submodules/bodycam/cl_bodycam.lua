bodyCamOn = false
local showOverlay = true
local doAnimation = true
screenshotFrequency = 2000
local soundLevel = 0.3
CreateThread(function()
    Config.LoadPlugin("bodycam", function(pluginConfig)
        if pluginConfig.enabled then
            doAnimation = pluginConfig.enableAnimation
            showOverlay = pluginConfig.enableOverlay
            screenshotFrequency = pluginConfig.screenshotFrequency

            function IsWearingBodycam()
                local ped = PlayerPedId()
                local pedModel = GetEntityModel(ped)
                if not pluginConfig.clothing or #pluginConfig.clothing == 0 then
                    return true
                end
                for _, item in ipairs(pluginConfig.clothing) do
                    if not item.ped or pedModel == GetHashKey(item.ped) then
                        if item.component and item.drawable then
                            local compDrawable = GetPedDrawableVariation(ped, item.component)
                            if compDrawable == item.drawable then
                                if item.textures then
                                    local compTexture = GetPedTextureVariation(ped, item.component)
                                    for _, tex in ipairs(item.textures) do
                                        if compTexture == tex then
                                            return true
                                        end
                                    end
                                else
                                    return true
                                end
                            end
                        elseif item.component then
                            return true
                        elseif item.ped then
                            return true
                        end
                    end
                end
                return false
            end

            function PlayBeepSound()
                if pluginConfig.beepType == 'native' then
                    local coord = GetEntityCoords(GetPlayerPed(PlayerId()))
                    PlaySoundFromCoord(-1, 'Beep_Red', coord.x, coord.y, coord.z,
                        'DLC_HEIST_HACKING_SNAKE_SOUNDS', false, 0, false)
                else
                    SendNUIMessage({
                        type = 'playSound',
                        transactionFile = 'sounds/beeps.mp3',
                        transactionVolume = soundLevel
                    })
                end
            end

            AddEventHandler('playerSpawned', function()
                TriggerServerEvent('SonoranCAD::bodycam::Request')
            end)

            TriggerEvent('chat:addSuggestion', '/' .. pluginConfig.command, '',
                { { name = "[freq|sound|anim|overlay]", help = "Subcommand" } })
            RegisterCommand('SonoranCAD::bodycam::Keybind', function()
                TriggerServerEvent('SonoranCAD::bodycam::RequestToggle', true, not bodyCamOn)
            end, false)
            RegisterKeyMapping('SonoranCAD::bodycam::Keybind', "Toggle BodyCam", "keyboard", pluginConfig.defaultKeybind)
            CreateThread(function()
                while pluginConfig.autoEnableWithWeapons do
                    Wait(1)
                    local ped = PlayerPedId()
                    local weapon = GetSelectedPedWeapon(ped)
                    if not bodyCamOn and pluginConfig.weapons then
                        for _, weaponName in ipairs(pluginConfig.weapons) do
                            if weapon == GetHashKey(weaponName) then
                                TriggerServerEvent('SonoranCAD::bodycam::RequestToggle', false, true)
                                break
                            end
                        end
                    end
                end
            end)

            CreateThread(function()
                while pluginConfig.autoEnableWithLights do
                    Wait(1)
                    local ped = PlayerPedId()
                    local veh = GetVehiclePedIsIn(ped, false)
                    -- Only check if player is in a vehicle and is the driver
                    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and GetVehicleClass(veh) == 18 then
                        if IsVehicleSirenOn(veh) then
                            if not bodyCamOn then
                                TriggerServerEvent('SonoranCAD::bodycam::RequestToggle', false, true)
                            end
                        elseif not IsVehicleSirenOn(veh) and bodyCamOn then
                            TriggerServerEvent('SonoranCAD::bodycam::RequestToggle', false, false)
                        end
                    end
                end
            end)

            CreateThread(function()
                while true do
                    Wait(1)
                    if bodyCamOn then
                        TriggerServerEvent('SonoranCAD::core:TakeScreenshot')
                        Wait(screenshotFrequency)
                    end
                end
            end)

            CreateThread(function()
                while true do
                    Wait(1)
                    if pluginConfig.enableBeeps then
                        if bodyCamOn then
                            PlayBeepSound()
                            TriggerServerEvent('SonoranCAD::bodycam::RequestSound')
                            Wait(pluginConfig.beepFrequency)
                        end
                    end
                end
            end)

            RegisterNetEvent('SonoranCAD::bodycam::GiveSound', function(serverId, serverCoords)
                if GetPlayerFromServerId(serverId) ~= PlayerId() and GetDistanceBetweenCoords(GetEntityCoords(GetPlayerPed(PlayerId())), serverCoords, true) < pluginConfig.beepRange then
                    PlayBeepSound()
                end
            end)

            RegisterNetEvent('SonoranCAD::bodycam::Init', function(isReady, apiVersion)
                if isReady == 0 then
                    CreateThread(function()
                        debugLog('Bodycam not ready, retrying in 10s')
                        Wait(10000)
                        TriggerServerEvent('SonoranCAD::bodycam::Request')
                    end)
                    return
                end
                if apiVersion ~= -1 then
                    Config.apiVersion = apiVersion
                end


                RegisterNetEvent('SonoranCAD::bodycam::Toggle', function(manualActivation, toggle)
                    if not IsWearingBodycam() then
                        if manualActivation then
                            TriggerEvent('chat:addMessage',
                                { args = { 'Sonoran Bodycam', 'You must be wearing a bodycam to activate it.' } })
                            return
                        end
                    end

                    if manualActivation and doAnimation then
                        local ped = PlayerPedId()
                        RequestAnimDict("clothingtie")
                        while not HasAnimDictLoaded("clothingtie") do
                            Wait(10)
                        end
                        TaskPlayAnim(ped, "clothingtie", "outro", 8.0, 2.0, 1880, 51, 2.0, false, false, false)
                        Wait(1880)
                    end

                    if not toggle and bodyCamOn then
                        bodyCamOn = false
                        if showOverlay then
                            SendNUIMessage({
                                type = 'toggleGif',
                                location = pluginConfig.overlayLocation
                            })
                        end
                        TriggerServerEvent('SonoranCAD::core::bodyCamOff')
                        TriggerEvent('chat:addMessage',
                            { args = { 'Sonoran Bodycam', 'Bodycam disabled' } })
                        PlayBeepSound()
                    elseif toggle and not bodyCamOn then
                        bodyCamOn = true
                        if showOverlay then
                            SendNUIMessage({
                                type = 'toggleGif',
                                location = pluginConfig.overlayLocation
                            })
                        end
                        TriggerEvent('chat:addMessage',
                            { args = { 'Sonoran Bodycam', 'Bodycam enabled' } })
                        PlayBeepSound()
                    end
                end)
                RegisterNetEvent('SonoranCAD::bodycam::SetScreenshotFrequency', function(frequency)
                    if frequency then
                        frequency = tonumber(frequency)
                        if not frequency or frequency <= 0 or frequency > 10 then
                            errorLog('Screenshot Frequency must be a number greater than 0 and less then 10 seconds.')
                            TriggerEvent('chat:addMessage', {
                                args = { 'Sonoran Bodycam', 'Screenshot Frequency must be a number greater than 0 and less then 10 seconds.' }
                            })
                            return
                        end

                        screenshotFrequency = (tonumber(frequency) * 1000)
                        TriggerEvent('chat:addMessage',
                            { args = { 'Sonoran Bodycam', ('Screenshot Frequency set to %s'):format((screenshotFrequency / 1000)) } })
                    else
                        TriggerEvent('chat:addMessage', {
                            args = { 'Sonoran Bodycam', ('Current screenshot frequency is %s'):format((screenshotFrequency / 1000)) }
                        })
                    end
                end)
                RegisterNetEvent('SonoranCAD::bodycam::SetSoundLevel', function(level)
                    if level then
                        level = tonumber(level)
                        if not level or level <= 0 or level > 1 then
                            errorLog('Sound level must be a number greater than 0 and less then 1.0 percent.')
                            TriggerEvent('chat:addMessage', {
                                args = { 'Sonoran Bodycam', 'Sound level must be a number greater than 0 and less then 1.0 percent.' }
                            })
                            return
                        end
                        soundLevel = tonumber(level)
                        TriggerEvent('chat:addMessage',
                            { args = { 'Sonoran Bodycam', ('Sound level set to %s'):format(soundLevel) } })
                    else
                        TriggerEvent('chat:addMessage', {
                            args = { 'Sonoran Bodycam', ('Current sound level is %s'):format((soundLevel)) }
                        })
                    end
                end)
                RegisterNetEvent('SonoranCAD::bodycam::ToggleAnimation', function()
                    if doAnimation then
                        doAnimation = false
                    else
                        doAnimation = true
                    end
                    TriggerEvent('chat:addMessage',
                        { args = { 'Sonoran Bodycam', ('Animations set to %s'):format(doAnimation) } })
                end)
                RegisterNetEvent('SonoranCAD::bodycam::ToggleOverlay', function()
                    if showOverlay then
                        showOverlay = false
                    else
                        showOverlay = true
                    end
                    if bodyCamOn then
                        SendNUIMessage({
                            type = 'toggleGif',
                            location = pluginConfig.overlayLocation
                        })
                    end
                    TriggerEvent('chat:addMessage',
                        { args = { 'Sonoran Bodycam', ('Overlay set to %s'):format(showOverlay) } })
                end)
            end)
        end
    end)
end)
