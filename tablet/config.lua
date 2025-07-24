Config = {}

Config.Framework = "qb" -- qb, esx, auto

Config.AutoHideOnVehicleExit = true -- if true, the cad will automatically hide when the player exits a vehicle
Config.AllowMiniCadOnFoot = false -- if true, player can access the cad while on foot

Config.AccessRestrictions = {
    RequireTabletItem = true, -- if true, player must have the tablet item to access the cad
    TabletItemName = "sonorantablet", -- name of the tablet item
    RestrictByJob = true, -- if true, player must have a job in the allowed jobs list to access the cad
    RestrictByVehicle = false, -- if true, player must be in a vehicle in the allowed vehicles list to access the cad
    AllowedJobs = {
        "lspd",
        "sheriff",
        "ambulance",
        "fire"
    },
    AllowedVehicles = {
        "police",
        "police2",
        "police3",
        "police4",
        "fbi",
        "fbi2",
        "ambulance",
        "firetruk"
    }
}
