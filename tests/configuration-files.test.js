// Run: node --test tests/configuration-files.test.js
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../sonorancad/core/http.js'), 'utf8');

function setup(t) {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'cad-configuration-test-'));
    t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
    const api = {};
    const state = { failRename: false, failWrite: false };
    const io = Object.create(fs);
    io.renameSync = (...args) => {
        if (state.failRename) throw new Error('Permission denied');
        return fs.renameSync(...args);
    };
    io.writeFileSync = (...args) => {
        if (state.failWrite) throw new Error('Disk full');
        return fs.writeFileSync(...args);
    };
    vm.runInNewContext(source, {
        require: (name) => name === 'fs' ? io : require(name),
        GetCurrentResourceName: () => 'sonorancad', GetResourcePath: () => directory,
        exports: (name, fn) => { api[name] = fn; }
    });
    return { directory, api, state };
}

test('cache replacement preserves complete JSON and previous bytes on write/rename errors', t => {
    const { directory, api, state } = setup(t);
    const cache = path.join(directory, '.configuration-cache.json');
    const first = JSON.stringify({ configuration: { plugins: { custom: { enabled: false } } } });
    assert.equal(api.WriteCadConfiguration('cache', first), true);
    for (const failure of ['failWrite', 'failRename']) {
        state[failure] = true;
        assert.equal(api.WriteCadConfiguration('cache', '{"replacement":true}'), false);
        assert.equal(fs.readFileSync(cache, 'utf8'), first);
        assert.equal(fs.existsSync(cache + '.tmp'), false);
        state[failure] = false;
    }
    assert.equal(api.WriteCadConfiguration('mock', '{"mock":true}'), true);
    assert.equal(fs.readFileSync(cache, 'utf8'), first, 'Mock storage must not alter fallback cache');
    assert.equal(api.WriteCadConfiguration('cache', '{"replacement":true}'), true);
    assert.deepEqual(JSON.parse(fs.readFileSync(cache, 'utf8')), { replacement: true });
});

test('legacy inventory and archive preserve custom/disabled configs and existing backups', t => {
    const { directory, api, state } = setup(t);
    const legacy = path.join(directory, 'configuration');
    const archived = path.join(directory, 'configuration_old');
    fs.mkdirSync(legacy);
    fs.mkdirSync(path.join(directory, 'submodules/custom'), { recursive: true });
    fs.writeFileSync(path.join(legacy, 'custom_config.lua'), 'disabled custom settings');
    const found = JSON.parse(api.ListLegacyCadConfiguration());
    assert.deepEqual(found.files, ['custom_config.lua']);
    assert.deepEqual(found.plugins, ['custom']);
    assert.match(JSON.parse(api.ListLegacyCadConfiguration('..')).error, /Cannot read/);
    state.failRename = true;
    assert.equal(api.ArchiveLegacyCadConfiguration(), false);
    assert.equal(fs.existsSync(legacy), true);
    state.failRename = false;
    fs.mkdirSync(archived);
    fs.writeFileSync(path.join(archived, 'keep.txt'), 'existing backup');
    assert.equal(api.ArchiveLegacyCadConfiguration(), false);
    assert.equal(fs.readFileSync(path.join(archived, 'keep.txt'), 'utf8'), 'existing backup');
    fs.unlinkSync(path.join(archived, 'keep.txt'));
    fs.rmdirSync(archived);
    assert.equal(api.ArchiveLegacyCadConfiguration(), true);
    assert.equal(fs.existsSync(legacy), false);
    assert.equal(fs.readFileSync(path.join(archived, 'custom_config.lua'), 'utf8'), 'disabled custom settings');
    assert.match(JSON.parse(api.ListLegacyCadConfiguration()).error, /Cannot read/);
});

