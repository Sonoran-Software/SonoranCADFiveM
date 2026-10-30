var currentlyCheckingLink = false;

var myident = null;

var CallCache = {
	active: [],
	emergency: []
};

var maxrows = 10;

let cachedResourceName = null;
const isCfxNui = () => (typeof GetParentResourceName === "function") || (typeof window.invokeNative === "function");
const getResourceName = () => {
	if (cachedResourceName) return cachedResourceName;
	if (typeof GetParentResourceName === "function") {
		cachedResourceName = GetParentResourceName();
		return cachedResourceName;
	}
	return "tablet";
};
const nui = (eventName, payload) => {
	if (!isCfxNui()) return;
	return $.post(`https://${getResourceName()}/${eventName}`, JSON.stringify(payload || {})).fail(() => {});
};

const tabletNotepadSync = typeof TabletNotepadSync === "object" ? TabletNotepadSync : null;
const NOTEPAD_SYNC_QUEUE_LIMIT = 32;
const NOTEPAD_SYNC_PROBE_REQUEST_ID = "tablet-notepad-auth-probe";
let cadFrameReady = false;
let cadSessionAuthenticated = false;
let cadAccountLinked = false;
let cadNotepadProbeSucceeded = false;
let cadSessionStatusDelivery = Promise.resolve();
const notepadSyncQueue = [];

function safeNotepadRequestId(message) {
	const requestId = message && message.requestId;
	return tabletNotepadSync && tabletNotepadSync.isValidRequestId(requestId)
		? requestId
		: undefined;
}

function sendNotepadSyncError(reason, requestId) {
	const message = {
		type: "scad:notepad:error",
		error: tabletNotepadSync
			? tabletNotepadSync.sanitizeErrorText(reason)
			: "unknown_error"
	};
	const safeRequestId = tabletNotepadSync && tabletNotepadSync.isValidRequestId(requestId)
		? requestId
		: undefined;
	if (safeRequestId) {
		message.requestId = safeRequestId;
	}
	nui("NotepadSyncResponse", { message });
}

function setCadSessionAuthenticated(authenticated) {
	const nextAuthenticated = authenticated === true;
	if (cadSessionAuthenticated === nextAuthenticated) return;

	cadSessionAuthenticated = nextAuthenticated;
	const statusAuthenticated = cadSessionAuthenticated;
	cadSessionStatusDelivery = cadSessionStatusDelivery
		.catch(() => {})
		.then(() => nui("NotepadSyncSessionStatus", { authenticated: statusAuthenticated }));
	if (cadSessionAuthenticated) {
		flushNotepadSyncQueue();
	}
}

function refreshCadSessionAuthenticated() {
	setCadSessionAuthenticated(Boolean(
		tabletNotepadSync
		&& tabletNotepadSync.isSessionAuthenticated(cadAccountLinked, cadNotepadProbeSucceeded)
	));
}

function resetCadSessionSignals() {
	cadAccountLinked = false;
	cadNotepadProbeSucceeded = false;
	refreshCadSessionAuthenticated();
}

function markCadFrameNotReady() {
	cadFrameReady = false;
	resetCadSessionSignals();
}

function probeCadNotepadSession() {
	const cadFrame = document.getElementById("cadFrame");
	if (!cadFrameReady || !cadFrame || !tabletNotepadSync) return;

	tabletNotepadSync.postToCad(cadFrame, {
		type: "scad:notepad:get",
		requestId: NOTEPAD_SYNC_PROBE_REQUEST_ID
	});
}

function flushNotepadSyncQueue() {
	const cadFrame = document.getElementById("cadFrame");
	if (!cadFrameReady || !cadSessionAuthenticated || !cadFrame || !tabletNotepadSync) return;

	while (notepadSyncQueue.length > 0) {
		const message = notepadSyncQueue.shift();
		const result = tabletNotepadSync.postToCad(cadFrame, message);
		if (!result.sent) {
			sendNotepadSyncError(result.reason === "invalid_request" ? "invalid_message" : "cad_unavailable", safeNotepadRequestId(message));
		}
	}
}

