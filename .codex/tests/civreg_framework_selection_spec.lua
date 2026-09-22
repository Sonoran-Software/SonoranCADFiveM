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
    local h = {
        events = {},
        serverEvents = {},
        now = 0,
        waits = {},
        playerLoaded = false,
        characterId = framework == "esx" and "license:esx-123" or "QB-123",
        components = {},
        componentTextures = {},
        componentPalettes = {},
        props = {},
        propTextures = {},
        headBlend = {
            shapeFirst = 0,
            shapeSecond = 0,
            shapeThird = 0,
            skinFirst = 0,
            skinSecond = 0,
            skinThird = 0,
            shapeMix = 0.0,
            skinMix = 0.0,
            thirdMix = 0.0
        },
        headOverlays = {},
        eyeColor = 0,
        hairColor = 0,
        hairHighlightColor = 0,
        tattoos = {
            ZONE_HEAD = {
                { collection = "collection-a", hashMale = "male-a", hashFemale = "female-a" },
                { collection = "collection-b", hashMale = "male-b", hashFemale = "female-b" }
            }
        }
    }
    for component = 0, 11 do
        h.components[component] = component
        h.componentTextures[component] = 0
        h.componentPalettes[component] = 0
    end
    for prop = 0, 7 do
        h.props[prop] = -1
        h.propTextures[prop] = 0
    end
    for overlay = 0, 12 do
        h.headOverlays[overlay] = {
            value = 255,
            colorType = 0,
            firstColor = 0,
            secondColor = 0,
            opacity = 0.0
        }
    end
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
        if options.qbAppearanceReadyAt and not h.qbAppearanceReady and
            h.now >= options.qbAppearanceReadyAt then
            h.qbAppearanceReady = true
            h.events["qb-clothing:client:loadPlayerClothing"]()
        end
        if options.appearanceChangeAt and not h.appearanceChanged and
            h.now >= options.appearanceChangeAt then
            h.appearanceChanged = true
            h.components[1] = h.components[1] + 10
        end
        if options.facialAppearanceChangeAt and not h.facialAppearanceChanged and
            h.now >= options.facialAppearanceChangeAt then
            h.facialAppearanceChanged = true
            h.headBlend.shapeFirst = h.headBlend.shapeFirst + 1
            h.headOverlays[4].value = 2
            h.headOverlays[4].firstColor = 3
            h.headOverlays[4].opacity = 0.8
            h.eyeColor = 4
            h.hairColor = 5
            h.hairHighlightColor = 6
        end
        if options.tattooAppearanceChangeAt and not h.tattooAppearanceChanged and
            h.now >= options.tattooAppearanceChangeAt then
            h.tattooAppearanceChanged = true
            h.tattoos = {
                ZONE_HEAD = {
                    { collection = "collection-c", hashMale = "male-c", hashFemale = "female-c" },
                    { collection = "collection-d", hashMale = "male-d", hashFemale = "female-d" }
                }
            }
        end
        if options.tattooOrderChangeAt and not h.tattooOrderChanged and
            h.now >= options.tattooOrderChangeAt then
            h.tattooOrderChanged = true
            local tattoos = h.tattoos.ZONE_HEAD
            tattoos[1], tattoos[2] = tattoos[2], tattoos[1]
        end
        if options.characterChangeAt and not h.characterChanged and
            h.now >= options.characterChangeAt then
            h.characterChanged = true
            h.characterId = framework == "esx" and "license:esx-999" or "QB-999"
        end
    end
    env.PlayerId = function() return 1 end
    env.PlayerPedId = function() return 99 end
    env.NetworkIsPlayerActive = function() return options.neverReady ~= true end
    env.DoesEntityExist = function() return options.neverReady ~= true end
    env.IsEntityVisible = function() return options.neverReady ~= true end
    env.HasCollisionLoadedAroundEntity = function() return options.neverReady ~= true end
    env.IsScreenFadedIn = function() return options.neverReady ~= true end
    env.GetEntityModel = function() return 1885233650 end
    env.GetPedDrawableVariation = function(_, component) return h.components[component] end
    env.GetPedTextureVariation = function(_, component) return h.componentTextures[component] end
    env.GetPedPaletteVariation = function(_, component) return h.componentPalettes[component] end
    env.GetPedPropIndex = function(_, prop) return h.props[prop] end
    env.GetPedPropTextureIndex = function(_, prop) return h.propTextures[prop] end
    env.GetPedFaceFeature = function(_, feature) return feature / 100 end
    env.Citizen = {
        PointerValueIntInitialized = function(value) return value end,
        PointerValueFloatInitialized = function(value) return value end,
        InvokeNative = function()
            local value = h.headBlend
            return true, value.shapeFirst, value.shapeSecond, value.shapeThird,
                value.skinFirst, value.skinSecond, value.skinThird,
                value.shapeMix, value.skinMix, value.thirdMix
        end
    }
    env.GetPedHeadOverlayData = function(_, overlay)
        local value = h.headOverlays[overlay]
        return true, value.value, value.colorType, value.firstColor,
            value.secondColor, value.opacity
    end
    env.GetPedEyeColor = function() return h.eyeColor end
    env.GetPedHairColor = function() return h.hairColor end
    env.GetPedHairHighlightColor = function() return h.hairHighlightColor end
    env.GetResourceState = function(name)
        if framework == "esx" then
            return name == "es_extended" and "started" or "missing"
        end
        if name == "qb-clothing" and options.qbClothing then return "started" end
        if name == "illenium-appearance" and options.illenium then return "started" end
        if name == "fivem-appearance" and options.fivemAppearance then return "started" end
        return name == "qb-core" and "started" or "missing"
    end
    env.exports = {
        ["qb-core"] = {
            GetCoreObject = function()
                return {
                    Functions = {
                        GetPlayerData = function()
                            return (options.alreadyLoaded or h.playerLoaded) and
                                { citizenid = h.characterId } or nil
                        end
                    }
                }
            end
        },
        ["es_extended"] = {
            getSharedObject = function()
                return {
                    GetPlayerData = function()
                        return (options.alreadyLoaded or h.playerLoaded) and
                            { identifier = h.characterId } or nil
                    end
                }
            end
        },
        ["illenium-appearance"] = {
            getPedAppearance = function()
                if options.appearanceExportFails then error("appearance export unavailable") end
                return { tattoos = h.tattoos }
            end
        },
        ["fivem-appearance"] = {
            getPedAppearance = function()
                if options.appearanceExportFails then error("appearance export unavailable") end
                return { tattoos = h.tattoos }
            end
        }
    }
    env.RegisterCommand = function() end
    env.TriggerEvent = function() end
    env.RegisterPlayerCommandHelp = function() end
    env.RegisterNetEvent = function(name, callback)
        if name == "QBCore:Client:OnPlayerLoaded" or name == "esx:playerLoaded" then
            h.events[name] = function(...)
                h.playerLoaded = true
                return callback(...)
            end
        else
            h.events[name] = callback
        end
    end
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
    equal(h.waits[1], 250)
    equal(h.now, 3000)
