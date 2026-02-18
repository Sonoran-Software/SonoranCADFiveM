// Lightweight helpers for finding canvases and recording them.
(function () {
	"use strict";

	function safeGetContext(canvas, type) {
		try {
			if (!canvas || typeof canvas.getContext !== "function") {
				return null;
			}
			return canvas.getContext(type);
		} catch (err) {
			return null;
		}
	}

	function getContextTypes(canvas) {
		const types = {
			webgl2: false,
			webgl: false,
			"2d": false,
		};
		if (!canvas) {
			return types;
		}
		if (safeGetContext(canvas, "webgl2")) {
			types.webgl2 = true;
		}
		if (safeGetContext(canvas, "webgl")) {
			types.webgl = true;
		}
		if (safeGetContext(canvas, "2d")) {
			types["2d"] = true;
		}
		return types;
	}

	function listCanvases() {
		const canvases = Array.from(document.querySelectorAll("canvas"));
		return canvases.map(function (canvas, index) {
			const rect = canvas.getBoundingClientRect ? canvas.getBoundingClientRect() : { width: 0, height: 0 };
			const types = getContextTypes(canvas);
			return {
				index: index,
				canvas: canvas,
				id: canvas.id || "",
				className: canvas.className || "",
				width: canvas.width || 0,
				height: canvas.height || 0,
				rectWidth: Math.round(rect.width || 0),
				rectHeight: Math.round(rect.height || 0),
				webgl2: types.webgl2,
				webgl: types.webgl,
				"2d": types["2d"],
				visible: rect.width > 0 && rect.height > 0,
			};
		});
	}

	function logCanvases() {
		const list = listCanvases().map(function (entry) {
			return {
				index: entry.index,
				id: entry.id,
				className: entry.className,
				width: entry.width,
				height: entry.height,
				rectWidth: entry.rectWidth,
				rectHeight: entry.rectHeight,
				webgl2: entry.webgl2,
				webgl: entry.webgl,
				"2d": entry["2d"],
				visible: entry.visible,
			};
		});
		if (list.length === 0) {
			console.warn("CanvasDiscovery: no canvases found.");
			return;
		}
		console.table(list);
	}

	function selectCanvas(options) {
		const opts = options || {};
		const list = listCanvases();
		if (!list.length) {
			console.error("CanvasDiscovery: no canvases found.");
			return null;
		}

		if (opts.id) {
			const match = list.find(function (entry) {
				return entry.id === opts.id;
			});
			if (!match) {
				console.error("CanvasDiscovery: canvas id not found:", opts.id);
				logCanvases();
				return null;
			}
			return match.canvas;
		}

		const preferWebgl = opts.preferWebgl !== false;
		const candidates = preferWebgl
			? list.filter(function (entry) {
					return entry.webgl2 || entry.webgl;
			  })
			: list.slice();

		if (!candidates.length) {
			console.error("CanvasDiscovery: no WebGL canvases found.");
			logCanvases();
			return null;
		}

		let best = candidates[0];
		let bestScore = 0;
		candidates.forEach(function (entry) {
			const area = (entry.rectWidth || entry.width) * (entry.rectHeight || entry.height);
			if (area > bestScore) {
				bestScore = area;
				best = entry;
			}
		});
		return best.canvas;
	}

	function createSilentAudioTrack(audioContext, destination) {
		if (!audioContext || !destination) {
			return null;
		}
		const oscillator = audioContext.createOscillator();
		const gain = audioContext.createGain();
		gain.gain.value = 0;
		oscillator.connect(gain).connect(destination);
		oscillator.start();
		return { oscillator: oscillator, gain: gain };
	}

	class CanvasRecorder {
		constructor(options) {
			const opts = options || {};
			this.mimeType = opts.mimeType || "video/webm;codecs=vp9,opus";
			this.videoBitsPerSecond = opts.videoBitsPerSecond || 8000000;
			this.timesliceMs = opts.timesliceMs || 1000;
			this.mediaRecorder = null;
			this.chunks = [];
			this.videoStream = null;
			this.audioContext = null;
			this.audioDestination = null;
			this.micStream = null;
			this.silentAudio = null;
			this.combinedStream = null;
		}

		async startRecording(canvas, fps, withAudio) {
			const targetCanvas = canvas;
			if (!targetCanvas || typeof targetCanvas.captureStream !== "function") {
				throw new Error("CanvasRecorder: canvas.captureStream is unavailable.");
			}
			if (this.mediaRecorder && this.mediaRecorder.state !== "inactive") {
				throw new Error("CanvasRecorder: recorder already active.");
			}

			this.videoStream = targetCanvas.captureStream(fps || 30);
			const videoTracks = this.videoStream.getVideoTracks();
			if (!videoTracks.length) {
				throw new Error("CanvasRecorder: no video track available.");
			}

			let audioTrack = null;
			if (withAudio !== false) {
				try {
					const AudioContextCtor = window.AudioContext || window.webkitAudioContext;
					if (!AudioContextCtor) {
						console.warn("CanvasRecorder: AudioContext not available; recording video only.");
					} else {
						this.audioContext = new AudioContextCtor();
						this.audioDestination = this.audioContext.createMediaStreamDestination();
						if (navigator.mediaDevices && typeof navigator.mediaDevices.getUserMedia === "function") {
							try {
								this.micStream = await navigator.mediaDevices.getUserMedia({ audio: true });
								const micSource = this.audioContext.createMediaStreamSource(this.micStream);
								micSource.connect(this.audioDestination);
							} catch (err) {
								console.error("CanvasRecorder: microphone capture failed.", err);
							}
						}
						if (this.audioDestination.stream.getAudioTracks().length === 0) {
							this.silentAudio = createSilentAudioTrack(this.audioContext, this.audioDestination);
						}
						if (this.audioContext.state === "suspended") {
							await this.audioContext.resume();
						}
						audioTrack = this.audioDestination.stream.getAudioTracks()[0] || null;
					}
				} catch (err) {
					console.error("CanvasRecorder: audio setup failed.", err);
				}
			}

			const tracks = audioTrack ? [audioTrack, videoTracks[0]] : [videoTracks[0]];
			this.combinedStream = new MediaStream(tracks);
			this.chunks = [];
			this.mediaRecorder = new MediaRecorder(this.combinedStream, {
				mimeType: this.mimeType,
				videoBitsPerSecond: this.videoBitsPerSecond,
			});
			this.mediaRecorder.ondataavailable = (event) => {
				if (event.data && event.data.size > 0) {
					this.chunks.push(event.data);
				}
			};
			this.mediaRecorder.start(this.timesliceMs);
			return this.mediaRecorder;
		}

		stopRecording() {
			const recorder = this.mediaRecorder;
			if (!recorder) {
				return Promise.resolve(null);
			}
			return new Promise((resolve) => {
				recorder.onstop = () => {
					const blob = new Blob(this.chunks, { type: this.mimeType || "video/webm" });
					this.destroy();
					resolve(blob);
				};
				if (recorder.state !== "inactive") {
					recorder.stop();
				} else {
					const blob = new Blob(this.chunks, { type: this.mimeType || "video/webm" });
					this.destroy();
					resolve(blob);
				}
			});
		}

		destroy() {
			if (this.mediaRecorder && this.mediaRecorder.state !== "inactive") {
				try {
					this.mediaRecorder.stop();
				} catch (err) {}
			}
			this.mediaRecorder = null;
			if (this.combinedStream) {
				this.combinedStream.getTracks().forEach((track) => track.stop());
			}
			if (this.videoStream) {
				this.videoStream.getTracks().forEach((track) => track.stop());
			}
			if (this.micStream) {
				this.micStream.getTracks().forEach((track) => track.stop());
			}
			if (this.silentAudio && this.silentAudio.oscillator) {
				try {
					this.silentAudio.oscillator.stop();
				} catch (err) {}
			}
			if (this.audioContext) {
				try {
					this.audioContext.close();
				} catch (err) {}
			}
			this.audioContext = null;
			this.audioDestination = null;
			this.micStream = null;
			this.silentAudio = null;
			this.videoStream = null;
			this.combinedStream = null;
			this.chunks = [];
		}
	}

	window.CanvasDiscovery = {
		listCanvases: listCanvases,
		logCanvases: logCanvases,
		selectCanvas: selectCanvas,
		getContextTypes: getContextTypes,
	};

	window.CanvasRecorder = CanvasRecorder;
})();
