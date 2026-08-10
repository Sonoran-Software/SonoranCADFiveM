light_port = 9990
light_last_event = "restore"

local function runEvent(event)
    if event == nil then
        return
    end
    if event == light_last_event or (light_last_event == "panic" and event ~= "restore") then
        return
    end
    light_last_event = event
    debugLog("send light event "..json.encode({ type = "light_event", event = event, port = light_port }))
    SendNUIMessage({ type = "light_event", event = event, port = light_port })
end

local function runGameEvent(eventName, arguments)
    arguments = arguments or {}
    arguments.gameTimeMs = GetGameTimer()
    debugLog("send Studio game event "..json.encode({ type = "studio_game_event", event = eventName, args = arguments, port = light_port }))
    SendNUIMessage({ type = "studio_game_event", event = eventName, args = arguments, port = light_port })
end

local function vehicleSignalState(veh)
    local lights = GetVehicleIndicatorLights(veh)
    if lights == 1 then
        return "left"
    elseif lights == 2 then
        return "right"
    elseif lights == 3 then
        return "hazard"
    end
    return "restore"
end

local function vehicleEmergencyState(veh)
    local siren = IsVehicleSirenOn(veh)
    return siren == true or siren == 1
end

local function healthPercent(ped)
    local health = GetEntityHealth(ped)
    local maximum = math.max(GetEntityMaxHealth(ped), 1)
    local floor = maximum > 100 and 100 or 0
    local usableMaximum = math.max(maximum - floor, 1)
    local percent = math.max(0, math.min(100, ((health - floor) / usableMaximum) * 100))
    return math.floor(percent + 0.5), health, maximum
end

local function travelState(ped)
    if not IsPedInAnyVehicle(ped, false) then
        return "on_foot", nil, nil
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return "on_foot", nil, nil
    end

    local vehicleClass = GetVehicleClass(vehicle)
    local mode = "vehicle"
    if vehicleClass == 14 then
        mode = "watercraft"
    elseif vehicleClass == 15 or vehicleClass == 16 then
        mode = "aircraft"
    end

    return mode, vehicleClass, GetEntityModel(vehicle)
end

local function readPlayerState()
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then
        return nil
    end

    local dead = IsEntityDead(ped)
    local percent, health, maximumHealth = healthPercent(ped)
    local travelMode, vehicleClass, vehicleModel = travelState(ped)
    local armed = not dead and IsPedArmed(ped, 7)

    return {
        dead = dead,
        armed = armed,
        weaponHash = armed and GetSelectedPedWeapon(ped) or nil,
        health = health,
        maximumHealth = maximumHealth,
        healthPercent = percent,
        travelMode = travelMode,
        vehicleClass = vehicleClass,
        vehicleModel = vehicleModel
    }
end

local function healthArguments(state)
    return {
        health = state.health,
        maximumHealth = state.maximumHealth,
        healthPercent = state.healthPercent
    }
end

local function travelArguments(state)
    return {
        travelMode = state.travelMode,
        vehicleClass = state.vehicleClass,
        vehicleModel = state.vehicleModel
    }
end

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do
        Wait(100)
    end

    local previous = readPlayerState()
    local nextHealthSampleAt = 0
    if previous ~= nil and not previous.dead then
        runGameEvent("game.health.sample", healthArguments(previous))
        nextHealthSampleAt = GetGameTimer() + 5000
    end
    while true do
        Wait(250)
        local current = readPlayerState()
        if current ~= nil and previous ~= nil then
            local lifeChanged = current.dead ~= previous.dead
            if lifeChanged then
                if current.dead then
                    runGameEvent("game.player.died", healthArguments(current))
                else
                    runGameEvent("game.player.returned", healthArguments(current))
                end
                nextHealthSampleAt = 0
            elseif not current.dead then
                if current.armed ~= previous.armed then
                    if current.armed then
                        runGameEvent("game.weapon.drawn", { weaponHash = current.weaponHash })
                    else
                        runGameEvent("game.weapon.holstered", { weaponHash = previous.weaponHash })
                    end
                elseif current.armed and current.weaponHash ~= previous.weaponHash then
                    runGameEvent("game.weapon.holstered", { weaponHash = previous.weaponHash })
                    runGameEvent("game.weapon.drawn", { weaponHash = current.weaponHash })
                end

                if current.travelMode ~= previous.travelMode then
                    runGameEvent("game.travel." .. current.travelMode, travelArguments(current))
                end

                if current.healthPercent ~= previous.healthPercent or GetGameTimer() >= nextHealthSampleAt then
                    runGameEvent("game.health.sample", healthArguments(current))
                    nextHealthSampleAt = GetGameTimer() + 5000
                end
            end
        end

        if current ~= nil then
            previous = current
        end
    end
end)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do
        Wait(10)
    end
    while true do
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 and DoesEntityExist(veh) then
                if vehicleEmergencyState(veh) then
                    runEvent("lights")
                else
                    runEvent(vehicleSignalState(veh))
                end
            end
        else
            runEvent("restore")
        end
        Wait(500)
    end
end)

local function setStudioPort(_, args)
    local port = tonumber(args[1])
    if port == nil or port < 1 or port > 65535 then
        return print("Invalid port. Enter a number from 1 to 65535.")
    end
    light_port = math.floor(port)
end

RegisterCommand("setlightport", setStudioPort)
RegisterCommand("setstudioport", setStudioPort)
