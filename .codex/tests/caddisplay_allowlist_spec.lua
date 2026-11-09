-- Run from the repository root with Lua 5.4 or newer.
local plugin
local configEnv = {Config = {RegisterPluginConfig = function(_, config) plugin = config end}}
assert(loadfile('sonorancad/configuration/caddisplay_config.dist.lua', 't', configEnv))()
assert(plugin.general.useAllowlist == true, 'vehicle filtering must ship enabled')

local events, threads, notifications, opened = {}, {}, {}, {}
local currentVehicle, created, loaded, edited, closed = 20, 0, 0, 0, 0
local archetype = 'addon_cruiser'
local models = {[10] = 100, [20] = 200, [30] = 300}
local hashes = {police = 100, addon_cruiser = 200, builtin_cruiser = 300}
plugin.allowlistedCars = {'POLICE'}
plugin.builtinScreens = {{vehicle = 'builtin_cruiser', screenTexture = 'screen'}}

local env = setmetatable({}, {__index = _G})
env.Config = {LoadPlugin = function(_, callback) callback(plugin) end}
env.CreateThread = function(callback) threads[#threads + 1] = callback end
env.RegisterNetEvent = function(name, callback) events[name] = callback end
env.RegisterCommand = function() end
env.RegisterKeyMapping = function() end
env.RegisterPlayerCommandHelp = function() end
env.AddEventHandler = function() end
env.TriggerServerEvent = function() end
env.TriggerEvent = function() end
env.GetConvar = function(_, fallback) return fallback end
env.GetHashKey = function(name) return hashes[name:lower()] or 400 end
env.GetEntityModel = function(vehicle) return models[vehicle] end
env.GetEntitySpeed = function() return 0 end
env.GetEntityArchetypeName = function() return archetype end
env.GetDisplayNameFromVehicleModel = function() return 'UNRELATED_DISPLAY_LABEL' end
env.GetVehiclePedIsIn = function() return currentVehicle end
env.PlayerPedId = function() return 1 end
env.DoesEntityExist = function(entity) return entity ~= nil and entity ~= 0 end
env.VehToNet = function(vehicle) return vehicle end
env.ApplyPluginNotificationOverrides = function(_, notification) return notification end
env.NotifyClient = function(notification) notifications[#notifications + 1] = notification end
env.HasModelLoaded = function() loaded = loaded + 1; return true end
env.CreateObjectNoOffset = function() created = created + 1; return 500 + created end
env.SetEntityHeading = function() end
env.SetEntityCollision = function() end
env.FreezeEntityPosition = function() end
env.SonoranPlacementEditor = {IsActive = function() return false end}
env.WarMenu = {
    OpenMenu = function(menu) opened[#opened + 1] = menu end,
    CloseMenu = function() closed = closed + 1 end,
    ComboBox = function(label) return label == plugin.lang.modelComboBox end,
    Button = function() return true end
}

assert(loadfile('sonorancad/submodules/caddisplay/cl_caddisplay.lua', 't', env))()
threads[1]() -- Initialize the real client without running its background loops.
env.ensureDui = function() end -- DUI rendering is outside this eligibility regression.
env.getDisplayPreviewTransform = function() return {x = 0, y = 0, z = 0}, 0 end
local beginVehiclePlacementEditor = env.beginVehiclePlacementEditor
env.beginVehiclePlacementEditor = function() edited = edited + 1 end -- Observe requests to the mouse editor.

local function lastErrorContains(text)
    local notification = notifications[#notifications]
    assert(notification and notification.type == 'error', 'denial must be an error notification')
    assert(notification.message:find(text, 1, true), notification.message)
end

assert(not env.isVehicleBlocked(10), 'listed vehicle must be allowed')
assert(env.isVehicleBlocked(20), 'unlisted vehicle must be blocked')
assert(env.isVehicleBlocked(30), 'built-in screens must not bypass the allowlist')
plugin.general.useAllowlist = nil
assert(env.isVehicleBlocked(20), 'old configs must retain filtering')
plugin.general = nil
assert(env.isVehicleBlocked(20), 'missing general settings must retain filtering')
plugin.general = {useAllowlist = false, useAllowlistAsBlacklist = true}
assert(not env.isVehicleBlocked(10) and not env.isVehicleBlocked(20), 'disabled filtering must ignore both modes')
plugin.general.useAllowlist = true
assert(env.isVehicleBlocked(10) and not env.isVehicleBlocked(20), 'blacklist mode must reverse membership')
assert(env.isVehicleBlocked(30) == false, 'unlisted built-in screen must pass blacklist mode')
plugin.general.useAllowlistAsBlacklist = false

events['SonoranCAD::caddisplay::OpenMenu'](false, false)
assert(#opened == 0, 'normal menu access must reject an unlisted vehicle')
lastErrorContains('"addon_cruiser"')
lastErrorContains('allowlistedCars in caddisplay_config.lua')

events['SonoranCAD::caddisplay::OpenMenu'](true, true)
assert(opened[#opened] == 'caddisplay_world_menu', 'world admin must retain access to station displays')
local menuCount = #opened
env.spawningCadDisplay()
assert(created == 0 and loaded == 0, 'world admin must not create or load a vehicle laptop in an unlisted car')
assert(#opened == menuCount, 'blocked spawn must not open the attachment menu')
lastErrorContains('"addon_cruiser"')
assert(env.spawnDisplay(20) == nil and created == 0, 'direct spawn path must also enforce eligibility')

-- New language keys are optional for existing installations.
plugin.lang.vehNotAllowlisted = nil
plugin.lang.vehNotAllowlistedUnknown = nil
plugin.lang.vehBlacklisted = nil
env.notifyVehicleBlocked(20)
lastErrorContains('"addon_cruiser"')
for _, unavailable in ipairs({'', 'NULL', 'UNRELATED_DISPLAY_LABEL'}) do
    archetype = unavailable
    env.notifyVehicleBlocked(20)
    lastErrorContains('modelName in vehicles.meta')
    assert(not notifications[#notifications].message:find('"' .. unavailable .. '"', 1, true),
        'must not present an unavailable or mismatched name as a spawn code')
end
archetype = nil
env.notifyVehicleBlocked(20)
lastErrorContains('modelName in vehicles.meta')
archetype = 'addon_cruiser'

plugin.general.useAllowlistAsBlacklist = true
currentVehicle = 10
assert(env.spawnDisplay(10) == nil and created == 0, 'blacklisted vehicle must not spawn a laptop')
lastErrorContains('Remove')
lastErrorContains('blacklist mode')
plugin.general.useAllowlistAsBlacklist = false

env.spawningCadDisplay()
assert(created == 1 and edited == 1, 'listed car must retain normal spawning and open the mouse editor')
-- A player can switch vehicles after opening the menu or spawning a preview.
currentVehicle = 20
menuCount = #opened
env.spawningCadDisplay()
assert(created == 1 and #opened == menuCount, 'vehicle change must be checked on spawn')
env.attachingCadDisplay()
assert(edited == 1 and closed == 1, 'vehicle change must also block attachment and close the menu')
lastErrorContains('"addon_cruiser"')
beginVehiclePlacementEditor()
assert(edited == 1 and closed == 2, 'direct editor entry must reject an unlisted vehicle')
lastErrorContains('"addon_cruiser"')

plugin.general.useAllowlist = false
env.spawningCadDisplay()
assert(created == 2 and edited == 2, 'disabled filtering must allow an unlisted car')
env.attachingCadDisplay()
assert(edited == 3, 'disabled filtering must allow attachment')
currentVehicle = 0
assert(env.spawnDisplay() == nil and created == 2, 'spawning still requires a vehicle')
assert(notifications[#notifications].message == plugin.lang.notInVeh)
events['SonoranCAD::caddisplay::OpenMenu'](true, true)
assert(opened[#opened] == 'caddisplay_world_menu', 'station menu access must remain available outside vehicles')

print('CAD display allowlist tests passed')
