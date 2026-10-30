const test = require('node:test');
const assert = require('node:assert/strict');
const { matrixForCorners } = require('../html/display-surface');

function project(matrix, x, y) {
    const w = matrix[3] * x + matrix[7] * y + matrix[15];
    return [(matrix[0] * x + matrix[4] * y + matrix[12]) / w,
        (matrix[1] * x + matrix[5] * y + matrix[13]) / w];
}

for (const [name, corners] of Object.entries({
    rectangle: [[100, 100], [900, 100], [900, 500], [100, 500]],
    perspective: [[320, 110], [1000, 230], [890, 660], [150, 540]],
    ultrawide: [[900, 210], [2700, 205], [2690, 1000], [910, 1010]]
})) {
    test(`${name}: all iframe corners land on their screen corners`, () => {
        const matrix = matrixForCorners(corners.map(([x, y]) => ({ x, y })), 1280, 640);
        [[0, 0], [1280, 0], [1280, 640], [0, 640]].forEach(([x, y], i) => {
            const actual = project(matrix, x, y);
            assert.ok(Math.abs(actual[0] - corners[i][0]) < 1e-8);
            assert.ok(Math.abs(actual[1] - corners[i][1]) < 1e-8);
        });
    });
}

test('invalid, degenerate and folded surfaces are rejected', () => {
    for (const corners of [null, [], [{ x: NaN, y: 0 }, {}, {}, {}],
        [0, 1, 2, 3].map(x => ({ x, y: 1 })),
        [[0, 0], [2, 2], [0, 2], [2, 0]].map(([x, y]) => ({ x, y }))]) {
        assert.equal(matrixForCorners(corners, 1280, 640), null);
    }
});

function createDisplayUi() {
    const vm = require('node:vm');
    const fs = require('node:fs');
    const classes = new Set();
    const properties = new Map();
    const listeners = {};
    const exit = { hidden: true, addEventListener(type, fn) { this[type] = fn; } };
    const surface = {
        classList: {
            toggle(name, on) { if (on) classes.add(name); else classes.delete(name); },
            remove(name) { classes.delete(name); }
        },
        style: {
            setProperty(name, value) { properties.set(name, value); },
            removeProperty(name) { properties.delete(name); }
        }
    };
    const callbacks = [];
    const gameWindow = {};
    const gameOrigin = 'nui://game';
    const context = {
        parent: gameWindow,
        location: { ancestorOrigins: [gameOrigin] },
        document: { getElementById(id) { return id === 'cadDiv' ? surface : exit; } },
        innerWidth: 1920, innerHeight: 1080,
        addEventListener(type, fn) { listeners[type] = fn; },
        nui(...args) { callbacks.push(args); }
    };
    context.window = context;
    vm.runInNewContext(fs.readFileSync(require.resolve('../html/display-surface'), 'utf8'), context);
    const send = data => listeners.message({ source: gameWindow, origin: gameOrigin, data });
    return { classes, properties, listeners, exit, callbacks, gameWindow, gameOrigin, send };
}

test('child and foreign messages cannot expose the CAD close control or projected surface', () => {
    const { classes, exit, listeners, gameWindow, gameOrigin } = createDisplayUi();
    for (const data of [
        { type: 'display', module: 'cad', enabled: true },
        { type: 'display_surface', enabled: true }
    ]) {
        listeners.message({ source: {}, origin: gameOrigin, data });
        listeners.message({ source: null, origin: gameOrigin, data });
        listeners.message({ source: gameWindow, origin: 'https://example.invalid', data });
    }
    assert.equal(classes.size, 0);
    assert.equal(exit.hidden, true);
});

test('the close control stays hidden for Mini CAD and closes the handheld through its existing callback', () => {
    const { exit, callbacks, send } = createDisplayUi();
    assert.equal(exit.hidden, true);
    send({ type: 'display', module: 'hud', enabled: true });
    assert.equal(exit.hidden, true);

    send({ type: 'display', module: 'cad', enabled: true });
    assert.equal(exit.hidden, false);
    assert.equal(exit.textContent, 'Close tablet');
    send({ type: 'display', module: 'hud', enabled: false });
    assert.equal(exit.hidden, false);
    exit.click();
    assert.equal(callbacks.length, 1);
    assert.equal(callbacks[0][0], 'NUIFocusOff');

    send({ type: 'display', module: 'cad', enabled: false });
    assert.equal(exit.hidden, true);
    send({ type: 'display', module: 'hud', enabled: true });
    assert.equal(exit.hidden, true);
});

test('projected mode exposes Exit computer after hiding the handheld and clears it on shutdown', () => {
    const { classes, properties, exit, callbacks, send } = createDisplayUi();
    // The game hides the handheld module before enabling its projected surface.
    send({ type: 'display', module: 'cad', enabled: false });
    assert.equal(exit.hidden, true);
    send({ type: 'display_surface', enabled: true });
    assert.equal(exit.hidden, false);
    assert.equal(exit.textContent, 'Exit computer');
    assert.equal(classes.has('display-surface-ready'), false);
    send({ type: 'display_surface_frame', corners: [
        { x: .1, y: .2 }, { x: .9, y: .2 }, { x: .9, y: .8 }, { x: .1, y: .8 }
    ] });
    assert.equal(classes.has('display-surface-ready'), true);
    assert.match(properties.get('--display-transform'), /^matrix3d\(/);
    exit.click();
    assert.equal(callbacks[0][0], 'NUIFocusOff');
    send({ type: 'display_surface', enabled: false });
    assert.equal(classes.size, 0);
    assert.equal(exit.hidden, true);
    assert.equal(properties.size, 0);
    send({ type: 'display', module: 'cad', enabled: false });
    assert.equal(exit.hidden, true);
});

test('the close control follows transitions between handheld and projected CAD', () => {
    const { exit, send } = createDisplayUi();
    send({ type: 'display', module: 'cad', enabled: true });
    send({ type: 'display_surface', enabled: true });
    assert.equal(exit.textContent, 'Exit computer');
    assert.equal(exit.hidden, false);

    // A CAD module visibility update must not hide the projected mode's exit.
    send({ type: 'display', module: 'cad', enabled: false });
    assert.equal(exit.hidden, false);
    assert.equal(exit.textContent, 'Exit computer');
    send({ type: 'display_surface', enabled: false });
    assert.equal(exit.hidden, true);

    send({ type: 'display', module: 'cad', enabled: true });
    assert.equal(exit.hidden, false);
    assert.equal(exit.textContent, 'Close tablet');
    send({ type: 'display_surface', enabled: false });
    assert.equal(exit.hidden, false);
    assert.equal(exit.textContent, 'Close tablet');
    send({ type: 'display', module: 'cad', enabled: false });
    assert.equal(exit.hidden, true);
});
