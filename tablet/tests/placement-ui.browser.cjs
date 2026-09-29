// Optional browser check: PLAYWRIGHT_MODULE may point to an installed Playwright package.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { createServer } = require('node:http');
const assert = require('node:assert/strict');
const script = readFileSync(resolve('sonorancad/core/client_nui/js/placement.js'),'utf8');
const frame = { type:'placement_frame',session:1,mode:'move',space:'local',snap:false,
    position:{x:1,y:2,z:3},rotation:{x:0,y:0,z:0},handles:[
        {id:'x',kind:'axis',points:[{x:.5,y:.4},{x:.75,y:.4}]},
        {id:'y',kind:'axis',points:[{x:.5,y:.4},{x:.65,y:.22}]},
        {id:'z',kind:'axis',points:[{x:.5,y:.4},{x:.5,y:.12}]},
        {id:'xy',kind:'plane',points:[{x:.54,y:.37},{x:.59,y:.37},{x:.62,y:.32},{x:.57,y:.32}]}
    ]};
const server=createServer((req,res)=>{
    res.setHeader('Content-Type',(req.url==='/placement.js'?'text/javascript':'text/html')+'; charset=utf-8');
    if(req.url==='/placement.js') return res.end(script);
    if(req.url==='/ui') return res.end(`<html><head></head><body><script>
        window.events=[];window.GetParentResourceName=()=> 'placement-test';
        window.fetch=async(url,init)=>{events.push(JSON.parse(init.body));await new Promise(r=>setTimeout(r,5));return {ok:true};};
        </script><script src="/placement.js"></script></body></html>`);
    res.end('<body style="margin:0;background:repeating-linear-gradient(0deg,#142333 0,#142333 49px,#263747 50px)"><iframe id="ui" src="/ui" style="width:100vw;height:100vh;border:0"></iframe></body>');
});
(async()=>{
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    const browser=await chromium.launch({channel:process.env.PLAYWRIGHT_CHANNEL || 'msedge',headless:true});
    try {
        for(const [width,height] of [[1920,1080],[1280,720]]) {
            const page=await browser.newPage({viewport:{width,height}});
            const errors=[];page.on('pageerror',error=>errors.push(error.message));
            await page.goto(`http://127.0.0.1:${server.address().port}`);
            const ui=page.frames().find(f=>f.url().endsWith('/ui'));
            await ui.waitForSelector('#placementEditor',{state:'attached'});
            const send=data=>page.evaluate(data=>document.querySelector('iframe').contentWindow.postMessage(data,location.origin),data);
            await send({type:'placement_editor',enabled:true,session:1,title:'Mouse placement test',actions:[{id:'apply',label:'Apply'}]});
            await send(frame);
            await ui.waitForSelector('[data-handle=x]',{state:'attached'});
            await page.mouse.move(width*.65,height*.4);await page.mouse.down();
            await page.mouse.move(width*.72,height*.44,{steps:5});await page.mouse.up();
            await ui.waitForFunction(()=>events.some(e=>e.action==='up'));
            const drag=await ui.evaluate(()=>events.filter(e=>['down','drag','up'].includes(e.action)));
            assert.equal(drag[0].action,'down');assert.equal(drag[0].handle,'x');
            assert.equal(drag.at(-1).action,'up');assert(drag.some(e=>e.action==='drag'&&e.x>.7));
            await ui.locator('[data-mode=rotate]').click();
            const ring={id:'z',kind:'ring',points:Array.from({length:49},(_,i)=>({x:.5+.2*Math.cos(i*Math.PI/24),y:.4+.2*Math.sin(i*Math.PI/24)}))};
            await send({...frame,mode:'rotate',handles:[ring]});
            await ui.waitForSelector('[data-handle=z]',{state:'attached'});
            await page.mouse.move(width*.7,height*.4);await page.mouse.down();
            await page.mouse.move(width*.5,height*.6,{steps:5});await page.mouse.up();
            await ui.waitForFunction(()=>events.some(e=>e.action==='down'&&e.handle==='z'));
            await ui.locator('[data-action=space]').click();await ui.locator('[data-action=snap]').click();
            await ui.locator('[data-action=focus]').click();await ui.locator('[data-action=reset]').click();
            await page.mouse.move(width*.3,height*.25);await page.mouse.down({button:'right'});
            await page.mouse.move(width*.35,height*.28,{steps:5});await page.mouse.up({button:'right'});
            await page.mouse.wheel(0,100);
            await ui.waitForFunction(()=>events.some(e=>e.action==='camera'&&e.zoom>0));
            await ui.evaluate(()=>{
                const child=document.createElement('iframe');child.style.display='none';document.body.appendChild(child);
                child.contentWindow.parent.postMessage({type:'placement_editor',session:1,enabled:false},location.origin);
            });
            assert.equal(await ui.locator('#placementEditor').isVisible(),true);
            const toolbar=await ui.locator('#placementToolbar').boundingBox();
            assert(toolbar.x>=0 && toolbar.x+toolbar.width<=width && toolbar.y+toolbar.height<=height);
            await send(frame);
            if(process.env.PLACEMENT_SCREENSHOT && width===1920) await page.screenshot({path:process.env.PLACEMENT_SCREENSHOT});
            await ui.locator('[data-finish=apply]').click();
            await ui.waitForFunction(()=>events.some(e=>e.action==='finish'));
            const events=await ui.evaluate(()=>window.events);
            for(const action of ['mode','space','snap','focus','reset','camera','finish']) assert(events.some(e=>e.action===action));
            await send({type:'placement_editor',enabled:false,session:1});
            await ui.waitForSelector('#placementEditor',{state:'hidden'});
            await send({type:'placement_editor',enabled:true,session:2,title:'Second session',actions:[]});
            await send({type:'placement_editor',enabled:false,session:1});
            await ui.locator('[data-action=cancel]').click();
            await ui.waitForFunction(()=>events.some(e=>e.action==='cancel'&&e.session===2));
            assert.deepEqual(errors,[]);
            console.log(`PASS mouse drag, toolbar, orbit, zoom, apply, origin/source checks and layout at ${width}x${height}`);
            await page.close();
        }
    } finally {await browser.close();server.close();}
})().catch(error=>{console.error(error);server.close();process.exitCode=1;});
