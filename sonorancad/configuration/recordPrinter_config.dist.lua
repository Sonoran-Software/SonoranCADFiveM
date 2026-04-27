--[[
    Sonoran Plugins

    Plugin Configuration

    Put all needed configuration in this file.
]]
local config = {
    enabled = true,
    pluginName = "recordPrinter", -- name your plugin here
    pluginAuthor = "SonoranCAD", -- author
    configVersion = "1.1",
    recordPurgeDays = 30, -- days until records are purged | set to 0 to disable
    commandPrefix = "printer", -- base command prefix, e.g. /printer queue, /printer print, /printer share
    printQueueCommand = "queue", -- command to print record
    printCommand = "print", -- command to print record
    clearPrintQueueCommand = "clearqueue", -- command to clear print queue
    shareCommand = "recordshare", -- command to share a queued record with other players
    acceptShareCommand = "accept", -- command to accept a shared record into your queue
    maxPrintsPerQueue = 5, -- max number of prints allowed in print queue
    vehicleConfig = {
        reverseWhitelist = false, -- if true the whitelist will be used as a blacklist
        whitelist = {"police", "sheriff", "state", "highway", "fbi", "ia", "park"}, -- jobs that can print vehicle records
    },
    printerObjects = {"prop_printer_02", "prop_printer_01", "v_res_printer", "v_ret_gc_print", "prop_copier_01"}, -- objects that can be used as printers
    interactRadius = 3.0, -- radius to interact with printers and players
    printerCoords = {}, -- add specific coords for printers here {x = 0, y = 0, z = 0, h = 0}
    frameworks = {
		use_esx = false, -- Use the ESX framework
		use_esx_ox_inventory = false, -- Use OX Inventory for ESX
		use_custom_inventory = false, -- Use a custom inventory
		use_quasar_inventory = false, -- Use Quasar inventory
		use_qbcore = false -- Use the QBCore framework
	},
    translations = {
        placedInPocketPutCamAway = 'Document placed in pocket!',
        placedInPocket = 'Document placed in pocket!',
        putAwayCamera = 'Put away the document with: ~INPUT_LOOK_RIGHT_ONLY~',
        imageDropped = 'Document dropped!',
        uploadCadPrintCancel = 'Press ~INPUT_REPLAY_SCREENSHOT~ to Upload PDF to CAD\nPress ~INPUT_VEH_HEADLIGHT~ to Print PDF\n Press ~INPUT_REPLAY_NEWMARKER~ to Cancel',
        uploadedCad = '~g~PDF Uploaded To CAD!',
        photoPrinting = '~y~PDF Printing!',
        pressToDrop = '~y~Press ~INPUT_FRONTEND_RRIGHT~ Drop Document!',
        photoDeleted = '~r~PDF Deleted!',
        printCancel = 'Press ~INPUT_VEH_HEADLIGHT~ To Print PDF\n Press ~INPUT_REPLAY_NEWMARKER~ To Cancel',
        notePadText = '~g~E~s~ To Pickup PDF, ~g~G~s~ To Destroy PDF',
        lookThroughCamera = '',
        putPhotoAway = '~y~Press ~INPUT_FRONTEND_RRIGHT~ to close',
        couldNotHold = 'You could not hold that.',
        photoDescription = 'A printed PDF document'
    }
}

if config.enabled then Config.RegisterPluginConfig(config.pluginName, config) end
