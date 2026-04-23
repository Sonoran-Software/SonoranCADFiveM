--[[
    Sonaran CAD Plugins

    Plugin Name: calltemplates
    Creator: SonoranCAD
    Description: Uses exported call type templates to build dispatch commands
]]

CreateThread(function()
    Config.LoadPlugin("calltemplates", function(pluginConfig)
        if not pluginConfig.enabled then return end

        local templateCache = {}
        local templateDirectory = pluginConfig.callTypeDirectory or "submodules/calltemplates/calltypes"

        local function loadTemplate(fileName)
            if fileName == nil or fileName == "" then
                warnLog("[calltemplates] callTypeFile missing from command config.")
                return nil
            end

            if not pluginConfig.reloadTemplatesOnEachUse and templateCache[fileName] ~= nil then
                return templateCache[fileName]
            end

            local filePath = ("%s/%s"):format(templateDirectory, fileName)
            local raw = LoadResourceFile(GetCurrentResourceName(), filePath)
            if raw == nil then
                errorLog(("[calltemplates] Unable to load call type template at %s"):format(filePath))
                return nil
            end

            local decoded = json.decode(raw)
            if decoded == nil then
                errorLog(("[calltemplates] Failed to decode JSON for template %s"):format(filePath))
                return nil
            end

            if type(decoded.callType) == "table" then
                decoded = decoded.callType
            elseif type(decoded) == "table" and #decoded > 0 and type(decoded[1]) == "table" then
                decoded = decoded[1]
            end

            if not pluginConfig.reloadTemplatesOnEachUse then
                templateCache[fileName] = decoded
            end

            return decoded
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
            local template = loadTemplate(cmdConfig.callTypeFile)
            if template == nil then
                TriggerClientEvent("chat:addMessage", source, {args = {"^0[ ^1Error ^0] ", "Call template missing or invalid."}})
                return
            end

            if not args[1] then
                TriggerClientEvent("chat:addMessage", source, {args = {"^0[ ^1Error ^0] ", "You need to specify call details."}})
                return
            end

            local communityUserId = GetPlayerCommunityUserId(source)
            if communityUserId == nil then
                TriggerClientEvent("chat:addMessage", source, {args = {"^0[ ^1Error ^0] ", "You must link your CAD account before sending this dispatch."}})
                return
            end

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
                metaData = template.metaData or {},
                units = units,
                primary = template.primary or -1,
                trackPrimary = template.trackPrimary or false,
                idents = template.idents or {}
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
                    TriggerClientEvent("chat:addMessage", source, {args = {"^0^5^*[SonoranCAD]^r ", "^7Your call has been sent to CAD."}})
                else
                    CadApiLogFailure("NEW_DISPATCH", response, payload)
                    TriggerClientEvent("chat:addMessage", source, {args = {"^0[ ^1Error ^0] ", "Call could not be sent to CAD."}})
                end
            else
                errorLog("Config.apiSendEnabled disabled via convar or config, skipping call creation. Check your config if this is unintentional.")
                TriggerClientEvent("chat:addMessage", source, {args = {"^0[ ^1Error ^0] ", "Call could not be sent; API is disabled."}})
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
                warnLog("[calltemplates] command configuration missing `command` or `callTypeFile`")
            end
        end
    end)
end)
