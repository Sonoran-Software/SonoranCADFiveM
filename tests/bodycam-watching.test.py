"""Run with python tests/bodycam-watching.test.py (requires lupa / Lua 5.4)."""
from pathlib import Path
import unittest
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'sonorancad/submodules/bodycam/cl_bodycam.lua').read_text(encoding='utf-8')
SERVER = (ROOT / 'sonorancad/submodules/bodycam/sv_bodycam.lua').read_text(encoding='utf-8')


class WatchingTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        prefix = SOURCE.split('local function sendBodycamInfo', 1)[0]
        callback = "RegisterNUICallback('bodycamWatching'" + SOURCE.split("RegisterNUICallback('bodycamWatching'", 1)[1].split("RegisterNUICallback('bodycamRecordingState'", 1)[0]
        guard = "RegisterNetEvent('SonoranCAD::bodycam::Toggle'" + SOURCE.split("RegisterNetEvent('SonoranCAD::bodycam::Toggle'", 1)[1].split('                if isForceOff then\n', 1)[0]
        self.lua.execute(prefix + '''
            changes = 0; logs = {}; callbacks = {}
            peerStreamActive = true
            function applyDisplayState() changes = changes + 1 end
            function debugLog(message) table.insert(logs, message) end
            function RegisterNUICallback(name, fn) callbacks[name] = fn end
            function isWatching() return watchingDisplayOn end
            function setActive(value) peerStreamActive = value end
            function revokeDuty() bodycamDutyRevoked = true end
        ''' + callback + '''
            errors = {}; errorMessages = {}; toggleAllowed = false
            pluginConfig = {command = 'bodycam'}
            function RegisterNetEvent(name, fn) toggleHandler = fn end
            function cancelAutomaticDisplayRequest() end
            function IsWearingBodycam() return true end
            function showClientError(code, message, ...)
                table.insert(errors, code)
                if message then table.insert(errorMessages, string.format(message, ...)) end
            end
        ''' + guard + 'toggleAllowed = true end)')
        self.g = self.lua.globals()

    def notify(self, watching, sequence):
        self.g.callbacks['bodycamWatching'](self.lua.table_from({'watching': watching, 'sequence': sequence}), lambda _: None)

    def test_last_viewer_disconnect_allows_manual_off(self):
        self.notify(True, 1)
        self.assertTrue(self.g.isWatching())
        self.g.toggleHandler(True, False, False)
        self.assertEqual(self.g.errors[1], 'BODYCAM_WATCH_ACTIVE')
        self.assertFalse(self.g.toggleAllowed)
        self.notify(False, 2)
        self.assertFalse(self.g.isWatching())
        self.g.toggleHandler(True, False, False)
        self.assertTrue(self.g.toggleAllowed)
        self.assertEqual(self.g.changes, 2)

    def test_late_true_cannot_restore_lock_after_false(self):
        self.notify(True, 1)
        self.notify(False, 3)
        self.notify(True, 2)
        self.assertFalse(self.g.isWatching())

    def test_duplicate_callbacks_do_not_reapply_display(self):
        self.notify(True, 1)
        self.notify(False, 1)
        self.notify(True, 2)
        self.assertTrue(self.g.isWatching())
        self.assertEqual(self.g.changes, 1)

    def test_stopped_stream_and_revoked_duty_reject_watching(self):
        self.g.setActive(False)
        self.notify(True, 1)
        self.assertFalse(self.g.isWatching())
        self.g.setActive(True)
        self.g.revokeDuty()
        self.notify(True, 2)
        self.assertFalse(self.g.isWatching())

    def test_invalid_sequences_are_ignored(self):
        for sequence in (0, -1, 1.5, float('inf'), float('nan'), 'bad'):
            self.notify(True, sequence)
            self.assertFalse(self.g.isWatching())
        self.notify(True, 1)
        self.assertTrue(self.g.isWatching())

    def test_client_compiles(self):
        self.lua.execute('assert(load(...))', SOURCE)
        self.lua.execute('assert(load(...))', SERVER)

    def test_authorized_player_is_shown_configured_forceoff_command(self):
        self.g.pluginConfig.command = 'bc'
        self.notify(True, 1)
        self.g.toggleHandler(True, False, False, True)
        self.assertEqual(self.g.errors[1], 'BODYCAM_WATCH_ACTIVE')
        self.assertIn('use /bc forceoff', self.g.errorMessages[1])
        self.assertFalse(self.g.toggleAllowed)

    def test_unauthorized_player_gets_permission_denial_and_wait_instruction(self):
        self.notify(True, 1)
        self.g.toggleHandler(True, False, False, False)
        self.assertEqual(self.g.errors[1], 'BODYCAM_WATCH_ACTIVE')
        self.assertIn('do not have permission', self.g.errorMessages[1])
        self.assertIn('Wait until all viewers stop watching', self.g.errorMessages[1])
        self.assertNotIn('/bodycam forceoff', self.g.errorMessages[1])
        self.assertFalse(self.g.toggleAllowed)

    def test_missing_permission_result_does_not_advertise_forceoff(self):
        self.notify(True, 1)
        self.g.toggleHandler(True, False, False)
        self.assertIn('do not have permission', self.g.errorMessages[1])

    def test_authorized_forceoff_bypasses_viewing_guard(self):
        self.notify(True, 1)
        self.g.toggleHandler(True, False, True)
        self.assertTrue(self.g.toggleAllowed)
        self.assertEqual(len(self.g.errors), 0)


class ForceOffPermissionTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        helper_and_command = 'local function canForceOffBodycam' + SERVER.split('local function canForceOffBodycam', 1)[1].split("RegisterNetEvent('SonoranCAD::bodycam::Request'", 1)[0]
        toggle = "RegisterNetEvent('SonoranCAD::bodycam::RequestToggle'" + SERVER.split("RegisterNetEvent('SonoranCAD::bodycam::RequestToggle'", 1)[1].split("RegisterNetEvent('SonoranCAD::bodycam::PublishRuntime'", 1)[0]
        self.lua.execute('''
            pluginConfig = {command = 'bodycam'}
            source = 42; allowed = false; permissionCalls = {}; sent = {}; errors = {}
            function IsPlayerAceAllowed(player, ace)
                table.insert(permissionCalls, {player, ace})
                return allowed
            end
            function RegisterCommand(name, fn) commandHandler = fn end
            function RegisterNetEvent(name, fn) toggleRequest = fn end
            function TriggerClientEvent(...) table.insert(sent, {...}) end
            function sendClientError(player, code) table.insert(errors, {player, code}) end
            function GetUnitByPlayerId() return nil end
            function debugLog() end
        ''' + helper_and_command + toggle)
        self.g = self.lua.globals()

    def command(self, player=42):
        self.g.commandHandler(player, self.lua.table_from(['forceoff']), 'bodycam forceoff')

    def test_permission_hint_uses_default_ace_without_running_a_command_first(self):
        self.g.allowed = True
        self.g.toggleRequest(True, False)
        self.assertEqual(list(self.g.permissionCalls[1].values()), [42, 'sonorancad.bodycam.forceoff'])
        self.assertEqual(list(self.g.sent[1].values()), ['SonoranCAD::bodycam::Toggle', 42, True, False, False, True])

    def test_denied_permission_cannot_be_overridden_by_client_arguments(self):
        self.g.toggleRequest(True, False, True)
        self.assertFalse(self.g.sent[1][6])
        self.command()
        self.assertEqual(list(self.g.errors[1].values()), [42, 'BODYCAM_FORCEOFF_PERMISSION'])
        self.assertEqual(len(self.g.sent), 1)

    def test_custom_ace_is_shared_by_hint_and_forceoff_execution(self):
        self.g.pluginConfig.forceOffAce = 'staff.bodycam.forceoff'
        self.g.allowed = True
        self.g.toggleRequest(True, False)
        self.command()
        self.assertEqual(self.g.permissionCalls[1][2], 'staff.bodycam.forceoff')
        self.assertEqual(self.g.permissionCalls[2][2], 'staff.bodycam.forceoff')
        self.assertTrue(self.g.sent[1][6])
        self.assertEqual(list(self.g.sent[2].values()), ['SonoranCAD::bodycam::Toggle', 42, True, False, True])

    def test_blank_ace_allows_hint_and_command_without_permission_lookup(self):
        self.g.pluginConfig.forceOffAce = ''
        self.g.toggleRequest(True, False)
        self.command()
        self.assertTrue(self.g.sent[1][6])
        self.assertEqual(len(self.g.permissionCalls), 0)
        self.assertEqual(len(self.g.sent), 2)

    def test_forceoff_rechecks_permission_after_hint(self):
        self.g.allowed = True
        self.g.toggleRequest(True, False)
        self.g.allowed = False
        self.command()
        self.assertEqual(len(self.g.sent), 1)
        self.assertEqual(self.g.errors[1][2], 'BODYCAM_FORCEOFF_PERMISSION')

    def test_automatic_off_does_not_check_or_advertise_forceoff(self):
        self.g.toggleRequest(False, False)
        self.assertEqual(len(self.g.permissionCalls), 0)
        self.assertFalse(self.g.sent[1][6])

    def test_console_forceoff_preserves_existing_bypass(self):
        self.command(0)
        self.assertEqual(len(self.g.permissionCalls), 0)
        self.assertEqual(list(self.g.sent[1].values()), ['SonoranCAD::bodycam::Toggle', 0, True, False, True])


if __name__ == '__main__':
    unittest.main()
