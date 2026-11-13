Config = {plugins = {}, apiVersion = -1}
Plugins = {}
SonoranCommandHelp = {}

local function normalize_help_command_name(command)
    if type(command) ~= "string" then
        return nil
    end
    local trimmed = command:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then
        return nil
    end
    return trimmed:gsub("^/", "")
end

function RegisterPlayerCommandHelp(submodule, command, description, usage)
    local normalizedCommand = normalize_help_command_name(command)
    if normalizedCommand == nil then
        return
    end

    local normalizedSubmodule = type(submodule) == "string" and submodule:lower() or "core"
    if SonoranCommandHelp[normalizedSubmodule] == nil then
        SonoranCommandHelp[normalizedSubmodule] = {}
    end

    SonoranCommandHelp[normalizedSubmodule][normalizedCommand] = {
        command = normalizedCommand,
        description = type(description) == "string" and description or "",
        usage = type(usage) == "string" and usage or nil
    }
end

local function send_command_help_message(message)
    TriggerEvent("chat:addMessage", {
        args = {"^0[ ^3SonoranCAD ^0] ", tostring(message)}
    })
end

local function disable_plugin(reason)
    return {
        enabled = false,
        disableReason = reason
    }
end

local function sorted_keys(input)
    local keys = {}
    for key in pairs(input or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function show_sonoran_command_help(submodule)
    if submodule ~= nil and submodule ~= "" then
        local normalizedSubmodule = string.lower(submodule)
        local entries = SonoranCommandHelp[normalizedSubmodule]
        if entries == nil then
            send_command_help_message(("Unknown submodule '%s'."):format(tostring(submodule)))
            local modules = sorted_keys(SonoranCommandHelp)
            if #modules > 0 then
                send_command_help_message(("Enabled submodules: %s"):format(table.concat(modules, ", ")))
            end
            return
        end

        send_command_help_message(("Commands for %s:"):format(normalizedSubmodule))
        for _, commandName in ipairs(sorted_keys(entries)) do
            local entry = entries[commandName]
            local line = "/" .. entry.command
            if entry.usage ~= nil and entry.usage ~= "" then
                line = line .. " " .. entry.usage
            end
            if entry.description ~= nil and entry.description ~= "" then
                line = line .. " - " .. entry.description
            end
            send_command_help_message(line)
        end
        return
    end

    local modules = sorted_keys(SonoranCommandHelp)
    if #modules < 1 then
        send_command_help_message("No player command help is registered.")
        return
    end

    send_command_help_message("Enabled command groups:")
    for _, moduleName in ipairs(modules) do
        local entries = SonoranCommandHelp[moduleName]
        local commands = {}
        for _, commandName in ipairs(sorted_keys(entries)) do
            commands[#commands + 1] = "/" .. commandName
        end
        send_command_help_message(("%s: %s"):format(moduleName, table.concat(commands, ", ")))
    end
end

RegisterNetEvent("SonoranCAD::core:ShowCommandHelp")
AddEventHandler("SonoranCAD::core:ShowCommandHelp", function(submodule)
    show_sonoran_command_help(submodule)
end)

RegisterNetEvent("SonoranCAD::core:ShowCommandMessage")
AddEventHandler("SonoranCAD::core:ShowCommandMessage", function(message)
    send_command_help_message(message)
end)

TriggerEvent("chat:addSuggestion", "/sonorancad", "Show SonoranCAD command help.", {
    { name = "action", help = "Use help or support" },
    { name = "value", help = "Submodule name for help, or support request ID for support" }
})
RegisterPlayerCommandHelp("core", "sonorancad", "Show SonoranCAD command help by submodule or upload support logs.", "help [submodule]|support <id>")


-- Local config scripts cannot replace the server-resolved configuration.
Config.RegisterPluginConfig = function() end

--[[
    @function getApiMode
    @description Returns the API mode for the current server. 0 = Development, 1 = Production
    @returns int
]]
function getApiMode()
    if Config.mode == nil then
        return 1
    elseif Config.mode == 'development' then
        return 0
    else
        return 1
    end
end

exports('getApiMode', getApiMode)

local pluginRequests = {}
RegisterNetEvent('SonoranCAD::core:receivePluginConfig')
AddEventHandler('SonoranCAD::core:receivePluginConfig', function(name, entry)
    if not pluginRequests[name] or Config.plugins[name] then return end
    local settings = ParseCadPluginConfiguration(name, entry, Config.configurationSource == 'legacy')
    Config.plugins[name] = settings or disable_plugin('Invalid CAD plugin configuration')
    if settings and settings.enabled then Plugins[#Plugins + 1] = name end
end)

Config.GetPluginConfig = function(name)
    local started = GetGameTimer()
    while not Config.inited and GetGameTimer() - started < 60000 do Wait(25) end
    if not Config.inited or Config.critError then return disable_plugin('Configuration startup aborted') end
    if not Config.plugins[name] then
        if not pluginRequests[name] then
            pluginRequests[name] = true
            TriggerServerEvent('SonoranCAD::core:requestPluginConfig', name)
        end
        while not Config.plugins[name] and GetGameTimer() - started < 75000 do Wait(25) end
    end
    return Config.plugins[name] or disable_plugin('CAD plugin configuration request timed out')
end
Config.LoadPlugin = function(name, callback)
    local settings = Config.GetPluginConfig(name)
    if settings.enabled ~= true then return end
    return callback(settings)
end

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(1) end
    TriggerServerEvent('SonoranCAD::core:sendClientConfig')
end)

RegisterNetEvent('SonoranCAD::core:recvClientConfig')
AddEventHandler('SonoranCAD::core:recvClientConfig', function(config)
    for k, v in pairs(config) do Config[k] = v end
    Config.inited = true
    debugLog('Configuration received')
end)


CreateThread(function()
    while not Config.inited do Wait(10) end
    if Config.devHiddenSwitch then
        debugLog('Spawned discord thread')
        SetDiscordAppId(867548404724531210)
        SetDiscordRichPresenceAsset('icon')
        SetDiscordRichPresenceAssetSmall('icon')
        while true do
            SetRichPresence('Developing SonoranCAD!')
            Wait(5000)
            SetRichPresence('sonorancad.com')
            Wait(5000)
        end
    end
end)

local inited = false
AddEventHandler('playerSpawned', function()
    TriggerServerEvent('SonoranCAD::core:PlayerReady')
    inited = true
end)

AddEventHandler('onClientResourceStart', function(resourceName) --When resource starts, stop the GUI showing.
	if(GetCurrentResourceName() ~= resourceName) then
		return
	end
    Wait(10000)
    if not inited then
        TriggerServerEvent('SonoranCAD::core:PlayerReady')
        inited = true
    end
end)

RegisterNetEvent('SonoranCAD::core:debugModeToggle')
AddEventHandler('SonoranCAD::core:debugModeToggle',
                function(toggle) Config.debugMode = toggle end)

RegisterNetEvent('SonoranCAD::core:AddPlayer')
RegisterNetEvent('SonoranCAD::core:RemovePlayer')
