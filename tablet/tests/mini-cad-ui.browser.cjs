// Optional browser regression check. Run from any directory with:
// PLAYWRIGHT_MODULE=/path/to/playwright JQUERY_SOURCE=/path/to/jquery.js \
// PLAYWRIGHT_EXECUTABLE=/path/to/chromium TABLET_SCREENSHOT_DIR=/tmp/mini-cad node tablet/tests/mini-cad-ui.browser.cjs
// TABLET_BROWSER_CHECKS=scroll runs only the real mouse-wheel and keyboard checks.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const { createServer } = require('node:http');
const { readFileSync, mkdirSync, existsSync } = require('node:fs');
const { resolve, join, extname } = require('node:path');
const { scenarios, makeCall, defaultIdent, literal } = require('./fixtures/mini-cad-scenarios.cjs');

const htmlRoot = resolve(__dirname, '../html');
const jqueryPath = process.env.JQUERY_SOURCE || (() => {
    try { return require.resolve('jquery/dist/jquery.min.js'); } catch (_) { return null; }
})();
assert(jqueryPath && existsSync(jqueryPath), 'Set JQUERY_SOURCE to a local jQuery distribution.');
const screenshots = process.env.TABLET_SCREENSHOT_DIR;
if (screenshots) mkdirSync(screenshots, { recursive: true });

function listen(server) {
    return new Promise((resolveListen, reject) => {
        server.once('error', reject);
        server.listen(0, '127.0.0.1', () => resolveListen(`http://127.0.0.1:${server.address().port}`));
    });
}

const cadServer = createServer((_, res) => {
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.end('<!doctype html><html><body style="background:#17232e;color:white;font:16px system-ui"><h1>Sample CAD</h1><label>Call notes <input id="cadNotes" aria-label="Call notes"></label><p>Separate-origin fixture; no live account.</p></body></html>');
});
let cadOrigin;
const resourceServer = createServer((req, res) => {
    const pathname = new URL(req.url, 'http://localhost').pathname;
    if (pathname === '/jquery.js') {
        res.setHeader('Content-Type', 'text/javascript');
        return res.end(readFileSync(jqueryPath));
    }
    if (pathname === '/tablet') {
        res.setHeader('Content-Type', 'text/html; charset=utf-8');
        const bootstrap = `<script>
            window.GetParentResourceName=()=> 'tablet';
            window.__testMessageCount=0;
            window.addEventListener('message',event=>{if(event.source===parent)window.__testMessageCount++});
            $.post=(url,body)=>{parent.postMessage({type:'test-callback',name:url.split('/').pop(),payload:JSON.parse(body||'{}')},location.origin);return {fail(){return this}}};
        </script>`;
        return res.end(readFileSync(join(htmlRoot, 'index.html'), 'utf8')
            .replace('nui://game/ui/jquery.js', '/jquery.js')
            .replace('src="https://sonorancad.com/"', `src="${cadOrigin}/"`)
            .replace('</head>', `${bootstrap}</head>`));
    }
    const assets = new Set(['script.js', 'style.css', 'reset.css', 'display-surface.js', 'notepad-sync.js']);
    const asset = pathname.slice(1);
    if (assets.has(asset)) {
        res.setHeader('Content-Type', extname(asset) === '.css' ? 'text/css' : 'text/javascript');
        return res.end(readFileSync(join(htmlRoot, asset)));
    }
    if (pathname !== '/') { res.statusCode = 404; return res.end('Not found'); }
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.end(`<!doctype html><html><head><title>Mini CAD browser check</title><style>
        html,body{margin:0;width:100%;height:100%;overflow:hidden;background:radial-gradient(ellipse at 60% 15%,#344752,#101923 70%)}
        iframe{position:fixed;inset:0;border:0;width:100%;height:100%}
        .label{position:fixed;left:24px;bottom:18px;font:12px system-ui;color:#9cb1c1;pointer-events:none}
        </style></head><body><iframe id="resource" src="/tablet"></iframe><div class="label">LOCAL UI CHECK · Synthetic calls and mock FiveM callbacks</div><script>
        window.callbacks=[];
        window.addEventListener('message',event=>{if(event.source===document.querySelector('#resource').contentWindow&&event.origin===location.origin&&event.data?.type==='test-callback')callbacks.push(event.data)});
        </script></body></html>`);
});

