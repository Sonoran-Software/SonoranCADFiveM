// Run with node --test tests/bodycam-copium-upload.test.js
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'sonorancad/submodules/bodycam/sv_bodycam_recording.js'), 'utf8');
const WEBM = Buffer.from([0x1a, 0x45, 0xdf, 0xa3, 1, 2, 3, 4]);

// Loads the server script with FiveM's natives stubbed, and returns what it did.
function load({ copium = null, copiumState = 'started', copiumUpload, registerStatus = 201, unitNum = '1A-12' } = {}) {
	const resourceDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bodycam-copium-'));
	const handlers = {};
	const calls = { uploads: [], fetches: [], results: [], logs: [] };
	const exportsFn = () => {};
	exportsFn.sonorancad = {
		getPlayerCommunityUserId: () => 'cu-42',
		GetUnitByPlayerId: () => ({ id: 7, location: 'Legion Square', data: { unitNum } }),
		GetPluginConfig: (name) => (name === 'bodycam' ? { recording: copium === null ? {} : { copium } } : null),
	};
	exportsFn.copium = {
		UploadFile: (filePath, opts, cb) => {
			calls.uploads.push({ filePath, opts, fileExisted: fs.existsSync(filePath) });
			(copiumUpload || ((done) => setTimeout(() => done('https://v.copium.pics/AbCd1234.webm', { id: 'AbCd1234' }), 5)))(cb);
		},
	};
	const context = vm.createContext({
		require,
		console,
		Buffer,
		setTimeout,
		clearTimeout,
		AbortController,
		globalThis: {},
		GetResourcePath: () => resourceDir,
		GetCurrentResourceName: () => 'sonorancad',
		GetConvar: (name) => (name === 'sonoran_apiKey' ? 'cad-key' : 'NONE'),
		LoadResourceFile: () => '',
		GetResourceState: (name) => (name === 'copium' ? copiumState : 'missing'),
		emit: (event, level, message) => calls.logs.push({ level, message }),
		emitNet: (event, src, result) => calls.results.push(result),
		exports: exportsFn,
		on: (event, fn) => { handlers[event] = fn; },
		onNet: (event, fn) => { handlers[event] = fn; },
		fetch: async (url, opts) => {
			calls.fetches.push({ url, opts });
			const external = url.endsWith('/bodycam-recordings/external');
			const status = external ? registerStatus : 201;
			return { ok: status < 300, status, statusText: '', text: async () => '{"ok":true}' };
		},
	});
	context.globalThis.fetch = context.fetch;
	vm.runInContext(source, context);
	const clip = path.join(resourceDir, 'clip.webm');
	const send = () => {
		fs.writeFileSync(clip, WEBM);
		return handlers['SonoranCAD::bodycam::UploadSavedRecording'](3, { uploadId: 'u1', fileName: 'clip.webm', durationMs: 42000, trigger: 'panic' }, clip);
	};
	return { calls, send, clip, setCopiumState: (state) => { copiumState = state; } };
}

const cadUploads = (calls) => calls.fetches.filter((f) => f.url.endsWith('/v2/general/bodycam-recordings'));
const registrations = (calls) => calls.fetches.filter((f) => f.url.endsWith('/v2/general/bodycam-recordings/external'));

