(function (root, factory) {
    const api = factory();
    if (typeof module === 'object' && module.exports) {
        module.exports = api;
    }
    if (root) {
        root.TabletNotepadSync = api;
    }
}(typeof globalThis === 'object' ? globalThis : this, function () {
    const MESSAGE_TYPES = Object.freeze({
        get: 'scad:notepad:get',
        set: 'scad:notepad:set',
        state: 'scad:notepad:state',
        changed: 'scad:notepad:changed',
        error: 'scad:notepad:error',
    });
    const MAX_REQUEST_ID_LENGTH = 128;
    const MAX_ERROR_LENGTH = 160;

    function isRecord(value) {
        return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
    }

    function isValidRequestId(value) {
        return typeof value === 'string'
            && value.length > 0
            && value.length <= MAX_REQUEST_ID_LENGTH
            && value.trim() !== '';
    }

    function sanitizeErrorText(value) {
        if (typeof value !== 'string') {
            return 'unknown_error';
        }

        const normalized = value
            .replace(/[\u0000-\u001f\u007f]/g, ' ')
            .replace(/\s+/g, ' ')
            .trim()
            .slice(0, MAX_ERROR_LENGTH);
        return normalized || 'unknown_error';
    }

    function optionalRequestId(message) {
        if (!Object.prototype.hasOwnProperty.call(message, 'requestId')
            || message.requestId === undefined) {
            return { valid: true, requestId: undefined };
        }

        return isValidRequestId(message.requestId)
            ? { valid: true, requestId: message.requestId }
            : { valid: false, reason: 'invalid_request_id' };
    }

    function validateOutboundMessage(message) {
        if (!isRecord(message) || !isValidRequestId(message.requestId)) {
            return { valid: false, reason: 'invalid_request' };
        }

        if (message.type === MESSAGE_TYPES.get) {
            if (Object.prototype.hasOwnProperty.call(message, 'notes')) {
                return { valid: false, reason: 'get_has_notes' };
            }

            return {
                valid: true,
                message: {
                    type: message.type,
                    requestId: message.requestId,
                },
            };
        }

        if (message.type === MESSAGE_TYPES.set && Array.isArray(message.notes)) {
            return {
                valid: true,
                message: {
                    type: message.type,
                    requestId: message.requestId,
                    notes: message.notes,
                },
            };
        }

        return { valid: false, reason: 'invalid_request' };
    }

    function validateInboundMessage(message) {
        if (!isRecord(message)) {
            return { valid: false, reason: 'invalid_response' };
        }

        const requestId = optionalRequestId(message);
        if (!requestId.valid) {
            return requestId;
        }

        if ((message.type === MESSAGE_TYPES.state
            || message.type === MESSAGE_TYPES.changed)
            && Array.isArray(message.notes)) {
            const response = {
                type: message.type,
                notes: message.notes,
            };
            if (requestId.requestId !== undefined) {
                response.requestId = requestId.requestId;
            }
            return { valid: true, message: response };
        }

        if (message.type === MESSAGE_TYPES.error
            && typeof message.error === 'string') {
            const response = {
                type: message.type,
                error: sanitizeErrorText(message.error),
            };
            if (requestId.requestId !== undefined) {
                response.requestId = requestId.requestId;
            }
            return { valid: true, message: response };
        }

        return { valid: false, reason: 'invalid_response' };
    }

    function frameSource(frame) {
        if (!frame || typeof frame !== 'object') {
            return '';
        }
        if (typeof frame.src === 'string' && frame.src !== '') {
            return frame.src;
        }
        if (typeof frame.getAttribute === 'function') {
            return frame.getAttribute('src') || '';
        }
        return '';
    }

    function deriveCadFrameOrigin(frameOrUrl) {
        const source = typeof frameOrUrl === 'string' ? frameOrUrl : frameSource(frameOrUrl);
        if (typeof source !== 'string' || source.trim() === '') {
            return '';
        }

        try {
            const base = typeof document !== 'undefined' && document.baseURI
                ? document.baseURI
                : undefined;
            const parsed = base ? new URL(source, base) : new URL(source);
            if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
                return '';
            }
            return parsed.origin === 'null' ? '' : parsed.origin;
        } catch (_) {
            return '';
        }
    }

    function isTrustedCadEvent(event, cadFrame, targetOrigin) {
        const frameOrigin = deriveCadFrameOrigin(cadFrame);
        const expectedOrigin = targetOrigin || frameOrigin;
        return Boolean(
            event
            && cadFrame
            && cadFrame.contentWindow
            && frameOrigin
            && expectedOrigin
            && expectedOrigin !== '*'
            && expectedOrigin === frameOrigin
            && event.source === cadFrame.contentWindow
            && event.origin === expectedOrigin,
        );
    }

    function parseCadResponseEvent(event, cadFrame) {
        const targetOrigin = deriveCadFrameOrigin(cadFrame);
        if (!isTrustedCadEvent(event, cadFrame, targetOrigin)) {
            return { accepted: false, reason: 'untrusted_event' };
        }

        const parsed = validateInboundMessage(event.data);
        if (!parsed.valid) {
            return { accepted: false, reason: parsed.reason };
        }

        return { accepted: true, message: parsed.message };
    }

    function postToCad(cadFrame, message) {
        const validated = validateOutboundMessage(message);
        if (!validated.valid) {
            return { sent: false, reason: validated.reason };
        }

        const targetOrigin = deriveCadFrameOrigin(cadFrame);
        if (!targetOrigin || !cadFrame || !cadFrame.contentWindow) {
            return { sent: false, reason: 'cad_unavailable' };
        }

        try {
            cadFrame.contentWindow.postMessage(validated.message, targetOrigin);
            return { sent: true, targetOrigin, message: validated.message };
        } catch (_) {
            return { sent: false, reason: 'cad_unavailable' };
        }
    }

    function postMessageToCad(cadFrame, message) {
        return postToCad(cadFrame, message).sent;
    }

    return Object.freeze({
        MESSAGE_TYPES,
        MAX_REQUEST_ID_LENGTH,
        MAX_ERROR_LENGTH,
        isValidRequestId,
        sanitizeErrorText,
        validateOutboundMessage,
        validateInboundMessage,
        validateNotepadRequest: validateOutboundMessage,
        validateNotepadResponse: validateInboundMessage,
        deriveCadFrameOrigin,
        deriveCadOrigin: deriveCadFrameOrigin,
        isTrustedCadEvent,
        parseCadResponseEvent,
        postToCad,
        postMessageToCad,
    });
}));