async function loadUi(browser, origin, viewport) {
    const page = await browser.newPage({ viewport });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(origin);
    const ui = page.frames().find(frame => frame.url().endsWith('/tablet'));
    assert(ui, 'Resource iframe loaded');
    await ui.waitForFunction(() => typeof window.refreshCall === 'function' && $.isReady);
    const send = async data => {
        const previous = await ui.evaluate(() => window.__testMessageCount);
        await page.evaluate(data => document.querySelector('#resource').contentWindow.postMessage(data, location.origin), data);
        await ui.waitForFunction(previous => window.__testMessageCount > previous, previous);
    };
    const sync = calls => send({ type: 'callSync', ident: defaultIdent, activeCalls: calls, emergencyCalls: [] });
    return { page, ui, errors, send, sync };
}

async function setScenario(session, scenario, width, height) {
    const { ui, send, sync } = session;
    if (await ui.locator('#btnDetail').getAttribute('aria-pressed') === 'true') await send({ type: 'command', key: 'detail' });
    await send({ type: 'config', key: 'maxrows', value: (scenario.notesRows || 6) - 1 });
    await sync(scenario.calls);
    await send({ type: 'resize', module: 'hud', newWidth: width, newHeight: height });
    await send({ type: 'display', module: 'hud', enabled: true });
    if (scenario.details) await send({ type: 'command', key: 'detail' });
    await ui.waitForFunction(() => document.querySelector('#hudDiv').style.opacity === '1');
}

async function assertLayout(ui, label) {
    const layout = await ui.evaluate(() => {
        const panel = document.querySelector('#hudDiv');
        const bounds = panel.getBoundingClientRect();
        const escaped = [];
        for (const el of panel.querySelectorAll('*')) {
            const box = el.getBoundingClientRect();
            const style = getComputedStyle(el);
            if (!box.width || !box.height || style.visibility === 'hidden') continue;
            if (box.left < bounds.left - 1 || box.right > bounds.right + 1) escaped.push(`${el.tagName}#${el.id}.${el.className}`);
        }
        const controls = [...panel.querySelectorAll('#hudHeaderControls button, #hudFooter button')].map(el => {
            const box = el.getBoundingClientRect();
            return { text: el.textContent, x: box.x, y: box.y, right: box.right, bottom: box.bottom, width: box.width, height: box.height };
        });
        return { escaped, controls, bounds: { left: bounds.left, right: bounds.right, top: bounds.top, bottom: bounds.bottom }, viewport: { width: innerWidth, height: innerHeight } };
    });
    assert.deepEqual(layout.escaped, [], `${label}: every visible element stays within the panel's horizontal bounds`);
    assert.equal(layout.controls.length, 6, `${label}: native header and footer controls remain present`);
    for (const button of layout.controls) {
        assert(button.width > 0 && button.height > 0, `${label}: ${button.text} has a visible box`);
        assert(button.x >= 0 && button.right <= layout.viewport.width + 1 && button.y >= 0 && button.bottom <= layout.viewport.height + 1,
            `${label}: ${button.text} is inside the viewport: ${JSON.stringify(button)}`);
        assert(button.y >= layout.bounds.top && button.bottom <= layout.bounds.bottom + 1, `${label}: ${button.text} stays inside the panel`);
    }
}

