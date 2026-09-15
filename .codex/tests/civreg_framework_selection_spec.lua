-- Run from the repository root with Lua 5.4 or newer.
-- Exercises framework character-selection hooks with isolated FiveM boundaries.
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

local function harness(framework, options)
    options = options or {}
    local h = { events = {}, serverEvents = {}, now = 0, waits = {} }
    local env = setmetatable({}, { __index = _G })
    env.Config = {
        LoadPlugin = function(_, callback)
            callback({
                enabled = true,
                commandName = "civreg",
                language = { helpMsg = "help" }
            })
        end,
        GetPluginConfig = function()
            return { usingQBCore = framework ~= "esx" }
        end
    }
    env.CreateThread = function(callback) callback() end
    env.GetGameTimer = function() return h.now end
    env.Wait = function(milliseconds)
        h.waits[#h.waits + 1] = milliseconds
        h.now = h.now + milliseconds
    end
    env.PlayerId = function() return 1 end
    env.PlayerPedId = function() return 99 end
    env.NetworkIsPlayerActive = function() return options.neverReady ~= true end
    env.DoesEntityExist = function() return options.neverReady ~= true end
    env.IsEntityVisible = function() return options.neverReady ~= true end
    env.HasCollisionLoadedAroundEntity = function() return options.neverReady ~= true end
    env.IsScreenFadedIn = function() return options.neverReady ~= true end
    env.GetResourceState = function(name)
        if framework == "esx" then
            return name == "es_extended" and "started" or "missing"
        end
        return name == "qb-core" and "started" or "missing"
    end
    env.exports = {
        ["qb-core"] = {
            GetCoreObject = function()
                return {
                    Functions = {
                        GetPlayerData = function()
                            return options.alreadyLoaded and { citizenid = "QB-123" } or nil
                        end
                    }
                }
            end
        }
    }
    env.RegisterCommand = function() end
    env.TriggerEvent = function() end
    env.RegisterPlayerCommandHelp = function() end
    env.RegisterNetEvent = function(name, callback) h.events[name] = callback end
    env.AddEventHandler = function(name, callback) h.events[name] = callback end
    env.RegisterNUICallback = function() end
    env.TriggerServerEvent = function(name)
        h.serverEvents[#h.serverEvents + 1] = name
    end

    assert(loadfile("sonorancad/submodules/civreg/cl_civreg.lua", "t", env))()
    return h
end

test("QBCore selection settles after the player is fully spawned", function()
    local h = harness("qbcore")
    h.events["QBCore:Client:OnPlayerLoaded"]()
    equal(#h.serverEvents, 1)
    equal(h.serverEvents[1], "SonoranCAD::civreg::FrameworkCharacterSelected")
    equal(h.waits[1], 3000)
    equal(h.now, 3000)
end)

test("an already-loaded QBCore character is captured after resource restart", function()
    local h = harness("qbcore", { alreadyLoaded = true })
    equal(#h.serverEvents, 1)
    equal(h.serverEvents[1], "SonoranCAD::civreg::FrameworkCharacterSelected")
    equal(h.waits[1], 3000)
end)

test("ESX selection waits for the selected character ped to spawn", function()
    local h = harness("esx")
    h.events["esx:playerLoaded"]()
    equal(#h.serverEvents, 0)
    h.events["esx:onPlayerSpawn"]()
    equal(#h.serverEvents, 1)
    equal(h.serverEvents[1], "SonoranCAD::civreg::FrameworkCharacterSelected")
    h.events["esx:onPlayerSpawn"]()
    equal(#h.serverEvents, 1)
end)

test("framework selection times out when the player never fully spawns", function()
    local h = harness("qbcore", { neverReady = true })
    h.events["QBCore:Client:OnPlayerLoaded"]()
    equal(#h.serverEvents, 0)
    equal(h.now, 30000)
end)

print(("%d CivReg framework selection regression tests passed."):format(passed))
