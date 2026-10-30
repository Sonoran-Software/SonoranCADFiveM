const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const vm = require('node:vm');

const source = readFileSync(join(__dirname, '..', 'html', 'script.js'), 'utf8');

function harness() {
    const listeners = new Map(), requests = [], elements = {};
    function element(tagName, id = '') {
        const classes = new Set(), attributes = {};
        let text = '';
        const el = { id, tagName: tagName.toUpperCase(), children: [], dataset: {}, style: {},
            classList: { add: name => classes.add(name), remove: name => classes.delete(name),
                contains: name => classes.has(name), toggle(name, on) { on ? classes.add(name) : classes.delete(name); } },
            setAttribute(name, value) { attributes[name] = String(value); },
            getAttribute(name) { return attributes[name]; },
            addEventListener() {},
            appendChild(child) { this.children.push(child); child.parentNode = this; return child; },
            removeChild(child) { this.children.splice(this.children.indexOf(child), 1); child.parentNode = null; },
            closest() {
                if (['BUTTON', 'INPUT', 'TEXTAREA', 'SELECT', 'A'].includes(this.tagName)
                    || attributes.contenteditable === 'true') return this;
                return this.parentNode?.closest() || null;
            },
            getBoundingClientRect() {
                const width = parseFloat(this.style.width) || 360;
                return { top: this.offsetTop, left: this.offsetLeft - width / 2, width };
            },
            get offsetTop() { return parseFloat(this.style.top) || 120; },
            get offsetLeft() { return parseFloat(this.style.left) || 100; },
        };
        Object.defineProperties(el, {
            textContent: { get() { return text + this.children.map(child => child.textContent).join(''); },
                set(value) { text = String(value); this.children = []; } },
            innerHTML: { set() { throw new Error('Call data must not use innerHTML'); } },
        });
        Object.defineProperty(el.style, 'setProperty', { value(name, value) { this[name] = value; } });
        if (id) elements[id] = el;
        return el;
    }
    for (const id of ['cadDiv', 'hudDiv', 'hudFrame', 'hudHeader', 'hudHeaderCalls', 'hudHeaderTime',
        'hudHeaderControls', 'callCode', 'callTitle', 'callLocation', 'callDescription', 'callNotes',
        'callUnits', 'hudDetails', 'homeButton']) element('div', id);
    for (const id of ['btnPrevCall', 'btnAttach', 'btnDetail', 'btnNextCall', 'help', 'close']) element('button', id);
    const frame = element('iframe', 'cadFrame');
    frame.src = 'https://cad.example.test/'; frame.contentWindow = {};
    elements.hudDetails.style.display = 'none';
    elements.hudDiv.appendChild(elements.hudHeader);
    elements.hudHeader.appendChild(elements.hudHeaderControls);
    elements.hudHeaderControls.appendChild(elements.help);
    const body = element('body');
    const $ = target => {
        if (typeof target === 'function') return target();
        const selected = elements[target.slice(1)];
        assert.ok(selected, `Unexpected selector ${target}`);
        return { 0: selected, css(styles) { Object.assign(selected.style, styles); } };
    };
    $.post = (url, payload) => { requests.push({ url, payload: JSON.parse(payload) }); return { fail() {} }; };
    const document = { body, getElementById: id => elements[id] || null,
        createElement: tag => element(tag), addEventListener() {}, querySelectorAll: () => [] };
    const context = vm.createContext({ $, document, URL, GetParentResourceName: () => 'tablet',
        console: { log() {} }, window: { innerWidth: 1280, innerHeight: 720, addEventListener(name, callback) {
            if (!listeners.has(name)) listeners.set(name, []);
            listeners.get(name).push(callback);
        } } });
    vm.runInContext(source, context, { filename: 'tablet/html/script.js' });
    function send(data) {
        for (const callback of listeners.get('message') || []) callback({ source: {}, origin: 'https://cfx-nui-tablet', data });
    }
    return { context, document, elements, requests, send,
        sync(calls = []) { send({ type: 'callSync', ident: 42, activeCalls: calls, emergencyCalls: [] }); },
        command(key) { send({ type: 'command', key }); },
        resize() { for (const callback of listeners.get('resize') || []) callback(); },
    };
}

const call = (callId = 1, values = {}) => ({ dispatch_type: 'CALL_NEW', dispatch: {
    callId, code: '10-50', title: 'Traffic collision', postal: '7253', address: 'Alta St',
    description: 'Two vehicles.', notes: [], units: [], idents: [], ...values,
} });

