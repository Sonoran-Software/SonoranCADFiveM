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
	$("#hudDetails")[0].style.display = ($("#hudDetails")[0].style.display === "" ? "none": "")
	// Not Yet Implemented!
	//$("#hudInput")[0].style.display = ($("#hudInput")[0].style.display === "" ? "none":"");
}

function setupHud() {
	$("#hudHeaderTime")[0].innerText = "Sonoran Mini-CAD";
}

function buttonShow(name, visible, label) {
	$(name)[0].style.color = (visible? '': 'rgb(70,70,70)');
	if (label) $(name)[0].innerText = label;
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

	let activeCall = true;

	if (CallCache.active.length === 0) activeCall = false;
	if (currCall > CallCache.active.length) currCall = 0;

	buttonShow("#btnPrevCall", false);
	buttonShow("#btnAttach", false, "Attach");
	buttonShow("#btnDetail", false, "Details");
	buttonShow("#btnNextCall", false);

	if (!activeCall) {
		$("#hudHeaderCalls")[0].innerText = '';
		$("#callCode")[0].innerText = 'No Active Calls';
		$("#callTitle")[0].innerText = 'There are currently no active calls';
		$("#callLocation")[0].innerText = '';
		$("#callDescription")[0].innerText = '';
		$("#callNotes")[0].innerHTML = '';
		$("#callUnits")[0].innerHTML = '';
		$("#hudDetails")[0].style.display = "none";
	} else {
		let currentCall = CallCache?.active[currCall]?.dispatch;
		if (!currentCall) return;
		buttonShow("#btnAttach", true);
		if (isAttached(CallCache.active[currCall])) {
			buttonShow("#btnAttach", true, "Detach");
		} else {
			buttonShow("#btnAttach", true, "Attach");
		}
		buttonShow("#btnDetail", true);
		buttonShow("#btnPrevCall", hasPrevCall());
		buttonShow("#btnNextCall", hasNextCall());
		$("#hudHeaderCalls")[0].innerText = (currCall + 1) + "/" + CallCache.active.length;
		//$("#hudHeaderCalls")[0].innerText = "Call #" + currentCall.callId;
		$("#callCode")[0].innerText = currentCall.code;
		$("#callTitle")[0].innerText = currentCall.title;
		$("#callLocation")[0].innerText = (currentCall.postal != "" ? currentCall.postal + " ": "") + currentCall.address;
		$("#callDescription")[0].innerText = currentCall.description;
		$("#callNotes")[0].innerHTML = '';
		if (currentCall.notes) {
			if (currentCall.notes.length > maxrows) {
				$("#callNotes")[0].innerHTML += '<span class="callnote">** NOTE: ' + (currentCall.notes.length - maxrows) +' notes hidden. (Use /minicadrows) ***</span>';
			}
			for (var i = (currentCall.notes.length-1 > maxrows ? maxrows : currentCall.notes.length-1); i>=0; i--) {
				let callnote = "";
				if (currentCall.notes[i].content == null || currentCall.notes[i].type == null || currentCall.notes[i].time == null) {
					callnote = currentCall.notes[i].toString();
				} else {
					switch (currentCall.notes[i].type) {
						case "text":
							if (currentCall.notes[i].label == "Sonoran CAD") {
								callnote = currentCall.notes[i].time + " | " + currentCall.notes[i].content;
							} else {
								callnote = currentCall.notes[i].time + " | " + currentCall.notes[i].label + ": " + currentCall.notes[i].content;
							}
							break;
						default:
							callnote = currentCall.notes[i].time + " | " + currentCall.notes[i].label + ": " + "(" + currentCall.notes[i].type + " attachment.)";
							break;
					}
				}
				$("#callNotes")[0].innerHTML += '<span class="callnote">' + callnote + '</span>';
			}
		}
		if (currentCall.units?.length > 0) {
			$("#callUnits")[0].innerHTML = '';
			for (var i = 0; i<currentCall.units.length; i++) {
				//console.log(currentCall.units[i].status);
				let style = "unit";
				// Not Yet Implemented!
				// switch (currentCall.units[i].status) {
				// 	case 0:
				// 		style += " unavailable"
				// 		break;
				// 	case 1:
				// 		style += " busy"
				// 		break;
				// 	case 2:
				// 		style += " available"
				// 		break;
				// 	case 3:
				// 		style += " enroute"
				// 		break;
				// 	case 4:
				// 		style += " onscene"
				// 		break;
				// }
				$("#callUnits")[0].innerHTML += '<span class="' + style + '">' + currentCall.units[i].data.unitNum + '</span>'

			}
		} else {
			$("#callUnits")[0].innerHTML = '<span id="nounits">No units are attached to this call.</span>';
		}

	}
}

