--[[
    Sonaran CAD Plugins

    Plugin Name: ersintegration
    Creator: Sonoran Software
    Description: Integrates SonoranCAD PDFs in-game.
]]
CreateThread(function() Config.LoadPlugin("recordPrinter", function(pluginConfig)
    local printQueue = {}
    local pendingShares = {}
    local doc_link = nil
    local holdingDoc = false
    local uiOpen = false
    local uiMinimized = false
    local radius = pluginConfig.interactRadius or 3.0
    local baseCommand = pluginConfig.commandPrefix or "printer"
    local defaultCommands = { queue = "queue", clear = "clear", print = "print", share = "share", accept = "accept" }
    local function normalizeCommand(cmd, fallback)
        if type(cmd) ~= "string" then return fallback end
        local lowered = cmd:lower()
        if lowered == "" then return fallback end
        return lowered
    end
    local configuredCommands = {
        queue = normalizeCommand(pluginConfig.printQueueCommand, defaultCommands.queue),
        clear = normalizeCommand(pluginConfig.clearPrintQueueCommand, defaultCommands.clear),
        print = normalizeCommand(pluginConfig.printCommand, defaultCommands.print),
        share = normalizeCommand(pluginConfig.shareCommand, defaultCommands.share),
        accept = normalizeCommand(pluginConfig.acceptShareCommand or pluginConfig.acceptCommand, defaultCommands.accept)
    }
    local commandLookup = {}
    for key, name in pairs(configuredCommands) do
        name = (type(name) == "string" and name or ""):lower()
        if name ~= "" then
            commandLookup[name] = key
        end
    end
    -- Keep defaults as aliases so existing command usage still works.
    for key, name in pairs(defaultCommands) do
        if not commandLookup[name] then
            commandLookup[name] = key
        end
    end
    local function frameworksEnabled()
        local fw = pluginConfig.frameworks or {}
        return fw.use_qbcore or fw.use_esx or fw.use_esx_ox_inventory or fw.use_custom_inventory or fw.use_quasar_inventory
    end
    local function setActiveDocLink(link) doc_link = link end
    local function enqueueRecord(recordUrl, opts)
        opts = opts or {}
        if not recordUrl or recordUrl == '' then return end

        table.insert(printQueue, recordUrl)

        local maxQueue = pluginConfig.maxPrintsPerQueue or 5
        if #printQueue > maxQueue then
            table.remove(printQueue, 1)
        end

        local sharedBy = opts.sharedBy
        local message = "You have a new record to print."
        if sharedBy and sharedBy ~= '' then
            message = ("New record shared by %s."):format(sharedBy)
        end

        TriggerEvent('chat:addMessage', {
            color = { 0, 255, 0},
            multiline = true,
            args = {
                "Record Printer",
                message .. " Use /" .. baseCommand .. " " .. configuredCommands.queue .. " to view queue."
            }
        })
    end
    local function prettyFileName(path, opts)
        opts = opts or {}
        local max_len    = opts.max_len == nil and 40 or opts.max_len
        local keep_ext   = opts.keep_ext or false
        local dash_style = opts.dash_style or "spaced-dash"  -- choices: space | spaced-dash | keep

        -- 1) take just the last path segment
        local base = path:match("([^/\\]+)$") or path

        -- 2) optionally drop extension
        local ext = base:match("%.[%w]+$") or ""
        local name = keep_ext and base or base:gsub("%.[%w]+$", "")

        -- 3) strip leading UUID (8-4-4-4-12) + common separators
        local uuidPattern = "^(%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x)[%s%-%_]*"
        name = name:gsub(uuidPattern, "")

        -- 4) normalize separators
        name = name:gsub("[_]+", " ")         -- underscores -> spaces
        if dash_style == "space" then
            name = name:gsub("%s*%-%s*", " ")
        elseif dash_style == "spaced-dash" then
            name = name:gsub("%s*%-%s*", " - ")
        else
            -- "keep": leave dashes as-is
        end

        -- 5) trim & collapse whitespace
        name = name:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

        -- 6) clip if too long
        if max_len and #name > max_len then
            name = name:sub(1, max_len - 1) .. "…"
        end

        if keep_ext and ext ~= "" then
            name = name .. ext
        end

        -- fallback
        if name == "" then name = "(untitled)" end
        return name
    end
    RegisterNetEvent('SonoranCAD::recordPrinter:PrintQueue', function(data)
        enqueueRecord(data)
    end)
    RegisterNetEvent('SonoranCAD::recordPrinter:RecordShared', function(url, sharedBy, deliveryMode)
        if not url or url == '' then return end
        local sender = sharedBy or 'Unknown'
        local mode = deliveryMode or "queue"
        table.insert(pendingShares, { url = url, sharedBy = sender, mode = mode })
        local idx = #pendingShares
        sendChat({0, 255, 0}, ("New record shared by %s. Use /%s %s %d to accept."):format(sender, baseCommand, configuredCommands.accept, idx))
    end)
    local function isNearPrinterObject(radius)
        local ped = PlayerPedId()
        local pCoords = GetEntityCoords(ped)
        radius = radius or 3.5

        for _, modelName in ipairs(pluginConfig.printerObjects or {}) do
            local hash = GetHashKey(modelName)
            -- Look for the object close to the player
            local obj = GetClosestObjectOfType(pCoords.x, pCoords.y, pCoords.z, radius, hash, false, false, false)
            if obj and obj ~= 0 then
                return true
            end
        end
        return false
    end

    local function isAtPrinterCoord(radius)
        local ped = PlayerPedId()
        local pCoords = GetEntityCoords(ped)
        radius = radius or 3.5

        for _, c in ipairs(pluginConfig.printerCoords or {}) do
            local target = vector3(c.x or 0.0, c.y or 0.0, c.z or 0.0)
            if #(pCoords - target) <= radius then
                return true
            end
        end
        return false
    end

    local function isInVehicleWithPrinter()
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then return false end

        local veh = GetVehiclePedIsIn(ped, false)
        if not veh or veh == 0 then return false end

        local model = GetEntityModel(veh)

        -- Must be an emergency vehicle
        local vClass = GetVehicleClass(veh)
        if vClass ~= 18 then
            return false
        end

        -- Check whitelist logic
        local modelName = GetDisplayNameFromVehicleModel(model):lower()
        local allowed = false
        for _, v in ipairs(pluginConfig.vehicleConfig.whitelist or {}) do
            if modelName == v:lower() then
                allowed = true
                break
            end
        end

        if pluginConfig.vehicleConfig.reverseWhitelist then
            -- Blacklist: fail if it's in the whitelist
            return not allowed
        else
            -- Whitelist: only succeed if it's in the whitelist
            return allowed
        end
    end

    local function nearAnyPrinter()
        -- Succeeds if: in vehicle AND printer nearby, OR on foot and near a printer object, OR at a configured coord
        return isInVehicleWithPrinter(radius) or isNearPrinterObject(radius + 0.5) or isAtPrinterCoord(radius + 0.5)
    end

    function sendChat(color, msg)
        TriggerEvent('chat:addMessage', {
            color = color or {255,255,255},
            multiline = true,
            args = {"Record Printer", msg}
        })
    end

    local function printQueueList()
        if #printQueue == 0 then
            sendChat({255, 200, 0}, "Your print queue is empty.")
            return
        end

        for i, url in ipairs(printQueue) do
            local rawPath = url
            if type(rawPath) ~= 'string' then
                rawPath = tostring(rawPath or '')
            end
            local displayName = prettyFileName(rawPath, { keep_ext = true, max_len = pluginConfig.queueDisplayMaxLength or 48 })
            TriggerEvent('chat:addMessage', {
                color = { 0, 255, 0},
                multiline = true,
                args = {"Record Printer", "Record " .. i .. ": " .. displayName}
            })
        end
    end

    local function doPrint(idx)
        if type(printQueue) ~= "table" or #printQueue == 0 then
            sendChat({255, 100, 100}, "Your print queue is empty.")
            return
        end
        if not idx then
            sendChat({255, 200, 0}, "Usage: /" .. baseCommand .. " " .. configuredCommands.print .. " <queue index>")
            return
        end
        if idx < 1 or idx > #printQueue then
            sendChat({255, 100, 100}, ("Invalid position. Queue has %d item(s)."):format(#printQueue))
            return
        end
        if not nearAnyPrinter() then
            sendChat({255, 200, 0}, "You're not near a printer or inside a vehicle that has a printer.")
            return
        end

        local url = printQueue[idx]
        if not url or url == "" then
            sendChat({255, 100, 100}, "That queue entry is invalid.")
            return
        end

        sendChat({0, 255, 0}, ("Printing: queue #%d"):format(idx))
        setActiveDocLink(url)
        SendNuiMessage(json.encode({ action = 'openUI', link = url, first = true, type = 'pdf', recordPrinter = true }))
        uiOpen, uiMinimized = true, false
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
        table.remove(printQueue, idx)
    end

    local function getNearbyPlayers(radius)
        local nearby = {}
        local myPed = PlayerPedId()
        local myCoords = GetEntityCoords(myPed)
        for _, pid in ipairs(GetActivePlayers()) do
            if pid ~= PlayerId() then
                local tgtPed = GetPlayerPed(pid)
                if DoesEntityExist(tgtPed) then
                    local dist = #(GetEntityCoords(tgtPed) - myCoords)
                    if dist <= radius then
                        table.insert(nearby, GetPlayerServerId(pid))
                    end
                end
            end
        end
        return nearby
    end

    local function doShare(args)
        if frameworksEnabled() then
            sendChat({255, 100, 100}, "Sharing is only available when inventory frameworks are disabled.")
            return
        end

        local senderName = GetPlayerName(PlayerId())

        if holdingDoc and doc_link and doc_link ~= '' then
            local nearby = getNearbyPlayers(radius)
            if #nearby == 0 then
                sendChat({255, 200, 0}, "No nearby units within 3 to share your document with.")
                return
            end

            TriggerServerEvent('SonoranCAD::recordPrinter:ShareRecord', doc_link, senderName, nearby)
            sendChat({0, 255, 0}, ("Shared your document with %d nearby unit(s)."):format(#nearby))
            return
        end

        local targetArg = args[2]
        if not targetArg then
            sendChat({255, 200, 0}, "Usage: hold a document near others or /" .. baseCommand .. " " .. configuredCommands.share .. " <server id> to email your queue.")
            return
        end
        local targetId = tonumber(targetArg)
        if not targetId then
            sendChat({255, 100, 100}, "Invalid server ID.")
            return
        end
        if type(printQueue) ~= "table" or #printQueue == 0 then
            sendChat({255, 100, 100}, "Your print queue is empty.")
            return
        end

        local queueCopy = {}
        for _, url in ipairs(printQueue) do
            table.insert(queueCopy, url)
        end
        TriggerServerEvent('SonoranCAD::recordPrinter:EmailQueue', queueCopy, senderName, targetId)
        sendChat({0, 255, 0}, ("Emailed %d record(s) to server ID %s."):format(#queueCopy, targetId))
    end

    local function acceptShare(args)
        if type(pendingShares) ~= "table" or #pendingShares == 0 then
            sendChat({255, 200, 0}, "No pending shared records to accept.")
            return
        end

        local idx = tonumber(args[2]) or 1
        if idx < 1 or idx > #pendingShares then
            sendChat({255, 100, 100}, ("Invalid position. Pending list has %d item(s)."):format(#pendingShares))
            return
        end

        local entry = table.remove(pendingShares, idx)
        if entry.mode == "direct" then
            setActiveDocLink(entry.url)
            SendNuiMessage(json.encode({ action = 'openUI', link = entry.url, first = false, type = 'pdf', recordPrinter = true }))
            uiOpen, uiMinimized = true, false
            ToggleDocHold(true)
            SetNuiFocus(true, true)
            SetNuiFocusKeepInput(false)
            sendChat({0, 255, 0}, ("Opened shared record from %s."):format(entry.sharedBy or "Unknown"))
        else
            enqueueRecord(entry.url, { sharedBy = entry.sharedBy })
            sendChat({0, 255, 0}, ("Accepted shared record from %s."):format(entry.sharedBy or "Unknown"))
        end
    end

    RegisterCommand(baseCommand, function(_, args)
        local sub = (args[1] or ""):lower()
        local action = commandLookup[sub]
        if action == "queue" then
            printQueueList()
        elseif action == "clear" then
            printQueue = {}
            TriggerEvent('chat:addMessage', {
                color = { 0, 255, 0},
                multiline = true,
                args = {"Record Printer", "Print queue cleared."}
            })
        elseif action == "print" then
            doPrint(tonumber(args[2] or ""))
        elseif action == "share" then
            doShare(args)
        elseif action == "accept" then
            acceptShare(args)
        else
            sendChat({255, 200, 0}, ("Usage: /%s %s | /%s %s <index> | /%s %s | /%s %s [server id] | /%s %s [index]"):format(
                baseCommand, configuredCommands.queue, baseCommand, configuredCommands.print, baseCommand, configuredCommands.clear, baseCommand, configuredCommands.share, baseCommand, configuredCommands.accept))
        end
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. baseCommand, ('Record printer: %s | %s <index> | %s | %s [server id] | %s [index]'):format(
        configuredCommands.queue, configuredCommands.print, configuredCommands.clear, configuredCommands.share, configuredCommands.accept), {
        { name = 'action', help = ('%s | %s | %s | %s | %s'):format(configuredCommands.queue, configuredCommands.print, configuredCommands.clear, configuredCommands.share, configuredCommands.accept) },
        { name = 'param', help = 'For print/share/accept: queue index or server id' }
    })
    -- State
    local WorldDocs = {}  -- [{ pdf_link=string, Position={x,y,z}, entityObject=entity }, ...]

    -- Props/Anims for “holding” a doc while UI is open
    local mapModel = 'prop_tourist_map_01'
    local animDict = 'amb@world_human_tourist_map@male@base'
    local animName = 'base'
    local map_net = nil

    -- Fallback translations (safe defaults)
    if not pluginConfig.translations then
        pluginConfig.translations = {
            placedInPocketPutCamAway = 'Document placed in pocket!',
            placedInPocket = 'Document placed in pocket!',
            putAwayCamera = 'Put away the document with: ~INPUT_LOOK_RIGHT_ONLY~',
            imageDropped = 'Document dropped!',
            uploadCadPrintCancel = 'Press ~INPUT_REPLAY_SCREENSHOT~ to Upload PDF to CAD\nPress ~INPUT_VEH_HEADLIGHT~ to Print PDF\n Press ~INPUT_REPLAY_NEWMARKER~ to Cancel',
            uploadedCad = '~g~PDF Uploaded To CAD!',
            photoPrinting = '~y~PDF Printing!',
            pressToDrop = '~y~Press ~INPUT_FRONTEND_RRIGHT~ to drop document!',
            photoDeleted = '~r~PDF Deleted!',
            printCancel = 'Press ~INPUT_VEH_HEADLIGHT~ to Print PDF\n Press ~INPUT_REPLAY_NEWMARKER~ to Cancel',
            notePadText = '~g~E~s~ to pickup PDF, ~g~G~s~ to destroy PDF',
            putPhotoAway = '~y~Press ~INPUT_FRONTEND_RRIGHT~ to close',
            couldNotHold = 'You could not hold that.',
            photoDescription = 'A printed PDF document'
        }
    end

    local NotepadText = pluginConfig.translations.notePadText

    -- =========================
    -- Tiny helpers
    -- =========================
    local function DisplayNotification(msg)
        SetTextComponentFormat('STRING')
        AddTextComponentString(msg)
        DisplayHelpTextFromStringLabel(0, 0, 1, -1)
    end

    local function DrawText3Ds(x, y, z, text)
        local onScreen, _x, _y = World3dToScreen2d(x, y, z)
        local px, py, pz = table.unpack(GetGameplayCamCoords())
        SetTextScale(0.35, 0.35)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 215)
        SetTextEntry('STRING')
        SetTextCentre(1)
        AddTextComponentString(text)
        DrawText(_x, _y)
        local factor = (string.len(text)) / 370
        DrawRect(_x, _y + 0.0125, 0.015 + factor, 0.03, 41, 11, 41, 68)
    end

    local function deleteWorldEntitySafely(entity)
        if not entity or not DoesEntityExist(entity) then return end
        NetworkRequestControlOfEntity(entity)
        local timeout = GetGameTimer() + 1500
        while not NetworkHasControlOfEntity(entity) and GetGameTimer() < timeout do
            NetworkRequestControlOfEntity(entity)
            Wait(10)
        end
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
        DeleteObject(entity)
        if DoesEntityExist(entity) then
            SetEntityCoords(entity, 0.0, 0.0, -100.0, false, false, false, true)
        end
    end

    -- =========================
    -- World doc spawn/update
    -- =========================
    RegisterNetEvent('SonoranPDF:client:updatePDFs', function(serverDocs)
        -- serverDocs: array of { pdf_link, Position={x,y,z} }
        local previousDocs = WorldDocs or {}
        WorldDocs = serverDocs or {}

        local hash = GetHashKey('prop_notepad_01')
        RequestModel(hash)
        while not HasModelLoaded(hash) do Wait(50) end

        -- Destroy any existing entities we might still hold (fresh rebuild keeps it simple)
        -- If you prefer incremental updates, you can diff instead.
        -- (This approach keeps things predictable.)
        for i = 1, #previousDocs do
            local obj = previousDocs[i].entityObject
            if obj and DoesEntityExist(obj) then
                deleteWorldEntitySafely(obj)
                previousDocs[i].entityObject = nil
            end
        end

        for i = 1, #WorldDocs do
            local pos = WorldDocs[i].Position or {}
            local e = CreateObject(hash, pos.x or 0.0, pos.y or 0.0, (pos.z or 0.0) - 0.2, false, true, false)
            WorldDocs[i].entityObject = e
        end
    end)

    -- Ask server for all existing docs on start
    AddEventHandler('onClientResourceStart', function(resourceName)
        if GetCurrentResourceName() ~= resourceName then return end
        TriggerServerEvent('SonoranPDF:Server:RequestAll')
    end)

    -- =========================
    -- World interactions (pickup/destroy)
    -- =========================
    CreateThread(function()
        while true do
            Wait(1)
            if #WorldDocs == 0 then
                Wait(1000)
            else
                local ply = PlayerPedId()
                local plyLoc = GetEntityCoords(ply)

                local closestDist, closestId = 900.0, 0
                for i = 1, #WorldDocs do
                    local p = WorldDocs[i].Position
                    local d = #(plyLoc - vector3(p.x, p.y, p.z))
                    if d < 10.0 then
                        DrawMarker(27, p.x, p.y, p.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.2, 0.2, 2.0, 255, 255, 150, 75, 0, 0, 2, 0, 0, 0, 0)
                    end
                    if d < closestDist then closestDist, closestId = d, i end
                end

                if closestDist > 100.0 then
                    Wait(math.ceil(closestDist * 10))
                end

                local e = WorldDocs[closestId]
                if e ~= nil then
                    local d2 = #(plyLoc - vector3(e.Position.x, e.Position.y, e.Position.z))
                    if d2 < 2.0 then
                        DrawMarker(27, e.Position.x, e.Position.y, e.Position.z - 0.8, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 2.0, 255, 255, 155, 75, 0, 0, 2, 0, 0, 0, 0)
                        DrawText3Ds(e.Position.x, e.Position.y, e.Position.z - 0.4, NotepadText)

                        -- E: pickup & open viewer (does NOT add to inventory automatically)
                        if IsControlJustReleased(0, 38) then
                            if e.entityObject and DoesEntityExist(e.entityObject) then
                                deleteWorldEntitySafely(e.entityObject)
                                e.entityObject = nil
                            end
                            TriggerServerEvent('SonoranPDF:destroyWorldPDF', closestId)
                            SendNuiMessage(json.encode({ action = 'openUI', link = e.pdf_link, first = false, type = 'pdf', recordPrinter = true }))
                            uiOpen, uiMinimized = true, false
                            ToggleDocHold(true)
                            setActiveDocLink(e.pdf_link)
                            SetNuiFocusKeepInput(false)
                            SetNuiFocus(true, true)
                            table.remove(WorldDocs, closestId)
                        end

                        -- G: destroy in world
                        if IsControlJustReleased(0, 47) then
                            if e.entityObject and DoesEntityExist(e.entityObject) then
                                deleteWorldEntitySafely(e.entityObject)
                                e.entityObject = nil
                            end
                            TriggerServerEvent('SonoranPDF:destroyWorldPDF', closestId)
                            table.remove(WorldDocs, closestId)
                        end
                    end
                end
            end
        end
    end)

    -- =========================
    -- Inventory open (QB/ESX)
    -- =========================
    RegisterNetEvent('sonoran:lookpdf:qbcore', function(item)
        -- QB: item.info.pdf_link
        local link = (item and item.info and item.info.pdf_link) or nil
        if not link or link == '' then return end
        SendNuiMessage(json.encode({ action = 'openUI', link = link, first = false, type = 'pdf', recordPrinter = true }))
        uiOpen, uiMinimized = true, false
        ToggleDocHold(true)
        setActiveDocLink(link)
        SetNuiFocusKeepInput(false)
        SetNuiFocus(true, true)
    end)

    RegisterNetEvent('sonoran:lookpdf:esx', function(item)
        -- ESX (ox): entry.metadata.pdf_link
        local link = (item and item.metadata and item.metadata.pdf_link) or nil
        if not link or link == '' then return end
        SendNuiMessage(json.encode({ action = 'openUI', link = link, first = false, type = 'pdf', recordPrinter = true }))
        uiOpen, uiMinimized = true, false
        ToggleDocHold(true)
        setActiveDocLink(link)
        SetNuiFocusKeepInput(false)
        SetNuiFocus(true, true)
    end)

    -- Optional: direct open (e.g., when a brand-new PDF is produced and you want it to be “First” so putting away adds to inventory)
    RegisterNetEvent('SonoranPDF:Open', function(url)
        if not url or url == '' then return end
        setActiveDocLink(url)
        SendNuiMessage(json.encode({ action = 'openUI', link = url, first = true, type = 'pdf', recordPrinter = true })) -- first=true -> inventory put-away
        uiOpen, uiMinimized = true, false
        ToggleDocHold(true)
        SetNuiFocusKeepInput(false)
        SetNuiFocus(true, true)
    end)

    -- =========================
    -- NUI close / put-away / drop
    -- =========================
    RegisterNUICallback('CloseUI', function(data, cb)
        -- data.link (pdf url), data.first (bool), type='pdf'
        local link = data and data.link or nil
        local isFirst = data and data.first or false
        uiOpen, uiMinimized = false, false
        SetNuiFocusKeepInput(false)

        if pluginConfig.frameworks.use_qbcore and not pluginConfig.frameworks.use_quasar_inventory then
            if isFirst then
                SetNuiFocus(false, false)
                TriggerServerEvent('SonoranPDF:PutAway:QB:First', link)
                if cb then cb() end
                DisplayNotification(pluginConfig.translations.placedInPocketPutCamAway)
            else
                SetNuiFocus(false, false)
                if cb then cb() end
                DisplayNotification(pluginConfig.translations.placedInPocket)
            end

        elseif pluginConfig.frameworks.use_esx and pluginConfig.frameworks.use_esx_ox_inventory then
            if isFirst then
                SetNuiFocus(false, false)
                TriggerServerEvent('SonoranPDF:PutAway:ESX:First', link)
                if cb then cb() end
                DisplayNotification(pluginConfig.translations.placedInPocketPutCamAway)
            else
                SetNuiFocus(false, false)
                if cb then cb() end
                DisplayNotification(pluginConfig.translations.placedInPocket)
            end

        elseif pluginConfig.frameworks.use_custom_inventory then
            if isFirst then
                SetNuiFocus(false, false)
                TriggerServerEvent('SonoranPDF:PutAway:Custom:First', link)
                if cb then cb() end
                DisplayNotification(pluginConfig.translations.placedInPocketPutCamAway)
            else
                SetNuiFocus(false, false)
                if cb then cb() end
                DisplayNotification(pluginConfig.translations.placedInPocket)
            end

        elseif pluginConfig.frameworks.use_quasar_inventory and pluginConfig.frameworks.use_qbcore then
            if isFirst then
                SetNuiFocus(false, false)
                TriggerServerEvent('SonoranPDF:PutAway:Quasar:First', link)
                if cb then cb() end
                DisplayNotification(pluginConfig.translations.placedInPocketPutCamAway)
            else
                SetNuiFocus(false, false)
                if cb then cb() end
                DisplayNotification(pluginConfig.translations.placedInPocket)
            end

        else
            -- No inventory: drop to world if “first”
            SetNuiFocus(false, false)
            local pos = GetEntityCoords(PlayerPedId())
            TriggerServerEvent('SonoranPDF:SaveToWorld', link, pos.x, pos.y, pos.z - 0.8)
            if isFirst then
                DisplayNotification(pluginConfig.translations.putAwayCamera)
            else
                DisplayNotification(pluginConfig.translations.imageDropped)
            end
            if cb then cb() end
        end

        ToggleDocHold(false)
    end)

    RegisterNUICallback('RecordPrinter:MinimizeChanged', function(data, cb)
        uiMinimized = data and data.minimized or false
        if uiMinimized then
            releaseFocus()
            -- extra nudge: run twice to ensure FiveM drops focus immediately
            Wait(0)
            releaseFocus()
        elseif uiOpen then
            SetNuiFocusKeepInput(false)
            SetNuiFocus(true, true)
        end
        if cb then cb({ ok = true }) end
    end)

    RegisterNUICallback('RecordPrinter:ForceReleaseFocus', function(_, cb)
        releaseFocus()
        if cb then cb({ ok = true }) end
    end)

    local function releaseFocus()
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
    end

    -- Extra guard: if minimized, make sure focus stays released
    CreateThread(function()
        while true do
            if uiOpen and uiMinimized then
                releaseFocus()
                Wait(100)
            else
                Wait(500)
            end
        end
    end)

    -- =========================
    -- Held-doc prop while UI open
    -- =========================
    CreateThread(function()
        while true do
            Wait(1)
            if holdingDoc then
                DisableControlAction(0, 202, true) -- BACK
                if uiMinimized and IsDisabledControlJustPressed(0, 202) then
                    if uiOpen then
                        SendNuiMessage(json.encode({ action = 'toggleMinimize', recordPrinter = true }))
                        releaseFocus()
                    end
                end
            end
        end
    end)

    -- Allow restoring/minimizing with BACK even after focus was released
    CreateThread(function()
        while true do
            if uiOpen then
                if IsControlJustReleased(0, 202) then
                    SendNuiMessage(json.encode({ action = 'toggleMinimize', recordPrinter = true }))
                    releaseFocus()
                end
                Wait(5)
            else
                Wait(250)
            end
        end
    end)

    function ToggleDocHold(shouldHold)
        if shouldHold and not holdingDoc then
            holdingDoc = true
            local model = GetHashKey(mapModel)
            RequestModel(model)
            while not HasModelLoaded(model) do Wait(50) end
            RequestAnimDict(animDict)
            while not HasAnimDictLoaded(animDict) do Wait(50) end

            ClearPedSecondaryTask(PlayerPedId())
            local plyCoords = GetOffsetFromEntityInWorldCoords(PlayerPedId(), 0.0, 0.0, -5.0)
            local obj = CreateObject(model, plyCoords.x, plyCoords.y, plyCoords.z, 1, 1, 1)
            Wait(250)
            local netid = ObjToNet(obj)
            SetNetworkIdExistsOnAllMachines(netid, true)
            NetworkSetNetworkIdDynamic(netid, true)
            SetNetworkIdCanMigrate(netid, false)
            AttachEntityToEntity(obj, PlayerPedId(), GetPedBoneIndex(PlayerPedId(), 28422), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1, 1, 0, 1, 0, 1)
            TaskPlayAnim(PlayerPedId(), animDict, animName, 1.0, -1, -1, 50, 0, 0, 0, 0)
            map_net = netid

        elseif not shouldHold and holdingDoc then
            holdingDoc = false
            ClearPedSecondaryTask(PlayerPedId())
            if map_net then
                local o = NetToObj(map_net)
                if o and o ~= 0 then
                    DetachEntity(o, 1, 1)
                    DeleteEntity(o)
                end
            end
            map_net = nil
        end
    end
end) end)
