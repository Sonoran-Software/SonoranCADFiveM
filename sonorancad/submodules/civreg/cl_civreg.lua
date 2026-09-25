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
        local FRAMEWORK_READY_POLL_MS = 250
        local qbAppearanceReadyAt = nil
        local qbAppearanceReadyPed = nil
        local qbExpectedProps = nil

        local function portraitDebug(message)
            if type(debugLog) == "function" then
                debugLog("[civreg portrait] " .. message)
            end
        end

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

        local function serializeFingerprintValue(value, seen)
            local valueType = type(value)
            if valueType ~= "table" then
                local serialized = tostring(value)
                return valueType .. ":" .. #serialized .. ":" .. serialized
            end

            seen = seen or {}
            if seen[value] then
                return "table:cycle"
            end
            seen[value] = true

            local count = 0
            local highestIndex = 0
            local isArray = true
            for key in pairs(value) do
                count = count + 1
                if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
                    isArray = false
                elseif key > highestIndex then
                    highestIndex = key
                end
            end
            isArray = isArray and highestIndex == count

            local parts = {}
            if isArray then
                for _, item in ipairs(value) do
                    parts[#parts + 1] = serializeFingerprintValue(item, seen)
                end
                -- Tattoo order is not meaningful and can vary between provider loads.
                table.sort(parts)
            else
                for key, item in pairs(value) do
                    parts[#parts + 1] = serializeFingerprintValue(key, seen) .. "=" ..
                        serializeFingerprintValue(item, seen)
                end
                table.sort(parts)
            end

            seen[value] = nil
            return "table:{" .. table.concat(parts, ",") .. "}"
        end

        local function getProviderTattooFingerprint(ped)
            for _, resourceName in ipairs({ "illenium-appearance", "fivem-appearance" }) do
                if GetResourceState(resourceName) == "started" then
                    local ok, appearance = pcall(function()
                        return exports[resourceName]:getPedAppearance(ped)
                    end)
                    if ok and type(appearance) == "table" and type(appearance.tattoos) == "table" then
                        return serializeFingerprintValue(appearance.tattoos)
                    end
                end
            end
            return nil
        end

        local function getPedAppearanceFingerprint(ped, ignoreCoverings)
            local parts = { tostring(ped), tostring(GetEntityModel(ped)) }
            for component = 0, 11 do
                if not ignoreCoverings or (component ~= 1 and component ~= 7) then
                    parts[#parts + 1] = table.concat({
                        GetPedDrawableVariation(ped, component),
                        GetPedTextureVariation(ped, component),
                        GetPedPaletteVariation(ped, component)
                    }, ":")
                end
            end
            for prop = 0, 7 do
                if not ignoreCoverings or prop > 2 then
                    parts[#parts + 1] = table.concat({
                        GetPedPropIndex(ped, prop),
                        GetPedPropTextureIndex(ped, prop)
                    }, ":")
                end
            end
            for feature = 0, 19 do
                parts[#parts + 1] = string.format("%.4f", GetPedFaceFeature(ped, feature))
            end

            local _, shapeFirst, shapeSecond, shapeThird, skinFirst, skinSecond, skinThird,
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

            local tattooFingerprint = getProviderTattooFingerprint(ped)
            if tattooFingerprint then
                parts[#parts + 1] = tattooFingerprint
            end
            return table.concat(parts, "|")
        end

        local function frameworkCharacterIsFullySpawned()
            local ped = PlayerPedId()
            return NetworkIsPlayerActive(PlayerId()) and DoesEntityExist(ped) and
                IsEntityVisible(ped) and HasCollisionLoadedAroundEntity(ped) and IsScreenFadedIn()
        end

        local function qbSkinPropsApplied(ped)
            if not qbExpectedProps then
                return true
            end
            for prop, expected in pairs(qbExpectedProps) do
                if GetPedPropIndex(ped, prop) ~= expected.drawable or
                    GetPedPropTextureIndex(ped, prop) ~= expected.texture then
                    return false
                end
            end
            return true
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
                local appearanceChanged = false
                local lastCharacterReady = false
                local lastAppearanceReady = false
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
                        (qbAppearanceReadyAt and qbAppearanceReadyAt >= options.startedAt and
                            qbAppearanceReadyPed == ped and qbSkinPropsApplied(ped))
                    lastCharacterReady = characterReady
                    lastAppearanceReady = appearanceReady
                    local ready = characterReady and appearanceReady and frameworkCharacterIsFullySpawned()
                    local fingerprint = ready and getPedAppearanceFingerprint(ped) or nil
                    if ready and options.initialFingerprint and not options.allowUnchangedAppearance and
                        not appearanceChanged then
                        if fingerprint ~= options.initialFingerprint then
                            appearanceChanged = true
                        else
                            -- A timer cannot prove that an asynchronous appearance provider applied
                            -- the selected skin. Capture only after a visible change on fresh login.
                            ready = false
                        end
                    end

                    if ready then
                        if fingerprint ~= stableFingerprint then
                            stableFingerprint = fingerprint
                            stableSince = GetGameTimer()
                        elseif stableSince and GetGameTimer() - stableSince >= FRAMEWORK_CAPTURE_SETTLE_MS then
                            portraitDebug(("appearance settled for character %s, ped %s, model %s; requesting capture"):format(
                                tostring(expectedCharacterId), tostring(ped), tostring(GetEntityModel(ped))))
                            TriggerServerEvent("SonoranCAD::civreg::FrameworkCharacterSelected")
                            return
                        end
                    else
                        stableFingerprint = nil
                        stableSince = nil
                    end
                    Wait(FRAMEWORK_READY_POLL_MS)
                end
                if generation == frameworkSelectionGeneration then
                    portraitDebug(("spawn readiness timed out for character %s (character=%s, clothing=%s, signaledPed=%s, propsApplied=%s, ped=%s, changed=%s)"):format(
                        tostring(expectedCharacterId), tostring(lastCharacterReady), tostring(lastAppearanceReady),
                        tostring(qbAppearanceReadyPed),
                        tostring(DoesEntityExist(PlayerPedId()) and qbSkinPropsApplied(PlayerPedId())),
                        tostring(PlayerPedId()), tostring(appearanceChanged)))
                end
            end)
        end

        if useQBCore then
            RegisterNetEvent("qb-clothing:client:loadPlayerClothing", function(skinData, targetPed)
                if targetPed and targetPed ~= PlayerPedId() then
                    portraitDebug(("ignored qb-clothing preview ped %s; player ped is %s"):format(
                        tostring(targetPed), tostring(PlayerPedId())))
                    return
                end
                if type(skinData) ~= "table" then
                    portraitDebug("ignored qb-clothing signal without skin data")
                    return
                end
                qbAppearanceReadyAt = GetGameTimer()
                qbAppearanceReadyPed = PlayerPedId()
                qbExpectedProps = {}
                for prop, key in pairs({ [0] = "hat", [1] = "glass", [2] = "ear" }) do
                    local value = skinData[key]
                    if type(value) == "table" and type(value.item) == "number" and value.item > 0 then
                        qbExpectedProps[prop] = { drawable = value.item, texture = value.texture or 0 }
                    end
                end
                portraitDebug(("qb-clothing signaled player ped %s"):format(tostring(qbAppearanceReadyPed)))
            end)
            AddEventHandler("qb-clothing:client:onMenuClose", function()
                qbAppearanceReadyAt = GetGameTimer()
                qbAppearanceReadyPed = PlayerPedId()
                qbExpectedProps = nil
                portraitDebug(("qb-clothing menu closed on player ped %s"):format(tostring(qbAppearanceReadyPed)))
            end)

            RegisterNetEvent("QBCore:Client:OnPlayerLoaded", function()
                local startedAt = GetGameTimer()
                local playerData = getQBCorePlayerData()
                local ped = PlayerPedId()
                local qbClothingStarted = GetResourceState("qb-clothing") == "started"
                local alternateAppearanceStarted = GetResourceState("illenium-appearance") == "started" or
                    GetResourceState("fivem-appearance") == "started"
                qbAppearanceReadyAt = nil
                qbAppearanceReadyPed = nil
                qbExpectedProps = nil
                portraitDebug(("QB player loaded: character %s, ped %s, model %s, qb-clothing=%s, alternate=%s"):format(
                    tostring(type(playerData) == "table" and playerData.citizenid), tostring(ped),
                    tostring(GetEntityModel(ped)), tostring(qbClothingStarted), tostring(alternateAppearanceStarted)))
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
                qbAppearanceReadyPed = nil
                qbExpectedProps = nil
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

            local fingerprintOk, identityFingerprint = pcall(getPedAppearanceFingerprint, ped, true)
            if not fingerprintOk then
                portraitDebug("could not read ped appearance before capture")
                return { success = false, error = "Could not read your character appearance." }
            end

            portraitCaptureActive = true
            local components = {}
            local props = {}
            local appearanceRestored = false
            local appearanceChangedDuringCapture = false
            local function restoreAppearance()
                -- Do not reapply this snapshot after conversion; the player's outfit may change meanwhile.
                if appearanceRestored then
                    return not appearanceChangedDuringCapture
                end

                local restored = true
                local identityStable = ped == PlayerPedId() and DoesEntityExist(ped) and
                    getPedAppearanceFingerprint(ped, true) == identityFingerprint
                if not identityStable then
                    appearanceChangedDuringCapture = true
                    appearanceRestored = true
                    portraitDebug(("ped or appearance changed during capture; original ped %s, current ped %s; skipped stale gear restoration"):format(
                        tostring(ped), tostring(PlayerPedId())))
                    return false
                end

                -- A clothing provider may replace a hidden slot while the headshot loads.
                -- Keep its newer value, restore other hidden slots, and reject the covered image.
                for _, component in ipairs(HIDDEN_PORTRAIT_COMPONENTS) do
                    if components[component] and (GetPedDrawableVariation(ped, component) ~= 0 or
                        GetPedTextureVariation(ped, component) ~= 0 or
                        GetPedPaletteVariation(ped, component) ~= 0) then
                        appearanceChangedDuringCapture = true
                        portraitDebug(("covering component %s changed before headshot was ready"):format(
                            tostring(component)))
                    end
                end
                for _, prop in ipairs(HIDDEN_PORTRAIT_PROPS) do
                    if props[prop] and GetPedPropIndex(ped, prop) ~= -1 then
                        appearanceChangedDuringCapture = true
                        portraitDebug(("covering prop %s changed before headshot was ready"):format(tostring(prop)))
                    end
                end

                if DoesEntityExist(ped) then
                    for _, component in ipairs(HIDDEN_PORTRAIT_COMPONENTS) do
                        local value = components[component]
                        if value and GetPedDrawableVariation(ped, component) == 0 and
                            GetPedTextureVariation(ped, component) == 0 then
                            local restoredComponent = pcall(SetPedComponentVariation, ped, component,
                                value.drawable, value.texture, value.palette)
                            restored = restored and restoredComponent
                        end
                    end
                    for _, prop in ipairs(HIDDEN_PORTRAIT_PROPS) do
                        local value = props[prop]
                        if value and GetPedPropIndex(ped, prop) == -1 then
                            local restoredProp
                            if value.drawable and value.drawable >= 0 then
                                for _ = 1, 3 do
                                    restoredProp = pcall(SetPedPropIndex, ped, prop, value.drawable,
                                        value.texture, true)
                                    if restoredProp and GetPedPropIndex(ped, prop) == value.drawable and
                                        GetPedPropTextureIndex(ped, prop) == value.texture then
                                        break
                                    end
                                    Wait(0)
                                end
                                restoredProp = restoredProp and GetPedPropIndex(ped, prop) == value.drawable and
                                    GetPedPropTextureIndex(ped, prop) == value.texture
                            else
                                restoredProp = pcall(ClearPedProp, ped, prop)
                            end
                            if not restoredProp then
                                portraitDebug(("could not restore prop %s (drawable %s, texture %s); now %s/%s"):format(
                                    tostring(prop), tostring(value.drawable), tostring(value.texture),
                                    tostring(GetPedPropIndex(ped, prop)), tostring(GetPedPropTextureIndex(ped, prop))))
                            end
                            restored = restored and restoredProp
                        end
                    end
                else
                    restored = false
                end

                appearanceRestored = restored
                return restored and not appearanceChangedDuringCapture
            end

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

                portraitDebug(("capturing ped %s, model %s, hat=%s, glasses=%s, ears=%s"):format(
                    tostring(ped), tostring(GetEntityModel(ped)), tostring(props[0].drawable),
                    tostring(props[1].drawable), tostring(props[2].drawable)))

                Wait(0)
                Wait(0)
                return GetBase64(ped, restoreAppearance)
            end)

            local restored = restoreAppearance()
            portraitCaptureActive = false

            if not ok or not restored or ped ~= PlayerPedId() or
                getPedAppearanceFingerprint(ped, true) ~= identityFingerprint then
                portraitDebug(("portrait capture failed: helper=%s, restored=%s, error=%s"):format(
                    tostring(ok), tostring(restored), tostring(ok and type(result) == "table" and result.error or result)))
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
