--[[
    Sonaran CAD Plugins

    Plugin Name: unitstatus
    Creator: SonoranCAD
    Description: Allows updating unit status

    Put all server-side logic in this file.
]]

local pluginConfig = Config.GetPluginConfig("unitstatus")

if pluginConfig.enabled then

    function setUnitStatus(unitIdentity, status, player)
        local statusNumber = nil
        debugLog(("%s %s %s"):format(unitIdentity, status, player))
        if tonumber(status) ~= nil and tonumber(status) >= 0 and tonumber(status) <= 5 then
            statusNumber = tonumber(status)
        else
            statusNumber = tonumber(pluginConfig.statusCodes[string.upper(status)])
        end
        if statusNumber == nil then
            if player ~= nil then
                sendClientError(player, "UNITSTATUS_INVALID_STATUS", nil)
            end
            errorLog("UNITSTATUS_INVALID_STATUS", ("Status %s was not found in config"):format(tostring(status)))
            return
        end
        local communityUserId = player ~= nil and GetPlayerCommunityUserId(player) or unitIdentity
        if player ~= nil then
            local playerCadStatus = getPlayerCadStatus(player, "Unit Status", { link = true, unit = true })
            if not playerCadStatus.success then
                return
            end
            communityUserId = playerCadStatus.link
        end
        local payload = {
            ["communityUserId"] = communityUserId,
            ["status"] = statusNumber,
            ["serverId"] = tonumber(Config.serverId)
        }
        local response = CadApiSetUnitStatus(payload)
        if not response.success then
            CadApiLogFailure("UNIT_STATUS", response, payload)
        end
        TriggerEvent("SonoranCAD::unitstatus:StatusUpdate", unitIdentity, statusNumber, response.success == true)
        if player ~= nil then
            TriggerClientEvent("SonoranCAD::unitstatus:StatusUpdate", player, unitIdentity, statusNumber, response.success == true)
        end
    end

    exports('cadSetUnitStatus', setUnitStatus)

    RegisterNetEvent("SonoranCAD::unitstatus:UpdateStatus")
    AddEventHandler("SonoranCAD::unitstatus:UpdateStatus", function(status)
        local source = source
        if not IsPlayerAceAllowed(source, "command.setstatus") and pluginConfig.enableAceCheck then
            sendClientError(source, "PERMISSION_DENIED", "Access denied.")
            return
        end
        local ids = GetIdentifiers(source)
        local identifier = ids[Config.primaryIdentifier]
        setUnitStatus(identifier, status, source)
    end)

end
