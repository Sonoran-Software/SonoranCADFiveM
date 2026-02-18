// CfxTexture -> WebGLRenderTarget -> readRenderTargetPixels -> 2D canvas (screenshot-basic style).
(function () {
	"use strict";

	function createGameRenderer() {
		const THREE = window.THREE;
		if (!THREE) {
			console.error("Bodycam renderer: THREE not available. Load @citizenfx/three first.");
			return null;
		}
		if (typeof THREE.CfxTexture !== "function") {
			console.error("Bodycam renderer: CfxTexture not available on THREE.");
			return null;
		}

		const app = document.getElementById("app");
		const captureCanvas = document.getElementById("bodycamStreamCanvas");
		if (!captureCanvas) {
			console.error("Bodycam renderer: #bodycamStreamCanvas not found.");
			return null;
		}
		const ctx = captureCanvas.getContext("2d", { alpha: false });
		if (!ctx) {
			console.error("Bodycam renderer: 2D context unavailable.");
			return null;
		}

		let renderer = null;
		let rtTexture = null;
		let sceneRTT = null;
		let cameraRTT = null;
		let material = null;
		let quad = null;
		let width = 0;
		let height = 0;
		let pixelBuffer = null;
		let imageData = null;
		let running = false;
		let rafId = 0;
		let requestFrameTrack = null;
		let lastFrameTime = 0;
		let frameIntervalMs = 0;
		let renderErrorLogged = false;
		let loggedNonZero = false;

		function buildScene() {
			cameraRTT = new THREE.OrthographicCamera(
				window.innerWidth / -2,
				window.innerWidth / 2,
				window.innerHeight / 2,
				window.innerHeight / -2,
				-10000,
				10000
			);
			cameraRTT.position.z = 100;

			sceneRTT = new THREE.Scene();
			const plane = new THREE.PlaneBufferGeometry(window.innerWidth, window.innerHeight);
			quad = new THREE.Mesh(plane, material);
			quad.position.z = -100;
			sceneRTT.add(quad);
		}

		function resize(targetWidth, targetHeight) {
			width = targetWidth || window.innerWidth;
			height = targetHeight || window.innerHeight;
			if (width < 1) {
				width = 1;
			}
			if (height < 1) {
				height = 1;
			}
			if (!renderer) {
				renderer = new THREE.WebGLRenderer();
				renderer.setPixelRatio(window.devicePixelRatio);
				renderer.autoClear = false;
				if (app) {
					renderer.domElement.style.position = "absolute";
					renderer.domElement.style.left = "-10000px";
					renderer.domElement.style.top = "-10000px";
					renderer.domElement.style.width = "1px";
					renderer.domElement.style.height = "1px";
					renderer.domElement.style.opacity = "0";
					app.appendChild(renderer.domElement);
				}
			}

			if (!material) {
				const gameTexture = new THREE.CfxTexture();
				gameTexture.needsUpdate = true;
				material = new THREE.ShaderMaterial({
					uniforms: {
						tDiffuse: { value: gameTexture },
					},
					vertexShader: [
						"varying vec2 vUv;",
						"void main() {",
						"  vUv = vec2(uv.x, 1.0-uv.y);",
						"  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);",
						"}",
					].join("\n"),
					fragmentShader: [
						"varying vec2 vUv;",
						"uniform sampler2D tDiffuse;",
						"void main() {",
						"  gl_FragColor = texture2D(tDiffuse, vUv);",
						"}",
					].join("\n"),
				});
			}

			buildScene();
			rtTexture = new THREE.WebGLRenderTarget(width, height, {
				minFilter: THREE.LinearFilter,
				magFilter: THREE.NearestFilter,
				format: THREE.RGBAFormat,
				type: THREE.UnsignedByteType,
			});
			renderer.setSize(width, height);
			captureCanvas.width = width;
			captureCanvas.height = height;
			pixelBuffer = new Uint8Array(width * height * 4);
			imageData = ctx.createImageData(width, height);
			loggedNonZero = false;
		}

		function renderFrame() {
			if (!renderer || !sceneRTT || !cameraRTT || !rtTexture) {
				return;
			}
			renderer.clear();
			renderer.render(sceneRTT, cameraRTT, rtTexture, true);
			renderer.readRenderTargetPixels(rtTexture, 0, 0, width, height, pixelBuffer);
			imageData.data.set(pixelBuffer);
			ctx.putImageData(imageData, 0, 0);
			if (!loggedNonZero) {
				for (let i = 0; i < pixelBuffer.length; i += 16) {
					if (pixelBuffer[i] !== 0 || pixelBuffer[i + 1] !== 0 || pixelBuffer[i + 2] !== 0) {
						loggedNonZero = true;
						break;
					}
				}
				if (!loggedNonZero) {
					console.warn("Bodycam renderer: frame buffer still empty.");
				}
			}
		}

		function renderLoop(time) {
			if (!running) {
				return;
			}
			if (frameIntervalMs > 0 && time - lastFrameTime < frameIntervalMs) {
				rafId = requestAnimationFrame(renderLoop);
				return;
			}
			lastFrameTime = time;
			try {
				renderFrame();
				if (requestFrameTrack && typeof requestFrameTrack.requestFrame === "function") {
					requestFrameTrack.requestFrame();
				}
			} catch (err) {
				if (!renderErrorLogged) {
					renderErrorLogged = true;
					console.error("Bodycam renderer: render loop error.", err);
				}
				stop();
				return;
			}
			rafId = requestAnimationFrame(renderLoop);
		}

		function start(fps) {
			if (running) {
				return;
			}
			frameIntervalMs = fps ? 1000 / fps : 0;
			lastFrameTime = 0;
			resize(window.innerWidth, window.innerHeight);
			running = true;
			rafId = requestAnimationFrame(renderLoop);
		}

		function stop() {
			running = false;
			if (rafId) {
				cancelAnimationFrame(rafId);
				rafId = 0;
			}
		}

		function setVideoTrack(track) {
			requestFrameTrack = track || null;
		}

		window.addEventListener("resize", function () {
			if (running) {
				resize(window.innerWidth, window.innerHeight);
			}
		});
		return {
			start: start,
			stop: stop,
			getCanvas: function () {
				return captureCanvas;
			},
			setVideoTrack: setVideoTrack,
		};
	}

	function init() {
		window.BodycamGameRenderer = createGameRenderer();
	}

	if (document.readyState === "loading") {
		document.addEventListener("DOMContentLoaded", init);
	} else {
		init();
	}
})();
