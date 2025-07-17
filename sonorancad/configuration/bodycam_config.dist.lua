--[[
    Sonoran Plugins

    Plugin Configuration

    Put all needed configuration in this file.

]]
local config = {
    enabled = true,
    pluginName = "bodycam", -- name your plugin here
    pluginAuthor = "digitalfire", -- author
    configVersion = "1.0",

    -- The command name to toggle your body camera on or off.
    command="bodycam",

    -- Enables or disables animations on start up
    enableAnimation = true,

    -- Enables or disables the blinking body camera image on screen when enabled.
    enableOverlay = true,

    --[[
        The position (corner) of the screen where the body camera image is displayed.

        Options:
        - top-left
        - top-right
        - bottom-left
        - bottom-right
    ]]
    overlayLocation = 'top-right',

    -- Enables or disables the body camera beeping when turned on.
    enableBeeps = true,

    --[[
        Type of audio that the beeps use.

        native: GtaV Native Sounds

        nui/custom: Custom Sound File
    ]]
    beepType = "nui",

    -- Adjusts the frequency at which unit body camera beeps when turned on(in milliseconds).
    beepFrequency = 10000,

    -- Adjusts the range at which a person can hear the bodycam beeps
    beepRange = 19.99,

    -- Adjusts the frequency at which unit body cameras update (in milliseconds).
    screenshotFrequency=2000,

    -- The default keybind for toggling the bodycam.
    defaultKeybind="",

    -- Automaticlly enable bodycam when lights are enabled / disabled
    autoEnableWithLights = true,

    -- Automaticlly enable bodycam when a weapon is drawn.
    autoEnableWithWeapons = true,

    --[[
        If you want to use ped/clothing based bodycams, you can add them here.

        Examples:
        { ped = "s_m_y_cop_01" }
        {
            ped = "mp_f_freemode_01",
            component = 8,
            drawable = 148,
        }
        {
            ped = "mp_m_freemode_01",
            component = 8,
            drawable = 148,
            textures = {2, 4},
        }

        ----

        Components:
            0  - Head
            1  - Beard
            2  - Hair
            3  - Torso
            4  - Legs
            5  - Hands
            6  - Foot
            7  - Scarfs/Neck Accessories
            8  - Accessories 1
            9  - Accessories 2
            10 - Decals
            11 - Auxiliary parts for torso
    ]]
    clothing = {},

    -- Weapons that when drawn enable bodycam.
    weapons = {
        -- Heavy
        "weapon_snowlauncher"
        ,"weapon_compactlauncher"
        ,"weapon_minigun"
        ,"weapon_grenadelauncher_smoke"
        ,"weapon_hominglauncher"
        ,"weapon_railgun"
        ,"weapon_firework"
        ,"weapon_grenadelauncher"
        ,"weapon_rpg"
        ,"weapon_rayminigun"
        ,"weapon_emplauncher"
        ,"weapon_railgunxm3"

        -- Shotguns
        ,"weapon_combatshotgun"
        ,"weapon_autoshotgun"
        ,"weapon_pumpshotgun"
        ,"weapon_heavyshotgun"
        ,"weapon_pumpshotgun_mk2"
        ,"weapon_sawnoffshotgun"
        ,"weapon_bullpupshotgun"
        ,"weapon_assaultshotgun"
        ,"weapon_dbshotgun"

        -- Snipers
        ,"weapon_heavysniper"
        ,"weapon_marksmanrifle_mk2"
        ,"weapon_precisionrifle"
        ,"weapon_musket"
        ,"weapon_marksmanrifle"

        -- Thrown
        ,"weapon_snowball"
        ,"weapon_ball"
        ,"weapon_molotov"
        ,"weapon_stickybomb"
        ,"weapon_flare"
        ,"weapon_grenade"
        ,"weapon_bzgas"
        ,"weapon_proxmine"
        ,"weapon_pipebomb"
        ,"weapon_acidpackage"
        ,"weapon_smokegrenade"

        -- Pistols
        ,"weapon_vintagepistol"
        ,"weapon_pistol"
        ,"weapon_pistolxm3"
        ,"weapon_appistol"
        ,"weapon_ceramicpistol"
        ,"weapon_flaregun"
        ,"weapon_gadgetpistol"
        ,"weapon_combatpistol"
        ,"weapon_snspistol_mk2"
        ,"weapon_navyrevolver"
        ,"weapon_doubleaction"
        ,"weapon_pistol50"
        ,"weapon_raypistol"
        ,"weapon_snspistol"
        ,"weapon_pistol_mk2"
        ,"weapon_revolver"
        ,"weapon_revolver_mk2"
        ,"weapon_heavypistol"
        ,"weapon_marksmanpistol"

        ,"weapon_stungun"
        ,"weapon_stungun_mp"

        -- SMGs
        ,"weapon_combatpdw"
        ,"weapon_microsmg"
        ,"weapon_tecpistol"
        ,"weapon_smg"
        ,"weapon_smg_mk2"
        ,"weapon_minismg"
        ,"weapon_machinepistol"
        ,"weapon_assaultsmg"

        -- Rifles
        ,"weapon_assaultrifle_mk2"
        ,"weapon_compactrifle"
        ,"weapon_battlerifle"
        ,"weapon_bullpuprifle"
        ,"weapon_carbinerifle"
        ,"weapon_bullpuprifle_mk2"
        ,"weapon_specialcarbine_mk2"
        ,"weapon_militaryrifle"
        ,"weapon_advancedrifle"
        ,"weapon_assaultrifle"
        ,"weapon_specialcarbine"
        ,"weapon_heavyrifle"
        ,"weapon_tacticalrifle"
        ,"weapon_carbinerifle_mk2"

        -- MGs
        ,"weapon_raycarbine"
        ,"weapon_gusenberg"
        ,"weapon_combatmg"
        ,"weapon_mg"
        ,"weapon_combatmg_mk2"

    }
}
if config.enabled then Config.RegisterPluginConfig(config.pluginName, config) end