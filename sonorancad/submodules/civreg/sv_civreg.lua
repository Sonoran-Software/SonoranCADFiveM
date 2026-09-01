CreateThread(function()
    Config.LoadPlugin("civreg", function(pluginConfig)
        if not pluginConfig.enabled then
            return
        end

        local sessions = {}
        local lastFormRequest = {}
        local templateCache = nil
        local SESSION_LIFETIME_MS = 10 * 60 * 1000
        local FORM_REQUEST_COOLDOWN_MS = 3000
        local MAX_FIELD_LENGTH = 8000
        local DEFAULT_STATUS_OPTIONS = { "0", "1", "2" }

        AddPluginFilePath("civreg")

        local function notifyPlayer(target, payload)
            NotifyPlayer(target, ApplyPluginNotificationOverrides(pluginConfig, payload))
        end

        local function nonEmpty(...)
            for i = 1, select("#", ...) do
                local value = select(i, ...)
                if value ~= nil and tostring(value) ~= "" then
                    return value
                end
            end
            return nil
        end

        local function normalizeTemplate(data, templateId)
            if type(data) ~= "table" then
                return nil
            end
            if type(data.template) == "table" then
                data = data.template
            elseif type(data.templates) == "table" then
                data = data.templates
            end
            if data.recordTypeId ~= nil then
                return data
            end
            for _, template in pairs(data) do
                if type(template) == "table" and
                    tostring(template.recordTypeId) == tostring(templateId) then
                    return template
                end
            end
            return nil
        end

        local function collectFields(template)
            local fields = {}
            for _, section in ipairs(template.sections or {}) do
                for _, field in ipairs(section.fields or {}) do
                    if type(field.uid) == "string" and field.uid ~= "" then
                        fields[field.uid] = field
                    end
                end
            end
            return fields
        end

        local function getLiveTemplate(templateId)
            local now = GetGameTimer()
            local cacheLifetimeMs = math.max(0, tonumber(pluginConfig.templateCacheSeconds) or 60) * 1000
            if type(templateCache) == "table" and templateCache.templateId == templateId and
                now - templateCache.fetchedAt < cacheLifetimeMs then
                return templateCache.template, nil
            end

            local response = CadApiGetTemplates({ recordTypeId = templateId })
            if not response.success then
                return nil, response
            end
            local template = normalizeTemplate(response.data, templateId)
            if type(template) ~= "table" or type(template.sections) ~= "table" then
                return nil, response
            end
            templateCache = {
                templateId = templateId,
                fetchedAt = now,
                template = template
            }
            return template, response
        end

        local function normalizeSex(value)
            if value == nil then
                return nil
            end
            local normalized = tostring(value):lower()
            if normalized == "0" or normalized == "m" or normalized == "male" then
                return "M"
            end
            if normalized == "1" or normalized == "f" or normalized == "female" then
                return "F"
            end
            return tostring(value)
        end

        local function collectFrameworkIdentity(source)
            if type(GetIdentity) ~= "function" then
                return {}
            end

            local identity = nil
            local completed = false
            local ok = pcall(function()
                GetIdentity(source, function(result)
                    identity = result
                    completed = true
                end)
            end)
            if not ok then
                return {}
            end

            local timeoutAt = GetGameTimer() + 2500
            while not completed and GetGameTimer() < timeoutAt do
                Wait(0)
            end
            if type(identity) ~= "table" then
                return {}
            end

            local playerData = type(identity.PlayerData) == "table" and identity.PlayerData or {}
            local charInfo = type(playerData.charinfo) == "table" and playerData.charinfo or {}
            local variables = type(identity.variables) == "table" and identity.variables or {}

            return {
                first = nonEmpty(charInfo.firstname, identity.firstName, identity.firstname, variables.firstName,
                    variables.firstname),
                last = nonEmpty(charInfo.lastname, identity.lastName, identity.lastname, variables.lastName,
                    variables.lastname),
                dob = nonEmpty(charInfo.birthdate, charInfo.dateofbirth, identity.dateofbirth, variables.dateofbirth),
                sex = normalizeSex(nonEmpty(charInfo.gender, charInfo.sex, identity.sex, variables.sex)),
                height = nonEmpty(charInfo.height, identity.height, variables.height),
                phone = nonEmpty(charInfo.phone, charInfo.phoneNumber, identity.phone, identity.phoneNumber,
                    variables.phone),
                nationality = nonEmpty(charInfo.nationality, identity.nationality, variables.nationality)
            }
        end

        local function buildPrefill(source, fields)
            local identity = collectFrameworkIdentity(source)
            local prefill = {}
            for semanticName, uid in pairs(pluginConfig.autofillFieldIds or {}) do
                local value = identity[semanticName]
                if type(uid) == "string" and fields[uid] ~= nil and value ~= nil then
                    prefill[uid] = tostring(value)
                end
            end
            return prefill
        end

        local function newSessionToken(source)
            local ok, token = pcall(function()
                return exports[GetCurrentResourceName()]:CreateImageToken()
            end)
            if ok and type(token) == "string" and token ~= "" then
                return token
            end
            return ("%x-%x-%x-%x"):format(os.time(), source, GetGameTimer(), math.random(0, 0x7fffffff))
        end

        local function resolveSelfieBaseUrl()
            local configured = type(pluginConfig.selfieBaseUrl) == "string" and
                pluginConfig.selfieBaseUrl:gsub("%s+$", ""):gsub("/+$", "") or ""
            if configured ~= "" then
                return configured
            end

            local server = type(ServerInfo) == "table" and ServerInfo or nil
            if server == nil then
                local response = CadApiGetServers()
                if response.success and type(response.data) == "table" then
                    for _, candidate in pairs(response.data.servers or response.data) do
                        if type(candidate) == "table" and
                            tostring(candidate.id) == tostring(Config.serverId) then
                            server = candidate
                            break
                        end
                    end
                end
            end

            local host = server and server.mapIp or nil
            local port = server and server.listenerPort or GetConvar("netPort", "")
            if type(host) ~= "string" or host == "" or tostring(port or "") == "" or tostring(port) == "0" then
                return nil
            end
            return ("http://%s:%s/%s/civreg"):format(host, tostring(port), GetCurrentResourceName())
        end

        local function dependencyValue(values, fields, uid)
            if values[uid] ~= nil then
                return values[uid]
            end
            local field = fields[uid]
            if type(field) ~= "table" then
                return nil
            end
            if field.type == "checkboxes" and type(field.data) == "table" then
                return field.data.flags
            end
            return field.value
        end

        local function dependencyMatches(dependency, values, fields)
            if type(dependency) ~= "table" or type(dependency.fid) ~= "string" or dependency.fid == "" then
                return true
            end
            local actual = dependencyValue(values, fields, dependency.fid)
            local acceptable = type(dependency.acceptableValues) == "table" and dependency.acceptableValues or {}
            local contains = false
            if type(actual) == "table" then
                local selected = actual.flags or actual
                for _, selectedValue in pairs(selected) do
                    for _, acceptedValue in pairs(acceptable) do
                        if tostring(selectedValue) == tostring(acceptedValue) then
                            contains = true
                        end
                    end
                end
            else
                for _, acceptedValue in pairs(acceptable) do
                    if tostring(actual or "") == tostring(acceptedValue) then
                        contains = true
                    end
                end
            end
            if tostring(dependency.type or ""):upper() == "NOTEQUAL" then
                return not contains
            end
            return contains
        end

        local function fieldIsVisible(field, section, values, fields)
            return dependencyMatches(section and section.dependency, values, fields) and
                dependencyMatches(field.dependency, values, fields)
        end

        local function hasValue(value)
            if type(value) == "table" then
                local flags = value.flags or value
                return next(flags) ~= nil
            end
            return value ~= nil and tostring(value):match("%S") ~= nil
        end

        local function sanitizeSubmission(session, submittedValues)
            if type(submittedValues) ~= "table" then
                return nil, "The submitted form data was invalid."
            end

            local replacements = {}
            for uid, field in pairs(session.fields) do
                local value = submittedValues[uid]
                local fieldType = tostring(field.type or "")
                if field.isSupervisor or fieldType == "image" or fieldType == "label" or fieldType == "id" or
                    fieldType:match("^UNIT_") then
                    value = nil
                elseif field.readOnly then
                    value = session.prefill[uid]
                elseif fieldType == "checkboxes" then
                    if value ~= nil then
                        local flags = type(value) == "table" and (value.flags or value) or {}
                        local allowed = {}
                        for _, option in ipairs(field.options or {}) do
                            allowed[tostring(option)] = true
                        end
                        local selected = {}
                        for _, option in pairs(flags) do
                            option = tostring(option)
                            if allowed[option] then
                                selected[#selected + 1] = option
                            end
                        end
                        value = { flags = selected }
                    end
                elseif fieldType == "select" or fieldType == "status" then
                    if value ~= nil then
                        value = tostring(value)
                        if #value > MAX_FIELD_LENGTH then
                            return nil, ("%s is too long."):format(field.label or uid)
                        end

                        local options = field.options or {}
                        if fieldType == "status" and #options == 0 then
                            options = DEFAULT_STATUS_OPTIONS
                        end
                        local allowed = value == ""
                        for _, option in ipairs(options) do
                            if tostring(option) == value then
                                allowed = true
                                break
                            end
                        end
                        if not allowed then
                            return nil, ("%s contains an invalid option."):format(field.label or uid)
                        end
                    end
                else
                    if value ~= nil then
                        value = tostring(value)
                        if #value > MAX_FIELD_LENGTH then
                            return nil, ("%s is too long."):format(field.label or uid)
                        end
                    end
                end

                if value ~= nil then
                    replacements[uid] = value
                end
            end
            return replacements
        end

        local function findSectionForField(template, targetField)
            for _, section in ipairs(template.sections or {}) do
                for _, field in ipairs(section.fields or {}) do
                    if field == targetField then
                        return section
                    end
                end
            end
            return nil
        end

        local function validateRequiredFields(session, replacements)
            for uid, field in pairs(session.fields) do
                local section = findSectionForField(session.template, field)
                if field.isRequired and fieldIsVisible(field, section, replacements, session.fields) then
                    local value = replacements[uid]
                    if value == nil then
                        value = tostring(field.type or "") == "checkboxes" and field.data or field.value
                    end
                    if not hasValue(value) then
                        return false, ("%s is required."):format(field.label or uid)
                    end
                end
            end
            return true
        end

        local function deleteSavedFiles(paths)
            for _, path in ipairs(paths) do
                os.remove(path)
            end
        end

        RegisterNetEvent("SonoranCAD::civreg::RequestForm", function()
            local source = source
            local now = GetGameTimer()
            if lastFormRequest[source] and now - lastFormRequest[source] < FORM_REQUEST_COOLDOWN_MS then
                return
            end
            lastFormRequest[source] = now

            local playerCadStatus = getPlayerCadStatus(source, "Character Registration", { link = true, unit = false })
            if not playerCadStatus.success then
                return
            end

            local templateId = tonumber(pluginConfig.templateId) or 7
            local template, response = getLiveTemplate(templateId)
            if template == nil and response and not response.success then
                CadApiLogFailure("GET_TEMPLATES", response, { recordTypeId = templateId })
                sendClientError(source, "CIVREG_TEMPLATE_FAILED")
                return
            end
            if type(template) ~= "table" or type(template.sections) ~= "table" then
                logError("CIVREG_TEMPLATE_FAILED", "Template #7 was missing sections or returned an unexpected payload.")
                sendClientError(source, "CIVREG_TEMPLATE_FAILED")
                return
            end

            local fields = collectFields(template)
            local prefill = buildPrefill(source, fields)
            local token = newSessionToken(source)
            sessions[source] = {
                token = token,
                createdAt = now,
                communityUserId = playerCadStatus.link,
                template = template,
                fields = fields,
                prefill = prefill
            }

            TriggerClientEvent("SonoranCAD::civreg::OpenForm", source, {
                session = token,
                template = template,
                prefill = prefill,
                language = pluginConfig.language
            })
        end)

        RegisterNetEvent("SonoranCAD::civreg::Submit", function(token, submittedValues, selfies)
            local source = source
            local session = sessions[source]
            if type(session) ~= "table" or token ~= session.token or
                GetGameTimer() - session.createdAt > SESSION_LIFETIME_MS then
                sessions[source] = nil
                sendClientError(source, "CIVREG_SUBMISSION_INVALID")
                TriggerClientEvent("SonoranCAD::civreg::SubmissionResult", source,
                    { success = false, message = getErrorText("CIVREG_SUBMISSION_INVALID") })
                return
            end
            if session.submitting then
                return
            end
            session.submitting = true

            local replacements, validationError = sanitizeSubmission(session, submittedValues)
            if not replacements then
                session.submitting = false
                sendClientError(source, "CIVREG_SUBMISSION_INVALID", validationError)
                TriggerClientEvent("SonoranCAD::civreg::SubmissionResult", source,
                    { success = false, message = validationError })
                return
            end

            local savedFiles = {}
            selfies = type(selfies) == "table" and selfies or {}
            local baseUrl = nil
            for uid, dataUrl in pairs(selfies) do
                local field = session.fields[uid]
                if type(field) ~= "table" or tostring(field.type) ~= "image" or type(dataUrl) ~= "string" then
                    deleteSavedFiles(savedFiles)
                    session.submitting = false
                    sendClientError(source, "CIVREG_SUBMISSION_INVALID")
                    TriggerClientEvent("SonoranCAD::civreg::SubmissionResult", source,
                        { success = false, message = getErrorText("CIVREG_SUBMISSION_INVALID") })
                    return
                end

                baseUrl = baseUrl or resolveSelfieBaseUrl()
                if baseUrl == nil then
                    logError("CIVREG_SELFIE_URL_MISSING",
                        "Could not derive a public selfie URL. Configure civreg selfieBaseUrl.")
                    sendClientError(source, "CIVREG_SELFIE_URL_MISSING")
                    session.submitting = false
                    TriggerClientEvent("SonoranCAD::civreg::SubmissionResult", source,
                        { success = false, message = getErrorText("CIVREG_SELFIE_URL_MISSING") })
                    return
                end

                local extension = dataUrl:find("^data:image/png;base64,") and "png" or "jpg"
                local safeUid = uid:gsub("[^%w_]", "_")
                local filename = ("%s-%s.%s"):format(session.token:gsub("[^%w]", ""), safeUid, extension)
                local filePath = ("%s/filestore/civreg/%s"):format(GetResourcePath(GetCurrentResourceName()), filename)
                local saveResult = exports[GetCurrentResourceName()]:SaveBase64Image(dataUrl, filePath,
                    tonumber(pluginConfig.maxSelfieBytes) or 1024 * 1024)
                if type(saveResult) ~= "table" or not saveResult.success then
                    deleteSavedFiles(savedFiles)
                    logError("CIVREG_SELFIE_SAVE_FAILED",
                        ("Could not save character selfie: %s"):format(tostring(saveResult and saveResult.reason)))
                    sendClientError(source, "CIVREG_SELFIE_SAVE_FAILED")
                    session.submitting = false
                    TriggerClientEvent("SonoranCAD::civreg::SubmissionResult", source,
                        { success = false, message = getErrorText("CIVREG_SELFIE_SAVE_FAILED") })
                    return
                end
                savedFiles[#savedFiles + 1] = filePath
                replacements[uid] = ("%s/%s"):format(baseUrl, filename)
            end

            local valid, requiredError = validateRequiredFields(session, replacements)
            if not valid then
                deleteSavedFiles(savedFiles)
                session.submitting = false
                sendClientError(source, "CIVREG_SUBMISSION_INVALID", requiredError)
                TriggerClientEvent("SonoranCAD::civreg::SubmissionResult", source,
                    { success = false, message = requiredError })
                return
            end

            local createResponse = CadApiCreateRecord({
                communityUserId = session.communityUserId,
                useDictionary = true,
                recordTypeId = tonumber(pluginConfig.templateId) or 7,
                replaceValues = replacements
            })
            if not createResponse.success then
                deleteSavedFiles(savedFiles)
                session.submitting = false
                CadApiLogFailure("NEW_CHARACTER", createResponse, {
                    communityUserId = session.communityUserId,
                    recordTypeId = tonumber(pluginConfig.templateId) or 7,
                    replaceValues = replacements
                })
                sendClientError(source, "CIVREG_CREATE_FAILED")
                TriggerClientEvent("SonoranCAD::civreg::SubmissionResult", source,
                    { success = false, message = getErrorText("CIVREG_CREATE_FAILED") })
                return
            end

            local successMessage = pluginConfig.language.success or "Character registered successfully in CAD."
            sessions[source] = nil
            notifyPlayer(source, {
                title = "CAD - Success",
                message = successMessage,
                type = "success"
            })
            TriggerClientEvent("SonoranCAD::civreg::SubmissionResult", source,
                { success = true, message = successMessage, recordId = createResponse.recordId })
        end)

        AddEventHandler("playerDropped", function()
            sessions[source] = nil
            lastFormRequest[source] = nil
        end)
    end)
end)
