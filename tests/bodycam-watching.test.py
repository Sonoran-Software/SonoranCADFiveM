"""Run with python tests/bodycam-watching.test.py (requires lupa / Lua 5.4)."""
from pathlib import Path
import unittest
from lupa.lua54 import LuaRuntime

SOURCE = (Path(__file__).resolve().parents[1] / 'sonorancad/submodules/bodycam/cl_bodycam.lua').read_text(encoding='utf-8')


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
            errors = {}; toggleAllowed = false
            function RegisterNetEvent(name, fn) toggleHandler = fn end
            function cancelAutomaticDisplayRequest() end
            function IsWearingBodycam() return true end
            function showClientError(code) table.insert(errors, code) end
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


if __name__ == '__main__':
    unittest.main()
