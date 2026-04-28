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
    const MANUAL_RETRY_DELAYS_MS = [2000, 5000, 10000, 30000];
    const SIGNALR_DEBUG_ONLY_PATTERNS = [
        "(WebSockets transport) There was an error with the transport.",
        "Failed to start the transport 'WebSockets'",
        "Failed to start the connection: Error: Unable to connect to the server with any of the available transports.",
        "WebSocket failed to connect. The connection could not be found on the server"
    ];

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
    let manualRetryTimer = null;
    let manualRetryAttempt = 0;
    const serverIssueState = Object.create(null);

    function apiWsLog(level, message) {
        emit("SonoranCAD::core:writeLog", level, "[apiws] " + message);
    }

    function isSignalRDebugOnlyMessage(message) {
        if (!message || typeof message !== "string") {
            return false;
        }
        return SIGNALR_DEBUG_ONLY_PATTERNS.some((pattern) => message.indexOf(pattern) !== -1);
    }

    function createSignalRLogger() {
        return {
            log: (level, message) => {
                if (!message) {
                    return;
                }
                if (isSignalRDebugOnlyMessage(message)) {
                    apiWsLog("debug", "[signalr] " + message);
                    return;
                }
                if (level === signalR.LogLevel.Critical || level === signalR.LogLevel.Error) {
                    apiWsLog("error", "[signalr] " + message);
                    return;
                }
                if (level === signalR.LogLevel.Warning) {
                    apiWsLog("warn", "[signalr] " + message);
                    return;
                }
                apiWsLog("debug", "[signalr] " + message);
            }
        };
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
        apiWsLog("debug", "Suppressed server console error [" + key + "]: " + message);
    }

    function resetReconnectState() {
        reconnectFailureCount = 0;
        reconnectEscalated = false;
    }

    function clearManualRetry() {
        if (!manualRetryTimer) {
            return;
        }
        clearTimeout(manualRetryTimer);
        manualRetryTimer = null;
    }

    function resetManualRetryState() {
        clearManualRetry();
        manualRetryAttempt = 0;
    }

    function scheduleManualRetry(reason) {
        if (manualRetryTimer) {
            apiWsLog("debug", "Manual retry already scheduled; latest reason=" + reason + ".");
            return;
        }
        const delay = typeof MANUAL_RETRY_DELAYS_MS[manualRetryAttempt] === "number"
            ? MANUAL_RETRY_DELAYS_MS[manualRetryAttempt]
            : MANUAL_RETRY_DELAYS_MS[MANUAL_RETRY_DELAYS_MS.length - 1];
        manualRetryAttempt += 1;
        apiWsLog("debug", "Scheduling manual API WS retry in " + delay + "ms. Reason=" + reason + ".");
        manualRetryTimer = setTimeout(async () => {
            manualRetryTimer = null;
            apiWsLog("debug", "Manual API WS retry fired.");
            await runBackgroundEnsure();
        }, delay);
    }

    function reportReconnectFailure(failedAttempts, err) {
        if (failedAttempts <= MAX_SILENT_RECONNECT_FAILURES || reconnectEscalated) {
            return;
        }

        reconnectEscalated = true;
        apiWsLog(
            "debug",
            "API WS reconnect has failed " + failedAttempts
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
            apiWsLog("debug", "pushEvent callback fired. Raw payload type=" + typeof payload + ".");
            const parsed = parsePushEventPayload(payload);
            if (!parsed || typeof parsed !== "object") {
                throw new Error("payload was not an object");
            }
            if (!parsed.type) {
                throw new Error("payload missing event type");
            }
            emit("SonoranCAD::pushevents:shim", JSON.stringify(parsed));
            clearServerIssue("ws-push");
            apiWsLog("debug", "Received pushEvent over WS: type=" + parsed.type + ", keys=" + Object.keys(parsed).join(","));
        } catch (err) {
            const errMsg = getErrorMessage(err);
            apiWsLog("warn", "Failed to process pushEvent payload: " + errMsg);
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
            apiWsLog("warn", "Failed to parse configuration/config.json: " + (err.message || err));
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
        apiWsLog("debug", "Config: mode=" + mode + ", hubUrl=" + hubUrl + ", apiSendEnabled=" + apiSendEnabled
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
            apiWsLog("debug", "Authenticate: already in progress.");
            return authenticating;
        }
        apiWsLog("debug", "Authenticate: invoking authenticatev2 for serverId=" + String(connectionConfig.serverId) + ".");
        authenticating = connection.invoke("authenticatev2", connectionConfig.communityID, connectionConfig.apiKey, connectionConfig.serverId)
            .then((auth) => {
                if (auth && auth.success) {
                    authenticated = true;
                    resetManualRetryState();
                    apiWsLog("info", "Authenticated with API WS hub.");
                    apiWsLog("debug", "Authenticate: success.");
                    return true;
                }
                authenticated = false;
                const errMsg = auth && auth.error ? auth.error : "unknown error";
                apiWsLog("error", "Authentication failed: " + errMsg);
                apiWsLog("debug", "Authenticate: failed response: " + JSON.stringify(auth));
                scheduleManualRetry("authentication_failed");
                return false;
            })
            .catch((err) => {
                authenticated = false;
                apiWsLog("error", "Authentication error: " + (err && err.message ? err.message : err));
                apiWsLog("debug", "Authenticate: exception.");
                scheduleManualRetry("authentication_exception");
                return false;
            })
            .finally(() => {
                apiWsLog("debug", "Authenticate: completed.");
                authenticating = null;
            });
        return authenticating;
    }

    async function ensureConnection(config) {
        if (!signalR) {
            apiWsLog("debug", "ensureConnection: signalR missing.");
            return false;
        }
        if (!config.apiSendEnabled) {
            if (!warnedApiSendDisabled) {
                apiWsLog("warn", "apiSendEnabled is false; skipping WS sends.");
                warnedApiSendDisabled = true;
            }
            apiWsLog("debug", "ensureConnection: apiSendEnabled false.");
            return false;
        }
        warnedApiSendDisabled = false;
        if (!config.communityID || !config.apiKey || config.serverId === null) {
            if (!warnedMissingConfig) {
                apiWsLog("error", "Missing communityID, apiKey, or serverId for WS authentication. Check config.json or convars.");
                warnedMissingConfig = true;
            }
            apiWsLog("debug", "ensureConnection: missing communityID/apiKey/serverId.");
            return false;
        }
        warnedMissingConfig = false;

        if (!connection || !configsEqual(connectionConfig, config)) {
            apiWsLog("debug", "ensureConnection: building new connection (config changed or missing).");
            if (connection) {
                try {
                    apiWsLog("debug", "ensureConnection: stopping previous connection before rebuild.");
                    await connection.stop();
                } catch (_) {
                }
            }
            authenticated = false;
            connectionConfig = config;
            apiWsLog("debug", "ensureConnection: withUrl(" + config.hubUrl + "), transport=WebSockets, skipNegotiation=false");
            connection = new signalR.HubConnectionBuilder()
                .configureLogging(createSignalRLogger())
                .withUrl(config.hubUrl, {
                    transport: signalR.HttpTransportType.WebSockets
                })
                .withAutomaticReconnect({
                    nextRetryDelayInMilliseconds: (retryContext) => {
                        reconnectFailureCount = retryContext.previousRetryCount;
                        if (retryContext.previousRetryCount > 0) {
                            apiWsLog(
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

            apiWsLog("debug", "ensureConnection: registering pushEvent handler on hub connection.");
            connection.on("pushEvent", handleIncomingPushEvent);

            connection.onreconnecting((err) => {
                authenticated = false;
                resetReconnectState();
                const msg = err && err.message ? ": " + err.message : "";
                apiWsLog("debug", "Reconnecting to API WS hub" + msg + ".");
            });
            connection.onreconnected(async () => {
                authenticated = false;
                resetReconnectState();
                resetManualRetryState();
                clearServerIssue("ws-send");
                apiWsLog("debug", "Reconnected: re-authenticating.");
                await authenticate();
            });
            connection.onclose((err) => {
                authenticated = false;
                const msg = err && err.message ? ": " + err.message : "";
                reportReconnectFailure(reconnectFailureCount, err);
                apiWsLog("debug", "Disconnected from API WS hub" + msg + ".");
                resetReconnectState();
                scheduleManualRetry("connection_closed");
            });
        }

        apiWsLog("debug", "ensureConnection: current state=" + String(connection.state) + ".");
        if (connection.state !== signalR.HubConnectionState.Connected) {
            if (!connecting) {
                apiWsLog("debug", "ensureConnection: starting connection.");
                connecting = connection.start()
                    .then(() => {
                        clearServerIssue("ws-send");
                        resetManualRetryState();
                        apiWsLog("info", "Connected to API WS hub (" + connectionConfig.hubUrl + ").");
                        apiWsLog("debug", "ensureConnection: connection start resolved.");
                    })
                    .catch((err) => {
                        const errMsg = getErrorMessage(err);
                        apiWsLog("debug", "Failed to connect to API WS hub: " + errMsg);
                        reportServerIssue("ws-send", "Unable to connect to API WS hub: " + errMsg, SEND_ERROR_LOG_INTERVAL_MS);
                        apiWsLog("debug", "ensureConnection: connection start rejected.");
                        scheduleManualRetry("connection_start_failed");
                        throw err;
                    })
                    .finally(() => {
                        apiWsLog("debug", "ensureConnection: start attempt finished.");
                        connecting = null;
                    });
            }
            try {
                await connecting;
            } catch (_) {
                apiWsLog("debug", "ensureConnection: connection start failed.");
                return false;
            }
        }

        if (!authenticated) {
            apiWsLog("debug", "ensureConnection: authenticating.");
            const authOk = await authenticate();
            apiWsLog("debug", "ensureConnection: authenticate result=" + authOk + ".");
            return authOk;
        }
        apiWsLog("debug", "ensureConnection: ready.");
        return true;
    }

    async function runBackgroundEnsure() {
        if (backgroundEnsureInFlight) {
            apiWsLog("debug", "Background ensure skipped: already running.");
            return;
        }
        backgroundEnsureInFlight = true;
        try {
            apiWsLog("debug", "Background ensure tick starting.");
            await ensureConnection(buildConfig());
        } catch (_) {
        } finally {
            apiWsLog("debug", "Background ensure tick finished.");
            backgroundEnsureInFlight = false;
        }
    }

    function startBackgroundEnsureLoop() {
        if (!signalR || backgroundEnsureInterval) {
            return;
        }
        apiWsLog("debug", "Starting API WS background ensure loop (" + BACKGROUND_ENSURE_INTERVAL_MS + "ms).");
        runBackgroundEnsure();
        backgroundEnsureInterval = setInterval(runBackgroundEnsure, BACKGROUND_ENSURE_INTERVAL_MS);
    }

    async function stopConnection() {
        authenticated = false;
        connecting = null;
        authenticating = null;
        resetManualRetryState();
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
            const payload = (Array.isArray(updates) ? updates : Object.values(updates)).filter((entry) => {
                if (!entry || typeof entry !== "object") {
                    return false;
                }
                const hasIdentity = typeof entry.communityUserId === "string" && entry.communityUserId.length > 0;
                const hasLocation = typeof entry.location === "string" && entry.location.length > 0;
                return hasIdentity && hasLocation;
            });
            if (!payload || payload.length === 0) {
                return false;
            }
            const config = buildConfig();
            const ok = await ensureConnection(config);
            if (!ok) {
                reportServerIssue("ws-send", "unitLocation skipped: connection not ready.", SEND_ERROR_LOG_INTERVAL_MS);
                return false;
            }
            apiWsLog("debug", "Sending location update with payload: " + JSON.stringify(payload));
            const result = await connection.invoke("unitLocation", payload);
            clearServerIssue("ws-send");
            apiWsLog("debug", "unitLocation response: " + JSON.stringify(result));
            if (result && result.success === false) {
                const errMsg = result.error || "unknown error";
                apiWsLog("warn", "unitLocation rejected: " + errMsg);
                return false;
            }
            return true;
        } catch (err) {
            const errMsg = getErrorMessage(err);
            apiWsLog("debug", "unitLocation send failed: " + errMsg);
            reportServerIssue("ws-send", "unitLocation send failed: " + errMsg, SEND_ERROR_LOG_INTERVAL_MS);
            return false;
        }
    });
