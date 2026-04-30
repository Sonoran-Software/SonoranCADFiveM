const fs = require("fs");
const path = require("path");

const MAX_FILE_SIZE_BYTES = 6000000;
const MAX_DURATION_MS = 120000;
const BODYCAM_UPLOAD_PATH = "/v2/general/bodycam-recordings";
const RECORDINGS_DIR = path.join(GetResourcePath(GetCurrentResourceName()), "submodules", "bodycam", "recordings");
const PENDING_UPLOADS = new Map();

function log(level, message) {
	emit("SonoranCAD::core:writeLog", level, `[bodycam-recording] ${message}`);
}

function ensureRecordingsDirectory() {
	if (!fs.existsSync(RECORDINGS_DIR)) {
		fs.mkdirSync(RECORDINGS_DIR, { recursive: true });
	}
}

function readConfigFile() {
	try {
		const raw = LoadResourceFile(GetCurrentResourceName(), "configuration/config.json");
		if (raw && raw !== "") {
			return JSON.parse(raw);
		}
	} catch (err) {
		log("warn", `Failed to parse configuration/config.json: ${err && err.message ? err.message : err}`);
	}
	return {};
}

function getConvarValue(name) {
	const value = GetConvar(name, "NONE");
	if (value === "NONE" || value === "") {
		return null;
	}
	return value;
}

function getApiBaseUrl() {
	const fileConfig = readConfigFile();
	const mode = (getConvarValue("sonoran_mode") || fileConfig.mode || "production").toLowerCase();
	if (mode === "development") {
		return "https://staging-api.dev.sonorancad.com";
	}
	return "https://api.sonorancad.com";
}

function getApiKey() {
	const fileConfig = readConfigFile();
	return getConvarValue("sonoran_apiKey") || fileConfig.apiKey || null;
}

function getCommunityUserId(src) {
	if (!exports[GetCurrentResourceName()].getPlayerCommunityUserId) {
		return null;
	}
	return exports[GetCurrentResourceName()].getPlayerCommunityUserId(String(src));
}

function summarizeInitPayload(payload) {
	const data = payload && typeof payload === "object" ? payload : {};
	return {
		uploadId: data.uploadId || null,
		fileName: data.fileName || null,
		sourceType: data.sourceType || null,
		trigger: data.trigger || null,
		stopReason: data.stopReason || null,
		durationMs: Number(data.durationMs) || 0,
		size: Number(data.size) || 0,
		totalChunks: Number(data.totalChunks) || 0,
		metadataKeys: data.metadata && typeof data.metadata === "object" ? Object.keys(data.metadata) : [],
	};
}

function sanitizeFileName(fileName) {
	return String(fileName || `bodycam-${Date.now()}.webm`).replace(/[^a-zA-Z0-9._-]/g, "_");
}

function hasWebmEbmlHeader(buffer) {
	return !!(
		buffer &&
		buffer.byteLength >= 4 &&
		buffer[0] === 0x1a &&
		buffer[1] === 0x45 &&
		buffer[2] === 0xdf &&
		buffer[3] === 0xa3
	);
}

function buildMultipartBody(fields, fileField) {
	const boundary = `----sonorancad-bodycam-${Date.now()}-${Math.random().toString(16).slice(2)}`;
	const buffers = [];

	for (const [name, value] of Object.entries(fields || {})) {
		if (value === undefined || value === null || value === "") {
			continue;
		}
		buffers.push(Buffer.from(`--${boundary}\r\n`));
		buffers.push(Buffer.from(`Content-Disposition: form-data; name="${name}"\r\n\r\n`));
		buffers.push(Buffer.from(String(value)));
		buffers.push(Buffer.from("\r\n"));
	}

	buffers.push(Buffer.from(`--${boundary}\r\n`));
	buffers.push(
		Buffer.from(
			`Content-Disposition: form-data; name="${fileField.fieldName}"; filename="${fileField.fileName}"\r\n`
		)
	);
	buffers.push(Buffer.from(`Content-Type: ${fileField.contentType || "application/octet-stream"}\r\n\r\n`));
	buffers.push(fileField.buffer);
	buffers.push(Buffer.from("\r\n"));
	buffers.push(Buffer.from(`--${boundary}--\r\n`));

	return {
		boundary,
		body: Buffer.concat(buffers),
	};
}

