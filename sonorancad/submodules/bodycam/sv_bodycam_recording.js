const API_CACHE = new Map();
const ACCOUNT_CACHE = new Map();
const MAX_FILE_SIZE_BYTES = 6000000;
const MAX_DURATION_MS = 120000;
const UPLOAD_URL = "https://api.sonorancad.com/upload";
let accountApiRegistered = false;

function log(level, message) {
	emit("SonoranCAD::core:writeLog", level, `[bodycam-recording] ${message}`);
}

function getCommunityId() {
	return GetConvar("sonoran_communityID", "");
}

function getPlayerIdentifierByType(src) {
	const preferred = (GetConvar("sonoran_primaryIdentifier", "steam") || "steam").toLowerCase();
	const identifiers = GetPlayerIdentifiers(String(src)) || [];
	for (const identifier of identifiers) {
		if (String(identifier).toLowerCase().startsWith(`${preferred}:`)) {
			return identifier;
		}
	}
	return identifiers[0] || null;
}

function buildMultipartPayload(fields, fileBuffer, fileName) {
	const boundary = `----sonorancad-${Date.now().toString(16)}-${Math.random().toString(16).slice(2)}`;
	const chunks = [];
	Object.entries(fields).forEach(([key, value]) => {
		if (value === undefined || value === null || value === "") {
			return;
		}
		chunks.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${key}"\r\n\r\n${String(value)}\r\n`));
	});
	chunks.push(
		Buffer.from(
			`--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${fileName}"\r\nContent-Type: video/webm\r\n\r\n`
		)
	);
	chunks.push(fileBuffer);
	chunks.push(Buffer.from(`\r\n--${boundary}--\r\n`));
	return {
		body: Buffer.concat(chunks),
		contentType: `multipart/form-data; boundary=${boundary}`,
	};
}

async function resolveAccountId(src, apiData) {
	if (apiData && apiData.account) {
		return apiData.account;
	}

	const identifier = getPlayerIdentifierByType(src);
	if (!identifier) {
		return null;
	}
	if (ACCOUNT_CACHE.has(identifier)) {
		return ACCOUNT_CACHE.get(identifier);
	}

	if (!accountApiRegistered) {
		exports[GetCurrentResourceName()].registerApiType("GET_ACCOUNT", "general");
		accountApiRegistered = true;
	}

	return new Promise((resolve) => {
		exports[GetCurrentResourceName()].performApiRequest(
			[{ apiId: identifier, username: apiData && apiData.username ? apiData.username : undefined }],
			"GET_ACCOUNT",
			(res, ok) => {
				if (!ok) {
					log("warn", `Account lookup failed for ${identifier}: ${res}`);
					resolve(null);
					return;
				}
				let parsed = null;
				try {
					parsed = typeof res === "string" ? JSON.parse(res) : res;
				} catch (err) {}
				const accountId =
					(parsed &&
						(parsed.uuid ||
							parsed.accId ||
							parsed.accountId ||
							(parsed.account && (parsed.account.uuid || parsed.account.id)))) ||
					null;
				if (accountId) {
					ACCOUNT_CACHE.set(identifier, accountId);
				}
				resolve(accountId);
			}
		);
	});
}

async function uploadBodycamClip(src, payload) {
	const community = getCommunityId();
	const apiData = API_CACHE.get(String(src)) || {};
	const account = await resolveAccountId(src, apiData);
	const unit = exports[GetCurrentResourceName()].GetUnitByPlayerId(String(src));
	const durationMs = Math.max(1, Math.min(MAX_DURATION_MS, Number(payload.durationMs) || 0));
	const fileName = (payload.fileName || `bodycam-${Date.now()}.webm`).replace(/[^a-zA-Z0-9._-]/g, "_");
	const metadata = payload.metadata || {};

	if (!community || !apiData.sessionId || !apiData.username || !account) {
		log("warn", `Upload rejected for ${src}: missing metadata community=${!!community} session=${!!apiData.sessionId} username=${!!apiData.username} account=${!!account}`);
		emitNet("SonoranCAD::bodycam::UploadResult", src, {
			ok: false,
			reason: "missing_metadata",
		});
		return;
	}

	if (!payload.fileData || typeof payload.fileData !== "string" || !payload.fileData.startsWith("data:video/webm")) {
		log("warn", `Upload rejected for ${src}: invalid file type`);
		emitNet("SonoranCAD::bodycam::UploadResult", src, {
			ok: false,
			reason: "invalid_file",
		});
		return;
	}

	const base64Data = payload.fileData.split(";base64,").pop();
	const fileBuffer = Buffer.from(base64Data, "base64");
	if (fileBuffer.byteLength > MAX_FILE_SIZE_BYTES) {
		log("warn", `Upload rejected for ${src}: clip_too_large size=${fileBuffer.byteLength}`);
		emitNet("SonoranCAD::bodycam::UploadResult", src, {
			ok: false,
			reason: "clip_too_large",
		});
		return;
	}
	if (durationMs < 1 || durationMs > MAX_DURATION_MS) {
		log("warn", `Upload rejected for ${src}: invalid_duration durationMs=${durationMs}`);
		emitNet("SonoranCAD::bodycam::UploadResult", src, {
			ok: false,
			reason: "invalid_duration",
		});
		return;
	}

	const fields = {
		community,
		account,
		sessionId: apiData.sessionId,
		username: apiData.username,
		type: "bodycam",
		durationMs,
		identId: metadata.identId || (unit && unit.id) || undefined,
		unitNumber: metadata.unitNumber || (unit && unit.data && unit.data.unitNum) || undefined,
		unitLocation: metadata.unitLocation || (unit && unit.location) || undefined,
	};

	const multipart = buildMultipartPayload(fields, fileBuffer, fileName);
	log("info", `Upload begin src=${src} trigger=${payload.trigger || "manual"} durationMs=${durationMs} size=${fileBuffer.byteLength}`);

	exports[GetCurrentResourceName()].HandleHttpRequest(
		UPLOAD_URL,
		(statusCode, res) => {
			if (Number(statusCode) < 200 || Number(statusCode) >= 300) {
				log("error", `Upload failure src=${src} status=${statusCode} body=${res}`);
				emitNet("SonoranCAD::bodycam::UploadResult", src, {
					ok: false,
					reason: "upload_failed",
					status: statusCode,
				});
				return;
			}
			log("info", `Upload success src=${src} status=${statusCode}`);
			emitNet("SonoranCAD::bodycam::UploadResult", src, {
				ok: true,
			});
		},
		"POST",
		multipart.body,
		{
			"Content-Type": multipart.contentType,
			"Content-Length": multipart.body.length,
		}
	);
}

onNet("SonoranCAD::Tablet::SetApiData", (sessionId, username) => {
	const src = String(global.source);
	const current = API_CACHE.get(src) || {};
	API_CACHE.set(src, {
		...current,
		sessionId,
		username,
	});
});

onNet("SonoranCAD::bodycam::UploadRecording", (payload) => {
	const src = Number(global.source);
	uploadBodycamClip(src, payload || {});
});

onNet("SonoranCAD::bodycam::LogRecordingEvent", (payload) => {
	const src = Number(global.source);
	const details = payload || {};
	log(details.level || "info", `src=${src} event=${details.event || "unknown"} source=${details.sourceType || "unknown"} trigger=${details.trigger || "n/a"} reason=${details.reason || "n/a"}`);
});

on("playerDropped", () => {
	const src = String(global.source);
	API_CACHE.delete(src);
});