test('full custom metadata, notes and unit labels stay literal and retain long Unicode text', () => {
    const s = harness(), long = '警🚓<script>&'.repeat(150);
    s.sync([call(1, { code: long, title: long, postal: '<7253>', address: long, description: long,
        notes: [`<img src=x onerror=alert(1)> ${long}`], units: [{ data: { unitNum: `<b>${long}</b>` } }] })]);
    for (const id of ['callCode', 'callTitle']) {
        assert.equal(s.elements[id].textContent, long);
        assert.equal(s.elements[id].title, long);
    }
    assert.equal(s.elements.callLocation.textContent, `<7253> ${long}`);
    assert.equal(s.elements.callLocation.title, `<7253> ${long}`);
    assert.equal(s.elements.callDescription.textContent, long);
    assert.equal(s.elements.callNotes.children[0].textContent, `<img src=x onerror=alert(1)> ${long}`);
    assert.equal(s.elements.callUnits.children[0].textContent, `<b>${long}</b>`);
    assert.equal(s.elements.callUnits.children[0].title, `<b>${long}</b>`);
    assert.equal(s.elements.callNotes.children[0].children.length, 0);
    assert.equal(s.elements.hudHeaderTime.textContent, 'SONORAN');
});

test('note formats are preserved and newest notes win the inclusive configured row limit', () => {
    const s = harness();
    s.send({ type: 'config', key: 'maxrows', value: 2 }); // /tablet mini rows 3 stores 2.
    s.sync([call(1, { notes: ['oldest', 'legacy <value>',
        { type: 'text', time: '12:01', label: 'Sonoran CAD', content: '<official>' },
        { type: 'text', time: '12:02', label: '<Unit>', content: 'Latest text & <literal>' },
        { type: 'image', time: '12:03', label: '<Unit>', content: 'https://example.test/image' }] })]);
    assert.deepEqual(s.elements.callNotes.children.map(note => note.textContent), [
        '2 older notes hidden.',
        '12:03 | <Unit>: (image attachment.)',
        '12:02 | <Unit>: Latest text & <literal>',
        '12:01 | <official>',
    ]);
    s.send({ type: 'config', key: 'maxrows', value: 0 });
    assert.equal(s.elements.callNotes.children.length, 2);
    assert.match(s.elements.callNotes.children[0].textContent, /4 older notes hidden/);
    s.sync([call(1, { notes: ['legacy <literal>'] })]);
    assert.deepEqual(s.elements.callNotes.children.map(note => note.textContent), ['legacy <literal>']);
});

test('empty calls have one message and action functions and key commands safely do nothing', () => {
    const s = harness(); s.sync();
    assert.equal(s.elements.hudDiv.dataset.empty, 'true');
    assert.equal(s.elements.callCode.textContent, 'No active calls');
    assert.equal(s.elements.callTitle.textContent, '');
    assert.equal(s.elements.callLocation.textContent, '');
    for (const id of ['btnPrevCall', 'btnAttach', 'btnDetail', 'btnNextCall']) {
        assert.equal(s.elements[id].disabled, true);
        assert.equal(s.elements[id].getAttribute('aria-disabled'), 'true');
    }
    for (const action of ['prevCall', 'nextCall', 'toggleDetail', 'attach']) s.context[action]();
    for (const key of ['prev', 'next', 'detail', 'attach']) s.command(key);
    assert.equal(s.context.currCall, 0);
    assert.equal(s.elements.hudDetails.style.display, 'none');
    assert.deepEqual(s.requests, []);
});

test('shrinking call sync resets an invalid selection and cleans stale expanded content', () => {
    const s = harness(); s.sync([call(1), call(2), call(3)]);
    s.command('next'); s.command('next'); s.command('detail');
    assert.equal(s.context.currCall, 2);
    assert.equal(s.elements.btnDetail.getAttribute('aria-pressed'), 'true');
    assert.equal(s.elements.hudDiv.classList.contains('details-open'), true);
    s.sync([call(8, { title: 'Replacement' }), call(9)]);
    assert.equal(s.context.currCall, 0);
    assert.equal(s.elements.callTitle.textContent, 'Replacement');
    assert.equal(s.elements.hudHeaderCalls.textContent, '1/2');
    s.sync();
    assert.equal(s.elements.btnDetail.getAttribute('aria-pressed'), 'false');
    assert.equal(s.elements.btnDetail.classList.contains('active'), false);
    assert.equal(s.elements.hudDiv.classList.contains('details-open'), false);
    assert.equal(s.elements.callDescription.textContent, '');
    assert.equal(s.elements.callNotes.textContent, '');
});

test('optional missing fields render empty and meaningful numeric zero survives', () => {
    const s = harness();
    s.sync([{ dispatch: { callId: 1 } }]);
    for (const id of ['callCode', 'callTitle', 'callLocation', 'callDescription', 'callNotes']) {
        assert.equal(s.elements[id].textContent, '');
    }
    s.sync([call(2, { code: 0, title: null, postal: 0, address: undefined, description: 0,
        units: [null, {}, { data: null }, { data: { unitNum: 0 } }], notes: null })]);
    assert.equal(s.elements.callCode.textContent, '0');
    assert.equal(s.elements.callTitle.textContent, '');
    assert.equal(s.elements.callLocation.textContent, '0');
    assert.equal(s.elements.callDescription.textContent, '0');
    assert.deepEqual(s.elements.callUnits.children.map(unit => unit.textContent), ['', '', '', '0']);
});