test('an older config automatically saves clips to running Copium and registers their links with the CAD', async () => {
	const { calls, send, clip } = load();
	await send();
	assert.equal(calls.uploads.length, 1);
	const { opts, fileExisted } = calls.uploads[0];
	assert.equal(fileExisted, true, 'the clip must still be on disk while Copium reads it');
	assert.equal(opts.public, true);
	assert.equal(opts.evidence, true, 'evidence locker by default');
	assert.equal(opts.path, 'bodycam/1A-12');
	assert.equal(opts.mimeType, 'video/webm');
	assert.deepEqual({ ...opts.metadata }, { source: 'sonorancad-bodycam', communityUserId: 'cu-42', unitNumber: '1A-12', identId: 7, durationMs: 42000, trigger: 'panic' });

	assert.equal(cadUploads(calls).length, 0);
	const [register] = registrations(calls);
	assert.equal(register.opts.headers.Authorization, 'Bearer cad-key');
	assert.deepEqual(JSON.parse(register.opts.body), {
		fileUrl: 'https://v.copium.pics/AbCd1234.webm',
		communityUserId: 'cu-42',
		durationMs: 42000,
		identId: 7,
		unitNumber: '1A-12',
		unitLocation: 'Legion Square',
		originalFileName: 'clip.webm',
		mimeType: 'video/webm',
	});
	assert.deepEqual(calls.results.map((r) => r.ok), [true]);
	assert.equal(fs.existsSync(clip), false, 'the temp clip is still cleaned up');
});

test('evidence can be turned off', async () => {
	const { calls, send } = load({ copium: { evidence: false, path: 'cams' } });
	await send();
	assert.equal(calls.uploads[0].opts.evidence, false);
	assert.equal(calls.uploads[0].opts.path, 'cams/1A-12');
});

test('unit numbers become folder names Copium accepts', async () => {
	for (const [unitNum, folder] of [['2-ADAM-12', 'bodycam/2-ADAM-12'], ['1A/12', 'bodycam/1A-12'], ['#12 ★', 'bodycam/12'], ['..', 'bodycam'], ['★', 'bodycam']]) {
		const { calls, send } = load({ unitNum });
		await send();
		assert.equal(calls.uploads[0].opts.path, folder, unitNum);
		assert.equal(calls.uploads[0].opts.title, `Bodycam - ${unitNum}`, 'the title keeps the unit number as written');
	}
});

test('a failed Copium upload falls back to the normal CAD upload', async () => {
	const { calls, send } = load({ copiumUpload: (done) => done(null, { error: 'Copium returned 401' }) });
	await send();
	assert.equal(registrations(calls).length, 0);
	assert.equal(cadUploads(calls).length, 1);
	assert.deepEqual(calls.results.map((r) => r.ok), [true]);
});

test('a failed CAD registration falls back to the normal CAD upload', async () => {
	const { calls, send } = load({ registerStatus: 500 });
	await send();
	assert.equal(registrations(calls).length, 1);
	assert.equal(cadUploads(calls).length, 1);
	assert.deepEqual(calls.results.map((r) => r.ok), [true]);
});

test('Copium turned off, or its resource not running: the CAD upload is unchanged', async () => {
	for (const options of [
		{ copium: { enabled: false } },
		{ copiumState: 'stopped' },
		{ copiumState: 'missing' },
		{ copiumState: 'starting' },
		{ copium: { enabled: true }, copiumState: 'stopped' },
	]) {
		const { calls, send } = load(options);
		await send();
		assert.equal(calls.uploads.length, 0);
		assert.equal(registrations(calls).length, 0);
		assert.equal(cadUploads(calls).length, 1);
		assert.equal(calls.logs.some((entry) => entry.level === 'warn'), false);
	}
});

test('default and explicitly enabled settings both auto-detect Copium', async () => {
	for (const copium of [{}, { enabled: true }]) {
		const { calls, send } = load({ copium });
		await send();
		assert.equal(calls.uploads.length, 1);
		assert.equal(registrations(calls).length, 1);
		assert.equal(cadUploads(calls).length, 0);
	}
});

test('resource starts, stops and restarts are detected for each clip', async () => {
	const { calls, send, setCopiumState } = load({ copiumState: 'stopped' });
	await send();
	setCopiumState('started');
	await send();
	setCopiumState('stopped');
	await send();
	setCopiumState('started');
	await send();
	assert.equal(calls.uploads.length, 2);
	assert.equal(registrations(calls).length, 2);
	assert.equal(cadUploads(calls).length, 2);
	assert.deepEqual(calls.results.map((result) => result.ok), [true, true, true, true]);
});
