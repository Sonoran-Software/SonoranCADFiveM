-- Run from the repository root with Lua 5.4 or newer.
local commands, printed, uploaded = {}, {}, nil
local env = setmetatable({}, {__index = _G})
env.Config = {
    plugins = {ersintegration = {enabled = false, disableReason = "Disabled", version = "1.4", latestVersion = "1.4"}},
    latestVersion = "4.0.119", debugMode = false
}
env.RegisterCommand = function(name, handler) commands[name] = handler end
env.RegisterNetEvent = function() end
env.AddEventHandler = function() end
env.GetResourceState = function() return "started" end
env.GetResourceMetadata = function() return "4.0.119" end
env.GetCurrentResourceName = function() return "sonorancad" end
env.getServerVersion = function() return "test" end
env.GetConvar = function() return "30120" end
env.GetGameTimer = function() return 0 end
env.PerformHttpRequest = function(_, callback) callback(200, '{"ip":"127.0.0.1"}') end
env.SafeJsonDecode = function() return {ip = "127.0.0.1"} end
env.SafeJsonEncode = function(value)
    return '{"status":"' .. tostring(value.status) .. '"}'
end
env.json = {encode = function() return "[]" end}
env.print = function(message) printed[#printed + 1] = message end
env.infoLog = function() end
env.getSupportErrorBuffer = function() return {} end
env.GetConsoleBuffer = function() return "console" end
env.getDebugBuffer = function() return {} end
env.CadApiUploadSupportLogs = function(payload)
    uploaded = payload
    return {success = true}
end

assert(loadfile('sonorancad/core/commands.lua', 't', env))()
commands.sonorancad(0, {'ers'})
assert(printed[#printed]:find('Disabled', 1, true), 'disabled ERS should explain itself without the server submodule')
commands.sonorancad(0, {'support', '123'})
assert(uploaded.ersIntegration.status == 'Disabled', 'support payload must always include ERS status')
assert(uploaded.logs:find('ERS Integration Health', 1, true), 'support text must include ERS health')

env.Config.plugins.ersintegration.enabled = true
env.GetErsIntegrationDiagnostics = function() return {enabled = true, ready = true, status = 'running'} end
commands.sonorancad(0, {'support', '123'})
assert(uploaded.ersIntegration.ready == true, 'support payload should use the live ERS health snapshot')

env.GetErsIntegrationDiagnostics = function() error('health snapshot failed') end
commands.sonorancad(0, {'support', '123'})
assert(uploaded.ersIntegration.lastFailure.stage == 'diagnostics', 'diagnostics failure should not block support upload')
print('ERS support command tests passed')
