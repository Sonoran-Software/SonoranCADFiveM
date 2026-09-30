(() => {
    const style = document.createElement('style');
    style.textContent = `
        #placementEditor {position:fixed;inset:0;z-index:1600;color:#edf2fa;font:14px 'Segoe UI',sans-serif;user-select:none;touch-action:none}
        #placementEditor[hidden] {display:none}
        #placementEditor svg {position:absolute;inset:0;width:100%;height:100%;overflow:hidden}
        #placementEditor [data-handle] {cursor:grab}
        #placementToolbar {position:absolute;top:18px;left:18px;width:max-content;max-width:calc(100vw - 36px);padding:10px 12px;border:1px solid #ffffff24;border-radius:7px;background:rgba(12,17,23,.78);box-shadow:0 3px 14px #0004}
        #placementToolbar h3 {margin:0 0 8px;font-size:12px;font-weight:500;color:#cbd5e1}
        #placementToolbar .row {display:flex;gap:5px;flex-wrap:wrap;align-items:center}
        #placementEditor button {padding:6px 9px;border:1px solid #ffffff30;border-radius:4px;background:#1e293bcc;color:#edf2fa;cursor:pointer;font:12px 'Segoe UI',sans-serif}
        #placementToolbar button:hover {background:#3b4f69}
        #placementToolbar button[aria-pressed=true] {border-color:#66c9ff;background:#175078}
        #placementToolbar button[data-finish] {background:#176447;border-color:#37966f}
        #placementToolbar p {margin:9px 0 0;color:#abb9ce;font-size:12px}
        #placementValues {font-variant-numeric:tabular-nums}
        #placementFinish {position:absolute;right:18px;bottom:18px;display:flex;flex-wrap:wrap;gap:6px;justify-content:flex-end;max-width:calc(100vw - 36px)}
        #placementActions {display:contents}
        #placementFinish [data-finish] {background:#176447dd;border-color:#37966f}
        #placementFinish [data-action=cancel] {background:#1e293bdd}
    `;
    document.head.appendChild(style);
    const root = document.createElement('section');
    root.id = 'placementEditor';
    root.hidden = true;
    root.innerHTML = `<svg aria-label="Object transform handles"></svg><div id="placementToolbar">
        <h3></h3><div class="row">
        <button data-mode="move" aria-pressed="true">Move</button><button data-mode="rotate" aria-pressed="false">Rotate</button>
        <button data-action="space">Local axes</button><button data-action="snap" aria-pressed="false">Snap: off</button>
        <button data-action="view">Original view</button><button data-action="focus">Frame object</button><button data-action="reset">Reset</button>
        </div><p>Drag arrows, squares, or rings · Right-drag orbit · Middle-drag pan · Wheel zoom</p>
        <p id="placementValues"></p></div><div id="placementFinish"><span id="placementActions"></span><button data-action="cancel">Cancel</button></div>`;
    document.body.appendChild(root);
    const svg = root.querySelector('svg');
    const colors = {x:'#ff3030',y:'#32ed32',z:'#3f6bff',v:'#d8dde7'};
    const gameOrigin = window.location.ancestorOrigins[0];
    let session = null, pointer = null, pending = null, scheduled = false, sending = false, hovered = null;
    let lastFrame = null;
    const outbound = [];
    async function pump() {
        if (sending) return;
        sending = true;
        while (outbound.length) {
            const data = outbound.shift();
            try {
                await fetch(`https://${GetParentResourceName()}/placementInput`, {
                    method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)
                });
            } catch (_) { /* Resource stops can interrupt an outstanding callback. */ }
        }
        sending = false;
    }
    function send(action, extra = {}) {
        const data = {session,action,...extra};
        if (data.session === null) return;
        const last = outbound[outbound.length-1];
        if (last && last.session===data.session && last.action===action && last.pan===data.pan && (action==='drag' || action==='camera')) {
            if (action==='camera') {data.dx+=last.dx; data.dy+=last.dy; data.zoom+=last.zoom;}
            outbound[outbound.length-1]=data;
        } else outbound.push(data);
        pump();
    }
    function flush() {
        scheduled = false;
        if (pending) { const data = pending; pending = null; send(data.action,data); }
    }
    function defer(data) {
        // Keep pointer motion bounded while preserving down -> drag -> up order.
        if (pending && (pending.action!==data.action || pending.pan!==data.pan)) flush();
        if (pending && data.action === 'camera' && pending.action === 'camera' && pending.pan===data.pan) {
            data.dx += pending.dx; data.dy += pending.dy; data.zoom += pending.zoom;
        }
        pending = data;
        if (!scheduled) { scheduled = true; requestAnimationFrame(flush); }
    }
    function coordinates(event) {return {x:event.clientX/innerWidth,y:event.clientY/innerHeight};}
    function node(name, attrs) {
        const el = document.createElementNS('http://www.w3.org/2000/svg',name);
        for (const [key,value] of Object.entries(attrs)) el.setAttribute(key,String(value));
        return el;
    }
    function render(data) {
        lastFrame=data;
        svg.setAttribute('viewBox',`0 0 ${innerWidth} ${innerHeight}`);
        const fragment = document.createDocumentFragment();
        for (const handle of data.handles || []) {
            const points = handle.points.map(p => p && Number.isFinite(p.x) && Number.isFinite(p.y)
                ? {x:p.x*innerWidth,y:p.y*innerHeight} : null);
            const selected=data.selected || hovered;
            const color = handle.id===selected ? '#fff000' : colors[handle.id[0]];
            if (handle.kind==='axis' && handle.id===selected && points[0] && points[1]) {
                const [a,b]=points, length=Math.hypot(b.x-a.x,b.y-a.y);
                if (length>1) {
                    const scale=Math.hypot(innerWidth,innerHeight)/length;
                    fragment.appendChild(node('line',{x1:a.x-(b.x-a.x)*scale,y1:a.y-(b.y-a.y)*scale,
                        x2:b.x+(b.x-a.x)*scale,y2:b.y+(b.y-a.y)*scale,stroke:'#d5d9df',
                        'stroke-opacity':.45,'stroke-width':1,'pointer-events':'none'}));
                }
            }
            if (handle.kind === 'plane') {
                if (points.some(p => !p)) continue;
                fragment.appendChild(node('polygon',{points:points.map(p=>`${p.x},${p.y}`).join(' '),
                    fill:color,'fill-opacity':'.65',stroke:color,'stroke-width':1,'data-handle':handle.id}));
                continue;
            }
            let path = '', previous = false;
            for (const p of points) {
                if (!p) {previous = false; continue;}
                path += `${previous?'L':'M'}${p.x},${p.y} `; previous = true;
            }
            fragment.appendChild(node('path',{d:path,fill:'none',stroke:color,'stroke-width':handle.kind==='ring'?1.6:2,'pointer-events':'none'}));
            fragment.appendChild(node('path',{d:path,fill:'none',stroke:color,'stroke-opacity':0,
                'stroke-width':12,'pointer-events':'stroke','data-handle':handle.id}));
            if (handle.kind === 'axis' && points[0] && points[1]) {
                for (const [a,b] of [points,[points[1],points[0]]]) {
                    const angle = Math.atan2(b.y-a.y,b.x-a.x);
                    const wing = sign => `${b.x-10*Math.cos(angle)+sign*5*Math.sin(angle)},${b.y-10*Math.sin(angle)-sign*5*Math.cos(angle)}`;
                    fragment.appendChild(node('polygon',{points:`${b.x},${b.y} ${wing(1)} ${wing(-1)}`,fill:color,'data-handle':handle.id}));
                }
            }
        }
        if (data.pivot) fragment.appendChild(node('circle',{cx:data.pivot.x*innerWidth,cy:data.pivot.y*innerHeight,r:3,fill:'#fff000','pointer-events':'none'}));
        svg.replaceChildren(fragment);
        for (const button of root.querySelectorAll('[data-mode]')) button.setAttribute('aria-pressed',button.dataset.mode===data.mode);
        root.querySelector('[data-action=space]').textContent=data.space==='local'?'Local axes':'World axes';
        const snap=root.querySelector('[data-action=snap]');
        snap.setAttribute('aria-pressed',data.snap); snap.textContent=data.snap?'Snap: 1 cm / 5°':'Snap: off';
        const format=v=>['x','y','z'].map(k=>Number(v[k]).toFixed(3)).join(' / ');
        root.querySelector('#placementValues').textContent=`Position ${format(data.position)}   Rotation ${format(data.rotation)}`;
    }
    window.addEventListener('message',event=>{
        if (!gameOrigin || event.source!==window.parent || event.origin!==gameOrigin || !event.data) return;
        const data=event.data;
        if (data.type==='placement_editor') {
            if (!data.enabled && data.session!==session) return;
            if (pointer && root.hasPointerCapture(pointer.id)) {
                const id=pointer.id; pointer=null; root.releasePointerCapture(id);
            }
            session=data.enabled?data.session:null; root.hidden=!data.enabled; pointer=null; pending=null; hovered=null; lastFrame=null;
            svg.replaceChildren();
            if (data.enabled) {
                root.querySelector('h3').textContent=data.title;
                root.querySelector('[data-action=view]').textContent=data.title.startsWith('Vehicle')?'Driver view':'Original view';
                const actions=root.querySelector('#placementActions'); actions.replaceChildren();
                for (const action of data.actions || []) {
                    const button=document.createElement('button'); button.dataset.finish=action.id;
                    button.textContent=action.label; actions.appendChild(button);
                }
            }
        } else if (data.type==='placement_frame' && session!==null && data.session===session) render(data);
    });
    root.addEventListener('contextmenu',event=>event.preventDefault());
    root.addEventListener('click',event=>{
        const button=event.target.closest('button'); if (!button) return;
        flush();
        if (button.dataset.mode) send('mode',{value:button.dataset.mode});
        else if (button.dataset.finish) send('finish',{choice:button.dataset.finish});
        else send(button.dataset.action);
    });
    root.addEventListener('pointerdown',event=>{
        const handle=event.target.closest('[data-handle]');
        if (event.target.closest('#placementToolbar, #placementFinish')) return;
        if (event.button!==2 && event.button!==1 && !(event.button===0 && handle)) return;
        event.preventDefault(); root.setPointerCapture(event.pointerId);
        pointer={id:event.pointerId,camera:event.button!==0,pan:event.button===1,x:event.clientX,y:event.clientY};
        if (!pointer.camera) {hovered=handle.dataset.handle;send('down',{...coordinates(event),handle:handle.dataset.handle});}
    });
    root.addEventListener('pointermove',event=>{
        if (!pointer) {
            const next=event.target.closest('[data-handle]')?.dataset.handle || null;
            if (next!==hovered) {hovered=next;if(lastFrame) render(lastFrame);}
            return;
        }
        if (event.pointerId!==pointer.id) return;
        if (pointer.camera) defer({action:'camera',pan:pointer.pan,dx:(event.clientX-pointer.x)/innerWidth,dy:(event.clientY-pointer.y)/innerHeight,zoom:0});
        else defer({action:'drag',...coordinates(event)});
        pointer.x=event.clientX; pointer.y=event.clientY;
    });
    function release(event) {
        if (!pointer || pointer.id!==event.pointerId) return;
        flush(); send('up'); pointer=null;
        if (root.hasPointerCapture(event.pointerId)) root.releasePointerCapture(event.pointerId);
    }
    root.addEventListener('pointerup',release); root.addEventListener('pointercancel',release);
    root.addEventListener('lostpointercapture',release);
    root.addEventListener('wheel',event=>{
        event.preventDefault(); if (pointer) return;
        defer({action:'camera',dx:0,dy:0,zoom:Math.sign(event.deltaY)});
    },{passive:false});
})();
