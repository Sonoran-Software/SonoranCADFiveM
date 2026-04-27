--[[
    Sonaran CAD Plugins

    Plugin Name: civintegration
    Creator: civintegration
    Description: Describe your plugin here

    Put all server-side logic in this file.
]]

local pluginConfig = Config.GetPluginConfig("civintegration")

if pluginConfig.enabled then
    if pluginConfig.enableIDCardUI then
        if GetResourceState('sonoran_idcard') ~= 'started' then
            if GetResourceState('sonoran_idcard') == 'stopped' then
                logError('IDCARD_RESOURCE_NOT_STARTED')
                ExecuteCommand("ensure sonoran_idcard")
            elseif GetResourceState('sonoran_idcard') == 'missing' then
                logError('IDCARD_RESOURCE_MISSING')
            else
                logError('IDCARD_RESOURCE_BAD_STATE')
            end
        end
    end
    CharacterCache = {}
    CustomCharacterCache = {}
    local CharacterCacheTimers = {}

    AddEventHandler("playerDropped", function()
        CharacterCache[source] = nil
        CharacterCacheTimers[source] = nil
        CustomCharacterCache[source] = nil
    end)

    local function getCharactersApi(player, callback)
        local communityUserId = GetPlayerCommunityUserId(player)
        if not communityUserId then
            callback(nil)
            return
        end
        local response = CadApiGetCharacters({communityUserId = communityUserId})
        if response.success then
            local result = response.data
            if result ~= nil then
                local characters = {}
                for _, records in pairs(result) do
                    local charData = {}
                   -- debugLog(("check record %s"):format(json.encode(records)))
                    for _, section in pairs(records.sections) do
                        if section.category == 7 then
                            debugLog("cat 7")
                            for _, field in pairs(section.fields) do
                                if field.uid == "img" then
                                    debugLog("add image")
                                    charData["img"] = field.value
                                end
                            end
                        elseif section.category == 0 then
                            for _, field in pairs(section.fields) do
                                debugLog(("add %s = %s"):format(field.uid, field.value))
                                charData[field.uid] = field.value
                            end
                        end
                    end
                    table.insert(characters, charData)
                end
                callback(characters)
            else
                callback(nil)
            end
        else
            CadApiLogFailure("GET_CHARACTERS", response, {communityUserId = communityUserId})
            callback(nil)
        end
    end

    function GetCharacters(player, callback)
        if CustomCharacterCache[player] ~= nil then
            callback(CustomCharacterCache[player])
        elseif CharacterCache[player] ~= nil then
            if CharacterCacheTimers[player] < GetGameTimer()+(1000*pluginConfig.cacheTime) then
                getCharactersApi(player, function(characters)
                    CharacterCache[player] = characters
                    CharacterCacheTimers[player] = GetGameTimer()
                    callback(characters)
                end)
            else
                callback(CharacterCache[player])
            end
        else
            getCharactersApi(player, function(characters)
                CharacterCache[player] = characters
                CharacterCacheTimers[player] = GetGameTimer()
                callback(characters)
            end)
        end
    end

    exports('GetCharacters', GetCharacters)

    if pluginConfig.enableCommands then
        local nearbyDistance = tonumber(pluginConfig.showNearbyDistance) or 5.0
        if nearbyDistance <= 0 then
            nearbyDistance = 5.0
        end

        local function sendChatMessage(player, colorTag, title, message)
            TriggerClientEvent("chat:addMessage", player, {
                args = {("^0[ %s%s ^0] "):format(colorTag, title), message}
            })
        end

        local function sendIdHelp(player)
            sendChatMessage(player, "^3", "ID", "Usage: /id show, /id set, /id reset, /id refresh, /id help")
            sendChatMessage(player, "^3", "ID", ("/id show displays your ID to nearby players within %.1f units."):format(nearbyDistance))
            if pluginConfig.allowCustomIds then
                sendChatMessage(player, "^3", "ID", "/id set opens a prompt for a custom first name, last name, and DOB.")
            end
            if pluginConfig.allowPurge then
                sendChatMessage(player, "^3", "ID", "/id refresh clears the cached CAD character so /id show pulls fresh data.")
            end
        end

        local function getNearbyPlayers(source)
            local viewers = {}
            local sourcePed = GetPlayerPed(source)
            if sourcePed == 0 or not DoesEntityExist(sourcePed) then
                return viewers
            end

            local sourceCoords = GetEntityCoords(sourcePed)
            for _, playerId in ipairs(GetPlayers()) do
                local numericPlayerId = tonumber(playerId)
                if numericPlayerId ~= nil and numericPlayerId ~= source then
                    local ped = GetPlayerPed(numericPlayerId)
                    if ped ~= 0 and DoesEntityExist(ped) then
                        local pedCoords = GetEntityCoords(ped)
                        if #(pedCoords - sourceCoords) <= nearbyDistance then
                            viewers[#viewers + 1] = numericPlayerId
                        end
                    end
                end
            end
            return viewers
        end

        local function showIdCommand(source)
            GetCharacters(source, function(characters)
                if characters == nil or #characters < 1 then
                    sendChatMessage(source, "^1", "Error", "No characters found. Use /id set to create a temporary custom ID if enabled.")
                else
                    local char = characters[1]
                    local name = ("%s %s"):format(char.first, char.last)
                    local dob = char.dob
                    local viewers = getNearbyPlayers(source)
                    if char.img == "statics/images/blank_user.jpg" then
                        char.img = "https://sonorancad.com/statics/images/blank_user.jpg"
                    end

                    if #viewers < 1 then
                        sendChatMessage(source, "^3", "ID", ("No nearby players were found within %.1f units."):format(nearbyDistance))
                        return
                    end

                    for _, viewer in ipairs(viewers) do
                        if pluginConfig.enableIDCardUI then
                            TriggerClientEvent("SonoranCAD::civint:DisplayID", viewer, char.img, source, name, dob)
                        else
                            TriggerClientEvent("pNotify:SendNotification", viewer, {
                                text = ("<h3>ID Lookup</h3><img width=\"96px\" height=\"128px\" align=\"left\" src=\"%s\"></image><p><strong>Player ID:</strong> %s </p><p><strong>Name:</strong> %s </p><p><strong>Date of Birth:</strong> %s</p>"):format(char.img, source, name, dob),
                                type = "success",
                                layout = "bottomcenter",
                                timeout = "10000"
                            })
                        end
                    end

                    sendChatMessage(source, "^2", "OK", ("Displayed your ID to %s nearby player(s)."):format(#viewers))
                end
            end)
        end

        RegisterCommand(pluginConfig.commandName, function(source, args, rawCommand)
            local subcommand = args[1] and string.lower(args[1]) or "help"

            if subcommand == "show" then
                showIdCommand(source)
                return
            end

            if subcommand == "set" then
                if not pluginConfig.allowCustomIds then
                    sendChatMessage(source, "^1", "Error", "Custom IDs are disabled on this server.")
                    return
                end
                TriggerClientEvent("chat:addMessage", source, {
                    args = {"^0[ ^3ID ^0] ", "Enter your first and last name, then enter your DOB. Use /id reset to clear it later."}
                })
                TriggerClientEvent("SonoranCAD::civintegration:SetCustomId", source)
                return
            end

            if subcommand == "reset" then
                if not pluginConfig.allowCustomIds then
                    sendChatMessage(source, "^1", "Error", "Custom IDs are disabled on this server.")
                    return
                end
                if CustomCharacterCache[source] ~= nil then
                    CustomCharacterCache[source] = nil
                    sendChatMessage(source, "^2", "OK", "Custom character removed.")
                else
                    sendChatMessage(source, "^3", "ID", "No custom ID is currently set.")
                end
                return
            end

            if subcommand == "refresh" then
                if not pluginConfig.allowPurge then
                    sendChatMessage(source, "^1", "Error", "Character refresh is disabled on this server.")
                    return
                end
                CharacterCacheTimers[source] = 0
                sendChatMessage(source, "^2", "OK", "Character cache cleared. Use /id show again.")
                return
            end

            if subcommand == "help" then
                sendIdHelp(source)
                return
            end

            sendChatMessage(source, "^1", "Error", ("Unknown subcommand '%s'."):format(tostring(args[1])))
            sendIdHelp(source)
        end)

        if pluginConfig.allowCustomIds then
            RegisterNetEvent("SonoranCAD::civintegration:SetCustomId")
            AddEventHandler("SonoranCAD::civintegration:SetCustomId", function(id)
                CustomCharacterCache[source] = {{ ['first'] = id.first, ['last'] = id.last, ['dob'] = id.dob, img = "https://sonorancad.com/statics/images/blank_user.jpg" }}
            end)
        end
    end


end