function forwardNotepadSyncRequest(message) {
	if (!tabletNotepadSync) {
		sendNotepadSyncError("cad_unavailable", safeNotepadRequestId(message));
		return;
	}

	const validation = tabletNotepadSync.validateOutboundMessage(message);
	if (!validation.valid) {
		sendNotepadSyncError("invalid_message", safeNotepadRequestId(message));
		return;
	}

	if (!cadSessionAuthenticated) {
		sendNotepadSyncError("cad_unavailable", validation.message.requestId);
		return;
	}

	const cadFrame = document.getElementById("cadFrame");
	if (!cadFrame || !cadFrame.contentWindow || !tabletNotepadSync.deriveCadFrameOrigin(cadFrame)) {
		sendNotepadSyncError("cad_unavailable", validation.message.requestId);
		return;
	}

	if (!cadFrameReady) {
		if (notepadSyncQueue.length >= NOTEPAD_SYNC_QUEUE_LIMIT) {
			sendNotepadSyncError("queue_overflow", validation.message.requestId);
			return;
		}
		notepadSyncQueue.push(validation.message);
		return;
	}

	const result = tabletNotepadSync.postToCad(cadFrame, validation.message);
	if (!result.sent) {
		sendNotepadSyncError(result.reason === "invalid_request" ? "invalid_message" : "cad_unavailable", validation.message.requestId);
	}
}

const cadFrameForSync = document.getElementById("cadFrame");
if (cadFrameForSync) {
	cadFrameForSync.addEventListener("load", function () {
		cadFrameReady = true;
		probeCadNotepadSession();
	});
}

function handleCadAccountLinkMessage(event) {
	const cadFrame = document.getElementById("cadFrame");
	if (!cadFrame || event.source !== cadFrame.contentWindow) return;

	let cadOrigin;
	try {
		cadOrigin = new URL(cadFrame.src).origin;
	} catch (_) {
		return;
	}

	if (event.origin !== cadOrigin || !event.data || event.data.type !== "scad:account-link") return;

	const { accountUuid, secretUuid } = event.data;
	if (typeof accountUuid !== "string" || typeof secretUuid !== "string") return;
	cadAccountLinked = true;
	refreshCadSessionAuthenticated();

	// Keep the account secret in memory only. The server derives the player's
	// communityUserId and performs the authenticated CAD request.
	nui("SetLinkInformation", { accountUuid, secretUuid });
}

const KeyMaps = {
	previous: "",
	attach: "",
	detail: "",
	next: ""
}

var currCall = 0;

function toggleDetail() {
	if (!CallCache.active[currCall]?.dispatch) return;
	setDetailVisible(document.getElementById("hudDetails").style.display === "none");
}

function setupHud() {
	document.getElementById("hudHeaderTime").textContent = "SONORAN";
}

function buttonShow(name, enabled, label) {
	const button = $(name)[0];
	button.disabled = !enabled;
	button.setAttribute("aria-disabled", String(!enabled));
	if (label !== undefined) button.textContent = label;
}

function setDetailVisible(visible) {
	document.getElementById("hudDetails").style.display = visible ? "" : "none";
	document.getElementById("hudDiv").classList.toggle("details-open", visible);
	const button = document.getElementById("btnDetail");
	button.setAttribute("aria-pressed", String(visible));
	button.classList.toggle("active", visible);
	updateHudBounds();
}

function setHudText(id, value, tooltip = false) {
	const element = document.getElementById(id);
	const text = value == null ? "" : String(value);
	element.textContent = text;
	if (tooltip) element.title = text;
}

function appendHudText(parent, className, text, tooltip = false) {
	const element = document.createElement("span");
	element.className = className;
	element.textContent = text;
	if (tooltip) element.title = text;
	parent.appendChild(element);
	return element;
}

function formatCallNote(note) {
	if (!note || typeof note !== "object" || note.type == null || note.time == null) {
		return note == null ? "" : String(note);
	}
	const label = note.label == null ? "" : String(note.label);
	if (note.type === "text") {
		const content = note.content == null ? "" : String(note.content);
		return note.time + " | " + (label === "Sonoran CAD" ? "" : label + ": ") + content;
	}
	return note.time + " | " + label + ": (" + note.type + " attachment.)";
}