function buildTempFilePath(uploadId, fileName) {
	ensureRecordingsDirectory();
	const safeName = sanitizeFileName(fileName);
	return path.join(RECORDINGS_DIR, `${uploadId}-${safeName}`);
}

function safeDeleteFile(filePath) {
	try {
		if (filePath && fs.existsSync(filePath)) {
			fs.unlinkSync(filePath);
		}
	} catch (err) {
		log("warn", `Failed to delete temp bodycam file ${filePath}: ${err && err.message ? err.message : err}`);
	}
}

exports("CreateTempBodycamRecordingFile", function (uploadId, fileName) {
	const tempPath = buildTempFilePath(uploadId, fileName);
	safeDeleteFile(tempPath);
	return tempPath;
});

async function uploadSavedBodycamClip(src, session) {
	const apiKey = getApiKey();
	const communityUserId = getCommunityUserId(src);
	const unit = exports[GetCurrentResourceName()].GetUnitByPlayerId(String(src));
	const payload = session.payload || {};
	const metadata = payload && typeof payload.metadata === "object" ? payload.metadata : {};
	const durationMs = Math.max(1, Math.min(MAX_DURATION_MS, Number(payload.durationMs) || 0));
	const endpoint = `${getApiBaseUrl().replace(/\/$/, "")}${BODYCAM_UPLOAD_PATH}`;

	log("debug", `Upload prerequisites for ${src}: apiKey=${!!apiKey} communityUserId=${!!communityUserId} unit=${!!unit} uploadId=${session.uploadId}`);

	if (!apiKey) {
		emitNet("SonoranCAD::bodycam::UploadResult", src, {
			ok: false,
			reason: "missing_api_key",
		});
		return;
	}

	if (!communityUserId) {
		emitNet("SonoranCAD::bodycam::UploadResult", src, {
			ok: false,
			reason: "missing_community_user_id",
		});
		return;
	}

	if (durationMs < 1 || durationMs > MAX_DURATION_MS) {
		emitNet("SonoranCAD::bodycam::UploadResult", src, {
			ok: false,
			reason: "invalid_duration",
		});
		return;
	}

	if (!fs.existsSync(session.filePath)) {
		emitNet("SonoranCAD::bodycam::UploadResult", src, {
			ok: false,
			reason: "missing_temp_file",
		});
		return;
	}

	const fileBuffer = fs.readFileSync(session.filePath);
	if (!fileBuffer || fileBuffer.byteLength < 1) {
		emitNet("SonoranCAD::bodycam::UploadResult", src, {
			ok: false,
			reason: "invalid_file",
		});
		return;
	}

	if (fileBuffer.byteLength > MAX_FILE_SIZE_BYTES) {
		emitNet("SonoranCAD::bodycam::UploadResult", src, {
			ok: false,
			reason: "clip_too_large",
		});
		return;
	}

	const identId = metadata.identId || (unit && unit.id) || undefined;
	const unitNumber = metadata.unitNumber || (unit && unit.data && unit.data.unitNum) || undefined;
	const unitLocation = metadata.unitLocation || (unit && unit.location) || undefined;
	if (!hasWebmEbmlHeader(fileBuffer)) {
		log("error", `Upload rejected for ${src}: invalid WebM header uploadId=${session.uploadId} firstBytes=${fileBuffer.subarray(0, 16).toString("hex")}`);
		emitNet("SonoranCAD::bodycam::UploadResult", src, {
			ok: false,
			reason: "invalid_file_header",
		});
		return;
	}

	const multipart = buildMultipartBody(
		{
			communityUserId: String(communityUserId),
			durationMs: String(durationMs),
			identId: identId !== undefined && identId !== null && identId !== "" ? String(identId) : undefined,
			unitNumber: unitNumber !== undefined && unitNumber !== null && unitNumber !== "" ? String(unitNumber) : undefined,
			unitLocation: unitLocation !== undefined && unitLocation !== null && unitLocation !== "" ? String(unitLocation) : undefined,
		},
		{
			fieldName: "file",
			fileName: session.fileName,
			contentType: "video/webm",
			buffer: fileBuffer,
		}
	);

	log("debug", `Upload begin src=${src} uploadId=${session.uploadId} trigger=${payload.trigger || "manual"} durationMs=${durationMs} rawSize=${fileBuffer.byteLength} endpoint=${endpoint}`);
	log("debug", `Upload request body for ${src}: ${JSON.stringify({
		uploadId: session.uploadId,
		endpoint,
		fileName: session.fileName,
		communityUserId,
		durationMs,
		fileSizeBytes: fileBuffer.byteLength,
		identId: identId || null,
		unitNumber: unitNumber || null,
		unitLocation: unitLocation || null,
		metadata,
	})}`);

	try {
		const controller = typeof AbortController !== "undefined" ? new AbortController() : null;
		const timeout = controller
			? setTimeout(() => controller.abort(), 45000)
			: null;
		const response = await fetch(endpoint, {
			method: "POST",
			body: multipart.body,
			headers: {
				Authorization: `Bearer ${apiKey}`,
				"Content-Type": `multipart/form-data; boundary=${multipart.boundary}`,
				"Content-Length": String(multipart.body.byteLength),
			},
			signal: controller ? controller.signal : undefined,
		});
		if (timeout) {
			clearTimeout(timeout);
		}
		const bodyText = await response.text();
		if (!response.ok) {
			log("error", `Upload failure src=${src} uploadId=${session.uploadId} status=${response.status} statusText=${response.statusText || ""} body=${String(bodyText)}`);
			emitNet("SonoranCAD::bodycam::UploadResult", src, {
				ok: false,
				reason: "upload_failed",
				status: response.status,
				statusText: JSON.parse(bodyText).detail || "",
				apiResponse: String(bodyText),
			});
			return;
		}
		log("debug", `Upload success src=${src} uploadId=${session.uploadId} status=${response.status} statusText=${response.statusText || ""} body=${String(bodyText)}`);
		emitNet("SonoranCAD::bodycam::UploadResult", src, {
			ok: true,
			status: response.status,
			statusText: response.statusText || "",
			apiResponse: String(bodyText),
		});
	} catch (err) {
		log("error", `Upload exception src=${src} uploadId=${session.uploadId}: ${err && err.stack ? err.stack : err}`);
		emitNet("SonoranCAD::bodycam::UploadResult", src, {
			ok: false,
			reason: "upload_exception",
			apiResponse: err && err.stack ? String(err.stack) : String(err),
		});
	}
}

