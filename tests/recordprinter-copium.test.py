"""Run with python tests/recordprinter-copium.test.py (requires lupa / Lua 5.4)."""
from pathlib import Path
import unittest
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'sonorancad/submodules/recordPrinter/sv_recordPrinter.lua').read_text(encoding='utf-8')
# Load the actual push-event registration and upload flow, without inventory/world-object handlers.
PRINTER = SOURCE.split('    local Docs = {}', 1)[0] + '\nend) end)'
CAD_URL = 'https://cad.example/record.pdf'
COPIUM_URL = 'https://v.copium.pics/record.pdf'


class RecordPrinterCopiumTests(unittest.TestCase):
    def runtime(self, copium=None, state='started', upload_mode='success'):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute('''
            pluginConfig = {enabled = true}; uploads = {}; queued = {}; warnings = {}
            resourceState = 'started'; uploadMode = 'success'
            function CreateThread(fn) fn() end
            Config = {LoadPlugin = function(_, callback) callback(pluginConfig) end}
            function TriggerEvent(name, event, callback) printRecord = callback end
            function TriggerClientEvent(name, player, url) table.insert(queued, url) end
            function GetResourceState(_) return resourceState end
            function GetUnitCache() return {{id = 7}} end
            function GetUnitIdentityValues(unit) return unit end
            function GetSourceByCadIdentity(_) return 3 end
            function GetPlayerCommunityUserId(source) return 'cu-' .. source end
            function debugLog(...) end
            function warnLog(message) table.insert(warnings, message) end
            function SetTimeout(_, fn) timeout = fn end
            promise = {new = function()
                return {resolve = function(self, value) self.value = value end}
            end}
            Citizen = {Await = function(p)
                if p.value == nil then timeout() end
                return p.value
            end}
            exports = {
                sonorancad = {
                    createPDFDirectory = function(_, id) return '/records/' .. id end,
                    savePdfFromUrl = function(_, url, path) return path end,
                },
                copium = {UploadFile = function(_, path, options, callback)
                    table.insert(uploads, {path = path, options = options})
                    if uploadMode == 'throw' then error('resource stopped') end
                    if uploadMode == 'timeout' then return end
                    if uploadMode == 'failure' then
                        callback(nil, {error = 'upload failed'})
                    else
                        callback('https://v.copium.pics/record.pdf', {})
                    end
                end},
            }
        ''')
        g = lua.globals()
        if copium is not None:
            g.pluginConfig.copium = lua.table_from(copium)
        g.resourceState = state
        g.uploadMode = upload_mode
        lua.execute(PRINTER)
        return lua, g

    def print_record(self, lua, g):
        g.printRecord(lua.table_from({'data': {'identId': 7, 'url': CAD_URL}}, recursive=True))

    def test_older_config_auto_detects_copium_and_exposes_default_to_companion(self):
        lua, g = self.runtime()
        self.assertTrue(g.pluginConfig.copium.enabled)
        self.print_record(lua, g)
        self.assertEqual(g.queued[1], COPIUM_URL)
        self.assertEqual(g.uploads[1].path, '/records/7/record.pdf')
        options = g.uploads[1].options
        self.assertEqual(options.path, 'records')
        self.assertTrue(options.public)
        self.assertFalse(options.evidence)
        self.assertEqual(dict(options.metadata), {'source': 'sonorancad-record-printer', 'identId': 7, 'communityUserId': 'cu-3'})

    def test_records_upload_without_a_linked_cad_account(self):
        for stub in ('GetPlayerCommunityUserId = nil', "function GetPlayerCommunityUserId() error('not linked') end"):
            with self.subTest(stub=stub):
                lua, g = self.runtime()
                lua.execute(stub)
                self.print_record(lua, g)
                self.assertEqual(g.queued[1], COPIUM_URL)
                self.assertIsNone(g.uploads[1].options.metadata.communityUserId)

    def test_auto_detection_preserves_custom_options(self):
        lua, g = self.runtime({'path': 'case-files', 'evidence': True})
        self.print_record(lua, g)
        self.assertTrue(g.pluginConfig.copium.enabled)
        self.assertEqual(g.uploads[1].options.path, 'case-files')
        self.assertTrue(g.uploads[1].options.evidence)

    def test_explicit_opt_out_keeps_cad_link(self):
        lua, g = self.runtime({'enabled': False})
        self.print_record(lua, g)
        self.assertFalse(g.pluginConfig.copium.enabled)
        self.assertEqual(len(g.uploads), 0)
        self.assertEqual(g.queued[1], CAD_URL)

    def test_resource_must_be_started(self):
        for state in ('missing', 'starting', 'stopped'):
            with self.subTest(state=state):
                lua, g = self.runtime(state=state)
                self.print_record(lua, g)
                self.assertEqual(len(g.uploads), 0)
                self.assertEqual(g.queued[1], CAD_URL)
                self.assertEqual(len(g.warnings), 0)

    def test_resource_starts_and_stops_are_detected_per_print(self):
        lua, g = self.runtime(state='stopped')
        for state in ('stopped', 'started', 'stopped', 'started'):
            g.resourceState = state
            self.print_record(lua, g)
        self.assertEqual(list(g.queued.values()), [CAD_URL, COPIUM_URL, CAD_URL, COPIUM_URL])
        self.assertEqual(len(g.uploads), 2)

    def test_upload_failure_exception_and_timeout_keep_cad_link(self):
        for mode in ('failure', 'throw', 'timeout'):
            with self.subTest(mode=mode):
                lua, g = self.runtime(upload_mode=mode)
                self.print_record(lua, g)
                self.assertEqual(len(g.uploads), 1)
                self.assertEqual(g.queued[1], CAD_URL)
                self.assertEqual(len(g.warnings), 1)


if __name__ == '__main__':
    unittest.main()
