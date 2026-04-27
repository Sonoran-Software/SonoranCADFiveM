--[[
    Sonaran CAD Plugins

    Plugin Name: dispatchnotify
    Creator: SonoranCAD
    Description: Show incoming 911 calls and allow units to attach to them.

    Put all client-side logic in this file.
]]

local trackingCall = false
local trackingID = nil

CreateThread(function() Config.LoadPlugin("dispatchnotify", function(pluginConfig)

    if pluginConfig.enabled then
        if pluginConfig.commandName == nil or pluginConfig.commandName == "" then
            pluginConfig.commandName = "dn"
        end
        if pluginConfig.respondSubcommandName == nil or pluginConfig.respondSubcommandName == "" then
            pluginConfig.respondSubcommandName = pluginConfig.respondCommandName or "respond"
        end
        if pluginConfig.unitNotifyToggleSubcommand == nil or pluginConfig.unitNotifyToggleSubcommand == "" then
            pluginConfig.unitNotifyToggleSubcommand = pluginConfig.unitNotifyToggleCommand or "notify"
        end
        if pluginConfig.addNoteSubcommand == nil or pluginConfig.addNoteSubcommand == "" then
            pluginConfig.addNoteSubcommand = pluginConfig.addNoteCommand or "note"
        end
        if pluginConfig.addPlateSubcommand == nil or pluginConfig.addPlateSubcommand == "" then
            pluginConfig.addPlateSubcommand = pluginConfig.addPlateCommand or "plate"
        end
        if pluginConfig.gpsToggleSubcommand == nil or pluginConfig.gpsToggleSubcommand == "" then
            pluginConfig.gpsToggleSubcommand = "gps"
        end

        local gpsLock = true
        local lastPostal = nil
        local lastCoords = nil
        local currentCallId = nil
        local lockedPlate = nil
        local gpsBlip = false

        RegisterNetEvent("SonoranCAD::dispatchnotify:SetGps")
        AddEventHandler("SonoranCAD::dispatchnotify:SetGps", function(postal)
            -- try to set postal via command?
            if gpsLock then
                ExecuteCommand("postal "..tostring(postal))
                if lastPostal ~= nil and lastPostal ~= postal then
                    TriggerEvent("chat:addMessage", {args = {"^0[ ^2Dispatch ^0] ", ("Call GPS coordinates updated (%s)."):format(postal)}})
                    lastPostal = postal
                else
                    lastPostal = postal
                    TriggerEvent("chat:addMessage", {args = {"^0[ ^2Dispatch ^0] ", ("GPS coordinates set to caller's last known postal (%s)."):format(postal)}})
                end
            end
        end)

        RegisterNetEvent("SonoranCAD::dispatchnotify:UnsetGps")
        AddEventHandler("SonoranCAD::dispatchnotify:UnsetGps", function()
            if gpsBlip then
                TriggerEvent("chat:addMessage", {args = {"^0[ ^2Dispatch ^0] ", "You are now on scene. Disabling GPS."}})
                RemoveBlip(gpsBlip)
                gpsBlip = nil
            elseif lastPostal ~= nil then
                ExecuteCommand("postal")
                lastPostal = nil
                TriggerEvent("chat:addMessage", {args = {"^0[ ^2Dispatch ^0] ", "You are now on scene. Disabling GPS."}})
            end
        end)

        RegisterNetEvent("SonoranCAD::dispatchnotify:SetLocation")
        AddEventHandler("SonoranCAD::dispatchnotify:SetLocation", function(coords)
            if coords == nil then
                return warnLog("SetLocation was called, but no coordinates were found")
            else
                debugLog(("In SetLocation: x: %s y: %s z: %s"):format(coords.x, coords.y, coords.z))
            end
            if gpsLock then
                if gpsBlip then RemoveBlip(gpsBlip) end
                gpsBlip = AddBlipForCoord(tonumber(coords.x), tonumber(coords.y), 0.0)
                SetBlipRouteColour(gpsBlip, 3)
                SetBlipRoute(gpsBlip, true)
                if lastCoords ~= nil then
                    if lastCoords.x == coords.x and lastCoords.y == coords.y then
                        TriggerEvent("chat:addMessage", {args = {"^0[ ^2Dispatch ^0] ", "GPS coordinates have been updated."}})
                        return
                    end
                end
                lastCoords = coords
                TriggerEvent("chat:addMessage", {args = {"^0[ ^2Dispatch ^0] ", "GPS coordinates set to caller's last known location."}})
            end
        end)

        RegisterNetEvent("SonoranCAD::dispatchnotify:BeginTracking")
        AddEventHandler("SonoranCAD::dispatchnotify:BeginTracking", function(callID)
            trackingCall = true
            trackingID = callID
            track()
        end)

        RegisterNetEvent("SonoranCAD::dispatchnotify:StopTracking")
        AddEventHandler("SonoranCAD::dispatchnotify:StopTracking", function()
            trackingCall = false
            trackingID = nil
        end)

        local function setGpsLock(value)
            gpsLock = value
            TriggerEvent("chat:addMessage", {args = {"^0[ ^2GPS ^0] ", ("GPS lock has been %s"):format(gpsLock and "enabled" or "disabled")}})
        end

        RegisterNetEvent("SonoranCAD::dispatchnotify:CallAttach")
        RegisterNetEvent("SonoranCAD::dispatchnotify:CallDetach")
        RegisterNetEvent("SonoranCAD::dispatchnotify:AddNoteToCall")

        AddEventHandler("SonoranCAD::dispatchnotify:CallAttach", function(callId)
            debugLog("Got attach for call "..tostring(callId))
            currentCallId = callId
        end)
        AddEventHandler("SonoranCAD::dispatchnotify:CallDetach", function(callId)
            debugLog("Got detach for call "..tostring(callId))
            currentCallId = nil
            if gpsBlip then RemoveBlip(gpsBlip) end
            gpsBlip = nil
        end)

        function track()
            local lastpostal = nil
            if trackingCall then
                while trackingCall and trackingID ~= nil do
                    local postal = nil
                    if isPluginLoaded("postals") and getNearestPostal() ~= nil then
                        postal = getNearestPostal()
                    else
                        assert(false, "Required postal resource is not loaded. Cannot use postals plugin.")
                    end
                    if postal ~= nil and postal ~= lastpostal then
                        TriggerServerEvent("SonoranCAD::dispatchnotify:UpdateCallPostal", postal, trackingID)
                        lastpostal = postal
                    end
                    Citizen.Wait(pluginConfig.postalSendTimer)
                end
            end
        end

        local canAddPlate = pluginConfig.enableAddPlate and isPluginLoaded("wraithv2")
        if canAddPlate then
            RegisterNetEvent("SonoranCAD::dispatchnotify:PlateLock")
            AddEventHandler("SonoranCAD::dispatchnotify:PlateLock", function(plate)
                debugLog("Got locked plate event "..tostring(plate))
                lockedPlate = plate
            end)
        end

        TriggerEvent("chat:addSuggestion", "/" .. pluginConfig.commandName,
            "Dispatch notify commands: respond, notify, note, plate, gps, help.", {
                { name = "action", help = "respond | notify | note | plate | gps | help" },
                { name = "param", help = "Call ID, notify mode, or note text depending on subcommand" }
            })
        RegisterPlayerCommandHelp("dispatchnotify", pluginConfig.commandName,
            "Dispatch notify commands: respond, notify, note, plate, gps, help.",
            "<respond|notify|note|plate|gps|help> [param]")

        RegisterCommand(pluginConfig.commandName, function(source, args, rawCommand)
            local subcommand = args[1] and string.lower(args[1]) or "help"

            if subcommand == string.lower(pluginConfig.gpsToggleSubcommand) then
                setGpsLock(not gpsLock)
                return
            end

            if subcommand == string.lower(pluginConfig.respondSubcommandName) then
                if args[2] == nil then
                    TriggerEvent("chat:addMessage", {args = {"^0[ ^4Error ^0] ", ("Usage: /%s %s <callId>"):format(pluginConfig.commandName, pluginConfig.respondSubcommandName)}})
                    return
                end
                TriggerServerEvent("SonoranCAD::dispatchnotify:CommandRespond", {args[2]})
                return
            end

            if subcommand == string.lower(pluginConfig.unitNotifyToggleSubcommand) then
                local notifyArgs = {}
                if args[2] ~= nil then
                    notifyArgs[1] = args[2]
                end
                TriggerServerEvent("SonoranCAD::dispatchnotify:CommandNotify", notifyArgs)
                return
            end

            if subcommand == string.lower(pluginConfig.addNoteSubcommand) then
                if not pluginConfig.enableAddNote then
                    TriggerEvent("chat:addMessage", {args = {"^0[ ^4Error ^0] ", "Adding notes is disabled."}})
                    return
                end
                local note = table.concat(args, " ", 2)
                if note == nil or note == "" then
                    TriggerEvent("chat:addMessage", {args = {"^0[ ^4Error ^0] ", ("Usage: /%s %s <note>"):format(pluginConfig.commandName, pluginConfig.addNoteSubcommand)}})
                    return
                end
                if currentCallId ~= nil then
                    TriggerServerEvent("SonoranCAD::dispatchnotify:AddNoteToCall", currentCallId, note)
                    TriggerEvent("chat:addMessage", {args = {"^0[ ^2Note ^0] ", "Note sent to CAD."}})
                else
                    TriggerEvent("chat:addMessage", {args = {"^0[ ^4Error ^0] ", "Not attached to any call."}})
                end
                return
            end

            if subcommand == string.lower(pluginConfig.addPlateSubcommand) then
                if not canAddPlate then
                    TriggerEvent("chat:addMessage", {args = {"^0[ ^4Error ^0] ", "Plate sending is unavailable."}})
                    return
                end
                if currentCallId ~= nil and lockedPlate ~= nil then
                    TriggerServerEvent("SonoranCAD::dispatchnotify:AddNoteToCall", currentCallId, ("PLATE NUMBER: %s"):format(lockedPlate))
                    TriggerEvent("chat:addMessage", {args = {"^0[ ^2Note ^0] ", ("Locked plate %s sent to CAD."):format(lockedPlate)}})
                else
                    TriggerEvent("chat:addMessage", {args = {"^0[ ^4Error ^0] ", "Not attached to any call or no plate locked."}})
                end
                return
            end

            TriggerEvent("chat:addMessage", {args = {"^0[ ^3Dispatch ^0] ", ("Usage: /%s %s <callId> | /%s %s [on|off|auto] | /%s %s <note> | /%s %s | /%s %s"):format(
                pluginConfig.commandName,
                pluginConfig.respondSubcommandName,
                pluginConfig.commandName,
                pluginConfig.unitNotifyToggleSubcommand,
                pluginConfig.commandName,
                pluginConfig.addNoteSubcommand,
                pluginConfig.commandName,
                pluginConfig.addPlateSubcommand,
                pluginConfig.commandName,
                pluginConfig.gpsToggleSubcommand
            )}})
        end)

    end
end) end)
