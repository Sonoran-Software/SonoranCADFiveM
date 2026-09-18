"""Run with Python + lupa; exercises the actual FiveM Lua event handlers."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]

class LinkingTests(unittest.TestCase):
    def runtime(self, server=False):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute('''
        handlers = {}; events = {}; notices = 0; focuses = 0; writes = 0; checks = 0; now = 1000
        Config = {primaryIdentifier = 'license'}; source = 1
        function GetConvar(_, fallback) return fallback end
        function RegisterCommand(...) end
        function RegisterPlayerCommandHelp(...) end
        function RegisterNetEvent(...) end
        function RegisterNUICallback(...) end
        function AddEventHandler(name, fn) handlers[name] = fn end
        function CreateThread(...) end
        function TriggerEvent(...) end
        function TriggerServerEvent(...) end
        function SendNUIMessage(...) end
        function SetNuiFocus(...) focuses = focuses + 1 end
        function SetNuiFocusKeepInput(...) end
        function NotifyClient(...) notices = notices + 1 end
        function debugLog(...) end
        function infoLog(...) end
        function warnLog(...) end
        function exports(...) end
        function GetGameTimer() return now end
        function GetIdentifiers(_) return {license = 'license:test'} end
        function TriggerClientEvent(name, player, data) events[#events+1] = {name=name, data=data} end
        account = '11111111-1111-1111-1111-111111111111'
        secret = '22222222-2222-2222-2222-222222222222'
        backendLinked = false
        function CadApiCheckCommunityLink(...)
            checks = checks + 1
            return {success=true, data={linked=backendLinked, accountUuid=backendLinked and account or nil, communityUserId='license:test'}}
        end
        function GetCadClient() return {setCommunityLinkV2=function(_, payload)
            writes = writes + 1
            if duringWrite then duringWrite(); duringWrite = nil end
            if failWrite then return {success=false, reason='test failure'} end
            backendLinked = true
            return {success=true, data={linked=true, accountUuid=payload.accountUuid}}
        end} end
        ''')
        lua.execute((ROOT / ('sonorancad/core/linking_sv.lua' if server else 'sonorancad/core/linking_cl.lua')).read_text())
        return lua

    def test_client_transitions_and_focus(self):
        lua=self.runtime()
        lua.execute('''
        status = handlers['SonoranCAD::links:Status']
        status({linked=true}); status({linked=true})
        assert(notices == 0 and focuses == 0)
        status({linked=false}); status({linked=true, newlyLinked=true}); status({linked=true, newlyLinked=false})
        assert(notices == 1 and focuses == 0)
        status({linked=false}); status({linked=true})
        assert(notices == 2)
        status({linked=true, newlyLinked=true}); status({linked=true})
        assert(notices == 3)
        ''')

    def test_already_linked_open_is_silent(self):
        lua=self.runtime()
        lua.execute('''
        handlers['SonoranCAD::links:OpenResult']({ok=true, linked=true})
        handlers['SonoranCAD::links:Status']({linked=true})
        assert(notices == 0)
        ''')

    def test_server_duplicate_burst_and_relink(self):
        lua=self.runtime(True)
        lua.execute('''
        link = handlers['SonoranCAD::Tablet::SetCommunityLink']
        duringWrite = function() link(account, secret) end
        for i=1,20 do link(account, secret) end
        assert(writes == 1 and checks == 1)
        local transitions = 0
        for _,e in ipairs(events) do if e.name == 'SonoranCAD::links:Status' and e.data.newlyLinked then transitions=transitions+1 end end
        assert(transitions == 1)
        now = now + 31000
        link(account, secret)
        assert(checks == 2 and writes == 1)
        backendLinked = false; now = now + 31000
        link(account, secret)
        assert(writes == 2)
        ''')

    def test_existing_link_and_failed_retry(self):
        lua=self.runtime(True)
        lua.execute('''
        backendLinked = true
        link = handlers['SonoranCAD::Tablet::SetCommunityLink']
        link(account, secret)
        assert(writes == 0)
        for _,e in ipairs(events) do if e.name == 'SonoranCAD::links:Status' then assert(not e.data.newlyLinked) end end
        backendLinked = false; now = now + 31000; failWrite = true
        link(account, secret)
        failWrite = false; link(account, secret)
        assert(writes == 2)
        ''')

if __name__ == '__main__': unittest.main()
