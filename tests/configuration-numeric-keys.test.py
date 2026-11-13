"""Run with python tests/configuration-numeric-keys.test.py (requires lupa / Lua 5.4).

Exercise the production exporter and parser with an actual JSON text round trip.
Unlike configuration.test.lua's IO doubles, JSON object keys cannot remain numbers.
"""
import json
from pathlib import Path
import unittest

from lupa.lua54 import LuaRuntime, lua_type

ROOT = Path(__file__).resolve().parents[1]


class ConfigurationNumericKeysTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        shared = (ROOT / 'sonorancad/core/shared_functions.lua').read_text(encoding='utf-8')
        self.lua.execute(shared[shared.index('CadLinkDefaults ='):shared.index('function PerformHttpRequestS')])
        configuration = (ROOT / 'sonorancad/core/configuration.lua').read_text(encoding='utf-8')
        self.lua.execute(configuration[configuration.index('local function legacyTokens'):
                                       configuration.index('collectLegacy = function')])
        callers = (ROOT / 'sonorancad/submodules/localcallers/cl_localcallers.lua').read_text(encoding='utf-8')
        lookup = callers[callers.index('local function lookupClothing'):
                         callers.index('            -- Returns a description string')]
        self.clothing_lookup = self.lua.execute('return function(pluginConfig, clothing, drawable, texture)\n' +
                                               lookup + '\nreturn lookupClothing(clothing, drawable, texture) end')
        display = (ROOT / 'sonorancad/submodules/caddisplay/cl_caddisplay.lua').read_text(encoding='utf-8')
        models = display[display.index('            for model, profile in pairs(interactionConfig.models or {}) do'):
                         display.index('            local interactRange')]
        self.model_lookup = self.lua.execute('''return function(interactionConfig)
            local interactionModels, interactionModelKeys = {}, {}
        ''' + models + '\nreturn interactionModels end')
        self.hash_calls = []

        def model_hash(name):
            self.hash_calls.append(name)
            # The consumer must call this only for genuine string names, never the
            # digit representation of a hash. Use the same joaat hash as game names.
            value = 0
            for char in name.lower().encode():
                value = (value + char) & 0xffffffff
                value = (value + (value << 10)) & 0xffffffff
                value ^= value >> 6
            value = (value + (value << 3)) & 0xffffffff
            value ^= value >> 11
            value = (value + (value << 15)) & 0xffffffff
            return value if value < 0x80000000 else value - 0x100000000

        self.lua.globals().GetHashKey = model_hash

    def json_value(self, value):
        if lua_type(value) != 'table':
            return value
        entries = dict(value.items())
        if entries and all(type(key) is int for key in entries) and set(entries) == set(range(1, len(entries) + 1)):
            return [self.json_value(entries[key]) for key in range(1, len(entries) + 1)]
        return {str(key): self.json_value(item) for key, item in entries.items()}

    def round_trip(self, plugin, source):
        exported = self.lua.globals().ExportLegacyPluginConfiguration(plugin, source)
        if isinstance(exported, tuple):
            self.fail(exported[1])
        wire = json.dumps(self.json_value(exported))
        received = self.lua.table_from(json.loads(wire), recursive=True)
        parsed = self.lua.globals().ParseCadPluginConfiguration(plugin, received, True)
        if isinstance(parsed, tuple):
            self.fail(parsed[1])
        self.assertEqual(self.json_value(received), json.loads(wire),
                         'Runtime decoding mutated the authoritative tagged JSON/cache document')
        return parsed, received, wire

    def numeric_entries(self, value):
        entries = value['__sonoranNumericEntries']
        self.assertIsNotNone(entries, 'Numeric dictionary keys lost their transport tag')
        return {entry.key: entry.value for _, entry in entries.items()}

    def parse_document(self, plugin, document):
        received = self.lua.table_from(json.loads(json.dumps(document)), recursive=True)
        parsed = self.lua.globals().ParseCadPluginConfiguration(plugin, received, True)
        if isinstance(parsed, tuple):
            self.fail(parsed[1])
        self.assertEqual(self.json_value(received), document)
        return parsed

    def clothing_source(self, root=False):
        container = 'config' if root else 'config.clothingConfig'
        return '''local config = {
            enabled=true, pluginName='localcallers', configVersion='1.0',
            clothingConfig={}, language={unknownItem='Unknown item', unknownColor='Unknown color'}
        }
        ''' + f'''
        for _, gender in ipairs({{'male', 'female'}}) do
            {container}[gender] = {{}}
            for _, component in ipairs({{'top', 'torso', 'pants', 'shoes', 'hat'}}) do
                {container}[gender][component] = {{}}
                for _, drawable in ipairs({{-1, 0, 7}}) do
                    {container}[gender][component][drawable] = {{
                        name=gender..component..drawable,
                        colors={{[-1]='None', [0]='White', [4]='Red'}}
                    }}
                end
            end
        end
        '''

    def check_clothing(self, root):
        parsed, received, _ = self.round_trip('localcallers', self.clothing_source(root))
        clothing = parsed if root else parsed.clothingConfig
        raw = received if root else received.clothingConfig
        for gender in ('male', 'female'):
            for component in ('top', 'torso', 'pants', 'shoes', 'hat'):
                for drawable in (-1, 0, 7):
                    for texture, color in ((-1, 'None'), (0, 'White'), (4, 'Red')):
                        with self.subTest(gender=gender, component=component, drawable=drawable, texture=texture):
                            self.assertEqual(self.clothing_lookup(parsed, clothing[gender][component], drawable, texture),
                                             (gender + component + str(drawable), color))
                    # Runtime normalization must not mutate the authoritative JSON/cache document.
                    self.assertIsNone(raw[gender][component][drawable])
                    self.assertIsNone(raw[gender][component][str(drawable)])
                    transported = self.numeric_entries(raw[gender][component])[drawable]
                    self.assertEqual(transported.name, gender + component + str(drawable))
                    self.assertEqual(dict(self.numeric_entries(transported.colors)), {-1: 'None', 0: 'White', 4: 'Red'})

    def test_clothing_drawable_and_texture_ids_survive_json(self):
        self.check_clothing(root=False)

    def test_legacy_root_clothing_dictionaries_survive_json(self):
        self.check_clothing(root=True)

    def test_contiguous_clothing_arrays_keep_one_based_indices(self):
        parsed, received, wire = self.round_trip('localcallers', '''local config = {
            enabled=true, pluginName='localcallers', configVersion='1.0',
            language={unknownItem='Unknown item', unknownColor='Unknown color'},
            clothingConfig={male={top={{name='Shirt', colors={'White', 'Red'}},
                                       {name='Vest', colors={'Black'}}}}}
        }''')
        self.assertIsInstance(json.loads(wire)['clothingConfig']['male']['top'], list)
        self.assertEqual(self.clothing_lookup(parsed, parsed.clothingConfig.male.top, 1, 2), ('Shirt', 'Red'))
        self.assertEqual(self.clothing_lookup(parsed, parsed.clothingConfig.male.top, 2, 1), ('Vest', 'Black'))
        self.assertEqual(received.clothingConfig.male.top[1].colors[2], 'Red')

    def test_model_hashes_and_model_names_select_the_original_profile(self):
        source = '''local config = {
            enabled=true, pluginName='caddisplay', configVersion='1.0',
            interaction={models={
                [-1234567]={label='negative'}, [0]={label='zero'}, [1234567]={label='positive'},
                ['0']={label='string zero'}, ['1234567']={label='genuine numeric-string model name'},
                prop_laptop_jimmy={label='named'}, ['001']={label='numeric-looking model name'}
            }}
        }'''
        original = self.lua.globals().ParseCadPluginConfiguration('caddisplay', source, True)
        expected = self.model_lookup(original.interaction)
        parsed, received, _ = self.round_trip('caddisplay', source)
        self.hash_calls.clear()
        actual = self.model_lookup(parsed.interaction)
        self.assertCountEqual(self.hash_calls, ['prop_laptop_jimmy', '001', '0', '1234567'])
        self.assertEqual(set(actual.keys()), set(expected.keys()))
        for key, profile in expected.items():
            self.assertEqual(actual[key].label, profile.label)
        for key in (-1234567, 0, 1234567):
            self.assertIsNone(received.interaction.models[key])
            self.assertEqual(self.numeric_entries(received.interaction.models)[key].label,
                             {-1234567: 'negative', 0: 'zero', 1234567: 'positive'}[key])
        self.assertEqual(received.interaction.models['0'].label, 'string zero')
        self.assertEqual(received.interaction.models['1234567'].label, 'genuine numeric-string model name')
        self.assertEqual(parsed.interaction.models[0].label, 'zero')
        self.assertEqual(parsed.interaction.models['0'].label, 'string zero')

    def test_tagged_clothing_maps_preserve_simultaneous_numeric_and_string_zero_keys(self):
        parsed, received, _ = self.round_trip('localcallers', '''local config = {
            enabled=true, pluginName='localcallers', configVersion='1.0',
            language={unknownItem='Unknown item', unknownColor='Unknown color'},
            clothingConfig={male={top={
                [0]={name='Numeric drawable', colors={[0]='Numeric white', ['0']='String white'}},
                ['0']={name='String drawable', colors={[0]='Numeric black', ['0']='String black'}}
            }}}
        }''')
        drawables = parsed.clothingConfig.male.top
        self.assertEqual(self.clothing_lookup(parsed, drawables, 0, 0), ('Numeric drawable', 'Numeric white'))
        self.assertEqual(drawables['0'].name, 'String drawable')
        self.assertEqual(drawables[0].colors['0'], 'String white')
        self.assertEqual(drawables['0'].colors[0], 'Numeric black')
        self.assertEqual(drawables['0'].colors['0'], 'String black')
        raw = received.clothingConfig.male.top
        self.assertEqual(raw['0'].name, 'String drawable')
        self.assertEqual(self.numeric_entries(raw)[0].name, 'Numeric drawable')
        self.assertEqual(self.numeric_entries(raw['0'].colors)[0], 'Numeric black')

    def test_plain_cad_catalog_clothing_maps_still_restore_numeric_drawable_and_texture_ids(self):
        parsed = self.parse_document('localcallers', {
            'enabled': True, 'pluginName': 'localcallers', 'configVersion': '1.0',
            'language': {'unknownItem': 'Unknown item', 'unknownColor': 'Unknown color'},
            'clothingConfig': {'male': {'top': {
                '0': {'name': 'Catalog shirt', 'colors': {'0': 'White', '4': 'Red'}},
                '7': {'name': 'Catalog vest', 'colors': {'0': 'Black'}},
            }}},
            'custom': {'0': 'record-field string stays a string'},
        })
        self.assertEqual(self.clothing_lookup(parsed, parsed.clothingConfig.male.top, 0, 4), ('Catalog shirt', 'Red'))
        self.assertEqual(self.clothing_lookup(parsed, parsed.clothingConfig.male.top, 7, 0), ('Catalog vest', 'Black'))
        self.assertEqual(parsed.custom['0'], 'record-field string stays a string')
        self.assertIsNone(parsed.custom[0])

    def test_plain_model_names_are_not_guessed_to_be_numeric_hashes(self):
        parsed = self.parse_document('caddisplay', {
            'enabled': True, 'pluginName': 'caddisplay', 'configVersion': '1.0',
            'interaction': {'models': {'1234567': {'label': 'Digit model name'}, '0': {'label': 'Zero model name'}}},
        })
        self.assertIsNone(parsed.interaction.models[1234567])
        self.assertIsNone(parsed.interaction.models[0])
        actual = self.model_lookup(parsed.interaction)
        self.assertCountEqual(self.hash_calls, ['1234567', '0'])
        self.assertCountEqual([profile.label for _, profile in actual.items()], ['Digit model name', 'Zero model name'])

    def test_tagged_weapon_response_maps_preserve_numeric_hash_and_string_key_collisions(self):
        parsed, received, _ = self.round_trip('localcallers', '''local config = {
            enabled=true, pluginName='localcallers', configVersion='1.0',
            weaponConfig={weaponResponses={
                [0]='Numeric zero', ['0']='String zero',
                [1234567]='Numeric hash', ['1234567']='String name', weapon_pistol='Named weapon'
            }}
        }''')
        responses = parsed.weaponConfig.weaponResponses
        self.assertEqual(responses[0], 'Numeric zero')
        self.assertEqual(responses['0'], 'String zero')
        self.assertEqual(responses[1234567], 'Numeric hash')
        self.assertEqual(responses['1234567'], 'String name')
        self.assertEqual(responses.weapon_pistol, 'Named weapon')
        self.assertEqual(self.hash_calls, [], 'Tagged keys were reinterpreted by the legacy dictionary fallback')
        self.assertEqual(received.weaponConfig.weaponResponses['0'], 'String zero')
        self.assertEqual(self.numeric_entries(received.weaponConfig.weaponResponses)[0], 'Numeric zero')

    def test_unrelated_keys_value_types_and_noncanonical_names_are_unchanged(self):
        parsed, _, _ = self.round_trip('caddisplay', '''local config = {
            enabled=true, pluginName='caddisplay', configVersion='1.0',
            custom={['7']='record field', ['0']='zero field', ['-1']='negative field'},
            interaction={models={['1.0']={label='decimal'}, ['1e3']={label='exponent'},
                ['+1']={label='signed name'}, prop_laptop_jimmy={corners={{x=1.25,y=-2,z=0}},
                    enabled=false, label='123', metadata={['0']='string key'}}}}
        }''')
        self.assertEqual(dict(parsed.custom.items()), {'7': 'record field', '0': 'zero field', '-1': 'negative field'})
        for key in ('1.0', '1e3', '+1', 'prop_laptop_jimmy'):
            self.assertIsNotNone(parsed.interaction.models[key])
        profile = parsed.interaction.models.prop_laptop_jimmy
        self.assertIs(profile.enabled, False)
        self.assertEqual(profile.label, '123')
        self.assertEqual(profile.metadata['0'], 'string key')
        self.assertIsNone(profile.metadata[0])
        self.assertEqual(profile.corners[1].x, 1.25)
        self.assertEqual(profile.corners[1].y, -2)
        self.assertEqual(profile.corners[1].z, 0)


if __name__ == '__main__':
    unittest.main()