test('button action handlers and NUI key commands share navigation, details and attachment callbacks', () => {
    const s = harness(); s.sync([call(1, { idents: [42] }), call(2)]);
    assert.equal(s.elements.btnPrevCall.disabled, true);
    assert.equal(s.elements.btnNextCall.disabled, false);
    assert.equal(s.elements.btnAttach.textContent, 'Detach');
    s.context.nextCall(); s.command('next');
    assert.equal(s.context.currCall, 1);
    assert.equal(s.elements.btnNextCall.disabled, true);
    s.context.toggleDetail();
    assert.equal(s.elements.btnDetail.getAttribute('aria-pressed'), 'true');
    s.command('detail');
    assert.equal(s.elements.btnDetail.getAttribute('aria-pressed'), 'false');
    s.command('attach');
    assert.deepEqual(s.requests, [
        { url: 'https://tablet/DetachFromCall', payload: { callId: 1 } },
        { url: 'https://tablet/AttachToCall', payload: { callId: 2 } },
    ]);
    s.context.prevCall(); s.command('prev');
    assert.equal(s.context.currCall, 0);
    s.context.attach();
    assert.deepEqual(s.requests.at(-1), { url: 'https://tablet/DetachFromCall', payload: { callId: 1 } });
});

test('HUD resize accepts numeric and saved pixel dimensions and bounds follow show, resize and drag', () => {
    const s = harness();
    s.send({ type: 'resize', module: 'hud', newWidth: 408, newHeight: '260px' });
    assert.equal(s.elements.hudDiv.style.width, '408px');
    assert.equal(s.elements.hudDiv.style.height, '260px');
    assert.equal(s.elements.hudDiv.style['--hud-top'], '120px');
    s.send({ type: 'resize', module: 'hud', newWidth: -1, newHeight: 'Infinity' });
    assert.equal(s.elements.hudDiv.style.width, '408px');
    assert.equal(s.elements.hudDiv.style.height, '260px');
    s.elements.hudDiv.style.top = '340px'; s.resize();
    assert.equal(s.elements.hudDiv.style['--hud-top'], '340px');
    s.elements.hudDiv.style.top = '360px';
    s.send({ type: 'display', module: 'hud', enabled: true });
    assert.equal(s.elements.hudDiv.style['--hud-top'], '360px');
});

test('Mini CAD drags only by the header and header buttons never start a drag', () => {
    const s = harness();
    assert.equal(s.elements.hudDiv.onmousedown, undefined);
    assert.equal(typeof s.elements.hudHeader.onmousedown, 'function');
    assert.equal(typeof s.elements.cadDiv.onmousedown, 'function');
    let prevented = 0;
    const down = target => ({ target, clientX: 200, clientY: 200,
        preventDefault() { prevented++; }, stopPropagation() {} });
    s.elements.hudHeader.onmousedown(down(s.elements.help));
    assert.equal(prevented, 0);
    assert.equal(s.document.onmousemove, undefined);
    s.elements.hudHeader.onmousedown(down(s.elements.hudHeader));
    assert.equal(prevented, 1);
    s.document.onmousemove({ clientX: 220, clientY: 240, preventDefault() {}, stopPropagation() {} });
    assert.equal(s.elements.hudDiv.style.top, '160px');
    assert.equal(s.elements.hudDiv.style['--hud-top'], '160px');
    s.document.onmouseup();
    assert.equal(s.document.onmousemove, null);
});

test('HUD bounds clamp viewport overflow with a twelve-pixel margin and preserve fitting positions', () => {
    const s = harness();
    s.elements.hudDiv.style.width = '420px';
    s.elements.hudDiv.style.left = '1100px';
    s.elements.hudDiv.style.top = '690px';
    s.send({ type: 'display', module: 'hud', enabled: true });
    assert.equal(s.elements.hudDiv.getBoundingClientRect().left, 848);
    assert.equal(s.elements.hudDiv.style.top, '518px');
    assert.equal(s.elements.hudDiv.style['--hud-top'], '518px');
    s.elements.hudDiv.style.left = '640px';
    s.elements.hudDiv.style.top = '300px';
    s.resize();
    assert.equal(s.elements.hudDiv.style.left, '640px');
    assert.equal(s.elements.hudDiv.style.top, '300px');
    s.elements.hudDiv.style.left = '0px';
    s.elements.hudDiv.style.top = '-40px';
    s.resize();
    assert.equal(s.elements.hudDiv.getBoundingClientRect().left, 12);
    assert.equal(s.elements.hudDiv.style.top, '12px');
});

test('expanding Details reserves its usable height near the viewport bottom without losing saved height', () => {
    const s = harness(); s.sync([call()]);
    s.elements.hudDiv.style.top = '518px';
    s.elements.hudDiv.style.height = '220px';
    s.context.toggleDetail();
    assert.equal(s.elements.hudDiv.style.top, '428px');
    assert.equal(s.elements.hudDiv.style['--hud-top'], '428px');
    assert.equal(s.elements.hudDiv.style.height, '220px');
    s.context.toggleDetail();
    assert.equal(s.elements.hudDiv.style.height, '220px');
    assert.equal(s.elements.btnDetail.getAttribute('aria-pressed'), 'false');
});
