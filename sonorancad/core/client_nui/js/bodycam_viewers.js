(function (root) {
    "use strict";

    // Own viewer connections only. The publisher's capture tracks are shared with
    // other viewers and recordings and must never be stopped by viewer cleanup.
    class BodycamViewerConnections {
        constructor({ onWatchingChange, onDiagnostic = () => {}, onError = () => {} }) {
            this.calls = new Map();
            this.onWatchingChange = onWatchingChange;
            this.onDiagnostic = onDiagnostic;
            this.onError = onError;
        }

        notify(reason) {
            let pending = 0;
            for (const entry of this.calls.values()) {
                if (!entry.answered) pending += 1;
            }
            const state = { watching: this.calls.size > 0, active: this.calls.size - pending, pending, reason };
            this.onDiagnostic(state);
            this.onWatchingChange(state);
        }

        add(call, stream) {
            if (this.calls.has(call)) return;
            if (this.calls.size >= 4) {
                try { call.close(); } catch (_) {}
                this.onDiagnostic({ reason: "viewer_limit", active: this.calls.size });
                return;
            }
            const entry = { answered: false, pc: null, listeners: [], disconnectTimer: null, connectTimer: null };
            this.calls.set(call, entry);
            const onClose = () => this.remove(call, "call_closed");
            const onError = () => {
                this.onError("call_error");
                this.remove(call, "call_error");
            };
            call.on("close", onClose);
            call.on("error", onError);
            entry.onClose = onClose;
            entry.onError = onError;
            // Pending calls can close without emitting PeerJS 'close' before
            // answer(), so every admitted call has a bounded setup lifetime.
            entry.connectTimer = setTimeout(() => this.remove(call, "setup_timeout"), 30000);
            this.notify("call_received");
            if (stream) this.answer(call, stream);
        }

        answer(call, stream) {
            const entry = this.calls.get(call);
            if (!entry || entry.answered) return;
            try {
                call.answer(stream);
                if (this.calls.get(call) !== entry) return;
                entry.answered = true;
                // PeerJS creates the incoming RTCPeerConnection in answer().
                entry.pc = call.peerConnection;
                if (!entry.pc) {
                    this.remove(call, "missing_peer_connection");
                    return;
                }
                const onState = () => this.checkState(call, entry);
                const onCandidateError = () => this.onError("ice_candidate_error");
                for (const [name, listener] of [
                    ["connectionstatechange", onState],
                    ["iceconnectionstatechange", onState],
                    ["icecandidateerror", onCandidateError],
                ]) {
                    entry.pc.addEventListener(name, listener);
                    entry.listeners.push([name, listener]);
                }
                this.checkState(call, entry);
                if (this.calls.has(call)) this.notify("call_answered");
            } catch (_) {
                this.onError("answer_failed");
                this.remove(call, "answer_failed");
            }
        }

        answerPending(stream) {
            for (const call of Array.from(this.calls.keys())) this.answer(call, stream);
        }

        checkState(call, entry) {
            if (this.calls.get(call) !== entry) return;
            const states = [entry.pc.connectionState, entry.pc.iceConnectionState];
            if (states.includes("closed") || states.includes("failed")) {
                this.remove(call, states.includes("failed") ? "connection_failed" : "connection_closed");
                return;
            }
            if (states.includes("disconnected")) {
                if (entry.disconnectTimer === null) {
                    this.notify("connection_disconnected");
                    entry.disconnectTimer = setTimeout(() => {
                        entry.disconnectTimer = null;
                        if ([entry.pc.connectionState, entry.pc.iceConnectionState].includes("disconnected")) {
                            this.remove(call, "disconnect_timeout");
                        } else {
                            this.checkState(call, entry);
                        }
                    }, 5000);
                }
                return;
            }
            if (entry.disconnectTimer !== null) {
                clearTimeout(entry.disconnectTimer);
                entry.disconnectTimer = null;
                this.notify("connection_recovered");
            }
            if (states.includes("connected") || states.includes("completed")) {
                clearTimeout(entry.connectTimer);
                entry.connectTimer = null;
            } else if (entry.connectTimer === null) {
                entry.connectTimer = setTimeout(() => this.remove(call, "recovery_timeout"), 30000);
            }
        }

        remove(call, reason) {
            const entry = this.calls.get(call);
            if (!entry) return;
            // Remove first: close() may synchronously emit close/error again.
            this.calls.delete(call);
            clearTimeout(entry.connectTimer);
            clearTimeout(entry.disconnectTimer);
            if (entry.pc) {
                for (const [name, listener] of entry.listeners) entry.pc.removeEventListener(name, listener);
            }
            call.off("close", entry.onClose);
            call.off("error", entry.onError);
            try { call.close(); } catch (_) { this.onError("close_failed"); }
            // Still release the transport when PeerJS close() throws.
            const pc = entry.pc || call.peerConnection;
            if (pc && pc.signalingState !== "closed") {
                try { pc.close(); } catch (_) {}
            }
            this.notify(reason);
        }

        closeAll(reason) {
            for (const call of Array.from(this.calls.keys())) this.remove(call, reason);
            this.notify(reason);
        }
    }

    // Serialize notifications, retry failures, and coalesce rapid hover changes.
    // Sequence numbers also let Lua reject a timed-out request arriving late.
    class BodycamWatchingNotifier {
        constructor(send) {
            this.send = send;
            this.desired = null;
            this.acknowledged = null;
            this.sequence = 0;
            this.inFlight = false;
            this.retryTimer = null;
        }

        update(state) {
            this.desired = state;
            this.flush();
        }

        async flush() {
            if (this.inFlight || this.retryTimer !== null || !this.desired ||
                this.acknowledged === this.desired.watching) return;
            const state = { ...this.desired, sequence: ++this.sequence };
            this.inFlight = true;
            const controller = new AbortController();
            const timeout = setTimeout(() => controller.abort(), 5000);
            try {
                const response = await this.send(state, controller.signal);
                if (!response.ok) throw new Error("watching_callback_failed");
                this.acknowledged = state.watching;
            } catch (_) {
                // A rejected request may already have reached Lua. Resend the
                // latest value even if it matches an earlier acknowledgement.
                this.acknowledged = null;
                this.retryTimer = setTimeout(() => {
                    this.retryTimer = null;
                    this.flush();
                }, 1000);
            } finally {
                clearTimeout(timeout);
                this.inFlight = false;
            }
            this.flush();
        }
    }

    root.BodycamViewerConnections = BodycamViewerConnections;
    root.BodycamWatchingNotifier = BodycamWatchingNotifier;
})(typeof window === "undefined" ? globalThis : window);