test('root config contains only credentials and is created atomically without replacing configured values', t => {
    const { directory, api, state } = setup(t);
    const target = path.join(directory, 'config.json');
    state.failWrite = true;
    assert.equal(api.WriteCadBootstrapConfiguration('legacy-key', 7), false);
    assert.equal(fs.existsSync(target), false);
    state.failWrite = false;
    fs.writeFileSync(target, '{"apiKey":"","serverId":1}');
    assert.equal(api.WriteCadBootstrapConfiguration('legacy-key', 7), true);
    assert.deepEqual(JSON.parse(fs.readFileSync(target, 'utf8')), { apiKey: 'legacy-key', serverId: 7 });
    const original = fs.readFileSync(target, 'utf8');
    assert.equal(api.WriteCadBootstrapConfiguration('legacy-key', 7), true);
    assert.equal(api.WriteCadBootstrapConfiguration('other-key', 8), false);
    assert.equal(fs.readFileSync(target, 'utf8'), original);
    fs.writeFileSync(target, '{"apiKey":"","serverId":1,"branch":"development"}');
    assert.equal(api.WriteCadBootstrapConfiguration('legacy-key', 7), false);
    assert.equal(api.WriteCadBootstrapConfiguration('legacy-key', '7'), false);
    for (const empty of ['', ' \r\n ', '{}', '{"apiKey":"","serverId":1}', '{"apiKey":""}']) {
        fs.writeFileSync(target, empty);
        state.failRename = true;
        assert.equal(api.WriteCadBootstrapConfiguration('legacy-key', 17), false);
        assert.equal(fs.readFileSync(target, 'utf8'), empty, 'Interrupted migration changed the existing bootstrap');
        state.failRename = false;
        assert.equal(api.WriteCadBootstrapConfiguration('legacy-key', 17), true);
        assert.deepEqual(JSON.parse(fs.readFileSync(target, 'utf8')), {apiKey:'legacy-key',serverId:17});
    }
    fs.writeFileSync(target, '{broken');
    assert.equal(api.WriteCadBootstrapConfiguration('legacy-key', 17), false);
    assert.equal(fs.readFileSync(target, 'utf8'), '{broken');
});

test('cache identity follows credentials/server/bootstrap target, independently of CAD-controlled settings', t => {
    const { api } = setup(t);
    const scope = api.GetCadConfigurationScope('private-key', 1, 'https://api.example.test/', false);
    assert.match(scope, /^[a-f0-9]{64}$/);
    assert.equal(scope, api.GetCadConfigurationScope('private-key', 1, 'https://api.example.test', false));
    assert.notEqual(scope, api.GetCadConfigurationScope('other-key', 1, 'https://api.example.test', false));
    assert.notEqual(scope, api.GetCadConfigurationScope('private-key', 2, 'https://api.example.test', false));
    assert.notEqual(scope, api.GetCadConfigurationScope('private-key', 1, 'https://staging.example.test', false));
    assert.notEqual(scope, api.GetCadConfigurationScope('private-key', 1, 'https://api.example.test', true));
});

test('WebSocket and bodycam services use the resolved configuration without local overrides', () => {
    let resolved = { ready: false, apiSendEnabled: true, apiKey: 'resolved-secret', mode: 'development', serverId: 2, communityID: 'test' };
    const exporter = () => {};
    exporter.sonorancad = { GetResolvedConfig: () => JSON.stringify(resolved) };
    function runtime(file) {
        const context = vm.createContext({
            require: name => {
                if (name === '@microsoft/signalr') throw new Error('No networking in this test');
                if (name === 'node-fetch') return () => {};
                return require(name);
            },
            GetCurrentResourceName: () => 'sonorancad', GetResourcePath: () => __dirname,
            GetConvar: () => { throw new Error('Local override read'); },
            LoadResourceFile: () => { throw new Error('Legacy config read'); },
            exports: exporter, emit() {}, on() {}, onNet() {}
        });
        vm.runInContext(fs.readFileSync(path.join(__dirname, '../sonorancad', file), 'utf8'), context);
        return expression => vm.runInContext(expression, context);
    }
    const ws = runtime('core/apiws.js');
    const bodycam = runtime('submodules/bodycam/sv_bodycam_recording.js');
    assert.equal(ws('buildConfig().apiSendEnabled'), false);
    assert.equal(bodycam('getApiKey()'), null);
    resolved.ready = true;
    assert.equal(ws('buildConfig().serverId'), 2);
    assert.equal(ws('buildConfig().apiSendEnabled'), true);
    assert.equal(bodycam('getApiKey()'), 'resolved-secret');
    assert.equal(bodycam('getApiBaseUrl()'), 'https://staging-api.dev.sonorancad.com');
    resolved.apiUrl = 'https://custom-cad-api.example.test/';
    assert.equal(ws('buildConfig().hubUrl'), 'https://custom-cad-api.example.test/apiWsHub');
    assert.equal(bodycam('getApiBaseUrl()'), 'https://custom-cad-api.example.test');
    resolved.apiSendEnabled = false;
    assert.equal(ws('buildConfig().apiSendEnabled'), false);
});
