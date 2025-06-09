--[[
    Sonaran CAD Plugins
    Plugin Name: aicrimereport
    Creator: SonoranCAD
    Description: AI will report crime when it sees it
]]
CreateThread(function()
    Config.LoadPlugin("aicrimereport", function(pluginConfig)
        if pluginConfig.enabled then
            local lastCallEndTime  = 0    -- tracks when the most recent call finished
            local callTemplates = {
                pistol = {
                    "Someone is waving a handgun around near %s! I think it's a %s!",
                    "There's a guy showing off a pistol on %s! %s!",
                    "Help! I just saw someone flashing a pistol on %s. %s.",
                    "Looks like a handgun on %s. %s!",
                    "They're brandishing a pistol openly at %s. %s!",
                    "I’m scared. There’s someone with a small gun on %s. %s.",
                    "A handgun! I saw a %s on %s!",
                    "They've got a sidearm on %s, just flashing it around. %s.",
                    "Looks like a concealed pistol being shown on %s. %s.",
                    "Man with a pistol spotted near %s! %s!"
                },
                knife = {
                    "Someone's got a knife out on %s! %s!",
                    "There’s a person waving a blade around on %s! %s!",
                    "Looks like a knife! They're on %s. %s.",
                    "Dangerous looking guy with a knife near %s! %s.",
                    "He's swinging a knife around %s. %s!",
                    "This guy has a knife in his hand on %s. %s!",
                    "They're brandishing a blade at %s. %s.",
                    "Knife-wielding person spotted on %s! %s!",
                    "They're acting threatening with a knife at %s. %s.",
                    "I think they’ve got a knife at %s! %s!"
                },
                longgun = {
                    "Someone’s got a rifle out on %s! %s!",
                    "He’s walking around with a long gun on %s. %s.",
                    "There’s a guy carrying a rifle down %s. %s!",
                    "I saw a scoped rifle on %s! %s.",
                    "That looks like an assault weapon on %s! %s.",
                    "Rifle spotted near %s! %s.",
                    "Man with a long weapon walking near %s! %s.",
                    "They're carrying something like a sniper on %s. %s!",
                    "Definitely a long gun, I saw it near %s. %s!",
                    "They’ve got a rifle out on %s. %s!"
                },
                shotgun = {
                    "He’s carrying a shotgun down %s! %s!",
                    "There’s a person with a pump-action shotgun on %s! %s.",
                    "I just saw someone with a shotgun at %s. %s.",
                    "Sawed-off or not, it’s a shotgun on %s! %s!",
                    "Someone with a 12-gauge at %s. %s!",
                    "That looked like a shotgun being carried on %s. %s.",
                    "Openly carrying a shotgun down %s! %s.",
                    "They’ve got a big shotgun out on %s! %s!",
                    "I’m sure it’s a shotgun – on %s! %s.",
                    "Shotgun-wielding person walking down %s. %s!"
                },
                smg = {
                    "Someone’s flashing a submachine gun on %s! %s!",
                    "They're carrying a compact SMG on %s. %s!",
                    "That looked like an SMG on %s. %s!",
                    "Small automatic weapon spotted on %s! %s!",
                    "He’s got a machine pistol on %s. %s!",
                    "They're holding something like a Uzi at %s! %s!",
                    "I swear that was a mini-SMG at %s. %s!",
                    "Rapid-fire gun seen on %s! %s!",
                    "Someone’s armed with an SMG on %s. %s!",
                    "Automatic weapon sighting on %s! %s!"
                },
                sniper = {
                    "I saw someone with a sniper rifle on %s! %s!",
                    "There’s a long-range weapon on %s. %s!",
                    "Scoped rifle spotted near %s! %s!",
                    "They’ve got a sniper on %s. %s!",
                    "Sniper-type weapon seen at %s! %s!",
                    "Someone’s aiming something big on %s. %s!",
                    "That's a sniper rifle near %s! %s!",
                    "It looked like a precision weapon on %s. %s!",
                    "Sniper spotted at %s! %s!",
                    "Someone’s lining up shots at %s. %s!"
                },
                melee = {
                    "There’s someone swinging a bat on %s! %s!",
                    "They’re holding a melee weapon on %s. %s!",
                    "Looks like a crowbar or something at %s! %s!",
                    "He’s threatening folks with a wrench on %s. %s!",
                    "That guy has a hammer on %s! %s!",
                    "There’s a person with a club at %s! %s!",
                    "He’s got something blunt on %s. %s!",
                    "Looks like a flashlight used as a weapon at %s! %s!",
                    "They’re ready to swing something on %s. %s!",
                    "Blunt weapon spotted on %s! %s!"
                },
                heavy = {
                    "There's a guy with a rocket launcher on %s! %s!",
                    "Heavy weapon spotted at %s. %s!",
                    "That looked like a minigun near %s! %s!",
                    "Big launcher spotted on %s. %s!",
                    "He’s carrying military-grade stuff on %s! %s!",
                    "I swear I saw a railgun on %s. %s!",
                    "That’s a heavy-duty launcher at %s! %s!",
                    "Huge weapon on display at %s. %s!",
                    "Massive firepower seen near %s! %s!",
                    "There’s someone armed to the teeth on %s. %s!"
                },
                explosive = {
                    "Someone just pulled out a grenade on %s! %s!",
                    "Explosives sighted at %s! %s!",
                    "They’ve got a molotov on %s. %s!",
                    "Sticky bomb spotted near %s! %s!",
                    "Looks like they’ve got a pipe bomb at %s! %s!",
                    "Person is holding an explosive on %s. %s!",
                    "They’ve got some kind of bomb at %s! %s!",
                    "Looks like tear gas or something worse on %s! %s!",
                    "That guy’s got an explosive device at %s. %s!",
                    "That’s not safe! Explosive spotted on %s! %s!"
                },
                throwable = {
                    "They’ve got something in their hand—maybe a flare—on %s. %s!",
                    "Someone’s throwing snowballs on %s! %s!",
                    "I think I saw a ball fly past on %s. %s!",
                    "That looked like something tossed on %s! %s!",
                    "He’s throwing random stuff on %s. %s!",
                    "Could be a distraction—something just flew on %s! %s!",
                    "They’re throwing stuff! On %s! %s!",
                    "Tossed something on %s! %s!",
                    "Object thrown at someone on %s. %s!",
                    "Suspicious object thrown on %s! %s!"
                },
                fire = {
                    "Someone’s spraying something flammable on %s! %s!",
                    "Fire extinguisher used on %s—don’t know why! %s!",
                    "They’ve got a gas can out on %s. %s!",
                    "They’re pouring fuel at %s! %s!",
                    "Potential arsonist on %s! %s!",
                    "Flammable liquid being poured near %s! %s!",
                    "That’s a petrol can at %s! %s!",
                    "I think they’re starting a fire at %s. %s!",
                    "They’re holding some fire hazard at %s. %s!",
                    "Fire-related activity spotted on %s! %s!"
                },
                fighting = {
                    "There’s a brawl on %s! %s!",
                    "Two people are fighting at %s! %s!",
                    "I just saw someone getting punched on %s. %s!",
                    "Big fight going down on %s! %s!",
                    "They're in a fistfight on %s! %s!",
                    "Physical altercation on %s! %s!",
                    "They’re beating each other up on %s. %s!",
                    "Some sort of street fight at %s! %s!",
                    "They're swinging at each other on %s! %s!",
                    "Crazy fight happening near %s! %s!"
                }
            }

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
                    return "Unknown Item", "Unknown Color"
                end

                local drawableEntry = compTable[compID]
                if not drawableEntry then
                    return "Unknown Item", "Unknown Color"
                end

                local itemName = drawableEntry.name or "Unknown Item"
                local colorName = "Unknown Color"
                if drawableEntry.colors and drawableEntry.colors[texID] then
                    colorName = drawableEntry.colors[texID]
                end

                return itemName, colorName
            end

            -- Returns a description string for a given ped, e.g.:
            -- “Male, T-Shirt (Red), Leather Jacket (Black), Jeans (Blue), Sneakers (White)”
            function getPlayerDescription(ped)
                if not DoesEntityExist(ped) then
                    return "Unknown"
                end

                -- 1) Gender
                local gender = IsPedMale(ped) and "Male" or "Female"

                -- 2) Top (component 8)
                local topDraw = GetPedDrawableVariation(ped, 8)
                local topTex  = GetPedTextureVariation(ped,    8)
                local topName, topColor = lookupClothing(pluginConfig.clothingConfig.top, topDraw, topTex)

                -- 3) Torso/Jacket (component 3)
                local torsoDraw = GetPedDrawableVariation(ped, 3)
                local torsoTex  = GetPedTextureVariation(ped,    3)
                local torsoName, torsoColor = lookupClothing(pluginConfig.clothingConfig.torso, torsoDraw, torsoTex)

                -- 4) Pants (component 4)
                local pantsDraw = GetPedDrawableVariation(ped, 4)
                local pantsTex  = GetPedTextureVariation(ped,    4)
                local pantsName, pantsColor = lookupClothing(pluginConfig.clothingConfig.pants, pantsDraw, pantsTex)

                -- 5) Shoes (component 6)
                local shoesDraw = GetPedDrawableVariation(ped, 6)
                local shoesTex  = GetPedTextureVariation(ped,    6)
                local shoesName, shoesColor = lookupClothing(pluginConfig.clothingConfig.shoes, shoesDraw, shoesTex)

                -- (Optional) Hat / Glasses / Accessories could be added here similarly:
                local hatProp  = GetPedPropIndex(ped, 0)
                local hatTex   = GetPedPropTextureIndex(ped, 0)
                local hatName, hatColor = lookupClothing(pluginConfig.clothingConfig.hat, hatProp, hatTex)

                -- Build the final description string
                local desc = string.format(
                    "%s, %s (%s), %s (%s), %s (%s), %s (%s)",
                    gender,
                    topName,   topColor,
                    torsoName, torsoColor,
                    pantsName, pantsColor,
                    shoesName, shoesColor
                )

                return desc
            end

            -- Pick a random template, fill in street + description
            function getRandomCallMessage(actionType, street, description)
                local templates = callTemplates[actionType]
                if not templates then
                    -- Fallback if we have no entry for this actionType
                    return string.format("911! I saw someone acting suspicious on %s. %s", street, description)
                end
                local chosen = templates[math.random(1, #templates)]
                return string.format(chosen, street, description)
            end

            -- Helper function: returns true if `ped` is wearing ANY of the whitelisted items
            local function isPedWhitelisted(ped)
                for _, entry in ipairs(pluginConfig.clothingConfig.whiteList) do
                    local comp = entry.component
                    local draw = GetPedDrawableVariation(ped, comp)
                    local tex = GetPedTextureVariation(ped, comp)

                    if draw == entry.drawable then
                        for _, allowedTex in ipairs(entry.textures) do
                            if tex == allowedTex then
                                return true
                            end
                        end
                    end
                end
                return false
            end

            -- Main function to have AI call 911
            function aiCall911(aiPed, suspectPed)
                if activeCalls[aiPed] then
                    return
                end
                activeCalls[aiPed] = true

                local playerDesc = getPlayerDescription(suspectPed)
                local street = getStreetName(GetEntityCoords(suspectPed))
                local actionType = detectActionType(suspectPed)
                local fullMessage = getRandomCallMessage(actionType, street, playerDesc)

                -- Move the AI close to the suspect, then play the call emote
                TaskGoToEntity(aiPed, suspectPed, -1, 10.0, 2.0, 0, 0)
                Wait(2000)

                local phone = playCallEmote(aiPed)

                local startTime = GetGameTimer()
                local duration = 30000  -- 30 seconds total
                local interval = 500
                local elapsed = 0
                local callAborted = false

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
                    TriggerServerEvent('SonoranCAD::callcommands:SendCallApi', true, 'Bystander', street, partialMessage, PlayerPedId(), false, true)
                    lastCallEndTime = GetGameTimer()
                    activeCalls[aiPed] = nil
                end)
            end

            -- Continuously watch for “playerPed” committing a crime in front of other peds
            CreateThread(function()
                while true do
                    local playerPed = PlayerPedId()
                    local playerCoords = GetEntityCoords(playerPed)
                    local nearbyPeds = {}

                    -- Gather any nearby non-player peds
                    for ped in EnumeratePeds() do
                        if ped ~= playerPed and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped) then
                            local pedCoords = GetEntityCoords(ped)
                            if #(playerCoords - pedCoords) < 50.0 and HasEntityClearLosToEntity(ped, playerPed, 17) then
                                table.insert(nearbyPeds, ped)
                            end
                        end
                    end
                    -- If any ped is already calling 911, skip everything this tick
                    local someoneCalling = false
                    -- check if activeCalls has any key:
                    if next(activeCalls) ~= nil then
                        someoneCalling = true
                    end

                    local now = GetGameTimer()
                    local cooldownOK = (now - lastCallEndTime >= pluginConfig.callCoolDown * 1000)
                    local ignoreSuspect = isPedWhitelisted(playerPed)

                    -- If nobody is mid-call, and the player is actively “criminal,” have each nearby ped call 911
                    if (not someoneCalling) and cooldownOK and (not ignoreSuspect) then
                        -- If the player is armed, shooting, or in melee, have each nearby ped call 911
                        local isArmed = IsPedArmed(playerPed, 7)
                        local isShooting = IsPedShooting(playerPed)
                        local isMelee = IsPedInMeleeCombat(playerPed)

                        if (isArmed or isShooting or isMelee) and #nearbyPeds > 0 then
                            for _, ai in ipairs(nearbyPeds) do
                                aiCall911(ai, playerPed)
                            end
                        end
                    end
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