async function assertClamps(ui, call, label) {
    const result = await ui.evaluate(() => {
        const info = selector => {
            const el = document.querySelector(selector), style = getComputedStyle(el);
            return { text: el.textContent, title: el.title, overflow: style.overflowX, ellipsis: style.textOverflow,
                clamp: style.webkitLineClamp, lineHeight: Number.parseFloat(style.lineHeight), height: el.getBoundingClientRect().height,
                scrollWidth: el.scrollWidth, clientWidth: el.clientWidth, scrollHeight: el.scrollHeight, clientHeight: el.clientHeight };
        };
        return { code: info('#callCode'), title: info('#callTitle'), location: info('#callLocation') };
    });
    assert.equal(result.code.title, call.code, `${label}: code tooltip retains full text`);
    assert.equal(result.title.title, call.title, `${label}: title tooltip retains full text`);
    assert.equal(result.location.title, `${call.postal ? call.postal + ' ' : ''}${call.address}`, `${label}: location tooltip retains full text`);
    for (const field of ['code', 'location']) {
        assert.equal(result[field].ellipsis, 'ellipsis', `${label}: ${field} uses ellipsis`);
        assert.equal(result[field].overflow, 'hidden', `${label}: ${field} overflow is clipped`);
        assert(result[field].scrollWidth > result[field].clientWidth, `${label}: ${field} has real overflowing fixture text`);
    }
    assert.equal(result.title.clamp, '2', `${label}: title clamps to two lines`);
    assert(result.title.height <= result.title.lineHeight * 2 + 1, `${label}: title never exceeds two rendered lines`);
    assert(result.title.scrollHeight > result.title.clientHeight, `${label}: title fixture extends beyond its clamp`);
}

async function assertFooterAtBottom(ui, label) {
    const gap = await ui.evaluate(() => document.querySelector('#hudDiv').getBoundingClientRect().bottom - document.querySelector('#hudFooter').getBoundingClientRect().bottom);
    assert(gap >= 0 && gap <= 2, `${label}: collapsed footer stays at the bottom of the panel, gap=${gap}`);
}

async function assertDisabledAttachStyle(ui, label) {
    const style = await ui.locator('#btnAttach').evaluate(async el => {
        // Let the enabled -> disabled color transition finish before checking its final appearance.
        getComputedStyle(el).backgroundColor;
        await Promise.all(el.getAnimations().map(animation => animation.finished.catch(() => {})));
        const style = getComputedStyle(el);
        return { disabled: el.disabled, background: style.backgroundColor, color: style.color, opacity: Number(style.opacity) };
    });
    assert(style.disabled, `${label}: Attach is disabled`);
    assert.notEqual(style.background, 'rgb(231, 76, 60)', `${label}: disabled Attach never looks like a red primary action`);
    const components = style.color.match(/[\d.]+/g).map(Number);
    const alpha = components.length > 3 ? components[3] : 1;
    assert(Math.max(...components.slice(0, 3)) * alpha * style.opacity < 200, `${label}: disabled Attach text is visually muted (${style.color})`);
}

async function screenshot(session, name) {
    if (!screenshots) return;
    const panel = await session.ui.locator('#hudDiv').boundingBox();
    const viewport = session.page.viewportSize();
    const x = Math.max(0, panel.x - 12), y = Math.max(0, panel.y - 12);
    await session.page.screenshot({ path: join(screenshots, `${name}.png`), animations: 'disabled', clip: {
        x, y, width: Math.min(viewport.width - x, panel.width + 24), height: Math.min(viewport.height - y, panel.height + 24)
    } });
}

async function assertExpandedText(ui, call, label) {
    const result = await ui.evaluate(() => ['callCode', 'callTitle', 'callLocation'].map(id => {
        const el = document.getElementById(id), style = getComputedStyle(el);
        return { id, text: el.textContent, clamp: style.webkitLineClamp, whiteSpace: style.whiteSpace,
            scrollWidth: el.scrollWidth, clientWidth: el.clientWidth, height: el.getBoundingClientRect().height, lineHeight: Number.parseFloat(style.lineHeight) };
    }));
    for (const el of result) {
        assert(['normal', 'pre-wrap'].includes(el.whiteSpace), `${label}: expanded ${el.id} wraps`);
        assert.notEqual(el.clamp, '2', `${label}: expanded ${el.id} releases the clamp`);
        assert(el.scrollWidth <= el.clientWidth + 1, `${label}: expanded ${el.id} wraps even unbroken tokens`);
    }
    assert.equal(result[0].text, call.code);
    assert.equal(result[1].text, call.title);
    assert.equal(result[2].text, `${call.postal ? call.postal + ' ' : ''}${call.address}`);
}

