--[[
    SonoranCAD Character Registration

    Opens the live CAD character template in-game and creates a character for
    the player's linked CAD account.
]]

local config = {
    enabled = true,
    pluginName = "civreg",
    pluginAuthor = "SonoranCAD",
    configVersion = "1.1",

    -- Optional notification override for this submodule only.
    -- Valid values: "none", "ox_lib", "lation_ui", "pnotify", "chat"
    notificationOverride = "none",

    commandName = "civreg",
    templateId = 7,
    -- A short shared cache prevents multiple players from exhausting the CAD
    -- template endpoint's rate limit. The form is never loaded from a bundled copy.
    templateCacheSeconds = 60,

    -- Portraits are submitted to CAD as base64 image data. This limit applies
    -- to the decoded size of each PNG or JPEG. No public image hosting is needed.
    maxSelfieBytes = 1024 * 1024,

    -- When CAD database sync and character mapping are enabled, CivReg writes
    -- portraits to the framework database instead of creating API characters.
    -- These defaults match the standard QBCore and ESX character schemas.
    databaseSync = {
        qbCore = {
            tableName = "players",
            characterIdColumn = "citizenid"
        },
        esx = {
            tableName = "users",
            characterIdColumn = "identifier"
        }
    },

    -- Map framework identity values to field UIDs from template #7. Change the
    -- value on the right when a field has a custom Field Mapping ID in CAD.
    autofillFieldIds = {
        first = "first",
        last = "last",
        dob = "dob",
        sex = "sex",
        height = "height",
        phone = "phone",
        nationality = "nationality"
    },

    language = {
        helpMsg = "Register a new civilian character in CAD",
        title = "Character Registration",
        subtitle = "Complete the live CAD character form below.",
        selfieAction = "Click to take a selfie",
        selfieHint = "Your current character portrait will be attached to this CAD record.",
        submit = "Register Character",
        cancel = "Cancel",
        loading = "Loading the live CAD template...",
        success = "Character registered successfully in CAD.",
        databaseSyncSuccess = "Character portrait updated successfully."
    }
}

if config.enabled then
    Config.RegisterPluginConfig(config.pluginName, config)
end
