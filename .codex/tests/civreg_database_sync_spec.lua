-- Run from the repository root with Lua 5.4 or newer.
-- Exercises CivReg database sync mode with isolated FiveM, CAD, and SQL boundaries.
local PNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j5ioAAAAASUVORK5CYII="
local passed = 0

local function equal(actual, expected, message)
    assert(actual == expected,
        (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, callback)
    local ok, err = pcall(callback)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
    print("PASS " .. name)
end

local function loadConfig()
    local config
    local env = setmetatable({
        Config = { RegisterPluginConfig = function(_, value) config = value end }
    }, { __index = _G })
    assert(loadfile("sonorancad/configuration/civreg_config.dist.lua", "t", env))()
    return config
end

local function harness(options)
    options = options or {}
    local h = {
        now = 10000,
        events = {},
        queries = {},
        clientEvents = {},
        failures = {},
        errors = {},
        accountRequests = 0,
        configurationRequests = 0,
        identityRequests = 0,
        tokenIndex = 0
    }
    local config = loadConfig()
    if options.config then
        options.config(config)
    end

    local env = setmetatable({ source = 42 }, { __index = _G })
    env.Config = {
        LoadPlugin = function(_, callback) callback(config) end,
        GetPluginConfig = function() return { usingQBCore = options.framework ~= "esx" } end
    }
    env.CreateThread = function(callback) callback() end
    env.RegisterNetEvent = function(name, callback) h.events[name] = callback end
    env.AddEventHandler = function(name, callback) h.events[name] = callback end
    env.GetGameTimer = function() return h.now end
    env.GetCurrentResourceName = function() return "sonorancad" end
    env.AddPluginFilePath = function() end
    env.GetResourceState = function(name)
        if options.noDatabase then
            if name == "qb-core" then return "started" end
            return "missing"
        end
        if options.framework == "esx" then
            if name == "es_extended" or name == (options.provider or "oxmysql") then return "started" end
            return "missing"
        end
        if name == "qb-core" or name == (options.provider or "oxmysql") then return "started" end
        return "missing"
    end

    local function recordQuery(provider, sql, parameters, callback)
        h.queries[#h.queries + 1] = { provider = provider, sql = sql, parameters = parameters }
        if sql:match("^SELECT ") then
            callback(options.selectRows or {})
        elseif sql:match("^UPDATE ") then
            callback(options.updateResult or (provider == "mysql-async" and 1 or { affectedRows = 1 }))
        else
            callback(options.queryResult or { affectedRows = 0 })
        end
    end

    env.exports = {
        sonorancad = {
            CreateImageToken = function()
                h.tokenIndex = h.tokenIndex + 1
                return "db-token-" .. tostring(h.tokenIndex)
            end
        },
        oxmysql = {
            query = function(_, sql, parameters, callback)
                recordQuery("oxmysql", sql, parameters, callback)
            end
        },
        ["mysql-async"] = {
            mysql_execute = function(_, sql, parameters, callback)
                recordQuery("mysql-async", sql, parameters, callback)
            end,
            mysql_fetch_all = function(_, sql, parameters, callback)
                recordQuery("mysql-async", sql, parameters, callback)
            end
        },
        ["qb-core"] = {
            GetCoreObject = function()
                return {
                    Functions = {
                        GetPlayer = function()
                            return { PlayerData = { citizenid = options.currentCharacterId or "QB-123" } }
                        end
                    }
                }
            end
        },
        ["es_extended"] = {
            getSharedObject = function()
                return {
                    GetPlayerFromId = function()
                        return { getIdentifier = function() return options.currentCharacterId or "license:esx-123" end }
                    end
                }
            end
        }
    }

    local configurationFailuresRemaining = tonumber(options.configurationFailures) or 0
    env.CadApiGetDatabaseSyncConfiguration = function()
        h.configurationRequests = h.configurationRequests + 1
        if options.configurationFailure or configurationFailuresRemaining > 0 then
            configurationFailuresRemaining = math.max(0, configurationFailuresRemaining - 1)
            return { success = false, reason = "fixture configuration failure" }
        end
        return {
            success = true,
            data = options.databaseSync or {
                enabled = true,
                character = true,
                licenses = true,
                vehicleRegistrations = true
            }
        }
    end
    env.CadApiGetAccount = function(payload)
        h.accountRequests = h.accountRequests + 1
        h.accountPayload = payload
        return { success = true, data = { communityUserId = "linked-player" } }
    end
    env.CadApiGetTemplates = function() error("Database sync mode must not load the API character template") end
    env.CadApiCreateRecord = function() error("Database sync mode must not create an API character") end
    env.CadApiLogFailure = function(name, response, payload)
        h.failures[#h.failures + 1] = { name = name, response = response, payload = payload }
    end
    env.GetSourceByCadIdentity = function(identities)
        h.identityRequests = h.identityRequests + 1
        equal(identities[1], "linked-player")
        return 42
    end
    env.GetPlayers = function() return { "42" } end
    env.GetPlayerCommunityUserId = function()
        if options.playerCommunityUserId == false then
            return nil
        end
        return options.playerCommunityUserId or "linked-player"
    end
    if options.cachedAccountPlayer then
        env.GetSourceByCadAccountUuid = function(accountUuid)
            equal(accountUuid, "00000000-0000-0000-0000-000000000000")
            return 42
        end
    end
    env.getPlayerCadStatus = function(_, _, checks)
        equal(checks.link, true)
        equal(checks.unit, false)
        return { success = true, link = "linked-player" }
    end
    env.TriggerClientEvent = function(name, target, payload)
        equal(target, 42)
        h.clientEvents[#h.clientEvents + 1] = { name = name, payload = payload }
        h.lastClientEvent = h.clientEvents[#h.clientEvents]
    end
    env.sendClientError = function(_, key, detail)
        h.errors[#h.errors + 1] = { key = key, detail = detail }
    end
    env.getErrorText = function(key) return key end
    env.CadApiReasonText = function(value) return tostring(value) end
    env.logError = function(key, detail)
        h.errors[#h.errors + 1] = { key = key, detail = detail }
    end
    env.infoLog = function(message) h.info = message end
    env.debugLog = function(message) h.debug = message end
    env.ApplyPluginNotificationOverrides = function(_, payload) return payload end
    env.NotifyPlayer = function(_, payload) h.notification = payload end

    assert(loadfile("sonorancad/submodules/civreg/sv_civreg.lua", "t", env))()

    function h:requestCommandCapture()
        self.events["SonoranCAD::civreg::RequestForm"]()
        return self.lastClientEvent
    end

    function h:submitCapture(clientEvent, image, captureError, token)
        self.events["SonoranCAD::civreg::DatabaseSyncMugshot"](
            token or clientEvent.payload.token, image, captureError)
    end

    return h
end

test("enabled character sync always migrates the QBCore table with MEDIUMTEXT", function()
    local h = harness()
    equal(#h.queries, 1)
    equal(h.queries[1].provider, "oxmysql")
    equal(h.queries[1].sql,
        "ALTER TABLE `players` ADD COLUMN IF NOT EXISTS `sonoran_mugshot` MEDIUMTEXT NULL")
end)

test("the civreg command updates the active QBCore character instead of creating an API record", function()
    local h = harness()
    local capture = h:requestCommandCapture()
    equal(capture.name, "SonoranCAD::civreg::CaptureDatabaseSyncMugshot")
    h:submitCapture(capture, PNG)
    equal(#h.queries, 2)
    equal(h.queries[2].sql, "UPDATE `players` SET `sonoran_mugshot` = ? WHERE `citizenid` = ?")
    equal(h.queries[2].parameters[1], PNG)
    equal(h.queries[2].parameters[2], "QB-123")
    equal(h.notification.message, "Character portrait updated successfully.")
end)

test("character selected updates the exact DB sync ID and caches account resolution", function()
    local h = harness()
    h.events["SonoranCAD::pushevents:CharacterSelected"]({
        accId = "00000000-0000-0000-0000-000000000000",
        id = "SYNC-456"
    })
    local capture = h.lastClientEvent
    h:submitCapture(capture, PNG)
    equal(h.queries[2].parameters[2], "SYNC-456")
    equal(h.accountPayload.accountUuid, "00000000-0000-0000-0000-000000000000")

    h.events["SonoranCAD::pushevents:CharacterSelected"]({
        accId = "00000000-0000-0000-0000-000000000000",
        id = "SYNC-789"
    })
    equal(h.accountRequests, 1)
end)

test("character selected uses the existing CAD link cache before the account API", function()
    local h = harness({ cachedAccountPlayer = true })
    h.events["SonoranCAD::pushevents:CharacterSelected"]({
        accId = "00000000-0000-0000-0000-000000000000",
        id = "SYNC-CACHED"
    })
    h:submitCapture(h.lastClientEvent, PNG)
    equal(h.accountRequests, 0)
    equal(h.queries[2].parameters[2], "SYNC-CACHED")
end)

test("character selected requires an active link after account resolution", function()
    local h = harness({ playerCommunityUserId = false })
    h.events["SonoranCAD::pushevents:CharacterSelected"]({
        accId = "00000000-0000-0000-0000-000000000000",
        id = "SYNC-UNLINKED"
    })
    equal(h.accountRequests, 1)
    equal(h.identityRequests, 0)
    equal(#h.clientEvents, 0)
end)

test("an old token cannot delete the current pending capture", function()
    local h = harness()
    local capture = h:requestCommandCapture()
    h:submitCapture(capture, PNG, nil, "forged-token")
    equal(#h.queries, 1)
    h:submitCapture(capture, PNG)
    equal(#h.queries, 2)
end)

test("an in-flight capture remains bound to its original character", function()
    local h = harness()
    local capture = h:requestCommandCapture()
    h.now = h.now + 3001
    h.events["SonoranCAD::pushevents:CharacterSelected"]({
        accId = "00000000-0000-0000-0000-000000000000",
        id = "SYNC-LATEST"
    })
    equal(#h.clientEvents, 1)
    equal(h.lastClientEvent.payload.token, capture.payload.token)
    h:submitCapture(capture, PNG)
    equal(h.queries[2].parameters[2], "QB-123")
end)

test("expired database portrait uploads cannot write SQL", function()
    local h = harness()
    local capture = h:requestCommandCapture()
    h.now = h.now + 30001
    h:submitCapture(capture, PNG)
    equal(#h.queries, 1)
end)

test("zero-row updates reject a missing framework character", function()
    local h = harness({ updateResult = { affectedRows = 0 }, selectRows = {} })
    local capture = h:requestCommandCapture()
    h:submitCapture(capture, PNG)
    equal(#h.queries, 3)
    assert(h.queries[3].sql:match("^SELECT 1 AS `found`"))
    equal(h.notification, nil)
    equal(h.errors[#h.errors].key, "CIVREG_DB_SYNC_FAILED")
    assert(h.errors[#h.errors].detail:find("No framework character matched", 1, true))
end)

test("zero-row updates accept an unchanged portrait on an existing character", function()
    local h = harness({ updateResult = { affectedRows = 0 }, selectRows = { { found = 1 } } })
    local capture = h:requestCommandCapture()
    h:submitCapture(capture, PNG)
    equal(#h.queries, 3)
    equal(h.notification.message, "Character portrait updated successfully.")
end)

test("mysql-async uses the ESX table and named parameters", function()
    local h = harness({ framework = "esx", provider = "mysql-async" })
    equal(h.queries[1].sql,
        "ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `sonoran_mugshot` MEDIUMTEXT NULL")
    local capture = h:requestCommandCapture()
    h:submitCapture(capture, PNG)
    equal(h.queries[2].provider, "mysql-async")
    equal(h.queries[2].sql,
        "UPDATE `users` SET `sonoran_mugshot` = @mugshot WHERE `identifier` = @characterId")
    equal(h.queries[2].parameters["@characterId"], "license:esx-123")
    equal(h.queries[2].parameters["@mugshot"], PNG)
end)

test("database configuration failure remains fail closed", function()
    local h = harness({ configurationFailure = true })
    equal(#h.queries, 0)
    h.events["SonoranCAD::civreg::RequestForm"]()
    equal(h.errors[#h.errors].key, "CIVREG_DB_SYNC_FAILED")
end)

test("database configuration discovery retries after a startup failure", function()
    local h = harness({ configurationFailures = 1 })
    equal(h.configurationRequests, 1)
    equal(#h.queries, 0)
    local capture = h:requestCommandCapture()
    equal(h.configurationRequests, 2)
    equal(#h.queries, 1)
    equal(capture.name, "SonoranCAD::civreg::CaptureDatabaseSyncMugshot")
end)

test("missing SQL provider prevents portrait writes", function()
    local h = harness({ noDatabase = true })
    equal(#h.queries, 0)
    equal(h.errors[1].key, "CIVREG_DB_SYNC_FAILED")
    h.events["SonoranCAD::civreg::RequestForm"]()
    equal(#h.queries, 0)
end)

print(("%d civreg database sync regression tests passed."):format(passed))
