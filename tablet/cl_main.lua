nuiFocused = false
isRegistered = false
usingTablet = false
myident = nil
isMiniVisible = false
local caddisplayEnabled = true

local function requestCadDisplayConfig()
	TriggerServerEvent("SonoranCAD::tabletDisplay::RequestConfig")
end

-- Debugging Information
isDebugging = true

function DebugMessage(message, module)
	if not isDebugging then return end
	if module ~= nil then message = "[" .. module .. "] " .. message end
	print(message .. "\n")
end

-- Initialization Procedure
Citizen.CreateThread(function()
	Wait(1000)
	-- Set Default Module Sizes
	InitModuleSize("cad")
	InitModuleSize("hud")
	InitModuleConfig("hud")
	local apiMode = exports['sonorancad']:getApiMode()
	local tabletURL = ""
	if apiMode == 1 then
		tabletURL = "https://sonorancad.com/"
	elseif apiMode == 0 then
		tabletURL = "https://staging.dev.sonorancad.com/"
	end
	local convar = GetConvar("sonorantablet_cadUrl", tabletURL)
	local comId = convar:match("comid=(%w+)")
	if comId ~= "" and comId ~= nil then
		SetModuleUrl("cad", GetConvar("sonorantablet_cadUrl", tabletURL .. 'login?comid='..comId), true)
	else
		SetModuleUrl("cad", GetConvar("sonorantablet_cadUrl", tabletURL), false)
	end

	TriggerServerEvent("SonoranCAD::mini:CallSync_S")
	requestCadDisplayConfig()

	-- Disable Controls Loop
	while true do
		if nuiFocused then	-- Disable controls while NUI is focused.
			DisableControlAction(0, 1, nuiFocused) -- LookLeftRight
			DisableControlAction(0, 2, nuiFocused) -- LookUpDown
			DisableControlAction(0, 142, nuiFocused) -- MeleeAttackAlternate
			DisableControlAction(0, 106, nuiFocused) -- VehicleMouseControlOverride
		end
		Citizen.Wait(0) -- Yield until next frame.
	end
end)

function InitModuleSize(module)
	-- Check if the size of the specified module is already configured.
	local moduleWidth = GetResourceKvpString(module .. "width")
	local moduleHeight = GetResourceKvpString(module .. "height")
	if moduleWidth ~= nil and moduleHeight ~= nil then
		DebugMessage("retrieving saved presets", module)
		-- Send message to NUI to resize the specified module.
		SetModuleSize(module, moduleWidth, moduleHeight)
		SendNUIMessage({
			type = "refresh",
			module = module
		})
	end
end

function InitModuleConfig(module)
	local moduleMaxRows = GetResourceKvpString(module .. "maxrows")
	if moduleMaxRows ~= nil then
		DebugMessage("retrieving config presets", module)
		-- Send messsage to NUI to update config of specified module.
		SetModuleConfigValue(module, "maxrows", moduleMaxRows)
		SendNUIMessage({
			type = "refresh",
			module = module
		})
	end
end

function SetModuleConfigValue(module, key, value)
	DebugMessage(("MODULE %s Setting %s to %s"):format(module, key, value))
	SendNUIMessage({
		type = "config",
		module = module,
		key = key,
		value = value
	})
	DebugMessage("saving config value to kvp")
	SetResourceKvp(module .. key, value)
end

-- Set a Module's Size
function SetModuleSize(module, width, height)
	DebugMessage(("MODULE %s SIZE %s - %s"):format(module, width, height))
	-- Send message to NUI to resize the specified module.
	DebugMessage("sending resize message to nui", module)
	SendNUIMessage({
		type = "resize",
		module = module,
		newWidth = width,
		newHeight = height
	})

	DebugMessage("saving module size to kvp")
	SetResourceKvp(module .. "width", width)
	SetResourceKvp(module .. "height", height)
end

-- Refresh a Module
function RefreshModule(module)
	DebugMessage("sending refresh message to nui", module)
	SendNUIMessage({
		type = "refresh",
		module = module
	})
end

-- Display a Module
function DisplayModule(module, show)
	DebugMessage("sending display message to nui "..tostring(show), module)
	if not isRegistered then apiCheck = true end
	SendNUIMessage({
		type = "display",
		module = module,
		apiCheck = apiCheck,
		enabled = show
	})
	if module == "hud" then
		isMiniVisible = show
	end
end