function createUploadSession(src, payload) {
	ensureRecordingsDirectory();
	const summary = summarizeInitPayload(payload);
	const uploadId = summary.uploadId;
	if (!uploadId) {
		log("warn", `Upload init rejected for ${src}: missing uploadId`);
		return null;
	}
	const fileName = sanitizeFileName(summary.fileName);
	const filePath = path.join(RECORDINGS_DIR, `${uploadId}-${fileName}`);
	safeDeleteFile(filePath);
	const session = {
		src,
		uploadId,
		fileName,
		filePath,
		payload: payload || {},
		totalChunks: summary.totalChunks,
		receivedChunks: 0,
		chunks: new Map(),
		createdAt: Date.now(),
	};
	PENDING_UPLOADS.set(uploadId, session);
	log("debug", `Upload init for ${src}: ${JSON.stringify(summary)} filePath=${filePath}`);
	return session;
}

function appendUploadChunk(src, uploadId, chunkIndex, base64Chunk) {
	const session = PENDING_UPLOADS.get(uploadId);
	if (!session) {
		log("warn", `Upload chunk rejected for ${src}: unknown uploadId=${uploadId}`);
		return;
	}
	if (typeof base64Chunk !== "string" || base64Chunk.length < 1) {
		log("warn", `Upload chunk rejected for ${src}: empty chunk uploadId=${uploadId} index=${chunkIndex}`);
		return;
	}
	const normalizedChunkIndex = Number(chunkIndex) || 0;
	if (normalizedChunkIndex < 1 || normalizedChunkIndex > session.totalChunks) {
		log("warn", `Upload chunk rejected for ${src}: invalid index uploadId=${uploadId} index=${chunkIndex} total=${session.totalChunks}`);
		return;
	}
	if (session.chunks.has(normalizedChunkIndex)) {
		log("warn", `Upload chunk rejected for ${src}: duplicate index uploadId=${uploadId} index=${chunkIndex}`);
		return;
	}
	session.chunks.set(normalizedChunkIndex, base64Chunk);
	session.receivedChunks += 1;
	if (session.receivedChunks === 1 || session.receivedChunks === session.totalChunks || session.receivedChunks % 10 === 0) {
		log("debug", `Upload chunk stored for ${src}: uploadId=${uploadId} chunk=${normalizedChunkIndex}/${session.totalChunks} chars=${base64Chunk.length}`);
	}
}

