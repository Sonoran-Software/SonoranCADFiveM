--[[
    Sonoran CAD Plugins

    Plugin Name: caddisplay
    Description: CAD display placement (client)
]]

CreateThread(function()
    Config.LoadPlugin("caddisplay", function(pluginConfig)
        if pluginConfig.enabled then
            local displayModel = "prop_laptop_jimmy"
            local displayTexture = "prop_jimmy_screen"
            local displayModelHash = GetHashKey(displayModel)
        local builtinScreens = {}
        local builtinScreensByHash = {}
        local allowlistHashes = {}
        for _, v in pairs(pluginConfig.allowlistedCars or {}) do
            if v and v ~= "" then
                allowlistHashes[GetHashKey(v)] = true
            end
        end
        for _, entry in ipairs(pluginConfig.builtinScreens or {}) do
            local veh = entry.vehicle and string.upper(entry.vehicle) or nil
            local screenTexture = entry.screenTexture
            if veh and veh ~= "" and screenTexture then
                local vehHash = GetHashKey(veh)
                local texW = entry.textureWidth
                local texH = entry.textureHeight
                if type(texW) == "string" and not tonumber(texW) then
                    local w, h = texW:match("(%d+)%s*[xX]%s*(%d+)")
                    if w and h then
                        texW = tonumber(w)
                        texH = tonumber(h)
                    end
                elseif type(texW) == "table" then
                    texH = texH or texW.y or texW.height or texW[2]
                    texW = texW.x or texW.width or texW[1]
                end
                if type(texH) == "string" and not tonumber(texH) then
                    local _, h = texH:match("(%d+)%s*[xX]%s*(%d+)")
                    texH = h or texH
                elseif type(texH) == "table" then
                    texH = texH.y or texH.height or texH[2] or texH[1]
                end
                texW = tonumber(texW) or 512
                texH = tonumber(texH) or 256
                local sx = texW / 512.0
                local sy = texH / 256.0
                local cfg = {texture = screenTexture, scale = {x = sx, y = sy, z = 1.0}, model = veh, modelHash = vehHash}
                builtinScreens[veh] = cfg
                builtinScreensByHash[vehHash] = cfg
            end
        end
            local placementDb = {}
            local spawnedDisplays = {}
            local vehiclesWithDisplays = {}
            local miscDisplayIndex = 1
            local spawnedDisplayIndex = 1
            local displayMoveSpeed = 0.01
            local displayPosition = {x = 0.0, y = 0.0, z = 0.0}
            local displayRotation = {x = 0.0, y = 0.0, z = 0.0}
            local latestSpawnedDisplay = nil
            local attachedDisplay = false
            local displayScale = nil
            local isAdmin = false
            local screenDui = nil
            local duiObjs = {}
            local displayOwners = {}
            local activeRequests = {}
            local incomingRequest = nil
            local claimedOnce = {}

            local interactRange = pluginConfig.interactRange or 1.5
            local interactControl = pluginConfig.interactControl or 47
            local interactKeybind = pluginConfig.interactKey or "G"
            local screenshotInterval = 5000
            local acceptKeybind = pluginConfig.requestAcceptKey or "Y"
            local denyKeybind = pluginConfig.requestDenyKey or "L"

            local function getVehNetIdOrNil(veh)
                if veh == nil or veh == 0 then
                    return nil
                end
                local net = VehToNet(veh)
                if net == 0 then
                    return nil
                end
                return net
            end

            local function notify(message)
                if pluginConfig.general.notificationType == "native" then
                    SetNotificationTextEntry("STRING")
                    AddTextComponentString(message)
                    DrawNotification(false, false)
                elseif pluginConfig.general.notificationType == "okokNotify" then
                    pcall(function()
                        exports["okokNotify"]:Alert("CAD Display", message, 5000, "info")
                    end)
                elseif pluginConfig.general.notificationType == "pNotify" then
                    pcall(function()
                        exports.pNotify:SendNotification({text = message, type = "info"})
                    end)
                end
            end

            local function ensureModel(model)
                local hash = type(model) == "number" and model or GetHashKey(model)
                if not HasModelLoaded(hash) then
                    RequestModel(hash)
                    while not HasModelLoaded(hash) do
                        Wait(10)
                    end
                end
                return hash
            end

            local function getVehNetId(veh)
                if veh == nil or veh == 0 then
                    return nil
                end
                local vehNet = VehToNet(veh)
                if vehNet == 0 then
                    return nil
                end
                return vehNet
            end

            local function isPlayerInVeh(veh)
                for i = -1, GetVehicleMaxNumberOfPassengers(veh) + 1, 1 do
                    local ped = GetPedInVehicleSeat(veh, i)
                    if DoesEntityExist(ped) and IsPedAPlayer(ped) then
                        return true
                    end
                end
                return false
            end

            local function isVehicleBlocked(veh)
                local modelHash = GetEntityModel(veh)
                if builtinScreensByHash and builtinScreensByHash[modelHash] then
                    return false
                end
                if allowlistHashes and allowlistHashes[modelHash] then
                    if pluginConfig.general.useAllowlistAsBlacklist then
                        return true
                    else
                        return false
                    end
                end
                return not pluginConfig.general.useAllowlistAsBlacklist
            end

            local function hasTrackedVehicle(tab, veh)
                local targetVehNet = getVehNetId(veh)
                for _, value in ipairs(tab) do
                    if (targetVehNet ~= nil and value.vehNet == targetVehNet) or value.veh == veh then
                        return true
                    end
                end
                return false
            end

            local function getSpawnedDisplayIndex(displayProp)
                for idx, obj in ipairs(spawnedDisplays) do
                    if obj == displayProp then
                        return idx
                    end
                end
                return nil
            end

            local function findVehicleRecord(veh)
                local vehNet = getVehNetIdOrNil(veh)
                if vehNet == nil then
                    return nil
                end
                for _, car in ipairs(vehiclesWithDisplays) do
                    if car.vehNet == vehNet or car.veh == veh then
                        return car
                    end
                end
                return nil
            end

        local function hasAnyOccupant(veh)
            if not DoesEntityExist(veh) then
                return false
            end
            local maxSeats = GetVehicleMaxNumberOfPassengers(veh)
            for seat = -1, maxSeats do
                local ped = GetPedInVehicleSeat(veh, seat)
                if ped ~= 0 and DoesEntityExist(ped) then
                    return true
                end
            end
            return false
        end

        local function getSeatIndexForPed(veh, ped)
            if veh == 0 or not DoesEntityExist(veh) then
                return nil
            end
            local maxSeats = GetVehicleMaxNumberOfPassengers(veh)
            for seat = -1, maxSeats do
                if GetPedInVehicleSeat(veh, seat) == ped then
                    return seat
                end
            end
            return nil
        end

            local function getBuiltinScreenConfig(veh)
                if not DoesEntityExist(veh) then
                    return nil
                end
                local modelHash = GetEntityModel(veh)
                return builtinScreensByHash[modelHash] or nil
            end

            local function applyConfiguredScale(obj, scaleCfg)
                if not scaleCfg or not DoesEntityExist(obj) then
                    return
                end
                local sx = tonumber(scaleCfg.x) or 1.0
                local sy = tonumber(scaleCfg.y) or 1.0
                local sz = tonumber(scaleCfg.z) or 1.0
                local right, forward, up, at = GetEntityMatrix(obj)
                SetEntityMatrix(obj,
                    right.x * sx, right.y * sx, right.z * sx,
                    forward.x * sy, forward.y * sy, forward.z * sy,
                    up.x * sz, up.y * sz, up.z * sz,
                    at.x, at.y, at.z)
            end

            local function drawWorldPrompt(pos, text)
                SetDrawOrigin(pos.x, pos.y, pos.z, 0)
                SetTextScale(0.35, 0.35)
                SetTextFont(4)
                SetTextProportional(1)
                SetTextColour(255, 255, 255, 215)
                SetTextCentre(true)
                BeginTextCommandDisplayText("STRING")
                AddTextComponentSubstringPlayerName(text)
                EndTextCommandDisplayText(0.0, 0.0)
                ClearDrawOrigin()
            end

            local function trackDisplayForVehicle(veh, displayProp)
                local vehNet = getVehNetId(veh)
                local index = getSpawnedDisplayIndex(displayProp)
                if not index then
                    table.insert(spawnedDisplays, displayProp)
                    index = #spawnedDisplays
                end
                table.insert(vehiclesWithDisplays, {index = index, prop = displayProp, veh = veh, vehNet = vehNet})
            end

            local function findExistingDisplayForVehicle(veh)
                if not DoesEntityExist(veh) then
                    return nil
                end
                local builtinCfg = getBuiltinScreenConfig(veh)
                if builtinCfg then
                    return veh
                end
                local vehNet = getVehNetId(veh)
                if vehNet ~= nil then
                    for _, car in ipairs(vehiclesWithDisplays) do
                        if car.vehNet == vehNet then
                            return car.prop
                        end
                    end
                end
                for _, obj in ipairs(GetGamePool("CObject")) do
                    if DoesEntityExist(obj) and GetEntityModel(obj) == displayModelHash then
                        if IsEntityAttachedToEntity(obj, veh) or GetEntityAttachedTo(obj) == veh then
                            return obj
                        end
                    end
                end
                return nil
            end

            local function getPlacementForVehicle(veh)
                local vehModel = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
                for _, entry in ipairs(placementDb) do
                    if string.upper(entry.Vehicle) == string.upper(vehModel) then
                        return entry
                    end
                end
                return nil
            end

            local function ensureDui()
                if screenDui ~= nil then
                    return
                end
                local htmlPath = ("nui://%s/submodules/caddisplay/html/display.html"):format(GetCurrentResourceName())
                screenDui = CreateDui(htmlPath, 512, 256)
                local duiHandle = GetDuiHandle(screenDui)
                local txd = CreateRuntimeTxd("caddisplay_screen")
                CreateRuntimeTextureFromDuiHandle(txd, "caddisplay_screen_tex", duiHandle)
                AddReplaceTexture(displayModel, displayTexture, "caddisplay_screen", "caddisplay_screen_tex")
                for _, cfg in pairs(builtinScreens) do
                    AddReplaceTexture(cfg.model or displayModel, cfg.texture, "caddisplay_screen", "caddisplay_screen_tex")
                end
                table.insert(duiObjs, screenDui)
            end

            local function destroyDuiObjects()
                for _, duiObj in ipairs(duiObjs) do
                    if IsDuiAvailable(duiObj) then
                        DestroyDui(duiObj)
                    end
                end
                duiObjs = {}
                screenDui = nil
            end

            local function updateDui(payload)
                if screenDui and IsDuiAvailable(screenDui) then
                    SendDuiMessage(screenDui, json.encode(payload or {}))
                end
            end

            local function spawnDisplay(veh)
                ensureModel(displayModelHash)
                local player = PlayerPedId()
                local x, y, z = table.unpack(GetEntityCoords(player, true))
                local obj = CreateObject(displayModelHash, x, y, z, true, true, false)
                latestSpawnedDisplay = obj
                trackDisplayForVehicle(veh or GetVehiclePedIsIn(player, false), obj)
                ensureDui()
                return obj
            end

            local function attachDisplayToVehicle(obj, veh, placement)
                if not DoesEntityExist(obj) or not DoesEntityExist(veh) then
                    return
                end
                local bone = placement.Bone or -1
                AttachEntityToEntity(obj, veh, bone, placement.Position.x, placement.Position.y, placement.Position.z,
                                    placement.Rotation.pitch, placement.Rotation.roll, placement.Rotation.yaw, false, false,
                                    true, false, 0, true)
                FreezeEntityPosition(obj, false)
            end

            local function marker(pos)
                DrawMarker(0, pos.x, pos.y, pos.z + 2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.2, 255, 255, 0, 255, true,
                        false, 0, false, nil, nil, false)
            end

            local function setIndex(veh, index)
                local vehNet = getVehNetId(veh)
                for _, car in ipairs(vehiclesWithDisplays) do
                    if (vehNet ~= nil and car.vehNet == vehNet) or car.veh == veh then
                        car.index = index
                        car.veh = veh
                    end
                end
            end

            local function removeDisplayAtIndex(index)
                if not index then
                    return
                end
                local obj = spawnedDisplays[index]
                if obj and DoesEntityExist(obj) then
                    DeleteObject(obj)
                end
                table.remove(spawnedDisplays, index)
                for _, car in ipairs(vehiclesWithDisplays) do
                    if car.index == index then
                        car.prop = nil
                    elseif car.index and car.index > index then
                        car.index = car.index - 1
                    end
                end
                for i = #vehiclesWithDisplays, 1, -1 do
                    if vehiclesWithDisplays[i].prop == nil then
                        table.remove(vehiclesWithDisplays, i)
                    end
                end
                if spawnedDisplayIndex > #spawnedDisplays then
                    spawnedDisplayIndex = #spawnedDisplays > 0 and #spawnedDisplays or 1
                end
            end

            local function refreshOffsetsForCurrentSelection()
                local veh = GetVehiclePedIsIn(PlayerPedId(), false)
                local prop = spawnedDisplays[spawnedDisplayIndex]
                if veh ~= 0 and DoesEntityExist(prop) then
                    local propCoords = GetEntityCoords(prop)
                    local vehCoords = GetEntityCoords(veh)
                    local offset = GetOffsetFromEntityGivenWorldCoords(veh, propCoords.x, propCoords.y, propCoords.z)
                    displayPosition = {x = offset.x, y = offset.y, z = offset.z}
                    local propRot = GetEntityRotation(prop, 2)
                    local vehRot = GetEntityRotation(veh, 2)
                    displayRotation = {
                        x = propRot.x - vehRot.x,
                        y = propRot.y - vehRot.y,
                        z = propRot.z - vehRot.z
                    }
                end
            end

            local function spawningCadDisplay()
                local modelNames = {pluginConfig.lang.objectName}
                if WarMenu.ComboBox(pluginConfig.lang.modelComboBox, modelNames, miscDisplayIndex, miscDisplayIndex,
                                    function(current) miscDisplayIndex = current end) then
                    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
                    if veh == 0 then
                        notify(pluginConfig.lang.notInVeh)
                        return
                    end
                    local placement = getPlacementForVehicle(veh)
                    if placement then
                        notify(pluginConfig.lang.vehAlreadyDisplayNoti)
                        return
                    end
                    spawnDisplay(veh)
                    WarMenu.OpenMenu("caddisplay_attach_menu")
                end
            end

            local function attachingCadDisplay()
                local attachType = pluginConfig.lang.vehicleBone
                if WarMenu.ComboBox(pluginConfig.lang.object, spawnedDisplays, spawnedDisplayIndex, spawnedDisplayIndex,
                                    function(current)
                    spawnedDisplayIndex = current
                    local object = spawnedDisplays[current]
                    if DoesEntityExist(object) then
                        marker(GetEntityCoords(object))
                    end
                end) then
                    attachType = pluginConfig.lang.vehicleBone
                elseif WarMenu.Button(pluginConfig.lang.attachButton) then
                    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
                    if veh ~= 0 and spawnedDisplays[spawnedDisplayIndex] ~= nil then
                        refreshOffsetsForCurrentSelection()
                        AttachEntityToEntity(spawnedDisplays[spawnedDisplayIndex], veh,
                                            GetEntityBoneIndexByName(veh, "chassis"), displayPosition.x, displayPosition.y,
                                            displayPosition.z, displayRotation.x, displayRotation.y, displayRotation.z,
                                            false, false, true, false, 0, true)
                        attachedDisplay = true
                    end
                elseif WarMenu.Button(pluginConfig.lang.detachButton) then
                    if spawnedDisplays[spawnedDisplayIndex] ~= nil then
                        DetachEntity(spawnedDisplays[spawnedDisplayIndex], false, false)
                        attachedDisplay = false
                    end
                end

                if isAdmin then
                    if WarMenu.Button(pluginConfig.lang.confirmPlacementButton) then
                        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
                        if veh ~= 0 and spawnedDisplays[spawnedDisplayIndex] ~= nil then
                            local bone = GetEntityBoneIndexByName(veh, "chassis")
                            local vehicle = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
                            local data = {
                                position = displayPosition,
                                rotation = displayRotation,
                                bone = bone,
                                vehicle = vehicle
                            }
                            TriggerServerEvent("SonoranCAD::caddisplay::SavePlacement", data)
                            WarMenu.CloseMenu()
                        end
                    end
                end

                if attachedDisplay and spawnedDisplays[spawnedDisplayIndex] ~= nil then
                    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
                    if IsControlPressed(0, 118) and GetLastInputMethod(0) then
                        displayRotation.x = displayRotation.x + displayMoveSpeed
                    elseif IsControlPressed(0, 117) and GetLastInputMethod(0) then
                        displayRotation.x = displayRotation.x - displayMoveSpeed
                    elseif IsControlPressed(0, 121) and GetLastInputMethod(0) then
                        displayRotation.y = displayRotation.y + displayMoveSpeed
                    elseif IsControlPressed(0, 178) and GetLastInputMethod(0) then
                        displayRotation.y = displayRotation.y - displayMoveSpeed
                    elseif IsControlPressed(0, 207) and GetLastInputMethod(0) then
                        displayRotation.z = displayRotation.z + displayMoveSpeed
                    elseif IsControlPressed(0, 208) and GetLastInputMethod(0) then
                        displayRotation.z = displayRotation.z - displayMoveSpeed
                    elseif IsControlPressed(0, 108) and GetLastInputMethod(0) then
                        displayPosition.x = displayPosition.x + displayMoveSpeed
                    elseif IsControlPressed(0, 107) and GetLastInputMethod(0) then
                        displayPosition.x = displayPosition.x - displayMoveSpeed
                    elseif IsControlPressed(0, 112) and GetLastInputMethod(0) then
                        displayPosition.y = displayPosition.y + displayMoveSpeed
                    elseif IsControlPressed(0, 111) and GetLastInputMethod(0) then
                        displayPosition.y = displayPosition.y - displayMoveSpeed
                    elseif IsControlPressed(0, 313) and GetLastInputMethod(0) then
                        displayPosition.z = displayPosition.z + displayMoveSpeed
                    elseif IsControlPressed(0, 312) and GetLastInputMethod(0) then
                        displayPosition.z = displayPosition.z - displayMoveSpeed
                    elseif IsControlJustReleased(0, 21) and GetLastInputMethod(0) then
                        if displayMoveSpeed < 2.0 then
                            displayMoveSpeed = displayMoveSpeed + 0.001
                        else
                            notify(pluginConfig.lang.cannotGoFaster)
                        end
                    elseif IsControlJustReleased(0, 132) and GetLastInputMethod(0) then
                        if displayMoveSpeed > 0.001 then
                            displayMoveSpeed = displayMoveSpeed - 0.001
                        else
                            notify(pluginConfig.lang.cannotGoSlower)
                        end
                    end

                    AttachEntityToEntity(spawnedDisplays[spawnedDisplayIndex], veh,
                                        GetEntityBoneIndexByName(veh, "chassis"), displayPosition.x, displayPosition.y,
                                        displayPosition.z, displayRotation.x, displayRotation.y, displayRotation.z, false,
                                        false, true, false, 0, true)

                    if displayScale and HasScaleformMovieLoaded(displayScale) then
                        BeginScaleformMovieMethod(displayScale, "CLEAR_ALL")
                        EndScaleformMovieMethod()

                        BeginScaleformMovieMethod(displayScale, "SET_DATA_SLOT")
                        ScaleformMovieMethodAddParamInt(0)
                        PushScaleformMovieMethodParameterString(GetControlInstructionalButton(0, 108))
                        PushScaleformMovieMethodParameterString(GetControlInstructionalButton(0, 107))
                        PushScaleformMovieMethodParameterString("Move X")
                        EndScaleformMovieMethod()

                        BeginScaleformMovieMethod(displayScale, "SET_DATA_SLOT")
                        ScaleformMovieMethodAddParamInt(1)
                        PushScaleformMovieMethodParameterString(GetControlInstructionalButton(0, 112))
                        PushScaleformMovieMethodParameterString(GetControlInstructionalButton(0, 111))
                        PushScaleformMovieMethodParameterString("Move Y")
                        EndScaleformMovieMethod()

                        BeginScaleformMovieMethod(displayScale, "SET_DATA_SLOT")
                        ScaleformMovieMethodAddParamInt(6)
                        PushScaleformMovieMethodParameterString(GetControlInstructionalButton(0, 21))
                        PushScaleformMovieMethodParameterString(GetControlInstructionalButton(0, 36))
                        PushScaleformMovieMethodParameterString("Change Speed")
                        EndScaleformMovieMethod()

                        BeginScaleformMovieMethod(displayScale, "SET_DATA_SLOT")
                        ScaleformMovieMethodAddParamInt(2)
                        PushScaleformMovieMethodParameterString(GetControlInstructionalButton(0, 313))
                        PushScaleformMovieMethodParameterString(GetControlInstructionalButton(0, 312))
                        PushScaleformMovieMethodParameterString("Move Z")
                        EndScaleformMovieMethod()

                        BeginScaleformMovieMethod(displayScale, "SET_DATA_SLOT")
                        ScaleformMovieMethodAddParamInt(3)
                        PushScaleformMovieMethodParameterString(GetControlInstructionalButton(0, 118))
                        PushScaleformMovieMethodParameterString(GetControlInstructionalButton(0, 117))
                        PushScaleformMovieMethodParameterString("Rotate X")
                        EndScaleformMovieMethod()

                        BeginScaleformMovieMethod(displayScale, "SET_DATA_SLOT")
                        ScaleformMovieMethodAddParamInt(4)
                        PushScaleformMovieMethodParameterString(GetControlInstructionalButton(0, 121))
                        PushScaleformMovieMethodParameterString(GetControlInstructionalButton(0, 178))
                        PushScaleformMovieMethodParameterString("Rotate Y")
                        EndScaleformMovieMethod()

                        BeginScaleformMovieMethod(displayScale, "SET_DATA_SLOT")
                        ScaleformMovieMethodAddParamInt(5)
                        PushScaleformMovieMethodParameterString(GetControlInstructionalButton(0, 207))
                        PushScaleformMovieMethodParameterString(GetControlInstructionalButton(0, 208))
                        PushScaleformMovieMethodParameterString("Rotate Z")
                        EndScaleformMovieMethod()

                        BeginScaleformMovieMethod(displayScale, "DRAW_INSTRUCTIONAL_BUTTONS")
                        ScaleformMovieMethodAddParamInt(0)
                        EndScaleformMovieMethod()
                        DrawScaleformMovieFullscreen(displayScale, 255, 255, 255, 255, 0)
                    end
                end
            end

            CreateThread(function()
                while true do
                    Wait(5000)
                    for idx = #vehiclesWithDisplays, 1, -1 do
                        local car = vehiclesWithDisplays[idx]
                        local vehEntity = car.veh
                        if (vehEntity == nil or not DoesEntityExist(vehEntity)) and car.vehNet ~= nil then
                            vehEntity = NetToVeh(car.vehNet)
                            car.veh = vehEntity
                        end
                        if vehEntity == nil or vehEntity == 0 or not DoesEntityExist(vehEntity) then
                            local displayIndex = getSpawnedDisplayIndex(car.prop) or car.index
                            if displayIndex ~= nil then
                                removeDisplayAtIndex(displayIndex)
                            else
                                table.remove(vehiclesWithDisplays, idx)
                            end
                        end
                    end
                end
            end)

            CreateThread(function()
                while true do
                    Wait(2500)
                    local vehPedIn = GetVehiclePedIsIn(PlayerPedId(), false)
                    if vehPedIn ~= 0 and isPlayerInVeh(vehPedIn) then
                        local builtinCfg = getBuiltinScreenConfig(vehPedIn)
                        if builtinCfg and not isVehicleBlocked(vehPedIn) then
                            if not hasTrackedVehicle(vehiclesWithDisplays, vehPedIn) then
                                trackDisplayForVehicle(vehPedIn, vehPedIn)
                            end
                            ensureDui()
                        else
                            local placement = getPlacementForVehicle(vehPedIn)
                            if placement and not isVehicleBlocked(vehPedIn) then
                                if not hasTrackedVehicle(vehiclesWithDisplays, vehPedIn) then
                                    local existingDisplay = findExistingDisplayForVehicle(vehPedIn)
                                    if existingDisplay ~= nil then
                                        trackDisplayForVehicle(vehPedIn, existingDisplay)
                                    else
                                        local obj = spawnDisplay(vehPedIn)
                                        attachDisplayToVehicle(obj, vehPedIn, placement)
                                    end
                                end
                                ensureDui()
                            end
                        end
                    end
                end
            end)

            CreateThread(function()
                displayScale = RequestScaleformMovie("INSTRUCTIONAL_BUTTONS")
                while not HasScaleformMovieLoaded(displayScale) do
                    Wait(0)
                end
            end)

            while WarMenu == nil do
                Wait(50)
            end

            CreateThread(function()
                WarMenu.CreateMenu("caddisplay_menu", pluginConfig.lang.menuHeader)
                WarMenu.SetSubTitle("caddisplay_menu", pluginConfig.lang.creditsPanel .. " Sonoran Software")
                WarMenu.SetMenuTitleBackgroundSprite('caddisplay_menu', 'cad_menu_header', 'option_2')
                WarMenu.CreateSubMenu("caddisplay_spawn_menu", "caddisplay_menu", pluginConfig.lang.spawningSubMenu)
                WarMenu.CreateSubMenu("caddisplay_attach_menu", "caddisplay_menu", pluginConfig.lang.attachingSubMenu)
                WarMenu.CreateSubMenu("caddisplay_delete_menu", "caddisplay_menu", pluginConfig.lang.deletionSubMenu)
                while true do
                    if WarMenu.IsMenuOpened("caddisplay_menu") then
                        if WarMenu.MenuButton(pluginConfig.lang.spawnMenuButton, "caddisplay_spawn_menu") then
                        end
                        if WarMenu.MenuButton(pluginConfig.lang.attachMenuButton, "caddisplay_attach_menu") then
                        end
                        if WarMenu.MenuButton(pluginConfig.lang.deleteMenuButton, "caddisplay_delete_menu") then
                        end
                        WarMenu.Display()
                    elseif WarMenu.IsMenuOpened("caddisplay_spawn_menu") then
                        spawningCadDisplay()
                        WarMenu.Display()
                    elseif WarMenu.IsMenuOpened("caddisplay_attach_menu") then
                        attachingCadDisplay()
                        WarMenu.Display()
                    elseif WarMenu.IsMenuOpened("caddisplay_delete_menu") then
                        local currentVeh = GetVehiclePedIsIn(PlayerPedId(), false)
                        if currentVeh ~= 0 then
                            local model = GetDisplayNameFromVehicleModel(GetEntityModel(currentVeh))
                            if WarMenu.Button(pluginConfig.lang.deletionConfirmationButton) then
                                if spawnedDisplays[spawnedDisplayIndex] ~= nil then
                                    SetEntityAsMissionEntity(spawnedDisplays[spawnedDisplayIndex])
                                    removeDisplayAtIndex(spawnedDisplayIndex)
                                end
                                TriggerServerEvent("SonoranCAD::caddisplay::DeletePlacement", model)
                                WarMenu.CloseMenu()
                            end
                            if WarMenu.Button(pluginConfig.lang.deletionCancelButton) then
                                notify(pluginConfig.lang.deletionCancelled)
                            end
                        else
                            notify(pluginConfig.lang.notInVeh)
                        end
                        WarMenu.Display()
                    end
                    Wait(0)
                end
            end)

            RegisterNetEvent("SonoranCAD::caddisplay::SyncPlacements", function(serverDb)
                placementDb = serverDb or {}
                for idx = #vehiclesWithDisplays, 1, -1 do
                    local car = vehiclesWithDisplays[idx]
                    local veh = car.veh
                    local keep = false
                    if veh ~= nil and DoesEntityExist(veh) then
                        if getBuiltinScreenConfig(veh) then
                            keep = true
                        else
                            local model = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
                            for _, entry in ipairs(placementDb) do
                                if string.upper(entry.Vehicle) == string.upper(model) then
                                    keep = true
                                    break
                                end
                            end
                        end
                    end
                    if not keep then
                        local dispIndex = getSpawnedDisplayIndex(car.prop) or car.index
                        if dispIndex ~= nil then
                            removeDisplayAtIndex(dispIndex)
                        else
                            table.remove(vehiclesWithDisplays, idx)
                        end
                    end
                end
            end)

        RegisterNetEvent("SonoranCAD::caddisplay::SyncOwners", function(serverOwners)
            displayOwners = serverOwners or {}
            local me = GetPlayerServerId(PlayerId())
            for vehNet, owner in pairs(displayOwners) do
                if owner ~= nil then
                    local key = tostring(vehNet)
                    claimedOnce[key] = true
                    if owner == me then
                        notify("You now have control of the CAD display.")
                    end
                end
            end
        end)

            RegisterNetEvent("SonoranCAD::Tablet::CadScreenshotResponse", function(requestId, image)
                local meta = activeRequests[requestId]
                if not meta then
                    return
                end
                activeRequests[requestId] = nil
                if not image or image == "" then
                    return
                end
                updateDui({type = "cad_image", image = image})
                if meta.vehNet ~= nil then
                    TriggerServerEvent("SonoranCAD::caddisplay::BroadcastCadScreenshot", meta.vehNet, image)
                end
            end)

            RegisterNetEvent("SonoranCAD::caddisplay::ControlRequest", function(data)
                incomingRequest = {
                    requester = data.requester,
                    requesterName = data.requesterName,
                    vehNet = data.vehNet,
                    expires = GetGameTimer() + 10000
                }
                notify(("Control request from %s - Press %s to accept, %s to deny"):format(
                    incomingRequest.requesterName or "someone", acceptKeybind, denyKeybind))
            end)

            RegisterNetEvent("SonoranCAD::caddisplay::ControlRequestExpired", function()
                incomingRequest = nil
            end)

            RegisterNetEvent("SonoranCAD::caddisplay::OpenMenu", function(adminFlag)
                isAdmin = adminFlag or false
                local veh = GetVehiclePedIsIn(PlayerPedId(), false)
                if veh ~= 0 and not isVehicleBlocked(veh) then
                    WarMenu.OpenMenu("caddisplay_menu")
                else
                    notify(pluginConfig.lang.vehNotCompatible)
                end
            end)

            RegisterNetEvent("SonoranCAD::caddisplay::UpdateDui", function(payload)
                ensureDui()
                updateDui(payload)
            end)

            AddEventHandler("onResourceStop", function(resource)
                if resource == GetCurrentResourceName() then
                    while #spawnedDisplays > 0 do
                        removeDisplayAtIndex(1)
                    end
                    destroyDuiObjects()
                end
            end)

            TriggerServerEvent("SonoranCAD::caddisplay::RequestPlacements")
            TriggerEvent("chat:addSuggestion", "/" .. pluginConfig.commands.cadDisplayMenu,
                "Sonoran CAD Display: " .. pluginConfig.lang.addNewDisplayHelp)

            RegisterCommand("SonoranCAD::caddisplay::Interact", function()
                local ped = PlayerPedId()
                local veh = GetVehiclePedIsIn(ped, false)
                if veh == 0 then
                    notify(pluginConfig.lang.notInVeh)
                    return
                end

                local vehicleRecord = findVehicleRecord(veh)
                if not vehicleRecord or not vehicleRecord.prop or not DoesEntityExist(vehicleRecord.prop) then
                    notify("No CAD display found in this vehicle.")
                    return
                end

                local dist = #(GetEntityCoords(ped) - GetEntityCoords(vehicleRecord.prop))
                if dist > interactRange then
                    notify("Move closer to the CAD display to interact.")
                    return
                end

                local vehNet = getVehNetIdOrNil(veh)
                if vehNet == nil then
                    notify("Unable to identify this vehicle.")
                    return
                end

                local seat = getSeatIndexForPed(veh, ped)
                TriggerServerEvent("SonoranCAD::caddisplay::ClaimDisplay", vehNet, seat)
            end, false)

            RegisterKeyMapping("SonoranCAD::caddisplay::Interact", "Interact with CAD Display", "keyboard", interactKeybind)

            RegisterCommand("SonoranCAD::caddisplay::AcceptRequest", function()
                if not incomingRequest then
                    return
                end
                TriggerServerEvent("SonoranCAD::caddisplay::RespondToRequest", incomingRequest.vehNet,
                    incomingRequest.requester, true)
                incomingRequest = nil
            end, false)
            RegisterKeyMapping("SonoranCAD::caddisplay::AcceptRequest", "Accept CAD control request", "keyboard", acceptKeybind)

            RegisterCommand("SonoranCAD::caddisplay::DenyRequest", function()
                if not incomingRequest then
                    return
                end
                TriggerServerEvent("SonoranCAD::caddisplay::RespondToRequest", incomingRequest.vehNet,
                    incomingRequest.requester, false)
                incomingRequest = nil
            end, false)
            RegisterKeyMapping("SonoranCAD::caddisplay::DenyRequest", "Deny CAD control request", "keyboard", denyKeybind)

            -- Poll for CAD screenshots when the owner is seated in the vehicle and near the display
            CreateThread(function()
                while true do
                    Wait(1000)
                    if incomingRequest and incomingRequest.expires and GetGameTimer() > incomingRequest.expires then
                        incomingRequest = nil
                    end
                    local now = GetGameTimer()
                    local ped = PlayerPedId()
                    local localServerId = GetPlayerServerId(PlayerId())

                    for _, car in ipairs(vehiclesWithDisplays) do
                        local veh = car.veh
                        if (veh == nil or veh == 0 or not DoesEntityExist(veh)) and car.vehNet ~= nil then
                            veh = NetToVeh(car.vehNet)
                            car.veh = veh
                        end

                        if veh ~= 0 and DoesEntityExist(veh) then
                            local vehNet = getVehNetIdOrNil(veh)
                            local ownerId = vehNet and displayOwners[tostring(vehNet)] or nil
                            local prop = car.prop
                            if prop ~= nil and DoesEntityExist(prop) and ownerId == nil and hasAnyOccupant(veh) then
                                local distPrompt = #(GetEntityCoords(ped) - GetEntityCoords(prop))
                                local promptKey = tostring(vehNet or prop)
                                if distPrompt <= interactRange + 0.5 and not claimedOnce[promptKey] then
                                    drawWorldPrompt(GetEntityCoords(prop) + vector3(0.0, 0.0, 0.3),
                                        ("Press %s to interact"):format(interactKeybind))
                                end
                            end

                            if ownerId ~= nil and ownerId == localServerId then
                                if prop ~= nil and DoesEntityExist(prop) then
                                    if (car._nextReq or 0) <= now then
                                        local reqId = ("caddisplay-%s-%d"):format(ownerId, now)
                                        activeRequests[reqId] = {vehNet = vehNet}
                                        TriggerEvent("SonoranCAD::Tablet::RequestCadScreenshot", reqId)
                                        car._nextReq = now + screenshotInterval
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        end
    end)
end)

