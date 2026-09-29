(() => {
    const style = document.createElement('style');
    style.textContent = `
        #placementEditor {position:fixed;inset:0;z-index:1600;color:#edf2fa;font:14px 'Segoe UI',sans-serif;user-select:none;touch-action:none}
        #placementEditor[hidden] {display:none}
        #placementEditor svg {position:absolute;inset:0;width:100%;height:100%;overflow:hidden}
        #placementEditor [data-handle] {cursor:grab}
        #placementEditor [data-handle]:hover {stroke:#fff;stroke-opacity:.55}
        #placementToolbar {position:absolute;bottom:30px;left:50%;transform:translateX(-50%);width:max-content;max-width:94vw;padding:14px 18px;border:1px solid #475569;border-radius:12px;background:rgba(15,23,36,.97);box-shadow:0 8px 32px #0008}
        #placementToolbar h3 {margin:0 0 10px;font-size:15px}
        #placementToolbar .row {display:flex;gap:7px;flex-wrap:wrap;align-items:center}
        #placementToolbar button {padding:8px 12px;border:1px solid #526174;border-radius:6px;background:#253246;color:#edf2fa;cursor:pointer;font:inherit}
        #placementToolbar button:hover {background:#3b4f69}
        #placementToolbar button[aria-pressed=true] {border-color:#66c9ff;background:#175078}
        #placementToolbar button[data-finish] {background:#176447;border-color:#37966f}
        #placementToolbar p {margin:9px 0 0;color:#abb9ce;font-size:12px}
        #placementValues {font-variant-numeric:tabular-nums}
    `;
    document.head.appendChild(style);
    const root = document.createElement('section');
    root.id = 'placementEditor';
    root.hidden = true;
    root.innerHTML = `<svg aria-label="Object transform handles"></svg><div id="placementToolbar">
        <h3></h3><div class="row">
        <button data-mode="move" aria-pressed="true">Move</button><button data-mode="rotate" aria-pressed="false">Rotate</button>
        <button data-action="space">Local axes</button><button data-action="snap" aria-pressed="false">Snap: off</button>
        <button data-action="focus">Frame object</button><button data-action="reset">Reset</button><span id="placementActions" class="row"></span><button data-action="cancel">Cancel</button>
        </div><p>Drag a colored axis, plane, or ring. Right-drag to orbit · Wheel to zoom.</p>
        <p id="placementValues"></p></div>`;
    document.body.appendChild(root);
    const svg = root.querySelector('svg');
    const colors = {x:'#ff515a',y:'#64dc78',z:'#569aff'};
    const gameOrigin = window.location.ancestorOrigins[0];
    let session = null, pointer = null, pending = null, scheduled = false, sending = false;
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
        if (last && last.session===data.session && last.action===action && (action==='drag' || action==='camera')) {
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
        if (pending && data.action === 'camera' && pending.action === 'camera') {
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
        svg.setAttribute('viewBox',`0 0 ${innerWidth} ${innerHeight}`);
        const fragment = document.createDocumentFragment();
        for (const handle of data.handles || []) {
            const points = handle.points.map(p => p && Number.isFinite(p.x) && Number.isFinite(p.y)
                ? {x:p.x*innerWidth,y:p.y*innerHeight} : null);
            const color = colors[handle.id[0]];
            if (handle.kind === 'plane') {
                if (points.some(p => !p)) continue;
                fragment.appendChild(node('polygon',{points:points.map(p=>`${p.x},${p.y}`).join(' '),
                    fill:color,'fill-opacity':'.22',stroke:color,'stroke-width':1,'data-handle':handle.id}));
                continue;
            }
            let path = '', previous = false;
            for (const p of points) {
                if (!p) {previous = false; continue;}
                path += `${previous?'L':'M'}${p.x},${p.y} `; previous = true;
            }
            fragment.appendChild(node('path',{d:path,fill:'none',stroke:color,'stroke-width':3,'pointer-events':'none'}));
            fragment.appendChild(node('path',{d:path,fill:'none',stroke:color,'stroke-opacity':0,
                'stroke-width':18,'pointer-events':'stroke','data-handle':handle.id}));
            if (handle.kind === 'axis' && points[0] && points[1]) {
                const [a,b] = points, angle = Math.atan2(b.y-a.y,b.x-a.x);
                const wing = sign => `${b.x-12*Math.cos(angle)+sign*6*Math.sin(angle)},${b.y-12*Math.sin(angle)-sign*6*Math.cos(angle)}`;
                fragment.appendChild(node('polygon',{points:`${b.x},${b.y} ${wing(1)} ${wing(-1)}`,fill:color,'data-handle':handle.id}));
                const label = node('text',{x:b.x+9,y:b.y-9,fill:color,'font-size':14,'font-weight':700,'pointer-events':'none'});
                label.textContent=handle.id.toUpperCase(); fragment.appendChild(label);
            }
        }
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
            session=data.enabled?data.session:null; root.hidden=!data.enabled; pointer=null; pending=null;
            svg.replaceChildren();
            if (data.enabled) {
                root.querySelector('h3').textContent=data.title;
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
        if (event.target.closest('#placementToolbar')) return;
        if (event.button!==2 && !(event.button===0 && handle)) return;
        event.preventDefault(); root.setPointerCapture(event.pointerId);
        pointer={id:event.pointerId,orbit:event.button===2,x:event.clientX,y:event.clientY};
        if (!pointer.orbit) send('down',{...coordinates(event),handle:handle.dataset.handle});
    });
    root.addEventListener('pointermove',event=>{
        if (!pointer || event.pointerId!==pointer.id) return;
        if (pointer.orbit) defer({action:'camera',dx:(event.clientX-pointer.x)/innerWidth,dy:(event.clientY-pointer.y)/innerHeight,zoom:0});
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