function updateHudBounds() {
	const hud = document.getElementById("hudDiv");
	if (!hud || typeof hud.getBoundingClientRect !== "function") return;
	const bounds = hud.getBoundingClientRect();
	const margin = 12;
	if (Number.isFinite(window.innerWidth) && Number.isFinite(bounds.width) && Number.isFinite(bounds.left)) {
		const left = Math.min(Math.max(margin, bounds.left), Math.max(margin, window.innerWidth - margin - bounds.width));
		if (left !== bounds.left) hud.style.left = (hud.offsetLeft + left - bounds.left) + "px";
	}
	if (Number.isFinite(window.innerHeight) && Number.isFinite(bounds.top)) {
		// Reserve the same minimum usable panel height as the CSS before constraining its scrollers.
		const minimumHeight = Math.min(hud.classList.contains("details-open") ? 280 : 190,
			Math.max(0, window.innerHeight - margin * 2));
		const top = Math.min(Math.max(margin, bounds.top), Math.max(margin, window.innerHeight - margin - minimumHeight));
		if (top !== bounds.top) hud.style.top = (hud.offsetTop + top - bounds.top) + "px";
	}
	const top = hud.getBoundingClientRect().top;
	if (Number.isFinite(top)) hud.style.setProperty("--hud-top", Math.max(0, top) + "px");
}

function hudPixelDimension(value) {
	if (typeof value !== "number" && typeof value !== "string") return null;
	const pixels = Number(typeof value === "string" ? value.trim().replace(/px$/i, "") : value);
	return Number.isFinite(pixels) && pixels > 0 ? pixels + "px" : null;
}

function setHotkeys(keyMap) {
	return;
	KeyMaps.previous = keyMap.previous,
	KeyMaps.attach = keyMap.attach,
	KeyMaps.detail = keyMap.detail,
	KeyMaps.next = keyMap.next
}

function refreshCall() {
	setupHud();
	if (!Number.isInteger(currCall) || currCall < 0 || currCall >= CallCache.active.length) currCall = 0;
	const currentCall = CallCache.active[currCall]?.dispatch;
	document.getElementById("hudDiv").dataset.empty = String(!currentCall);

	buttonShow("#btnPrevCall", false);
	buttonShow("#btnAttach", false, "Attach");
	buttonShow("#btnDetail", false, "Details");
	buttonShow("#btnNextCall", false);

	if (!currentCall) {
		setHudText("hudHeaderCalls", "");
		setHudText("callCode", "No active calls", true);
		setHudText("callTitle", "", true);
		setHudText("callLocation", "", true);
		setHudText("callDescription", "");
		setHudText("callNotes", "");
		setHudText("callUnits", "");
		setDetailVisible(false);
	} else {
		buttonShow("#btnAttach", true, isAttached(CallCache.active[currCall]) ? "Detach" : "Attach");
		buttonShow("#btnDetail", true);
		buttonShow("#btnPrevCall", hasPrevCall());
		buttonShow("#btnNextCall", hasNextCall());
		setHudText("hudHeaderCalls", (currCall + 1) + "/" + CallCache.active.length);
		setHudText("callCode", currentCall.code, true);
		setHudText("callTitle", currentCall.title, true);
		const location = [currentCall.postal, currentCall.address]
			.filter(value => value != null && String(value) !== "").join(" ");
		setHudText("callLocation", location, true);
		setHudText("callDescription", currentCall.description);
		setHudText("callNotes", "");
		const notes = Array.isArray(currentCall.notes) ? currentCall.notes : [];
		const rows = Number(maxrows);
		// Lua stores /tablet mini rows N as N - 1; the original loop was inclusive.
		const rowLimit = Number.isFinite(rows) && rows >= 0 ? Math.floor(rows) + 1 : 11;
		const firstNote = Math.max(0, notes.length - rowLimit);
		const notesElement = document.getElementById("callNotes");
		if (firstNote > 0) {
			appendHudText(notesElement, "callnote", firstNote + " older notes hidden.");
		}
		for (let i = notes.length - 1; i >= firstNote; i--) {
			appendHudText(notesElement, "callnote", formatCallNote(notes[i]));
		}
		setHudText("callUnits", "");
		const unitsElement = document.getElementById("callUnits");
		const units = Array.isArray(currentCall.units) ? currentCall.units : [];
		if (units.length > 0) {
			for (const unit of units) appendHudText(unitsElement, "unit", String(unit?.data?.unitNum ?? ""), true);
		} else {
			appendHudText(unitsElement, "", "No units are attached to this call.").id = "nounits";
		}
		setDetailVisible(document.getElementById("hudDetails").style.display !== "none");
	}
}

function prevCall() {
	if (!hasPrevCall()) return;
	currCall -= 1;
	refreshCall();
}

