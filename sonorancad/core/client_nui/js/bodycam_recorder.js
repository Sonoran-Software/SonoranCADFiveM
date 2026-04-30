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
	const MAX_DURATION_MS = 120000;
	const INTERNAL_UPLOAD_BASE64_CHUNK_SIZE = 4 * 1024;

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

	function postToGame(endpoint, payload) {
		return fetch(`https://${GetParentResourceName()}/${endpoint}`, {
			method: "POST",
			headers: { "Content-Type": "application/json; charset=UTF-8" },
			body: JSON.stringify(payload || {}),
		})
			.then(function (response) {
				logRecorder("info", "Posted recorder event to game.", {
					endpoint: endpoint,
					ok: !!(response && response.ok),
					status: response && typeof response.status === "number" ? response.status : null,
					state: payload && payload.state ? payload.state : null,
					action: payload && payload.action ? payload.action : null,
					reason: payload && payload.reason ? payload.reason : null,
				});
				return response;
			})
			.catch(function (err) {
				logRecorder("error", "Failed to post recorder event to game.", {
					endpoint: endpoint,
					state: payload && payload.state ? payload.state : null,
					action: payload && payload.action ? payload.action : null,
					reason: payload && payload.reason ? payload.reason : null,
					error: err && err.message ? err.message : String(err),
				});
				throw err;
			});
	}

	function logRecorder(level, message, details) {
		const payload = details && typeof details === "object" ? details : undefined;
		if (level === "error") {
			console.error("[bodycam-recorder] " + message, payload || "");
			return;
		}
		if (level === "warn") {
			console.warn("[bodycam-recorder] " + message, payload || "");
			return;
		}
		console.info("[bodycam-recorder] " + message, payload || "");
	}

	async function readJsonResponse(response) {
		const text = await response.text();
		if (!text) {
			return { text: "", json: null };
		}
		try {
			return {
				text: text,
				json: JSON.parse(text),
			};
		} catch (err) {
			return {
				text: text,
				json: null,
			};
		}
	}

	function hasWebmEbmlHeader(bytes) {
		return !!(
			bytes &&
			bytes.length >= 4 &&
			bytes[0] === 0x1a &&
			bytes[1] === 0x45 &&
			bytes[2] === 0xdf &&
			bytes[3] === 0xa3
		);
	}

	function uint8ArrayToBase64(bytes) {
		let binary = "";
		const chunkSize = 0x8000;
		for (let index = 0; index < bytes.length; index += chunkSize) {
			const chunk = bytes.subarray(index, Math.min(index + chunkSize, bytes.length));
			for (let offset = 0; offset < chunk.length; offset += 1) {
				binary += String.fromCharCode(chunk[offset]);
			}
		}
		return btoa(binary);
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
			renderTimer: null,
			recordingSession: null,
			pipelineReady: false,
			uploadConfig: {
				proxyUrl: null,
				uploadToken: null,
			},
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
		}

		function notifyState(payload) {
			logRecorder("info", "Recorder state change.", payload);
			postToGame("bodycamRecordingState", payload);
		}

		function buildValidationResult(session, selectedChunks, durationMs, totalSize, clipBlob) {
			if (!Array.isArray(selectedChunks) || selectedChunks.length < 1) {
				return { ok: false, reason: "no_data" };
			}
			if (!Number.isFinite(durationMs) || durationMs < 1 || durationMs > MAX_DURATION_MS) {
				return { ok: false, reason: "invalid_duration" };
			}
			if (!Number.isFinite(totalSize) || totalSize < 1) {
				return { ok: false, reason: "empty_clip" };
			}
			if (!clipBlob || !Number.isFinite(clipBlob.size) || clipBlob.size < 1) {
				return { ok: false, reason: "empty_blob" };
			}
			if (clipBlob.size > state.config.maxFileSizeBytes) {
				return { ok: false, reason: "clip_too_large" };
			}
			return {
				ok: true,
				chunkCount: selectedChunks.length,
				durationMs: durationMs,
				totalSize: totalSize,
				blobSize: clipBlob.size,
				mimeType: clipBlob.type || getMimeType(),
				sourceType: session.sourceType,
				trigger: session.trigger,
			};
		}

		function buildSession(message) {
			const shadowDurationMs = getShadowDurationMs();
			const maxClipMs = Math.min(getMaxClipMs(), MAX_DURATION_MS);
			const requestedLiveMs = clamp(state.config.liveClipSeconds, 1, 120, DEFAULTS.liveClipSeconds) * 1000;
			const liveDurationMs = Math.max(1, Math.min(requestedLiveMs, maxClipMs - shadowDurationMs));
			const totalDurationMs = Math.min(maxClipMs, shadowDurationMs + liveDurationMs);
			const startedAt = nowMs();
			return {
				sourceType: message.sourceType || "manual",
				trigger: message.trigger || null,
				metadata: clonePayload(message.metadata),
				startedAt: startedAt,
				shadowDurationMs: shadowDurationMs,
				liveDurationMs: liveDurationMs,
				totalDurationMs: totalDurationMs,
				captureStartAt: startedAt,
				captureStopAt: startedAt + liveDurationMs,
				stopTimer: null,
				recordedChunks: [],
				mediaRecorder: null,
				stopPromise: null,
				stopResolve: null,
			};
		}

		function startClipRecorder(session) {
			if (!state.pipelineReady && !buildExportStream()) {
				return false;
			}
			const recorder = new MediaRecorder(state.exportStream, {
				mimeType: getMimeType(),
				videoBitsPerSecond: clamp(state.config.videoBitrate, 64000, 2500000, DEFAULTS.videoBitrate),
				audioBitsPerSecond: clamp(state.config.audioBitrate, 16000, 256000, DEFAULTS.audioBitrate),
			});
			session.stopPromise = new Promise(function (resolve) {
				session.stopResolve = resolve;
			});
			recorder.ondataavailable = function (event) {
				if (!event.data || event.data.size <= 0) {
					return;
				}
				session.recordedChunks.push(event.data);
			};
			recorder.onstop = function () {
				if (session.stopResolve) {
					session.stopResolve();
				}
			};
			recorder.start();
			session.mediaRecorder = recorder;
			return true;
		}

		async function uploadClip(blob, session, reason) {
			const durationMs = Math.max(1, Math.min(MAX_DURATION_MS, Math.round(session.totalDurationMs)));
			if (blob.size > state.config.maxFileSizeBytes) {
				logRecorder("warn", "Finalized clip rejected before upload: clip too large.", {
					size: blob.size,
					maxFileSizeBytes: state.config.maxFileSizeBytes,
					sourceType: session.sourceType,
					trigger: session.trigger,
					reason: reason,
				});
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
			logRecorder("info", "Finalized clip accepted. Uploading bodycam recording.", {
				size: blob.size,
				durationMs: durationMs,
				sourceType: session.sourceType,
				trigger: session.trigger,
				reason: reason,
				mimeType: blob.type || getMimeType(),
			});
			notifyState({
				state: "uploading",
				sourceType: session.sourceType,
				trigger: session.trigger,
				reason: reason,
				size: blob.size,
				durationMs: durationMs,
			});
			try {
				const fileName = `bodycam-${Date.now()}.webm`;
				const uploadId = `bodycam-upload-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
				const arrayBuffer = await blob.arrayBuffer();
				const fileBytes = new Uint8Array(arrayBuffer);
				if (!hasWebmEbmlHeader(fileBytes)) {
					logRecorder("error", "Finalized clip has invalid WebM header before upload.", {
						firstBytes: Array.from(fileBytes.subarray(0, 16)).map(function (value) {
							return value.toString(16).padStart(2, "0");
						}).join(""),
						size: blob.size,
						sourceType: session.sourceType,
						trigger: session.trigger,
					});
					notifyState({
						state: "failed",
						reason: "invalid_file_header_client",
						sourceType: session.sourceType,
						trigger: session.trigger,
						size: blob.size,
						durationMs: durationMs,
					});
					return;
				}
				const base64Data = uint8ArrayToBase64(fileBytes);
				if (!base64Data) {
					notifyState({
						state: "failed",
						reason: "base64_encode_failed",
						sourceType: session.sourceType,
						trigger: session.trigger,
						size: blob.size,
						durationMs: durationMs,
					});
					return;
				}
				const totalChunks = Math.max(1, Math.ceil(base64Data.length / INTERNAL_UPLOAD_BASE64_CHUNK_SIZE));
				const initResponse = await postToGame("bodycamRecordingUploadInit", {
					uploadId: uploadId,
					fileName: fileName,
					size: blob.size,
					durationMs: durationMs,
					sourceType: session.sourceType,
					trigger: session.trigger,
					stopReason: reason,
					metadata: session.metadata || {},
					totalChunks: totalChunks,
				});
				const initPayload = await readJsonResponse(initResponse);
				logRecorder("info", "Internal bodycam upload init completed.", {
					ok: !!(initResponse && initResponse.ok),
					status: initResponse && typeof initResponse.status === "number" ? initResponse.status : null,
					responseText: initPayload.text || "",
					uploadId: uploadId,
					totalChunks: totalChunks,
				});
				if (!initResponse.ok || !uploadId) {
					notifyState({
						state: "failed",
						reason: "upload_request_failed",
						sourceType: session.sourceType,
						trigger: session.trigger,
						size: blob.size,
						durationMs: durationMs,
						uploadStatus: initResponse && typeof initResponse.status === "number" ? initResponse.status : null,
						uploadResponse: initPayload.text || "",
					});
					return;
				}

				for (let chunkIndex = 0; chunkIndex < totalChunks; chunkIndex += 1) {
					const start = chunkIndex * INTERNAL_UPLOAD_BASE64_CHUNK_SIZE;
					const end = Math.min(start + INTERNAL_UPLOAD_BASE64_CHUNK_SIZE, base64Data.length);
					const base64Chunk = base64Data.slice(start, end);
					const chunkResponse = await postToGame("bodycamRecordingUploadChunk", {
						uploadId: uploadId,
						chunkIndex: chunkIndex + 1,
						base64Chunk: base64Chunk,
					});
					const chunkPayload = await readJsonResponse(chunkResponse);
					if (!chunkResponse.ok) {
						logRecorder("warn", "Internal bodycam upload chunk failed.", {
							uploadId: uploadId,
							chunkIndex: chunkIndex + 1,
							totalChunks: totalChunks,
							status: chunkResponse.status,
							responseText: chunkPayload.text || "",
						});
						notifyState({
							state: "failed",
							reason: "upload_chunk_failed",
							sourceType: session.sourceType,
							trigger: session.trigger,
							size: blob.size,
							durationMs: durationMs,
							uploadStatus: chunkResponse.status,
							uploadResponse: chunkPayload.text || "",
						});
						return;
					}
				}

				const completeResponse = await postToGame("bodycamRecordingUploadComplete", {
					uploadId: uploadId,
				});
				const completePayload = await readJsonResponse(completeResponse);
				logRecorder("info", "Internal bodycam upload complete request finished.", {
					ok: !!(completeResponse && completeResponse.ok),
					status: completeResponse && typeof completeResponse.status === "number" ? completeResponse.status : null,
					responseText: completePayload.text || "",
					uploadId: uploadId,
				});
				if (!completeResponse.ok) {
					notifyState({
						state: "failed",
						reason: "upload_complete_failed",
						sourceType: session.sourceType,
						trigger: session.trigger,
						size: blob.size,
						durationMs: durationMs,
						uploadStatus: completeResponse && typeof completeResponse.status === "number" ? completeResponse.status : null,
						uploadResponse: completePayload.text || "",
					});
				}
			} catch (err) {
				logRecorder("error", "Direct bodycam upload request failed.", {
					error: err && err.message ? err.message : String(err),
					sourceType: session.sourceType,
					trigger: session.trigger,
				});
				notifyState({
					state: "failed",
					reason: "upload_request_exception",
					sourceType: session.sourceType,
					trigger: session.trigger,
					size: blob.size,
					durationMs: durationMs,
					uploadResponse: err && err.message ? err.message : String(err),
				});
			}
		}

		async function stopSession(reason) {
			const session = state.recordingSession;
			if (!session) {
				logRecorder("warn", "Stop requested with no active recording session.", { reason: reason });
				return false;
			}
			logRecorder("info", "Stopping recording session.", {
				reason: reason,
				sourceType: session.sourceType,
				trigger: session.trigger,
				captureStartAt: session.captureStartAt,
				captureStopAt: session.captureStopAt,
				totalDurationMs: session.totalDurationMs,
			});
			if (session.stopTimer) {
				clearTimeout(session.stopTimer);
			}
			state.recordingSession = null;

			if (session.mediaRecorder && session.mediaRecorder.state !== "inactive") {
				try {
					session.mediaRecorder.stop();
				} catch (err) {}
			}
			if (session.stopPromise) {
				await session.stopPromise;
			}
			if (!session.recordedChunks.length) {
				logRecorder("warn", "Recording stop validation failed: no chunks available for final clip.", {
					sourceType: session.sourceType,
					trigger: session.trigger,
					reason: reason,
				});
				notifyState({
					state: "failed",
					reason: "no_data",
					sourceType: session.sourceType,
					trigger: session.trigger,
				});
				return false;
			}

			const durationMs = Math.max(1, Math.min(MAX_DURATION_MS, Math.min(nowMs() - session.startedAt, session.totalDurationMs)));
			let totalSize = 0;
			session.recordedChunks.forEach(function (chunk) {
				totalSize += chunk.size || 0;
			});
			if (durationMs < 1 || durationMs > MAX_DURATION_MS) {
				logRecorder("warn", "Recording stop validation failed: invalid duration.", {
					sourceType: session.sourceType,
					trigger: session.trigger,
					reason: reason,
					durationMs: durationMs,
				});
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
				session.recordedChunks,
				{ type: getMimeType() }
			);
			const validation = buildValidationResult(session, session.recordedChunks, durationMs, totalSize, clipBlob);
			if (!validation.ok) {
				logRecorder("warn", "Recording stop validation failed.", {
					sourceType: session.sourceType,
					trigger: session.trigger,
					reason: reason,
					validationReason: validation.reason,
					durationMs: durationMs,
					totalSize: totalSize,
					chunkCount: session.recordedChunks.length,
					blobSize: clipBlob.size,
				});
				notifyState({
					state: "failed",
					reason: validation.reason,
					sourceType: session.sourceType,
					trigger: session.trigger,
					durationMs: durationMs,
					size: totalSize,
				});
				return false;
			}
			logRecorder("info", "Recording ended and passed validation.", {
				sourceType: validation.sourceType,
				trigger: validation.trigger,
				reason: reason,
				durationMs: validation.durationMs,
				totalSize: validation.totalSize,
				blobSize: validation.blobSize,
				chunkCount: validation.chunkCount,
				mimeType: validation.mimeType,
			});
			session.totalDurationMs = durationMs;
			await uploadClip(clipBlob, session, reason);
			return true;
		}

		async function startSession(message) {
			logRecorder("info", "Start session requested.", {
				sourceType: message && message.sourceType ? message.sourceType : null,
				trigger: message && message.trigger ? message.trigger : null,
				reason: message && message.reason ? message.reason : null,
				hasSourceStream: !!state.sourceStream,
				pipelineReady: state.pipelineReady,
			});
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
			if (!state.pipelineReady && !buildExportStream()) {
				notifyState({
					state: "failed",
					reason: "pipeline_unavailable",
					sourceType: message.sourceType || "manual",
					trigger: message.trigger || null,
				});
				return false;
			}

			const session = buildSession(message);
			if (!startClipRecorder(session)) {
				notifyState({
					state: "failed",
					reason: "pipeline_unavailable",
					sourceType: message.sourceType || "manual",
					trigger: message.trigger || null,
				});
				return false;
			}
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
				logRecorder("warn", "Recorder control ignored: invalid message.", { messageType: typeof message });
				return;
			}
			logRecorder("info", "Recorder control received.", {
				action: message.action || null,
				sourceType: message.sourceType || null,
				trigger: message.trigger || null,
				reason: message.reason || null,
			});
			if (message.config && typeof message.config === "object") {
				state.config = { ...state.config, ...message.config };
			}
			if (message.action === "start") {
				await startSession(message);
			} else if (message.action === "stop") {
				await stopSession(message.reason || "manual_stop");
			}
		}

		function setUploadConfig(message) {
			const nextProxyUrl = message && Object.prototype.hasOwnProperty.call(message, "proxyUrl")
				? (message.proxyUrl || null)
				: state.uploadConfig.proxyUrl;
			const nextUploadToken = message && Object.prototype.hasOwnProperty.call(message, "uploadToken")
				? (message.uploadToken || null)
				: state.uploadConfig.uploadToken;
			state.uploadConfig = {
				proxyUrl: nextProxyUrl,
				uploadToken: nextUploadToken,
			};
			logRecorder("info", "Recorder upload config updated.", {
				hasProxyUrl: !!state.uploadConfig.proxyUrl,
				hasUploadToken: !!state.uploadConfig.uploadToken,
			});
		}

		return {
			setSourceStream: setSourceStream,
			control: control,
			setUploadConfig: setUploadConfig,
		};
	}

	window.BodycamRecordingManager = createRecorder();
})();
