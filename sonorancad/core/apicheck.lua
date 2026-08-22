function cadLinkExists(identifier, identifier_type, callback)
    local options = nil
    if type(callback) == "table" then
        options = callback
        callback = nil
    end
    if type(identifier_type) == "table" and callback == nil then
        options = identifier_type
        identifier_type = nil
    end
    if type(identifier_type) == "function" and callback == nil then
        callback = identifier_type
        identifier_type = nil
    end

    local exists = IsIdentifierLinkedToCad(identifier, identifier_type, options)
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
    print(("linked: %s"):format(tostring(cadLinkExists(identifier, nil, {
        forceRefresh = true
    }))))
end, true)

RegisterServerEvent("SonoranCAD::apicheck:CheckPlayerLinked")
AddEventHandler("SonoranCAD::apicheck:CheckPlayerLinked", function(player)
    local identifier = GetIdentifiers(player)[Config.primaryIdentifier]
    if GetPlayerLinkIdentifier ~= nil then
        identifier = GetPlayerLinkIdentifier(player)
    end
    local exists = IsPlayerLinkedToCad(player, {
        refreshIfMissing = true
    })
    TriggerEvent("SonoranCAD::apicheck:CheckPlayerLinkedResponse", player, identifier, exists)
end)

exports("CadIsPlayerLinked", cadLinkExists)
