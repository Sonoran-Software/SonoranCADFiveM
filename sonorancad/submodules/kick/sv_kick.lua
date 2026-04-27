--[[
    Sonaran CAD Plugins

    Plugin Name: kick
    Creator: Taylor McGaw
    Description: Kicks user from the cad upon exiting the server
]]

local pluginConfig = Config.GetPluginConfig("kick")

if pluginConfig.enabled then

    local PendingKicks = {}

    local function queueKickForPlayer(playerSource, reason)
        local communityUserId = GetPlayerCommunityUserId(playerSource)
        if not communityUserId then
            debugLog("kick: no CAD link, skip")
            return false, "no CAD link"
        end

        local unit = GetUnitByPlayerId(playerSource)
        if not unit then
            debugLog(("kick: no unit found for %s, skip"):format(communityUserId))
            return false, "no unit found"
        end

        table.insert(PendingKicks, {
            communityUserId = communityUserId,
            reason = reason or "You have exited the server"
        })
        debugLog(("kick: pending kick %s"):format(communityUserId))
        return true, communityUserId
    end

    local function processPendingKicks()
        if #PendingKicks < 1 then
            return
        end

        local kicks = {}
        while true do
            local pendingKick = table.remove(PendingKicks)
            if pendingKick ~= nil then
                table.insert(kicks, {
                    ["communityUserId"] = pendingKick.communityUserId,
                    ["reason"] = pendingKick.reason,
                    ["serverId"] = tonumber(Config.serverId)
                })
            else
                break
            end
        end

        for _, unit in ipairs(kicks) do
            debugLog(("kick: processing kick for %s"):format(unit.communityUserId))
            local link = CadApiCheckCommunityLink({["communityUserId"] = unit.communityUserId})
            local response = CadApiKickUnits(unit)
            if not response.success then
                CadApiLogFailure("KICK_UNIT", response, kicks)
            end
        end
    end

    AddEventHandler("playerDropped", function()
        local source = source
        queueKickForPlayer(source)
    end)

    RegisterCommand("testkick", function(source)
        if source == 0 then
            print("kick: /testkick must be run by an in-game player")
            return
        end

        local queued, result = queueKickForPlayer(source, "Kick test command")
        if not queued then
            TriggerClientEvent("chat:addMessage", source, {
                args = {"SonoranCAD", ("Kick test failed: %s"):format(result)}
            })
            return
        end

        processPendingKicks()
        TriggerClientEvent("chat:addMessage", source, {
            args = {"SonoranCAD", ("Kick test sent for CAD user %s"):format(result)}
        })
    end, false)

    CreateThread(function()
        while true do
            processPendingKicks()
            Wait(10000)
        end
    end)
end
