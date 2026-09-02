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

        RegisterNUICallback("civregClose", function(_, cb)
            closeUi()
            cb({ ok = true })
        end)

        RegisterNUICallback("civregTakeSelfie", function(_, cb)
            local ok, result = pcall(GetBase64, PlayerPedId())
            if not ok or type(result) ~= "table" or not result.success or
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
            local ok, result = pcall(GetBase64, PlayerPedId())
            databaseSyncCaptureActive = false

            local image = ok and type(result) == "table" and result.success and result.base64 or nil
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
