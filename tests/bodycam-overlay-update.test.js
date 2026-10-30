// Run with node --test tests/bodycam-overlay-update.test.js (requires zip).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { execFileSync, fork } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const nuiPath = 'sonorancad/core/client_nui';
const customLogoPath = `${nuiPath}/img/bodycam_logo.png`;
const releaseFiles = [
    `${nuiPath}/index.html`,
    `${nuiPath}/bodycam_screen.html`,
    `${nuiPath}/img/bodycam_overlay.png`,
    `${nuiPath}/img/bodycam_logo_standard.png`,
    `${nuiPath}/img/bodycam_logo_gold.png`,
];

function extractUpdate(file, dest) {
    return new Promise((resolve, reject) => {
        const worker = fork(path.join(root, 'sonorancad/core/unzipper/unzip-child.js'), [], {
            stdio: ['ignore', 'pipe', 'pipe', 'ipc'],
        });
        let result;
        let output = '';
        const timer = setTimeout(() => worker.kill(), 10000);
        worker.stdout.on('data', chunk => { output += chunk; });
        worker.stderr.on('data', chunk => { output += chunk; });
        worker.once('message', message => { result = message; });
        worker.once('error', error => { clearTimeout(timer); reject(error); });
        worker.once('close', (code, signal) => {
            clearTimeout(timer);
            if (code === 0 && result?.ok) resolve();
            else reject(new Error(`Update worker failed (${signal || code}): ${result?.error || output}`));
        });
        worker.send({ file, dest, updaterIgnore: { ignore: [] } });
    });
}

test('bodycam release upgrades legacy installs and preserves the optional active logo', async t => {
    // A reserved, unshipped filename survives even updaters that do not know about it.
    assert.equal(execFileSync('git', ['ls-files', '--', customLogoPath], { cwd: root, encoding: 'utf8' }).trim(), '');
    execFileSync('git', ['check-ignore', '--no-index', customLogoPath], { cwd: root });

    const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'bodycam-overlay-update-'));
    t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
    const staging = path.join(temp, 'release');
    const archive = path.join(temp, 'release.zip');
    for (const file of releaseFiles) {
        const destination = path.join(staging, '[sonorancad]', file);
        fs.mkdirSync(path.dirname(destination), { recursive: true });
        fs.copyFileSync(path.join(root, file), destination);
    }
    assert.equal(fs.existsSync(path.join(staging, '[sonorancad]', customLogoPath)), false);
    execFileSync('zip', ['-qr', archive, '[sonorancad]'], { cwd: staging });

    for (const withCustomLogo of [false, true]) {
        await t.test(withCustomLogo ? 'existing logo choice survives updates' : 'existing install receives the default without a config migration', async () => {
            const install = path.join(temp, withCustomLogo ? 'custom' : 'legacy');
            const resource = path.join(install, '[sonorancad]', 'sonorancad');
            const img = path.join(resource, 'core/client_nui/img');
            fs.mkdirSync(img, { recursive: true });
            fs.mkdirSync(path.join(resource, 'configuration'), { recursive: true });
            const config = '{"allowAutoUpdate":true,"existingSetting":"preserve"}\n';
            const bodycamConfig = 'Config = { overlayLocation = "top-right" }\n';
            fs.writeFileSync(path.join(resource, 'configuration/config.json'), config);
            fs.writeFileSync(path.join(resource, 'configuration/bodycam_config.lua'), bodycamConfig);
            fs.writeFileSync(path.join(img, 'bodycam_overlay.png'), 'legacy baked housing and logo');
            fs.writeFileSync(path.join(resource, 'core/client_nui/index.html'), '<iframe src="bodycam_screen.html"></iframe><iframe src="bodycam_light.html"></iframe>');
            fs.writeFileSync(path.join(resource, 'core/client_nui/bodycam_screen.html'), '<img src="./img/bodycam_overlay.png">');
            const customLogo = fs.readFileSync(path.join(root, `${nuiPath}/img/bodycam_logo_standard.png`));
            if (withCustomLogo) fs.writeFileSync(path.join(img, 'bodycam_logo.png'), customLogo);

            await extractUpdate(archive, install);

            for (const file of releaseFiles) {
                assert.deepEqual(fs.readFileSync(path.join(install, '[sonorancad]', file)), fs.readFileSync(path.join(root, file)), file);
            }
            assert.equal(fs.readFileSync(path.join(resource, 'configuration/config.json'), 'utf8'), config);
            assert.equal(fs.readFileSync(path.join(resource, 'configuration/bodycam_config.lua'), 'utf8'), bodycamConfig);
            const activeLogo = path.join(img, 'bodycam_logo.png');
            if (withCustomLogo) assert.deepEqual(fs.readFileSync(activeLogo), customLogo);
            else assert.equal(fs.existsSync(activeLogo), false);

            // Exercise the installed HTML's image fallback, as the browser does on a missing file.
            const nui = path.join(resource, 'core/client_nui');
            const html = fs.readFileSync(path.join(nui, 'bodycam_screen.html'), 'utf8');
            const tag = html.match(/<img\b[^>]*\bid="bodycamLogo"[^>]*>/)[0];
            const logo = { src: tag.match(/\bsrc="([^"]+)"/)[1], onerror: true };
            if (!fs.existsSync(path.resolve(nui, logo.src))) {
                const handler = tag.match(/\bonerror="([^"]+)"/)[1];
                vm.runInNewContext(`(function () { ${handler} }).call(logo)`, { logo });
                assert.equal(logo.onerror, null, 'a missing fallback must not recurse indefinitely');
            }
            const expectedLogo = withCustomLogo ? customLogo : fs.readFileSync(path.join(img, 'bodycam_logo_gold.png'));
            assert.deepEqual(fs.readFileSync(path.resolve(nui, logo.src)), expectedLogo);
        });
    }
});
