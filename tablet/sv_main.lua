CallCache = {}
EmergencyCache = {}
FrameworkConfig = exports.sonorancad:GetPluginConfig("frameworksupport")
TabletConfig = exports.sonorancad:GetPluginConfig("tablet_config")

Framework = nil

if FrameworkConfig.usingQBCore then
    Framework = exports['qb-core']:GetCoreObject()
else
    Framework = exports.es_extended:getSharedObject()
end

CreateThread(function()
    while GetResourceState("sonorancad") ~= "started" do
        print("Waiting for sonorancad resource to start... (current state: "..GetResourceState("sonorancad")..")")
        Wait(5000)
    end

    local function debounce(fn, time)
        local i = 0
        return function()
            i = i + 1
            local iCopy = i
            CreateThread(function()
                Wait(time)
                -- invoke if 'i' hasn't been incremented since this thread was created
                if i == iCopy then fn() end
            end)
        end
    end
    -- safely remove keys of an object based on a predicate
    local function removeKeyAt(obj, predicate)
        local kToRemove = {}
        for k, v in pairs(obj) do
            if predicate(k, v) then
                table.insert(kToRemove, k)
            end
        end
        for _, k in ipairs(kToRemove) do
            obj[k] = nil
        end
        return obj
    end

    local function miniCadCallSync()
        local callCache = exports['sonorancad']:GetCallCache()
        local unitCache = exports['sonorancad']:GetUnitCache()
        removeKeyAt(callCache, function(k, v)
            -- only include active calls
            -- Jordan 11/5 - This is causing pending calls to not show up in the mini cad
            -- if v.dispatch.status ~= 1 then return true end

            -- add unit info to the call (idk if this is really needed)
            v.dispatch.units = {}
            if v.dispatch.idents then
                for _, va in pairs(v.dispatch.idents) do
                    local unitId = exports['sonorancad']:GetUnitById(va)
                    table.insert(v.dispatch.units, unitCache[unitId])
                end
            end
            return false
        end)
        CallCache = callCache

        -- the cache already removes stale 911 calls, no need to use removeKeyAt
        EmergencyCache = exports["sonorancad"]:GetEmergencyCache()

        -- TODO: only send to active units
        TriggerClientEvent("SonoranCAD::mini:CallSync", -1, CallCache, EmergencyCache)
    end
    local miniCadCallSyncDebounced = debounce(miniCadCallSync, 1000)
    miniCadCallSyncDebounced() -- call immediately for sync

    -- watch for calls and emergencies
    -- NOTE: debounce because these can come through in quick succession
    AddEventHandler('SonoranCAD::pushevents:CallCacheUpdated', miniCadCallSyncDebounced)
    AddEventHandler('SonoranCAD::pushevents:EmergencyCacheUpdated', miniCadCallSyncDebounced)

    RegisterNetEvent("SonoranCAD::mini:CallSync_S")
    AddEventHandler("SonoranCAD::mini:CallSync_S", function()
        TriggerClientEvent("SonoranCAD::mini:CallSync", source, CallCache, EmergencyCache)
    end)

    AddEventHandler("SonoranCAD::pushevents:DispatchNote", function(data)
        TriggerClientEvent("SonoranCAD::mini:NewNote", -1, data)
    end)

    RegisterServerEvent("SonoranCAD::mini:OpenMini")
    AddEventHandler("SonoranCAD::mini:OpenMini", function ()
        local ident = exports["sonorancad"]:GetUnitByPlayerId(source)
        if ident == nil then TriggerClientEvent("SonoranCAD::mini:OpenMini:Return", source, false) return end
        if ident.data == nil then TriggerClientEvent("SonoranCAD::mini:OpenMini:Return", source, false) return end
        if ident.data.apiIds[1] == nil then TriggerClientEvent("SonoranCAD::mini:OpenMini:Return", source, false) return end
        TriggerClientEvent("SonoranCAD::mini:CallSync", source, CallCache, EmergencyCache)
        TriggerClientEvent("SonoranCAD::mini:OpenMini:Return", source, true, ident.id)
    end)

    RegisterServerEvent("SonoranCAD::mini:AttachToCall")
    AddEventHandler("SonoranCAD::mini:AttachToCall", function(callId)
        local ident = exports["sonorancad"]:GetUnitByPlayerId(source)
        if ident ~= nil then
            local data = {callId = callId, units = {ident.data.apiIds[1]}, serverId = GetConvar("sonoran_serverId", 1)}
            exports["sonorancad"]:performApiRequest({data}, "ATTACH_UNIT", function(res)
                print("Attach OK: " .. tostring(res))
            end)
        else
            print("Unable to attach... if api id is set properly, try relogging into cad.")
        end
    end)

    RegisterServerEvent("SonoranCAD::mini:DetachFromCall")
    AddEventHandler("SonoranCAD::mini:DetachFromCall", function(callId)
        local ident = exports["sonorancad"]:GetUnitByPlayerId(source)
        if ident ~= nil then
            local data = {callId = callId, units = {ident.data.apiIds[1]}, serverId = GetConvar("sonoran_serverId", 1)}
            exports["sonorancad"]:performApiRequest({data}, "DETACH_UNIT", function(res)
                print("Detach OK: " .. tostring(res))
            end)
        else
            print("Unable to detach... if api id is set properly, try relogging into cad.")
        end
    end)

    -- Send requestConfig configuration to client
    RegisterServerEvent("SonoranCAD::requestConfig")
    AddEventHandler("SonoranCAD::requestConfig", function()
        TriggerClientEvent("SonoranCAD::receiveConfig", source, FrameworkConfig, TabletConfig)
    end)
end)

