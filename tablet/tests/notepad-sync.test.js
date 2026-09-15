const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const sync = require('../html/notepad-sync.js');

const frameWindow = {};
const frame = {
    src: 'https://cad.example.test/app?community=one',
    contentWindow: frameWindow,
};

test('derives the current CAD iframe origin and requires exact source and origin', () => {
    assert.equal(sync.deriveCadFrameOrigin(frame), 'https://cad.example.test');
    assert.equal(sync.deriveCadFrameOrigin('https://cad.example.test/other'), 'https://cad.example.test');
    assert.equal(sync.deriveCadFrameOrigin('file:///tmp/cad.html'), '');
    assert.equal(sync.deriveCadFrameOrigin('*'), '');

    const event = {
        source: frameWindow,
        origin: 'https://cad.example.test',
        data: { type: sync.MESSAGE_TYPES.state, notes: [] },
    };
    assert.equal(sync.isTrustedCadEvent(event, frame), true);
    assert.equal(sync.isTrustedCadEvent(event, frame, 'https://evil.example.test'), false);
    assert.equal(sync.isTrustedCadEvent({ ...event, source: {} }, frame), false);
    assert.equal(sync.isTrustedCadEvent({ ...event, origin: 'https://evil.example.test' }, frame), false);
    assert.equal(sync.isTrustedCadEvent({ ...event, origin: 'https://cad.example.test:443' }, frame), false);
});

test('posts only validated requests with the exact iframe origin', () => {
    const calls = [];
    const postingFrame = {
        ...frame,
        contentWindow: {
            postMessage(message, targetOrigin) {
                calls.push({ message, targetOrigin });
            },
        },
    };
    const note = {
        id: 'one',
        title: 'Title',
        notes: 'Body',
        metadata: { lookups: [{ result: { status: 'clear' } }] },
    };
    const result = sync.postToCad(postingFrame, {
        type: sync.MESSAGE_TYPES.set,
        requestId: 'set-1',
        notes: [note],
    });
    assert.equal(result.sent, true);
    assert.equal(result.targetOrigin, 'https://cad.example.test');
    assert.deepEqual(calls, [{
        message: {
            type: sync.MESSAGE_TYPES.set,
            requestId: 'set-1',
            notes: [note],
        },
        targetOrigin: 'https://cad.example.test',
    }]);
    assert.notEqual(calls[0].targetOrigin, '*');
    assert.equal(sync.postToCad(postingFrame, {
        type: sync.MESSAGE_TYPES.get,
        requestId: 'get-1',
        notes: [],
    }).sent, false);
});

test('validates inbound response shapes without stripping note metadata', () => {
    const notes = [{
        id: 'one',
        title: 'Title',
        notes: 'Body',
        metadata: { arbitrary: { nested: true } },
    }];
    const event = {
        source: frameWindow,
        origin: 'https://cad.example.test',
        data: {
            type: sync.MESSAGE_TYPES.changed,
            requestId: 'set-1',
            notes,
        },
    };
    assert.deepEqual(sync.parseCadResponseEvent(event, frame), {
        accepted: true,
        message: event.data,
    });
    assert.equal(sync.parseCadResponseEvent({ ...event, source: {} }, frame).accepted, false);
    assert.equal(sync.parseCadResponseEvent({ ...event, origin: 'https://evil.example.test' }, frame).accepted, false);
    assert.equal(sync.parseCadResponseEvent({
        ...event,
        data: { type: sync.MESSAGE_TYPES.state, notes: 'not-a-list' },
    }, frame).accepted, false);
    assert.equal(sync.parseCadResponseEvent({
        ...event,
        data: { type: sync.MESSAGE_TYPES.error, error: { message: 'no' } },
    }, frame).accepted, false);
});