end)

test("an already-loaded QBCore character is captured after resource restart", function()
    local h = harness("qbcore", { alreadyLoaded = true })
    equal(#h.serverEvents, 1)
    equal(h.serverEvents[1], "SonoranCAD::civreg::FrameworkCharacterSelected")
    equal(h.waits[1], 250)
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

test("an already-loaded ESX character is captured after resource restart", function()
    local h = harness("esx", { alreadyLoaded = true })
    equal(#h.serverEvents, 1)
    equal(h.serverEvents[1], "SonoranCAD::civreg::FrameworkCharacterSelected")
    equal(h.waits[1], 250)
end)

test("framework selection times out when the player never fully spawns", function()
    local h = harness("qbcore", { neverReady = true })
    h.events["QBCore:Client:OnPlayerLoaded"]()
    equal(#h.serverEvents, 0)
    equal(h.now, 30000)
end)

test("QBCore waits for qb-clothing to apply the selected appearance", function()
    local h = harness("qbcore", {
        qbClothing = true,
        qbAppearanceReadyAt = 1000
    })
    h.events["QBCore:Client:OnPlayerLoaded"]()
    equal(#h.serverEvents, 1)
    equal(h.now, 4000)
end)

test("QBCore fails closed when qb-clothing never reports an applied appearance", function()
    local h = harness("qbcore", { qbClothing = true })
    h.events["QBCore:Client:OnPlayerLoaded"]()
    equal(#h.serverEvents, 0)
    equal(h.now, 30000)
end)

test("QBCore waits for an alternate appearance provider to replace the placeholder", function()
    local h = harness("qbcore", {
        illenium = true,
        appearanceChangeAt = 1000
    })
    h.events["QBCore:Client:OnPlayerLoaded"]()
    equal(#h.serverEvents, 1)
    equal(h.now, 4000)
end)

test("QBCore detects alternate-provider changes to facial appearance only", function()
    local h = harness("qbcore", {
        fivemAppearance = true,
        facialAppearanceChangeAt = 1000
    })
    h.events["QBCore:Client:OnPlayerLoaded"]()
    equal(#h.serverEvents, 1)
    equal(h.now, 4000)
end)

test("QBCore detects alternate-provider changes to tattoo identities only", function()
    local h = harness("qbcore", {
        illenium = true,
        tattooAppearanceChangeAt = 1000
    })
    h.events["QBCore:Client:OnPlayerLoaded"]()
    equal(#h.serverEvents, 1)
    equal(h.now, 4000)
end)

test("QBCore ignores alternate-provider tattoo application order changes", function()
    local h = harness("qbcore", {
        fivemAppearance = true,
        tattooOrderChangeAt = 1000
    })
    h.events["QBCore:Client:OnPlayerLoaded"]()
    equal(#h.serverEvents, 1)
    equal(h.now, 18000)
end)

test("QBCore tolerates an unavailable alternate-provider appearance export", function()
    local h = harness("qbcore", {
        illenium = true,
        appearanceExportFails = true
    })
    h.events["QBCore:Client:OnPlayerLoaded"]()
    equal(#h.serverEvents, 1)
    equal(h.now, 18000)
end)

test("QBCore accepts a stable unchanged alternate-provider appearance after a grace period", function()
    local h = harness("qbcore", { illenium = true })
    h.events["QBCore:Client:OnPlayerLoaded"]()
    equal(#h.serverEvents, 1)
    equal(h.now, 18000)
end)

test("QBCore restarts stability when alternate-provider appearance changes during the grace fallback", function()
    local h = harness("qbcore", {
        fivemAppearance = true,
        appearanceChangeAt = 16000
    })
    h.events["QBCore:Client:OnPlayerLoaded"]()
    equal(#h.serverEvents, 1)
    equal(h.now, 19000)
end)

test("QBCore cancels capture if the active citizen changes while loading", function()
    local h = harness("qbcore", { characterChangeAt = 1000 })
    h.events["QBCore:Client:OnPlayerLoaded"]()
    equal(#h.serverEvents, 0)
    equal(h.now, 30000)
end)

print(("%d CivReg framework selection regression tests passed."):format(passed))