-- Server-side job restriction check function
function CheckJobRestrictionServer(source)
	if not TabletConfig.AccessRestrictions.RestrictByJob then
		return true
	end
	
	local playerJob = nil
	if FrameworkConfig.usingQBCore then
		local Player = Framework.Functions.GetPlayer(source)
		if Player then
			playerJob = Player.PlayerData.job.name
		end
	elseif not FrameworkConfig.usingQBCore then
		local xPlayer = Framework.GetPlayerFromId(source)
		if xPlayer then
			playerJob = xPlayer.job.name
		end
	end
	
	if playerJob then
		for _, allowedJob in pairs(TabletConfig.AccessRestrictions.AllowedJobs) do
			if playerJob == allowedJob then
				return true
			end
		end
	end
	
	return false
end

if TabletConfig.AccessRestrictions.RequireTabletItem and FrameworkConfig.usingQBCore then
    Framework.Functions.CreateUseableItem(Config.AccessRestrictions.TabletItemName, function(source, item)
        if CheckJobRestrictionServer(source) then
            TriggerClientEvent("SonoranCAD::showcad", source)
        else
            TriggerClientEvent('chatMessage', source, "System", {255, 0, 0}, "You do not have permission to use the CAD Tablet.")
        end
    end)
elseif TabletConfig.AccessRestrictions.RequireTabletItem and FrameworkConfig.usingQBCore then
    exports.qbx_core:CreateUseableItem(Config.AccessRestrictions.TabletItemName, function(source, item)
        if CheckJobRestrictionServer(source) then
            TriggerClientEvent("SonoranCAD::showcad", source)
        else
            TriggerClientEvent('chatMessage', source, "System", {255, 0, 0}, "You do not have permission to use the CAD Tablet.")
        end
    end)
elseif TabletConfig.AccessRestrictions.RequireTabletItem and not FrameworkConfig.usingQBCore then
    Framework.RegisterUsableItem(Config.AccessRestrictions.TabletItemName, function(source, item)
        if CheckJobRestrictionServer(source) then
            TriggerClientEvent("SonoranCAD::showcad", source)
        else
            TriggerClientEvent('chatMessage', source, "System", {255, 0, 0}, "You do not have permission to use the CAD Tablet.")
        end
    end)
elseif not TabletConfig.AccessRestrictions.RequireTabletItem or FrameworkConfig == nil then
    RegisterCommand("showcad", function(source, args, rawCommand)
        if CheckJobRestrictionServer(source) then
            TriggerClientEvent("SonoranCAD::showcad", source)
        else
            TriggerClientEvent('chatMessage', source, "System", {255, 0, 0}, "You do not have permission to use the CAD Tablet.")
        end
    end, false)
end
