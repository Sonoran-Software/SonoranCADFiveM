--[[
    Sonaran CAD Plugins

    Plugin Name: calltemplates
    Creator: SonoranCAD
    Description: Uses templates from the resolved CAD configuration to build dispatch commands
]]

CreateThread(function()
    Config.LoadPlugin("calltemplates", function(pluginConfig)
        if not pluginConfig.enabled then return end

        local function notifyPlayer(target, payload)
            NotifyPlayer(target, ApplyPluginNotificationOverrides(pluginConfig, payload))
        end

        local function getTemplate(templateKey)
            -- The key can be a legacy filename. It only indexes the resolved
            -- configuration, including the cached copy if CAD is unavailable.
            local template = Config.callTemplates[templateKey]
            if type(template) ~= "table" then
                errorLog("UNHANDLED_SERVER_ERROR", ("[calltemplates] Missing CAD call template: %s"):format(tostring(templateKey)))
                return nil
            end

            -- Preserve the older exported object and array formats.
            if type(template.callType) == "table" then
                return template.callType
            elseif type(template[1]) == "table" then
                return template[1]
            end
            return template
        end

        local function buildDescription(cmdConfig, template, args)
            local userText = table.concat(args, " ")
            local pieces = {}

            local prefix = cmdConfig.descriptionPrefix or template.descriptionPrefix
            if prefix ~= nil and prefix ~= "" then
                table.insert(pieces, prefix)
            end

            if template.description ~= nil and template.description ~= "" and cmdConfig.includeTemplateDescription ~= false then
                table.insert(pieces, template.description)
            end

            if userText ~= nil and userText ~= "" then
                table.insert(pieces, userText)
            end

            local combined = table.concat(pieces, " - ")
            if combined == "" then
                combined = userText
            end

            return combined
        end

        local function mergeNotes(baseNotes, extraNotes)
            local notes = {}
            if type(baseNotes) == "table" then
                for _, note in ipairs(baseNotes) do
                    notes[#notes + 1] = note
                end
            end

            if type(extraNotes) == "table" then
                for _, note in ipairs(extraNotes) do
                    notes[#notes + 1] = note
                end
            end

            return notes
        end

        local function handleCommand(cmdConfig, source, args, rawCommand)
            local template = getTemplate(cmdConfig.callTypeFile)
            if template == nil then
                sendClientError(source, "CALL_TEMPLATE_INVALID")
                return
            end

            if not args[1] then
                sendClientError(source, "CALL_MISSING_DETAILS")
                return
            end

            local playerCadStatus = getPlayerCadStatus(source, "Call Templates", { link = true })
            if not playerCadStatus.success then
                return
            end
            local communityUserId = playerCadStatus.link

            local address = LocationCache[source] ~= nil and LocationCache[source].location or "Unknown"
            address = address:gsub('%b[]', '')

            local postal = ""
            if isPluginLoaded("postals") then
                if PostalsCache ~= nil and PostalsCache[source] ~= nil then
                    postal = PostalsCache[source]
                else
                    postal = getNearestPostal(source) or ""
                end
            end

            local units = {}
            if type(template.units) == "table" then
                for _, unit in ipairs(template.units) do
                    units[#units + 1] = unit
                end
            end

            if cmdConfig.includePlayerUnit ~= false then
                units[#units + 1] = communityUserId
            end

            local extraNotes = {}
            if cmdConfig.includeWraithPlate and isPluginLoaded("wraithv2") and wraithLastPlates ~= nil and wraithLastPlates.locked ~= nil then
                local plate = wraithLastPlates.locked.plate
                if plate ~= nil then
                    plate = plate:gsub("%s+", "")
                    table.insert(extraNotes, {
                        time = "00:00:00",
                        label = "Dispatch",
                        type = "text",
                        content = ("PLATE: %s"):format(plate)
                    })
                end
            end

            local payload = {
                serverId = tonumber(Config.serverId),
                callId = template.callId or -1,
                origin = template.origin or pluginConfig.defaultOrigin or 2,
                status = template.status or pluginConfig.defaultStatus or 1,
                priority = template.priority or pluginConfig.defaultPriority or 2,
                block = template.block or "",
                postal = template.postal or postal,
                address = template.address or address,
                title = cmdConfig.title or template.title or "Dispatch Call",
                code = cmdConfig.code or template.code or "",
                description = buildDescription(cmdConfig, template, args),
                notes = mergeNotes(template.notes, extraNotes),
                communityUserIds = CadApiResolveCommunityUserIds(units)
            }

            TriggerEvent("SonoranCAD::calltemplates:SendDispatch", payload, source, cmdConfig.command)
        end

        RegisterNetEvent("SonoranCAD::calltemplates:SendDispatch")
        AddEventHandler("SonoranCAD::calltemplates:SendDispatch", function(payload, source, commandName)
            TriggerEvent("SonoranCAD::calltemplates:cadIncomingDispatch", payload, source, commandName)

            if Config.apiSendEnabled then
                debugLog(("[calltemplates] sending dispatch from /%s"):format(commandName or "unknown"))
                local response = CadApiCreateDispatchCall(payload)
                if response.success then
                    notifyPlayer(source, {
                        title = "SonoranCAD",
                        message = "Your call has been sent to CAD.",
                        type = "success"
                    })
                else
                    CadApiLogFailure("NEW_DISPATCH", response, payload)
                    sendClientError(source, "CALL_SEND_FAILED")
                end
            else
                logError("CAD_API_DISABLED")
                sendClientError(source, "CAD_API_DISABLED")
            end
        end)

        for _, cmdConfig in ipairs(pluginConfig.commands or {}) do
            if cmdConfig.command ~= nil and cmdConfig.callTypeFile ~= nil then
                local cfg = cmdConfig
                local restricted = cfg.useAcePermissions
                if restricted == nil then restricted = true end

                RegisterCommand(cfg.command, function(source, args, rawCommand)
                    handleCommand(cfg, source, args, rawCommand)
                end, restricted)
            else
                warnLog("UNHANDLED_WARNING", "[calltemplates] command configuration missing `command` or `callTypeFile`")
            end
        end
    end)
end)
