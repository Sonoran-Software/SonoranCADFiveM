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

RegisterCommand("sonorancad", function(_, args)
    local subcommand = args[1] and string.lower(args[1]) or "help"
    if subcommand ~= "help" then
        send_command_help_message("Usage: /sonorancad help [submodule]")
        return
    end
    show_sonoran_command_help(args[2])
end, false)

TriggerEvent("chat:addSuggestion", "/sonorancad", "Show SonoranCAD command help.", {
    { name = "action", help = "Use help" },
    { name = "submodule", help = "Optional submodule name, such as civintegration or dispatchnotify" }
})
RegisterPlayerCommandHelp("core", "sonorancad", "Show SonoranCAD command help by submodule.", "help [submodule]")


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

Config.GetPluginConfig = function(pluginName)
    local correctConfig = nil
    if Config.plugins[pluginName] ~= nil then
        if Config.critError then
            Config.plugins[pluginName].enabled = false
            Config.plugins[pluginName].disableReason = 'startup aborted'
        elseif Config.plugins[pluginName].enabled == nil then
            Config.plugins[pluginName].enabled = true
        elseif Config.plugins[pluginName].enabled == false then
            Config.plugins[pluginName].disableReason = 'Disabled'
        end
        return Config.plugins[pluginName]
    else
        if pluginName == 'apicheck' or pluginName == 'livemap' or pluginName ==
            'smartsigns' then
            return {enabled = false, disableReason = 'deprecated plugin'}
        end
        correctConfig = LoadResourceFile(GetCurrentResourceName(),
                                         '/configuration/' .. pluginName ..
                                             '_config.lua')
        if not correctConfig then
            warnLog(
                ('Plugin %s is missing critical configuration. Please check our plugin install guide at https://info.sonorancad.com/integration-submodules/integration-submodules/plugin-installation for steps to properly install.'):format(
                    pluginName))
            Config.plugins[pluginName] = {
                enabled = false,
                disableReason = 'Missing configuration file'
            }
            return {
                enabled = false,
                disableReason = 'Missing configuration file'
            }
        else
            local configChunk = correctConfig:match("local config = {.-\n}") ..
                                    "\nreturn config"
            if not configChunk then
                errorLog("No config table found in the string.")
            end
            local tempEnv = {}
            setmetatable(tempEnv, {__index = _G}) -- Allow access to global functions if needed
            local loadedPlugin, pluginError =
                load(configChunk, 'config', 't', tempEnv)
            if loadedPlugin then
                -- Execute and capture the returned config table
                local success, res = pcall(loadedPlugin)
                if not success then
                    errorLog(
                        ('Plugin %s failed to load due to error: %s'):format(
                            pluginName, res))
                    Config.plugins[pluginName] = {
                        enabled = false,
                        disableReason = 'Failed to load'
                    }
                    return {enabled = false, disableReason = 'Failed to load'}
                end
                if res and type(res) == "table" then
                    -- Assign the extracted config to Config.plugins[pluginName]
                    Config.plugins[pluginName] = res
                else
                    -- Handle case where config is not available
                    errorLog(
                        ('Plugin %s did not define a valid config table.'):format(
                            pluginName))
                    Config.plugins[pluginName] = {
                        enabled = false,
                        disableReason = 'Invalid or missing config'
                    }
                    return {
                        enabled = false,
                        disableReason = 'Invalid or missing config'
                    }
                end
                if Config.critError then
                    Config.plugins[pluginName].enabled = false
                    Config.plugins[pluginName].disableReason = 'startup aborted'
                elseif Config.plugins[pluginName].enabled == nil then
                    Config.plugins[pluginName].enabled = true
                elseif Config.plugins[pluginName].enabled == false then
                    Config.plugins[pluginName].disableReason = 'Disabled'
                end
            else
                errorLog(('Plugin %s failed to load due to error: %s'):format(
                             pluginName, pluginError))
                Config.plugins[pluginName] = {
                    enabled = false,
                    disableReason = 'Failed to load'
                }
                return {enabled = false, disableReason = 'Failed to load'}
            end
            return Config.plugins[pluginName]
        end
        Config.plugins[pluginName] = {
            enabled = false,
            disableReason = 'Missing configuration file'
        }
        return {enabled = false, disableReason = 'Missing configuration file'}
    end
