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
const DEFAULT_RECONNECT_DELAYS_MS = [0, 2000, 10000, 30000];
const BACKGROUND_ENSURE_INTERVAL_MS = 30000;
const SEND_ERROR_LOG_INTERVAL_MS = 60 * 1000;
const MAX_SILENT_RECONNECT_FAILURES = 2;

let connection = null;
let connectionConfig = null;
let connecting = null;
let authenticating = null;
let authenticated = false;
let warnedMissingConfig = false;
let warnedApiSendDisabled = false;
let reconnectFailureCount = 0;
let reconnectEscalated = false;
let backgroundEnsureInterval = null;
let backgroundEnsureInFlight = false;
const serverIssueState = Object.create(null);

function log(level, message) {
    emit("SonoranCAD::core:writeLog", level, "[apiws] " + message);
}

function getErrorMessage(err) {
    if (!err) {
        return "unknown error";
    }
    return err.message ? err.message : String(err);
}

function clearServerIssue(key) {
    delete serverIssueState[key];
}

function reportServerIssue(key, message, intervalMs) {
    const now = Date.now();
    let state = serverIssueState[key];
    if (!state) {
        state = {
            lastLoggedAt: 0,
            suppressedCount: 0,
            pendingMessage: message
        };
        serverIssueState[key] = state;
    }

    state.pendingMessage = message;
    if (state.lastLoggedAt === 0 || (now - state.lastLoggedAt) >= intervalMs) {
        const suffix = state.suppressedCount > 0
            ? " (" + state.suppressedCount + " similar events suppressed)"
            : "";
        console.error("[apiws] " + state.pendingMessage + suffix);
        state.lastLoggedAt = now;
        state.suppressedCount = 0;
        return;
    }

    state.suppressedCount++;
    log("debug", "Suppressed server console error [" + key + "]: " + message);
}

function resetReconnectState() {
    reconnectFailureCount = 0;
    reconnectEscalated = false;
}