function nextCall() {
	if (!hasNextCall()) return;
	currCall += 1;
	refreshCall();
}

const hasPrevCall = () => {
	return !!CallCache.active[currCall]?.dispatch && currCall > 0;
}

const hasNextCall = () => {
	return !!CallCache.active[currCall]?.dispatch && currCall < CallCache.active.length - 1;
}

const isAttached = (call) => {
	return Array.isArray(call?.dispatch?.idents) && call.dispatch.idents.includes(myident);
}

function attach() {
	const currentCall = CallCache.active[currCall]?.dispatch;
	if (!currentCall) return;
	// Don't reattach to the same call.
	if (isAttached(CallCache.active[currCall])) {
		for (const call of CallCache.active) {
			// Detach from other calls.
			if (isAttached(call)) {
				console.log("Detaching from call #" + call.dispatch.callId);
				nui('DetachFromCall', {callId: call.dispatch.callId});
			}
		}
	} else {
		for (const call of CallCache.active) {
			// Detach from other calls.
			if (isAttached(call)) {
				console.log("Detaching from call #" + call.dispatch.callId);
				nui('DetachFromCall', {callId: call.dispatch.callId});
			}
		}
		// Attach to the current call.
		nui('AttachToCall', {callId: currentCall.callId});
	}
}

function moduleVisible(module, visible, notifyLua = true) {
	const el = $("#" + module + "Div");
	if (visible) {
		el.css({ opacity: 1, pointerEvents: "auto" });
		if (module === "hud") updateHudBounds();
	} else {
		el.css({ opacity: 0, pointerEvents: "none" });
	}
	// Lua already tracks game-driven displays; only report direct UI changes.
	if (notifyLua) nui('VisibleEvent', { state: visible, module: module });
}

function showHelp() {
	nui('ShowHelp');
}

