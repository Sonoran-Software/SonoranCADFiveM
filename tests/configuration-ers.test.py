"""Run: python tests/configuration-ers.test.py (requires lupa / Lua 5.4).

Exercise the pinned, unchanged master ERS configuration through the production
exporter, actual JSON text round trip and parser. The fixture is deliberately
independent of the current branch's generated defaults and helper implementation.
"""
import json
from datetime import datetime, timezone
from pathlib import Path
import unittest

from lupa.lua54 import LuaRuntime, lua_type


ROOT = Path(__file__).resolve().parents[1]
MASTER_SOURCE = (ROOT / 'tests/fixtures/ersintegration_config.master.lua').read_text(encoding='utf-8')
HELPER_PATH = 'submodules/ersintegration/sh_date_helpers.lua'


class ConfigurationErsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.logs = []
        self.lua.globals().warnLog = lambda code, text: self.logs.append((code, text))
        self.lua.globals().GetCurrentResourceName = lambda: 'sonorancad'
        self.lua.globals().LoadResourceFile = lambda _, path: (ROOT / 'sonorancad' / path).read_text(encoding='utf-8')
        self.lua.globals().resource = 'sonorancad'
        self.lua.execute((ROOT / 'sonorancad' / HELPER_PATH).read_text(encoding='utf-8'))
        shared = (ROOT / 'sonorancad/core/shared_functions.lua').read_text(encoding='utf-8')
        self.lua.execute(shared[shared.index('CadLinkDefaults ='):shared.index('function PerformHttpRequestS')])
        configuration = (ROOT / 'sonorancad/core/configuration.lua').read_text(encoding='utf-8')
        self.lua.execute(configuration[configuration.index('local function legacyTokens'):
                                       configuration.index('collectLegacy = function')])
        self.today = datetime(2026, 7, 15, tzinfo=timezone.utc)
        self.lua.globals().os.time = lambda: int(self.today.timestamp())
        self.lua.globals().os.date = self.date
        self.lua.execute('math.random = function(first, last) return first == 1 and 3 or first end')

    def date(self, pattern, timestamp=None):
        value = self.today if timestamp is None else datetime.fromtimestamp(timestamp, timezone.utc)
        if pattern == '*t':
            return self.lua.table_from({'year': value.year, 'month': value.month, 'day': value.day})
        return value.strftime(pattern)

    def source(self, enabled=False, format_name='en'):
        return MASTER_SOURCE.replace('enabled = false,', f'enabled = {str(enabled).lower()},', 1).replace(
            'DOBFormat = "en",', f'DOBFormat = "{format_name}",', 1)

    def json_value(self, value):
        if lua_type(value) != 'table':
            return value
        entries = dict(value.items())
        if entries and all(type(key) is int for key in entries) and set(entries) == set(range(1, len(entries) + 1)):
            return [self.json_value(entries[key]) for key in range(1, len(entries) + 1)]
        return {str(key): self.json_value(item) for key, item in entries.items()}

    def export(self, source, plugin='ersintegration'):
        exported = self.lua.globals().ExportLegacyPluginConfiguration(plugin, source)
        if isinstance(exported, tuple):
            self.fail(exported[1])
        return self.json_value(exported)

    def parse(self, document):
        received = self.lua.table_from(json.loads(json.dumps(document)), recursive=True)
        parsed = self.lua.globals().ParseCadPluginConfiguration('ersintegration', received)
        if isinstance(parsed, tuple):
            self.fail(parsed[1])
        self.assertEqual(self.json_value(received), document, 'Parser mutated the authoritative JSON/cache document')
        return parsed

    def round_trip(self, source):
        document = self.export(source)
        return self.parse(document), document

    def custom_age_source(self, body):
        start = MASTER_SOURCE.index('function returnAgeFromDobString(')
        end = MASTER_SOURCE.index('function generateDate(', start)
        return MASTER_SOURCE[:start] + 'function returnAgeFromDobString(dobString)\n' + body + '\nend\n\n' + MASTER_SOURCE[end:]

    def test_unchanged_master_exports_and_loads_enabled_or_disabled_without_helper_settings(self):
        for enabled in (False, True):
            with self.subTest(enabled=enabled):
                parsed, document = self.round_trip(self.source(enabled=enabled))
                self.assertEqual(parsed.enabled, enabled)
                for helper in ('returnAgeFromDobString', 'generateDate'):
                    self.assertNotIn(helper, document)
                    self.assertIsNone(parsed[helper])
                    self.assertIsNone(self.lua.globals()[helper], 'Runtime helper leaked into global scope')
                self.assertEqual(parsed.customRecords.civilianValues.age(self.lua.table_from({'DOB': '07/10/2000'})), '25')
                self.assertIn('returnAgeFromDobString', document['customRecords']['civilianValues']['age'])
                self.assertIn('generateDate', document['customRecords']['vehicleRegistrationValues']['_imtoih149'])

    def test_builtin_callbacks_match_the_actual_master_functions_for_all_formats(self):
        for format_name, dob in (('en', '07/10/2000'), ('us', '10/07/2000'), ('iso', '2000/10/07')):
            for enabled in (False, True):
                with self.subTest(format=format_name, enabled=enabled):
                    source = self.source(enabled=enabled, format_name=format_name)
                    parsed, _ = self.round_trip(source)
                    legacy = self.lua.globals().ParseCadPluginConfiguration('ersintegration', source, True)
                    self.assertNotIsInstance(legacy, tuple)
                    for value in (dob, 'invalid', None):
                        ped = self.lua.table_from({} if value is None else {'DOB': value})
                        self.assertEqual(parsed.customRecords.civilianValues.age(ped), legacy.customRecords.civilianValues.age(ped))
                        self.assertEqual(parsed.customRecords.licenseRecordValues.age(ped), legacy.customRecords.licenseRecordValues.age(ped))
                    for valid in (False, True):
                        vehicle = self.lua.table_from({'mot': valid})
                        self.assertEqual(parsed.customRecords.vehicleRegistrationValues['_imtoih149'](vehicle),
                                         legacy.customRecords.vehicleRegistrationValues['_imtoih149'](vehicle))
                        ped = self.lua.table_from({'License_Car': 'Valid' if valid else 'Expired'})
                        context = self.lua.table_from({'license': 'License_Car'})
                        self.assertEqual(parsed.customRecords.licenseRecordValues['_54iz1scv7'](ped, context),
                                         legacy.customRecords.licenseRecordValues['_54iz1scv7'](ped, context))

    def test_stock_helper_detection_accepts_indentation_and_windows_line_endings(self):
        source = '\r\n'.join('  \t' + line for line in MASTER_SOURCE.splitlines())
        parsed, document = self.round_trip(source)
        self.assertNotIn('returnAgeFromDobString', document)
        self.assertNotIn('generateDate', document)
        self.assertEqual(parsed.customRecords.civilianValues.age(self.lua.table_from({'DOB': '07/10/2000'})), '25')

    def test_helpers_use_each_parsed_configuration_without_cross_server_leakage(self):
        en, _ = self.round_trip(self.source(True, 'en'))
        us, _ = self.round_trip(self.source(True, 'us'))
        iso, _ = self.round_trip(self.source(True, 'iso'))
        ped = self.lua.table_from({'DOB': '07/10/2000'})
        self.assertEqual(en.customRecords.civilianValues.age(ped), '25')
        self.assertEqual(us.customRecords.civilianValues.age(ped), '26')
        self.assertEqual(en.customRecords.civilianValues.age(ped), '25')
        vehicle = self.lua.table_from({'mot': True})
        self.assertEqual(en.customRecords.vehicleRegistrationValues['_imtoih149'](vehicle), '18/07/2026')
        self.assertEqual(us.customRecords.vehicleRegistrationValues['_imtoih149'](vehicle), '07/18/2026')
        self.assertEqual(iso.customRecords.vehicleRegistrationValues['_imtoih149'](vehicle), '2026/07/18')

    def test_custom_legacy_helper_with_its_real_config_capture_is_preserved(self):
        source = self.custom_age_source('    return "custom:" .. config.DOBFormat .. ":" .. tostring(dobString)')
        parsed, document = self.round_trip(source)
        self.assertIn('returnAgeFromDobString', document)
        self.assertNotIn('generateDate', document)
        self.assertEqual(parsed.customRecords.civilianValues.age(self.lua.table_from({'DOB': 'anything'})), 'custom:en:anything')
        self.assertEqual(parsed.customRecords.licenseRecordValues.age(self.lua.table_from({'DOB': 'other'})), 'custom:en:other')

    def test_literal_only_customizations_are_not_mistaken_for_stock_helpers(self):
        source = MASTER_SOURCE.replace('dobString or "12/12/2000"', 'dobString or "01/01/1990"', 1)
        parsed, document = self.round_trip(source)
        self.assertIn('returnAgeFromDobString', document)
        self.assertEqual(parsed.customRecords.civilianValues.age(self.lua.table_from({})), '36')
        source = MASTER_SOURCE.replace('format_string = "%m/%d/%Y"', 'format_string = "%Y-%m-%d"', 1)
        source = source.replace('DOBFormat = "en",', 'DOBFormat = "us",', 1)
        parsed, document = self.round_trip(source)
        self.assertIn('generateDate', document)
        self.assertEqual(parsed.customRecords.vehicleRegistrationValues['_imtoih149'](self.lua.table_from({'mot': True})), '2026-07-18')

    def test_saved_custom_helpers_override_builtins_only_for_their_configuration(self):
        document = self.export(self.source(True, 'us'))
        document['returnAgeFromDobString'] = 'function(dob) return "saved:" .. config.DOBFormat end'
        document['generateDate'] = 'function(days, before) return before and "custom-past" or "custom-future" end'
        custom = self.parse(document)
        standard, _ = self.round_trip(self.source(True, 'en'))
        ped = self.lua.table_from({'DOB': '07/10/2000'})
        self.assertEqual(custom.customRecords.civilianValues.age(ped), 'saved:us')
        self.assertEqual(standard.customRecords.civilianValues.age(ped), '25')
        self.assertEqual(custom.customRecords.vehicleRegistrationValues['_imtoih149'](self.lua.table_from({'mot': False})), 'custom-past')
        self.assertEqual(custom.customRecords.vehicleRegistrationValues['_imtoih149'](self.lua.table_from({'mot': True})), 'custom-future')

    def test_explicit_helper_properties_remain_available_to_config_qualified_callbacks(self):
        source = MASTER_SOURCE + '''
        config.generateDate = generateDate
        config.customRecords.vehicleRegistrationValues._imtoih149 = function(vehicleData)
            return config.generateDate(365, not vehicleData.mot)
        end'''
        parsed, document = self.round_trip(source)
        self.assertIn('generateDate', document)
        self.assertNotIn('returnAgeFromDobString', document)
        self.assertEqual(lua_type(parsed.generateDate), 'function')
        self.assertEqual(parsed.customRecords.vehicleRegistrationValues['_imtoih149'](self.lua.table_from({'mot': True})), '18/07/2026')
        self.assertEqual(parsed.customRecords.vehicleRegistrationValues['_imtoih149'](self.lua.table_from({'mot': False})), '12/07/2026')

    def test_unrelated_unsupported_captures_and_globals_remain_rejected(self):
        cases = {
            'offset': 'local offset = 3\n' + self.custom_age_source('    return tostring(offset) .. config.DOBFormat'),
            'other': 'local other = {}\n' + self.custom_age_source('    return tostring(other) .. config.DOBFormat'),
            'customGlobal': 'customGlobal = 3\n' + self.custom_age_source('    return tostring(customGlobal) .. config.DOBFormat'),
        }
        for name, source in cases.items():
            with self.subTest(name=name):
                result = self.lua.globals().ExportLegacyPluginConfiguration('ersintegration', source)
                self.assertIsInstance(result, tuple)
                self.assertIsNone(result[0])
                self.assertIn(name, result[1])
        unrelated = '''local config = {enabled=false, pluginName='other'}
        config.callback = function() return config.enabled end'''
        result = self.lua.globals().ExportLegacyPluginConfiguration('other', unrelated)
        self.assertIsInstance(result, tuple)
        self.assertIsNone(result[0])
        self.assertIn('config', result[1])

    def test_an_unrelated_shadowed_local_named_config_is_not_treated_as_the_exported_table(self):
        source = '''local config = {enabled=false, pluginName='ersintegration'}
        do
            local config = {DOBFormat='us'}
            function returnAgeFromDobString() return config.DOBFormat end
        end'''
        result = self.lua.globals().ExportLegacyPluginConfiguration('ersintegration', source)
        self.assertIsInstance(result, tuple)
        self.assertIsNone(result[0])
        self.assertIn('config', result[1])


if __name__ == '__main__':
    unittest.main()
