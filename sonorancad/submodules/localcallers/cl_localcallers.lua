--[[
    Sonaran CAD Plugins
    Plugin Name: localcallers
    Creator: SonoranCAD
    Description: AI will report crime when it sees it
]]
CreateThread(function()
    Config.LoadPlugin("localcallers", function(pluginConfig)
        if pluginConfig.enabled then
            local lastCallEndTime  = 0    -- tracks when the most recent call finished
            local activeCalls = {}
            -- Get the street name at these coords
            function getStreetName(coords)
                local streetHash, _ = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
                return GetStreetNameFromHashKey(streetHash)
            end
            -- Play the phone-call emote + attach a phone prop
            function playCallEmote(ped)
                RequestAnimDict("cellphone@")
                while not HasAnimDictLoaded("cellphone@") do
                    Wait(10)
                end
                TaskPlayAnim(ped, "cellphone@", "cellphone_call_listen_base", 8.0, -8.0, -1, 49, 0, false, false, false)

                local phone = CreateObject(GetHashKey("prop_phone_ing"), 1.0, 1.0, 1.0, true, true, false)
                AttachEntityToEntity(
                    phone,
                    ped,
                    GetPedBoneIndex(ped, 28422),
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    true, true, false, true, 1, true
                )
                return phone
            end

            -- Stop the emote + delete phone prop
            function stopCallEmote(ped, phone)
                ClearPedTasks(ped)
                if DoesEntityExist(phone) then
                    DeleteEntity(phone)
                end
            end

            -- Return one of: pistol, knife, longgun, shotgun, smg, sniper,
            -- melee, heavy, explosive, throwable, fire, or “unknown”
            function getWeaponCategory(weaponHash)
                local weaponCategories = {
                    pistol = {
                        `WEAPON_PISTOL`, `WEAPON_COMBATPISTOL`, `WEAPON_APPISTOL`, `WEAPON_PISTOL50`,
                        `WEAPON_SNSPISTOL`, `WEAPON_HEAVYPISTOL`, `WEAPON_VINTAGEPISTOL`, `WEAPON_MARKSMANPISTOL`,
                        `WEAPON_REVOLVER`, `WEAPON_DOUBLEACTION`, `WEAPON_CERAMICPISTOL`, `WEAPON_NAVYPISTOL`,
                        `WEAPON_GADGETPISTOL`, `WEAPON_STUNGUN`
                    },
                    knife = {
                        `WEAPON_KNIFE`, `WEAPON_DAGGER`, `WEAPON_SWITCHBLADE`, `WEAPON_MACHETE`,
                        `WEAPON_BOTTLE`, `WEAPON_HATCHET`, `WEAPON_BATTLEAXE`, `WEAPON_STONE_HATCHET`
                    },
                    longgun = {
                        `WEAPON_ASSAULTRIFLE`, `WEAPON_CARBINERIFLE`, `WEAPON_ADVANCEDRIFLE`, `WEAPON_SPECIALCARBINE`,
                        `WEAPON_BULLPUPRIFLE`, `WEAPON_COMPACTRIFLE`, `WEAPON_MILITARYRIFLE`, `WEAPON_HEAVYRIFLE`,
                        `WEAPON_TACTICALRIFLE`
                    },
                    shotgun = {
                        `WEAPON_PUMPSHOTGUN`, `WEAPON_SAWNOFFSHOTGUN`, `WEAPON_BULLPUPSHOTGUN`, `WEAPON_ASSAULTSHOTGUN`,
                        `WEAPON_MUSKET`, `WEAPON_HEAVYSHOTGUN`, `WEAPON_DBSHOTGUN`, `WEAPON_AUTOSHOTGUN`
                    },
                    smg = {
                        `WEAPON_MICROSMG`, `WEAPON_SMG`, `WEAPON_ASSAULTSMG`, `WEAPON_COMBATPDW`,
                        `WEAPON_MACHINEPISTOL`, `WEAPON_MINISMG`
                    },
                    sniper = {
                        `WEAPON_SNIPERRIFLE`, `WEAPON_HEAVYSNIPER`, `WEAPON_MARKSMANRIFLE`, `WEAPON_PRECISIONRIFLE`
                    },
                    melee = {
                        `WEAPON_HAMMER`, `WEAPON_BAT`, `WEAPON_GOLFCLUB`, `WEAPON_CROWBAR`, `WEAPON_FLASHLIGHT`,
                        `WEAPON_NIGHTSTICK`, `WEAPON_WRENCH`, `WEAPON_POOLCUE`, `WEAPON_UNARMED`
                    },
                    heavy = {
                        `WEAPON_GRENADELAUNCHER`, `WEAPON_RPG`, `WEAPON_MINIGUN`, `WEAPON_FIREWORK`, `WEAPON_RAILGUN`,
                        `WEAPON_COMPACTLAUNCHER`, `WEAPON_HOMINGLAUNCHER`, `WEAPON_GRENADELAUNCHER_SMOKE`,
                        `WEAPON_EMPLAUNCHER`
                    },
                    explosive = {
                        `WEAPON_GRENADE`, `WEAPON_STICKYBOMB`, `WEAPON_PROXMINE`, `WEAPON_PIPEBOMB`,
                        `WEAPON_MOLOTOV`, `WEAPON_SMOKEGRENADE`, `WEAPON_BZGAS`
                    },
                    throwable = {
                        `WEAPON_SNOWBALL`, `WEAPON_FLARE`, `WEAPON_BALL`
                    },
                    fire = {
                        `WEAPON_FIREEXTINGUISHER`, `WEAPON_PETROLCAN`, `WEAPON_HAZARDCAN`
                    }
                }

                for category, list in pairs(weaponCategories) do
                    for _, w in ipairs(list) do
                        if weaponHash == w then
                            return category
                        end
                    end
                end

                return "unknown"
            end

            -- Decide which action category applies—and return that key for callTemplates
            function detectActionType(ped)
                -- If the ped is shooting right now, override everything and report "shooting"
                if IsPedShooting(ped) then
                    return "shooting"
                end

                -- If the ped is in melee combat, override and report "fighting"
                if IsPedInMeleeCombat(ped) then
                    return "fighting"
                end

                -- Otherwise look at the weapon they currently have selected
                local weapon = GetSelectedPedWeapon(ped)
                local cat = getWeaponCategory(weapon)
                if cat ~= "unknown" then
                    return cat
                end

                -- If we still can't match, but they are armed, fall back to "pistol"
                if IsPedArmed(ped, 7) then
                    return "pistol"
                end
                return "fighting"  -- if unarmed but in melee, or unknown scenario
            end

            -- Safely look up a component’s “name” and “color” from pluginConfig.clothingConfig.
            --   compTable: e.g. pluginConfig.clothingConfig.top (or .torso, .pants, .shoes)
            --   compID:     the component index returned by GetPedDrawableVariation or GetPedPropIndex
            --   texID:      the texture index returned by GetPedTextureVariation or GetPedPropTextureIndex
            -- Returns two strings: itemName and colorName (or “Unknown …” if not found).
            local function lookupClothing(compTable, compID, texID)
                if not compTable or type(compID) ~= "number" or type(texID) ~= "number" then
                    return pluginConfig.language.unknownItem, pluginConfig.language.unknownColor
                end

                local drawableEntry = compTable[compID]
                if not drawableEntry then
                    return pluginConfig.language.unknownItem, pluginConfig.language.unknownColor
                end

                local itemName = drawableEntry.name or pluginConfig.language.unknownItem
                local colorName = pluginConfig.language.unknownColor
                if drawableEntry.colors and drawableEntry.colors[texID] then
                    colorName = drawableEntry.colors[texID]
                end

                return itemName, colorName
            end

            -- Returns a description string for a given ped, e.g.:
            -- “Male, T-Shirt (Red), Leather Jacket (Black), Jeans (Blue), Sneakers (White)”
            function getPlayerDescription(ped)
                if not DoesEntityExist(ped) then
                    return pluginConfig.language.unknown
                end

                -- 1) Determine gender
                local isMale    = IsPedMale(ped)
                local genderKey = isMale and "male" or "female"
                local genderStr = isMale and pluginConfig.language.male or pluginConfig.language.female

                -- 2) Grab the gendered clothing table
                local clothes = pluginConfig.clothingConfig[genderKey]

                -- 3) Top (component 8)
                local topDraw = GetPedDrawableVariation(ped, 8)
                local topTex  = GetPedTextureVariation(ped,    8)
                local topName,   topColor   = lookupClothing(clothes.top,   topDraw, topTex)

                -- 4) Torso (component 3)
                local torsoDraw = GetPedDrawableVariation(ped, 3)
                local torsoTex  = GetPedTextureVariation(ped,    3)
                local torsoName, torsoColor = lookupClothing(clothes.torso, torsoDraw, torsoTex)

                -- 5) Pants (component 4)
                local pantsDraw = GetPedDrawableVariation(ped, 4)
                local pantsTex  = GetPedTextureVariation(ped,    4)
                local pantsName, pantsColor = lookupClothing(clothes.pants, pantsDraw, pantsTex)

                -- 6) Shoes (component 6)
                local shoesDraw = GetPedDrawableVariation(ped, 6)
                local shoesTex  = GetPedTextureVariation(ped,    6)
                local shoesName, shoesColor = lookupClothing(clothes.shoes, shoesDraw, shoesTex)

                -- 7) Hat/Prop (prop 0)
                local hatProp = GetPedPropIndex(ped, 0)
                local hatTex  = GetPedPropTextureIndex(ped, 0)
                local hatName,  hatColor  = lookupClothing(clothes.hat,   hatProp, hatTex)

                -- 8) Build description
                local desc = string.format(
                    "%s, %s (%s), %s (%s), %s (%s), %s (%s), %s (%s)",
                    genderStr,
                    topName,   topColor,
                    torsoName, torsoColor,
                    pantsName, pantsColor,
                    shoesName, shoesColor,
                    hatName,   hatColor
                )

                return desc
            end

            -- Pick a random template, fill in street + description
            function getRandomCallMessage(actionType, street, description)
                local templates = pluginConfig.language.callTemplates[actionType]
                if not templates then
                    -- Fallback if we have no entry for this actionType
                    return ("911! I saw someone acting suspicious on {street}. {description}")
                        :gsub("{street}", street)
                        :gsub("{description}", description)
                end

                local chosen = templates[math.random(1, #templates)]
                return chosen
                    :gsub("{street}", street)
                    :gsub("{description}", description)
            end
            -- Helper function to get the ped's gender
            local function getPedGender(ped)
                local t = GetPedType(ped)
                if t == 4 then
                    return "male"
                elseif t == 5 then
                    return "female"
                end
                return "unknown"
            end
            -- Helper function: returns true if `ped` is wearing ANY of the whitelisted items
            local function isPedWhitelisted(ped)
                local pedModel  = GetEntityModel(ped)
                local pedGender = getPedGender(ped)

                for _, entry in ipairs(pluginConfig.clothingConfig.whiteList) do
                    -- 0) skip any entry whose gender doesn’t match
                    if entry.gender and entry.gender ~= pedGender then
                        goto continue
                    end

                    -- 1) full‐ped model whitelist (ignore clothes)
                    if entry.ped and not entry.component then
                        if pedModel == GetHashKey(entry.ped) then
                            debugLog("Ped model fully whitelisted: " .. entry.ped)
                            return true
                        end
                    end

                    -- 2) global clothing whitelist (all peds)
                    if entry.component and not entry.ped then
                        local comp = entry.component
                        local draw = GetPedDrawableVariation(ped, comp)
                        local tex  = GetPedTextureVariation(ped, comp)
                        if draw == entry.drawable then
                            for _, allowedTex in ipairs(entry.textures) do
                                if tex == allowedTex then
                                    debugLog(("Global clothing match: comp %d draw %d tex %d"):format(comp,draw,tex))
                                    return true
                                end
                            end
                        end
                    end

                    -- 3) ped‐specific clothing whitelist
                    if entry.ped and entry.component then
                        if pedModel == GetHashKey(entry.ped) then
                            local comp = entry.component
                            local draw = GetPedDrawableVariation(ped, comp)
                            local tex  = GetPedTextureVariation(ped, comp)
                            if draw == entry.drawable then
                                for _, allowedTex in ipairs(entry.textures) do
                                    if tex == allowedTex then
                                        debugLog(("Ped-specific clothing match for %s: comp %d draw %d tex %d")
                                            :format(entry.ped,comp,draw,tex))
                                        return true
                                    end
                                end
                            end
                        end
                    end

                    ::continue::
                end

                return false
            end

            function isInWhitelistedZone(coords, callType)
                for _, zone in ipairs(pluginConfig.whitelistZones) do
                    if #(coords - zone.center) <= zone.radius then
                        for _, allowedType in ipairs(zone.whitelistTypes) do
                            if allowedType == callType then
                                return false -- this call type *is allowed* in zone, so don't skip it
                            end
                        end
                        return true -- call type NOT in whitelistTypes, suppress it
                    end
                end
                return false -- not in any zone
            end

            -- Main function to have AI call 911
            function aiCall911(aiPed, suspectPed, type)
                local playerDesc = getPlayerDescription(suspectPed)
                local street = getStreetName(GetEntityCoords(suspectPed))
                local actionType = detectActionType(suspectPed)
                local fullMessage = getRandomCallMessage(actionType, street, playerDesc)
                -- Move the AI close to the suspect, then play the call emote
                if not pluginConfig.localRunTime or pluginConfig.localRunTime < 0 or pluginConfig.localRunTime == nil then
                    pluginConfig.localRunTime = 0 -- default time if not set
                end
                pluginConfig.localRunTime = pluginConfig.localRunTime * 1000
                TaskGoToEntity(aiPed, suspectPed, pluginConfig.localRunTime, 10.0, 2.0, 0, 0)
                Wait(2000)
                local phone = playCallEmote(aiPed)

                local startTime = GetGameTimer()
                local duration = pluginConfig.callTimers.gun * 1000
                local interval = 500
                local elapsed = 0
                local callAborted = false
                if type == "carjacking" then
                    -- If this is a carjacking, we want to shorten the call duration
                    duration = pluginConfig.callTimers.carJacking * 1000
                    fullMessage = getRandomCallMessage('carjacking', street, playerDesc)
                end
                if type == "playerDied" then
                    -- If this is a player death, we want to shorten the call duration
                    duration = pluginConfig.callTimers.death * 1000
                    fullMessage = getRandomCallMessage('playerDied', street, playerDesc)
                end
                CreateThread(function()
                    while elapsed < duration do
                        if not DoesEntityExist(aiPed) or IsEntityDead(aiPed) then
                            callAborted = true
                            break
                        end
                        Wait(interval)
                        elapsed = GetGameTimer() - startTime
                    end
                    stopCallEmote(aiPed, phone)
                    -- How much of the 30 s did we actually run?
                    local percent = math.min(elapsed / duration, 1.0)
                    local cutoff = math.floor(#fullMessage * percent)
                    local partialMessage = string.sub(fullMessage, 1, cutoff)
                    if callAborted then
                        debugLog("AI Call Aborted: " .. partialMessage)
                        partialMessage = partialMessage .. pluginConfig.language.callDropped
                        Wait(5000)
                    end
                    debugLog("AI Call Message: " .. partialMessage)
                    TriggerServerEvent('SonoranCAD::localcallers:Call911', street, pluginConfig.language.callerStates .. partialMessage, GetEntityCoords(aiPed))
                    lastCallEndTime = GetGameTimer()
                    activeCalls[aiPed] = nil
                end)
            end

            local QBCore = nil
            local hasQBCore = false

            -- Safely attempt to get QBCore
            CreateThread(function()
                local success, core = pcall(function()
                    return exports['qb-core']:GetCoreObject()
                end)

                if success and core then
                    QBCore = core
                    hasQBCore = true
                    debugLog("QBCore detected.")
                else
                    debugLog("QBCore not found. Continuing without it.")
                end
            end)

            local wasDead = false
            -- Continuously watch for “playerPed” committing a crime in front of other peds
            CreateThread(function()
                while true do
                    local playerPed = PlayerPedId()
                    local playerCoords = GetEntityCoords(playerPed)
                    local nearbyPeds = {}

                    -- Gather any nearby non-player peds
                    for ped in EnumeratePeds() do
                        if ped ~= playerPed and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped) and IsPedHuman(ped) then
                            local pedCoords = GetEntityCoords(ped)
                            if #(playerCoords - pedCoords) < 50.0 and HasEntityClearLosToEntity(ped, playerPed, 17) then
                                table.insert(nearbyPeds, ped)
                            end
                        end
                    end
                    -- If any ped is already calling 911, skip everything this tick
                    local someoneCalling = false
                    -- check if activeCalls has any key:
                    if #activeCalls > 0 then
                        someoneCalling = true
                    end

                    local now = GetGameTimer()
                    local cooldownOK = (now - lastCallEndTime >= pluginConfig.callCoolDown * 1000)
                    local ignoreSuspect = isPedWhitelisted(playerPed)

                    debugLog("Nearby Peds: " .. #nearbyPeds)
                    debugLog("Cooldown OK: " .. tostring(cooldownOK))
                    debugLog("Ignore Suspect: " .. tostring(ignoreSuspect))
                    debugLog("Someone Calling: " .. tostring(someoneCalling))
                    debugLog("Active Calls: " .. json.encode(activeCalls))

                    -- Check for player death
                    local playerIsDead = IsEntityDead(playerPed)

                    if hasQBCore then
                        local success, playerData = pcall(function()
                            return QBCore.Functions.GetPlayerData()
                        end)
                        if success and playerData and playerData.metadata and playerData.metadata["isdead"] == true then
                            playerIsDead = true
                        end
                    end
                    debugLog("Player is dead: " .. tostring(playerIsDead))
                    local inWhiteListZoneDeath = isInWhitelistedZone(playerCoords, "death")
                    local inWhiteListZoneGun = isInWhitelistedZone(playerCoords, "gun")
                    local inWhiteListZoneCarJacking = isInWhitelistedZone(playerCoords, "carjacking")
                    debugLog("In Whitelist Zone (Death): " .. tostring(inWhiteListZoneDeath))
                    debugLog("In Whitelist Zone (Gun): " .. tostring(inWhiteListZoneGun))
                    debugLog("In Whitelist Zone (Carjacking): " .. tostring(inWhiteListZoneCarJacking))
                    if pluginConfig.callTypes.death and #activeCalls == 0 and (not inWhiteListZoneDeath) and playerIsDead and not wasDead and not someoneCalling and cooldownOK then
                        wasDead = true
                        if #nearbyPeds > 0 then
                            debugLog("AI Ped calling 911 for player death")
                            if not activeCalls[nearbyPeds[1]] or activeCalls[nearbyPeds[1]] == nil then
                                activeCalls[nearbyPeds[1]] = true
                                aiCall911(nearbyPeds[1], playerPed, "playerDied")
                            end
                        end
                    elseif not playerIsDead then
                        wasDead = false
                    end
                    -- If nobody is mid-call, and the player is actively “criminal,” have each nearby ped call 911
                    if pluginConfig.callTypes.gun and (not inWhiteListZoneGun) and (not someoneCalling) and cooldownOK and (not ignoreSuspect) then
                        -- If the player is armed, shooting, or in melee, have each nearby ped call 911
                        local isArmed = IsPedArmed(playerPed, 7)
                        local isShooting = IsPedShooting(playerPed)
                        local isMelee = IsPedInMeleeCombat(playerPed)
                        debugLog("Is Armed: " .. tostring(isArmed))
                        debugLog("Is Shooting: " .. tostring(isShooting))
                        debugLog("Is Melee: " .. tostring(isMelee))
                        -- If any of these conditions are true, have the first nearby ped call 911
                        if (isArmed or isShooting or isMelee) and #nearbyPeds > 0 and #activeCalls == 0 then
                            debugLog("AI Ped calling 911 for player crime")
                            if not activeCalls[nearbyPeds[1]] or activeCalls[nearbyPeds[1]] == nil then
                                activeCalls[nearbyPeds[1]] = true
                                aiCall911(nearbyPeds[1], playerPed)
                            end
                        end
                        if pluginConfig.callTypes.carJacking and (not inWhiteListZoneCarJacking) and #activeCalls == 0 and (IsPedTryingToEnterALockedVehicle(playerPed) or IsPedJacking(playerPed)) then
                            if not activeCalls[nearbyPeds[1]] or activeCalls[nearbyPeds[1]] == nil then
                                activeCalls[nearbyPeds[1]] = true
                                aiCall911(nearbyPeds[1], playerPed, "carjacking")
                            end
                        end
                    end
                    -- Car jacking detection: if the player is in a vehicle and nearby peds see it
                    Wait(3000)
                end
            end)
            -- Helper: iterate all peds in the world
            function EnumeratePeds()
                return coroutine.wrap(function()
                    local handle, ped = FindFirstPed()
                    local success
                    repeat
                        coroutine.yield(ped)
                        success, ped = FindNextPed(handle)
                    until not success
                    EndFindPed(handle)
                end)
            end
        end
    end)
end)