end

Config.LoadPlugin = function(pluginName, cb)
    local correctConfig = nil
    while Config.apiVersion == -1 do Wait(1) end
    if Config.plugins[pluginName] ~= nil then
        if Config.critError then
            Config.plugins[pluginName].enabled = false
            Config.plugins[pluginName].disableReason = 'startup aborted'
        elseif Config.plugins[pluginName].enabled == nil then
            Config.plugins[pluginName].enabled = true
        elseif Config.plugins[pluginName].enabled == false then
            Config.plugins[pluginName].disableReason = 'Disabled'
        end
        return cb(Config.plugins[pluginName])
    else
        if pluginName == 'yourpluginname' then
            return cb({enabled = false, disableReason = 'Template plugin'})
        end
        correctConfig = LoadResourceFile(GetCurrentResourceName(),
                                         '/configuration/' .. pluginName ..
                                             '_config.lua')
        if not correctConfig then
            warnLog(
                ('Submodule %s is missing critical configuration. Please check our submodule install guide at https://info.sonorancad.com/integration-plugins/in-game-integration/fivem-installation/submodule-configuration#activating-a-submodule for steps to properly install.'):format(
                    pluginName))
            Config.plugins[pluginName] = {
                enabled = false,
                disableReason = 'Missing configuration file'
            }
            return {
                enabled = false,
                disableReason = 'Missing configuration file'
            }
        else
            local configChunk = correctConfig:match("local config = {.-\n}") ..
                                    "\nreturn config"
            if not configChunk then
                errorLog("No config table found in the string.")
            end
            local tempEnv = {}
            setmetatable(tempEnv, {__index = _G}) -- Allow access to global functions if needed
            local loadedPlugin, pluginError =
                load(configChunk, 'config', 't', tempEnv)
            if loadedPlugin then
                -- Execute and capture the returned config table
                local success, res = pcall(loadedPlugin)
                if not success then
                    errorLog(
                        ('Submodule %s failed to load due to error: %s'):format(
                            pluginName, res))
                    Config.plugins[pluginName] = {
                        enabled = false,
                        disableReason = 'Failed to load'
                    }
                    return {enabled = false, disableReason = 'Failed to load'}
                end
                if res and type(res) == "table" then
                    -- Assign the extracted config to Config.plugins[pluginName]
                    Config.plugins[pluginName] = res
                else
                    -- Handle case where config is not available
                    errorLog(
                        ('Submodule %s did not define a valid config table.'):format(
                            pluginName))
                    Config.plugins[pluginName] = {
                        enabled = false,
                        disableReason = 'Invalid or missing config'
                    }
                    return {
                        enabled = false,
                        disableReason = 'Invalid or missing config'
                    }
                end
                if Config.critError then
                    Config.plugins[pluginName].enabled = false
                    Config.plugins[pluginName].disableReason = 'startup aborted'
                elseif Config.plugins[pluginName].enabled == nil then
                    Config.plugins[pluginName].enabled = true
                elseif Config.plugins[pluginName].enabled == false then
                    Config.plugins[pluginName].disableReason = 'Disabled'
                end
            else
                errorLog(('Submodule %s failed to load due to error: %s'):format(
                             pluginName, pluginError))
                Config.plugins[pluginName] = {
                    enabled = false,
                    disableReason = 'Failed to load'
                }
                return {enabled = false, disableReason = 'Failed to load'}
            end
            return Config.plugins[pluginName]
        end
        Config.plugins[pluginName] = {
            enabled = false,
            disableReason = 'Missing configuration file'
        }
        return cb({
            enabled = false,
            disableReason = 'Missing configuration file'
        })
    end
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
