var pdfLink = "";
var firstView = false;
var isOpen = false;
var isMinimized = false;
var isFullscreen = false;

$(function () {
	var $wrapper = $("#wrapper");
	var $pdfWindow = $("#pdfWindow");
	var $pdfViewer = $("#pdfViewer");
	var $statusText = $("#statusText");
	var $minimizeBtn = $("#minimizeBtn");
	var $fullscreenBtn = $("#fullscreenBtn");
	var $closeBtn = $("#closeBtn");
	var pdfRenderToken = 0;
	var pdfLoadingTask = null;
	function notifyMinimizeChanged() {
		try {
			$.post("https://sonorancad/RecordPrinter:MinimizeChanged", JSON.stringify({ minimized: isMinimized }));
		} catch (err) {
			console.warn("recordPrinter: WRN-CORE-900 failed to notify minimize state. More: https://sonorancad.com/error/WRN-CORE-900", err);
		}
	}

	function clearPdfViewer(message, isError) {
		$pdfViewer.empty();
		var $message = $("<div>")
			.addClass(isError ? "pdf-error" : "pdf-placeholder")
			.text(message || "No record selected.");
		$pdfViewer.append($message);
	}

	function cancelCurrentRender() {
		if (pdfLoadingTask && typeof pdfLoadingTask.destroy === "function") {
			try {
				pdfLoadingTask.destroy();
			} catch (err) {
				console.warn("recordPrinter: WRN-CORE-900 failed to cancel existing PDF task. More: https://sonorancad.com/error/WRN-CORE-900", err);
			}
		}
		pdfLoadingTask = null;
	}

	function renderDocumentPages(pdf, token) {
		var renderPromise = Promise.resolve();

		function renderPage(pageNumber) {
			if (token !== pdfRenderToken) {
				return Promise.resolve();
			}

			return pdf.getPage(pageNumber).then(function (page) {
				if (token !== pdfRenderToken) {
					return;
				}

				var containerWidth = $pdfViewer.innerWidth() || 600;
				var baseViewport = page.getViewport({ scale: 1 });
				var scale = Math.min(Math.max(containerWidth / baseViewport.width, 0.9), 2.4);
				var viewport = page.getViewport({ scale: scale });

				var $pageWrapper = $("<div>").addClass("pdf-page");
				var canvas = document.createElement("canvas");
				canvas.className = "pdf-canvas";
				canvas.width = viewport.width;
				canvas.height = viewport.height;
				$pageWrapper.append(canvas);
				$pdfViewer.append($pageWrapper);

				var context = canvas.getContext("2d", { alpha: false });
				return page
					.render({ canvasContext: context, viewport: viewport })
					.promise.catch(function (err) {
						console.warn("recordPrinter: ERR-CORE-906 failed to render page. More: https://sonorancad.com/error/ERR-CORE-906");
						if (token === pdfRenderToken) {
							$pageWrapper.empty().append(
								$("<div>")
									.addClass("pdf-error")
									.text("Unable to render page " + pageNumber + ".")
							);
						}
					});
			});
		}

		for (var pageNum = 1; pageNum <= pdf.numPages; pageNum++) {
			(function (number) {
				renderPromise = renderPromise.then(function () {
					return renderPage(number);
				});
			})(pageNum);
		}

		return renderPromise
			.then(function () {
				if (token === pdfRenderToken) {
					$pdfViewer.scrollTop(0);
				}
			})
			.finally(function () {
				try {
					pdf.cleanup();
				} catch (cleanupErr) {
					console.warn("recordPrinter: WRN-CORE-900 cleanup warning. More: https://sonorancad.com/error/WRN-CORE-900", cleanupErr);
				}
				return pdf.destroy();
			});
	}

	function updateStatusText() {
		if (!isOpen) {
			$statusText.text("");
			return;
		}

		if (isMinimized) {
			$statusText.text("Press Backspace to restore.");
		} else if (isFullscreen) {
			$statusText.text("Scroll to view the record. Backspace to minimize, ESC to close.");
		} else {
			$statusText.text("Press Backspace to minimize, ESC to close.");
		}
	}

	function applyWindowState() {
		var shouldFullscreen = isFullscreen && !isMinimized;
		$pdfWindow.toggleClass("minimized", isMinimized);
		$pdfWindow.toggleClass("fullscreen", shouldFullscreen);

		$minimizeBtn.attr("title", isMinimized ? "Restore" : "Minimize");
		$minimizeBtn.attr("aria-label", isMinimized ? "Restore Window" : "Minimize Window");

		$fullscreenBtn.attr("title", shouldFullscreen ? "Exit Fullscreen" : "Fullscreen");
		$fullscreenBtn.attr("aria-label", shouldFullscreen ? "Exit Fullscreen" : "Enter Fullscreen");

		$fullscreenBtn.find(".icon")
			.toggleClass("icon-maximize", !shouldFullscreen)
			.toggleClass("icon-restore", shouldFullscreen);

		updateStatusText();
	}
	function forceShowWrapper() {
		// make sure wrapper is visible and above the game
		$wrapper
			.removeClass("hidden")
			.css({
				display: "block",
				visibility: "visible",
				opacity: 1,
				"z-index": 999999,
			})
			.stop(true, true)
			.fadeIn(120);

		// your window is a flex container per CSS
		$pdfWindow.css({ display: "flex" });

		updateStatusText();
	}

	function setPdfSrc(url) {
		var normalizedUrl = url;
		if (!normalizedUrl || normalizedUrl === "about:blank") {
			normalizedUrl = "";
		}

		pdfLink = normalizedUrl;
		pdfRenderToken += 1;
		cancelCurrentRender();

		if (!normalizedUrl) {
			clearPdfViewer();
			return;
		}

		if (!window.pdfjsLib || typeof pdfjsLib.getDocument !== "function") {
			console.warn("recordPrinter: WRN-CORE-900 pdf.js is not available; cannot render document. More: https://sonorancad.com/error/WRN-CORE-900");
			clearPdfViewer("PDF viewer not available.", true);
			return;
		}

		// Ensure worker is configured in case HTML did not set it
		if (!pdfjsLib.GlobalWorkerOptions.workerSrc) {
			pdfjsLib.GlobalWorkerOptions.workerSrc = "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js";
		}

		clearPdfViewer("Loading record...");

		var currentToken = pdfRenderToken;
		pdfLoadingTask = pdfjsLib.getDocument({
			url: normalizedUrl,
		});

		pdfLoadingTask.promise
			.then(function (pdf) {
				if (currentToken !== pdfRenderToken) {
					return pdf.destroy();
				}
				$pdfViewer.empty();
				return renderDocumentPages(pdf, currentToken);
			})
			.catch(function (err) {
				if (currentToken !== pdfRenderToken) {
					return;
				}
				console.warn("recordPrinter: ERR-CORE-906 failed to load pdf. More: https://sonorancad.com/error/ERR-CORE-906");
				clearPdfViewer("Unable to load document.", true);
			})
			.finally(function () {
				if (currentToken === pdfRenderToken) {
					pdfLoadingTask = null;
				}
			});
	}

	function openUI(link, firstFlag) {
		setPdfSrc(link);
		firstView = !!firstFlag;
		isOpen = true;
		isMinimized = false;
		isFullscreen = false;

		// make sure the UI can actually be seen
		forceShowWrapper();
		applyWindowState();
		notifyMinimizeChanged();
	}

	function closeUI(sendMessage) {
		if (!isOpen) return;
		isOpen = false;
		isMinimized = false;
		isFullscreen = false;

		$wrapper.stop(true, true).fadeOut(120, function () {
			setPdfSrc("");
			$wrapper.addClass("hidden").css("display", "none");
			updateStatusText();
		});

		if (sendMessage !== false) {
			$.post("https://sonorancad/CloseUI", JSON.stringify({ link: pdfLink, first: firstView }));
		}
	}

	function toggleMinimize(force) {
		if (!isOpen) {
			return;
		}

		if (typeof force === "boolean") {
			isMinimized = force;
		} else {
			isMinimized = !isMinimized;
		}

		if (isMinimized) {
			isFullscreen = false;
		}

		applyWindowState();
		notifyMinimizeChanged();

		// Explicitly request focus release on minimize
		if (isMinimized) {
			try {
				$.post("https://sonorancad/RecordPrinter:ForceReleaseFocus", JSON.stringify({}));
			} catch (err) {
				console.warn("recordPrinter: WRN-CORE-900 failed to request focus release. More: https://sonorancad.com/error/WRN-CORE-900", err);
			}
		}
	}

	function toggleFullscreen(force) {
		if (!isOpen) {
			return;
		}

		if (isMinimized) {
			isMinimized = false;
		}

		if (typeof force === "boolean") {
			isFullscreen = force;
		} else {
			isFullscreen = !isFullscreen;
		}

		applyWindowState();
	}

	$minimizeBtn.on("click", function () {
		toggleMinimize();
	});

	$fullscreenBtn.on("click", function () {
		toggleFullscreen();
	});

	$closeBtn.on("click", function () {
		closeUI(true);
	});

	window.addEventListener("message", function (event) {
		var data = event.data || {};

		if (data.link) {
			pdfLink = data.link;
		}
		if (typeof data.first !== "undefined") {
			firstView = !!data.first;
		}

		switch (data.action) {
			case "openUI":
				openUI(pdfLink, firstView);
				break;
			case "closeui":
				closeUI(true);
				break;
			case "toggleMinimize":
				toggleMinimize();
				break;
			case "toggleFullscreen":
				toggleFullscreen();
				break;
			default:
				break;
		}
	});

	$(document).on("keydown", function (event) {
		if (!isOpen) {
			return;
		}

		if (event.key === "Escape") {
			event.preventDefault();
			closeUI(true);
		} else if (event.key === "Backspace") {
			event.preventDefault();
			toggleMinimize(); 
		}
	});
});
