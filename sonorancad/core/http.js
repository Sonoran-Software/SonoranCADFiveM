(() => {
    const https = require("https");
    const url = require("url");
    const zlib = require("zlib");
    const fs = require("fs");
    const path = require("path");
    const crypto = require("crypto");
    const resourcePath = GetResourcePath(GetCurrentResourceName());

    // Fixed internal paths only. Atomic replacement leaves the previous cache intact
    // when a write/rename fails; no fallback truncation of the original is allowed.
    function writeConfigurationFile(name, content) {
        const target = path.join(resourcePath, name);
        const temporary = target + ".tmp";
        let fd;
        try {
            fd = fs.openSync(temporary, "w", 0o600);
            fs.writeFileSync(fd, content, "utf8");
            fs.fsyncSync(fd);
            fs.closeSync(fd);
            fd = undefined;
            fs.renameSync(temporary, target);
            return true;
        } catch (_) {
            if (fd !== undefined) { try { fs.closeSync(fd); } catch (_) {} }
            try { fs.unlinkSync(temporary); } catch (_) {}
            return false;
        }
    }

    exports("WriteCadConfiguration", (kind, content) => writeConfigurationFile(
        kind === "mock" ? ".configuration-mock.json" : ".configuration-cache.json", content));

    exports("GetCadConfigurationScope", (apiKey, serverId, bootstrapUrl, mock) => crypto.createHash("sha256")
        .update([apiKey || "", String(serverId), String(bootstrapUrl).replace(/\/+$/, ""), mock ? "mock" : "cad"].join("\0"))
        .digest("hex"));

    exports("WriteCadBootstrapConfiguration", (apiKey, serverId) => {
        if (typeof apiKey !== "string" || !apiKey || !Number.isInteger(serverId) || serverId < 1) return false;
        try {
            const target = path.join(resourcePath, "config.json");
            if (fs.existsSync(target)) {
                const content = fs.readFileSync(target, "utf8");
                const existing = content.trim() === "" ? {} : JSON.parse(content);
                if (!existing || Array.isArray(existing) || typeof existing !== "object" ||
                    Object.keys(existing).some(key => key !== "apiKey" && key !== "serverId")) return false;
                if (existing.apiKey === apiKey && existing.serverId === serverId) return true;
                // Empty files/objects and unconfigured templates inherit the legacy
                // key AND server ID as a pair; an existing key is never replaced.
                if (existing.apiKey !== undefined && existing.apiKey !== "") return false;
            }
            return writeConfigurationFile("config.json", JSON.stringify({apiKey, serverId}, null, 2) + "\n");
        } catch (_) {
            return false;
        }
    });

    exports("ListLegacyCadConfiguration", (relativeDirectory) => {
        try {
            const directory = path.resolve(resourcePath, relativeDirectory || "configuration");
            const relative = path.relative(resourcePath, directory);
            if (relative.startsWith("..") || path.isAbsolute(relative)) throw new Error("Outside resource");
            return JSON.stringify({ files: fs.readdirSync(directory, { withFileTypes: true })
                .filter((entry) => entry.isFile()).map((entry) => entry.name),
                plugins: fs.readdirSync(path.join(resourcePath, "submodules"), { withFileTypes: true })
                    .filter((entry) => entry.isDirectory()).map((entry) => entry.name) });
        } catch (_) {
            return JSON.stringify({ error: "Cannot read the legacy configuration directory. Check that it exists and is readable." });
        }
    });

    exports("ArchiveLegacyCadConfiguration", () => {
        try {
            const archived = path.join(resourcePath, "configuration_old");
            if (fs.existsSync(archived)) return false;
            fs.renameSync(path.join(resourcePath, "configuration"), archived);
            return true;
        } catch (_) {
            return false;
        }
    });

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

    function sanitizeHeaderValue(value) {
        if (value === undefined || value === null) {
            return "";
        }
        if (Array.isArray(value)) {
            return value
                .filter((entry) => entry !== undefined && entry !== null)
                .map((entry) => String(entry))
                .join(", ");
        }
        return String(value);
    }

    function sanitizeHeaders(headers) {
        const normalized = {};
        for (const [key, value] of Object.entries(headers || {})) {
            normalized[String(key)] = sanitizeHeaderValue(value);
        }
        return normalized;
    }

    function safeCallback(callback, statusCode, body, headers) {
        const safeStatusCode = Number.isInteger(statusCode) ? statusCode : 0;
        const safeBody = body === undefined || body === null ? "" : String(body);
        const safeHeaders = JSON.stringify(sanitizeHeaders(headers));
        callback(safeStatusCode, safeBody, safeHeaders);
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
                const finish = (decoded) => safeCallback(callback, res.statusCode, decoded, res.headers);

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
            safeCallback(callback, 0, JSON.stringify({
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
