latestFrame = {};

RegisterNetEvent('SonoranCAD::core:TakeScreenshot', function()
	debugLog('Bodycam screenshot capture disabled (screenshot-basic removed).')
end)

RegisterNetEvent('SonoranCAD::core::bodyCamOff', function()
	local source = source
	latestFrame[source] = nil
	local unit = GetUnitByPlayerId(source)
	if unit == nil then
		debugLog('Unit not found')
		-- TriggerClientEvent('SonoranCAD::core::ScreenshotOff', source)
		return
	end
	local screenshotDirectory = exports['sonorancad']:createScreenshotDirectory(tostring(unit.id))
	exports['sonorancad']:deleteDirectory(screenshotDirectory)
end)
