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
        local DB_SYNC_CAPTURE_TIMEOUT_MS = 30 * 1000
        local MAX_FIELD_LENGTH = 8000
        local MUGSHOT_COLUMN = "sonoran_mugshot"
        local databaseSync = {
            mode = "unavailable",
            ready = false,
            mapping = nil
        }
        local pendingDatabaseSyncCaptures = {}
        local accountCommunityUserCache = {}
        local DEFAULT_STATUS_OPTIONS = { "0", "1", "2" }
        local MASK_TOKENS = {
            ["#"] = "%d",
            M = "%d",
            D = "%d",
            Y = "%d",
            S = "%a",
            X = "[%a%d]"
        }
        local LUA_PATTERN_CHARACTERS = {
            ["^"] = true,
            ["$"] = true,
            ["("] = true,
            [")"] = true,
            ["%"] = true,
            ["."] = true,
            ["["] = true,
            ["]"] = true,
            ["*"] = true,
            ["+"] = true,
            ["-"] = true,
            ["?"] = true
        }

        -- Keep serving portraits referenced by records created before base64 uploads.
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

        local function validSqlIdentifier(value)
            return type(value) == "string" and value:match("^[A-Za-z0-9_]+$") ~= nil
        end

        local function resolveDatabaseMapping()
            local settings = type(pluginConfig.databaseSync) == "table" and pluginConfig.databaseSync or {}
            local qbSettings = type(settings.qbCore) == "table" and settings.qbCore or {}
            local esxSettings = type(settings.esx) == "table" and settings.esx or {}
            local frameworkConfig = type(Config.plugins) == "table" and
                Config.plugins.frameworksupport or {}
            local qbStarted = GetResourceState("qb-core") == "started"
            local esxStarted = GetResourceState("es_extended") == "started"
            local useQBCore = qbStarted and (not esxStarted or frameworkConfig.usingQBCore ~= false)
            local mapping

            if useQBCore then
                mapping = {
                    framework = "qbcore",
                    tableName = qbSettings.tableName or "players",
                    characterIdColumn = qbSettings.characterIdColumn or "citizenid"
                }
            elseif esxStarted then
                mapping = {
                    framework = "esx",
                    tableName = esxSettings.tableName or "users",
                    characterIdColumn = esxSettings.characterIdColumn or "identifier"
                }
            else
                return nil, "QBCore or ESX must be started before Sonoran CAD."
            end

            if not validSqlIdentifier(mapping.tableName) or not validSqlIdentifier(mapping.characterIdColumn) then
                return nil, "The configured database sync table and character ID column must contain only letters, numbers, and underscores."
            end
            return mapping
        end

        local function executeDatabase(oxSql, oxParameters, mysqlSql, mysqlParameters, callback)
            local completed = false
            local function finish(success, result)
                if completed then
                    return
                end
                completed = true
                callback(success, result)
            end

            if GetResourceState("oxmysql") == "started" then
                local ok, err = pcall(function()
                    exports.oxmysql:query(oxSql, oxParameters or {}, function(result)
                        finish(true, result)
                    end)
                end)
                if not ok then
                    finish(false, err)
                end
                return
            end
            if GetResourceState("mysql-async") == "started" then
                local ok, err = pcall(function()
                    exports["mysql-async"]:mysql_execute(mysqlSql or oxSql, mysqlParameters or {}, function(result)
                        finish(true, result)
                    end)
                end)
                if not ok then
                    finish(false, err)
                end
                return
            end

            finish(false, "Neither oxmysql nor mysql-async is started.")
        end

        local function fetchDatabase(oxSql, oxParameters, mysqlSql, mysqlParameters, callback)
            local completed = false
            local function finish(success, result)
                if completed then
                    return
                end
                completed = true
                callback(success, result)
            end

            if GetResourceState("oxmysql") == "started" then
                local ok, err = pcall(function()
                    exports.oxmysql:query(oxSql, oxParameters or {}, function(result)
                        finish(true, result)
                    end)
                end)
                if not ok then
                    finish(false, err)
                end
                return
            end
            if GetResourceState("mysql-async") == "started" then
                local ok, err = pcall(function()
                    exports["mysql-async"]:mysql_fetch_all(mysqlSql or oxSql, mysqlParameters or {}, function(result)
                        finish(true, result)
                    end)
                end)
                if not ok then
                    finish(false, err)
                end
                return
            end

            finish(false, "Neither oxmysql nor mysql-async is started.")
        end

        local function logDatabaseSyncFailure(detail)
            logError("CIVREG_DB_SYNC_FAILED", tostring(detail or "Unknown database sync error."))
        end

        local function migrateMugshotColumn()
            local mapping, mappingError = resolveDatabaseMapping()
            if mapping == nil then
                databaseSync.mode = "unavailable"
                databaseSync.ready = false
                databaseSync.mapping = nil
                logDatabaseSyncFailure(mappingError)
                return
            end
            databaseSync.mapping = mapping

            local sql = ("ALTER TABLE `%s` ADD COLUMN IF NOT EXISTS `%s` MEDIUMTEXT NULL"):format(
                mapping.tableName, MUGSHOT_COLUMN)
            executeDatabase(sql, {}, sql, {}, function(success, result)
                if not success then
                    databaseSync.mode = "unavailable"
                    databaseSync.ready = false
                    databaseSync.mapping = nil
                    logDatabaseSyncFailure(("Could not add %s.%s: %s"):format(
                        mapping.tableName, MUGSHOT_COLUMN, tostring(result)))
                    return
                end
                databaseSync.ready = true
                infoLog(("CivReg database sync mode is ready (%s.%s -> %s)."):format(
                    mapping.tableName, mapping.characterIdColumn, MUGSHOT_COLUMN))
            end)
        end

        local function updateDatabaseMugshot(characterId, dataUrl, callback)
            local mapping = databaseSync.mapping
            if databaseSync.mode ~= "database" or not databaseSync.ready or type(mapping) ~= "table" then
                callback(false, "Database sync mode is not ready.")
                return
            end
            if characterId == nil or tostring(characterId) == "" then
                callback(false, "The selected character did not include a database sync ID.")
                return
            end

            local oxSql = ("UPDATE `%s` SET `%s` = ? WHERE `%s` = ?"):format(
                mapping.tableName, MUGSHOT_COLUMN, mapping.characterIdColumn)
            local mysqlSql = ("UPDATE `%s` SET `%s` = @mugshot WHERE `%s` = @characterId"):format(
                mapping.tableName, MUGSHOT_COLUMN, mapping.characterIdColumn)
            local normalizedCharacterId = tostring(characterId)
            executeDatabase(oxSql, { dataUrl, normalizedCharacterId }, mysqlSql, {
                ["@mugshot"] = dataUrl,
                ["@characterId"] = normalizedCharacterId
            }, function(success, result)
                if not success then
                    callback(false, result)
                    return
                end

                local affectedRows = type(result) == "number" and result or
                    (type(result) == "table" and tonumber(result.affectedRows))
                if affectedRows == nil then
                    callback(false, "The database did not return an affected-row count for the mugshot update.")
                    return
                end
                if affectedRows > 0 then
                    callback(true, result)
                    return
                end

                -- A zero count can mean either a missing character or an unchanged portrait.
                -- Check the row before reporting success to the player.
                local oxExistsSql = ("SELECT 1 AS `found` FROM `%s` WHERE `%s` = ? LIMIT 1"):format(
                    mapping.tableName, mapping.characterIdColumn)
                local mysqlExistsSql = ("SELECT 1 AS `found` FROM `%s` WHERE `%s` = @characterId LIMIT 1"):format(
                    mapping.tableName, mapping.characterIdColumn)
                fetchDatabase(oxExistsSql, { normalizedCharacterId }, mysqlExistsSql, {
                    ["@characterId"] = normalizedCharacterId
                }, function(fetchSuccess, rows)
                    if not fetchSuccess then
                        callback(false, rows)
                    elseif type(rows) == "table" and rows[1] ~= nil then
                        callback(true, result)
                    else
                        callback(false, ("No framework character matched database sync ID %s."):format(
                            normalizedCharacterId))
                    end
                end)
            end)
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
                return tostring(data.recordTypeId) == tostring(templateId) and data or nil
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

        local function normalizeMaskedPrefill(field, value)
            value = tostring(value)
            if tostring(field.mask or "") == "MM/DD/YYYY" then
                local year, month, day = value:match("^(%d%d%d%d)[-/](%d%d)[-/](%d%d)$")
                if year ~= nil then
                    return ("%s/%s/%s"):format(month, day, year)
                end
            end
            return value
        end

        local function generateRandomValue(field)
            if field.value ~= nil and tostring(field.value) ~= "" then
                return tostring(field.value)
            end
            local mask = type(field.mask) == "string" and field.mask or ""
            if mask == "" then
                return nil
            end
            local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            local digits = "0123456789"
            local alphanumeric = letters .. digits
            local sources = {
                ["#"] = digits,
                M = digits,
                D = digits,
                Y = digits,
                S = letters,
                X = alphanumeric
            }
            return (mask:gsub(".", function(character)
                local source = sources[character]
                if source == nil then
                    return character
                end
                local index = math.random(1, #source)
                return source:sub(index, index)
            end))
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

        local function getCurrentFrameworkCharacterId(source)
            local mapping = databaseSync.mapping
            if type(mapping) ~= "table" then
                return nil
            end

            if mapping.framework == "qbcore" then
                local ok, characterId = pcall(function()
                    local core = exports["qb-core"]:GetCoreObject()
                    local player = core.Functions.GetPlayer(source)
                    return player and player.PlayerData and player.PlayerData.citizenid or nil
                end)
                return ok and nonEmpty(characterId) or nil
            end

            local ok, characterId = pcall(function()
                local esx = exports["es_extended"]:getSharedObject()
                local player = esx.GetPlayerFromId(source)
                if player == nil then
                    return nil
                end
                if type(player.getIdentifier) == "function" then
                    return player.getIdentifier()
                end
                return player.identifier
            end)
            return ok and nonEmpty(characterId) or nil
        end

        local function buildPrefill(source, fields)
            local identity = collectFrameworkIdentity(source)
            local prefill = {}
            for semanticName, uid in pairs(pluginConfig.autofillFieldIds or {}) do
                local value = identity[semanticName]
                if type(uid) == "string" and fields[uid] ~= nil and value ~= nil then
                    prefill[uid] = normalizeMaskedPrefill(fields[uid], value)
                end
            end
            for uid, field in pairs(fields) do
                if tostring(field.type or "") == "random" and prefill[uid] == nil then
                    prefill[uid] = generateRandomValue(field)
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

        local function requestDatabaseSyncCapture(source, characterId, notifyOnSuccess)
            if databaseSync.mode ~= "database" or not databaseSync.ready then
                return false, "Database sync mode is not ready."
            end
            if characterId == nil or tostring(characterId) == "" then
                return false, "No active database sync character was found."
            end

            local pending = pendingDatabaseSyncCaptures[source]
            if type(pending) == "table" and
                GetGameTimer() - pending.createdAt <= DB_SYNC_CAPTURE_TIMEOUT_MS then
                if pending.characterId == tostring(characterId) then
                    pending.notifyOnSuccess = pending.notifyOnSuccess or notifyOnSuccess == true
                    return true
                end
                return false, "A portrait capture is already in progress for another character."
            end

            local token = newSessionToken(source)
            pendingDatabaseSyncCaptures[source] = {
                token = token,
                characterId = tostring(characterId),
                createdAt = GetGameTimer(),
                notifyOnSuccess = notifyOnSuccess == true
            }
            TriggerClientEvent("SonoranCAD::civreg::CaptureDatabaseSyncMugshot", source, {
                token = token
            })
            return true
        end

        local function validateSelfie(dataUrl)
            if type(dataUrl) ~= "string" then
                return false, "The character portrait must contain a base64 PNG or JPEG image."
            end
            local prefix = dataUrl:match("^data:image/png;base64,") or dataUrl:match("^data:image/jpeg;base64,")
            if prefix == nil then
                return false, "The character portrait must contain a base64 PNG or JPEG image."
            end

            local limit = tonumber(pluginConfig.maxSelfieBytes)
            if limit == nil or limit ~= limit or limit <= 0 or limit == math.huge then
                limit = 1024 * 1024
            end
            limit = math.floor(limit)
            local encodedLength = #dataUrl - #prefix
            -- Bound the input before extracting or scanning the base64 payload.
            if encodedLength > math.ceil(limit / 3) * 4 then
                return false, "The character portrait exceeds the configured image size limit."
            end
            if encodedLength == 0 or encodedLength % 4 ~= 0 then
                return false, "The character portrait contains invalid base64 data."
            end
            local encoded = dataUrl:sub(#prefix + 1)
            local padding = encoded:match("=*$")
            if #padding > 2 or encoded:sub(1, #encoded - #padding):find("[^A-Za-z0-9+/]") then
                return false, "The character portrait contains invalid base64 data."
            end
            local decodedBytes = encodedLength / 4 * 3 - #padding
            if decodedBytes > limit then
                return false, "The character portrait exceeds the configured image size limit."
            end
            return true
        end

        local function resolveCharacterSelectedPlayer(accountUuid)
            accountUuid = tostring(accountUuid or "")
            if accountUuid == "" then
                return nil
            end

            if type(GetSourceByCadAccountUuid) == "function" then
                local cachedPlayer = GetSourceByCadAccountUuid(accountUuid)
                if cachedPlayer ~= nil then
                    return tonumber(cachedPlayer) or cachedPlayer
                end
            end

            local communityUserId = accountCommunityUserCache[accountUuid]
            if communityUserId == nil then
                local response = CadApiGetAccount({ accountUuid = accountUuid })
                if not response.success then
                    CadApiLogFailure("GET_ACCOUNT", response, { accountUuid = accountUuid })
                    return nil
                end
                local account = type(response.data) == "table" and
                    (response.data.account or response.data) or {}
                communityUserId = nonEmpty(account.communityUserId, account.apiId)
                if communityUserId == nil then
                    logDatabaseSyncFailure("The selected character account did not include a communityUserId.")
                    return nil
                end
                accountCommunityUserCache[accountUuid] = tostring(communityUserId)
            end

            if type(GetPlayers) == "function" and type(GetPlayerCommunityUserId) == "function" then
                for _, player in ipairs(GetPlayers()) do
                    if tostring(GetPlayerCommunityUserId(player) or "") == tostring(communityUserId) then
                        return tonumber(player) or player
                    end
                end
            end
            return nil
        end

        local function initializeMode()
            local response = CadApiGetDatabaseSyncConfiguration()
            if type(response) ~= "table" or response.success ~= true or type(response.data) ~= "table" then
                databaseSync.mode = "unavailable"
                databaseSync.ready = false
                databaseSync.mapping = nil
                CadApiLogFailure("GET_DATABASE_SYNC_CONFIGURATION", response or { success = false }, {})
                logDatabaseSyncFailure("Could not determine whether CAD character database sync is enabled.")
                return false
            end

            if response.data.enabled == true and response.data.character == true then
                databaseSync.mode = "database"
                databaseSync.ready = false
                databaseSync.mapping = nil
                migrateMugshotColumn()
                return databaseSync.mode == "database"
            end
            databaseSync.mode = "api"
            databaseSync.ready = false
            databaseSync.mapping = nil
            return true
        end

        initializeMode()

        local function dependencyValue(values, fields, uid)
            if values[uid] ~= nil then
                return values[uid]
            end
            local field = fields[uid]
            if type(field) ~= "table" then
                return nil
            end
            if (field.type == "checkboxes" or
                    (type(field.data) == "table" and type(field.data.flags) == "table")) and
                type(field.data) == "table" then
                return field.data.flags
            end
            return field.value
        end

        local function fieldUsesFlags(field)
            return tostring(field.type or "") == "checkboxes" or
                (type(field.data) == "table" and type(field.data.flags) == "table")
        end

        local function valueMatchesMask(value, mask)
            mask = type(mask) == "string" and mask or ""
            value = tostring(value or "")
            if mask == "" or value == "" then
                return true
            end

            local pattern = { "^" }
            for character in mask:gmatch(".") do
                local token = MASK_TOKENS[character]
                if token ~= nil then
                    pattern[#pattern + 1] = token
                else
                    pattern[#pattern + 1] = LUA_PATTERN_CHARACTERS[character] and ("%" .. character) or character
                end
            end
            pattern[#pattern + 1] = "$"
            return value:match(table.concat(pattern)) ~= nil
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
                elseif fieldType == "random" then
                    value = session.prefill[uid]
                elseif field.readOnly then
                    value = session.prefill[uid]
                    if value == nil then
                        value = fieldUsesFlags(field) and field.data or field.value
                    end
                end

                if value ~= nil and fieldUsesFlags(field) then
                    local flags = value
                    if type(value) == "table" and value.flags ~= nil then
                        flags = value.flags
                    end
                    if type(flags) ~= "table" then
                        return nil, ("%s contains invalid options."):format(field.label or uid)
                    end
                    local allowed = {}
                    local options = type(field.options) == "table" and field.options or {}
                    for _, option in ipairs(options) do
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
                elseif value ~= nil and (fieldType == "select" or fieldType == "status") then
                    value = tostring(value)
                    if #value > MAX_FIELD_LENGTH then
                        return nil, ("%s is too long."):format(field.label or uid)
                    end

                    local options = type(field.options) == "table" and field.options or {}
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
                elseif value ~= nil then
                    value = tostring(value)
                    if #value > MAX_FIELD_LENGTH then
                        return nil, ("%s is too long."):format(field.label or uid)
                    end
                    if not valueMatchesMask(value, field.mask) then
                        return nil, ("%s must match the format %s."):format(field.label or uid, field.mask)
                    end
                end

                if value ~= nil then
                    replacements[uid] = value
                end
            end

            local removed = true
            while removed do
                removed = false
                for uid in pairs(replacements) do
                    local field = session.fields[uid]
                    local section = findSectionForField(session.template, field)
                    if not fieldIsVisible(field, section, replacements, session.fields) then
                        replacements[uid] = nil
                        removed = true
                    end
                end
            end
            return replacements
        end

        local function validateRequiredFields(session, replacements)
            for uid, field in pairs(session.fields) do
                local section = findSectionForField(session.template, field)
                local fieldType = tostring(field.type or "")
                local automaticallyManaged = field.isSupervisor or field.readOnly or fieldType == "label" or
                    fieldType == "id" or fieldType:match("^UNIT_")
                if not automaticallyManaged and field.isRequired and
                    fieldIsVisible(field, section, replacements, session.fields) then
                    local value = replacements[uid]
                    if value == nil then
                        value = fieldUsesFlags(field) and field.data or field.value
                    end
                    if not hasValue(value) then
                        return false, ("%s is required."):format(field.label or uid)
                    end
                end
            end
            return true
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

            if databaseSync.mode == "unavailable" then
                initializeMode()
            end
            if databaseSync.mode == "unavailable" then
                sendClientError(source, "CIVREG_DB_SYNC_FAILED")
                return
            end
            if databaseSync.mode == "database" then
                local characterId = getCurrentFrameworkCharacterId(source)
                local requested, requestError = requestDatabaseSyncCapture(source, characterId, true)
                if not requested then
                    logDatabaseSyncFailure(requestError)
                    sendClientError(source, "CIVREG_DB_SYNC_FAILED", requestError)
                end
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
                logError("CIVREG_TEMPLATE_FAILED",
                    ("Template #%s was missing sections or returned an unexpected payload."):format(templateId))
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

            local currentCadStatus = getPlayerCadStatus(source, "Character Registration", { link = true, unit = false })
            if not currentCadStatus.success or
                tostring(currentCadStatus.link or "") ~= tostring(session.communityUserId or "") then
                sessions[source] = nil
                sendClientError(source, "CIVREG_SUBMISSION_INVALID")
                TriggerClientEvent("SonoranCAD::civreg::SubmissionResult", source,
                    { success = false, message = getErrorText("CIVREG_SUBMISSION_INVALID") })
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

            selfies = type(selfies) == "table" and selfies or {}
            for uid, dataUrl in pairs(selfies) do
                local field = session.fields[uid]
                local section = type(field) == "table" and findSectionForField(session.template, field) or nil
                if type(field) ~= "table" or tostring(field.type) ~= "image" or field.isSupervisor or field.readOnly or
                    type(dataUrl) ~= "string" or
                    not fieldIsVisible(field, section, replacements, session.fields) then
                    session.submitting = false
                    sendClientError(source, "CIVREG_SUBMISSION_INVALID")
                    TriggerClientEvent("SonoranCAD::civreg::SubmissionResult", source,
                        { success = false, message = getErrorText("CIVREG_SUBMISSION_INVALID") })
                    return
                end

                local validSelfie, selfieError = validateSelfie(dataUrl)
                if not validSelfie then
                    sendClientError(source, "CIVREG_SUBMISSION_INVALID", selfieError)
                    session.submitting = false
                    TriggerClientEvent("SonoranCAD::civreg::SubmissionResult", source,
                        { success = false, message = selfieError })
                    return
                end
                replacements[uid] = dataUrl
            end

            local valid, requiredError = validateRequiredFields(session, replacements)
            if not valid then
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
                session.submitting = false
                CadApiLogFailure("NEW_CHARACTER", createResponse, {
                    communityUserId = session.communityUserId,
                    recordTypeId = tonumber(pluginConfig.templateId) or 7
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

        AddEventHandler("SonoranCAD::pushevents:CharacterSelected", function(data)
            if databaseSync.mode == "unavailable" then
                initializeMode()
            end
            if databaseSync.mode ~= "database" or not databaseSync.ready or type(data) ~= "table" then
                return
            end
            local characterId = nonEmpty(data.id, data.syncId, data.characterId)
            local accountUuid = nonEmpty(data.accId, data.accountUuid, data.accountId)
            if characterId == nil or accountUuid == nil then
                logDatabaseSyncFailure("EVENT_CHAR_SELECTED was missing the account UUID or database sync character ID.")
                return
            end

            local player = resolveCharacterSelectedPlayer(accountUuid)
            if player == nil then
                debugLog(("CivReg did not refresh database sync mugshot %s because its CAD account is not linked to an online player."):format(
                    tostring(characterId)))
                return
            end
            local requested, requestError = requestDatabaseSyncCapture(player, characterId, false)
            if not requested then
                logDatabaseSyncFailure(requestError)
            end
        end)

        RegisterNetEvent("SonoranCAD::civreg::DatabaseSyncMugshot", function(token, dataUrl, captureError)
            local source = source
            local pending = pendingDatabaseSyncCaptures[source]
            if type(pending) ~= "table" then
                return
            end
            if token ~= pending.token then
                return
            end
            if GetGameTimer() - pending.createdAt > DB_SYNC_CAPTURE_TIMEOUT_MS then
                pendingDatabaseSyncCaptures[source] = nil
                return
            end
            pendingDatabaseSyncCaptures[source] = nil

            local valid, validationError = validateSelfie(dataUrl)
            if not valid then
                local detail = nonEmpty(captureError, validationError)
                logDatabaseSyncFailure(detail)
                if pending.notifyOnSuccess then
                    sendClientError(source, "CIVREG_DB_SYNC_FAILED", detail)
                end
                return
            end

            updateDatabaseMugshot(pending.characterId, dataUrl, function(success, result)
                if not success then
                    logDatabaseSyncFailure(result)
                    if pending.notifyOnSuccess then
                        sendClientError(source, "CIVREG_DB_SYNC_FAILED", result)
                    end
                    return
                end
                debugLog(("CivReg updated the database sync mugshot for character %s."):format(
                    tostring(pending.characterId)))
                if pending.notifyOnSuccess then
                    notifyPlayer(source, {
                        title = "CAD - Success",
                        message = pluginConfig.language.databaseSyncSuccess or
                            "Character portrait updated successfully.",
                        type = "success"
                    })
                end
            end)
        end)

        AddEventHandler("playerDropped", function()
            sessions[source] = nil
            lastFormRequest[source] = nil
            pendingDatabaseSyncCaptures[source] = nil
        end)
    end)
end)
