// Optional browser check: PLAYWRIGHT_MODULE may point to an installed Playwright package.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { createServer } = require('node:http');
const assert = require('node:assert/strict');
const script = readFileSync(resolve('sonorancad/core/client_nui/js/placement.js'),'utf8');
const frame = { type:'placement_frame',session:1,mode:'move',space:'local',snap:false,
    position:{x:1,y:2,z:3},rotation:{x:0,y:0,z:0},pivot:{x:.5,y:.5},handles:[
        {id:'x',kind:'axis',points:[{x:.45,y:.5},{x:.55,y:.5}]},
        {id:'y',kind:'axis',points:[{x:.47,y:.54},{x:.53,y:.46}]},
        {id:'z',kind:'axis',points:[{x:.5,y:.59},{x:.5,y:.41}]},
        {id:'xy',kind:'plane',points:[{x:.51,y:.48},{x:.52,y:.48},{x:.525,y:.465},{x:.515,y:.465}]}
    ]};
const server=createServer((req,res)=>{
    res.setHeader('Content-Type',(req.url==='/placement.js'?'text/javascript':'text/html')+'; charset=utf-8');
    if(req.url==='/placement.js') return res.end(script);
    if(req.url==='/ui') return res.end(`<html><head></head><body><script>
        window.events=[];window.GetParentResourceName=()=> 'placement-test';
        window.fetch=async(url,init)=>{events.push(JSON.parse(init.body));await new Promise(r=>setTimeout(r,25));return {ok:true};};
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
            await send({type:'placement_editor',enabled:true,session:1,title:'Vehicle display placement',cameraMode:'cockpit',ready:false,actions:[{id:'apply',label:'Apply to this vehicle'}]});
            await ui.waitForFunction(()=>document.querySelector('[data-finish=apply]')?.disabled);
            assert.equal(await ui.locator('[data-action=cancel]').isEnabled(),true);
            assert.match(await ui.locator('#placementValues').textContent(),/Preparing/);
            await send(frame);
            await ui.waitForSelector('[data-handle=x]',{state:'attached'});
            assert.equal(await ui.locator('[data-action=focus]').textContent(),'Look at display');
            assert.equal(await ui.locator('[data-action=view]').textContent(),'Cabin view');
            assert.match(await ui.locator('#placementHelp').textContent(),/Right-drag look/);
            assert.match(await ui.locator('#placementHelp').textContent(),/Middle-drag lean/);
            assert.match(await ui.locator('#placementHelp').textContent(),/Wheel zoom/);
            const orbitToggle=ui.locator('[data-action=orbit]');
            assert.equal(await orbitToggle.isVisible(),true);
            assert.equal(await orbitToggle.textContent(),'Orbit laptop');
            assert.equal(await orbitToggle.getAttribute('aria-pressed'),'false');
            await orbitToggle.click();
            await ui.waitForFunction(()=>events.some(e=>e.session===1&&e.action==='orbit'));
            // Camera state belongs to the game: clicking alone cannot change the mode.
            assert.equal(await orbitToggle.getAttribute('aria-pressed'),'false');
            assert.match(await ui.locator('#placementHelp').textContent(),/Right-drag look/);
            await send({...frame,cameraOrbit:true});
            await ui.waitForFunction(()=>document.querySelector('[data-action=orbit]').getAttribute('aria-pressed')==='true');
            assert.match(await ui.locator('#placementHelp').textContent(),/Right-drag orbit laptop · Middle-drag lean · Wheel zoom/);
            await orbitToggle.click();
            await ui.waitForFunction(()=>events.filter(e=>e.session===1&&e.action==='orbit').length===2);
            assert.equal(await orbitToggle.getAttribute('aria-pressed'),'true');
            await send({...frame,cameraOrbit:false});
            await ui.waitForFunction(()=>document.querySelector('[data-action=orbit]').getAttribute('aria-pressed')==='false');
            assert.match(await ui.locator('#placementHelp').textContent(),/Right-drag look/);
            assert.equal(await ui.locator('polygon[data-handle=x]').count(),2);
            await page.mouse.move(width*.54,height*.5);await page.mouse.down();
            // Game frames replace handles while the pointer stays captured by the root.
            await send({...frame,selected:'x'});
            await page.mouse.move(width*.49,height*.5,{steps:5});await page.mouse.up();
            await ui.waitForFunction(()=>events.some(e=>e.action==='up'));
            const drag=await ui.evaluate(()=>events.filter(e=>['down','drag','up'].includes(e.action)));
            assert.equal(drag[0].action,'down');assert.equal(drag[0].handle,'x');
            assert.equal(drag.at(-1).action,'up');assert(drag.some(e=>e.action==='drag'&&e.x<.5));
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
            await ui.waitForFunction(()=>events.filter(e=>e.action==='up').length>=3);
            const cameraCount=await ui.evaluate(()=>events.filter(e=>e.action==='camera').length);
            await page.mouse.wheel(0,100);
            await ui.waitForFunction(()=>events.some(e=>e.session===1&&e.action==='camera'&&e.zoom>0));
            await page.mouse.move(width*.3,height*.3);await page.mouse.down({button:'middle'});
            await page.mouse.move(width*.33,height*.32,{steps:5});await page.mouse.up({button:'middle'});
            await ui.waitForFunction(()=>events.some(e=>e.session===1&&e.action==='camera'&&e.pan===true&&e.dx>0));
            await ui.waitForFunction(()=>events.filter(e=>e.action==='up').length>=4);
            const afterCameraCount=await ui.evaluate(()=>events.filter(e=>e.action==='camera').length);
            assert(afterCameraCount>cameraCount+1);
            await send({...frame,cameraZoom:false});
            await ui.waitForFunction(()=>!document.querySelector('#placementHelp').textContent.includes('Wheel zoom'));
            await page.mouse.wheel(0,100);await page.waitForTimeout(75);
            assert.equal(await ui.evaluate(()=>events.filter(e=>e.action==='camera').length),afterCameraCount);
            await send({...frame,cameraOrbit:true,cameraZoom:false});
            await ui.waitForFunction(()=>document.querySelector('[data-action=orbit]').getAttribute('aria-pressed')==='true');
            await ui.locator('[data-action=view]').click();
            await ui.waitForFunction(()=>events.some(e=>e.session===1&&e.action==='view'));
            assert.equal(await orbitToggle.getAttribute('aria-pressed'),'true');
            await send({...frame,cameraOrbit:false,cameraZoom:true});
            await ui.waitForFunction(()=>document.querySelector('[data-action=orbit]').getAttribute('aria-pressed')==='false');
            assert.match(await ui.locator('#placementHelp').textContent(),/Right-drag look · Middle-drag lean · Wheel zoom/);
            await ui.evaluate(()=>{
                const child=document.createElement('iframe');child.style.display='none';document.body.appendChild(child);
                child.contentWindow.parent.postMessage({type:'placement_editor',session:1,enabled:false},location.origin);
            });
            assert.equal(await ui.locator('#placementEditor').isVisible(),true);
            const toolbar=await ui.locator('#placementToolbar').boundingBox();
            assert(toolbar.x>=0 && toolbar.x+toolbar.width<=width && toolbar.y+toolbar.height<=height);
            const finish=await ui.locator('#placementFinish').boundingBox();
            assert(finish.x>=0 && finish.x+finish.width<=width && finish.y+finish.height<=height);
            await send(frame);
            if(process.env.PLACEMENT_SCREENSHOT && width===1920) await page.screenshot({path:process.env.PLACEMENT_SCREENSHOT});
            await ui.locator('[data-finish=apply]').click();
            await ui.waitForFunction(()=>events.some(e=>e.action==='finish'));
            const events=await ui.evaluate(()=>window.events);
            for(const action of ['mode','space','snap','focus','reset','camera','orbit','view','finish']) assert(events.some(e=>e.action===action));
            await send({type:'placement_editor',enabled:false,session:1});
            await ui.waitForSelector('#placementEditor',{state:'hidden'});
            await send({type:'placement_editor',enabled:true,session:2,title:'Second session',actions:[]});
            await send({type:'placement_editor',enabled:false,session:1});
            await ui.waitForFunction(()=>document.querySelector('[data-action=view]').textContent==='Original view');
            assert.equal(await ui.locator('[data-action=focus]').textContent(),'Frame object');
            assert.equal(await orbitToggle.isVisible(),false);
            assert.equal(await orbitToggle.evaluate(button=>getComputedStyle(button).display),'none');
            assert.equal(await orbitToggle.getAttribute('aria-pressed'),'false');
            assert.match(await ui.locator('#placementHelp').textContent(),/Right-drag orbit/);
            await page.mouse.move(width*.3,height*.3);await page.mouse.down({button:'middle'});
            await page.mouse.move(width*.33,height*.32,{steps:5});await page.mouse.up({button:'middle'});
            await page.mouse.wheel(0,100);
            await ui.waitForFunction(()=>events.some(e=>e.session===2&&e.action==='camera'&&e.pan===true&&e.dx>0));
            await ui.waitForFunction(()=>events.some(e=>e.session===2&&e.action==='camera'&&e.zoom>0));
            await ui.locator('[data-action=cancel]').click();
            await ui.waitForFunction(()=>events.some(e=>e.action==='cancel'&&e.session===2));
            assert.deepEqual(errors,[]);
            console.log(`PASS mouse drag, toolbar, orbit, zoom, apply, origin/source checks and layout at ${width}x${height}`);
            await page.close();
        }
    } finally {await browser.close();server.close();}
})().catch(error=>{console.error(error);server.close();process.exitCode=1;});