$(function () {
	window.addEventListener('message', function (event) {
		if (!event.data || typeof event.data !== "object") return;
		handleCadAccountLinkMessage(event);
		if (event.data.type == "display") {
			moduleVisible(event.data.module, event.data.enabled, false)
			if (event.data.apiCheck) {
				currentlyCheckingLink = true;
			}
			setHotkeys(event.data.keyMap);
		}
		else if (event.data.type == "config") {
			switch (event.data.key) {
				case 'maxrows':
					maxrows = event.data.value;
					console.log("Rows set to " + event.data.value);
					refreshCall();
					break;
				default:
					console.log("Invalid Config Option");
					break;
			}
		}
		else if (event.data.type == "command") {
			switch (event.data.key) {
				case 'prev':
					prevCall();
					break;
				case 'attach':
					attach();
					break;
				case 'detail':
					toggleDetail();
					break;
				case 'next':
					nextCall();
					break;
				default:
					break;
			}
		}
		else if (event.data.type == "callSync") {
			myident = event.data.ident;
			CallCache.active = [];
			for (const call of Object.values(event.data.activeCalls || {})) {
				if (call?.dispatch && call.dispatch_type !== "CALL_CLOSE") CallCache.active.push(call);
			}
			CallCache.emergency = event.data.emergencyCalls;
			refreshCall();
		}
		else if (event.data.type == "notepad_sync_request") {
			forwardNotepadSyncRequest(event.data.message);
		}
		else if (event.data.type == "setUrl") {
			if (event.data.module == "cad") {
				markCadFrameNotReady();
                let date = Date.now()
				if (event.data.comId) {
					document.getElementById("cadFrame").src = event.data.url + "&cachebuster=" + date;
				} else {
					document.getElementById("cadFrame").src = event.data.url + "?cachebuster=" + date;
				}
				document.getElementById('cadFrame').setAttribute("name", Date.now())
			}
		}
		else if (event.data.type == "cad_link_status") {
			currentlyCheckingLink = event.data.linked !== true;
		}
		else if (event.data.type == "resize") {
			if (event.data.module == "cad") {
				document.getElementById('cadFrame').width = event.data.newWidth;
				document.getElementById('cadFrame').height = event.data.newHeight;
				document.getElementById('cadDiv').style.width = event.data.newWidth;
				document.getElementById('cadDiv').style.height = event.data.newHeight;
			} else if (event.data.module == "hud") {
				const hud = document.getElementById('hudDiv');
				const width = hudPixelDimension(event.data.newWidth);
				const height = hudPixelDimension(event.data.newHeight);
				if (width) hud.style.width = width;
				if (height) hud.style.height = height;
				updateHudBounds();
			}
		}
		else if (event.data.type == "refresh") {
			let t = new Date().getTime();
			if (event.data.module == "cad") {
				markCadFrameNotReady();
				let s = document.getElementById('cadFrame').src;
				document.getElementById('cadFrame').src = s + "&" + t.toString();
				document.getElementById('cadFrame').setAttribute("name", Date.now())
			}
		}
	});

	// document.getElementById('cadFrame').onkeyup = function (data) {
	// 	switch (data.which) {
	// 		case 27:
	// 			nui('NUIFocusOff', {});
	// 			break;
	// 		default:
	// 			break;
	// 	}
	// }

	document.onkeyup = function (data) {
		switch (data.which) {
			case 27:
				nui('NUIFocusOff', {});
				break;
			default:
				break;
		}
	};

	dragElement(document.getElementById("cadDiv"));
	dragElement(document.getElementById("hudDiv"));
	window.addEventListener('resize', updateHudBounds);

	document.addEventListener('mousedown', function(e) {
		const draggingElements = document.querySelectorAll('.dragging');
		if (draggingElements.length > 0) {
			const cadFrame = document.getElementById('cadFrame');
			if (cadFrame && (cadFrame === e.target || cadFrame.contains(e.target))) {
				e.preventDefault();
				e.stopPropagation();
				return false;
			}
		}
	}, true);

	document.addEventListener('mouseover', function(e) {
		const draggingElements = document.querySelectorAll('.dragging');
		if (draggingElements.length > 0) {
			const cadFrame = document.getElementById('cadFrame');
			if (cadFrame && (cadFrame === e.target || cadFrame.contains(e.target))) {
				e.preventDefault();
				e.stopPropagation();
			}
		}
	}, true);

window.addEventListener("message", receiveMessage, false);

	window.addEventListener('blur', function() {
		const draggingElements = document.querySelectorAll('.dragging');
		if (draggingElements.length > 0) {
			draggingElements.forEach(function(element) {
				element.classList.remove('dragging');
			});
			const overlay = document.getElementById('dragOverlay');
			if (overlay) {
				overlay.parentNode.removeChild(overlay);
			}
			const cadFrame = document.getElementById('cadFrame');
			if (cadFrame) {
				cadFrame.style.pointerEvents = 'auto';
			}
		}
	});
});

function dragElement(elmnt) {
	var pos1 = 0, pos2 = 0, pos3 = 0, pos4 = 0;
	var isDragging = false;
	var dragOverlay = null;

	const isHud = elmnt.id === "hudDiv";
	const handle = isHud ? document.getElementById("hudHeader")
		: document.getElementById(elmnt.id + "header") || elmnt;
	if (handle) handle.onmousedown = dragMouseDown;

	function dragMouseDown(e) {
		if (elmnt.classList.contains('display-surface')) return;
		e = e || window.event;
		if (isHud && e.target?.closest?.('button, input, textarea, select, a, [contenteditable="true"]')) return;
		e.preventDefault();
		e.stopPropagation();

		// get the mouse cursor position at startup:
		pos3 = e.clientX;
		pos4 = e.clientY;
		isDragging = true;

		elmnt.classList.add('dragging');

		createDragOverlay();

		document.onmouseup = closeDragElement;
		// call a function whenever the cursor moves:
		document.onmousemove = elementDrag;
	}

	function elementDrag(e) {
		e = e || window.event;
		e.preventDefault();
		e.stopPropagation();

		if (!isDragging) return;

		// calculate the new cursor position:
		pos1 = pos3 - e.clientX;
		pos2 = pos4 - e.clientY;
		pos3 = e.clientX;
		pos4 = e.clientY;
		// set the element's new position:
		elmnt.style.top = (elmnt.offsetTop - pos2) + "px";
		elmnt.style.left = (elmnt.offsetLeft - pos1) + "px";
		if (isHud) updateHudBounds();
	}

	function closeDragElement() {
		// stop moving when mouse button is released:
		isDragging = false;
		elmnt.classList.remove('dragging');
		removeDragOverlay();
		document.onmouseup = null;
		document.onmousemove = null;
	}

	function createDragOverlay() {
		removeDragOverlay();

		dragOverlay = document.createElement('div');
		dragOverlay.id = 'dragOverlay';
		dragOverlay.style.cssText = `
			position: fixed;
			top: 0;
			left: 0;
			width: 100%;
			height: 100%;
			background: transparent;
			z-index: 9998;
			pointer-events: none;
		`;
		document.body.appendChild(dragOverlay);

		const cadFrame = document.getElementById('cadFrame');
		if (cadFrame) {
			cadFrame.style.pointerEvents = 'none';
		}
	}

function removeDragOverlay() {
		if (dragOverlay) {
			if (dragOverlay.parentNode) {
				dragOverlay.parentNode.removeChild(dragOverlay);
			}
			dragOverlay = null;
		}

		const cadFrame = document.getElementById('cadFrame');
		if (cadFrame) {
			cadFrame.style.pointerEvents = 'auto';
		}
	}
}

