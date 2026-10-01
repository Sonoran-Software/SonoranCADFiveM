// Run with node --test tests/bodycam-viewers.test.js
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { EventEmitter } = require('node:events');

const root = path.resolve(__dirname, '..');
const viewerSource = fs.readFileSync(path.join(root, 'sonorancad/core/client_nui/js/bodycam_viewers.js'), 'utf8');
const html = fs.readFileSync(process.env.BODYCAM_INDEX_PATH || path.join(root, 'sonorancad/core/client_nui/index.html'), 'utf8');
const drain = () => new Promise(resolve => setImmediate(resolve));

class Clock {
    now = 0;
    nextId = 1;
    timers = new Map();
    setTimeout = (fn, delay) => {
        const id = this.nextId++;
        this.timers.set(id, { fn, at: this.now + delay });
        return id;
    };
    clearTimeout = id => this.timers.delete(id);
    tick(ms) {
        const end = this.now + ms;
        while (true) {
            const next = [...this.timers].filter(([, t]) => t.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
            if (!next) break;
            this.now = next[1].at;
            this.timers.delete(next[0]);
            next[1].fn();
        }
        this.now = end;
    }
}

class PC extends EventEmitter {
    connectionState = 'new';
    iceConnectionState = 'new';
    signalingState = 'stable';
    addEventListener(name, fn) { this.on(name, fn); }
    removeEventListener(name, fn) { this.off(name, fn); }
    state(connection, ice = connection) {
        this.connectionState = connection;
        this.iceConnectionState = ice;
        this.emit('connectionstatechange');
        this.emit('iceconnectionstatechange');
    }
    close() { this.signalingState = 'closed'; this.state('closed'); }
}

class Call extends EventEmitter {
    answerCount = 0;
    closeCount = 0;
    answer(stream) {
        this.answerCount++;
        this.stream = stream;
        this.peerConnection = new PC(); // Matches incoming PeerJS 1.5.5 calls.
        this.transport = this.peerConnection;
        if (this.throwAnswer) throw new Error('answer failed');
        if (this.closeOnAnswer) this.close();
    }
    close() {
        this.closeCount++;
        if (this.throwClose) throw new Error('close failed');
        if (this.peerConnection) this.peerConnection.close();
        this.peerConnection = null;
        // Unanswered PeerJS media calls do not emit close.
        if (this.answerCount) this.emit('close');
    }
}

function environment() {
    const clock = new Clock();
    const context = vm.createContext({
        setTimeout: clock.setTimeout, clearTimeout: clock.clearTimeout,
        setInterval: () => 0, clearInterval: () => {}, AbortController,
        console: { debug() {}, warn() {}, log() {} },
    });
    vm.runInContext(viewerSource, context);
    return { clock, context };
}

function manager() {
    const env = environment();
    const states = [];
    const errors = [];
    const viewers = new env.context.BodycamViewerConnections({
        onWatchingChange: state => states.push(state), onError: reason => errors.push(reason),
    });
    return { ...env, viewers, states, errors, watching: () => states.at(-1)?.watching };
}

test('incoming PC listeners attach after answer; persistent disconnect unlocks', () => {
    const e = manager();
    const call = new Call();
    e.viewers.add(call, {});
    assert.ok(call.transport.listenerCount('connectionstatechange'));
    call.transport.state('connected');
    call.transport.state('disconnected');
    e.clock.tick(4999);
    assert.equal(e.watching(), true);
    e.clock.tick(1);
    assert.equal(e.watching(), false);
    assert.equal(call.closeCount, 1);
    assert.equal(e.clock.timers.size, 0);
    assert.equal(call.transport.eventNames().length, 0);
});

test('transient disconnect recovers without dropping viewer', () => {
    const e = manager(); const call = new Call();
    e.viewers.add(call, {});
    call.transport.state('connected');
    call.transport.state('disconnected');
    e.clock.tick(4000);
    call.transport.state('connected', 'completed');
    e.clock.tick(60000);
    assert.equal(e.watching(), true);
    assert.equal(call.closeCount, 0);
    assert.equal(e.clock.timers.size, 0);
    e.viewers.closeAll('test_end');
});

for (const mode of ['failed', 'closed', 'ice_failed', 'ice_closed', 'ice_disconnected']) {
    test(`${mode} clears a viewer without a PeerJS close event`, () => {
        const e = manager(); const call = new Call();
        e.viewers.add(call, {});
        if (mode.startsWith('ice_')) call.transport.state('connected', mode.slice(4));
        else call.transport.state(mode);
        e.clock.tick(5000);
        assert.equal(e.watching(), false);
        assert.equal(e.clock.timers.size, 0);
    });
}

test('another connected viewer retains the lock and shared capture tracks', () => {
    const e = manager(); const first = new Call(); const second = new Call();
    const stream = { getTracks: () => [{ stop: () => assert.fail('shared track stopped') }] };
    e.viewers.add(first, stream); e.viewers.add(second, stream);
    second.transport.state('connected'); first.transport.state('failed');
    e.clock.tick(60000);
    assert.equal(e.watching(), true);
    assert.equal(second.closeCount, 0);
    e.viewers.closeAll('stream_stopped');
    assert.equal(e.watching(), false);
});

test('pending calls that close silently expire and free a viewer slot', () => {
    const e = manager(); const calls = Array.from({ length: 4 }, () => new Call());
    calls.forEach(call => e.viewers.add(call));
    e.viewers.add(calls[0]); // Duplicate must not close an admitted call at capacity.
    assert.equal(calls[0].closeCount, 0);
    const rejected = new Call(); e.viewers.add(rejected, {});
    assert.equal(rejected.closeCount, 1);
    calls[0].close();
    e.clock.tick(30000);
    assert.equal(e.watching(), false);
    const replacement = new Call(); e.viewers.add(replacement, {});
    assert.equal(replacement.answerCount, 1);
    e.viewers.closeAll('test_end');
});

test('deferred answer attaches PC listeners; failed answer releases transport', () => {
    const e = manager(); const good = new Call(); const bad = new Call();
    bad.throwAnswer = true;
    e.viewers.add(good); e.viewers.add(bad);
    e.viewers.answerPending({});
    assert.equal(bad.transport.signalingState, 'closed');
    good.transport.state('failed');
    assert.equal(e.watching(), false);
    assert.ok(e.errors.includes('answer_failed'));
    assert.equal(e.clock.timers.size, 0);
});

test('answer can synchronously close without restoring a removed call', () => {
    const e = manager(); const call = new Call(); call.closeOnAnswer = true;
    e.viewers.add(call, {});
    assert.equal(e.watching(), false);
    assert.equal(e.clock.timers.size, 0);
});

test('setup and stalled recovery are bounded', () => {
    const e = manager(); const call = new Call();
    e.viewers.add(call, {}); e.clock.tick(30000);
    assert.equal(e.watching(), false);
    const recovering = new Call(); e.viewers.add(recovering, {});
    recovering.transport.state('connected'); recovering.transport.state('disconnected');
    recovering.transport.state('connecting', 'checking');
    e.clock.tick(30000);
    assert.equal(e.watching(), false);
});

test('cleanup is idempotent even if PeerJS close throws', () => {
    const e = manager(); const call = new Call(); call.throwClose = true;
    e.viewers.add(call, {});
    e.viewers.closeAll('peer_closed'); e.viewers.closeAll('stream_stopped');
    assert.equal(call.closeCount, 1);
    assert.equal(call.transport.signalingState, 'closed');
    assert.equal(e.watching(), false);
    assert.equal(e.clock.timers.size, 0);
});

test('watching callbacks serialize rapid hover changes and deduplicate acknowledgements', async () => {
    const e = environment(); const sent = []; let finish;
    const notifier = new e.context.BodycamWatchingNotifier(state => {
        sent.push(state);
        return new Promise(resolve => { finish = resolve; });
    });
    notifier.update({ watching: true }); notifier.update({ watching: false });
    assert.equal(sent.length, 1);
    finish({ ok: true }); await drain();
    assert.equal(sent.length, 2); assert.equal(sent[1].watching, false);
    assert.ok(sent[1].sequence > sent[0].sequence);
    finish({ ok: true }); await drain();
    notifier.update({ watching: false }); await drain();
    assert.equal(sent.length, 2); assert.equal(e.clock.timers.size, 0);
});

test('call error releases only the failed viewer', () => {
    const e = manager(); const call = new Call();
    e.viewers.add(call, {}); call.emit('error', new Error('negotiation failed'));
    assert.equal(e.watching(), false);
    assert.equal(call.transport.signalingState, 'closed');
    assert.equal(e.clock.timers.size, 0);
});

for (const failure of ['reject', 'http_error', 'timeout']) {
    test(`watching callback ${failure} retries the latest state`, async () => {
        const e = environment(); const sent = [];
        const notifier = new e.context.BodycamWatchingNotifier((state, signal) => {
            sent.push(state);
            if (sent.length > 1) return Promise.resolve({ ok: true });
            if (failure === 'reject') return Promise.reject(new Error('offline'));
            if (failure === 'http_error') return Promise.resolve({ ok: false });
            return new Promise((_, reject) => signal.addEventListener('abort', () => reject(new Error('timeout'))));
        });
        notifier.update({ watching: true }); await drain();
        notifier.update({ watching: false });
        if (failure === 'timeout') { e.clock.tick(5000); await drain(); }
        e.clock.tick(1000); await drain();
        assert.equal(sent.length, 2); assert.equal(sent[1].watching, false);
        assert.equal(e.clock.timers.size, 0);
    });
}

function publisher() {
    const e = environment(); const peers = []; const requests = [];
    class Peer extends EventEmitter {
        constructor() { super(); peers.push(this); }
        destroy() { this.destroyed = true; this.emit('close'); }
    }
    Object.assign(e.context, {
        Peer, window: {}, navigator: {}, GetParentResourceName: () => 'sonorancad',
        WebSocket: class { close() {} },
        fetch: (url, options) => { requests.push({ url, state: JSON.parse(options.body) }); return Promise.resolve({ ok: true }); },
    });
    const start = html.indexOf('const defaultPeerConfig =');
    const end = html.indexOf('window.addEventListener("message"', start);
    vm.runInContext(html.slice(start, end), e.context);
    return { ...e, peers, requests, run: code => vm.runInContext(code, e.context) };
}

test('publisher integration: persistent viewer disconnect sends watching=false to Lua', async () => {
    const e = publisher();
    await e.run('ensurePeer({}, "publisher")');
    e.run('peerStream.mediaStream = { getTracks: () => [] }');
    const call = new Call(); e.peers[0].emit('call', call); await drain();
    call.transport.state('connected'); call.transport.state('disconnected');
    e.clock.tick(5000); await drain();
    const notifications = e.requests.filter(r => r.url.endsWith('/bodycamWatching'));
    assert.equal(notifications.at(-1).state.watching, false);
});

test('publisher integration: delayed close from old peer cannot remove new viewers', async () => {
    const e = publisher(); await e.run('ensurePeer({}, "publisher")');
    const old = e.peers[0]; await e.run('stopBodycamStream()'); await drain();
    await e.run('ensurePeer({}, "publisher")'); e.run('peerStream.mediaStream = { getTracks: () => [] }');
    const call = new Call(); e.peers[1].emit('call', call);
    old.emit('close'); old.emit('open', 'old-id'); await drain();
    assert.equal(call.closeCount, 0);
    assert.equal(e.run('peerInstance'), e.peers[1]);
    await e.run('stopBodycamStream()');
});

test('publisher integration: stop cancels pending peer creation', async () => {
    const e = publisher(); let release;
    e.context.buildOptions = () => new Promise(resolve => { release = resolve; });
    e.run('buildPeerOptions = buildOptions');
    const starting = e.run('startBodycamStream({ remotePeerId: "publisher" })');
    await e.run('stopBodycamStream()'); release({}); await starting;
    assert.equal(e.peers.length, 0);
    assert.equal(e.run('peerStream.mediaStream'), null);
});

test('publisher integration: restarting a closed peer reuses the existing capture', async () => {
    const e = publisher(); await e.run('ensurePeer({}, "publisher")');
    e.run('peerStream.mediaStream = { getTracks: () => [] }');
    const capture = e.run('peerStream.mediaStream');
    e.peers[0].emit('close');
    await e.run('startBodycamStream({ remotePeerId: "publisher" })');
    assert.equal(e.peers.length, 2);
    assert.equal(e.run('peerStream.mediaStream'), capture);
    await e.run('stopBodycamStream()');
});

test('publisher integration: signaling disconnect preserves an established media call', async () => {
    const e = publisher(); await e.run('ensurePeer({}, "publisher")');
    e.run('peerStream.mediaStream = { getTracks: () => [] }');
    const call = new Call(); e.peers[0].emit('call', call); call.transport.state('connected');
    e.peers[0].disconnected = true;
    let reconnects = 0; e.peers[0].reconnect = () => { reconnects++; };
    e.peers[0].emit('disconnected'); e.clock.tick(5000); await drain();
    assert.equal(reconnects, 1); assert.equal(call.closeCount, 0);
    await e.run('stopBodycamStream()');
});

test('publisher integration: closed peer reconnect timer does not block its replacement', async () => {
    const e = publisher(); await e.run('ensurePeer({}, "publisher")');
    e.peers[0].disconnected = true; e.peers[0].emit('disconnected'); e.peers[0].emit('close');
    await e.run('ensurePeer({}, "publisher")');
    const replacement = e.peers[1]; let reconnects = 0;
    replacement.disconnected = true; replacement.reconnect = () => { reconnects++; };
    replacement.emit('disconnected'); e.clock.tick(5000); await drain();
    assert.equal(reconnects, 1);
    await e.run('stopBodycamStream()');
});

test('publisher integration: a stopped start failure cannot report failure for a newer stream', async () => {
    const e = publisher(); let reject;
    e.context.buildOptions = () => new Promise((_, fail) => { reject = fail; });
    e.run('buildPeerOptions = buildOptions');
    const starting = e.run('startBodycamStream({ remotePeerId: "publisher" })');
    await e.run('stopBodycamStream()'); reject(new Error('old TURN request failed'));
    await starting;
    assert.equal(e.peers.length, 0);
});

test('publisher integration: stop/restart during microphone setup releases only old capture', async () => {
    const e = publisher(); const videos = []; const mics = []; let releaseMic;
    function stream(bucket) {
        const track = { stopCount: 0, stop() { this.stopCount++; } };
        bucket.push(track);
        return { getTracks: () => [track], getVideoTracks: () => [track], getAudioTracks: () => [track] };
    }
    const renderer = { start() {}, stop() {}, setVideoTrack() {}, getCanvas: () => ({ captureStream: () => stream(videos) }) };
    e.context.window.BodycamGameRenderer = renderer; e.context.BodycamGameRenderer = renderer;
    e.context.MediaStream = class { constructor(tracks) { this.getTracks = () => tracks; } };
    e.context.window.AudioContext = class {
        state = 'running';
        createMediaStreamDestination() { return { stream: stream([]) }; }
        createMediaStreamSource() { return { connect() {} }; }
        close() { return Promise.resolve(); }
    };
    e.context.navigator.mediaDevices = { getUserMedia: () => new Promise(resolve => { releaseMic = resolve; }) };
    const oldStart = e.run('startBodycamStream({ remotePeerId: "publisher" })'); await drain();
    const duplicate = e.run('startBodycamStream({ remotePeerId: "publisher" })');
    assert.equal(duplicate, oldStart); assert.equal(videos.length, 1);
    await e.run('stopBodycamStream()');
    const resolveOld = releaseMic;
    const newStart = e.run('startBodycamStream({ remotePeerId: "publisher" })'); await drain();
    releaseMic(stream(mics)); await newStart;
    const newCapture = e.run('peerStream.mediaStream');
    resolveOld(stream(mics)); await oldStart;
    assert.equal(e.run('peerStream.mediaStream'), newCapture);
    assert.equal(mics[0].stopCount, 0); assert.equal(mics[1].stopCount, 1);
    assert.ok(videos[0].stopCount > 0); assert.equal(videos[1].stopCount, 0);
    await e.run('stopBodycamStream()');
});

test('all inline NUI scripts parse and viewer helper is packaged before use', () => {
    for (const match of html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)) new vm.Script(match[1]);
    assert.ok(html.indexOf('src="js/bodycam_viewers.js"') < html.indexOf('new BodycamViewerConnections'));
    const manifest = fs.readFileSync(path.join(root, 'sonorancad/fxmanifest.lua'), 'utf8');
    assert.ok(manifest.includes("'core/client_nui/js/*.js'"));
});
