-- Run from the repository root: lua tests/civreg_registration_spec.lua
-- Uses the real config and server module with isolated FiveM/CAD boundaries.
local PNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j5ioAAAAASUVORK5CYII="
local JPEG = "data:image/jpeg;base64,/9j/2Q=="
local passed = 0

local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function harness(options)
    options = options or {}
    local h = {
        events = {}, replies = {}, requests = {}, failures = {}, now = 10000, registeredPaths = {},
        currentLink = "linked-account"
    }
    local config
    local configEnv = setmetatable({ Config = { RegisterPluginConfig = function(_, value) config = value end } }, { __index = _G })
    assert(loadfile("sonorancad/configuration/civreg_config.dist.lua", "t", configEnv))()
    config.maxSelfieBytes = options.limit or config.maxSelfieBytes
    -- Existing configurations may still contain this; it must not affect uploads.
    config.selfieBaseUrl = "https://obsolete.example.com/civreg"
    local photo = { uid = "photo", label = "Portrait", type = "image", isRequired = true }
    if options.photo then options.photo(photo) end
    local template = { recordTypeId = 7, sections = { { label = "Character", fields = {
        { uid = "first", label = "First Name", type = "text", isRequired = true },
        { uid = "visibility", label = "Visibility", type = "select", options = { "show", "hide" }, value = "show" },
        photo
    } } } }
    local env = setmetatable({ source = 42 }, { __index = _G })
    env.Config = { LoadPlugin = function(_, callback) callback(config) end }
    env.CreateThread = function(callback) callback() end
    env.RegisterNetEvent = function(name, callback) h.events[name] = callback end
    env.AddEventHandler = function(name, callback) h.events[name] = callback end
    env.GetGameTimer = function() return h.now end
    env.GetCurrentResourceName = function() return "sonorancad" end
    env.AddPluginFilePath = function(path) h.registeredPaths[path] = true end
    env.CadApiGetServers = function() error("Base64 registration must not look up a public server URL") end
    env.exports = { sonorancad = setmetatable({
        CreateImageToken = function() return "session-token" end
    }, { __index = function(_, key) error("Unexpected export (file writes are forbidden): " .. key) end }) }
    env.os = { time = os.time, remove = function() error("Registration must not delete portrait files") end }
    env.getPlayerCadStatus = function(_, _, checks)
        equal(checks.link, true)
        equal(checks.unit, false)
        return { success = true, link = h.currentLink }
    end
    env.CadApiGetTemplates = function() return { success = true, data = template } end
    env.CadApiGetDatabaseSyncConfiguration = function()
        return { success = true, data = { enabled = false, character = false } }
    end
    env.TriggerClientEvent = function(name, target, payload)
        equal(target, 42)
        h.replies[#h.replies + 1] = { name = name, payload = payload }
        if name == "SonoranCAD::civreg::OpenForm" then h.form = payload end
        if name == "SonoranCAD::civreg::SubmissionResult" then h.result = payload end
    end
    env.CadApiCreateRecord = function(payload)
        h.requests[#h.requests + 1] = payload
        return h.apiResponse or { success = true, recordId = 123 }
    end
    env.sendClientError = function(_, key, detail) h.errorKey, h.errorDetail = key, detail end
    env.getErrorText = function(key) return key end
    env.CadApiLogFailure = function(name, response, payload)
        h.failures[#h.failures + 1] = { name = name, response = response, payload = payload }
    end
    env.logError = function(key, detail) error("Unexpected server error: " .. key .. ": " .. detail) end
    env.ApplyPluginNotificationOverrides = function(_, payload) return payload end
    env.NotifyPlayer = function(_, payload) h.notification = payload end
    assert(loadfile("sonorancad/submodules/civreg/sv_civreg.lua", "t", env))()
    h.events["SonoranCAD::civreg::RequestForm"]()
    assert(h.form, "registration form did not open")
    function h:submit(selfies, values, token)
        self.events["SonoranCAD::civreg::Submit"](token or self.form.session, values or { first = "Alex", visibility = "show" }, selfies or {})
    end
    return h
end

local function test(name, callback)
    local ok, err = pcall(callback)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
    print("PASS " .. name)
end

test("PNG is embedded unchanged in the linked account's CAD record", function()
    local h = harness()
    h:submit({ photo = PNG })
    equal(#h.requests, 1)
    equal(h.requests[1].replaceValues.photo, PNG)
    equal(h.requests[1].replaceValues.first, "Alex")
    equal(h.requests[1].communityUserId, "linked-account")
    equal(h.requests[1].recordTypeId, 7)
    equal(h.requests[1].useDictionary, true)
    equal(h.result.success, true)
    equal(h.result.recordId, 123)
    assert(h.registeredPaths.civreg, "previous URL-based portraits must remain accessible")
end)

test("JPEG is embedded unchanged", function()
    local h = harness()
    h:submit({ photo = JPEG })
    equal(h.requests[1].replaceValues.photo, JPEG)
end)

test("optional portrait can be omitted", function()
    local h = harness({ photo = function(field) field.isRequired = false end })
    h:submit()
    equal(h.result.success, true)
    equal(h.requests[1].replaceValues.photo, nil)
end)

test("required portrait cannot be injected through normal values", function()
    local h = harness()
    h:submit({}, { first = "Alex", photo = PNG })
    equal(#h.requests, 0)
    equal(h.errorKey, "CIVREG_SUBMISSION_INVALID")
    equal(h.result.message, "Portrait is required.")
end)

for name, mutate in pairs({
    ["read-only"] = function(field) field.readOnly = true end,
    ["supervisor"] = function(field) field.isSupervisor = true end,
    ["non-image"] = function(field) field.type = "text" end,
    ["hidden field"] = function(field)
        field.dependency = { fid = "visibility", acceptableValues = { "hide" } }
    end
}) do
    test(name .. " portrait cannot be submitted", function()
        local h = harness({ photo = mutate })
        h:submit({ photo = PNG })
        equal(#h.requests, 0)
        equal(h.errorKey, "CIVREG_SUBMISSION_INVALID")
    end)
end

test("unknown portrait field cannot be submitted", function()
    local h = harness()
    h:submit({ unknown = PNG })
    equal(#h.requests, 0)
    equal(h.errorKey, "CIVREG_SUBMISSION_INVALID")
end)

for name, value in pairs({
    ["external URL"] = "https://example.com/portrait.png",
    ["bare base64"] = "aGVsbG8=",
    ["unsupported MIME"] = "data:image/svg+xml;base64,AAAA",
    ["empty payload"] = "data:image/png;base64,",
    ["invalid alphabet"] = "data:image/png;base64,AA!A",
    ["whitespace"] = "data:image/png;base64,AA A",
    ["leading padding"] = "data:image/png;base64,=AAA",
    ["interior padding"] = "data:image/png;base64,AA=A",
    ["excess padding"] = "data:image/png;base64,A===",
    ["only padding"] = "data:image/png;base64,====",
    ["truncated quartet"] = "data:image/png;base64,AAA",
    ["non-string payload"] = { image = PNG }
}) do
    test(name .. " is rejected before the CAD request", function()
        local h = harness()
        h:submit({ photo = value })
        equal(#h.requests, 0)
        equal(h.result.success, false)
        equal(h.errorKey, "CIVREG_SUBMISSION_INVALID")
    end)
end

test("decoded size limit accepts the exact padded boundary", function()
    local h = harness({ limit = 1 })
    h:submit({ photo = "data:image/png;base64,AA==" })
    equal(h.result.success, true)
end)

test("decoded size is checked even when encoded length fits", function()
    local h = harness({ limit = 1 })
    h:submit({ photo = "data:image/png;base64,AAA=" })
    equal(#h.requests, 0)
    assert(h.result.message:find("size limit", 1, true))
end)

test("oversized encoded payload is rejected", function()
    local h = harness({ limit = 3 })
    h:submit({ photo = "data:image/png;base64,AAAAAAAA" })
    equal(#h.requests, 0)
    assert(h.result.message:find("size limit", 1, true))
end)

test("invalid portrait can be corrected in the same form", function()
    local h = harness()
    h:submit({ photo = "invalid" })
    h:submit({ photo = PNG })
    equal(#h.requests, 1)
    equal(h.result.success, true)
end)

test("CAD failure preserves retry and excludes image data from failure logging", function()
    local h = harness()
    h.apiResponse = { success = false, reason = "fixture rejection" }
    h:submit({ photo = PNG })
    equal(h.result.success, false)
    equal(h.errorKey, "CIVREG_CREATE_FAILED")
    equal(h.failures[1].payload.replaceValues, nil)
    h.apiResponse = nil
    h:submit({ photo = PNG })
    equal(#h.requests, 2)
    equal(h.requests[2].replaceValues.photo, PNG)
    equal(h.result.success, true)
end)

test("successful session cannot create a duplicate record", function()
    local h = harness()
    h:submit({ photo = PNG })
    h:submit({ photo = PNG })
    equal(#h.requests, 1)
    equal(h.result.success, false)
end)

test("submission rejects a session after the linked account changes", function()
    local h = harness()
    h.currentLink = "different-account"
    h:submit({ photo = PNG })
    equal(#h.requests, 0)
    equal(h.errorKey, "CIVREG_SUBMISSION_INVALID")
    equal(h.result.success, false)
end)

test("expired session cannot submit a portrait", function()
    local h = harness()
    h.now = h.now + 600001
    h:submit({ photo = PNG })
    equal(#h.requests, 0)
    equal(h.result.success, false)
end)

test("wrong session token cannot submit a portrait", function()
    local h = harness()
    h:submit({ photo = PNG }, nil, "forged-token")
    equal(#h.requests, 0)
    equal(h.result.success, false)
end)

print(("%d civreg server regression tests passed."):format(passed))
