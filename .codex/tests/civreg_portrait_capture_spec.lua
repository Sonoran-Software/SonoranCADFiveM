-- Run from the repository root with Lua 5.4 or newer.
-- Exercises temporary portrait appearance changes with isolated FiveM boundaries.
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

local function harness(options)
    options = options or {}
    local h = {
        events = {},
        nuiCallbacks = {},
        components = {
            [1] = { drawable = 12, texture = 3, palette = 2 },
            [2] = { drawable = 9, texture = 1, palette = 0 },
            [7] = { drawable = 5, texture = 4, palette = 1 }
        },
        props = {
            [0] = { drawable = 8, texture = 2 },
            [1] = { drawable = 6, texture = 1 },
            [2] = { drawable = 4, texture = 3 }
        }
    }
    local env = setmetatable({}, { __index = _G })
    env.Config = {
        LoadPlugin = function(_, callback)
            callback({
                enabled = true,
                commandName = "civreg",
                language = { helpMsg = "help" }
            })
        end,
        GetPluginConfig = function() return { usingQBCore = true } end
    }
    env.CreateThread = function(callback) callback() end
    env.Wait = function() end
    env.GetGameTimer = function() return 0 end
    env.GetResourceState = function(name)
        return name == "qb-core" and "started" or "missing"
    end
    env.exports = {
        ["qb-core"] = {
            GetCoreObject = function()
                return { Functions = { GetPlayerData = function() return nil end } }
            end
        }
    }
    env.PlayerId = function() return 1 end
    env.PlayerPedId = function() return 99 end
    env.DoesEntityExist = function() return true end
    env.NetworkIsPlayerActive = function() return true end
    env.IsEntityVisible = function() return true end
    env.HasCollisionLoadedAroundEntity = function() return true end
    env.IsScreenFadedIn = function() return true end
    env.GetEntityModel = function() return 1885233650 end
    env.GetPedDrawableVariation = function(_, component)
        return h.components[component] and h.components[component].drawable or 0
    end
    env.GetPedTextureVariation = function(_, component)
        return h.components[component] and h.components[component].texture or 0
    end
    env.GetPedPaletteVariation = function(_, component)
        return h.components[component] and h.components[component].palette or 0
    end
    env.SetPedComponentVariation = function(_, component, drawable, texture, palette)
        h.components[component] = { drawable = drawable, texture = texture, palette = palette }
    end
    env.GetPedPropIndex = function(_, prop)
        return h.props[prop] and h.props[prop].drawable or -1
    end
    env.GetPedPropTextureIndex = function(_, prop)
        return h.props[prop] and h.props[prop].texture or 0
    end
    env.ClearPedProp = function(_, prop)
        h.props[prop] = { drawable = -1, texture = 0 }
    end
    env.SetPedPropIndex = function(_, prop, drawable, texture)
        h.props[prop] = { drawable = drawable, texture = texture }
    end
    env.GetPedFaceFeature = function() return 0 end
    env.GetBase64 = function()
        h.duringCapture = {
            mask = h.components[1].drawable,
            hair = h.components[2].drawable,
            accessory = h.components[7].drawable,
            hat = h.props[0].drawable,
            glasses = h.props[1].drawable,
            ears = h.props[2].drawable
        }
        if options.captureError then
            error("fixture capture failure")
        end
        return { success = true, base64 = "data:image/png;base64,fixture" }
    end
    env.RegisterCommand = function() end
    env.TriggerEvent = function() end
    env.RegisterPlayerCommandHelp = function() end
    env.RegisterNetEvent = function(name, callback) h.events[name] = callback end
    env.AddEventHandler = function(name, callback) h.events[name] = callback end
    env.RegisterNUICallback = function(name, callback) h.nuiCallbacks[name] = callback end
    env.SetNuiFocus = function() end
    env.SetNuiFocusKeepInput = function() end
    env.SendNUIMessage = function() end
    env.GetCurrentResourceName = function() return "sonorancad" end
    env.TriggerServerEvent = function() end
    env.TriggerLatentServerEvent = function(name, bandwidth, ...)
        h.latent = { name = name, bandwidth = bandwidth, args = { ... } }
    end

    assert(loadfile("sonorancad/submodules/civreg/cl_civreg.lua", "t", env))()
    return h
end

local function assertHiddenAndRestored(h)
    equal(h.duringCapture.mask, 0, "mask must be hidden")
    equal(h.duringCapture.hair, 9, "hair must be preserved")
    equal(h.duringCapture.accessory, 0, "neck accessory must be hidden")
    equal(h.duringCapture.hat, -1, "hat must be hidden")
    equal(h.duringCapture.glasses, -1, "glasses must be hidden")
    equal(h.duringCapture.ears, -1, "ear prop must be hidden")
    equal(h.components[1].drawable, 12, "mask must be restored")
    equal(h.components[1].texture, 3, "mask texture must be restored")
    equal(h.components[1].palette, 2, "mask palette must be restored")
    equal(h.components[2].drawable, 9, "hair must remain unchanged")
    equal(h.components[7].drawable, 5, "neck accessory must be restored")
    equal(h.props[0].drawable, 8, "hat must be restored")
    equal(h.props[1].drawable, 6, "glasses must be restored")
    equal(h.props[2].drawable, 4, "ear prop must be restored")
end

test("database portraits hide face coverings and restore the exact appearance", function()
    local h = harness()
    h.events["SonoranCAD::civreg::CaptureDatabaseSyncMugshot"]({ token = "token-1" })
    assertHiddenAndRestored(h)
    equal(h.latent.name, "SonoranCAD::civreg::DatabaseSyncMugshot")
    equal(h.latent.args[1], "token-1")
    equal(h.latent.args[2], "data:image/png;base64,fixture")
end)

test("manual portraits use the same temporary face-covering removal", function()
    local h = harness()
    local response
    h.nuiCallbacks.civregTakeSelfie({}, function(value) response = value end)
    assertHiddenAndRestored(h)
    equal(response.ok, true)
    equal(response.image, "data:image/png;base64,fixture")
end)

test("capture failures still restore the exact appearance", function()
    local h = harness({ captureError = true })
    h.events["SonoranCAD::civreg::CaptureDatabaseSyncMugshot"]({ token = "token-2" })
    assertHiddenAndRestored(h)
    equal(h.latent.args[1], "token-2")
    equal(h.latent.args[2], nil)
    equal(h.latent.args[3], "Could not capture your character portrait.")
end)

print(("%d CivReg portrait capture regression tests passed."):format(passed))
