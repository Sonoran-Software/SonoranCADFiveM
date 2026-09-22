Config = {plugins = {}}
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


Config.RegisterPluginConfig = function(pluginName, configs)
    Config.plugins[pluginName] = {}
    for k, v in pairs(configs) do Config.plugins[pluginName][k] = v end
    table.insert(Plugins, pluginName)
end

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

RegisterNetEvent('SonoranCAD::core:recvClientConfig')
AddEventHandler('SonoranCAD::core:recvClientConfig', function(config)
    if source ~= 65535 then return end
    for k,v in pairs(config) do
        if k == 'plugins' then Config.plugins = ResolveFiveMConfig(v) else Config[k] = v end
    end
    Plugins = {}
    for name, plugin in pairs(Config.plugins) do
        if plugin.enabled then Plugins[#Plugins + 1] = name end
    end
    Config.inited = true
end)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(100) end
    while not Config.inited do
        TriggerServerEvent('SonoranCAD::core:sendClientConfig')
        Wait(5000)
    end
end)

Config.GetPluginConfig = function(pluginName)
    while not Config.inited do Wait(50) end
    return Config.plugins[pluginName] or {enabled = false, disableReason = 'Unknown module'}
end
Config.LoadPlugin = function(pluginName, cb)
    while not Config.inited or Config.apiVersion == -1 do Wait(50) end
    return cb(Config.GetPluginConfig(pluginName))
end


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
