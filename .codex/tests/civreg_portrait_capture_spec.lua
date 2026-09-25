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
        },
        liveMutations = 0
    }
    local function copySlots(slots)
        local copy = {}
        for key, value in pairs(slots) do
            copy[key] = { drawable = value.drawable, texture = value.texture, palette = value.palette }
        end
        return copy
    end
    local function stateFor(ped)
        return ped == 199 and h.clone or h
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
    env.DoesEntityExist = function(ped) return ped == 99 or (ped == 199 and h.clone and not h.cloneDeleted) end
    env.GetEntityModel = function(ped) return ped == 199 and options.cloneModel or 1885233650 end
    env.GetEntityCoords = function() return { x = 10.0, y = 20.0, z = 30.0 } end
    env.SetEntityCoordsNoOffset = function(ped, x, y, z)
        h.cloneMoved = { ped = ped, x = x, y = y, z = z }
    end
    env.FreezeEntityPosition = function(ped, frozen) h.cloneFrozen = ped == 199 and frozen end
    env.SetEntityCollision = function(ped, collision) h.cloneCollisionDisabled = ped == 199 and not collision end
    env.ClonePed = function(ped, isNetwork, scriptHost, copyHeadBlend)
        equal(ped, 99)
        equal(isNetwork, false)
        equal(scriptHost, false)
        equal(copyHeadBlend, true)
        if options.cloneFailure then return 0 end
        h.clone = { components = copySlots(h.components), props = copySlots(h.props) }
        if options.cloneMismatch then h.clone.components[2].drawable = 15 end
        return 199
    end
    env.DeleteEntity = function(ped)
        equal(ped, 199)
        h.cloneDeleted = true
    end
    env.GetPedDrawableVariation = function(ped, component)
        local value = stateFor(ped).components[component]
        return value and value.drawable or 0
    end
    env.GetPedTextureVariation = function(ped, component)
        local value = stateFor(ped).components[component]
        return value and value.texture or 0
    end
    env.GetPedPaletteVariation = function(ped, component)
        local value = stateFor(ped).components[component]
        return value and value.palette or 0
    end
    env.SetPedComponentVariation = function(ped, component, drawable, texture, palette)
        if ped == 99 then h.liveMutations = h.liveMutations + 1 end
        stateFor(ped).components[component] = {
            drawable = drawable, texture = texture, palette = palette
        }
    end
    env.GetPedPropIndex = function(ped, prop)
        local value = stateFor(ped).props[prop]
        return value and value.drawable or -1
    end
    env.GetPedPropTextureIndex = function(ped, prop)
        local value = stateFor(ped).props[prop]
        return value and value.texture or 0
    end
    env.ClearPedProp = function(ped, prop)
        if ped == 99 then h.liveMutations = h.liveMutations + 1 end
        stateFor(ped).props[prop] = { drawable = -1, texture = 0 }
    end
    env.GetPedFaceFeature = function() return 0 end
    env.Citizen = {
        PointerValueIntInitialized = function(value) return value end,
        PointerValueFloatInitialized = function(value) return value end,
        InvokeNative = function() return true, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0 end
    }
    env.GetPedHeadOverlayData = function() return true, 255, 0, 0, 0, 0.0 end
    env.GetPedEyeColor = function() return 0 end
    env.GetPedHairColor = function() return 0 end
    env.GetPedHairHighlightColor = function() return 0 end
    env.GetBase64 = function(ped)
        equal(ped, 199, "headshot must use the clone")
        h.duringCapture = {
            mask = h.clone.components[1].drawable,
            hair = h.clone.components[2].drawable,
            accessory = h.clone.components[7].drawable,
            hat = h.clone.props[0].drawable,
            glasses = h.clone.props[1].drawable,
            ears = h.clone.props[2].drawable,
            liveHat = h.props[0].drawable,
            liveGlasses = h.props[1].drawable
        }
        if options.captureError then error("fixture capture failure") end
        if options.liveHatChangeDuringCapture then
            h.props[0] = { drawable = options.liveHatChangeDuringCapture, texture = 9 }
        end
        if options.liveMaskChangeDuringCapture then
            h.components[1] = { drawable = options.liveMaskChangeDuringCapture, texture = 0, palette = 0 }
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
    env.debugLog = function(message) h.lastDebug = message end

    assert(loadfile("sonorancad/submodules/civreg/cl_civreg.lua", "t", env))()
    return h
end

local function assertCloneCapture(h)
    equal(h.duringCapture.mask, 0, "clone mask must be hidden")
    equal(h.duringCapture.hair, 9, "clone hair must be preserved")
    equal(h.duringCapture.accessory, 0, "clone accessory must be hidden")
    equal(h.duringCapture.hat, -1, "clone hat must be hidden")
    equal(h.duringCapture.glasses, -1, "clone glasses must be hidden")
    equal(h.duringCapture.ears, -1, "clone ear prop must be hidden")
    equal(h.duringCapture.liveHat, 8, "player hat must stay equipped")
    equal(h.duringCapture.liveGlasses, 6, "player glasses must stay equipped")
    equal(h.components[1].drawable, 12, "player mask must stay equipped")
    equal(h.props[0].drawable, 8, "player hat must stay equipped")
    equal(h.props[1].drawable, 6, "player glasses must stay equipped")
    equal(h.liveMutations, 0, "capture must not change the player ped")
    equal(h.cloneDeleted, true, "clone must be deleted")
    equal(h.cloneMoved.z, -70.0, "clone must be moved out of view")
    equal(h.cloneFrozen, true)
    equal(h.cloneCollisionDisabled, true)
