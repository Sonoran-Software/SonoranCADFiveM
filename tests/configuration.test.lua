-- Run from the repository root: lua tests/configuration.test.lua
-- FiveM IO/time and JSON serialization are doubled; production resolution,
-- migration, adapter and legacy Lua conversion are exercised directly.
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
local files, convars, handlers, threads, logs, writes, archiveCalls, now, replies, readyEvents
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
function TriggerEvent(name)
    if name == 'SonoranCAD::core:configurationReady' then
        assert(Config.configurationReady and not Config.critError, 'Readiness published before configuration was usable')
        readyEvents = readyEvents + 1
    end
end
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
local function setup(status, data, cached, rootConfig, legacyServerId, legacyMode, withoutLegacy, migrationPending)
    notices = {}
    readyEvents = 0
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
    if withoutLegacy then
        files['configuration/config.json']=nil
        files['configuration/kick_config.lua']=nil
        files.inventory={}
    end
    if cached then files['.configuration-cache.json'] = json.encode({version=1, scope='scope:1:cad', apiVersion=3, configuration=cached}) end
    dofile('sonorancad/core/shared_functions.lua')
    dofile('sonorancad/core/sonoran_api.lua')
    CadConfigurationApi.request = function(_, _, cb) cb(status, clone(data), nil, {migrationPending=migrationPending}) end
    dofile('sonorancad/core/configuration.lua')
    threads[3]=nil; threads[2]=nil -- Unrelated existing server-registration/diagnostic threads.
    runUntil(function() return Config.configurationReady end)
    assert(readyEvents == (Config.critError and 0 or 1), 'Configuration did not publish readiness exactly once')
    if not Config.critError then Config.apiVersion=3 end
end

setup(200, document())
assert(Config.configurationSource=='cad' and Config.debugMode==false and writes==1)
assert(Config.GetPluginConfig('kick').enabled and not Config.GetPluginConfig('missing').enabled)
local resolved=json.decode(registry.GetResolvedConfig())
assert(resolved.ready and resolved.communityID=='test' and resolved.serverId==1 and resolved.apiKey==nil,
    'Public resolved configuration exposed the CAD API key')
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
-- Force Reg owns linking; core fields are read-only compatibility inputs.
local function forceReg(enabled)
    return {enabled=enabled,pluginName='forcereg',configVersion='1.0',requireLink=true,
        linkCommand='cadconnect',linkPollIntervalMs=2750,linkPopupTitleText='Connect your account',linkButtonText='Connect CAD',
        autoOpenLinkPopup=false,allowPopupCloseWhenUnlinked=true,captiveOption='freeze',
        captiveMessage='',instructionalMessage='',verifyMessage='',nagDrawTextLocation='top',whitelist={enabled=false}}
end
for _, enabled in ipairs({false,true}) do
    local linking=document();linking.plugins.forcereg=forceReg(enabled)
    linking.core.linkCommand='oldlink';linking.core.linkPollIntervalMs=60000;linking.core.requireLink=false
    setup(200,linking)
    assert(not Config.critError and Config.linkCommand=='cadconnect' and Config.linkPollIntervalMs==2750)
    assert(Config.linkPopupTitleText=='Connect your account' and Config.linkButtonText=='Connect CAD' and not Config.autoOpenLinkPopup)
    assert(Config.requireLink and Config.freezeUntilLinked==enabled and Config.allowPopupCloseWhenUnlinked==not enabled)
    local cached=json.decode(files['.configuration-cache.json']).configuration
    for key in pairs(CadLinkDefaults) do
        assert(cached.core[key]==nil and cached.plugins.forcereg[key]~=nil, 'Linking has duplicate configuration owners')
    end
    assert(cached.core.freezeUntilLinked==nil)
    source=5;handlers['SonoranCAD::core:sendClientConfig']()
    assert(replies[3].linkCommand=='cadconnect' and replies[3].linkButtonText=='Connect CAD',
        'Client received different resolved linking settings')
end
local optionalLink=document();optionalLink.plugins.forcereg=forceReg(true);optionalLink.plugins.forcereg.requireLink=false
setup(200,optionalLink)
assert(not Config.requireLink and not Config.freezeUntilLinked and Config.allowPopupCloseWhenUnlinked,
    'Disabled enforcement still forced the linking popup')