-- Set Module URL (for iframes)
function SetModuleUrl(module, url, hasComID)
	DebugMessage("sending url update message to nui", module)
	SendNUIMessage({
		type = "setUrl",
		url = url,
		module = module,
		comId = hasComID
	})
end

-- Print a chat message to the current player
function PrintChatMessage(text)
	TriggerEvent('chatMessage', "System", { 255, 0, 0 }, text)
end

-- Set the focus state of the NUI
function SetFocused(focused)
	nuiFocused = focused
	SetNuiFocus(nuiFocused, nuiFocused)
end

-- Remove NUI focus
RegisterNUICallback('NUIFocusOff', function()
	print('NUI Focus Off Received')
	DisplayModule("cad", false)
	toggleTabletDisplay(false)
	SetFocused(false)
end)

RegisterNetEvent("SonoranCAD::mini:OpenMini:Return")
AddEventHandler('SonoranCAD::mini:OpenMini:Return', function(authorized, ident)
	myident = ident
	if authorized then
		DisplayModule("hud", true)
		if not GetResourceKvpString("shownTutorial") then
			ShowHelpMessage()
			SetResourceKvp("shownTutorial", "yes")
		end
	else
		PrintChatMessage("You are not logged into the CAD or your account is not linked. Run /link first.")
	end
end)

CreateThread(function()
	while true do
		if isMiniVisible then
			TriggerServerEvent("SonoranCAD::mini:CallSync_S")
		end
		Wait(10000)
	end
end)

function ShowHelpMessage()
	PrintChatMessage("Keybinds: Attach/Detach [K], Details [L], Previous/Next [LEFT/RIGHT], changable in settings!")
end

-- Mini Module Commands
RegisterCommand("minicad", function(source, args, rawCommand)
	TriggerServerEvent("SonoranCAD::mini:OpenMini")
end, false)
RegisterKeyMapping('minicad', 'Mini CAD', 'keyboard', '')

RegisterCommand("minicadhelp", function() ShowHelpMessage() end)

RegisterCommand("minicadp", function(source, args, rawCommand)
	if not isMiniVisible then return end
	SendNUIMessage({ type = "command", key="prev" })
end, false)
RegisterKeyMapping('minicadp', 'Previous Call', 'keyboard', 'LEFT')

RegisterCommand("minicada", function(source, args, rawCommand)
	print("ismini "..tostring(isMiniVisible))
	if not isMiniVisible then return end
	SendNUIMessage({ type = "command", key="attach" })
end, false)
RegisterKeyMapping('minicada', 'Attach to Call', 'keyboard', 'K')

RegisterCommand("minicadd", function(source, args, rawCommand)
	if not isMiniVisible then return end
	SendNUIMessage({ type = "command", key="detail" })
end, false)
RegisterKeyMapping('minicadd', 'Call Detail', 'keyboard', 'L')

RegisterCommand("minicadn", function(source, args, rawCommand)
	if not isMiniVisible then return end
	SendNUIMessage({ type = "command", key="next" })
end, false)
RegisterKeyMapping('minicadn', 'Next Call', 'keyboard', 'RIGHT')

TriggerEvent('chat:addSuggestion', '/minicadsize', "Resize the Mini-CAD to specific width and height in pixels.", {
	{ name="Width", help="Width in pixels" }, { name="Height", help="Height in pixels" }
})
RegisterCommand("minicadsize", function(source,args,rawCommand)
	if not args[1] and not args[2] then return end
	SetModuleSize("hud", args[1], args[2])
end)
RegisterCommand("minicadrefresh", function()
	RefreshModule("hud")
end)

RegisterCommand("minicadrows", function(source, args, rawCommand)
	if #args ~= 1 then
		PrintChatMessage("Please specify a number of rows to display.")
		return
	else
		SetModuleConfigValue("hud", "maxrows", tonumber(args[1]) - 1)
		PrintChatMessage("Maximum Mini-CAD call notes set to " .. args[1])
	end
end)
TriggerEvent('chat:addSuggestion', '/minicadrows', "Specify max number of call notes on Mini-CAD.", {
	{ name="rows", help="any number (default 10)" }
})

-- CAD Module Commands
RegisterCommand("showcad", function(source, args, rawCommand)
	DisplayModule("cad", true)
	toggleTabletDisplay(true)
	SetFocused(true)
end, false)
RegisterKeyMapping('showcad', 'CAD Tablet', 'keyboard', '')

