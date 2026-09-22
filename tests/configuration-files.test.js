"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const vm = require("vm");

const resourceRoot = fs.mkdtempSync(path.join(os.tmpdir(), "sonorancad-config-test-"));
const configurationRoot = path.join(resourceRoot, "configuration");
fs.mkdirSync(path.join(configurationRoot, "config-backup"), { recursive: true });
fs.writeFileSync(path.join(configurationRoot, "config.json"), JSON.stringify({
    communityID: "community",
    apiKey: "secret",
    serverId: 2,
    mode: "production",
    debugMode: true,
}));
fs.writeFileSync(path.join(configurationRoot, "updateIgnore.json"), "{}");
fs.writeFileSync(path.join(configurationRoot, "bodycam_config.lua"), "local config = {}");
fs.writeFileSync(path.join(configurationRoot, "config-backup", "old_config.lua"), "local config = {}");
fs.writeFileSync(path.join(configurationRoot, "keep.pdf"), "not configuration");

const registered = {};
const context = {
    require,
    GetResourcePath: () => resourceRoot,
    GetCurrentResourceName: () => "sonorancad",
    exports: (name, fn) => { registered[name] = fn; },
};
vm.runInNewContext(
    fs.readFileSync(path.join(__dirname, "..", "sonorancad", "core", "configuration_files.js"), "utf8"),
    context,
    { filename: "configuration_files.js" },
);

const scanned = JSON.parse(registered.GetLegacyConfigurationFiles());
assert.deepStrictEqual(Array.from(scanned.files), [
    "configuration/bodycam_config.lua",
    "configuration/config-backup/old_config.lua",
]);

const deleted = JSON.parse(registered.DeleteLegacyConfigurationFiles());
assert.strictEqual(deleted.success, true);
assert.strictEqual(fs.existsSync(path.join(configurationRoot, "bodycam_config.lua")), false);
assert.strictEqual(fs.existsSync(path.join(configurationRoot, "config-backup")), false);
assert.strictEqual(fs.existsSync(path.join(configurationRoot, "updateIgnore.json")), true);
assert.strictEqual(fs.existsSync(path.join(configurationRoot, "keep.pdf")), true);
assert.deepStrictEqual(JSON.parse(fs.readFileSync(path.join(configurationRoot, "config.json"), "utf8")), {
    communityID: "community",
    apiKey: "secret",
    mode: "production",
    serverId: 2,
});

fs.rmSync(resourceRoot, { recursive: true, force: true });
console.log("configuration file cleanup tests passed");
