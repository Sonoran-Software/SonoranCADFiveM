(() => {
    const https = require("https");
    const url = require("url");
    const zlib = require("zlib");

    function byteCount(s) {
        return encodeURI(s).split(/%..|./).length - 1;
    }

    function hasHeader(headers, name) {
        const normalized = name.toLowerCase();
        return Object.keys(headers || {}).some((key) => key.toLowerCase() === normalized);
    }

    function setVersionHeaders(headers) {
        const version = GetResourceMetadata(GetCurrentResourceName(), "version", 0);
        if (!version) {
            return;
        }

        if (!hasHeader(headers, "X-SonoranCAD-Version")) {
            headers["X-SonoranCAD-Version"] = version;
        }
        if (!hasHeader(headers, "X-FiveM-Resource-Version")) {
            headers["X-FiveM-Resource-Version"] = version;
        }
    }

    exports('HandleHttpRequest', (dest, callback, method, data, headers) => {
        emit("SonoranCAD::core:writeLog", "debug", "[http] to: " + dest + " - data: " + dest, JSON.stringify(data));
        const urlObj = url.parse(dest)
        const normalizedMethod = (method || "GET").toUpperCase();
        const requestHeaders = Object.assign({}, headers || {});
        const options = {
            hostname: urlObj.hostname,
            path: urlObj.path || urlObj.pathname,
            method: normalizedMethod,
            headers: requestHeaders
        }
        if (data !== undefined && data !== null && data !== "") {
            if (!options.headers['Content-Type']) {
                options.headers['Content-Type'] = 'application/json'
            }
        }
        setVersionHeaders(options.headers);
        const req = https.request(options, (res) => {
            const chunks = [];
            res.on('data', (d) => {
                chunks.push(Buffer.from(d))
            }),
            res.on('end', () => {
                const body = Buffer.concat(chunks);
                const encoding = String(res.headers["content-encoding"] || "").toLowerCase();
                const finish = (decoded) => callback(res.statusCode, decoded, res.headers);

                if (encoding.includes("gzip")) {
                    zlib.gunzip(body, (error, decoded) => {
                        if (error) {
                            console.debug("HTTP gzip decode failed: " + JSON.stringify(error));
                            finish(body.toString());
                            return;
                        }
                        finish(decoded.toString());
                    });
                    return;
                }

                if (encoding.includes("deflate")) {
                    zlib.inflate(body, (error, decoded) => {
                        if (error) {
                            console.debug("HTTP deflate decode failed: " + JSON.stringify(error));
                            finish(body.toString());
                            return;
                        }
                        finish(decoded.toString());
                    });
                    return;
                }

                finish(body.toString());
            })
          })

        req.on('error', (error) => {
            let ignore_ids = ["EAI_AGAIN", "ETIMEOUT", "ENOTFOUND"]
            if (!ignore_ids.includes(error.code))
                console.debug("HTTP error caught: " + JSON.stringify(error));
            callback(0, JSON.stringify({
                error: "HTTP_REQUEST_FAILED",
                code: error.code || "UNKNOWN",
                message: error.message || "HTTP request failed.",
                host: error.host || urlObj.hostname || null,
                port: error.port || urlObj.port || 443,
                path: error.path || null
            }), {"content-type": "application/json"});
        })
        if (data !== undefined && data !== null && data !== "") {
            req.write(data);
        }
        req.end();
    });
})();