TriggerEvent('chat:addSuggestion', '/cadsize', "Resize CAD to specific width and height in pixels. Default is 1280x640 (16:9-ish)", {
	{ name="Width", help="Width in pixels" }, { name="Height", help="Height in pixels" }
})
RegisterCommand("cadsize", function(source,args,rawCommand)
	if not args[1] and not args[2] then return end
	SetModuleSize("cad", args[1], args[2])
end)
RegisterCommand("cadrefresh", function()
	RefreshModule("cad")
end)

local function requestTabletLinkStatus()
	TriggerServerEvent("SonoranCAD::Tablet::CheckLinkStatus")
end

RegisterCommand("checkcadlink", function(source,args,rawCommand)
	requestTabletLinkStatus()
end, false)

local activeTablet = nil
local tabletDisplayModel = "sf_prop_sf_tablet_01a"
local tabletDisplayTxdName = "sf_prop_sf_tablet_01a"
local tabletDisplayTextures = {"prop_arena_tablet_drone_screen_d", "prop_tablet_screen"}
local tabletRuntimeTxdName = "tabletdisplay_screen"
local tabletRuntimeTextureName = "tabletdisplay_screen_texture"
local tabletDui = nil
local tabletDuiObjects = {}
local tabletActiveRequests = {}
local tabletScreenshotInterval = 5000
local nextTabletScreenshot = 0
local tabletLastBroadcastImage = nil

local function waitForTabletEntity(timeoutMs)
	local deadline = GetGameTimer() + (timeoutMs or 2000)
	while (not activeTablet or not DoesEntityExist(activeTablet)) and GetGameTimer() < deadline do
		Wait(50)
	end
	return activeTablet and DoesEntityExist(activeTablet)
end

local function applyTabletTextureReplacement(duiHandle)
	if not duiHandle then return end
	local txd = CreateRuntimeTxd(tabletRuntimeTxdName)
	CreateRuntimeTextureFromDuiHandle(txd, tabletRuntimeTextureName, duiHandle)
	for _, textureName in ipairs(tabletDisplayTextures) do
		AddReplaceTexture(tabletDisplayTxdName, textureName, tabletRuntimeTxdName, tabletRuntimeTextureName)
	end
end

local function debugTabletPropTextures()
	if not isDebugging then return end
	CreateThread(function()
		DebugMessage("Tablet prop texture scan starting", "tablet")
		local hasEntity = waitForTabletEntity(2000)
		DebugMessage(("Tablet entity ready=%s"):format(tostring(hasEntity)), "tablet")
		local modelHash = GetHashKey(tabletDisplayModel)
		RequestModel(modelHash)
		local modelTimeout = GetGameTimer() + 2000
		while not HasModelLoaded(modelHash) and GetGameTimer() < modelTimeout do
			Wait(0)
		end
		DebugMessage(("Tablet model %s loaded=%s"):format(tabletDisplayModel, tostring(HasModelLoaded(modelHash))), "tablet")
		local dictName = tabletDisplayTxdName
		if type(RequestStreamedTextureDict) == "function" then
			RequestStreamedTextureDict(dictName, false)
			local dictTimeout = GetGameTimer() + 2000
			while type(HasStreamedTextureDictLoaded) == "function"
				and not HasStreamedTextureDictLoaded(dictName)
				and GetGameTimer() < dictTimeout do
				Wait(0)
			end
		end
		local dictExists = "unknown"
		if type(DoesStreamedTxdExist) == "function" then
			dictExists = tostring(DoesStreamedTxdExist(dictName))
		elseif type(DoesStreamedTextureDictExist) == "function" then
			dictExists = tostring(DoesStreamedTextureDictExist(dictName))
		end
		local dictLoaded = "unknown"
		if type(HasStreamedTextureDictLoaded) == "function" then
			dictLoaded = tostring(HasStreamedTextureDictLoaded(dictName))
		end
		DebugMessage(("Texture dict %s (exists=%s, loaded=%s)"):format(dictName, dictExists, dictLoaded), "tablet")
		for _, textureName in ipairs(tabletDisplayTextures) do
			local res = GetTextureResolution(dictName, textureName)
			local width = res and math.floor(res.x or 0) or 0
			local height = res and math.floor(res.y or 0) or 0
			local sizeLabel = (width > 0 or height > 0) and ("%dx%d"):format(width, height) or "missing"
			DebugMessage((" - %s (%s)"):format(textureName, sizeLabel), "tablet")
		end
		if HasModelLoaded(modelHash) then
			SetModelAsNoLongerNeeded(modelHash)
		end
	end)
