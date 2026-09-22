"""Offline runtime contract tests. Run: python -m unittest discover -s tests -p test_remote_configuration.py
Requires lupa (Lua runtime); no live CAD credentials or FXServer are used.
"""
import json
import unittest
from pathlib import Path
from lupa import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]/'sonorancad'

class ConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            Config={apiKey='test-key',communityID='test-community',serverId=1,mode='production'}
            waits={}; commands={}; logs={}; convars={}
            promise={new=function() return {resolve=function(self,value) self.value=value end} end}
            Citizen={Await=function(p) return p.value end}
            function SetTimeout(ms,fn) end
            function Wait(ms) table.insert(waits,ms) end
            function CreateThread(fn) fn() end
            function infoLog(s) table.insert(logs,s) end
            function warnLog(code,s) table.insert(logs,s) end
            function SetConvar(k,v) convars[k]=v end
            function ExecuteCommand(s) table.insert(commands,s) end
            function GetCurrentResourceName() return 'sonorancad' end
            function vector3(x,y,z) return {x=x,y=y,z=z,native=true} end
        ''')
        self.responses=[]
        self.requests=[]
        self.lua.globals().PerformHttpRequest=self.request
        self.lua.globals().json=self.lua.table_from({'decode':lambda text:self.to_lua(json.loads(text))})
        self.lua.execute((ROOT/'core/configuration_hooks.lua').read_text())
        self.lua.execute((ROOT/'core/remote_configuration.lua').read_text())
    def to_lua(self,value):
        if isinstance(value,dict):return self.lua.table_from({k:self.to_lua(v) for k,v in value.items()})
        if isinstance(value,list):return self.lua.table_from([self.to_lua(v) for v in value])
        return value
    def request(self,url,callback,method,body,headers):
        self.requests.append((url,method))
        self.assertEqual(headers['Authorization'],'Bearer test-key')
        if not self.responses: raise AssertionError('Unexpected HTTP request; possible retry loop')
        status,value=self.responses.pop(0)
        callback(status,json.dumps(value))
    def payload(self,revision=2,schema=1):
        return {'serverId':1,'revision':revision,'schemaVersion':schema,'templateRevision':'catalog-1',
                'values':{'core':{'debugMode':False,'apiKey':'must-not-replace'},'plugins':{'bodycam':{'enabled':True}}}}
    def load(self):
        self.responses.append((200,self.payload()))
        self.lua.globals().LoadRemoteFiveMConfiguration()
    def test_startup_waits_and_retries_network_and_incompatible_responses(self):
        self.responses=[(503,{}),(200,self.payload(schema=99)),(200,self.payload())]
        self.lua.globals().LoadRemoteFiveMConfiguration()
        self.assertEqual(list(self.lua.globals().waits.values()),[60000,60000])
        self.assertTrue(self.lua.globals().Config.remoteReady)
        self.assertEqual(self.lua.globals().Config.apiKey,'test-key')
        self.assertEqual(self.lua.globals().Config.remoteRevision,2)
        self.assertEqual(list(self.lua.globals().Plugins.values()),['bodycam'])
    def test_restart_fetches_exact_revision_and_deduplicates(self):
        self.load()
        self.assertFalse(self.lua.globals().ApplyRemoteFiveMConfiguration(self.to_lua(self.payload())))
        self.responses.append((200,self.payload(3)))
        self.assertTrue(self.lua.globals().ApplyRemoteFiveMConfiguration(self.to_lua(self.payload(3))))
        self.assertEqual(list(self.lua.globals().commands.values()),['restart sonorancad'])
    def test_wrong_server_and_changed_revision_do_not_restart(self):
        self.load(); data=self.payload(3);data['serverId']=2
        self.assertFalse(self.lua.globals().ApplyRemoteFiveMConfiguration(self.to_lua(data)))
        self.responses.append((200,self.payload(4)))
        self.lua.globals().ApplyRemoteFiveMConfiguration(self.to_lua(self.payload(3)))
        self.assertEqual(list(self.lua.globals().commands.values()),[])
    def test_unsaved_configuration_waits_and_missing_dependency_is_disabled(self):
        data=self.payload()
        data['values']['plugins']['bodycam']['requiresPlugins']=[{'name':'locations','critical':True}]
        self.responses=[(200,self.payload(0)),(200,data)]
        self.lua.globals().LoadRemoteFiveMConfiguration()
        self.assertEqual(list(self.lua.globals().waits.values()),[60000])
        self.assertFalse(self.lua.globals().Config.plugins.bodycam.enabled)
        self.assertFalse(self.lua.globals().Config.remotePluginValues.bodycam.enabled)
    def test_hooks_restore_native_vectors_numeric_keys_and_functions(self):
        value={'localcallers':{'whitelistZones':[{'center':{'x':1,'y':2,'z':3}}],
                             'weaponConfig':{'weaponResponses':{'-2084633992':'rifle'}}},
               'ersintegration':{'customRecords':{'civilianValues':{'age':'builtin:plugins.ersintegration.customRecords.civilianValues.age'}}}}
        result=self.lua.globals().ResolveFiveMConfig(self.to_lua(value))
        self.assertTrue(result['localcallers']['whitelistZones'][1]['center']['native'])
        self.assertEqual(result['localcallers']['weaponConfig']['weaponResponses'][-2084633992],'rifle')
        self.assertEqual(self.lua.eval('type')(result['ersintegration']['customRecords']['civilianValues']['age']),'function')
    def test_changed_lua_files_compile(self):
        compile_lua=self.lua.eval('function(s,n) local fn,err=load(s,n); return fn~=nil,err end')
        for path in ['core/configuration_hooks.lua','core/configuration_export.lua','core/remote_configuration.lua','core/configuration.lua','core/client.lua','core/server.lua','core/httpd.lua','core/plugin_loader.lua','submodules/locations/sv_locations.lua']:
            ok,error=compile_lua((ROOT/path).read_text(),path)
            self.assertTrue(ok,error)

if __name__=='__main__': unittest.main()