test('malformed outbound and inbound messages fail closed', () => {
    assert.equal(sync.validateOutboundMessage(null).valid, false);
    assert.equal(sync.validateOutboundMessage({
        type: sync.MESSAGE_TYPES.get,
        requestId: ' '.repeat(4),
    }).valid, false);
    assert.equal(sync.validateOutboundMessage({
        type: sync.MESSAGE_TYPES.set,
        requestId: 'set-1',
        notes: 'not-a-list',
    }).valid, false);
    assert.equal(sync.validateInboundMessage({ type: sync.MESSAGE_TYPES.changed, notes: [] }).valid, true);
    assert.equal(sync.validateInboundMessage({
        type: sync.MESSAGE_TYPES.changed,
        requestId: 'x'.repeat(129),
        notes: [],
    }).valid, false);
    assert.equal(sync.validateInboundMessage({ type: 'unknown', notes: [] }).valid, false);
});

test('Lua response validation accepts valid correlated request IDs', () => {
    const luaSource = readFileSync(join(__dirname, '..', 'cl_main.lua'), 'utf8');
    const responseBlock = luaSource.match(
        /local function notepadSyncValidateResponse[\s\S]*?if message\.type == 'scad:notepad:state'/,
    )?.[0];
    assert.ok(responseBlock, 'response validator block should be present');
    assert.match(
        responseBlock,
        /if not notepadSyncValidRequestId\(message\.requestId\) then\s+return nil/,
    );
    assert.doesNotMatch(
        responseBlock,
        /if notepadSyncValidRequestId\(message\.requestId\) then\s+return nil/,
    );
});

test('every CAD navigation resets readiness before changing the iframe source', () => {
    const scriptSource = readFileSync(join(__dirname, '..', 'html', 'script.js'), 'utf8');
    const setUrlBlock = scriptSource.match(
        /else if \(event\.data\.type == "setUrl"\)[\s\S]*?else if \(event\.data\.type == "regbar"\)/,
    )?.[0];
    const refreshBlock = scriptSource.match(
        /else if \(event\.data\.type == "refresh"\)[\s\S]*?\n\s*\}\);/,
    )?.[0];
    const linkCheckBlock = scriptSource.match(
        /function runLinkCheck\(\)[\s\S]*?\n\}/,
    )?.[0];

    assert.ok(setUrlBlock, 'setUrl handler should be present');
    assert.ok(refreshBlock, 'refresh handler should be present');
    assert.ok(linkCheckBlock, 'runLinkCheck should be present');
    assert.ok(setUrlBlock.indexOf('markCadFrameNotReady();') < setUrlBlock.indexOf('.src ='));
    assert.ok(refreshBlock.indexOf('markCadFrameNotReady();') < refreshBlock.indexOf('.src ='));
    assert.ok(linkCheckBlock.indexOf('markCadFrameNotReady();') < linkCheckBlock.indexOf('.src +='));
});

test('notepad sync requires both a community link and a responsive CAD session', () => {
    const luaSource = readFileSync(join(__dirname, '..', 'cl_main.lua'), 'utf8');
    const scriptSource = readFileSync(join(__dirname, '..', 'html', 'script.js'), 'utf8');
    const availabilityBlock = luaSource.match(
        /local function notepadSyncAvailable\(\)[\s\S]*?\nend/,
    )?.[0];
    const loadBlock = scriptSource.match(
        /cadFrameForSync\.addEventListener\("load"[\s\S]*?\n\t\}\);/,
    )?.[0];

    assert.ok(availabilityBlock, 'Lua availability predicate should be present');
    assert.match(availabilityBlock, /isRegistered == true and notepadCadSessionAuthenticated == true/);
    assert.match(luaSource, /if not notepadSyncAvailable\(\) then/);
    assert.ok(loadBlock, 'CAD frame load handler should be present');
    assert.match(loadBlock, /setCadSessionAuthenticated\(false\)/);
    assert.match(loadBlock, /probeCadNotepadSession\(\)/);
    assert.match(scriptSource, /NOTEPAD_SYNC_PROBE_REQUEST_ID = "tablet-notepad-auth-probe"/);
    assert.match(scriptSource, /setCadSessionAuthenticated\(true\)/);
    assert.match(scriptSource, /requestId === NOTEPAD_SYNC_PROBE_REQUEST_ID/);
});