end

local function ensureTabletDui()
	if not caddisplayEnabled then
		return
	end
	if tabletDui ~= nil then
		return
	end
	local htmlPath = ("nui://%s/html/display.html"):format(GetCurrentResourceName())
	tabletDui = CreateDui(htmlPath, 512, 256)
	local duiHandle = GetDuiHandle(tabletDui)
	applyTabletTextureReplacement(duiHandle)
	debugTabletPropTextures()
	table.insert(tabletDuiObjects, tabletDui)
end

local function destroyTabletDuiObjects()
	for _, duiObj in ipairs(tabletDuiObjects) do
		if IsDuiAvailable(duiObj) then
			DestroyDui(duiObj)
		end
	end
	tabletDuiObjects = {}
	tabletDui = nil
	tabletLastBroadcastImage = nil
end

RegisterNetEvent("SonoranCAD::tabletDisplay::Config")
AddEventHandler("SonoranCAD::tabletDisplay::Config", function(config)
	caddisplayEnabled = config and config.enabled == true
	if not caddisplayEnabled then
		tabletActiveRequests = {}
		tabletLastBroadcastImage = nil
		destroyTabletDuiObjects()
	end
end)

local function updateTabletDui(payload)
	if tabletDui and IsDuiAvailable(tabletDui) then
		SendDuiMessage(tabletDui, json.encode(payload or {}))
	end
end
local function sendCadScreenshotRequest(requestId)
	if not caddisplayEnabled then
		return
	end
	SendNUIMessage({
		type = "caddisplay_screenshot_request",
		requestId = requestId
	})
end

-- Request a CAD screenshot (for caddisplay) and forward responses back via a client event.
RegisterNetEvent("SonoranCAD::Tablet::RequestCadScreenshot")
AddEventHandler("SonoranCAD::Tablet::RequestCadScreenshot", function(requestId)
	if not caddisplayEnabled or not requestId then return end
	sendCadScreenshotRequest(requestId)
end)

RegisterNetEvent("SonoranCAD::Tablet::CadScreenshotResponse")
AddEventHandler("SonoranCAD::Tablet::CadScreenshotResponse", function(requestId, image)
	if not caddisplayEnabled then
		return
	end
	if not tabletActiveRequests[requestId] then
		return
	end
	tabletActiveRequests[requestId] = nil
	if not image or image == "" then
		return
	end
	ensureTabletDui()
	updateTabletDui({type = "cad_image", image = image})
	if image ~= tabletLastBroadcastImage then
		tabletLastBroadcastImage = image
		TriggerLatentServerEvent("SonoranCAD::tabletDisplay::BroadcastCadScreenshot", 0, image)
	end
end)

RegisterNetEvent("SonoranCAD::tabletDisplay::UpdateDui")
AddEventHandler("SonoranCAD::tabletDisplay::UpdateDui", function(ownerId, image)
	if not caddisplayEnabled then
		return
	end
	if not image or image == "" then
		return
	end
	if usingTablet and ownerId ~= GetPlayerServerId(PlayerId()) then
		return
	end
	ensureTabletDui()
	updateTabletDui({type = "cad_image", image = image})
end)

-- Helper to load an animation dictionary
local function ensureAnimDict(dictName)
    RequestAnimDict(dictName)
    while not HasAnimDictLoaded(dictName) do
        Citizen.Wait(0)
    end
end

-- Helper to load a model by hash
local function ensureModel(modelHash)
    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Citizen.Wait(100)
    end
end

function toggleTabletDisplay(enable)
    local ped      = PlayerPedId()
    local animDict = "amb@code_human_in_bus_passenger_idles@female@tablet@base"
    local enter    = "base"
    local exit     = "exit"
    local model    = GetHashKey("sf_prop_sf_tablet_01a")
    local bone     = GetPedBoneIndex(ped, 60309)

	usingTablet = enable
	if enable then
        -- pull out tablet
		nextTabletScreenshot = 0
		tabletLastBroadcastImage = nil
		if caddisplayEnabled then
			ensureTabletDui()
		end
        ensureAnimDict(animDict)
        ensureModel(model)

        activeTablet = CreateObject(model, 1.0, 1.0, 1.0, true, true, false)
        SetEntityLodDist(activeTablet, 9999)
        AttachEntityToEntity(
            activeTablet,
            ped,
            bone,
            0.03, 0.002, 0.0,    -- position offsets
            10.0, 0.0, 0.0,    -- rotation offsets
            false, false, false, -- collision, vertex, etc.
            false, 2, true       -- isNetworked, boneIndex, useSoftPinning
        )

        TaskPlayAnim(ped, animDict, enter, 3.0, 3.0, -1, 49, 0, false, false, false)
    else
        -- put tablet away
		tabletActiveRequests = {}
		tabletLastBroadcastImage = nil
        if activeTablet then
            DetachEntity(activeTablet, true, true)
            DeleteObject(activeTablet)
            activeTablet = nil
        end
        TaskPlayAnim(ped, animDict, exit, 3.0, 3.0, -1, 49, 0, false, false, false)
    end
