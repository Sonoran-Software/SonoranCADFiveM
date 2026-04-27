function cadLinkExists(identifier, identifier_type, callback)
    if type(identifier_type) == "function" and callback == nil then
        callback = identifier_type
        identifier_type = nil
    end

    local exists = IsIdentifierLinkedToCad(identifier, identifier_type)
    if callback ~= nil then
        callback(exists)
    end
    return exists
end

RegisterCommand("forcecheck", function(source, args)
    local identifier = args[1]
    if not identifier then
        print("Usage: forcecheck <identifier>")
        return
    end
    print(("linked: %s"):format(tostring(cadLinkExists(identifier))))
end, true)

RegisterServerEvent("SonoranCAD::apicheck:CheckPlayerLinked")
AddEventHandler("SonoranCAD::apicheck:CheckPlayerLinked", function(player)
    local identifier = GetIdentifiers(player)[Config.primaryIdentifier]
    if GetPlayerLinkIdentifier ~= nil then
        identifier = GetPlayerLinkIdentifier(player)
    end
    local exists = IsPlayerLinkedToCad(player)
    TriggerEvent("SonoranCAD::apicheck:CheckPlayerLinkedResponse", player, identifier, exists)
end)

exports("CadIsPlayerLinked", cadLinkExists)