async function scrollMarkerIntoView(ui, marker, containerSelector) {
    return ui.evaluate(({ marker, containerSelector }) => {
        const container = document.querySelector(containerSelector);
        const walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT);
        let node;
        while ((node = walker.nextNode())) {
            const index = node.textContent.lastIndexOf(marker);
            if (index === -1) continue;
            const range = document.createRange();
            range.setStart(node, index); range.setEnd(node, index + marker.length);
            let box = range.getBoundingClientRect(), outer = container.getBoundingClientRect();
            container.scrollTop += box.bottom - outer.bottom + 12;
            box = range.getBoundingClientRect(); outer = container.getBoundingClientRect();
            return { found: true, visible: box.top >= outer.top - 1 && box.bottom <= outer.bottom + 1,
                scrollHeight: container.scrollHeight, clientHeight: container.clientHeight, overflow: getComputedStyle(container).overflowY };
        }
        return { found: false };
    }, { marker, containerSelector });
}

async function checkScenarios(browser, origin) {
    for (const viewport of [{ width: 1920, height: 1080 }, { width: 1280, height: 720 }]) {
        for (const width of [280, 320, 360, 420]) {
            const session = await loadUi(browser, origin, viewport);
            const { ui, send } = session;
            const prefix = `${viewport.width}x${viewport.height}-w${width}`;
            for (const [name, scenario] of Object.entries(scenarios)) {
                await setScenario(session, scenario, width, 0);
                assert.equal(Math.round((await ui.locator('#hudDiv').boundingBox()).width), width,
                    `${prefix}/${name}: numeric NUI resize applies the persisted panel width`);
                await assertLayout(ui, `${prefix}/${name}`);
                if (['long_header', 'unbroken'].includes(name)) {
                    await assertClamps(ui, scenario.calls[0].dispatch, `${prefix}/${name}`);
                    await screenshot(session, `${prefix}-${name}`);
                    await ui.locator('#btnDetail').click();
                    assert.equal(await ui.locator('#btnDetail').getAttribute('aria-pressed'), 'true');
                    await assertExpandedText(ui, scenario.calls[0].dispatch, `${prefix}/${name}`);
                    for (const field of ['code', 'title', 'address']) {
                        const marker = scenario.calls[0].dispatch[field].slice(-16);
                        const result = await scrollMarkerIntoView(ui, marker, '#hudContent');
                        assert(result.found && result.visible, `${prefix}/${name}: full ${field} remains scroll-reachable`);
                    }
                    await ui.locator('#hudContent').evaluate(el => { el.scrollTop = 0; });
                    await assertLayout(ui, `${prefix}/${name}/expanded`);
                    await screenshot(session, `${prefix}-${name}-expanded`);
                } else if (name === 'many_units') {
                    assert.equal(await ui.locator('#callUnits .unit').count(), 48);
                    const chips = await ui.locator('#callUnits .unit').evaluateAll(els => els.map(el => ({
                        text: el.textContent, title: el.title, overflow: getComputedStyle(el).overflowX,
                        ellipsis: getComputedStyle(el).textOverflow, scrollWidth: el.scrollWidth, clientWidth: el.clientWidth
                    })));
                    assert(chips.some(chip => chip.scrollWidth > chip.clientWidth), `${prefix}: long unit labels actually overflow`);
                    for (const chip of chips) {
                        assert.equal(chip.title, chip.text);
                        assert.equal(chip.overflow, 'hidden');
                        assert.equal(chip.ellipsis, 'ellipsis');
                    }
                    const scroll = await ui.locator('#callUnits').evaluate(el => {
                        el.scrollTop = el.scrollHeight;
                        const last = el.lastElementChild.getBoundingClientRect(), box = el.getBoundingClientRect();
                        return { hasOverflow: el.scrollHeight > el.clientHeight, visibleLast: last.bottom <= box.bottom + 1 && last.top >= box.top - 1 };
                    });
                    assert(scroll.hasOverflow && scroll.visibleLast, `${prefix}: last unit remains scroll-reachable`);
                    await ui.locator('#callUnits').evaluate(el => { el.scrollTop = 0; });
                } else if (name === 'no_units') {
                    assert.match(await ui.locator('#nounits').textContent(), /No units/i);
                } else if (name === 'attached') {
                    assert.equal(await ui.locator('#btnAttach').textContent(), 'Detach');
                } else if (name === 'long_details') {
                    await assertExpandedText(ui, scenario.calls[0].dispatch, `${prefix}/${name}`);
                    for (const [marker, suffix] of [['DESCRIPTION-END-MARKER', 'description-end'], ['OLDEST-VISIBLE-NOTE-END-MARKER', 'bottom']]) {
                        const result = await scrollMarkerIntoView(ui, marker, '#hudDetails');
                        assert(result.found && result.visible, `${prefix}: ${marker} remains scroll-reachable`);
                        assert(result.scrollHeight > result.clientHeight && ['auto', 'scroll'].includes(result.overflow), `${prefix}: long details scroll`);
                        await screenshot(session, `${prefix}-long_details-${suffix}`);
                    }
                    assert.match(await ui.locator('#callNotes').textContent(), /LATEST-NOTE-MARKER/);
                    await ui.locator('#hudDetails').evaluate(el => { el.scrollTop = 0; });
                } else if (name === 'attachments') {
                    const notes = await ui.locator('#callNotes').textContent();
                    assert(!notes.includes('HIDDEN-OLD-NOTE-MARKER'), `${prefix}: hidden notes come from the oldest end`);
                    assert(notes.includes('LATEST-LITERAL-NOTE-MARKER') && notes.includes('Legacy note: ' + literal));
                    assert(notes.includes('(image attachment.)'));
                    assert(notes.indexOf('LATEST-LITERAL-NOTE-MARKER') < notes.indexOf('Legacy note:'), `${prefix}: newest notes render first`);
                    assert.equal(await ui.locator('#hudDiv img, #hudDiv b, #hudDiv [onerror]').count(), 0, `${prefix}: HTML-like CAD text never becomes markup`);
                    assert.equal(await ui.evaluate(() => Boolean(window.__miniInjected)), false);
                    assert.equal(await ui.locator('#callCode').textContent(), scenario.calls[0].dispatch.code);
                    await ui.locator('#hudDetails').evaluate(el => { el.scrollTop = el.scrollHeight; });
                    await screenshot(session, `${prefix}-attachments-bottom`);
                    await ui.locator('#hudDetails').evaluate(el => { el.scrollTop = 0; });
                } else if (name === 'empty') {
                    assert.equal(await ui.locator('#hudDiv').getAttribute('data-empty'), 'true');
                    for (const selector of ['#btnPrevCall', '#btnAttach', '#btnDetail', '#btnNextCall']) assert(await ui.locator(selector).isDisabled());
                    await assertDisabledAttachStyle(ui, `${prefix}/empty`);
                    await assertFooterAtBottom(ui, `${prefix}/empty`);
                }
                if (!['long_header', 'unbroken'].includes(name)) await screenshot(session, `${prefix}-${name}`);
            }
            // A user-defined height must still leave footer controls accessible and details scrollable.
            await setScenario(session, scenarios.long_details, width, 560);
            await assertLayout(ui, `${prefix}/custom-height`);
            await screenshot(session, `${prefix}-custom-height`);
            await send({ type: 'command', key: 'detail' });
            await assertFooterAtBottom(ui, `${prefix}/custom-height-collapsed`);
            await screenshot(session, `${prefix}-custom-height-collapsed`);
            await session.sync([]);
            await assertDisabledAttachStyle(ui, `${prefix}/custom-height-empty`);
            await assertFooterAtBottom(ui, `${prefix}/custom-height-empty`);
            await screenshot(session, `${prefix}-custom-height-empty`);
            assert.deepEqual(session.errors, [], `${prefix}: no browser exceptions`);
            console.log(`PASS scenarios, clipping, literal text, scroll reachability and numeric resize at ${prefix}`);
            await session.page.close();
        }
    }
}

