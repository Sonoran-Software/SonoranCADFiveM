"use strict";

let signalR = null;
try {
    signalR = require("@microsoft/signalr");
} catch (err) {
    emit("SonoranCAD::core:writeLog", "error",
        "[apiws] Missing dependency @microsoft/signalr. Run `npm i @microsoft/signalr` in the sonorancad resource.");
}

const DEFAULT_HUBS = {
    production: "wss://api.sonorancad.com/apiWsHub",
    development: "wss://staging-api.dev.sonorancad.com/apiWsHub"
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
        return authenticating;
    }
    authenticating = connection.invoke("authenticate", connectionConfig.communityID, connectionConfig.apiKey)
        .then((auth) => {
            if (auth && auth.success) {
                authenticated = true;
                log("info", "Authenticated with API WS hub.");
                return true;
            }
            authenticated = false;
            const errMsg = auth && auth.error ? auth.error : "unknown error";
            log("error", "Authentication failed: " + errMsg);
            return false;
        })
        .catch((err) => {
            authenticated = false;
            log("error", "Authentication error: " + (err && err.message ? err.message : err));
            return false;
        })
        .finally(() => {
            authenticating = null;
        });
    return authenticating;
}

async function ensureConnection(config) {
    if (!signalR) {
        return false;
    }
    if (!config.apiSendEnabled) {
        if (!warnedApiSendDisabled) {
            log("warn", "apiSendEnabled is false; skipping WS sends.");
            warnedApiSendDisabled = true;
        }
        return false;
    }
    warnedApiSendDisabled = false;
    if (!config.communityID || !config.apiKey) {
        if (!warnedMissingConfig) {
            log("error", "Missing communityID or apiKey for WS authentication. Check config.json or convars.");
            warnedMissingConfig = true;
        }
        return false;
    }
    warnedMissingConfig = false;

    if (!connection || !configsEqual(connectionConfig, config)) {
        if (connection) {
            try {
                await connection.stop();
            } catch (_) {
            }
        }
        authenticated = false;
        connectionConfig = config;
        connection = new signalR.HubConnectionBuilder()
            .withUrl(config.hubUrl, {
                transport: signalR.HttpTransportType.WebSockets,
                skipNegotiation: true
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
            connecting = connection.start()
                .then(() => {
                    log("info", "Connected to API WS hub (" + connectionConfig.hubUrl + ").");
                })
                .catch((err) => {
                    log("error", "Failed to connect to API WS hub: " + (err && err.message ? err.message : err));
                    throw err;
                })
                .finally(() => {
                    connecting = null;
                });
        }
        try {
            await connecting;
        } catch (_) {
            return false;
        }
    }

    if (!authenticated) {
        return await authenticate();
    }
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
            return false;
        }
        const result = await connection.invoke("unitLocation", payload);
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