end

test("database portrait captures an uncovered clone without changing player gear", function()
    local h = harness()
    h.events["SonoranCAD::civreg::CaptureDatabaseSyncMugshot"]({ token = "token-1" })
    assertCloneCapture(h)
    equal(h.latent.name, "SonoranCAD::civreg::DatabaseSyncMugshot")
    equal(h.latent.args[1], "token-1")
    equal(h.latent.args[2], "data:image/png;base64,fixture")
end)

test("manual portrait uses the same uncovered clone", function()
    local h = harness()
    local response
    h.nuiCallbacks.civregTakeSelfie({}, function(value) response = value end)
    assertCloneCapture(h)
    equal(response.ok, true)
    equal(response.image, "data:image/png;base64,fixture")
end)

test("capture errors delete the clone and leave player gear intact", function()
    local h = harness({ captureError = true })
    h.events["SonoranCAD::civreg::CaptureDatabaseSyncMugshot"]({ token = "token-2" })
    assertCloneCapture(h)
    equal(h.latent.args[2], nil)
end)

test("a live hat removal during capture is preserved and rejects the stale image", function()
    local h = harness({ liveHatChangeDuringCapture = -1 })
    h.events["SonoranCAD::civreg::CaptureDatabaseSyncMugshot"]({ token = "token-3" })
    equal(h.props[0].drawable, -1)
    equal(h.props[1].drawable, 6)
    equal(h.liveMutations, 0)
    equal(h.cloneDeleted, true)
    equal(h.latent.args[2], nil)
end)

test("a live mask removal during capture is preserved and rejects the stale image", function()
    local h = harness({ liveMaskChangeDuringCapture = 0 })
    h.events["SonoranCAD::civreg::CaptureDatabaseSyncMugshot"]({ token = "token-4" })
    equal(h.components[1].drawable, 0)
    equal(h.props[0].drawable, 8)
    equal(h.liveMutations, 0)
    equal(h.cloneDeleted, true)
    equal(h.latent.args[2], nil)
end)

test("a clone with mismatched appearance is rejected before headshot capture", function()
    local h = harness({ cloneMismatch = true })
    h.events["SonoranCAD::civreg::CaptureDatabaseSyncMugshot"]({ token = "token-5" })
    equal(h.duringCapture, nil)
    equal(h.latent.args[2], nil)
    equal(h.cloneDeleted, true)
    equal(h.liveMutations, 0)
end)

test("clone creation failure leaves the player unchanged", function()
    local h = harness({ cloneFailure = true })
    h.events["SonoranCAD::civreg::CaptureDatabaseSyncMugshot"]({ token = "token-6" })
    equal(h.duringCapture, nil)
    equal(h.latent.args[2], nil)
    equal(h.liveMutations, 0)
end)
test("headshot helper restores before conversion and cleans up restoration failures", function()
    local order = {}
    local now = 0
    local registered = false
    local env = setmetatable({}, { __index = _G })
    env.PlayerPedId = function() return 99 end
    env.DoesEntityExist = function() return true end
    env.IsPedheadshotValid = function(handle) return registered and handle == 7 end
    env.RegisterPedheadshot = function()
        registered = true
        return 7
    end
    env.IsPedheadshotReady = function() return true end
    env.GetPedheadshotTxdString = function() return "fixture_txd" end
    env.GetGameTimer = function() return now end
    env.Wait = function(milliseconds) now = now + (milliseconds or 0) end
    env.UnregisterPedheadshot = function() registered = false end
    env.SendNUIMessage = function()
        order[#order + 1] = "convert"
    end
    env.RegisterNUICallback = function() end
    env.exports = function() end

    assert(loadfile("sonorancad/core/headshots.lua", "t", env))()
    local result = env.GetBase64(99, function()
        order[#order + 1] = "restore"
        return true
    end)

    equal(result.success, false, "fixture conversion should time out")
    equal(order[1], "restore", "appearance must restore first")
    equal(order[2], "convert", "conversion must start after restoration")

    local restoreFailure = env.GetBase64(99, function()
        order[#order + 1] = "restore-failed"
        return false
    end)
    equal(restoreFailure.success, false)
    equal(restoreFailure.error, "Could not restore character appearance.")
    equal(order[3], "restore-failed")
    equal(order[4], nil, "failed restoration must not start conversion")
    equal(registered, false, "failed restoration must release the headshot")
end)

print(("%d CivReg portrait capture regression tests passed."):format(passed))
