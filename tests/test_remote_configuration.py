"""Offline CAD-managed configuration contract tests.

Run: python -m unittest discover -s tests -p test_remote_configuration.py
Requires lupa; no live CAD credentials or FXServer are used.
"""
import json
import unittest
from pathlib import Path

from lupa.lua54 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1] / "sonorancad"


class ConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.responses = []
        self.requests = []
        self.files = {
            "version.json": json.dumps({
                "submoduleConfigs": {
                    "bodycam": {"requiresPlugins": [{"name": "locations", "critical": True}]},
                    "locations": {"requiresPlugins": []},
                }
            })
        }
        self.cleanup_result = {"success": True, "deleted": ["configuration/bodycam_config.lua"]}
        self.lua.execute("""
            Config={apiKey='test-key',communityID='test-community',serverId=1,mode='production',plugins={}}
            Plugins={}; waits={}; commands={}; logs={}; convars={}; threads={}; cleanupCalls=0
            promise={new=function() return {resolve=function(self,value) self.value=value end} end}
            Citizen={Await=function(p) return p.value end}
            function SetTimeout(ms,fn) end
            function Wait(ms) table.insert(waits,ms) end
            function CreateThread(fn) table.insert(threads,fn) end
            function RunThread(index) local fn=table.remove(threads,index or 1); if fn then fn() end end
            function infoLog(s) table.insert(logs,s) end
            function warnLog(code,s) table.insert(logs,s or code) end
            function logError(code,s) table.insert(logs,code .. ':' .. tostring(s)) end
            function SetConvar(k,v) convars[k]=v end
            function ExecuteCommand(s) table.insert(commands,s) end
            function GetCurrentResourceName() return 'sonorancad' end
            function vector3(x,y,z) return {x=x,y=y,z=z,native=true} end
        """)
        self.lua.globals().PerformHttpRequest = self.request
        self.lua.globals().LoadResourceFile = self.load_resource_file
        self.lua.globals().DeleteLocalFiveMConfigurationFiles = self.delete_local_files
        self.lua.globals().json = self.lua.table_from({
            "decode": lambda text: self.to_lua(json.loads(text)),
            "encode": lambda value: json.dumps(self.from_lua(value), separators=(",", ":")),
        })
        self.lua.execute((ROOT / "core/configuration_hooks.lua").read_text())
        self.lua.execute((ROOT / "core/remote_configuration.lua").read_text())

    def to_lua(self, value):
        if isinstance(value, dict):
            return self.lua.table_from({key: self.to_lua(entry) for key, entry in value.items()})
        if isinstance(value, list):
            return self.lua.table_from([self.to_lua(entry) for entry in value])
        return value

    def from_lua(self, value):
        if hasattr(value, "items"):
            pairs = list(value.items())
            if pairs and all(isinstance(key, int) for key, _ in pairs):
                highest = max(key for key, _ in pairs)
                if set(key for key, _ in pairs) == set(range(1, highest + 1)):
                    return [self.from_lua(value[index]) for index in range(1, highest + 1)]
            return {str(key): self.from_lua(entry) for key, entry in pairs}
        return value

    def load_resource_file(self, resource, path):
        return self.files.get(path)

    def delete_local_files(self):
        self.lua.globals().cleanupCalls += 1
        return self.to_lua(self.cleanup_result), None

    def request(self, url, callback, method, body, headers):
        self.requests.append((url, method, json.loads(body) if body else None))
        self.assertEqual(headers["Authorization"], "Bearer test-key")
        if not self.responses:
            raise AssertionError("Unexpected HTTP request; possible retry loop")
        status, value = self.responses.pop(0)
        callback(status, "" if value is None else json.dumps(value), {})

    def payload(self, revision=2, schema=1):
        return {
            "serverId": 1,
            "revision": revision,
            "schemaVersion": schema,
            "templateRevision": "catalog-1",
            "values": {
                "core": {"debugMode": False, "notificationSystem": "auto", "apiKey": "must-not-replace"},
                "plugins": {
                    "locations": {"enabled": True, "interval": 1000},
                    "bodycam": {"enabled": True, "settings": {"beep": True, "volume": 0.5}},
                },
            },
        }

    def load(self, payload=None):
        self.responses.append((200, payload or self.payload()))
        self.lua.globals().LoadRemoteFiveMConfiguration(self.to_lua({
            "detected": False, "core": {}, "plugins": {}, "files": [], "errors": []
        }))

    def test_startup_waits_for_saved_compatible_configuration(self):
        self.responses = [(503, {}), (200, self.payload(schema=99)), (200, self.payload())]
        self.lua.globals().LoadRemoteFiveMConfiguration(self.to_lua({
            "detected": False, "core": {}, "plugins": {}, "files": [], "errors": []
        }))
        self.assertEqual(list(self.lua.globals().waits.values()), [60000, 60000])
        self.assertTrue(self.lua.globals().Config.remoteReady)
        self.assertEqual(self.lua.globals().Config.apiKey, "test-key")
        self.assertEqual(self.lua.globals().Config.remoteRevision, 2)

    def test_local_values_override_cloud_and_are_uploaded_for_review(self):
        local_state = {
            "detected": True,
            "core": {"debugMode": True},
            "plugins": {"bodycam": {"settings": {"beep": False}}},
            "files": ["configuration/bodycam_config.lua"],
            "errors": [],
        }
        self.responses = [(200, self.payload()), (200, {"success": True})]
        self.lua.globals().LoadRemoteFiveMConfiguration(self.to_lua(local_state))
        self.assertTrue(self.lua.globals().Config.debugMode)
        self.assertFalse(self.lua.globals().Config.plugins.bodycam.settings.beep)
        self.assertEqual(self.lua.globals().Config.plugins.bodycam.settings.volume, 0.5)
        self.lua.globals().RunThread(1)
        self.assertTrue(self.lua.globals().Config.localMigrationUploaded)
        url, method, body = self.requests[-1]
        self.assertEqual(method, "POST")
        self.assertTrue(url.endswith("/configuration/migrate"))
        self.assertEqual(body["schemaVersion"], 1)
        self.assertFalse(body["values"]["plugins"]["bodycam"]["settings"]["beep"])

    def test_critical_dependencies_are_enforced_after_local_merge(self):
        data = self.payload()
        del data["values"]["plugins"]["locations"]
        self.load(data)
        self.assertFalse(self.lua.globals().Config.plugins.bodycam.enabled)
        self.assertEqual(self.lua.globals().Config.plugins.bodycam.disableReason, "Missing dependency locations")

    def test_explicit_empty_local_table_clears_cloud_collection(self):
        merged = self.lua.globals().MergeFiveMConfig(
            self.to_lua({"items": ["cloud-value"]}),
            self.to_lua({"items": {}}),
        )
        self.assertEqual(list(merged["items"].items()), [])

    def test_apply_restart_fetches_exact_revision_and_deduplicates(self):
        self.load()
        self.assertFalse(self.lua.globals().ApplyRemoteFiveMConfiguration(self.to_lua(self.payload())))
        self.responses.append((200, self.payload(3)))
        self.assertTrue(self.lua.globals().ApplyRemoteFiveMConfiguration(self.to_lua(self.payload(3))))
        self.lua.globals().RunThread(1)
        self.assertEqual(list(self.lua.globals().commands.values()), ["restart sonorancad"])

    def test_changed_revision_cancels_restart(self):
        self.load()
        self.responses.append((200, self.payload(4)))
        self.assertTrue(self.lua.globals().ApplyRemoteFiveMConfiguration(self.to_lua(self.payload(3))))
        self.lua.globals().RunThread(1)
        self.assertEqual(list(self.lua.globals().commands.values()), [])

    def test_migration_cleanup_requires_uploaded_exact_reviewed_revision(self):
        self.lua.execute("Config.remoteReady=true; Config.localConfigurationDetected=true; Config.localMigrationUploaded=true")
        self.responses.append((200, self.payload(3)))
        self.assertTrue(self.lua.globals().CompleteFiveMConfigurationMigration(self.to_lua(self.payload(3))))
        self.lua.globals().RunThread(1)
        self.assertEqual(self.lua.globals().cleanupCalls, 1)
        self.assertEqual(list(self.lua.globals().commands.values()), ["restart sonorancad"])

    def test_migration_cleanup_is_cancelled_for_stale_review(self):
        self.lua.execute("Config.remoteReady=true; Config.localConfigurationDetected=true; Config.localMigrationUploaded=true")
        self.responses.append((200, self.payload(4)))
        self.assertTrue(self.lua.globals().CompleteFiveMConfigurationMigration(self.to_lua(self.payload(3))))
        self.lua.globals().RunThread(1)
        self.assertEqual(self.lua.globals().cleanupCalls, 0)
        self.assertEqual(list(self.lua.globals().commands.values()), [])

    def test_local_file_loader_detects_core_and_plugin_settings(self):
        self.files["configuration/config.json"] = json.dumps({
            "communityID": "test-community", "apiKey": "secret", "serverId": 1,
            "mode": "production", "debugMode": True,
        })
        self.files["configuration/bodycam_config.lua"] = """
            local config = {enabled=true, pluginName='bodycam', settings={beep=false}}
            if config.enabled then Config.RegisterPluginConfig(config.pluginName, config) end
        """
        state = self.lua.globals().LoadLocalFiveMConfiguration()
        self.assertTrue(state.detected)
        self.assertTrue(state.core.debugMode)
        self.assertFalse(state.plugins.bodycam.settings.beep)

    def test_hooks_restore_vectors_numeric_keys_and_functions(self):
        value = {
            "localcallers": {
                "whitelistZones": [{"center": {"x": 1, "y": 2, "z": 3}}],
                "weaponConfig": {"weaponResponses": {"-2084633992": "rifle"}},
            },
            "ersintegration": {
                "customRecords": {
                    "civilianValues": {"age": "builtin:plugins.ersintegration.customRecords.civilianValues.age"}
                }
            },
        }
        result = self.lua.globals().ResolveFiveMConfig(self.to_lua(value))
        self.assertTrue(result["localcallers"]["whitelistZones"][1]["center"]["native"])
        self.assertEqual(result["localcallers"]["weaponConfig"]["weaponResponses"][-2084633992], "rifle")
        self.assertEqual(self.lua.eval("type")(result["ersintegration"]["customRecords"]["civilianValues"]["age"]), "function")

    def test_builtin_hook_matching_ignores_source_line_numbers_but_rejects_changes(self):
        candidate = self.lua.eval("""
            function(_, type)
                if type == 0 then
                    return true or false
                elseif type == 1 then
                    return true or false
                end
            end
        """)
        changed = self.lua.eval("function() return false end")
        path = "plugins.caddisplay.custom.permissionCheck"
        self.assertEqual(self.lua.globals().MatchFiveMConfigHook(candidate, path), "builtin:" + path)
        self.assertIsNone(self.lua.globals().MatchFiveMConfigHook(changed, path))

    def test_websocket_control_events_are_isolated_from_legacy_key_auth(self):
        source = (ROOT / "core/httpd.lua").read_text()
        self.assertIn("EVENT_FIVEM_CONFIGURATION_MIGRATION", source)
        self.assertIn("source == 'ws' and WebsocketAuthenticatedEvents[eventType] == true", source)
        self.assertIn("if source ~= 'ws' then return false, 'websocket required' end", source)

    def test_changed_lua_files_compile(self):
        compile_lua = self.lua.eval("function(s,n) local fn,err=load(s,n); return fn~=nil,err end")
        for path in [
            "core/configuration_hooks.lua", "core/local_configuration.lua", "core/remote_configuration.lua",
            "core/configuration.lua", "core/client.lua", "core/server.lua", "core/httpd.lua",
            "core/plugin_loader.lua", "submodules/locations/sv_locations.lua",
        ]:
            ok, error = compile_lua((ROOT / path).read_text(), path)
            self.assertTrue(ok, error)


if __name__ == "__main__":
    unittest.main()
