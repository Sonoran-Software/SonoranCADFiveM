--[[
    Sonoran Plugins

    Plugin Configuration

    Put all needed configuration in this file.

]]
local config = {
    enabled = true,
    configVersion = "1.2",
    pluginName = "forcereg", -- name your plugin here
    pluginAuthor = "SonoranCAD", -- author
    requiresPlugins = {}, -- required plugins for this plugin to work, separated by commas

    -- Controls whether ForceReg actually enforces CAD linking.
    -- This replaces the old top-level config.requireLink setting.
    requireLink = true,

    -- Replaces the old top-level config.autoOpenLinkPopup setting.
    autoOpenLinkPopup = true,

    -- Optional override for the /link command name used in ForceReg text and the link UI.
    linkCommand = "link",

    -- Optional override for how often the link UI polls for link completion.
    linkPollIntervalMs = 10000,

    -- Optional override for the link popup title/button text while ForceReg is active.
    linkPopupTitleText = "Press the button to link your CAD account to this FiveM server",
    linkButtonText = "Link CAD",

    --[[
        Below defines the "captive" option to use:

        Nag: Simply nags the user with a big notification across the top of their screen.
        Freeze: Forces the /link menu on screen and it cannot be closed until the player links.
        Whitelist: Prevents connection to the server entirely via deferrals.
        Whitelist also blocks the in-game /link flow, so first-time linking must already be completed in CAD or via another external process.
        WARNING: NOT COMPATIBLE WITH ADAPTIVE CARD RESOURCES
    ]]
    captiveOption = "Nag",

    -- When not using Freeze, should the popup still be closable while unlinked?
    -- This replaces the old top-level config.allowPopupCloseWhenUnlinked setting.
    allowPopupCloseWhenUnlinked = true,

    -- If using Nag, should the text be centered in the users screen or at the top? ('Center' or 'Top')
    nagDrawTextLocation = "Top",

    -- What message to show with the above options? Nag, Freeze, and Whitelist can use colors.
    captiveMessage = "You must ~r~link~s~ your CAD account before playing.",

    -- What message to show under the notice. This should tell players how to reopen the CAD link popup.
    verifyMessage = "Type ~r~/link~s~ to open the CAD link window.",

    -- What does the user do once they link?
    instructionalMessage = "Press the link button, finish the link in your browser, and this server will re-check automatically.",

    -- Would you like to only show this message to players who are whitelisted?
    whitelist = {
        enabled = false,
        mode = "qb-core", -- qb-core, esx, ace
        aces = { -- ace permissions will see the message
            "forcereg.whitelist"
        },
        jobs = { -- QB or ESX jobs will see the message
            "police"
        }
    }
}

if config.enabled then
    Config.RegisterPluginConfig(config.pluginName, config)
end