async function checkControls(browser, origin) {
    const session = await loadUi(browser, origin, { width: 1920, height: 1080 });
    const { page, ui, send, sync } = session;
    const calls = [makeCall({ callId: 701, title: 'First call' }), makeCall({ callId: 702, title: 'Second call' }), makeCall({ callId: 703, title: 'Third call' })];
    await setScenario(session, { calls }, 360, 0);
    await ui.locator('#btnNextCall').click();
    assert.equal(await ui.locator('#callTitle').textContent(), 'Second call');
    await send({ type: 'command', key: 'prev' });
    assert.equal(await ui.locator('#callTitle').textContent(), 'First call');
    await send({ type: 'command', key: 'next' });
    assert.equal(await ui.locator('#callTitle').textContent(), 'Second call');
    await ui.locator('#btnPrevCall').click();
    assert.equal(await ui.locator('#callTitle').textContent(), 'First call');
    await send({ type: 'command', key: 'next' });
    await send({ type: 'command', key: 'next' });
    await sync([calls[0]]);
    assert.equal(await ui.locator('#hudHeaderCalls').textContent(), '1/1');
    assert.equal(await ui.locator('#callTitle').textContent(), 'First call');
    assert(await ui.locator('#btnNextCall').isDisabled());
    assert(await ui.locator('#btnPrevCall').isDisabled());

    await page.evaluate(() => { callbacks.length = 0; });
    await ui.locator('#btnAttach').click();
    await page.waitForFunction(() => callbacks.some(item => item.name === 'AttachToCall'));
    assert.equal(await page.evaluate(() => callbacks.find(item => item.name === 'AttachToCall').payload.callId), 701);
    await sync([makeCall({ callId: 701, title: 'First call', idents: [defaultIdent] })]);
    assert.equal(await ui.locator('#btnAttach').textContent(), 'Detach');
    await send({ type: 'command', key: 'attach' });
    await page.waitForFunction(() => callbacks.some(item => item.name === 'DetachFromCall'));
    assert.equal(await page.evaluate(() => callbacks.find(item => item.name === 'DetachFromCall').payload.callId), 701);
    await ui.locator('#btnDetail').click();
    assert.equal(await ui.locator('#btnDetail').getAttribute('aria-pressed'), 'true');
    assert(await ui.locator('#hudDiv').evaluate(el => el.classList.contains('details-open')));
    await send({ type: 'command', key: 'detail' });
    assert.equal(await ui.locator('#btnDetail').getAttribute('aria-pressed'), 'false');

    await ui.locator('#hudHeaderControls .control').first().click();
    await page.waitForFunction(() => callbacks.some(item => item.name === 'ShowHelp'));
    const helpCount = await page.evaluate(() => callbacks.filter(item => item.name === 'ShowHelp').length);
    await ui.locator('#hudHeaderControls .control').first().focus();
    await page.keyboard.press('Enter');
    await page.waitForFunction(count => callbacks.filter(item => item.name === 'ShowHelp').length === count + 1, helpCount);
    const beforeDrag = await ui.locator('#hudDiv').boundingBox();
    const brand = await ui.locator('#hudHeaderTime').boundingBox();
    await page.mouse.move(brand.x + 20, brand.y + brand.height / 2);
    await page.mouse.down();
    await page.mouse.move(brand.x - 35, brand.y + 45, { steps: 6 });
    await page.mouse.up();
    const afterDrag = await ui.locator('#hudDiv').boundingBox();
    assert(Math.abs(afterDrag.x - beforeDrag.x) > 10 && afterDrag.y > beforeDrag.y + 10, 'header still drags the Mini CAD');
    await assertLayout(ui, 'after header drag');
    await ui.locator('#hudHeaderControls .control').last().click();
    await ui.waitForFunction(() => document.querySelector('#hudDiv').style.opacity === '0');
    await page.waitForFunction(() => callbacks.some(item => item.name === 'VisibleEvent' && item.payload.module === 'hud' && item.payload.state === false));

    await sync([]);
    await send({ type: 'display', module: 'hud', enabled: true });
    const callbackCount = await page.evaluate(() => callbacks.length);
    for (const key of ['prev', 'next', 'attach', 'detail']) await send({ type: 'command', key });
    assert.equal(await page.evaluate(() => callbacks.length), callbackCount, 'empty-call NUI commands remain no-ops');
    assert(await ui.locator('#btnAttach').isDisabled());

    await sync([makeCall({ code: null, title: null, postal: null, address: null, description: null, notes: null, units: null })]);
    for (const selector of ['#callCode', '#callTitle', '#callLocation', '#callDescription', '#callNotes']) {
        assert.equal(await ui.locator(selector).textContent(), '', `missing optional ${selector} remains empty text`);
    }
    assert.match(await ui.locator('#nounits').textContent(), /No units/i);
    await assertLayout(ui, 'missing optional call fields');
    await screenshot(session, '1920x1080-w360-missing-optional-fields');

    await send({ type: 'display', module: 'cad', enabled: true });
    assert.equal(await ui.locator('#displayExit').textContent(), 'Close tablet');
    const cad = page.frames().find(frame => frame.url().startsWith(cadOrigin));
    await cad.locator('#cadNotes').fill('Typing inside the separate CAD origin');
    await ui.locator('#displayExit').click();
    await page.waitForFunction(() => callbacks.some(item => item.name === 'NUIFocusOff'));
    await send({ type: 'display', module: 'cad', enabled: false });
    assert.equal(await ui.locator('#displayExit').isVisible(), false);
    await send({ type: 'display_surface', enabled: true });
    assert.equal(await ui.locator('#displayExit').textContent(), 'Exit computer');
    await send({ type: 'display_surface', enabled: false });
    assert.equal(await ui.locator('#displayExit').isVisible(), false);
    assert.deepEqual(session.errors, [], 'controls and focus flow produce no browser exceptions');
    console.log('PASS navigation, NUI parity, Attach/Detach call IDs, empty/shrinking call lists, help, close, native buttons, header drag and iframe-focus close');
    await page.close();
}

