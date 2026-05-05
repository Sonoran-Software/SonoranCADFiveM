--[[
    Sonaran CAD Plugins

    Plugin Name: unitstatus
    Creator: SonoranCAD
    Description: Allows updating unit status

    Put all client-side logic in this file.
]]

local pluginConfig = Config.GetPluginConfig("unitstatus")

if pluginConfig.enabled then

    local statuses = {}
    for k, v in pairs(pluginConfig.statusCodes) do
        statuses[v] = k
    end
    if pluginConfig.setStatusCommand ~= "" then
        RegisterCommand(pluginConfig.setStatusCommand, function(source, args, rawCommand)
            if #args == 1 then
                if pluginConfig.statusCodes[string.upper(args[1])] ~= nil or statuses[tonumber(args[1])] ~= nil then
                    TriggerServerEvent("SonoranCAD::unitstatus:UpdateStatus", args[1])
                else
                    showClientError("UNITSTATUS_INVALID_STATUS")
                end
            else
                showClientError("INVALID_COMMAND_ARGUMENT", "Missing argument.")
            end
        end)
        TriggerEvent('chat:addSuggestion', '/' .. pluginConfig.setStatusCommand, 'Sets your status in the CAD', {
            { name="Status to set", help="UNAVAILABLE/AVAILABLE/ON_SCENE/ENROUTE/BUSY" }
        })
        RegisterPlayerCommandHelp("unitstatus", pluginConfig.setStatusCommand, "Set your status in the CAD.", "<status>")
    end

    RegisterNetEvent("SonoranCAD::unitstatus:StatusUpdate")
    AddEventHandler("SonoranCAD::unitstatus:StatusUpdate", function(unitIdentity, status, success)
        if success then
            NotifyClient({
                title = "SonoranCAD",
                message = ("Status successfully changed to %s."):format(statuses[status]),
                type = "success"
            })
        else
            showClientError("CAD_API_REQUEST_FAILED", "Status change failed.")
        end
    end)

end
