(function () {
	"use strict";

	const DEFAULTS = {
		shadowBufferSeconds: 30,
		liveClipSeconds: 30,
		maxClipSeconds: 120,
		width: 960,
		height: 540,
		fps: 10,
		videoBitrate: 300000,
		audioBitrate: 64000,
		mimeType: "video/webm;codecs=vp8,opus",
		maxFileSizeBytes: 6000000,
	};
	const TIMESLICE_MS = 1000;
	const MAX_DURATION_MS = 120000;

	function nowMs() {
		return Date.now();
	}

	function clamp(value, min, max, fallback) {
		const parsed = Number(value);
		if (!Number.isFinite(parsed)) {
			return fallback;
		}
		return Math.min(max, Math.max(min, parsed));
	}

	function clonePayload(payload) {
		if (!payload || typeof payload !== "object") {
			return {};
		}
		return JSON.parse(JSON.stringify(payload));
	}

	function blobToDataUrl(blob) {
		return new Promise(function (resolve, reject) {
			const reader = new FileReader();
			reader.onloadend = function () {
				resolve(reader.result);
			};
			reader.onerror = reject;
			reader.readAsDataURL(blob);
		});
	}

	function postToGame(endpoint, payload) {
		return fetch(`https://${GetParentResourceName()}/${endpoint}`, {
			method: "POST",
			headers: { "Content-Type": "application/json; charset=UTF-8" },
			body: JSON.stringify(payload || {}),
		}).catch(function () {});
	}

	function createRecorder() {
		const exportCanvas = document.createElement("canvas");
		exportCanvas.id = "bodycamRecordingCanvas";
		exportCanvas.width = DEFAULTS.width;
		exportCanvas.height = DEFAULTS.height;
		exportCanvas.style.position = "absolute";
		exportCanvas.style.left = "-10000px";
		exportCanvas.style.top = "-10000px";
		exportCanvas.style.width = "1px";
		exportCanvas.style.height = "1px";
		exportCanvas.style.opacity = "0";
		exportCanvas.style.pointerEvents = "none";
		document.body.appendChild(exportCanvas);

		const exportCtx = exportCanvas.getContext("2d", { alpha: false });
		const previewVideo = document.createElement("video");
		previewVideo.autoplay = true;
		previewVideo.muted = true;
		previewVideo.playsInline = true;
		previewVideo.style.display = "none";
		document.body.appendChild(previewVideo);

		const state = {
			config: { ...DEFAULTS },
			sourceStream: null,
			exportCanvas: exportCanvas,
			exportCtx: exportCtx,
			previewVideo: previewVideo,
			exportStream: null,
			audioTrack: null,
			mediaRecorder: null,
			chunks: [],
			renderTimer: null,
			recordingSession: null,
			pipelineReady: false,
		};

		function getMimeType() {
			const requested = state.config.mimeType || DEFAULTS.mimeType;
			if (window.MediaRecorder && typeof window.MediaRecorder.isTypeSupported === "function") {
				if (window.MediaRecorder.isTypeSupported(requested)) {
					return requested;
				}
				if (window.MediaRecorder.isTypeSupported("video/webm;codecs=vp8,opus")) {
					return "video/webm;codecs=vp8,opus";
				}
			}
			return "video/webm";
		}

		function getShadowDurationMs() {
			return clamp(state.config.shadowBufferSeconds, 0, 60, DEFAULTS.shadowBufferSeconds) * 1000;
		}

		function getMaxClipMs() {
			return clamp(state.config.maxClipSeconds, 1, 120, DEFAULTS.maxClipSeconds) * 1000;
		}

		function trimChunks() {
			const maxAge = Math.max(getMaxClipMs(), getShadowDurationMs()) + (TIMESLICE_MS * 2);
			const cutoff = nowMs() - maxAge;
			state.chunks = state.chunks.filter(function (chunk) {
				if (state.recordingSession && chunk.timestamp >= state.recordingSession.captureStartAt - TIMESLICE_MS) {
					return true;
				}
				return chunk.timestamp >= cutoff;
			});
		}

		function stopRenderLoop() {
			if (state.renderTimer) {
				clearInterval(state.renderTimer);
				state.renderTimer = null;
			}
		}

		function startRenderLoop() {
			stopRenderLoop();
			const fps = clamp(state.config.fps, 1, 30, DEFAULTS.fps);
			const frameInterval = Math.max(50, Math.floor(1000 / fps));
			state.renderTimer = setInterval(function () {
				if (!state.previewVideo || state.previewVideo.readyState < 2) {
					return;
				}
				const width = clamp(state.config.width, 1, 1920, DEFAULTS.width);
				const height = clamp(state.config.height, 1, 1080, DEFAULTS.height);
				if (state.exportCanvas.width !== width) {
					state.exportCanvas.width = width;
				}
				if (state.exportCanvas.height !== height) {
					state.exportCanvas.height = height;
				}
				try {
					state.exportCtx.drawImage(state.previewVideo, 0, 0, width, height);
				} catch (err) {}
			}, frameInterval);
		}

		function destroyExportStream() {
			if (state.mediaRecorder && state.mediaRecorder.state !== "inactive") {
				try {
					state.mediaRecorder.stop();
				} catch (err) {}
			}
			state.mediaRecorder = null;
			if (state.exportStream) {
				state.exportStream.getTracks().forEach(function (track) {
					try {
						track.stop();
					} catch (err) {}
				});
				state.exportStream = null;
			}
			if (state.audioTrack) {
				try {
					state.audioTrack.stop();
				} catch (err) {}
				state.audioTrack = null;
			}
			state.pipelineReady = false;
			stopRenderLoop();
			state.chunks = [];
		}

		function buildExportStream() {
			if (!state.sourceStream || !state.exportCtx) {
				return false;
			}
			const width = clamp(state.config.width, 1, 1920, DEFAULTS.width);
			const height = clamp(state.config.height, 1, 1080, DEFAULTS.height);
			const fps = clamp(state.config.fps, 1, 30, DEFAULTS.fps);
			state.exportCanvas.width = width;
			state.exportCanvas.height = height;
			state.previewVideo.srcObject = state.sourceStream;
			state.previewVideo.play().catch(function () {});
			startRenderLoop();

			const canvasStream = state.exportCanvas.captureStream(fps);
			const tracks = canvasStream.getVideoTracks();
			const sourceAudioTrack = state.sourceStream.getAudioTracks()[0] || null;
			if (sourceAudioTrack) {
				state.audioTrack = sourceAudioTrack.clone();
				tracks.push(state.audioTrack);
			}
			state.exportStream = new MediaStream(tracks);
			state.pipelineReady = true;
			return true;
		}

		function startContinuousRecorder() {
			if (!state.pipelineReady && !buildExportStream()) {
				return false;
			}
			if (state.mediaRecorder && state.mediaRecorder.state !== "inactive") {
				return true;
			}
			state.chunks = [];
			state.mediaRecorder = new MediaRecorder(state.exportStream, {
				mimeType: getMimeType(),
				videoBitsPerSecond: clamp(state.config.videoBitrate, 64000, 2500000, DEFAULTS.videoBitrate),
				audioBitsPerSecond: clamp(state.config.audioBitrate, 16000, 256000, DEFAULTS.audioBitrate),
			});
			state.mediaRecorder.ondataavailable = function (event) {
				if (!event.data || event.data.size <= 0) {
					return;
				}
				state.chunks.push({
					blob: event.data,
					size: event.data.size,
					timestamp: nowMs(),
					durationMs: TIMESLICE_MS,
				});
				trimChunks();
			};
			state.mediaRecorder.start(TIMESLICE_MS);
			return true;
		}

		async function setSourceStream(stream) {
			if (stream === state.sourceStream) {
				return;
			}
			if (!stream) {
				await stopSession("bodycam_off");
				state.sourceStream = null;
				state.previewVideo.pause();
				state.previewVideo.srcObject = null;
				destroyExportStream();
				return;
			}
			state.sourceStream = stream;
			destroyExportStream();
			buildExportStream();
			startContinuousRecorder();
		}

		function notifyState(payload) {
			postToGame("bodycamRecordingState", payload);
		}

		function buildSession(message) {
			const shadowDurationMs = getShadowDurationMs();
			const maxClipMs = Math.min(getMaxClipMs(), MAX_DURATION_MS);
			const requestedLiveMs = clamp(state.config.liveClipSeconds, 1, 120, DEFAULTS.liveClipSeconds) * 1000;
			const liveDurationMs = Math.max(1, Math.min(requestedLiveMs, maxClipMs - shadowDurationMs));
			const totalDurationMs = Math.min(maxClipMs, shadowDurationMs + liveDurationMs);
			const startedAt = nowMs();
			const shadowStartAt = startedAt - shadowDurationMs;
			return {
				sourceType: message.sourceType || "manual",
				trigger: message.trigger || null,
				metadata: clonePayload(message.metadata),
				startedAt: startedAt,
				shadowDurationMs: shadowDurationMs,
				liveDurationMs: liveDurationMs,
				totalDurationMs: totalDurationMs,
				captureStartAt: shadowStartAt,
				captureStopAt: startedAt + liveDurationMs,
				stopTimer: null,
			};
		}

		async function uploadClip(blob, session, reason) {
			const durationMs = Math.max(1, Math.min(MAX_DURATION_MS, Math.round(session.totalDurationMs)));
			if (blob.size > state.config.maxFileSizeBytes) {
				notifyState({
					state: "failed",
					reason: "clip_too_large",
					sourceType: session.sourceType,
					trigger: session.trigger,
					size: blob.size,
					durationMs: durationMs,
				});
				return;
			}
			const fileData = await blobToDataUrl(blob);
			notifyState({
				state: "uploading",
				sourceType: session.sourceType,
				trigger: session.trigger,
				reason: reason,
				size: blob.size,
				durationMs: durationMs,
			});
			postToGame("bodycamRecordingUpload", {
				fileName: `bodycam-${Date.now()}.webm`,
				fileData: fileData,
				size: blob.size,
				durationMs: durationMs,
				sourceType: session.sourceType,
				trigger: session.trigger,
				stopReason: reason,
				metadata: session.metadata,
			});
		}

		async function stopSession(reason) {
			const session = state.recordingSession;
			if (!session) {
				return false;
			}
			if (session.stopTimer) {
				clearTimeout(session.stopTimer);
			}
			state.recordingSession = null;

			const selectedChunks = state.chunks.filter(function (chunk) {
				return chunk.timestamp >= (session.captureStartAt - TIMESLICE_MS) && chunk.timestamp <= (session.captureStopAt + TIMESLICE_MS);
			});
			if (!selectedChunks.length) {
				notifyState({
					state: "failed",
					reason: "no_data",
					sourceType: session.sourceType,
					trigger: session.trigger,
				});
				return false;
			}

			let durationMs = 0;
			let totalSize = 0;
			selectedChunks.forEach(function (chunk) {
				durationMs += chunk.durationMs || TIMESLICE_MS;
				totalSize += chunk.size || 0;
			});
			durationMs = Math.max(1, Math.min(MAX_DURATION_MS, Math.min(durationMs, session.totalDurationMs)));
			if (durationMs < 1 || durationMs > MAX_DURATION_MS) {
				notifyState({
					state: "failed",
					reason: "invalid_duration",
					sourceType: session.sourceType,
					trigger: session.trigger,
					durationMs: durationMs,
				});
				return false;
			}

			notifyState({
				state: "stopped",
				reason: reason,
				sourceType: session.sourceType,
				trigger: session.trigger,
				durationMs: durationMs,
				size: totalSize,
			});

			const clipBlob = new Blob(
				selectedChunks.map(function (chunk) {
					return chunk.blob;
				}),
				{ type: getMimeType() }
			);
			session.totalDurationMs = durationMs;
			await uploadClip(clipBlob, session, reason);
			trimChunks();
			return true;
		}

		async function startSession(message) {
			if (!state.sourceStream) {
				notifyState({
					state: "failed",
					reason: "bodycam_inactive",
					sourceType: message.sourceType || "manual",
					trigger: message.trigger || null,
				});
				return false;
			}
			if (state.recordingSession) {
				notifyState({
					state: "ignored",
					reason: "already_recording",
					sourceType: message.sourceType || "manual",
					trigger: message.trigger || null,
				});
				return false;
			}
			if (!startContinuousRecorder()) {
				notifyState({
					state: "failed",
					reason: "pipeline_unavailable",
					sourceType: message.sourceType || "manual",
					trigger: message.trigger || null,
				});
				return false;
			}

			const session = buildSession(message);
			state.recordingSession = session;
			session.stopTimer = setTimeout(function () {
				stopSession("auto_stop");
			}, session.liveDurationMs);

			notifyState({
				state: "started",
				sourceType: session.sourceType,
				trigger: session.trigger,
				shadowDurationMs: session.shadowDurationMs,
				liveDurationMs: session.liveDurationMs,
				totalDurationMs: session.totalDurationMs,
			});
			return true;
		}

		async function control(message) {
			if (!message || typeof message !== "object") {
				return;
			}
			if (message.config && typeof message.config === "object") {
				state.config = { ...state.config, ...message.config };
			}
			if (message.action === "start") {
				await startSession(message);
			} else if (message.action === "stop") {
				await stopSession(message.reason || "manual_stop");
			}
		}

		return {
			setSourceStream: setSourceStream,
			control: control,
		};
	}

	window.BodycamRecordingManager = createRecorder();
})();
