--[[
    Sonoran Plugins

    CAD Display Submodule Configuration
]]

local config = {
    enabled = true,
    pluginName = "caddisplay",
    pluginAuthor = "Sonoran Software Systems",
    configVersion = "1.0",

    lang = {
        addNewDisplayHelp = "Open the menu to begin placing a CAD display",
        vehNotCompatible = "This vehicle is not compatible with the CAD display placement system!",
        vehAlreadyDisplay = "This vehicle already has a CAD display placement!",
        menuHeader = "Sonoran CAD Display",
        creditsPanel = "Made by",
        spawningSubMenu = "CAD Display Spawning",
        attachingSubMenu = "Attaching",
        deletionSubMenu = "Remove placement?",
        attachMenuButton = "Attach CAD Display",
        deleteMenuButton = "Delete CAD Display Placement",
        spawnMenuButton = "Spawn CAD Display",
        deletionConfirmationButton = "Yes, remove from all of these vehicles",
        deletionCancelButton = "Cancel",
        deletionCancelled = "CAD display deletion cancelled",
        worldMenuButton = "Station CAD Displays",
        worldMenuHeader = "Station CAD Displays",
        worldPlacementSubMenu = "Station Display Placement",
        worldPlacementSelect = "Display:",
        worldSpawnButton = "Place Station Display",
        worldEditButton = "Edit Selected Display",
        worldDeleteButton = "Delete Selected Display",
        worldSaveButton = "Save Station Display",
        worldCancelButton = "Cancel",
        worldNoDisplays = "No station displays configured",
        worldDeletionCancelled = "Station display deletion cancelled",
        noDisplayFound = "No CAD display found in this vehicle!",
        modelComboBox = "Model:",
        vehAlreadyDisplayNoti = "~r~This vehicle already has a CAD display placement",
        notInVeh = "~r~You must be in a vehicle!",
        vehicleBone = "CAD Display - Vehicle Bone",
        object = "Object:",
        vehicleBoneComboBox = "Vehicle Bone",
        objectName = "Sonoran CAD Display",
        attachButton = "Attach",
        detachButton = "Detach",
        confirmPlacementButton = "Apply to all of this vehicle model",
        cannotGoFaster = "~r~You cannot go any faster!",
        cannotGoSlower = "~r~You cannot go any slower!"
    },

    commands = {
        cadDisplayMenu = "caddisplay",
        restricted = true -- should the CAD display menu be restricted?
    },

    permissionMode = "ace", -- Available Options: ace, framework, custom

    -- Ace Permissions Section --
    acePerms = {
        aceObjectUseMenu = "sonoran.caddisplay", -- Ace to open/attach CAD displays
        aceObjectAdminUseMenu = "sonoran.caddisplay.admin", -- Ace to save/delete placements for vehicle models
        aceWorldDisplayAdmin = "sonoran.caddisplay.world" -- Ace to save/delete station display placements
    },

    -- Framework Related Settings --
    framework = {
        frameworkType = "qb-core", -- Options: esx or qb-core
        civilianJobNames = {"unemployed"}, -- Jobs allowed to open the menu
        adminJobNames = {"admin"}, -- Jobs allowed to save/delete placements
        useCivilianJobListAsBlacklist = false -- Treat the civilian job list as a blacklist rather than whitelist
    },

    -- Configuration For Custom Permissions Handling --
    custom = {
        checkPermsServerSide = true, -- If true the permission event will be sent out to the server side resource
        permissionCheck = function(_, type) -- Always called server side.
            if type == 0 then -- Check permission to use the menu
                return true or false -- Return true if permitted, false otherwise
            elseif type == 1 then -- Check permission to manage station display placements
                return true or false -- Return true if permitted, false otherwise
            end
        end
    },

    general = {
        notificationType = "auto", -- Options: auto, native, pNotify, okokNotify, ox_lib, lation_ui
        useAllowlistAsBlacklist = false -- If true, allowlistedCars is treated as a blacklist
    },

    -- Station/world CAD display placements (static around the map)
    -- These defaults are approximate exterior locations for standard GTA V PD stations.
    -- Adjust as needed using the in-game menu.
    worldDisplays = {
        enabled = true,
        defaultPlacements = {
            {
                label = "Mission Row PD",
                position = { x = 440.84, y = -981.14, z = 30.69 },
                rotation = { pitch = 0.0, roll = 0.0, yaw = 0.0 },
                displayModel = "prop_laptop_jimmy",
                scale = { x = 1.0, y = 1.0, z = 1.0 }
            },
            {
                label = "Vespucci PD",
                position = { x = -1096.43, y = -839.32, z = 19.00 },
                rotation = { pitch = 0.0, roll = 0.0, yaw = 0.0 },
                displayModel = "prop_laptop_jimmy",
                scale = { x = 1.0, y = 1.0, z = 1.0 }
            },
            {
                label = "Davis PD",
                position = { x = 360.82, y = -1584.97, z = 29.29 },
                rotation = { pitch = 0.0, roll = 0.0, yaw = 0.0 },
                displayModel = "prop_laptop_jimmy",
                scale = { x = 1.0, y = 1.0, z = 1.0 }
            },
            {
                label = "La Mesa PD",
                position = { x = 823.01, y = -1290.19, z = 28.24 },
                rotation = { pitch = 0.0, roll = 0.0, yaw = 0.0 },
                displayModel = "prop_laptop_jimmy",
                scale = { x = 1.0, y = 1.0, z = 1.0 }
            },
            {
                label = "Rockford Hills PD",
                position = { x = -561.01, y = -132.09, z = 38.05 },
                rotation = { pitch = 0.0, roll = 0.0, yaw = 0.0 },
                displayModel = "prop_laptop_jimmy",
                scale = { x = 1.0, y = 1.0, z = 1.0 }
            },
            {
                label = "Sandy Shores Sheriff",
                position = { x = 1854.52, y = 3686.12, z = 34.27 },
                rotation = { pitch = 0.0, roll = 0.0, yaw = 0.0 },
                displayModel = "prop_laptop_jimmy",
                scale = { x = 1.0, y = 1.0, z = 1.0 }
            },
            {
                label = "Paleto Bay Sheriff",
                position = { x = -447.70, y = 6012.41, z = 31.72 },
                rotation = { pitch = 0.0, roll = 0.0, yaw = 0.0 },
                displayModel = "prop_laptop_jimmy",
                scale = { x = 1.0, y = 1.0, z = 1.0 }
            }
        }
    },

    -- Vehicles with built-in laptop screens you want to skin with the CAD DUI
    -- Each entry needs:
    --   vehicle         - spawn code (model name) for the vehicle
    --   screenTexture   - texture name on the built-in laptop model to replace with the DUI
    --   textureWidth    - optional width of the built-in texture in pixels (used to scale the DUI), default 512
    --   textureHeight   - optional height of the built-in texture in pixels (used to scale the DUI), default 256
    builtinScreens = {
        -- Example:
        -- {vehicle = "POLICE", screenTexture = "laptop_screen", textureWidth = 512, textureHeight = 256}
    },

    allowlistedCars = {
        "POLICE",
        "POLICE2",
        "POLICE3",
        "POLICE4",
        "FBI",
        "FBI2",
        "SHERIFF",
        "SHERIFF2"
    },

    -- Interaction settings
    interactKey = "G", -- Default key mapping for interaction (RegisterKeyMapping)
    interactControl = 47, -- Fallback control code (INPUT_DETONATE) - avoid horn (E)
    interactRange = 1.5, -- Distance in meters to allow interacting with the laptop
    requestAcceptKey = "Y", -- Key to accept a control request
    requestDenyKey = "L" -- Key to deny a control request
}

if config.enabled then Config.RegisterPluginConfig(config.pluginName, config) end
