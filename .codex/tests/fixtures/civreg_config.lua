local config = {
    enabled = true,
    pluginName = "civreg",
    pluginAuthor = "SonoranCAD",
    configVersion = "1.1",
    notificationOverride = "none",
    commandName = "civreg",
    templateId = 7,
    templateCacheSeconds = 60,
    maxSelfieBytes = 1024 * 1024,
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
        databaseSyncCommandNotice = "Character registration and portraits are handled automatically when you select your framework character. You do not need to use this command.",
        databaseSyncSuccess = "Character portrait updated successfully."
    }
}

return config
