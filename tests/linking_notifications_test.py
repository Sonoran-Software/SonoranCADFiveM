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

    def test_configured_poll_interval(self):
        lua = self.runtime(True)
        lua.execute('''
        Config.linkPollIntervalMs = 4500
        assert(not IsPlayerLinkedToCad(1) and checks == 1)
        now = now + 4499
        assert(not IsPlayerLinkedToCad(1) and checks == 1)
        now = now + 1
        assert(not IsPlayerLinkedToCad(1) and checks == 2)
        Config.linkPollIntervalMs = 1
        now = now + 999
        assert(not IsPlayerLinkedToCad(1) and checks == 2)
        now = now + 1
        assert(not IsPlayerLinkedToCad(1) and checks == 3)
        ''')

    def test_force_reg_uses_resolved_link_settings(self):
        lua = self.runtime()
        lua.execute('''
        Config.linkCommand = 'cadconnect'; Config.linkButtonText = 'Connect CAD'
        Config.requireLink = true; Config.autoOpenLinkPopup = false
        Config.allowPopupCloseWhenUnlinked = false
        Config.GetPluginConfig = function() return {enabled=true, captiveOption='nag',
            requireLink=false, linkCommand='stale', autoOpenLinkPopup=true,
            allowPopupCloseWhenUnlinked=true} end
        Citizen = {CreateThread=function() end}
        function Wait() end
        function TriggerEvent(name, value) events[#events+1]={name=name,value=value} end
        ''')
        lua.execute((ROOT / 'sonorancad/submodules/forcereg/cl_forcereg.lua').read_text())
        lua.execute('''
        assert(get_link_command() == 'cadconnect' and not should_auto_open_popup())
        assert(not should_allow_popup_close_when_unlinked())
        handlers['SonoranCAD::forcereg:PlayerReg']('license:test',false)
        assert(#events == 0)
        Config.autoOpenLinkPopup = true
        handlers['SonoranCAD::forcereg:PlayerReg']('license:test',false)
        assert(events[1].name == 'SonoranCAD::links:ForceOpen' and events[1].value == true)
        local messages = {}
        DrawText2D = function(text) messages[#messages+1]=text end
        draw_forcereg_message('top')
        assert(messages[2]:find('/cadconnect',1,true) and messages[2]:find('Connect CAD',1,true))
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
