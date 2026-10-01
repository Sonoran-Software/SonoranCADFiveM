-- Run from the repository root with Lua 5.4 or newer.
local passed = 0
local function test(name, callback)
    local ok, err = pcall(callback)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
    print("PASS " .. name)
end

local function harness()
    local h = { now = 0, registrations = 0, releases = {}, messages = {}, events = {}, logs = {} }
    local env = setmetatable({}, { __index = _G })
    env.PlayerPedId = function() return 99 end
    env.DoesEntityExist = function() return true end
    env.GetGameTimer = function() return h.now end
    env.Wait = function(ms)
        h.now = h.now + ms
        if h.onWait then h.onWait() end
    end
    env.RegisterPedheadshot = function()
        h.registrations = h.registrations + 1
        h.registered = true
        return 7 -- Simulate the game recycling the same texture slot.
    end
    env.IsPedheadshotValid = function() return true end
    env.IsPedheadshotReady = function() return not h.notReady end
    env.GetPedheadshotTxdString = function() return "pedheadshot_7" end
    env.UnregisterPedheadshot = function(handle)
        assert(handle == 7, "must never release another resource's headshots")
        h.registered = false
        h.releases[#h.releases + 1] = handle
    end
    env.SendNUIMessage = function(message)
        h.messages[#h.messages + 1] = message
        if h.onMessage then h.onMessage(message) end
    end
    env.RegisterNUICallback = function(_, callback) h.callback = callback end
    env.AddEventHandler = function(name, callback) h.events[name] = callback end
    env.GetCurrentResourceName = function() return "sonorancad" end
    env.debugLog = function(message) h.logs[#h.logs + 1] = message end
    env.exports = function() end
    assert(loadfile("sonorancad/core/headshots.lua", "t", env))()
    h.capture = env.GetBase64
    function h:reply(message, image)
        local acknowledged = false
        self.callback({ id = message.id, handle = message.handle, base64 = image }, function()
            acknowledged = true
        end)
        assert(acknowledged)
    end
    return h
end

test("recycled headshot textures get unique URLs and fresh image data", function()
    local h = harness()
    h.onMessage = function(message) h:reply(message, "data:image/png;base64,image" .. h.registrations) end
    local first, second = h.capture(99), h.capture(99)
    assert(first.success and second.success)
    assert(first.base64 ~= second.base64)
    assert(h.messages[1].img ~= h.messages[2].img)
    assert(h.messages[1].img:find("?capture=", 1, true))
    assert(h.registrations == 2 and #h.releases == 2)
    assert(not table.concat(h.logs):find("data:image", 1, true))
end)

test("late callbacks cannot release or populate a newer recycled handle", function()
    local h = harness()
    assert(not h.capture(99).success)
    local expired = h.messages[1]
    h.onMessage = function(message)
        h:reply(expired, "old image")
        assert(h.registered and #h.releases == 1)
        h:reply(message, "new image")
    end
    local result = h.capture(99)
    assert(result.success and result.base64 == "new image")
    assert(#h.releases == 2)
end)

test("duplicate callbacks cannot overwrite a completed conversion", function()
    local h = harness()
    h.onMessage = function(message)
        h:reply(message, "first image")
        h:reply(message, "duplicate image")
        assert(#h.releases == 0, "capture owns cleanup until it consumes the image")
    end
    local result = h.capture(99)
    assert(result.base64 == "first image")
    h:reply(h.messages[1], "late duplicate")
    assert(#h.releases == 1)
end)

test("mismatched handles cannot satisfy a conversion", function()
    local h = harness()
    h.onMessage = function(message)
        h:reply({ id = message.id, handle = 8 }, "wrong image")
    end
    assert(not h.capture(99).success)
    assert(#h.releases == 1)
end)

test("headshot readiness timeout releases only the owned handle", function()
    local h = harness()
    h.notReady = true
    assert(not h.capture(99).success)
    assert(#h.messages == 0 and #h.releases == 1)
end)

test("resource stop releases an in-flight headshot exactly once", function()
    local h = harness()
    h.onWait = function() h.events.onClientResourceStop("sonorancad") end
    assert(not h.capture(99).success)
    assert(#h.releases == 1)
end)

print(("%d headshot regression tests passed."):format(passed))