async function checkShortHeightAndDrag(browser, origin) {
    for (const viewport of [{ width: 1920, height: 1080 }, { width: 1280, height: 720 }]) {
        const session = await loadUi(browser, origin, viewport);
        const { ui, page, send } = session;
        const scenario = {
            ...scenarios.long_details,
            calls: [makeCall({ ...scenarios.long_details.calls[0].dispatch, units: scenarios.many_units.calls[0].dispatch.units })]
        };
        await setScenario(session, scenario, 320, 1);
        assert((await ui.locator('#hudDiv').boundingBox()).height >= 279, 'a one-pixel configured height preserves expanded controls and a readable scroll area');
        await assertLayout(ui, `${viewport.width}/height1`);
        const marker = await scrollMarkerIntoView(ui, 'OLDEST-VISIBLE-NOTE-END-MARKER', '#hudDetails');
        assert(marker.found && marker.visible, 'a one-pixel configured height still allows scrolling to the final note');
        await ui.locator('#hudDetails').evaluate(el => { el.scrollTop = 0; });
        await screenshot(session, `${viewport.width}x${viewport.height}-w320-height1`);

        const brand = await ui.locator('#hudHeaderTime').boundingBox();
        await page.mouse.move(brand.x + 20, brand.y + brand.height / 2);
        await page.mouse.down();
        await page.mouse.move(brand.x + 30, viewport.height - 12, { steps: 10 });
        await page.mouse.up();
        await assertLayout(ui, `${viewport.width}/lower-header-drag`);
        const dragged = await ui.locator('#hudDiv').boundingBox();
        assert(dragged.y + dragged.height <= viewport.height - 11, 'lower-edge dragging keeps the panel inside the viewport');
        await send({ type: 'resize', module: 'hud', newWidth: 320, newHeight: 160 });
        await assertLayout(ui, `${viewport.width}/height160-after-drag`);
        await screenshot(session, `${viewport.width}x${viewport.height}-w320-lower-drag-height160`);
        await page.setViewportSize({ width: 1280, height: 720 });
        await ui.waitForFunction(() => {
            const box = document.querySelector('#hudDiv').getBoundingClientRect();
            return box.right <= innerWidth - 11 && box.bottom <= innerHeight - 11;
        });
        await assertLayout(ui, `${viewport.width}/window-resize`);
        assert.deepEqual(session.errors, []);
        console.log(`PASS very short persisted heights, end-note access, lower-edge dragging and window resize at ${viewport.width}x${viewport.height}`);
        await page.close();
    }
}