end

CreateThread(function()
	while true do
		Wait(250)
		if usingTablet and caddisplayEnabled then
			local now = GetGameTimer()
			if now >= nextTabletScreenshot then
				local requestId = ("tabletdisplay-%d-%d"):format(GetPlayerServerId(PlayerId()), now)
				tabletActiveRequests[requestId] = true
				TriggerEvent("SonoranCAD::Tablet::RequestCadScreenshot", requestId)
				nextTabletScreenshot = now + tabletScreenshotInterval
			end
		end
	end
end)

-- Mini-Cad Callbacks
RegisterNUICallback('AttachToCall', function(data, cb)
	--Debug Only
	--print("cl_main -> sv_main: SonoranCAD::mini:AttachToCall")
	TriggerServerEvent("SonoranCAD::mini:AttachToCall", data.callId)
	cb({ ok = true })
end)

-- Mini-Cad Callbacks
RegisterNUICallback('DetachFromCall', function(data, cb)
	--Debug Only
	--print("cl_main -> sv_main: SonoranCAD::mini:DetachFromCall")
	TriggerServerEvent("SonoranCAD::mini:DetachFromCall", data.callId)
	cb({ ok = true })
end)

RegisterNUICallback("ShowHelp", function() ShowHelpMessage() end)

RegisterNUICallback("VisibleEvent", function(data, cb)
	if data.module == "hud" then
		isMiniVisible = data.state
	end
	cb({ ok = true })
end)

-- Mini-Cad Events
RegisterNetEvent("SonoranCAD::mini:CallSync")
AddEventHandler("SonoranCAD::mini:CallSync", function(CallCache, EmergencyCache)
	--Debug Only
	--print("sv_main -> cl_main: SonoranCAD::mini:CallSync")
	--print(json.encode(CallCache))
	SendNUIMessage({
		type = 'callSync',
		ident = myident,
		activeCalls = CallCache,
		emergencyCalls = EmergencyCache
	})
end)

AddEventHandler('onClientResourceStart', function(resourceName) --When resource starts, stop the GUI showing.
	if(GetCurrentResourceName() ~= resourceName) then
		return
	end
	SetFocused(false)
	requestTabletLinkStatus()
	requestCadDisplayConfig()
end)

AddEventHandler("onClientResourceStop", function(resourceName)
	if GetCurrentResourceName() ~= resourceName then
		return
	end
	destroyTabletDuiObjects()
end)

RegisterNetEvent("SonoranCAD::Tablet::LinkMissing")
AddEventHandler('SonoranCAD::Tablet::LinkMissing', function()
	isRegistered = false
	SendNUIMessage({
		type = "regbar"
	})
end)

RegisterNetEvent("SonoranCAD::Tablet::LinkFound")
AddEventHandler("SonoranCAD::Tablet::LinkFound", function()
	isRegistered = true
end)

RegisterNUICallback('SetLinkInformation', function(data,cb)
	TriggerServerEvent("SonoranCAD::Tablet::AssociateSsoData", data.session, data.username)
	requestTabletLinkStatus()
	cb(true)
end)

RegisterNUICallback('runLinkCheck', function()
	requestTabletLinkStatus()
end)

RegisterNetEvent("sonoran:tablet:failed")
AddEventHandler("sonoran:tablet:failed", function(message)
	errorLog("Failed to link CAD account: "..tostring(message))
end)

RegisterNUICallback("CadDisplayScreenshot", function(data, cb)
	if not caddisplayEnabled then
		if cb then cb({ ok = true }) end
		return
	end
	TriggerEvent("SonoranCAD::Tablet::CadScreenshotResponse", data.requestId, data.image)
	if cb then cb({ ok = true }) end
end)