const SCREENSHOT_MAX_WIDTH = 512;
const SCREENSHOT_MAX_HEIGHT = 256;
const SCREENSHOT_QUALITY = 0.6;

function downscaleCadScreenshot(dataUrl, done) {
	if (!dataUrl || typeof dataUrl !== "string" || dataUrl.indexOf("data:image") !== 0) {
		done(dataUrl);
		return;
	}

	var img = new Image();
	img.onload = function () {
		var scale = Math.min(SCREENSHOT_MAX_WIDTH / img.width, SCREENSHOT_MAX_HEIGHT / img.height, 1);
		var width = Math.max(1, Math.round(img.width * scale));
		var height = Math.max(1, Math.round(img.height * scale));
		var canvas = document.createElement("canvas");
		canvas.width = width;
		canvas.height = height;
		var ctx = canvas.getContext("2d");
		ctx.drawImage(img, 0, 0, width, height);
		done(canvas.toDataURL("image/jpeg", SCREENSHOT_QUALITY));
	};
	img.onerror = function () {
		done(dataUrl);
	};
	img.src = dataUrl;
}

function receiveMessage(event) {

	let cadframe = document.getElementById("cadFrame");
	if (!cadframe) return;

	if (tabletNotepadSync) {
		const notepadResponse = tabletNotepadSync.parseCadResponseEvent(event, cadframe);
		if (notepadResponse.accepted) {
			if (notepadResponse.message.requestId === NOTEPAD_SYNC_PROBE_REQUEST_ID) {
				if (cadFrameReady
					&& notepadResponse.message.type === tabletNotepadSync.MESSAGE_TYPES.state) {
					cadNotepadProbeSucceeded = true;
					refreshCadSessionAuthenticated();
				}
				return;
			}
			if (!cadSessionAuthenticated) return;
			nui("NotepadSyncResponse", { message: notepadResponse.message });
			return;
		}
	}

	let frameorigin;
	try {
		frameorigin = new URL(cadframe.src).origin;
	} catch (_) {
		return;
	}

	if (currentlyCheckingLink && event.origin == frameorigin) {
		const sanitizeLinkField = (value) => {
			if (typeof value !== "string") return null;
			const trimmed = value.trim();
			if (!trimmed || trimmed.length > 128) return null;
			if (!/^[A-Za-z0-9._:@/-]+$/.test(trimmed)) return null;
			return trimmed;
		};
		const session = sanitizeLinkField(event.data && event.data.session);
		const username = sanitizeLinkField(event.data && event.data.username);
		if (session || username) {
			nui('SetLinkInformation', {
				session: session,
				username: username
			});
		}
	}

	// Forward caddisplay screenshot requests to the CAD iframe
	if (event.data && event.data.type === "caddisplay_screenshot_request") {
		if (cadframe && cadframe.contentWindow) {
			cadframe.contentWindow.postMessage({
				type: "scad:screenshot:request",
				requestId: event.data.requestId
			}, "*");
		}
	}

	// Forward CAD iframe responses back to the game client
	if (event.data && event.data.type === "scad:screenshot:response") {
		downscaleCadScreenshot(event.data.image, function (image) {
			nui('CadDisplayScreenshot', {
				requestId: event.data.requestId,
				image: image
			});
		});
	}
}

function addCallNote(call, data) {
	nui('addCallNote', {call: call, data: data});
}

document.getElementById('homeButton').addEventListener('click', function() {
	nui('NUIFocusOff', {});
});
