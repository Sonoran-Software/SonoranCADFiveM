const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const vm = require('node:vm');

const source = readFileSync(join(__dirname, '..', 'html', 'script.js'), 'utf8');

function harness() {
    const listeners = new Map();
    const requests = [];
    const element = id => ({ id, style: {}, addEventListener() {} });
    const elements = {
        cadDiv: element('cadDiv'),
        hudDiv: element('hudDiv'),
        homeButton: element('homeButton'),
        cadFrame: {
            ...element('cadFrame'),
            src: 'https://cad.example.test/',
            contentWindow: {},
        },
    };
    const $ = target => {
        if (typeof target === 'function') return target();
        const selected = elements[target.slice(1)];
        assert.ok(selected, `Unexpected selector: ${target}`);
        return {
            0: selected,
            css(styles) { Object.assign(selected.style, styles); },
        };
    };
    $.post = (url, body) => {
        requests.push({ url, payload: JSON.parse(body) });
        return { fail() {} };
    };
    const context = vm.createContext({
        $, URL, console,
        GetParentResourceName: () => 'tablet',
        document: {
            getElementById: id => elements[id] || null,
            addEventListener() {},
        },
        window: {
            addEventListener(name, callback) {
                if (!listeners.has(name)) listeners.set(name, []);
                listeners.get(name).push(callback);
            },
        },
    });
    vm.runInContext(source, context, { filename: 'tablet/html/script.js' });
    return {
        context, elements, requests,
        display(enabled) {
            for (const callback of listeners.get('message') || []) {
                callback({
                    source: {},
                    origin: 'https://cfx-nui-tablet',
                    data: { type: 'display', module: 'hud', enabled },
                });
            }
        },
    };
}

test('game-driven Mini CAD displays update the UI without echoing visibility to Lua', () => {
    const s = harness();
    s.display(true);
    assert.deepEqual(s.elements.hudDiv.style, { opacity: 1, pointerEvents: 'auto' });
    s.display(false);
    assert.deepEqual(s.elements.hudDiv.style, { opacity: 0, pointerEvents: 'none' });
    s.display(true);
    assert.deepEqual(s.elements.hudDiv.style, { opacity: 1, pointerEvents: 'auto' });
    assert.deepEqual(s.requests, []);
});

test('the direct header close hides Mini CAD and reports its visibility to Lua', () => {
    const s = harness();
    s.display(true);
    s.context.moduleVisible('hud', false);
    assert.deepEqual(s.elements.hudDiv.style, { opacity: 0, pointerEvents: 'none' });
    assert.deepEqual(s.requests, [{
        url: 'https://tablet/VisibleEvent',
        payload: { state: false, module: 'hud' },
    }]);
});

test('the Mini CAD question-mark help requests the shared help text', () => {
    const s = harness();
    s.context.showHelp();
    assert.deepEqual(s.requests, [{ url: 'https://tablet/ShowHelp', payload: {} }]);
});