async function finalizeUploadSession(src, uploadId) {
	const session = PENDING_UPLOADS.get(uploadId);
	if (!session) {
		log("warn", `Upload complete rejected for ${src}: unknown uploadId=${uploadId}`);
		return;
	}
	try {
		log("debug", `Upload complete received for ${src}: uploadId=${uploadId} receivedChunks=${session.receivedChunks}/${session.totalChunks}`);
		if (session.receivedChunks !== session.totalChunks) {
			log("warn", `Upload complete rejected for ${src}: incomplete uploadId=${uploadId} receivedChunks=${session.receivedChunks} totalChunks=${session.totalChunks}`);
			return;
		}
		const orderedChunks = [];
		for (let chunkIndex = 1; chunkIndex <= session.totalChunks; chunkIndex += 1) {
			const chunkBase64 = session.chunks.get(chunkIndex);
			if (!chunkBase64) {
				log("warn", `Upload complete rejected for ${src}: missing chunk uploadId=${uploadId} index=${chunkIndex}`);
				return;
			}
			orderedChunks.push(chunkBase64);
		}
		fs.writeFileSync(session.filePath, Buffer.from(orderedChunks.join(""), "base64"));
		await uploadSavedBodycamClip(src, session);
	} finally {
		safeDeleteFile(session.filePath);
		PENDING_UPLOADS.delete(uploadId);
	}
}

on("SonoranCAD::bodycam::UploadSavedRecording", async (src, payload, filePath) => {
	const sessionPayload = payload && typeof payload === "object" ? payload : {};
	const session = {
		src: Number(src),
		uploadId: sessionPayload.uploadId || `direct-${Date.now()}`,
		fileName: sanitizeFileName(sessionPayload.fileName),
		filePath: filePath,
		payload: sessionPayload,
	};
	try {
		log("debug", `Direct upload accepted for ${session.src}: uploadId=${session.uploadId} filePath=${filePath}`);
		await uploadSavedBodycamClip(session.src, session);
	} finally {
		safeDeleteFile(filePath);
	}
});

onNet("SonoranCAD::bodycam::UploadRecordingInit", (payload) => {
	const src = Number(global.source);
	createUploadSession(src, payload || {});
});

onNet("SonoranCAD::bodycam::UploadRecordingChunk", (uploadId, chunkIndex, base64Chunk) => {
	const src = Number(global.source);
	appendUploadChunk(src, uploadId, chunkIndex, base64Chunk);
});

onNet("SonoranCAD::bodycam::UploadRecordingComplete", (uploadId) => {
	const src = Number(global.source);
	finalizeUploadSession(src, uploadId);
});

onNet("SonoranCAD::bodycam::LogRecordingEvent", (payload) => {
	const src = Number(global.source);
	const details = payload || {};
	log(details.level || "debug", `src=${src} event=${details.event || "unknown"} source=${details.sourceType || "unknown"} trigger=${details.trigger || "n/a"} reason=${details.reason || "n/a"}`);
});

on("playerDropped", () => {
	const src = Number(global.source);
	for (const [uploadId, session] of PENDING_UPLOADS.entries()) {
		if (session && session.src === src) {
			safeDeleteFile(session.filePath);
			PENDING_UPLOADS.delete(uploadId);
		}
	}
});
