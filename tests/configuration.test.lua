-- Run from the repository root: lua tests/configuration.test.lua
-- FiveM IO/time and JSON serialization are doubled; production resolution,
-- migration, adapter and every shipped plugin parser are exercised directly.
local function read(path)
    local f = assert(io.open(path, 'rb')); local text = f:read('*a'); f:close(); return text
end
local function clone(value)
    if type(value) ~= 'table' then return value end
    local copy = {}; for k, v in pairs(value) do copy[k] = clone(v) end; return copy
end
local encoded, counter = {}, 0
json = {
    encode = function(value)
        counter = counter + 1; local key = '{"test-json-id":' .. counter .. '}'; encoded[key] = clone(value); return key
    end,
    decode = function(value) assert(encoded[value], 'Invalid JSON'); return clone(encoded[value]) end
}
local files, convars, handlers, threads, logs, writes, archiveCalls, now, replies
local registry = {}
exports = setmetatable({sonorancad = {
    GetCadConfigurationScope = function(_, _, serverId, _, mock) return 'scope:'..tostring(serverId)..(mock and ':mock' or ':cad') end,
    WriteCadBootstrapConfiguration = function(_, apiKey, serverId)
        if convars.failBootstrap then return false end
        files['config.json']=json.encode({apiKey=apiKey,serverId=serverId}); return true
    end,
    WriteCadConfiguration = function(_, kind, content)
        if convars.failWrite then return false end
        files[kind == 'mock' and '.configuration-mock.json' or '.configuration-cache.json'] = content
        writes = writes + 1; return true
    end,
    ListLegacyCadConfiguration = function(_, directory)
        return json.encode({files = directory and files.templateInventory or files.inventory, plugins = {'kick', 'custom'}})
    end,
    ArchiveLegacyCadConfiguration = function()
        archiveCalls = archiveCalls + 1
        assert(files['.configuration-cache.json'], 'Archive must follow the cache write')
        local root=json.decode(files['config.json'])
        local count=0;for _ in pairs(root) do count=count+1 end
        assert(count==2 and root.apiKey==Config.apiKey and root.serverId==Config.serverId,
            'Archive must follow persistence of the two-field root config')
        assert(logs[#logs]:find('Restart'), 'Restart instruction must precede archive')
        if convars.throwArchive then error('Unsupported archive export') end
        return not convars.failArchive
    end
}}, {__call = function(_, name, fn) registry[name] = fn end})
function GetCurrentResourceName() return 'sonorancad' end
function GetConvar(key, fallback) return convars[key] or fallback end
function SetConvar(key, value) convars[key] = value end
function GetGameTimer() return now end
function LoadResourceFile(_, path) return files[path] end
function RegisterNetEvent() end
function AddEventHandler(name, fn) handlers[name] = fn end
function TriggerClientEvent(...) replies = {...} end
function IsDuplicityVersion() return true end
function warnLog(_, text) logs[#logs + 1] = text end
errorLog = warnLog
function infoLog(text) logs[#logs + 1] = text end
local notices = {}
function warningNotice(text) notices[#notices + 1] = text; logs[#logs + 1] = text end
function CreateThread(fn) threads[#threads + 1] = {co = coroutine.create(fn), at = now} end
function Wait(ms) coroutine.yield(ms) end
function vector3(x, y, z) return {x=x, y=y, z=z} end
local function runUntil(predicate, limit)
    local deadline = now + (limit or 20000)
    while not predicate() do
        table.sort(threads, function(a,b) return a.at < b.at end)
        local task = table.remove(threads, 1); assert(task and task.at <= deadline, 'Timed out')
        now = task.at
        local ok, delay = coroutine.resume(task.co); assert(ok, delay)
        if coroutine.status(task.co) ~= 'dead' then task.at = now + (delay or 1); threads[#threads + 1] = task end
    end
end
local function document()
    return {core = {communityID='test', mode='production', primaryIdentifier='license', postTime=5000, apiSendEnabled=true, debugMode=false},
        plugins = {kick = {pluginName='kick', configVersion='1.0', enabled=true}},
        updaterIgnore={ignore={}}, vehicleModels={car={type='SEDAN'}}, callTemplates={}}
end
local legacy = 'local config = {enabled=true, pluginName="kick", configVersion="1.0"}\n' ..
    'if config.enabled then Config.RegisterPluginConfig(config.pluginName, config) end'
local function setup(status, data, cached, rootConfig, legacyServerId, legacyMode)
    notices = {}
    files, convars, handlers, threads, logs, now, writes, archiveCalls = {}, {}, {}, {}, {}, 0, 0, 0
    Config, Plugins, replies = nil, nil, nil
    convars.sonoran_communityID='test'; convars.sonoran_apiKey='secret'; convars.sonoran_serverId='1'
    convars.sonoran_debugMode='true' -- CAD must override this ordinary setting.
    files['configuration/config.json'] = json.encode({communityID='test', apiKey='secret', serverId=legacyServerId or 1, mode=legacyMode,
        primaryIdentifier='license', postTime=5000, apiSendEnabled=true, debugMode=false})
    if rootConfig then files['config.json']=type(rootConfig)=='string' and rootConfig or json.encode(rootConfig) end
    files['configuration/kick_config.lua']=legacy
    files.inventory={'config.json', 'kick_config.dist.lua', 'kick_config.lua'}
    files['configuration/kick_config.dist.lua']='invalid default must not replace active file'
    if cached then files['.configuration-cache.json'] = json.encode({version=1, scope='scope:1:cad', apiVersion=3, configuration=cached}) end
    dofile('sonorancad/core/shared_functions.lua')
    dofile('sonorancad/core/sonoran_api.lua')
    CadConfigurationApi.request = function(_, _, cb) cb(status, clone(data)) end
    dofile('sonorancad/core/configuration.lua')
    threads[3]=nil; threads[2]=nil -- Unrelated existing server-registration/diagnostic threads.
    runUntil(function() return Config.configurationReady end)
    if not Config.critError then Config.apiVersion=3 end
end

setup(200, document())
assert(Config.configurationSource=='cad' and Config.debugMode==false and writes==1)
assert(Config.GetPluginConfig('kick').enabled and not Config.GetPluginConfig('missing').enabled)
Config.RegisterPluginConfig('kick', {enabled=false})
assert(Config.GetPluginConfig('kick').enabled, 'Local registration overrode CAD')
source=5; handlers['SonoranCAD::core:requestPluginConfig']('kick')
assert(replies[2]==5 and replies[4].pluginName=='kick' and replies[4].apiKey==nil)

local activeRoot=json.decode(files['config.json'])
assert(activeRoot.apiKey=='secret' and activeRoot.serverId==1 and activeRoot.communityID==nil and activeRoot.branch==nil)
setup(200, document(), nil, {apiKey='root-key',serverId=7})
assert(Config.apiKey=='root-key' and Config.serverId==7, 'Legacy/convars superseded root config.json')
assert(Config.communityID=='test' and Config.mode=='production' and Config.apiUrl=='https://api.sonorancad.com/')
local stored=json.decode(files['.configuration-cache.json']).configuration.core
assert(stored.mode=='production' and stored.branch==nil and stored.apiUrl==nil,
    'CAD cache must contain mode without an API URL')
setup(200, document(), nil, {apiKey='root-key',serverId=7,branch='development'})
assert(Config.critError and Config.bootstrapError, 'Extra root configuration keys were accepted')
setup(200, document(), nil, {apiKey='root-key',serverId='7'})
assert(Config.critError and Config.bootstrapError, 'Non-numeric server ID was accepted')
setup(200,document(),nil,'{broken')
assert(Config.critError and Config.bootstrapError, 'Malformed nonempty root config was accepted')
local routed=document(); routed.core.mode='development'
setup(200, routed, nil, {apiKey='root-key',serverId=7})
assert(Config.mode=='development' and Config.apiUrl=='https://staging-api.dev.sonorancad.com/')
setup(503, nil, routed)
assert(Config.configurationSource=='cache' and Config.mode=='development' and Config.apiUrl=='https://staging-api.dev.sonorancad.com/')
local oldCache=clone(routed);oldCache.core.mode=nil;oldCache.core.branch='development';oldCache.core.apiUrl='https://obsolete-api.example.test/'
setup(503,nil,oldCache)
assert(Config.configurationSource=='cache' and Config.mode=='development' and Config.apiUrl=='https://staging-api.dev.sonorancad.com/',
    'Earlier test cache did not normalize mode or discarded URL')
local incomplete=document();incomplete.core.communityID=nil
setup(200,incomplete)
assert(Config.critError, 'CAD configuration without community ID was activated')
incomplete=document();incomplete.core.mode=nil
setup(200,incomplete)
assert(Config.critError, 'CAD configuration without mode was activated')
incomplete=document();incomplete.core.mode='unknown'
setup(200,incomplete)
assert(Config.critError, 'CAD configuration with invalid mode was activated')

setup(404, nil, document())
assert(Config.critError and writes==0 and archiveCalls==0 and Config.configurationSource~='legacy',
    'A previously migrated server returned to legacy settings')
setup(404)
assert(not Config.critError and Config.configurationSource=='legacy' and Config.apiSendEnabled)
assert(Config.GetPluginConfig('kick').enabled and writes==0 and archiveCalls==0)
local migrationNotice='Configuration migration required. Run: sonorancad migrate. https://snorn.link/configmigration'
assert(#logs==1 and #notices==1 and notices[1]==migrationNotice,
    'Expected migration startup must show only one concise, untraced warning')
assert(not Config.SaveConfigurationCache(3) and files['.configuration-cache.json']==nil,
    'Pre-migration settings were written as a CAD cache')

-- Exercise the existing main startup after a pre-migration configuration 404.
threads={};Config.apiVersion=-1
function CadApiGetVersion() return {success=true,data='3'} end
function RegisterServerEvent() end
function RegisterCommand() end
function GetResourcePath() return 'test-resource' end
function GetResourceState() return 'stopped' end
function getServerVersion() return 6500 end
function debugLog() end
function SanitizeErrorDetail(value) return tostring(value) end
local warmed=false
function manuallySetUnitCache() warmed=true end
dofile('sonorancad/core/server.lua')
local startup=table.remove(threads,1)
assert(coroutine.resume(startup.co))
assert(Config.apiVersion==3 and not Config.critError and warmed and Config.GetPluginConfig('kick').enabled)
assert(writes==0 and files['.configuration-cache.json']==nil)
threads={}
convars.sonoran_mode='development';convars.sonoran_mode_setter='server'
dofile('sonorancad/core/configuration.lua')
threads[3]=nil;threads[2]=nil
runUntil(function() return Config.configurationReady end)
assert(not Config.critError and Config.configurationSource=='legacy' and Config.mode=='development')
assert(Config.apiUrl=='https://staging-api.dev.sonorancad.com/', 'Legacy server.cfg environment override was lost')
files['configuration/kick_config.lua']='local offset=40; local config={enabled=true,pluginName="kick",configVersion="1.0",callback=function(value) return value+offset end}'
threads={}
dofile('sonorancad/core/configuration.lua')
threads[3]=nil;threads[2]=nil
runUntil(function() return Config.configurationReady end)
Config.apiVersion=3
assert(Config.GetPluginConfig('kick').callback(2)==42, 'Legacy callback closure changed before migration')
for _, status in ipairs({0, 503}) do
    setup(status, nil, document()); assert(Config.configurationSource=='cache' and Config.cachedApiVersion==3 and writes==0)
end
setup(200, {core={}}, document())
assert(Config.configurationSource=='cache' and writes==0)
local partial=document(); partial.plugins.bodycam={enabled=true, pluginName='bodycam',configVersion='1.3'}
setup(200, partial, document())
assert(Config.configurationSource=='cad' and not Config.GetPluginConfig('bodycam').enabled and writes==0)
assert(not Config.SaveConfigurationCache(3), 'Partial response overwrote the good cache')
setup(401, nil, document()); assert(Config.critError and writes==0)
setup(401); assert(Config.configurationSource=='legacy' and not Config.critError)
setup(0); assert(not Config.critError and Config.configurationSource=='legacy' and Config.apiSendEnabled)
setup(503, nil, {core={}}); assert(Config.configurationSource=='legacy' and writes==0)
for _, status in ipairs({0, 401, 404, 503}) do
    setup(status)
    assert(Config.configurationSource=='legacy' and #logs==1 and #notices==1 and notices[1]==migrationNotice,
        'Pre-migration HTTP '..status..' printed diagnostic noise')
end
setup(404,nil,nil,{apiKey='different-key',serverId=2})
assert(Config.critError, 'Legacy settings from another credential/server were used')

for _, failure in ipairs({'none', 'development-mode', 'upload', 'archive', 'archive-throw', 'readback', 'partial-readback', 'cache', 'conflict', 'missing-setting', 'templates', 'templates-missing', 'older-config', 'bootstrap', 'empty-root', 'whitespace-root', 'empty-object-root', 'default-root'}) do
    local emptyRoots={['empty-root']='', ['whitespace-root']=' \r\n ', ['empty-object-root']={}, ['default-root']={apiKey='',serverId=1}}
    local root=emptyRoots[failure]
    setup(404,nil,nil,root,root and 17 or nil,failure=='development-mode' and 'development' or nil)
    if failure=='development-mode' then
        local core=json.decode(files['configuration/config.json'])
        core.mode='development';core.branch='production';core.apiUrl='https://obsolete-api.example.test/'
        files['configuration/config.json']=json.encode(core)
    end
    if root then
        assert(not Config.bootstrapError and Config.apiKey=='secret' and Config.serverId==17)
        assert(files['config.json']~=nil and archiveCalls==0, 'Startup archived or removed legacy settings')
    end
    convars.sonoran_debugMode=nil
    convars.failArchive=failure=='archive'; convars.failWrite=failure=='cache'
    convars.throwArchive=failure=='archive-throw'
    convars.failBootstrap=failure=='bootstrap'
    if failure=='older-config' then
        files.inventory[#files.inventory+1]='locations_config.lua'
        files['configuration/locations_config.lua']='local config={enabled=true,pluginName="locations",configVersion="1.1",clientCheckTime=250,prefixPostal=false}'
    end
    if failure:find('templates') then
        files.inventory[#files.inventory+1]='calltemplates_config.lua'
        files['configuration/calltemplates_config.lua']=read('sonorancad/configuration/calltemplates_config.dist.lua')
        files.templateInventory={'traffic_stop.json', 'tow_request.json', 'bank_robbery.json'}
        for _, name in ipairs(files.templateInventory) do
            files['submodules/calltemplates/calltypes/'..name]=json.encode({title=name})
        end
        if failure=='templates-missing' then files['submodules/calltemplates/calltypes/traffic_stop.json']=nil end
    end
    local uploaded, sent, gets, finished = nil, 0, 0, false
    CadConfigurationApi.request=function(operation, payload, callback)
        if operation=='get' then
            gets=gets+1
            if uploaded and failure~='readback' then
                local data=clone(uploaded)
                if failure=='partial-readback' then data.plugins.custom=nil end
                if failure=='older-config' then data.plugins.locations.customStreetNames={enabled=false,names={}} end
                callback(200, data)
            else callback(404) end
        else
            sent=sent+1
            if failure=='upload' then callback(403)
            else
                uploaded=clone(payload)
                callback(200, {serverId=Config.serverId, status=failure=='conflict' and 'alreadyMigrated' or 'saved'})
            end
        end
    end
    if failure=='missing-setting' then files['configuration/kick_config.lua']='local config = {enabled=true}' end
    MigrateCadConfiguration(); MigrateCadConfiguration() -- concurrent invocation must collapse
    CreateThread(function() Wait(100); finished=true end)
    runUntil(function() return finished end)
    assert(sent==((failure=='missing-setting' or failure=='templates-missing' or failure=='bootstrap') and 0 or 1))
    if failure~='bootstrap' then
        local prepared=json.decode(files['config.json'])
        assert(prepared.apiKey=='secret' and prepared.serverId==Config.serverId,
            'Migration did not prepare credentials before the API request')
    end
    local succeeds=failure=='none' or failure=='development-mode' or failure=='archive' or failure=='archive-throw' or failure=='templates' or failure=='older-config' or root~=nil
    assert(archiveCalls==(succeeds and 1 or 0))
    if uploaded then
        assert(uploaded.core.apiKey==nil and uploaded.core.serverId==nil and uploaded.core.communityID=='test')
        assert(uploaded.core.mode==(failure=='development-mode' and 'development' or 'production') and uploaded.core.branch==nil and uploaded.core.apiUrl==nil
            and uploaded.core.apiURL==nil, 'Legacy migration retained branch or an API URL')
        assert(uploaded.plugins.kick.pluginName=='kick' and uploaded.plugins.custom.enabled==false)
        if root then
            local boot=json.decode(files['config.json'])
            assert(boot.apiKey=='secret' and boot.serverId==17 and boot.communityID==nil and boot.branch==nil)
        end
        if failure=='older-config' then
            assert(uploaded.plugins.locations.prefixPostal==false and uploaded.plugins.locations.customStreetNames==nil)
        end
        if failure=='templates' then
            assert(uploaded.callTemplates['traffic_stop.json'].title=='traffic_stop.json')
            assert(uploaded.callTemplates['bank_robbery.json'].title=='bank_robbery.json', 'Unreferenced template was omitted')
        end
        local before=sent; MigrateCadConfiguration(); finished=false
        CreateThread(function() Wait(100); finished=true end); runUntil(function() return finished end)
        assert(sent==before, 'Repeated migration uploaded again')
    end
end

setup(200, document(), nil, {apiKey='new-key',serverId=9})
files['configuration/config.json']=nil
files['configuration_old/config.json']=nil
local savedRoot=files['config.json']
dofile('sonorancad/core/configuration.lua')
threads[3]=nil;threads[2]=nil
runUntil(function() return Config.configurationReady end)
assert(Config.apiKey=='new-key' and Config.serverId==9 and not Config.critError)
assert(json.decode(savedRoot).apiKey=='new-key')

-- The real mock adapter is persistent, create-only and clearly separate from cache.
setup(404)
dofile('sonorancad/core/sonoran_api.lua')
convars.sonoran_configurationMock='true'
local result
CreateThread(function()
    assert(CadConfigurationRequest('get').status==404)
    assert(CadConfigurationRequest('migrate', document()).status==200)
    assert(CadConfigurationRequest('migrate', document()).data.status=='alreadyMigrated')
    result=CadConfigurationRequest('get')
end)
runUntil(function() return result~=nil end)
assert(result.status==200 and result.data.plugins.kick.enabled)
CadConfigurationApi.request=function() end
CreateThread(function() result=CadConfigurationRequest('get') end); result=nil
runUntil(function() return result~=nil end)
assert(result.status==0 and now>=15000)

-- Exercise the actual HTTP adapter against the published GET/POST wire contract.
setup(404)
dofile('sonorancad/core/sonoran_api.lua')
local httpStatus, httpData, request
function PerformHttpRequest(url, callback, method, body, headers)
    request={url=url, method=method, body=body, headers=headers}
    callback(httpStatus, json.encode(httpData))
end
local function http(operation, status, body)
    httpStatus, httpData, result=status, body, nil
    CreateThread(function() result=CadConfigurationRequest(operation, operation=='migrate' and document() or nil) end)
    runUntil(function() return result~=nil end)
    return result
end
local flat={core=clone(document().core), kick=clone(document().plugins.kick)}
flat.core.apiKey='must-not-be-cached'
flat.core.updateIgnore={ignore={{path='/custom'}}}
flat.core.livemap_vehicle_models={car={type='CUSTOM'}}
assert(http('get',200,flat).data.plugins.kick.enabled)
assert(result.data.core.apiKey==nil and result.data.updaterIgnore.ignore[1].path=='/custom')
assert(result.data.vehicleModels.car.type=='CUSTOM')
assert(request.url=='https://api.sonorancad.com/v2/fivem/servers/1/configuration')
assert(request.method=='GET' and request.body=='')
assert(request.headers.Authorization=='Bearer secret')
assert(http('migrate',200,{serverId=1,status='saved'}).data.status=='saved')
local payload=json.decode(request.body)
assert(request.method=='POST' and request.url:match('/configuration/migrate$'))
assert(payload.serverId==1 and payload.config.kick.enabled and payload.config.plugins==nil)
assert(payload.config.core.apiKey==nil and payload.config.core.livemap_vehicle_models.car.type=='SEDAN')
assert(payload.config.core.mode=='production' and payload.config.core.branch==nil and payload.config.core.apiUrl==nil
    and payload.config.core.apiURL==nil, 'Migration must send mode without an API URL')
assert(http('migrate',200,{serverId=1,status='alreadyMigrated'}).data.status=='alreadyMigrated')
assert(http('migrate',200,{serverId=2,status='saved'}).status==502)
assert(http('migrate',200,{serverId=1,status='unknown'}).status==502)
assert(http('get',404,{title='Migration pending'}).migrationPending==true)
assert(http('get',404,{title='Server not found'}).migrationPending==false)
assert(http('get',404,{}).migrationPending==nil, 'An empty 404 was classified as an unknown server')
assert(http('get',404,{title='Not Found'}).migrationPending==nil)
assert(http('get',401,{title='Unauthorized'}).status==401)
assert(http('get',200,{revision=4,values=flat}).data==nil, 'Earlier draft envelope was accepted')
local alias=clone(flat);alias.core.communityID=nil;alias.core.commId='cad-community';alias.core.mode=nil;alias.core.branch='development';alias.core.apiUrl='https://cad-api.example.test/'
assert(http('get',200,alias).data.core.communityID=='cad-community')
assert(result.data.core.mode=='development' and result.data.core.branch==nil and result.data.core.apiUrl==nil)
alias.core.mode='production';alias.core.apiURL='https://other-api.example.test/'
assert(http('get',200,alias).data.core.mode=='production' and result.data.core.apiURL==nil,
    'Canonical mode must take priority over the earlier branch alias')
Config.apiUrl='https://other-api.example.test/'
assert(http('get',200,flat).status==200 and request.url=='https://api.sonorancad.com/v2/fivem/servers/1/configuration',
    'Runtime API URL changed the initial configuration lookup address')
function GetResourceMetadata(_,key) if key=='configuration_bootstrap_url' then return 'https://staging-api.dev.sonorancad.com/' end end
assert(http('get',200,flat).status==200 and request.url=='https://staging-api.dev.sonorancad.com/v2/fivem/servers/1/configuration')
GetResourceMetadata=nil

local clients={}
Sonoran={logLevels={ERROR=0},productEnums={CAD=0},createClient=function(options) clients[#clients+1]=options; return {} end}
GetCadClient()
Config.mode='development';Config.apiUrl=GetCadApiUrl(Config.mode);Config.communityID='configured-community'
GetCadClient()
assert(#clients==2 and clients[2].apiUrl==Config.apiUrl and clients[2].communityId==Config.communityID,
    'An early SDK client retained the pre-CAD API URL/community')
Sonoran=nil
local originalEncode=json.encode
json.encode=function(value)
    if type(value)=='table' and value.core and value.kick then return string.rep('x',1048577) end
    return originalEncode(value)
end
local before=request
assert(http('migrate',200,{serverId=1,status='saved'}).status==413 and request==before)
json.encode=originalEncode

-- The drop-in test artifact must not replace itself with a normal release.
threads={}
function GetResourceMetadata(_, key) if key=='configuration_test_build' then return 'true' elseif key=='version' then return '4.0.125-config-test' end end
dofile('sonorancad/core/updater.lua')
threads={}
Config.updateBranch='master'
before=request
RunAutoUpdater(true)
assert(request==before and logs[#logs]:find('staging test build'))

-- Client helpers wait for the resolved server state and never read legacy files.
threads, handlers = {}, {}
function TriggerEvent() end
function debugLog() end
dofile('sonorancad/core/client.lua')
threads = {}
handlers['SonoranCAD::core:recvClientConfig']({apiVersion=3, pluginStates={postals=true}})
assert(isPluginLoaded('postals'), 'Cross-plugin availability depended on response ordering')
function LoadResourceFile() error('Client attempted to read legacy configuration') end
function TriggerServerEvent(_, name)
    handlers['SonoranCAD::core:receivePluginConfig'](name,
        name=='kick' and document().plugins.kick or {enabled=false})
end
assert(Config.GetPluginConfig('kick').enabled and not Config.GetPluginConfig('missing').enabled)
local oldLocations={enabled=true,pluginName='locations',configVersion='1.1',clientCheckTime=250,prefixPostal=false}
handlers['SonoranCAD::core:recvClientConfig']({configurationSource='legacy'})
function TriggerServerEvent(_,name) handlers['SonoranCAD::core:receivePluginConfig'](name,oldLocations) end
assert(Config.GetPluginConfig('locations').enabled, 'Client rejected an eligible pre-migration configuration')
Config.plugins.locations=nil;Config.configurationSource='cad'
handlers['SonoranCAD::core:receivePluginConfig']('locations',oldLocations)
assert(not Config.GetPluginConfig('locations').enabled, 'Client relaxed CAD validation after migration')
Config.RegisterPluginConfig('kick', {enabled=false})
assert(Config.GetPluginConfig('kick').enabled)
handlers['SonoranCAD::core:recvClientConfig']({linkCommand='cadlink'})
local commands = {}
function RegisterCommand(name) commands[name]=true end
function RegisterNUICallback() end
dofile('sonorancad/core/linking_cl.lua')
local task=table.remove(threads, 1)
assert(coroutine.resume(task.co))
assert(commands.cadlink and not commands.link, 'Link command ignored CAD configuration')

-- Disabled Record Printer must return before framework access or event registration.
local loadPlugin=Config.LoadPlugin
Config.LoadPlugin=function(_,cb) cb({enabled=false,disableReason='Configuration startup aborted'}) end
for _,side in ipairs({'sv','cl'}) do
    threads={}
    dofile('sonorancad/submodules/recordPrinter/'..side..'_recordPrinter.lua')
    local task=table.remove(threads,1)
    local ok,err=coroutine.resume(task.co)
    assert(ok,err);assert(coroutine.status(task.co)=='dead')
end
Config.LoadPlugin=loadPlugin
threads={};Config.critError=true;Config.apiVersion=0
Citizen={CreateThread=CreateThread,Wait=Wait}
local priorLogs=#logs
dofile('sonorancad/core/unittracking.lua')
runUntil(function() return #threads==0 end)
assert(#logs==priorLogs, 'Critical configuration failure produced misleading API-disabled cache errors')

-- Every shipped legacy file, including disabled plugins, closures, helper functions,
-- vector literals and Cfx hash keys. Only Cfx syntax is translated for stock Lua.
local inventory=io.popen('git ls-files sonorancad/configuration/*_config.dist.lua')
local count=0
for path in inventory:lines() do
    local name=path:match('/([^/]+)_config%.dist%.lua$')
    local text=read(path):gsub('`[^`]+`','12345')
    local wire, exportError=ExportLegacyPluginConfiguration(name, text)
    assert(wire, name .. ': ' .. tostring(exportError))
    local config, err=ParseCadPluginConfiguration(name, wire)
    assert(config, name .. ': ' .. tostring(err)); count=count+1
    if name=='caddisplay' then
        assert(type(wire.custom.permissionCheck)=='string' and type(config.custom.permissionCheck)=='function')
        assert(config.custom.permissionCheck(1,0)==true)
    end
    if name=='dispatchnotify' then assert(type(config.unitDutyCustom)=='function') end
    if name=='ersintegration' then assert(tonumber(config.customRecords.civilianValues.age({DOB='01/01/2000'}))) end
    if name=='localcallers' then
        assert(wire.weaponConfig.weaponResponses['12345'] and config.weaponConfig.weaponResponses[12345])
        assert(wire.whitelistZones[1].center.x==441.2)
    end
end
inventory:close()
assert(count==20, 'Expected every shipped plugin to be covered')
-- Exercise the real logger so the notice cannot silently regain report/trace output.
local console, originalPrint = {}, print
print=function(text) console[#console+1]=text end
Config.debugMode=false; convars.sonoran_quietPrint='false'
dofile('sonorancad/core/logging.lua')
console={}
warningNotice(migrationNotice)
assert(#console==1 and console[1]:find(migrationNotice, 1, true))
assert(not console[1]:find('\n') and not console[1]:find('Trace:') and not console[1]:find('Docs:')
    and not console[1]:find('WRN%-CORE'), 'Migration notice included a diagnostic report')
assert(#getSupportErrorBuffer()==0 and #getErrorBuffer()==1,
    'Migration notice must remain in the console buffer without creating a support error')
print=originalPrint
print('Configuration resolution, migration, mock, timeout and all '..count..' plugin parsers passed')