function prevCall() {
	if (currCall === 0) return;
	currCall -= 1;
	refreshCall();
}

function nextCall() {
	if (currCall === CallCache.active.length - 1) return;
	currCall += 1;
	refreshCall();
}

const hasPrevCall = () => {
	if (currCall === 0) return false;
	return true;
}

const hasNextCall = () => {
	if (currCall === CallCache.active.length - 1) return false;
	return true;
}

const isAttached = (call) => {
	return call.dispatch.idents.includes(myident);
}

function attach() {
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
		nui('AttachToCall', {callId: CallCache.active[currCall].dispatch.callId});
	}
}

function moduleVisible(module, visible) {
	const el = $("#" + module + "Div");
	if (visible) {
		el.css({ opacity: 1, pointerEvents: "auto" });
	} else {
		el.css({ opacity: 0, pointerEvents: "none" });
	}
	nui('VisibleEvent', { state: visible, module: module });
}

function showHelp() {
	nui('ShowHelp');
}

$(function () {
	window.addEventListener('message', function (event) {
		if (!event.data || typeof event.data !== "object") return;
		handleCadAccountLinkMessage(event);
		if (event.data.type == "display") {
			moduleVisible(event.data.module, event.data.enabled)
			if (event.data.apiCheck) {
				currentlyCheckingLink = true;
				//$("#check-api-data").show();
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
			for (const [key, call] of Object.entries(event.data.activeCalls)) {
				if (call != null) {
					if (call.dispatch_type) {
						if (call.dispatch_type != "CALL_CLOSE") CallCache.active.push(call);
					} else {
						CallCache.active.push(call);
					}
				}
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
		else if (event.data.type == "regbar") {
			const shouldShow = event.data.show !== false;
			currentlyCheckingLink = shouldShow;
			if (shouldShow) {
				$("#check-api-data").show();
			} else {
				$("#check-api-data").hide();
			}
		}
		else if (event.data.type == "resize") {
			if (event.data.module == "cad") {
				document.getElementById('cadFrame').width = event.data.newWidth;
				document.getElementById('cadFrame').height = event.data.newHeight;
				document.getElementById('cadDiv').style.width = event.data.newWidth;
				document.getElementById('cadDiv').style.height = event.data.newHeight;
			} else if (event.data.module == "hud") {
				document.getElementById('hudFrame').width = event.data.newWidth;
				document.getElementById('hudFrame').height = event.data.newHeight;
				document.getElementById('hudDiv').style.width = event.data.newWidth;
				document.getElementById('hudDiv').style.height = event.data.newHeight;
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

	if (document.getElementById(elmnt.id + "header")) {
		// if present, the header is where you move the DIV from:
		document.getElementById(elmnt.id + "header").onmousedown = dragMouseDown;
	} else {
		// otherwise, move the DIV from anywhere inside the DIV:
		elmnt.onmousedown = dragMouseDown;
	}

	function dragMouseDown(e) {
		e = e || window.event;
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
			$("#check-api-data").hide();
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

function runLinkCheck() {
	currentlyCheckingLink = true;
	markCadFrameNotReady();
	document.getElementById("cadFrame").src += '';
	nui('runLinkCheck');
	$("#check-api-data").hide();
}

document.getElementById('homeButton').addEventListener('click', function() {
	nui('NUIFocusOff', {});
});
