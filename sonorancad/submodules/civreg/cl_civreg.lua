CreateThread(function()
    Config.LoadPlugin("civreg", function(pluginConfig)
        if not pluginConfig.enabled then
            return
        end

        local uiOpen = false

        local function setUiOpen(open)
            uiOpen = open == true
            SetNuiFocus(uiOpen, uiOpen)
            SetNuiFocusKeepInput(false)
        end

        local function closeUi()
            setUiOpen(false)
            SendNUIMessage({
                civreg = true,
                action = "close"
            })
        end

        RegisterCommand(pluginConfig.commandName or "civreg", function()
            if uiOpen then
                return
            end
            TriggerServerEvent("SonoranCAD::civreg::RequestForm")
        end)

        TriggerEvent("chat:addSuggestion", "/" .. (pluginConfig.commandName or "civreg"),
            pluginConfig.language.helpMsg)
        RegisterPlayerCommandHelp("civreg", pluginConfig.commandName or "civreg",
            pluginConfig.language.helpMsg)

        local frameworkConfig = Config.GetPluginConfig("frameworksupport") or {}
        local qbStarted = GetResourceState("qb-core") == "started"
        local esxStarted = GetResourceState("es_extended") == "started"
        local useQBCore = qbStarted and (not esxStarted or frameworkConfig.usingQBCore ~= false)
        local frameworkSelectionGeneration = 0
        local FRAMEWORK_SPAWN_TIMEOUT_MS = 30 * 1000
        local FRAMEWORK_CAPTURE_SETTLE_MS = 3 * 1000
        local FRAMEWORK_UNCHANGED_APPEARANCE_GRACE_MS = 15 * 1000
        local FRAMEWORK_READY_POLL_MS = 250
        local qbAppearanceReadyAt = nil

        local function getQBCorePlayerData()
            local loaded, playerData = pcall(function()
                local qbCore = exports["qb-core"]:GetCoreObject()
                return qbCore and qbCore.Functions and qbCore.Functions.GetPlayerData()
            end)
            if loaded and type(playerData) == "table" then
                return playerData
            end
            return nil
        end

        local function getPedAppearanceFingerprint(ped)
            local parts = { tostring(ped), tostring(GetEntityModel(ped)) }
            for component = 0, 11 do
                parts[#parts + 1] = table.concat({
                    GetPedDrawableVariation(ped, component),
                    GetPedTextureVariation(ped, component),
                    GetPedPaletteVariation(ped, component)
                }, ":")
            end
            for prop = 0, 7 do
                parts[#parts + 1] = table.concat({
                    GetPedPropIndex(ped, prop),
                    GetPedPropTextureIndex(ped, prop)
                }, ":")
            end
            for feature = 0, 19 do
                parts[#parts + 1] = string.format("%.4f", GetPedFaceFeature(ped, feature))
            end

            local shapeFirst, shapeSecond, shapeThird, skinFirst, skinSecond, skinThird,
                shapeMix, skinMix, thirdMix = Citizen.InvokeNative(0x2746BD9D88C5C5D0, ped,
                    Citizen.PointerValueIntInitialized(0), Citizen.PointerValueIntInitialized(0),
                    Citizen.PointerValueIntInitialized(0), Citizen.PointerValueIntInitialized(0),
                    Citizen.PointerValueIntInitialized(0), Citizen.PointerValueIntInitialized(0),
                    Citizen.PointerValueFloatInitialized(0), Citizen.PointerValueFloatInitialized(0),
                    Citizen.PointerValueFloatInitialized(0))
            parts[#parts + 1] = table.concat({
                shapeFirst, shapeSecond, shapeThird, skinFirst, skinSecond, skinThird,
                string.format("%.4f", shapeMix), string.format("%.4f", skinMix),
                string.format("%.4f", thirdMix or 0)
            }, ":")

            for overlay = 0, 12 do
                local success, value, colorType, firstColor, secondColor, opacity =
                    GetPedHeadOverlayData(ped, overlay)
                parts[#parts + 1] = table.concat({
                    tostring(success), value, colorType, firstColor, secondColor,
                    string.format("%.4f", opacity)
                }, ":")
            end
            parts[#parts + 1] = table.concat({
                GetPedEyeColor(ped), GetPedHairColor(ped), GetPedHairHighlightColor(ped)
            }, ":")
            parts[#parts + 1] = tostring(GetPedDecorationsState(ped))
            return table.concat(parts, "|")
        end

        local function frameworkCharacterIsFullySpawned()
            local ped = PlayerPedId()
            return NetworkIsPlayerActive(PlayerId()) and DoesEntityExist(ped) and
                IsEntityVisible(ped) and HasCollisionLoadedAroundEntity(ped) and IsScreenFadedIn()
        end

        local function captureFrameworkCharacterWhenSpawned(options)
            options = options or {}
            frameworkSelectionGeneration = frameworkSelectionGeneration + 1
            local generation = frameworkSelectionGeneration
            CreateThread(function()
                local timeoutAt = GetGameTimer() + FRAMEWORK_SPAWN_TIMEOUT_MS
                local expectedCharacterId = options.characterId
                local stableFingerprint = nil
                local stableSince = nil
                local unchangedAppearanceReadySince = nil
                local appearanceChanged = false
                while generation == frameworkSelectionGeneration and GetGameTimer() < timeoutAt do
                    local ped = PlayerPedId()
                    local characterReady = true
                    if useQBCore then
                        local playerData = getQBCorePlayerData()
                        local characterId = type(playerData) == "table" and playerData.citizenid or nil
                        characterReady = type(characterId) == "string" and characterId ~= ""
                        if characterReady and not expectedCharacterId then
                            expectedCharacterId = characterId
                        end
                        characterReady = characterReady and characterId == expectedCharacterId
                    end

                    local appearanceReady = not options.qbAppearanceReadyRequired or
                        (qbAppearanceReadyAt and qbAppearanceReadyAt >= options.startedAt)
                    local ready = characterReady and appearanceReady and frameworkCharacterIsFullySpawned()
                    local fingerprint = ready and getPedAppearanceFingerprint(ped) or nil
                    if ready and options.initialFingerprint and not options.allowUnchangedAppearance and
                        not appearanceChanged then
                        if fingerprint ~= options.initialFingerprint then
                            appearanceChanged = true
                            unchangedAppearanceReadySince = nil
                        else
                            unchangedAppearanceReadySince = unchangedAppearanceReadySince or GetGameTimer()
                            if GetGameTimer() - unchangedAppearanceReadySince <
                                FRAMEWORK_UNCHANGED_APPEARANCE_GRACE_MS then
                                ready = false
                            end
                        end
                    elseif not ready then
                        unchangedAppearanceReadySince = nil
                    end

                    if ready then
                        if fingerprint ~= stableFingerprint then
                            stableFingerprint = fingerprint
                            stableSince = GetGameTimer()
                        elseif stableSince and GetGameTimer() - stableSince >= FRAMEWORK_CAPTURE_SETTLE_MS then
                            TriggerServerEvent("SonoranCAD::civreg::FrameworkCharacterSelected")
                            return
                        end
                    else
                        stableFingerprint = nil
                        stableSince = nil
                    end
                    Wait(FRAMEWORK_READY_POLL_MS)
                end
            end)
        end

        if useQBCore then
            RegisterNetEvent("qb-clothing:client:loadPlayerClothing", function()
                qbAppearanceReadyAt = GetGameTimer()
            end)
            AddEventHandler("qb-clothing:client:onMenuClose", function()
                qbAppearanceReadyAt = GetGameTimer()
            end)

            RegisterNetEvent("QBCore:Client:OnPlayerLoaded", function()
                local startedAt = GetGameTimer()
                local playerData = getQBCorePlayerData()
                local ped = PlayerPedId()
                local qbClothingStarted = GetResourceState("qb-clothing") == "started"
                local alternateAppearanceStarted = GetResourceState("illenium-appearance") == "started" or
                    GetResourceState("fivem-appearance") == "started"
                captureFrameworkCharacterWhenSpawned({
                    startedAt = startedAt,
                    characterId = type(playerData) == "table" and playerData.citizenid or nil,
                    qbAppearanceReadyRequired = qbClothingStarted,
                    initialFingerprint = getPedAppearanceFingerprint(ped),
                    allowUnchangedAppearance = not alternateAppearanceStarted
                })
            end)
            RegisterNetEvent("QBCore:Client:OnPlayerUnload", function()
                frameworkSelectionGeneration = frameworkSelectionGeneration + 1
                qbAppearanceReadyAt = nil
            end)

            local playerData = getQBCorePlayerData()
            if type(playerData) == "table" and
                type(playerData.citizenid) == "string" and playerData.citizenid ~= "" then
                captureFrameworkCharacterWhenSpawned({
                    characterId = playerData.citizenid,
                    allowUnchangedAppearance = true
                })
            end
        elseif esxStarted then
            local selectedEsxCharacterPending = false
            RegisterNetEvent("esx:playerLoaded", function()
                selectedEsxCharacterPending = true
            end)
            AddEventHandler("esx:onPlayerSpawn", function()
                if not selectedEsxCharacterPending then
                    return
                end
                selectedEsxCharacterPending = false
                captureFrameworkCharacterWhenSpawned()
            end)

            local loaded, playerData = pcall(function()
                local esx = exports["es_extended"]:getSharedObject()
                return esx and esx.GetPlayerData and esx.GetPlayerData()
            end)
            if loaded and type(playerData) == "table" and
                type(playerData.identifier) == "string" and playerData.identifier ~= "" then
                captureFrameworkCharacterWhenSpawned()
            end
        end

        RegisterNetEvent("SonoranCAD::civreg::OpenForm", function(payload)
            if type(payload) ~= "table" then
                return
            end
            setUiOpen(true)
            SendNUIMessage({
                civreg = true,
                action = "open",
                payload = payload
            })
        end)

        RegisterNetEvent("SonoranCAD::civreg::SubmissionResult", function(payload)
            SendNUIMessage({
                civreg = true,
                action = "result",
                payload = payload or { success = false }
            })
            if payload and payload.success then
                closeUi()
            end
        end)

        local portraitCaptureActive = false
        local HIDDEN_PORTRAIT_COMPONENTS = { 1, 7 }
        local HIDDEN_PORTRAIT_PROPS = { 0, 1, 2 }

        local function captureUncoveredPortrait()
            if portraitCaptureActive then
                return { success = false, error = "Another character portrait capture is already active." }
            end

            local ped = PlayerPedId()
            if not DoesEntityExist(ped) then
                return { success = false, error = "Could not find your character for the portrait." }
            end

            portraitCaptureActive = true
            local components = {}
            local props = {}
            local ok, result = pcall(function()
                for _, component in ipairs(HIDDEN_PORTRAIT_COMPONENTS) do
                    components[component] = {
                        drawable = GetPedDrawableVariation(ped, component),
                        texture = GetPedTextureVariation(ped, component),
                        palette = GetPedPaletteVariation(ped, component)
                    }
                    SetPedComponentVariation(ped, component, 0, 0, 0)
                end
                for _, prop in ipairs(HIDDEN_PORTRAIT_PROPS) do
                    props[prop] = {
                        drawable = GetPedPropIndex(ped, prop),
                        texture = GetPedPropTextureIndex(ped, prop)
                    }
                    ClearPedProp(ped, prop)
                end

                Wait(0)
                Wait(0)
                return GetBase64(ped)
            end)

            local restored = true
            if DoesEntityExist(ped) then
                for _, component in ipairs(HIDDEN_PORTRAIT_COMPONENTS) do
                    local value = components[component]
                    if value then
                        local restoredComponent = pcall(SetPedComponentVariation, ped, component,
                            value.drawable, value.texture, value.palette)
                        restored = restored and restoredComponent
                    end
                end
                for _, prop in ipairs(HIDDEN_PORTRAIT_PROPS) do
                    local value = props[prop]
                    if value then
                        local restoredProp
                        if value.drawable and value.drawable >= 0 then
                            restoredProp = pcall(SetPedPropIndex, ped, prop, value.drawable, value.texture, true)
                        else
                            restoredProp = pcall(ClearPedProp, ped, prop)
                        end
                        restored = restored and restoredProp
                    end
                end
            end
            portraitCaptureActive = false

            if not ok or not restored then
                return { success = false, error = "Could not capture your character portrait." }
            end
            return type(result) == "table" and result or
                { success = false, error = "Could not capture your character portrait." }
        end

        RegisterNUICallback("civregClose", function(_, cb)
            closeUi()
            cb({ ok = true })
        end)

        RegisterNUICallback("civregTakeSelfie", function(_, cb)
            local result = captureUncoveredPortrait()
            if type(result) ~= "table" or not result.success or
                type(result.base64) ~= "string" or result.base64 == "" then
                cb({
                    ok = false,
                    error = type(result) == "table" and result.error or "Could not capture your character portrait."
                })
                return
            end

            cb({
                ok = true,
                image = result.base64
            })
        end)

        local databaseSyncCaptureActive = false
        RegisterNetEvent("SonoranCAD::civreg::CaptureDatabaseSyncMugshot", function(payload)
            if type(payload) ~= "table" or type(payload.token) ~= "string" then
                return
            end
            if databaseSyncCaptureActive then
                TriggerServerEvent("SonoranCAD::civreg::DatabaseSyncMugshot", payload.token, nil,
                    "Another character portrait capture is already active.")
                return
            end
            databaseSyncCaptureActive = true
            local result = captureUncoveredPortrait()
            databaseSyncCaptureActive = false

            local image = type(result) == "table" and result.success and result.base64 or nil
            local captureError = type(result) == "table" and result.error or
                "Could not capture your character portrait."
            TriggerLatentServerEvent("SonoranCAD::civreg::DatabaseSyncMugshot", 200000,
                payload.token, image, image and nil or captureError)
        end)

        RegisterNUICallback("civregSubmit", function(data, cb)
            if not uiOpen or type(data) ~= "table" then
                cb({ ok = false })
                return
            end

            TriggerLatentServerEvent("SonoranCAD::civreg::Submit", 200000,
                data.session, data.values or {}, data.selfies or {})
            cb({ ok = true })
        end)

        AddEventHandler("onClientResourceStop", function(resourceName)
            if resourceName == GetCurrentResourceName() and uiOpen then
                setUiOpen(false)
            end
        end)
    end)
end)
