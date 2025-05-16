var unzipper = require("unzipper");
var fs = require("fs");
let updaterIgnore = { ignore: [] };

try {
	const raw = fs.readFileSync(GetResourcePath(GetCurrentResourceName()) + "/configuration/updateIgnore.json", "utf8");
	updaterIgnore = JSON.parse(raw);
} catch (err) {
	console.warn("Failed to load updateIgnore.json, defaulting to empty ignore list.");
}

exports('UnzipFile', (file, dest) => {
	try {
		if (!fs.existsSync(file)) {
			console.error("File does not exist: " + file);
			emit("unzipCoreCompleted", false, "File not found");
			return;
		}

		fs.createReadStream(file)
			.pipe(unzipper.Parse())
			.on('entry', function(entry) {
				const type = entry.type;
				let fileName = entry.path;
				const finalPath = `${dest}/${fileName}`;
				const ignoreEntry = updaterIgnore.ignore.find(ignore => finalPath.includes(ignore.path));
				if (ignoreEntry) {
					emit("SonoranCAD::core:writeLog", "info", `IGNORED: ${finalPath} — ${ignoreEntry.reason}`);
					entry.autodrain();
				} else {
					// Ensure parent directories exist
					const dir = require("path").dirname(finalPath);
					if (!fs.existsSync(dir)) {
						fs.mkdirSync(dir, { recursive: true });
					}
					entry.pipe(fs.createWriteStream(finalPath));
				}
			})
			.on('close', () => {
				emit("unzipCoreCompleted", true);
			})
			.on('error', (error) => {
				emit("unzipCoreCompleted", false, error);
			});
	} catch (ex) {
		console.error("Failed to unzip a file: " + ex);
		emit("unzipCoreCompleted", false, ex.toString());
	}
});

function deleteDirR(dir) {
	fs.rmdir(dir, {recursive:true}, (err) => {
        if (err) {
            console.log(err)
            return false, err;
        }
    });
    return true;
}

exports('UnzipFolder', (file, name, dest) => {
    let firstDir = null;
	let hasStreamFolder = false;
	const rootPath = GetResourcePath(GetCurrentResourceName());
	const streamPath = rootPath + "/stream/" + name + "/";
	if (!fs.existsSync(file)) {
		console.error("File " + file + " doesn't exist.");
		return false;
	}
	fs.createReadStream(file).pipe(unzipper.Parse())
		.on('entry', function(entry) {
			var fileName = entry.path;
			const type = entry.type;
			if (type == "Directory") {
				if (fileName.includes("stream") && !hasStreamFolder) {
					hasStreamFolder = true;
					deleteDirR(streamPath);
				}
				if (firstDir == null) {
					firstDir = fileName;
				}
				else {
					fileName = fileName.replace(firstDir, "");
					if (!fs.existsSync(dest + fileName)) {
						fs.mkdirSync(dest + fileName);
					}
				}
			}
			if (type == "File") {
				fileName = fileName.replace(firstDir, "");
				let finalPath = dest + fileName;
				if (fileName.includes("stream")) {
					let file = fileName.replace(/^.*[\\\/]/, '');
					finalPath = `${rootPath}/stream/${name}/${file}`;
					if (!fs.existsSync(`${rootPath}/stream/${name}/`)) {
						fs.mkdirSync(`${rootPath}/stream/${name}/`);
					}
				}
				emit("SonoranCAD::core:writeLog", "debug", "write: " + finalPath);
				let ignoreEntry = updaterIgnore.ignore.find(ignore => finalPath.includes(ignore.path));
				if (ignoreEntry) {
					emit("SonoranCAD::core:writeLog", "info", `IGNORED: ${finalPath} — ${ignoreEntry.reason}`);
					entry.autodrain(); // Skip writing this file
				} else {
					entry.pipe(fs.createWriteStream(finalPath));
				}
			} else {
				entry.autodrain();

			}
	}).on('close', () => {
		emit("unzipCompleted", true, name, file);
	}).on('error', (error) => {
		emit("unzipCompleted", false, name, file, error);
	})
});

exports('CreateFolderIfNotExisting', (path) => {
    if (!fs.existsSync(path)) {
        fs.mkdirSync(path);
    }
});

exports('DeleteDirectoryRecursively', (dir) => {
    fs.rmdir(dir, {recursive:true}, (err) => {
        if (err) {
            console.log(err)
            return false, err;
        }
    });
    return true
});