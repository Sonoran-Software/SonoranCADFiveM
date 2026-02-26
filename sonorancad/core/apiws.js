"use strict";

let signalR = null;
try {
    signalR = require("@microsoft/signalr");
} catch (err) {
    emit("SonoranCAD::core:writeLog", "error",
        "[apiws] Missing dependency @microsoft/signalr. Run `npm i @microsoft/signalr` in the sonorancad resource.");
}

const DEFAULT_HUBS = {
    production: "https://api.sonorancad.com/apiWsHub",
    development: "https://staging-api.dev.sonorancad.com/apiWsHub"
};

let connection = null;
let connectionConfig = null;
let connecting = null;
let authenticating = null;
let authenticated = false;
let warnedMissingConfig = false;
let warnedApiSendDisabled = false;

function log(level, message) {
    emit("SonoranCAD::core:writeLog", level, "[apiws] " + message);
}

function parseBoolean(value, fallback) {
    if (value === undefined || value === null) {
        return fallback;
    }
    if (typeof value === "boolean") {
        return value;
    }
    if (typeof value === "string") {
        const normalized = value.toLowerCase();
        if (normalized === "true") {
            return true;
        }
        if (normalized === "false") {
            return false;
        }
    }
    return fallback;
}

function readConfigFile() {
    try {
        const raw = LoadResourceFile(GetCurrentResourceName(), "configuration/config.json");
        if (raw && raw !== "") {
            return JSON.parse(raw);
        }
    } catch (err) {
        log("warn", "Failed to parse configuration/config.json: " + (err.message || err));
    }
    return {};
}

function getConvar(name) {
    const value = GetConvar(name, "NONE");
    if (value === "NONE") {
        return null;
    }
    return value;
}

function buildConfig() {
    const fileConfig = readConfigFile();
    const communityID = getConvar("sonoran_communityID") || fileConfig.communityID;
    const apiKey = getConvar("sonoran_apiKey") || fileConfig.apiKey;
    const mode = (getConvar("sonoran_mode") || fileConfig.mode || "production").toLowerCase();
    const apiSendEnabled = parseBoolean(
        getConvar("sonoran_apiSendEnabled"),
        parseBoolean(fileConfig.apiSendEnabled, true)
    );
    const hubUrl = mode === "development" ? DEFAULT_HUBS.development : DEFAULT_HUBS.production;
    log("debug", "Config: mode=" + mode + ", hubUrl=" + hubUrl + ", apiSendEnabled=" + apiSendEnabled
        + ", communityID=" + (communityID ? "set" : "missing") + ", apiKey=" + (apiKey ? "set" : "missing"));
    return {
        communityID,
        apiKey,
        mode,
        hubUrl,
        apiSendEnabled
    };
}

function configsEqual(a, b) {
    return !!a && !!b &&
        a.communityID === b.communityID &&
        a.apiKey === b.apiKey &&
        a.hubUrl === b.hubUrl;
}

async function authenticate() {
    if (authenticating) {
        log("debug", "Authenticate: already in progress.");
        return authenticating;
    }
    log("debug", "Authenticate: invoking authenticate().");
    authenticating = connection.invoke("authenticate", connectionConfig.communityID, connectionConfig.apiKey)
        .then((auth) => {
            if (auth && auth.success) {
                authenticated = true;
                log("info", "Authenticated with API WS hub.");
                log("debug", "Authenticate: success.");
                return true;
            }
            authenticated = false;
            const errMsg = auth && auth.error ? auth.error : "unknown error";
            log("error", "Authentication failed: " + errMsg);
            log("debug", "Authenticate: failed response: " + JSON.stringify(auth));
            return false;
        })
        .catch((err) => {
            authenticated = false;
            log("error", "Authentication error: " + (err && err.message ? err.message : err));
            log("debug", "Authenticate: exception.");
            return false;
        })
        .finally(() => {
            log("debug", "Authenticate: completed.");
            authenticating = null;
        });
    return authenticating;
}