local oldLink=document()
oldLink.core.linkCommand='legacyconnect';oldLink.core.linkPollIntervalMs=500;oldLink.core.linkButtonText='Legacy Connect'
oldLink.core.freezeUntilLinked=true
setup(200,oldLink)
assert(Config.linkCommand=='legacyconnect' and Config.linkPollIntervalMs==1000 and Config.linkButtonText=='Legacy Connect')
assert(not Config.plugins.forcereg.enabled and not Config.freezeUntilLinked, 'Compatibility enabled Force Reg enforcement')
local linkCache=json.decode(files['.configuration-cache.json']).configuration
assert(linkCache.plugins.forcereg.captiveOption=='freeze' and linkCache.core.freezeUntilLinked==nil)
setup(503,nil,linkCache)
assert(Config.configurationSource=='cache' and Config.linkCommand=='legacyconnect' and Config.linkPollIntervalMs==1000)
setup(503, nil, routed)
assert(Config.configurationSource=='cache' and Config.mode=='development' and Config.apiUrl=='https://staging-api.dev.sonorancad.com/')
local oldCache=clone(routed);oldCache.core.mode=nil;oldCache.core.branch='development';oldCache.core.apiUrl='https://obsolete-api.example.test/'
setup(503,nil,oldCache)
assert(Config.configurationSource=='cache' and Config.mode=='development' and Config.apiUrl=='https://staging-api.dev.sonorancad.com/',
    'Earlier test cache did not normalize mode or discarded URL')
