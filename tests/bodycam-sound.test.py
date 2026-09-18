"""Run with python tests/bodycam-sound.test.py (requires lupa / Lua 5.4)."""
from pathlib import Path
import unittest
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / 'sonorancad/submodules/bodycam/cl_bodycam.lua'
SOURCE = CLIENT.read_text(encoding='utf-8')


def section(start, end):
    return SOURCE.split(start, 1)[1].split(end, 1)[0]


class BodycamSoundTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        # Execute production sound functions, event handlers and reminder loop.
        # Only FiveM IO, time and unrelated streaming/recording are replaced.
        prefix = SOURCE.split('local function sendBodycamInfo', 1)[0]
        sounds = 'function PlayBeepSound()' + section(
            'function PlayBeepSound()', "AddEventHandler('playerSpawned'")
        handlers = "RegisterNetEvent('SonoranCAD::bodycam::SetSoundLevel'" + section(
            "RegisterNetEvent('SonoranCAD::bodycam::SetSoundLevel'",
            "RegisterNetEvent('SonoranCAD::bodycam::ToggleAnimation'")
        loop = section('            CreateThread(function()\n                while true do\n                    Wait(100)',
                       "            RegisterNetEvent('SonoranCAD::bodycam::GiveSound'")
        self.lua.execute('''
            clock = 0; sounds = {}; errors = {}; messages = {}; events = {}; broadcasts = 0
            pluginConfig = {beepType='nui', beepFrequency=60000, enableBeeps=true}
            function RegisterNetEvent(name, handler) events[name] = handler end
            function SendNUIMessage(data) table.insert(sounds, data) end
            function PlaySoundFromCoord() table.insert(sounds, {type='native'}) end
            function GetEntityCoords() return {x=0,y=0,z=0} end
            function GetPlayerPed() return 1 end
            function PlayerId() return 1 end
            function GetGameTimer() return clock end
            function nowMs() return clock end
            function sendBodycamInfo(message) table.insert(messages, message) end
            function errorLog() end
            function showClientError(code) table.insert(errors, code) end
            function SetPadShake() end
            function TriggerServerEvent() broadcasts = broadcasts + 1 end
            function Wait(ms) coroutine.yield(ms) end
            function CreateThread(fn) reminder = coroutine.create(fn) end
        ''' + prefix + sounds + handlers + '''
            function enableCamera(enabled) bodyCamDisplayOn = enabled end
            CreateThread(function()
                while true do
                    Wait(100)
        ''' + loop)
        self.g = self.lua.globals()
        self.lua.execute('assert(coroutine.resume(reminder))')

    def command(self, name, value=None):
        self.g.events['SonoranCAD::bodycam::' + name](value)

    def tick(self, time):
        self.g.clock = time
        self.lua.execute('assert(coroutine.resume(reminder))')

    def test_zero_mutes_start_stop_and_reminders_for_both_sound_types(self):
        for sound_type in ('nui', 'native'):
            for zero in ('0', '0.0'):
                with self.subTest(sound_type=sound_type, zero=zero):
                    self.g.pluginConfig.beepType = sound_type
                    self.command('SetSoundLevel', zero)
                    self.g.PlayBeepSound()
                    self.g.PlayOffBeep()
                    self.g.enableCamera(True)
                    self.tick(self.g.clock + 60000)
                    self.assertEqual(len(self.g.sounds), 0)
                    self.assertEqual(len(self.g.errors), 0)

    def test_volume_can_be_restored_after_muting(self):
        self.command('SetSoundLevel', '0')
        self.command('SetSoundLevel', '0.5')
        self.g.PlayBeepSound()
        self.assertEqual(self.g.sounds[1].transactionVolume, 0.5)
        self.command('SetSoundLevel')
        self.assertIn('0.5', self.g.messages[len(self.g.messages)])

    def test_invalid_volume_does_not_change_previous_setting(self):
        for value in ('-1', '1.1', 'text', '1e999'):
            self.command('SetSoundLevel', value)
        self.assertEqual(len(self.g.errors), 4)
        self.g.PlayBeepSound()
        self.assertEqual(self.g.sounds[1].transactionVolume, 0.2)

    def test_default_interval_and_current_frequency(self):
        self.command('SetBeepFrequency')
        self.assertIn('60', self.g.messages[1])
        self.g.enableCamera(True)
        self.tick(100)
        self.tick(60099)
        self.assertEqual(len(self.g.sounds), 1)
        self.tick(60100)
        self.assertEqual(len(self.g.sounds), 2)

    def test_frequency_change_replaces_active_wait_in_seconds(self):
        self.g.enableCamera(True)
        self.tick(100)
        self.g.clock = 10000
        self.command('SetBeepFrequency', '30')
        self.tick(39999)
        self.assertEqual(len(self.g.sounds), 1)
        self.tick(40000)
        self.assertEqual(len(self.g.sounds), 2)
        self.tick(70000)
        self.assertEqual(len(self.g.sounds), 3)
        self.command('SetBeepFrequency', '290')
        self.tick(359999)
        self.assertEqual(len(self.g.sounds), 3)
        self.tick(360000)
        self.assertEqual(len(self.g.sounds), 4)

    def test_invalid_frequency_preserves_setting(self):
        self.command('SetBeepFrequency', '30')
        for value in ('0', '-1', '0.5', '30.5', '3601', 'text', '1e999'):
            self.command('SetBeepFrequency', value)
        self.assertEqual(len(self.g.errors), 7)
        self.command('SetBeepFrequency')
        self.assertIn('30', self.g.messages[len(self.g.messages)])

    def test_server_disable_and_inactive_camera_prevent_reminders(self):
        self.g.enableCamera(True)
        self.g.pluginConfig.enableBeeps = False
        self.tick(60000)
        self.g.pluginConfig.enableBeeps = True
        self.g.enableCamera(False)
        self.tick(120000)
        self.assertEqual(len(self.g.sounds), 0)
        self.assertEqual(self.g.broadcasts, 0)

    def test_server_routes_frequency_to_requesting_player(self):
        source = (ROOT / 'sonorancad/submodules/bodycam/sv_bodycam.lua').read_text(encoding='utf-8')
        block = source.split("elseif args[1] == 'frequency' then", 1)[1].split('elseif', 1)[0]
        self.lua.execute('''
            source = 42; args = {'frequency', '30'}
            function TriggerClientEvent(event, player, value)
                routed = {event, player, value}
            end
        ''' + block)
        self.assertEqual(list(self.g.routed.values()), ['SonoranCAD::bodycam::SetBeepFrequency', 42, '30'])

    def test_modified_lua_files_compile(self):
        for name in ('submodules/bodycam/cl_bodycam.lua', 'submodules/bodycam/sv_bodycam.lua', 'core/logging.lua'):
            self.lua.execute('assert(load(...))', (ROOT / 'sonorancad' / name).read_text(encoding='utf-8'))


if __name__ == '__main__':
    unittest.main()
