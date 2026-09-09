-- Run from the repository root with Lua 5.4 or newer.
-- Verifies that an old CAD account UUID cannot resolve after unlinking.
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

test("account UUID lookup requires a currently linked player", function()
    local events = {}
    local registeredExports = {}
    local now = 10000
    local linkResponse = {
        success = true,
        data = {
            linked = true,
            communityUserId = "linked-player",
            accountUuid = "00000000-0000-0000-0000-000000000000"
        }
    }

    local callableExports = setmetatable({}, {
        __call = function(_, name, callback)
            registeredExports[name] = callback
        end
    })
    local env = setmetatable({ source = 42 }, { __index = _G })
    env.Config = {
        primaryIdentifier = "license",
        linkCommand = "link",
        allowPopupCloseWhenUnlinked = true
    }
    env.CreateThread = function(callback) callback() end
    env.GetResourceState = function(name) return name == "tablet" and "started" or "missing" end
    env.GetGameTimer = function() return now end
    env.GetIdentifiers = function(player) return { license = "license:" .. tostring(player) } end
    env.GetPlayers = function() return { "42" } end
    env.RegisterNetEvent = function() end
    env.AddEventHandler = function(name, callback) events[name] = callback end
    env.TriggerClientEvent = function() end
    env.exports = callableExports
    env.debugLog = function() end
    env.infoLog = function() end
    env.warnLog = function() end
    env.logError = function() end
    env.CadApiCheckCommunityLink = function()
        return linkResponse
    end

    assert(loadfile("sonorancad/core/linking_sv.lua", "t", env))()

    equal(env.GetPlayerCommunityUserId(42), "linked-player")
    equal(env.GetSourceByCadAccountUuid("00000000-0000-0000-0000-000000000000"), 42)
    equal(registeredExports.getSourceByCadAccountUuid(
        "00000000-0000-0000-0000-000000000000"), 42)

    linkResponse = {
        success = true,
        data = {
            linked = false,
            communityUserId = "linked-player"
        }
    }
    now = now + 30001
    events["SonoranCAD::links:Poll"]()

    equal(env.GetSourceByCadAccountUuid("00000000-0000-0000-0000-000000000000"), nil)
end)

print(("%d linking account UUID regression test passed."):format(passed))
