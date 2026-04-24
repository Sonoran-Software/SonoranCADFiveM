--[[
    Sonaran CAD Plugins

    Plugin Name: forcereg
    Creator: Era#1337
    Description: Requires players to link their CAD account to a valid Sonoran account.

]]

local pluginConfig = Config.GetPluginConfig("forcereg")

if pluginConfig.enabled and Config.requireLink ~= false then

    local function resolve_forcereg_text(value, fallback)
        if type(value) ~= "string" or value == "" then
            return fallback
        end
        return value
    end

    local function get_player_identifier(player)
        if GetPlayerLinkIdentifier ~= nil then
            return GetPlayerLinkIdentifier(player)
        end
        return GetIdentifiers(player)[Config.primaryIdentifier], tostring(Config.primaryIdentifier)
    end

    local linkCommand = (type(Config.linkCommand) == "string" and Config.linkCommand ~= "" and Config.linkCommand) or "link"
    local captiveMessage = resolve_forcereg_text(
        pluginConfig.captiveMessage,
        ("You must link your CAD account before joining this server. Whitelist mode blocks the in-game /%s flow, so link your identifier in CAD first or switch ForceReg to Nag/Freeze."):format(linkCommand)
    )

    local function checkCadLink(identifier, identifier_type, deferral, cb)
        local exists = cadLinkExists(identifier, identifier_type, function(result)
            debugLog(("Forcereg link check for %s (%s): %s"):format(
                tostring(identifier),
                tostring(identifier_type),
                tostring(result)
            ))
            cb(result, deferral)
        end)
        return exists
    end

    if type(pluginConfig.captiveOption) == "string" and pluginConfig.captiveOption:lower() == "whitelist" then
        warnLog(("Forcereg whitelist mode is enabled. This blocks players before they can use /%s in-game, so first-time linking must be done outside the server or by using Nag/Freeze instead."):format(linkCommand))
        AddEventHandler("playerConnecting", function(name, setMessage, deferrals)
            local player = source
            deferrals.defer()
            Wait(1)
            deferrals.update("Checking CAD account link, please wait...")

            local identifier, identifier_type = get_player_identifier(player)
            checkCadLink(identifier, identifier_type, deferrals, function(exists, deferral)
                if not exists then
                    warnLog(("Forcereg denied player %s because no CAD link was found."):format(tostring(player)))
                    deferral.done(captiveMessage)
                else
                    deferral.done()
                end
            end)
        end)
    end

    RegisterNetEvent("SonoranCAD::forcereg:CheckPlayer")
    AddEventHandler("SonoranCAD::forcereg:CheckPlayer", function()
        TriggerEvent("SonoranCAD::apicheck:CheckPlayerLinked", source)
    end)

    AddEventHandler("SonoranCAD::apicheck:CheckPlayerLinkedResponse", function(player, identifier, exists)
        debugLog(("Forcereg decision for player %s linked=%s"):format(tostring(player), tostring(exists)))

        if not pluginConfig.whitelist then
            pluginConfig.whitelist = {
                enabled = false,
                mode = "qb-core",
                aces = {
                    "forcereg.whitelist"
                },
                jobs = {
                    "police"
                }
            }
            print("Forcereg: Whitelist configuration not found, using defaults. Please update your configuration.")
        end

        if pluginConfig.whitelist.enabled then
            if pluginConfig.whitelist.mode == "ace" then
                local aceAllowed = false
                for i = 1, #pluginConfig.whitelist.aces do
                    if IsPlayerAceAllowed(player, pluginConfig.whitelist.aces[i]) then
                        aceAllowed = true
                        break
                    end
                end
                if aceAllowed then
                    TriggerClientEvent("SonoranCAD::forcereg:PlayerReg", player, identifier, exists)
                end
            elseif pluginConfig.whitelist.mode == "qb-core" then
                local QBCore = exports['qb-core']:GetCoreObject()
                local Player = QBCore.Functions.GetPlayer(player)
                local job = Player.PlayerData.job.name
                if job ~= nil then
                    for i = 1, #pluginConfig.whitelist.jobs do
                        if job == pluginConfig.whitelist.jobs[i] then
                            TriggerClientEvent("SonoranCAD::forcereg:PlayerReg", player, identifier, exists)
                            break
                        end
                    end
                end
            elseif pluginConfig.whitelist.mode == "esx" then
                local ESX = exports['es_extended']:getSharedObject()
                local xPlayer = ESX.GetPlayerFromId(player)
                local job = xPlayer.job.name
                if job ~= nil then
                    for i = 1, #pluginConfig.whitelist.jobs do
                        if job == pluginConfig.whitelist.jobs[i] then
                            TriggerClientEvent("SonoranCAD::forcereg:PlayerReg", player, identifier, exists)
                            break
                        end
                    end
                end
            end
        else
            TriggerClientEvent("SonoranCAD::forcereg:PlayerReg", player, identifier, exists)
        end
    end)

end
