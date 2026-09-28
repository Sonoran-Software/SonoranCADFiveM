(function (root) {
    // Map a unit rectangle onto TL, TR, BR, BL using a projective transform.
    // CSS applies the same inverse transform to pointer hit testing in the iframe.
    function matrixForCorners(points, width, height) {
        if (!Array.isArray(points) || points.length !== 4 || !(width > 0 && height > 0)) return null;
        if (!points.every(p => p && Number.isFinite(p.x) && Number.isFinite(p.y))) return null;
        const [a, b, c, d] = points;
        const dx1 = b.x - c.x, dx2 = d.x - c.x, dx3 = a.x - b.x + c.x - d.x;
        const dy1 = b.y - c.y, dy2 = d.y - c.y, dy3 = a.y - b.y + c.y - d.y;
        const determinant = dx1 * dy2 - dx2 * dy1;
        if (Math.abs(determinant) < 0.000001) return null;
        // Reject folded, reversed, or collapsed quads before exposing an input surface.
        for (let i = 0; i < 4; i++) {
            const p = points[i], q = points[(i + 1) % 4], r = points[(i + 2) % 4];
            if ((q.x - p.x) * (r.y - q.y) - (q.y - p.y) * (r.x - q.x) <= 0) return null;
        }
        const g = (dx3 * dy2 - dx2 * dy3) / determinant;
        const h = (dx1 * dy3 - dx3 * dy1) / determinant;
        return [
            (b.x - a.x + g * b.x) / width, (b.y - a.y + g * b.y) / width, 0, g / width,
            (d.x - a.x + h * d.x) / height, (d.y - a.y + h * d.y) / height, 0, h / height,
            0, 0, 1, 0, a.x, a.y, 0, 1
        ];
    }

    if (typeof module === 'object' && module.exports) module.exports = { matrixForCorners };
    if (!root.document) return;
    const surface = document.getElementById('cadDiv');
    const exit = document.getElementById('displayExit');
    let enabled = false;
    let corners = null;
    let width = 1280, height = 640;
    function render() {
        if (!enabled || !corners) return;
        const pixels = corners.map(p => ({ x: p.x * innerWidth, y: p.y * innerHeight }));
        const matrix = matrixForCorners(pixels, width, height);
        surface.classList.toggle('display-surface-ready', !!matrix);
        if (matrix) surface.style.setProperty('--display-transform', `matrix3d(${matrix.join(',')})`);
    }
    root.addEventListener('message', event => {
        // NUI game messages have no source window; never accept iframe commands here.
        if (event.source !== null || !event.data) return;
        const data = event.data;
        if (data.type === 'display_surface') {
            enabled = data.enabled === true;
            corners = null;
            surface.classList.toggle('display-surface', enabled);
            surface.classList.remove('display-surface-ready');
            surface.style.removeProperty('--display-transform');
            if (enabled) {
                width = Number.isFinite(data.width) && data.width >= 256 && data.width <= 2048 ? data.width : 1280;
                height = Number.isFinite(data.height) && data.height >= 256 && data.height <= 2048 ? data.height : 640;
                surface.style.setProperty('--display-width', `${width}px`);
                surface.style.setProperty('--display-height', `${height}px`);
            } else {
                surface.style.removeProperty('--display-width');
                surface.style.removeProperty('--display-height');
            }
            exit.hidden = !enabled;
        } else if (data.type === 'display_surface_frame' && enabled) {
            if (!Array.isArray(data.corners) || data.corners.length !== 4
                || !data.corners.every(p => p && Number.isFinite(p.x) && Number.isFinite(p.y))) return;
            corners = data.corners;
            render();
        }
    });
    root.addEventListener('resize', render);
    // This stays outside the cross-origin iframe, so closing never relies on it forwarding Escape.
    exit.addEventListener('click', () => nui('NUIFocusOff', {}));
})(typeof window === 'undefined' ? globalThis : window);
