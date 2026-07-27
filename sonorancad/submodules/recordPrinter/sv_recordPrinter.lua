--[[
    Sonaran CAD Plugins

    Plugin Name: recordprinter
    Creator: Sonoran Software
    Description: Integrates SonoranCAD PDFs in-game.
]]
CreateThread(function() Config.LoadPlugin("recordPrinter", function(pluginConfig)
    local function notifyPlayer(target, payload)
        NotifyPlayer(target, ApplyPluginNotificationOverrides(pluginConfig, payload))
    end

    TriggerEvent('SonoranCAD::RegisterPushEvent', 'EVENT_PRINT_RECORD', function(data)
        local printData = data.data
        local unitCache = GetUnitCache()
        -- local userId = GetUnitById(printData.identId)
        -- print('record printer received print request for', printData.identId, 'from user', json.encode(userId))
        local unitInCache = nil
        for _, unit in pairs(unitCache) do
            if unit.id == printData.identId then
                unitInCache = unit
                break
            end
        end
        local unitSource = GetSourceByCadIdentity(GetUnitIdentityValues(unitInCache))
        if not unitSource then
            return warnLog(
                "RECORDPRINTER_UNIT_MISSING",
                ('Print request ignored for CAD identity %s because no active unit source was found.'):format(
                    tostring(printData.identId)
                )
            )
        end

        local function callAsyncExport(callback)
            local ok, result = pcall(function()
                local value = callback()
                if type(value) == 'table' or type(value) == 'userdata' then
                    return Citizen.Await(value)
                end
                return value
            end)
            if not ok then
                return nil, tostring(result)
            end
            return result, nil
        end

        local function isPermissionError(details)
            local normalized = tostring(details or ''):lower()
            return normalized:find('eacces', 1, true)
                or normalized:find('eperm', 1, true)
                or normalized:find('permission denied', 1, true)
                or normalized:find('operation not permitted', 1, true)
        end

        local identId = tostring(printData.identId or 'unknown')
        debugLog(('Record printer preparing output directory for CAD identity %s.'):format(identId))
        local pdfDirectory, directoryError = callAsyncExport(function()
            return exports['sonorancad']:createPDFDirectory(identId)
        end)
        if pdfDirectory == '' then
            pdfDirectory = nil
        end
        if not pdfDirectory then
            local details = ('CAD identity=%s resourcePath=%s details=%s'):format(
                identId,
                tostring(GetResourcePath(GetCurrentResourceName())),
                tostring(directoryError or 'export returned no directory')
            )
            if isPermissionError(directoryError) then
                errorLog("RECORDPRINTER_FILESYSTEM_PERMISSION", details)
            else
                errorLog("RECORDPRINTER_DIRECTORY_FAILED", details)
            end
            return
        end
        debugLog(('Record printer output directory ready: identity=%s path=%s'):format(identId, pdfDirectory))

        local filename = printData.url:match("^.+/(.+)$") or (('record_%s.pdf'):format(os.time()))
        local filePath = pdfDirectory .. '/' .. filename
        debugLog(('Record printer downloading PDF: identity=%s destination=%s'):format(identId, filePath))
        local savedPath, saveError = callAsyncExport(function()
            return exports['sonorancad']:savePdfFromUrl(printData.url, filePath)
        end)
        if not savedPath or savedPath == '' then
            local details = ('CAD identity=%s destination=%s details=%s'):format(
                identId,
                filePath,
                tostring(saveError or 'export returned no saved path')
            )
            if isPermissionError(saveError) then
                errorLog("RECORDPRINTER_FILESYSTEM_PERMISSION", details)
            else
                errorLog("RECORDPRINTER_SAVE_FAILED", details)
            end
            return
        end
        debugLog(('Record printer saved PDF: identity=%s path=%s'):format(identId, savedPath))

        local resourceName = GetCurrentResourceName()
        local pdfLink = ('nui://%s/submodules/recordPrinter/pdfs/%s/%s'):format(resourceName, identId, filename)
        TriggerClientEvent('SonoranCAD::recordPrinter:PrintQueue', unitSource, pdfLink)

    end)
    local Docs = {}
    local ESX = nil
    local QBCore = nil

    if pluginConfig.frameworks.use_qbcore then
        QBCore = exports['qb-core']:GetCoreObject()
    end
    if pluginConfig.frameworks.use_esx then
        ESX = exports['es_extended']:getSharedObject()
    end

    if not pluginConfig.translations then
        pluginConfig.translations = {
            placedInPocketPutCamAway = 'Document placed in pocket!',
            placedInPocket = 'Document placed in pocket!',
            putAwayCamera = 'Put away the document with: ~INPUT_LOOK_RIGHT_ONLY~',
            imageDropped = 'Document dropped!',
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
    end

    local function loadConfig()
        local loaded = LoadResourceFile(GetCurrentResourceName(), 'submodules/recordPrinter/pdfs.json')
        if loaded and loaded ~= '' then
            Docs = json.decode(loaded) or {}
        else
            Docs = {}
            SaveResourceFile(GetResourcePath(GetCurrentResourceName()),'/submodules/recordPrinter/pdfs.json', json.encode(Docs), -1)
        end
    end

    local function saveDocs()
        SaveResourceFile(GetResourcePath(GetCurrentResourceName()),'/submodules/recordPrinter/pdfs.json', json.encode(Docs), -1)
    end

    ---------------------------------------
    -- Events - Don't Touch (Use Config) --
    ---------------------------------------

    -- Drop/save a PDF into the world at given coords
    RegisterNetEvent('SonoranPDF:SaveToWorld', function(pdfUrl, x, y, z)
        local newDoc = { ['pdf_link'] = pdfUrl, ['Position'] = { ['x'] = x, ['y'] = y, ['z'] = z } }
        table.insert(Docs, newDoc)
        saveDocs()
        TriggerEvent('SonoranPDF:Server:BroadcastDocs')
    end)

    RegisterNetEvent('SonoranCAD::recordPrinter:ShareRecord', function(recordUrl, sharedBy, targetList)
        local src = source
        if type(recordUrl) ~= 'string' or recordUrl == '' then return end

        -- Basic allowlist for expected URLs (external https or local NUI file)
        if not (recordUrl:match("^https?://") or recordUrl:match("^nui://")) then
            warnLog("RECORDPRINTER_SHARE_INVALID", ('ShareRecord received an invalid URL from source %s.'):format(src))
            return
        end

        local senderName = sharedBy
        if not senderName or senderName == '' then
            senderName = GetPlayerName(src) or ('ID %s'):format(src)
        end

        local targets = {}
        local seen = {}
        if type(targetList) == 'table' then
            for _, tid in ipairs(targetList) do
                tid = tonumber(tid)
                if tid and tid ~= src and GetPlayerName(tid) and not seen[tid] then
                    table.insert(targets, tid)
                    seen[tid] = true
                end
            end
        end

        -- If no valid targets remain, bail instead of broadcasting to everyone.
        if #targets == 0 then
            warnLog("RECORDPRINTER_SHARE_INVALID", ('ShareRecord received no valid targets from source %s.'):format(src))
            return
        end

        for _, target in ipairs(targets) do
            TriggerClientEvent('SonoranCAD::recordPrinter:RecordShared', target, recordUrl, senderName, "direct")
        end
    end)

    RegisterNetEvent('SonoranCAD::recordPrinter:EmailQueue', function(queueUrls, sharedBy, targetId)
        local src = source
        local target = tonumber(targetId)
        if not target then return end
        if type(queueUrls) ~= 'table' or #queueUrls == 0 then return end

        local senderName = sharedBy
        if not senderName or senderName == '' then
            senderName = GetPlayerName(src) or ('ID %s'):format(src)
        end

        for _, url in ipairs(queueUrls) do
            if type(url) == 'string' and url ~= '' then
                TriggerClientEvent('SonoranCAD::recordPrinter:RecordShared', target, url, senderName, "email")
            end
        end
    end)

    -- Inventory put-away: QB
    RegisterNetEvent('SonoranPDF:PutAway:QB:First', function(pdfUrl)
        if not pluginConfig.frameworks.use_qbcore then return end
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then print('player no exist?') return end
        local info = {}
        info.pdf_link = pdfUrl
        Player.Functions.AddItem('sonoran_evidence_pdf', 1, nil, info)
    end)

    -- Inventory put-away: Quasar
    RegisterNetEvent('SonoranPDF:PutAway:Quasar:First', function(pdfUrl)
        TriggerEvent('qs-inventory:addItem', source, 'sonoran_evidence_pdf', 1, false, { pdf_link = pdfUrl })
    end)

    -- Inventory put-away: ESX + ox_inventory
    RegisterNetEvent('SonoranPDF:PutAway:ESX:First', function(pdfUrl)
        if not pluginConfig.frameworks.use_esx then return end
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return end
        local ox_inventory = exports.ox_inventory
        local info = { pdf_link = pdfUrl }

        if ox_inventory:CanCarryItem(source, 'sonoran_evidence_pdf', 1) then
            ox_inventory:AddItem(source, 'sonoran_evidence_pdf', 1, info, nil, function(success, reason) end)
        else
            notifyPlayer(source, {
                title = "Record Printer",
                message = pluginConfig.translations.couldNotHold,
                type = "error"
            })
            return
        end

        -- -- ensure metadata is set
        -- local item = ox_inventory:Search(source, 1, 'sonoran_evidence_pdf')
        -- for _, v in pairs(item) do
        --     item = v
        --     break
        -- end
        -- if item and item.slot and item.metadata then
        --     item.metadata.pdf_link = pdfUrl
        --     ox_inventory:SetMetadata(source, item.slot, item.metadata)
        -- end
    end)

    -- ox_inventory export handler for using the PDF item (ESX)
    exports('sonoran_evidence_pdf', function(event, item, inventory, slot, data)
        if event == 'usingItem' then
            local link = inventory.items[slot].metadata.pdf_link
            TriggerClientEvent('sonoran:lookpdf:esx', inventory.player.source, { metadata = { pdf_link = link } })
        end
    end)

    -- Broadcast updated world docs to all clients
    RegisterNetEvent('SonoranPDF:Server:BroadcastDocs', function()
        if #Docs ~= 0 then
            TriggerClientEvent('SonoranPDF:client:updatePDFs', -1, Docs)
        end
    end)

    -- Provide current world docs to a single client
    RegisterNetEvent('SonoranPDF:Server:RequestAll', function()
        if #Docs ~= 0 then
            TriggerClientEvent('SonoranPDF:client:updatePDFs', source, Docs)
        end
    end)

    -- Destroy a world PDF by index
    RegisterNetEvent('SonoranPDF:destroyWorldPDF', function(docID)
        if Docs[docID] ~= nil then
            table.remove(Docs, docID)
            saveDocs()
            TriggerEvent('SonoranPDF:Server:BroadcastDocs')
        end
    end)

    -----------------------------------------
    -- Handlers - Don't Touch (Use Config) --
    -----------------------------------------
    loadConfig()

    -- push existing docs to clients on start
    TriggerEvent('SonoranPDF:Server:BroadcastDocs')
    TriggerEvent(GetCurrentResourceName() .. '::StartUpdateLoop') -- keep if used elsewhere

    -- QB item
    if pluginConfig.frameworks.use_qbcore then
        exports['qb-core']:AddItem('sonoran_evidence_pdf', {
            name = 'sonoran_evidence_pdf',
            label = 'Evidence PDF',
            weight = 0,
            type = 'item',
            image = 'evidence.png',
            unique = true,
            useable = true,
            shouldClose = false,
            combinable = nil,
            description = pluginConfig.translations.photoDescription
        })
        QBCore.Functions.CreateUseableItem('sonoran_evidence_pdf', function(source, item)
            -- item.info.pdf_link
            TriggerClientEvent('sonoran:lookpdf:qbcore', source, item)
        end)
    end

    -- ESX items (keep camera item registration removed; only PDF)
    if pluginConfig.frameworks.use_esx and not pluginConfig.frameworks.use_esx_ox_inventory then
        ESX.RegisterUsableItem('sonoran_evidence_pdf', function(source)
            local ox_inventory = exports.ox_inventory
            local results = ox_inventory:Search(source, 1, 'sonoran_evidence_pdf')
            local entry
            for _, v in pairs(results) do entry = v; break end
            if entry then
                TriggerClientEvent('sonoran:lookpdf:esx', source, entry)
            end
        end)
    end

end) end)