async function checkWheelAndKeyboard(browser, origin) {
    // Chromium follows its host platform's document-edge shortcuts.
    const endKey = process.platform === 'darwin' ? 'Meta+ArrowDown' : 'Control+End';
    for (const viewport of [{ width: 1920, height: 1080 }, { width: 1280, height: 720 }]) {
        const session = await loadUi(browser, origin, viewport);
        const { ui, page } = session;
        const scenario = {
            ...scenarios.long_details,
            calls: [makeCall({ ...scenarios.long_details.calls[0].dispatch, units: scenarios.many_units.calls[0].dispatch.units })]
        };
        await setScenario(session, scenario, 320, 560);
        assert.equal(await ui.locator('#hudContent').getAttribute('tabindex'), '0', 'scrollable call summary accepts keyboard focus');
        for (const selector of ['#callUnits', '#hudDetails']) {
            await ui.locator(selector).scrollIntoViewIfNeeded();
            await ui.locator(selector).evaluate(el => { el.scrollTop = 0; });
            await ui.locator(selector).hover();
            const before = await ui.locator('#hudDiv').boundingBox();
            await page.mouse.wheel(0, 260);
            await ui.waitForFunction(selector => document.querySelector(selector).scrollTop > 0, selector);
            const after = await ui.locator('#hudDiv').boundingBox();
            assert(Math.abs(after.x - before.x) < 1 && Math.abs(after.y - before.y) < 1, `${selector}: real wheel scroll does not drag the panel`);
            await ui.locator(selector).focus();
            await ui.locator(selector).evaluate(el => { el.scrollTop = 0; });
            await page.keyboard.press(endKey);
            await ui.waitForFunction(selector => {
                const el = document.querySelector(selector);
                return el.scrollHeight - el.clientHeight - el.scrollTop <= 2;
            }, selector);
            await ui.locator(selector).hover();
            await page.mouse.wheel(0, -100000);
            await ui.waitForFunction(selector => document.querySelector(selector).scrollTop <= 2, selector);
        }
        await ui.locator('#hudContent').focus();
        await ui.locator('#hudContent').evaluate(el => { el.scrollTop = 0; });
        await page.keyboard.press(endKey);
        await ui.waitForFunction(() => {
            const el = document.querySelector('#hudContent');
            return el.scrollHeight - el.clientHeight - el.scrollTop <= 2;
        });
        const details = await ui.locator('#hudDetails').boundingBox();
        const before = await ui.locator('#hudDiv').boundingBox();
        await page.mouse.move(details.x + 40, details.y + 35);
        await page.mouse.down();
        await page.mouse.move(details.x + 65, details.y + 50, { steps: 4 });
        await page.mouse.up();
        const after = await ui.locator('#hudDiv').boundingBox();
        assert(Math.abs(after.x - before.x) < 1 && Math.abs(after.y - before.y) < 1, 'clicking or selecting detail text never drags the panel');
        assert.equal(await ui.locator('#hudDiv.dragging').count(), 0, 'body interactions leave no drag overlay active');
        await assertLayout(ui, `${viewport.width}/wheel-keyboard-body`);
        assert.deepEqual(session.errors, []);
        console.log(`PASS real mouse wheel in both directions, focused native document-end scrolling and body text selection without dragging at ${viewport.width}x${viewport.height}`);
        await page.close();
    }
}

(async () => {
    cadOrigin = await listen(cadServer);
    const origin = await listen(resourceServer);
    const launch = { headless: true };
    if (process.env.PLAYWRIGHT_EXECUTABLE) launch.executablePath = process.env.PLAYWRIGHT_EXECUTABLE;
    const browser = await chromium.launch(launch);
    try {
        const checks = new Set((process.env.TABLET_BROWSER_CHECKS || 'scenarios,controls,short-height,scroll').split(','));
        if (checks.has('scenarios')) await checkScenarios(browser, origin);
        if (checks.has('controls')) await checkControls(browser, origin);
        if (checks.has('short-height')) await checkShortHeightAndDrag(browser, origin);
        if (checks.has('scroll')) await checkWheelAndKeyboard(browser, origin);
    } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
    resourceServer.close(); cadServer.close();
});