async function ensureConnection(config) {
    if (!signalR) {
        log("debug", "ensureConnection: signalR missing.");
        return false;
    }
    if (!config.apiSendEnabled) {
        if (!warnedApiSendDisabled) {
            log("warn", "apiSendEnabled is false; skipping WS sends.");
            warnedApiSendDisabled = true;
        }
        log("debug", "ensureConnection: apiSendEnabled false.");
        return false;
    }
    warnedApiSendDisabled = false;
    if (!config.communityID || !config.apiKey) {
        if (!warnedMissingConfig) {
            log("error", "Missing communityID or apiKey for WS authentication. Check config.json or convars.");
            warnedMissingConfig = true;
        }
        log("debug", "ensureConnection: missing communityID/apiKey.");
        return false;
    }
    warnedMissingConfig = false;

    if (!connection || !configsEqual(connectionConfig, config)) {
        log("debug", "ensureConnection: building new connection (config changed or missing).");
        if (connection) {
            try {
                await connection.stop();
            } catch (_) {
            }
        }
        authenticated = false;
        connectionConfig = config;
        log("debug", "ensureConnection: withUrl(" + config.hubUrl + "), transport=WebSockets, skipNegotiation=false");
        connection = new signalR.HubConnectionBuilder()
            .withUrl(config.hubUrl, {
                transport: signalR.HttpTransportType.WebSockets
            })
            .withAutomaticReconnect()
            .build();

        connection.onreconnecting((err) => {
            authenticated = false;
            const msg = err && err.message ? ": " + err.message : "";
            log("warn", "Reconnecting to API WS hub" + msg + ".");
        });
        connection.onreconnected(async () => {
            authenticated = false;
            log("debug", "Reconnected: re-authenticating.");
            await authenticate();
        });
        connection.onclose((err) => {
            authenticated = false;
            const msg = err && err.message ? ": " + err.message : "";
            log("warn", "Disconnected from API WS hub" + msg + ".");
        });
    }

    if (connection.state !== signalR.HubConnectionState.Connected) {
        if (!connecting) {
            log("debug", "ensureConnection: starting connection.");
            connecting = connection.start()
                .then(() => {
                    log("info", "Connected to API WS hub (" + connectionConfig.hubUrl + ").");
                    log("debug", "ensureConnection: connection start resolved.");
                })
                .catch((err) => {
                    log("error", "Failed to connect to API WS hub: " + (err && err.message ? err.message : err));
                    log("debug", "ensureConnection: connection start rejected.");
                    throw err;
                })
                .finally(() => {
                    log("debug", "ensureConnection: start attempt finished.");
                    connecting = null;
                });
        }
        try {
            await connecting;
        } catch (_) {
            log("debug", "ensureConnection: connection start failed.");
            return false;
        }
    }

    if (!authenticated) {
        log("debug", "ensureConnection: authenticating.");
        return await authenticate();
    }
    log("debug", "ensureConnection: ready.");
    return true;
}

exports("sendUnitLocations", async (updates) => {
    try {
        if (!updates) {
            return false;
        }
        const payload = Array.isArray(updates) ? updates : Object.values(updates);
        if (!payload || payload.length === 0) {
            return false;
        }
        const config = buildConfig();
        const ok = await ensureConnection(config);
        if (!ok) {
            console.error("[apiws] unitLocation skipped: connection not ready.");
            return false;
        }
        log('debug', 'Sending location update with payload: ' + JSON.stringify(payload))
        const result = await connection.invoke("unitLocation", payload);
        log("debug", "unitLocation response: " + JSON.stringify(result));
        if (result && result.success === false) {
            const errMsg = result.error || "unknown error";
            log("warn", "unitLocation rejected: " + errMsg);
            return false;
        }
        return true;
    } catch (err) {
        log("error", "unitLocation send failed: " + (err && err.message ? err.message : err));
        return false;
    }
});
