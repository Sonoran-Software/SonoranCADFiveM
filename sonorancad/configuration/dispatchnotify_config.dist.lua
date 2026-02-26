--[[
    Sonoran Plugins

    Plugin Configuration

    Put all needed configuration in this file.

]]
local config = {
    enabled = false,
    configVersion = "3.3",
    pluginName = "dispatchnotify", -- name your plugin here
    pluginAuthor = "SonoranCAD", -- author
    requiresPlugins = {
        {name = "locations", critical = true},
        {name = "callcommands", critical = true},
        {name = "postals", critical = false}
    }, -- required plugins for this plugin to work, separated by commas

    --[[
        Enable incoming 911 call notifications
    ]]
    enableUnitNotify = true,
    --[[
        Specifies what emergency calls are displayed as. Some countries use different numbers (like 999)
    ]]
    emergencyCallType = "911",
    --[[
        Specifies non-emergency call types. If unused, set to blank ("")
    ]]
    civilCallType = "311",
    --[[
        Some communities use 511 for tow calls. Specify below, or set blank ("") to disable
    ]]
    dotCallType = "511",

    --[[
        Command to respond to calls with
    ]]
    respondCommandName = "rcall",

    --[[
        Enable call responding (self-dispatching)

        If disabled, running commandName will return an error to the unit
    ]]
    enableUnitResponse = true,

    --[[
        If a dispatcher is detected to be online, automatically disable the response command.
    ]]
    dispatchDisablesSelfResponse = false,
    --[[
        If a dispatcher is detected to be online, automatically suppress incoming 911 call notifications to units.
    ]]
    dispatchDisablesUnitNotify = false,
    --[[
        Enable an in-game command to override unit 911 notifications.

        Usage: /<unitNotifyToggleCommand> [on|off|auto]
            on: force notifications on
            off: force notifications off
            auto: follow dispatcher detection + config
    ]]
    enableUnitNotifyToggleCommand = true,
    unitNotifyToggleCommand = "toggledispatchnotify",
    -- Leave blank ("") to allow anyone to use the command.
    unitNotifyToggleAce = "sonorancad.dispatchnotify.toggle",

    --[[
        Enable "units are on the way" notifications
    ]]
    enableCallerNotify = true,
    --[[
        notifyMethod: how should the caller be notified?
            none: disable notification
            auto: Will automatically detect the system to use
            chat: Sends a message in chat
            pnotify: Uses pNotify to show a notification
            ox_lib: Uses ox_lib to show a notification
            lation_ui: Uses lation_ui to show a notification
            custom: Use the custom event instead (see docs)
    ]]
    callerNotifyMethod = "auto",
    --[[
        notifyMessage: Message template to use when sending to the player

        You can use the following replacements:
            {officer} - officer name
    ]]
    notifyMessage = "Officer {officer} is responding to your call!",

    --[[
        unitNotifyMethod: how should units be notified?
            none: disable notification
            auto: Will automatically detect the system to use
            chat: Sends a message in chat
            pnotify: Uses pNotify to show a notification
            ox_lib: Uses ox_lib to show a notification
            lation_ui: Uses lation_ui to show a notification
            custom: Use the custom event instead (see docs)
    ]]
    unitNotifyMethod = "auto",
    --[[
        incomingCallMessage: how should officers be notified of a new 911 call?

        Parameters:
            {location} - location of call (street + postal)
            {description} - description as given by civilian
            {caller} - caller's name
            {callId} - ID of the call so LEO can respond with /r911 <id>
            {command} - The command to use

        Note: pNotify uses HTML (commented below), chat uses special codes.
    ]]
    -- incomingCallMessage = "<b>Incoming Call!</b><br/>Location: {location}<br/>Description: {description}<br/>Use command /r911 <b>{callId}</b> to respond!",
    incomingCallMessage = "Incoming call from ^*{caller}^r! Location: ^3{location}^0 Description: ^3{description}^0 - Use /{command} ^*{callId}^r to respond!",
    --[[
        incomingCallMessageNoResponse: message shown when dispatchDisablesSelfResponse is true and a dispatcher is online.
        Removes the self-response instructions from the notification.
    ]]
    incomingCallMessageNoResponse = "Incoming call from ^*{caller}^r! Location: ^3{location}^0 Description: ^3{description}^0",

    --[[
        unitDutyMethod: How to detect if units are online?
            incad: units must be logged into the CAD
            permissions: units must have the "sonorancad.dispatchnotify" ACE permission (see docs)
            esxjob: requires esxsupport plugin, use jobs instead for on duty detection
            custom: Use custom function (defined below as unitDutyCustom)
    ]]
    unitDutyMethod = "incad",

    --[[
        unitStatusNotifyMethod: how should units be notified for status?
            none: disable notification
            auto: Will automatically detect the system to use
            chat: Sends a message in chat
            pnotify: Uses pNotify to show a notification
            ox_lib: Uses ox_lib to show a notification
            lation_ui: Uses lation_ui to show a notification
            custom: Use the custom event instead (see docs)
    ]]
    unitStatusNotifyMethod = "auto",
    unitStatusAttachedMessage = "You are now attached to call ^4{callId}^0. Description: ^4{description}^0",
    unitStatusDetachedMessage = "You were detached from call ^4{callId}^0.",

    --[[
        esxJobsAllowed: What jobs should count as being on duty?
    ]]
    esxJobsAllowed = {["police"] = true, ["ambulance"] = true, ["fire"] = true},

    --[[
        waypointType: Type of waypoint to use when officer is attached
            postal: set gps to caller's postal (less accurate, more realistic) - REQUIRES CONFIGURED POSTAL PLUGIN
            exact: set gps to caller's position (less realistic)
            none: disable waypointing
    ]]
    waypointType = "postal",

    --[[
        waypointFallbackEnabled: Fall back to postal if exact coordinates cannot be found (for self-generated calls)
    ]]
    waypointFallbackEnabled = true,
    --[[
        callTitle: Customize the title of a call made
    ]]
    callTitle = "OFFICER RESPONSE",
    --[[
        sendNotesToUnits: Whether the script will fire events related to call notes.
    ]]
    sendNotesToUnits = true,
    --[[
        noteNotifyMethod:
            chat: send new notes via chat
            auto: Will automatically detect the system to use
            pnotify: send new notes via a pNotify popup (requires pNotify resource)
            ox_lib: send new notes via a ox_lib notification (requires ox_lib resource)
            lation_ui: send new notes via a lation_ui notification (requires lation_ui resource)
            custom: fire a client-side event that your script will consume (each active unit gets SonoranCAD::dispatchnotify:NewCallNote with an object containing callId and note)
    ]]
    noteNotifyMethod = "auto",
    --[[
        noteMessage: Message to send to officers when a note is added, using the placeholders:
            {callid} - the call ID
            {note} - the note added
    ]]
    noteMessage = "New note added for call ^*{callid}^r: {note}",
    --[[
        enableAddNote: Whether or not to enable the addnote command, allowing units attached to calls to add notes to their call.
    ]]
    enableAddNote = true,
    --[[
        addNoteCommand: The command to create for adding notes.
    ]]
    addNoteCommand = "addnote",
    --[[
        enableAddPlate: Enable the addplate command, allowing units to send locked plate data as a note to their current call. Will require the wraithv2 plugin to work.
    ]]
    enableAddPlate = true,
    --[[
        addPlateCommand: The command to create for sending plate data
    ]]
    addPlateCommand = "addplate",

    --[[
        onSceneHandler: Enables automatically disabling waypointing when marked on scene
    ]]
    onSceneHandler = true,

    --[[
        onSceneIndex: Usually don't have to touch this. Controls which button is "on scene"
    ]]
    onSceneIndex = 4
}

if config.enabled then

    function unitDutyCustom(player) return false end

    Config.RegisterPluginConfig(config.pluginName, config)
end
