(() => {
	const fs = require("fs");
	const path = require("path");
	const crypto = require("crypto");

	exports("CreateImageToken", function () {
		return crypto.randomBytes(18).toString("hex");
	});

	exports("SaveBase64ToFile", function (base64String, filename) {
		let base64Image = base64String.split(";base64,").pop();
		fs.writeFile(filename, base64Image, { encoding: "base64" }, function (err) {
			return true;
		});
	});

	exports("SaveBase64Image", function (dataUrl, filename, maxBytes) {
		try {
			if (typeof dataUrl !== "string" || typeof filename !== "string") {
				return { success: false, reason: "invalid_arguments" };
			}
			const requestedLimit = Number(maxBytes);
			const limit = Number.isFinite(requestedLimit) && requestedLimit > 0
				? Math.floor(requestedLimit)
				: 1024 * 1024;
			const prefix = dataUrl.match(/^data:(image\/(?:jpeg|png));base64,/);
			if (!prefix) {
				return { success: false, reason: "invalid_image" };
			}
			const encodedLength = dataUrl.length - prefix[0].length;
			const maxEncodedLength = Math.ceil(limit / 3) * 4;
			if (encodedLength > maxEncodedLength) {
				return { success: false, reason: "image_too_large" };
			}
			const encodedImage = dataUrl.slice(prefix[0].length);
			if (!encodedImage || !/^[A-Za-z0-9+/=]+$/.test(encodedImage)) {
				return { success: false, reason: "invalid_image" };
			}
			const image = Buffer.from(encodedImage, "base64");
			if (!image.length || image.length > limit) {
				return { success: false, reason: image.length ? "image_too_large" : "invalid_image" };
			}
			fs.writeFileSync(filename, image, { flag: "wx" });
			return {
				success: true,
				bytes: image.length,
				extension: prefix[1] === "image/png" ? "png" : "jpg",
			};
		} catch (err) {
			return {
				success: false,
				reason: err && err.code ? err.code : "write_failed",
			};
		}
	});

	exports("createScreenshotDirectory", async function (apiID) {
		let screenshotFolder = `${GetResourcePath(GetCurrentResourceName())}/screenshots`;
		if (!fs.existsSync(screenshotFolder)) {
			fs.mkdirSync(screenshotFolder);
		}
		let dir = `${GetResourcePath(GetCurrentResourceName())}/screenshots/${apiID}`;
		if (!fs.existsSync(dir)) {
			fs.mkdirSync(dir);
		}
		return dir;
	});

	function deleteFileWithRetry(filePath, maxRetries = 50, interval = 100, attempt = 0) {
		try {
			fs.unlink(filePath, (err) => {
				if (err) {
					if (attempt < maxRetries) {
						setTimeout(() => {
							deleteFileWithRetry(filePath, maxRetries, interval, attempt + 1);
						}, interval);
					}
				}
			});
		} catch (e) {}
	}

	async function deleteDirectoryWithRetry(dirPath) {
		await fs.rm(dirPath, { recursive: true }, (err) => {
			if (err) {
				console.log(err);
			}
		});
	}

	exports("createScreenshotFilename", async function (directory) {
		try {
			let files = fs
				.readdirSync(directory)
				.filter((file) => file.endsWith(".jpg"))
				.map((file) => ({
					name: file,
					time: fs.statSync(path.join(directory, file)).mtime.getTime(),
				}))
				.sort((a, b) => a.time - b.time);

			let nextFileNumber;
			if (files.length >= 10) {
				const highestNumber = Math.max(...files.map((file) => parseInt(file.name.replace(".jpg", ""), 10)));
				nextFileNumber = highestNumber + 1;
				if (files.length > 10) {
					const oldestFile = files[0].name;
					deleteFileWithRetry(path.join(directory, oldestFile));
				}
			} else {
				let existingNumbers = files.map((file) => parseInt(file.name, 10));
				nextFileNumber = 1;
				for (let i = 1; i <= 10; i++) {
					if (!existingNumbers.includes(i)) {
						nextFileNumber = i;
						break;
					}
				}
			}
			return `${nextFileNumber}.jpg`;
		} catch (e) {
			emit("SonoranCAD::core:writeLog", "error", "[image] ERR-CORE-906 Failed to create screenshot filename. More: https://sonorancad.com/error/ERR-CORE-906");
		}
	});

	exports("deleteDirectory", async function (dir) {
		try {
			if (fs.existsSync(dir)) {
				deleteDirectoryWithRetry(dir);
			}
		} catch (e) {}
	});

	exports("clearScreenshotsFolder", async function () {
		try {
			let dir = `${GetResourcePath(GetCurrentResourceName())}/screenshots`;
			if (fs.existsSync(dir)) {
				deleteDirectoryWithRetry(dir);
			}
		} catch (e) {}
	});
})();
