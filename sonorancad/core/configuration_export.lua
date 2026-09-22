-- Console-only migration aid. Reads the operator's existing local files, never remote Lua.
RegisterCommand('sonoran_config_export', function(source)
    if source ~= 0 then return end
    local values = { core = {}, plugins = {} }
    local resource = GetCurrentResourceName()
    local errors = {}
    local function convert(value, path)
        local kind = type(value)
        if kind == 'function' then
            local hook = MatchFiveMConfigHook(value, path)
            if hook then return hook end
            errors[#errors + 1] = path .. ': custom Lua function requires a reviewed resource hook'
            return nil
        end
        if kind == 'vector3' then return {x=value.x,y=value.y,z=value.z} end
        if kind ~= 'table' then return value end
        local result = {}
        for k,v in pairs(value) do result[k] = convert(v, path .. '.' .. tostring(k)) end
        return result
    end
    local ok, err = pcall(function()
        local localCore = json.decode(LoadResourceFile(resource,'configuration/config.json') or '{}')
        for k,v in pairs(localCore) do
            if k ~= 'communityID' and k ~= 'apiKey' and k ~= 'serverId' and k ~= 'mode' then values.core[k] = v end
        end
        local version = json.decode(LoadResourceFile(resource,'version.json') or '{}')
        for name in pairs(version.submoduleConfigs or {}) do
            local text = LoadResourceFile(resource,'configuration/' .. name .. '_config.lua')
            if text then
                local config = text:match('local config = {.-\n}')
                if not config then error(name .. ': no configuration table found') end
                local chunk, loadError = load(config .. '\nreturn config', 'local-config-export', 't', _G)
                if not chunk then error(loadError) end
                local existing = chunk()
                if name == 'dispatchnotify' and existing.unitDutyMethod == 'custom' then
                    errors[#errors + 1] = 'dispatchnotify.unitDutyCustom: migrate this local callback into a reviewed resource hook'
                end
                values.plugins[name] = convert(existing, 'plugins.' .. name)
            end
        end
        local models = LoadResourceFile(resource,'configuration/livemap_vehicle_models.json')
        if models then
            values.plugins.locations = values.plugins.locations or {}
            values.plugins.locations.vehicleModels = json.decode(models)
        end
    end)
    if not ok then errors[#errors + 1] = tostring(err) end
    if #errors > 0 then
        print('[SonoranCAD] Export cancelled. ' .. table.concat(errors, '; '))
        return
    end
    local saved = SaveResourceFile(resource,'filestore/configuration-import.json',json.encode({schemaVersion=1,values=values}),-1)
    print(saved and '[SonoranCAD] Exported filestore/configuration-import.json. Import this file in CAD and review before saving.' or '[SonoranCAD] Export failed: file could not be written.')
end, true)