function reportReconnectFailure(failedAttempts, err) {
    if (failedAttempts <= MAX_SILENT_RECONNECT_FAILURES || reconnectEscalated) {
        return;
    }

    reconnectEscalated = true;
    console.error(
        "[apiws] API WS reconnect has failed " + failedAttempts
        + " times. Latest error: " + getErrorMessage(err)
    );
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

function normalizeServerId(value) {
    if (value === undefined || value === null) {
        return null;
    }
    if (typeof value === "number") {
        return value;
    }
    if (typeof value === "string") {
        const trimmed = value.trim();
        if (trimmed === "") {
            return null;
        }
        if (/^\d+$/.test(trimmed)) {
            return Number(trimmed);
        }
        return trimmed;
    }
    return value;
}

function parsePushEventPayload(payload) {
    if (typeof payload === "string") {
        return JSON.parse(payload);
    }
    return payload;
}

function handleIncomingPushEvent(payload) {
    try {
        const parsed = parsePushEventPayload(payload);
        if (!parsed || typeof parsed !== "object") {
            throw new Error("payload was not an object");
        }
        if (!parsed.type) {
            throw new Error("payload missing event type");
        }
        emit("SonoranCAD::pushevents:shim", JSON.stringify(parsed));
        clearServerIssue("ws-push");
        log("debug", "Received pushEvent over WS: " + parsed.type);
    } catch (err) {
        const errMsg = getErrorMessage(err);
        log("warn", "Failed to process pushEvent payload: " + errMsg);
        reportServerIssue("ws-push", "pushEvent processing failed: " + errMsg, SEND_ERROR_LOG_INTERVAL_MS);
    }
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
    const serverId = normalizeServerId(getConvar("sonoran_serverId") || fileConfig.serverId);
    const mode = (getConvar("sonoran_mode") || fileConfig.mode || "production").toLowerCase();
    const apiSendEnabled = parseBoolean(
        getConvar("sonoran_apiSendEnabled"),
        parseBoolean(fileConfig.apiSendEnabled, true)
    );
    const hubUrl = mode === "development" ? DEFAULT_HUBS.development : DEFAULT_HUBS.production;
    log("debug", "Config: mode=" + mode + ", hubUrl=" + hubUrl + ", apiSendEnabled=" + apiSendEnabled
        + ", communityID=" + (communityID ? "set" : "missing") + ", apiKey=" + (apiKey ? "set" : "missing")
        + ", serverId=" + (serverId !== null ? String(serverId) : "missing"));
    return {
        communityID,
        apiKey,
        serverId,
        mode,
        hubUrl,
        apiSendEnabled
    };
}

function configsEqual(a, b) {
    return !!a && !!b &&
        a.communityID === b.communityID &&
        a.apiKey === b.apiKey &&
        a.serverId === b.serverId &&
        a.hubUrl === b.hubUrl;
}

async function authenticate() {
    if (authenticating) {
        log("debug", "Authenticate: already in progress.");
        return authenticating;
    }
    log("debug", "Authenticate: invoking authenticate().");
    authenticating = connection.invoke("authenticate", connectionConfig.communityID, connectionConfig.apiKey, connectionConfig.serverId)
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
    if (!config.communityID || !config.apiKey || config.serverId === null) {
        if (!warnedMissingConfig) {
            log("error", "Missing communityID, apiKey, or serverId for WS authentication. Check config.json or convars.");
            warnedMissingConfig = true;
        }
        log("debug", "ensureConnection: missing communityID/apiKey/serverId.");
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
            .withAutomaticReconnect({
                nextRetryDelayInMilliseconds: (retryContext) => {
                    reconnectFailureCount = retryContext.previousRetryCount;
                    if (retryContext.previousRetryCount > 0) {
                        log(
                            "debug",
                            "Reconnect attempt " + retryContext.previousRetryCount
                            + " failed: " + getErrorMessage(retryContext.retryReason)
                        );
                    }
                    reportReconnectFailure(retryContext.previousRetryCount, retryContext.retryReason);
                    return typeof DEFAULT_RECONNECT_DELAYS_MS[retryContext.previousRetryCount] === "number"
                        ? DEFAULT_RECONNECT_DELAYS_MS[retryContext.previousRetryCount]
                        : null;
                }
            })
            .build();

        connection.on("pushEvent", handleIncomingPushEvent);

        connection.onreconnecting((err) => {
            authenticated = false;
            resetReconnectState();
            const msg = err && err.message ? ": " + err.message : "";
            log("debug", "Reconnecting to API WS hub" + msg + ".");
        });
        connection.onreconnected(async () => {
            authenticated = false;
            resetReconnectState();
            clearServerIssue("ws-send");
            log("debug", "Reconnected: re-authenticating.");
            await authenticate();
        });
        connection.onclose((err) => {
            authenticated = false;
            const msg = err && err.message ? ": " + err.message : "";
            reportReconnectFailure(reconnectFailureCount, err);
            log("debug", "Disconnected from API WS hub" + msg + ".");
            resetReconnectState();
        });
    }

    if (connection.state !== signalR.HubConnectionState.Connected) {
        if (!connecting) {
            log("debug", "ensureConnection: starting connection.");
            connecting = connection.start()
                .then(() => {
                    clearServerIssue("ws-send");
                    log("info", "Connected to API WS hub (" + connectionConfig.hubUrl + ").");
                    log("debug", "ensureConnection: connection start resolved.");
                })
                .catch((err) => {
                    const errMsg = getErrorMessage(err);
                    log("debug", "Failed to connect to API WS hub: " + errMsg);
                    reportServerIssue("ws-send", "Unable to connect to API WS hub: " + errMsg, SEND_ERROR_LOG_INTERVAL_MS);
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

async function runBackgroundEnsure() {
    if (backgroundEnsureInFlight) {
        return;
    }
    backgroundEnsureInFlight = true;
    try {
        await ensureConnection(buildConfig());
    } catch (_) {
    } finally {
        backgroundEnsureInFlight = false;
    }
}

function startBackgroundEnsureLoop() {
    if (!signalR || backgroundEnsureInterval) {
        return;
    }
    runBackgroundEnsure();
    backgroundEnsureInterval = setInterval(runBackgroundEnsure, BACKGROUND_ENSURE_INTERVAL_MS);
}

async function stopConnection() {
    authenticated = false;
    connecting = null;
    authenticating = null;
    if (!connection) {
        return;
    }
    const activeConnection = connection;
    connection = null;
    connectionConfig = null;
    try {
        await activeConnection.stop();
    } catch (_) {
    }
}

startBackgroundEnsureLoop();

on("onResourceStop", (resourceName) => {
    if (resourceName !== GetCurrentResourceName()) {
        return;
    }
    if (backgroundEnsureInterval) {
        clearInterval(backgroundEnsureInterval);
        backgroundEnsureInterval = null;
    }
    stopConnection();
});

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
            reportServerIssue("ws-send", "unitLocation skipped: connection not ready.", SEND_ERROR_LOG_INTERVAL_MS);
            return false;
        }
        log("debug", "Sending location update with payload: " + JSON.stringify(payload));
        const result = await connection.invoke("unitLocation", payload);
        clearServerIssue("ws-send");
        log("debug", "unitLocation response: " + JSON.stringify(result));
        if (result && result.success === false) {
            const errMsg = result.error || "unknown error";
            log("warn", "unitLocation rejected: " + errMsg);
            return false;
        }
        return true;
    } catch (err) {
        const errMsg = getErrorMessage(err);
        log("debug", "unitLocation send failed: " + errMsg);
        reportServerIssue("ws-send", "unitLocation send failed: " + errMsg, SEND_ERROR_LOG_INTERVAL_MS);
        return false;
    }
});