local incomplete=document();incomplete.core.communityID=nil
setup(200,incomplete)
assert(Config.critError, 'CAD configuration without community ID was activated')
assert(#logs==1 and logs[1]:find('core.communityID',1,true), 'Startup hid the rejected CAD field behind a cache error')
Config.LoadPlugin('recordPrinter',function() error('Disabled printer callback was invoked after configuration failure') end)
incomplete=document();incomplete.core.mode=nil
setup(200,incomplete)
assert(Config.critError, 'CAD configuration without mode was activated')
assert(#logs==1 and logs[1]:find('core.mode',1,true), 'Startup hid the missing CAD mode')
incomplete=document();incomplete.core.mode='unknown'
setup(200,incomplete)
assert(Config.critError, 'CAD configuration with invalid mode was activated')

local migrationNotice='Configuration migration required. Run: sonorancad migrate. https://sonoran.link/migrate'
local staleCache=document();staleCache.plugins.kick.enabled=false
for _, cached in ipairs({false, staleCache}) do
    setup(404,nil,cached or nil,nil,nil,nil,nil,false)
    assert(Config.critError and not Config.migrationRequired and not Config.configurationSource,
        'Known invalid-server 404 started legacy/cached settings')
    assert(writes==0 and archiveCalls==0 and #notices==0 and logs[#logs]:find('rejected',1,true))
    local sent=0
    CadConfigurationApi.request=function(operation, _, cb)
        if operation=='migrate' then sent=sent+1 end
        cb(404,nil,'Server not found',{migrationPending=false})
    end
    MigrateCadConfiguration()
    runUntil(function() return #threads==0 end)
    assert(sent==0 and writes==0 and archiveCalls==0, 'Known invalid-server 404 allowed a migration upload')
end
setup(404,nil,staleCache,nil,nil,nil,nil,true)
assert(Config.configurationSource=='legacy' and Config.migrationRequired and not Config.critError,
    'Explicit migration-pending 404 blocked legacy startup')
setup(404, nil, staleCache)
assert(not Config.critError and writes==0 and archiveCalls==0 and Config.configurationSource=='legacy' and Config.migrationRequired,
    'An existing cache blocked legacy startup on a migration-required 404')
assert(Config.GetPluginConfig('kick').enabled and #logs==1 and notices[1]==migrationNotice,
    '404 did not prefer local files or emitted diagnostic noise')
local priorCache=files['.configuration-cache.json']
assert(not Config.SaveConfigurationCache(3) and files['.configuration-cache.json']==priorCache)
setup(404,nil,document(),{apiKey='secret',serverId=1},nil,nil,true)
assert(not Config.critError and Config.configurationSource=='cache' and Config.migrationRequired and Config.GetPluginConfig('kick').enabled)
assert(writes==0 and archiveCalls==0 and #logs==1 and notices[1]==migrationNotice,
    '404 cache-only startup wrote settings or emitted diagnostic noise')
assert(not Config.SaveConfigurationCache(3))
setup(404,nil,nil,{apiKey='secret',serverId=1},nil,nil,true)
assert(Config.critError and Config.migrationRequired and #logs==1 and #notices==1
    and notices[1]:find('Local settings could not be loaded:',1,true),
    'Missing local files must produce one actionable migration notice')
Config.LoadPlugin('recordPrinter',function() error('Missing local settings started a plugin') end)
local priorLogs=#logs
threads={}
dofile('sonorancad/core/plugin_loader.lua')
runUntil(function() return #threads==0 end)
assert(#logs==priorLogs, 'Pending migration generated a redundant ERROR_ABORT trace')
local cadOnly=document();cadOnly.plugins.kick.enabled=false
setup(200,cadOnly,document())
assert(Config.configurationSource=='cad' and not Config.GetPluginConfig('kick').enabled and not Config.migrationRequired,
    'Successful CAD startup did not replace legacy/cache settings')
setup(404)
assert(not Config.critError and Config.configurationSource=='legacy' and Config.apiSendEnabled)
assert(Config.GetPluginConfig('kick').enabled and writes==0 and archiveCalls==0)
assert(#logs==1 and #notices==1 and notices[1]==migrationNotice,
    'Expected migration startup must show only one concise, untraced warning')
assert(not Config.SaveConfigurationCache(3) and files['.configuration-cache.json']==nil,
    'Pre-migration settings were written as a CAD cache')

-- Exercise the existing main startup after a pre-migration configuration 404.
setup(404,nil,staleCache)
local startupCache=files['.configuration-cache.json']
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
assert(writes==0 and files['.configuration-cache.json']==startupCache,
    'Legacy main startup after a 404 overwrote the prior cache')
for _, identifier in ipairs({'license','steam'}) do
    local cached=document();cached.core.primaryIdentifier=identifier
    setup(503,nil,cached)
    local previousCache=files['.configuration-cache.json']
    threads={};Config.apiVersion=-1;warmed=false
    function getServerVersion() return 6500 end
    function CadApiGetVersion() return {success=false,status=503} end
    function CadApiLogFailure() end
    local errors, commands={},{}
    function logError(code) errors[#errors+1]=code end
    function GetResourceState() return 'started' end
    function ExecuteCommand(command) commands[#commands+1]=command end
    dofile('sonorancad/core/server.lua')
    local task=table.remove(threads,1)
    local ok,err=coroutine.resume(task.co);assert(ok,err)
    assert(Config.apiVersion==3 and warmed and commands[1]=='stop sonoran_updatehelper',
        'Cached API version skipped common startup initialization: '..table.concat(logs,' | '))
    assert((Config.critError==true)==(identifier=='steam') and
        (identifier~='steam' or errors[1]=='STEAM_ERROR'), 'Cached startup skipped Steam API key validation')
    assert(writes==0 and files['.configuration-cache.json']==previousCache,
        'Cached API version replaced the last-known-good cache')
end
function GetResourceState() return 'stopped' end
setup(404,nil,staleCache)
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

for _, failure in ipairs({'none', 'linking', 'existing-cache', 'development-mode', 'upload', 'archive', 'archive-throw', 'readback', 'partial-readback', 'cache', 'conflict', 'missing-setting', 'templates', 'templates-missing', 'older-config', 'bootstrap', 'empty-root', 'whitespace-root', 'empty-object-root', 'default-root',
    'diagnostic-http', 'diagnostic-timeout', 'diagnostic-shape', 'diagnostic-validation', 'diagnostic-differences', 'diagnostic-limit',
    'float-roundtrip', 'float-change', 'float-id-change', 'float-type-change'}) do
    local emptyRoots={['empty-root']='', ['whitespace-root']=' \r\n ', ['empty-object-root']={}, ['default-root']={apiKey='',serverId=1}}
    local root=emptyRoots[failure]
    setup(404,nil,failure=='existing-cache' and document() or nil,root,root and 17 or nil,failure=='development-mode' and 'development' or nil)
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
    if failure=='linking' then
        local core=json.decode(files['configuration/config.json'])
        core.linkCommand='oldlink';core.linkPopupTitleText='Existing link prompt';core.linkPollIntervalMs=40000
        files['configuration/config.json']=json.encode(core)
        files.inventory[#files.inventory+1]='forcereg_config.lua'
        files['configuration/forcereg_config.lua']=[[
            local config={enabled=true,pluginName='forcereg',configVersion='1.0',
                linkCommand='forceconnect',linkPollIntervalMs=2500,captiveOption='nag',
                captiveMessage='',instructionalMessage='',verifyMessage='',nagDrawTextLocation='top',whitelist={enabled=false}}
        ]]
    end
    if failure=='older-config' then
        files.inventory[#files.inventory+1]='locations_config.lua'
        files['configuration/locations_config.lua']='local config={enabled=true,pluginName="locations",configVersion="1.1",clientCheckTime=250,prefixPostal=false}'
    end
    if failure:find('templates') then
        files.inventory[#files.inventory+1]='calltemplates_config.lua'
        files['configuration/calltemplates_config.lua']=[[
            local config={enabled=true,pluginName='calltemplates',configVersion='2.0.0',
                callTypeDirectory='submodules/calltemplates/calltypes',defaultOrigin=2,defaultStatus=1,
                defaultPriority=1,reloadTemplatesOnEachUse=false,
                commands={{command='ts',callTypeFile='traffic_stop.json'},{command='towreq',callTypeFile='tow_request.json'}}}
        ]]
        files.templateInventory={'traffic_stop.json', 'tow_request.json', 'bank_robbery.json'}
        for _, name in ipairs(files.templateInventory) do
            files['submodules/calltemplates/calltypes/'..name]=json.encode({title=name})
        end
        if failure=='templates-missing' then files['submodules/calltemplates/calltypes/traffic_stop.json']=nil end
    end
    if failure=='diagnostic-differences' or failure=='diagnostic-limit' then
        files['configuration/kick_config.lua']=[[
            local config={enabled=true,pluginName='kick',configVersion='1.0',pluginAuthor='Example author',
                password='local-private-value',label='local label',
                callback=function(value) return value+1 end}
        ]]
        if failure=='diagnostic-limit' then
            files['configuration/kick_config.lua']=files['configuration/kick_config.lua']..
                '\nfor i=1,20 do config["extra"..i]=i end'
        end
    end
    if failure:find('float-',1,true) then
        files['configuration/kick_config.lua']=[[
            local config={enabled=true,pluginName='kick',configVersion='1.0',measurements={
                range=19.989999999998002, x=-0.16199999999998, y=0.077400000000012,
                x2=0.15800000000002, y2=0.031599999999998, z=0.046000000000006,
                nearZero=0, scaled=12345.67890123456, largeId=1000000000000}}
        ]]
    end
    local initialCache=files['.configuration-cache.json']
    local uploaded, sent, gets, finished = nil, 0, 0, false
    CadConfigurationApi.request=function(operation, payload, callback)
        if operation=='get' then
            gets=gets+1
            if uploaded and failure~='readback' then
                if failure=='diagnostic-http' then callback(503,nil,'Service unavailable. Bearer private-bearer-value');return end
                if failure=='diagnostic-timeout' then callback(0,nil,'Configuration request timed out.');return end
                if failure=='diagnostic-shape' then callback(200,nil,'CAD returned invalid JSON or a non-object response.');return end
                local data=clone(uploaded)
                if failure=='partial-readback' then data.plugins.custom=nil end
                if failure=='older-config' then data.plugins.locations.customStreetNames={enabled=false,names={}} end
                if failure=='diagnostic-validation' then data.core.postTime='5000' end
                if failure=='diagnostic-differences' then
                    data.plugins.kick.pluginAuthor=nil
                    data.plugins.kick.password='cad-private-value'
                    data.plugins.kick.label='CAD label with secret\nnewline'
                    data.plugins.kick.callback='function(value) return value+2 end'
                end
                if failure=='diagnostic-limit' then
                    for i=1,20 do data.plugins.kick['extra'..i]=false end
                end
                if failure:find('float-',1,true) then
                    local measurements=data.plugins.kick.measurements
                    measurements.range=19.989999999997998;measurements.x=-0.16199999999998002
                    measurements.y=0.07740000000001;measurements.x2=0.158
                    measurements.y2=0.03159999999999;measurements.z=0.046
                    measurements.nearZero=1e-13;measurements.scaled=12345.678901234558
                    if failure=='float-change' then measurements.x2=0.15801 end
                    if failure=='float-id-change' then measurements.largeId=1000000000001 end
                    if failure=='float-type-change' then measurements.range='19.989999999998' end
                end
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
    local succeeds=failure=='none' or failure=='linking' or failure=='float-roundtrip' or failure=='existing-cache' or failure=='development-mode' or failure=='archive' or failure=='archive-throw' or failure=='templates' or failure=='older-config' or root~=nil
    assert(archiveCalls==(succeeds and 1 or 0))
    if failure=='linking' then
        assert(uploaded.plugins.forcereg.linkCommand=='forceconnect' and uploaded.plugins.forcereg.linkPollIntervalMs==2500)
        assert(uploaded.plugins.forcereg.linkPopupTitleText=='Existing link prompt', 'Migration lost legacy core linking values')
        for key in pairs(CadLinkDefaults) do assert(uploaded.core[key]==nil, 'Migration uploaded duplicate linking values') end
    end
    if failure:find('float-',1,true) then
        local output=table.concat(logs,'\n')
        if failure=='float-roundtrip' then
            assert(output:find('Configuration migration successful',1,true) and not output:find('Difference at',1,true),
                'Nominal floating-point round trips failed migration')
        else
            assert(files['.configuration-cache.json']==initialCache and output:find('Migration readback failed',1,true),
                'Meaningful numeric/type changes passed migration verification')
            local field=failure=='float-change' and 'x2' or failure=='float-id-change' and 'largeId' or 'range'
            assert(output:find('Difference at plugins.kick.measurements.'..field,1,true))
            local _,count=output:gsub('Difference at','');assert(count==1, 'Numeric noise hid the meaningful difference')
        end
    end
    if failure:find('diagnostic',1,true) then
        local output=table.concat(logs,'\n')
        assert(output:find('Migration readback failed for server 1',1,true))
        assert(files['.configuration-cache.json']==initialCache and archiveCalls==0,
            'Diagnostic failure changed the cache or archived local files')
        if failure=='diagnostic-http' then
            assert(output:find('GET HTTP 503',1,true) and output:find('Service unavailable.',1,true))
            assert(not output:find('private-bearer-value',1,true))
        elseif failure=='diagnostic-timeout' then
            assert(output:find('GET HTTP 0',1,true) and output:find('timed out',1,true))
        elseif failure=='diagnostic-shape' then
            assert(output:find('GET HTTP 200',1,true) and output:find('invalid JSON',1,true) and output:find('Validation:',1,true))
        elseif failure=='diagnostic-validation' then
            assert(output:find('Difference at core.postTime: local=number 5000; CAD=string "5000"',1,true))
        elseif failure=='diagnostic-differences' then
            assert(output:find('plugins.kick.pluginAuthor: local=string "Example author"; CAD=missing',1,true))
            assert(output:find('plugins.kick.password: local=string [redacted]; CAD=string [redacted]',1,true))
            assert(output:find('plugins.kick.callback: local=Lua source',1,true) and output:find('Lua source first differs at byte',1,true))
            assert(not output:find('local-private-value',1,true) and not output:find('cad-private-value',1,true)
                and not output:find('function(value)',1,true) and not output:find('secret',1,true))
            for _,notice in ipairs(notices) do assert(not notice:find('\n',1,true), 'Diagnostic contained a raw newline') end
        elseif failure=='diagnostic-limit' then
            local _,count=output:gsub('Difference at','')
            assert(count==10 and output:find('Additional differences omitted',1,true))
        end
    end
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
        if failure=='diagnostic-differences' then
            assert(table.concat(logs):find('Existing CAD settings differ from local files',1,true),
                'Rerunning migration after an accepted upload omitted difference diagnostics')
        end
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
local coreVersion = '4.0.126'
function GetResourceMetadata(_, key) if key == 'version' then return coreVersion end end
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
assert(request.url=='https://api.sonorancad.com/v2/fivem/servers/1/configuration?version='..coreVersion)
assert(request.method=='GET' and request.body=='')
assert(request.headers.Authorization=='Bearer secret')
coreVersion = '4.0.127'
assert(http('get',200,flat).status==200 and request.url=='https://api.sonorancad.com/v2/fivem/servers/1/configuration?version=4.0.127',
    'Configuration GET did not use the installed core version')
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
assert(result.message:find('core object',1,true), 'Missing core response omitted a shape diagnostic')
assert(http('get',200,'not an object').message:find('invalid JSON or a non-object',1,true))
assert(http('get',200,{core=flat.core,kick=42}).message:find('kick: expected object, received number',1,true),
    'Malformed plugin section omitted its name and type')
local alias=clone(flat);alias.core.communityID=nil;alias.core.commId='cad-community';alias.core.mode=nil;alias.core.branch='development';alias.core.apiUrl='https://cad-api.example.test/'
assert(http('get',200,alias).data.core.communityID=='cad-community')
assert(result.data.core.mode=='development' and result.data.core.branch==nil and result.data.core.apiUrl==nil)
alias.core.mode='production';alias.core.apiURL='https://other-api.example.test/'
assert(http('get',200,alias).data.core.mode=='production' and result.data.core.apiURL==nil,
    'Canonical mode must take priority over the earlier branch alias')
Config.apiUrl='https://other-api.example.test/'
assert(http('get',200,flat).status==200 and request.url=='https://api.sonorancad.com/v2/fivem/servers/1/configuration?version='..coreVersion,
    'Runtime API URL changed the initial configuration lookup address')
function GetResourceMetadata(_,key)
    if key=='configuration_bootstrap_url' then return 'https://staging-api.dev.sonorancad.com/'
    elseif key=='version' then return coreVersion end
end
assert(http('get',200,flat).status==200 and request.url=='https://staging-api.dev.sonorancad.com/v2/fivem/servers/1/configuration?version='..coreVersion)
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

-- Run template commands from the CAD response and its offline cache.
-- No calltype files or file-related settings are present.
local savedTypes = clone(flat)
savedTypes.calltemplates = {
    enabled=true, pluginName='calltemplates', configVersion='2.0.0',
    defaultOrigin=2, defaultStatus=1, defaultPriority=1,
    commands={
        {command='closure', callTypeFile='road_closure.json'},
        {command='tow', callTypeFile='tow_request.json'},
        {command='alarm', callTypeFile='bank_alarm.json'}
    },
    templates={
        ['road_closure.json']={title='Road Closure',description='function (use the service road',priority=2},
        ['tow_request.json']={callType={title='Tow Request'}},
        ['bank_alarm.json']={{title='Bank Alarm'}}
    }
}
function GetResourceMetadata(_, key) if key=='version' then return coreVersion end end
local inline = assert(http('get',200,savedTypes).data, 'CAD did not resolve the inline template response')
GetResourceMetadata = nil
assert(inline.plugins.calltemplates.templates==nil, 'Template bodies were retained in client-visible settings')
local function runTemplateCommands()
    local commands, sent = {}, nil
    local readFile, trigger, registerCommand = LoadResourceFile, TriggerEvent, RegisterCommand
    local playerStatus, pluginLoaded, resolveUnits = getPlayerCadStatus, isPluginLoaded, CadApiResolveCommunityUserIds
    local locationCache = LocationCache
    LoadResourceFile = function() error('Template command tried to read a local file') end
    TriggerEvent = function(name, payload)
        assert(name=='SonoranCAD::calltemplates:SendDispatch')
        sent = payload
    end
    function RegisterCommand(name, callback) commands[name] = callback end
    function getPlayerCadStatus() return {success=true,link='unit-1'} end
    function isPluginLoaded() return false end
    function CadApiResolveCommunityUserIds(units) return units end
    LocationCache = {}
    dofile('sonorancad/submodules/calltemplates/sv_calltemplates.lua')
    runUntil(function() return #threads==0 end)
    commands.closure(5,{'two lanes'})
    assert(sent.title=='Road Closure' and sent.priority==2 and sent.description=='function (use the service road - two lanes')
    commands.tow(5,{'truck'})
    assert(sent.title=='Tow Request')
    commands.alarm(5,{'test'})
    assert(sent.title=='Bank Alarm')
    LoadResourceFile, TriggerEvent, RegisterCommand = readFile, trigger, registerCommand
    getPlayerCadStatus, isPluginLoaded, CadApiResolveCommunityUserIds = playerStatus, pluginLoaded, resolveUnits
    LocationCache = locationCache
end
setup(200,inline,nil,{apiKey='secret',serverId=1},nil,nil,true)
assert(Config.configurationSource=='cad' and Config.GetPluginConfig('calltemplates').enabled)
source=5;handlers['SonoranCAD::core:requestPluginConfig']('calltemplates')
assert(replies[4].templates==nil, 'Client received the call template bodies')
runTemplateCommands()
local inlineCache=json.decode(files['.configuration-cache.json']).configuration
inlineCache.plugins.calltemplates.templates=clone(inlineCache.callTemplates) -- Earlier cache format.
setup(503,nil,inlineCache,{apiKey='secret',serverId=1},nil,nil,true)
assert(Config.configurationSource=='cache' and Config.GetPluginConfig('calltemplates').enabled)
source=5;handlers['SonoranCAD::core:requestPluginConfig']('calltemplates')
assert(replies[4].templates==nil, 'Earlier cache exposed the call template bodies')
runTemplateCommands()

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

-- The loader itself must protect old plugin scripts that lack an enabled guard.
Config.plugins.recordPrinter={enabled=false}
Config.LoadPlugin('recordPrinter',function() error('Client invoked a disabled plugin callback') end)
local called=false
Config.LoadPlugin('kick',function(settings) called=settings.enabled end)
assert(called, 'Client skipped an enabled plugin')
local unsafePrinter={enabled=true,pluginName='recordPrinter',configVersion='1.0'}
local printer, printerError=ParseCadPluginConfiguration('recordPrinter',unsafePrinter,true)
assert(printer==nil and printerError:find('recordPrinter.frameworks',1,true),
    'Legacy printer without frameworks would crash during initialization')

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

-- Legacy examples belong in this test, not in downloadable configuration files.
local legacyExamples={
    caddisplay=[[
        local config={enabled=true,pluginName='caddisplay',configVersion='1.0',custom={
            permissionCheck=function(player, permissionType)
                local text='end function'; -- Keywords in text must not terminate the callback.
                if player==1 then return permissionType==0 end
                return false
            end}}
    ]],
    dispatchnotify=[[
        local config={enabled=true,pluginName='dispatchnotify',configVersion='1.0'}
        function unitDutyCustom(player) return player==42 end
    ]],
    localcallers=[[
        local config={enabled=true,pluginName='localcallers',configVersion='1.0',
            weaponConfig={weaponResponses={[12345]={description='Example response'}}},
            whitelistZones={{center=vector3(441.2,1,2),radius=50}}}
    ]],
    custom=[[
        local config={enabled=false,pluginName='custom',configVersion='1.0',label='Example'}
    ]],
    localhelper=[[
        local function helper(value) return value+1 end
        local config={enabled=true,pluginName='localhelper',configVersion='1.0',
            callback=function(value) return helper(value) end, nested={callback=helper}}
    ]]
}
for name,text in pairs(legacyExamples) do
    local wire, exportError=ExportLegacyPluginConfiguration(name, text)
    assert(wire, name .. ': ' .. tostring(exportError))
    local config, err=ParseCadPluginConfiguration(name, wire, true)
    assert(config, name .. ': ' .. tostring(err))
    if name=='caddisplay' then
        assert(type(wire.custom.permissionCheck)=='string' and type(config.custom.permissionCheck)=='function')
        assert(config.custom.permissionCheck(1,0)==true)
    end
    if name=='dispatchnotify' then assert(config.unitDutyCustom(42) and not config.unitDutyCustom(1)) end
    if name=='custom' then assert(config.enabled==false and config.label=='Example') end
    if name=='localhelper' then
        assert(type(wire.helper)=='string' and wire.helper:match('^function helper'))
        assert(config.helper(41)==42 and config.callback(41)==42 and config.nested.callback(41)==42,
            'Local helper or callback references failed the plaintext round trip')
    end
    if name=='localcallers' then
        assert(wire.weaponConfig.weaponResponses['12345'] and config.weaponConfig.weaponResponses[12345])
        assert(wire.whitelistZones[1].center.x==441.2)
    end
end
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
print('Configuration resolution, migration, mock, timeout and legacy Lua conversion passed')
