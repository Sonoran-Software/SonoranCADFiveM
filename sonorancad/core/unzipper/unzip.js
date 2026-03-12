(() => {
    var child_process = require("child_process");
    var unzipper = require("unzipper");
    var fs = require("fs");
    var path = require("path");

    var cachedUpdaterIgnore = { ignore: [] };

    function normalizePathForMatch(value) {
        return String(value || "").replace(/\\/g, "/");
    }

    function getIgnoreList(updaterIgnore) {
        if (!updaterIgnore || !Array.isArray(updaterIgnore.ignore)) return [];
        return updaterIgnore.ignore;
    }

    function findIgnoreEntryByPath(finalPath, updaterIgnore) {
        const normalizedFinalPath = normalizePathForMatch(finalPath);
        const ignoreList = getIgnoreList(updaterIgnore);

        for (const ignore of ignoreList) {
            if (!ignore || !ignore.path) continue;

            const candidate = normalizePathForMatch(ignore.path);
            const directCandidate = candidate.startsWith("/") ? candidate.slice(1) : candidate;

            if (
                normalizedFinalPath.includes(candidate) ||
                normalizedFinalPath.includes(directCandidate)
            ) {
                return ignore;
            }
        }

        return null;
    }

    function createChildError(message) {
        return new Error(message || "Unzip worker failed without an error message.");
    }

    function getWorkerPath() {
        return path.join(
            GetResourcePath(GetCurrentResourceName()),
            "core",
            "unzipper",
            "unzip-child.js"
        );
    }

    function unzipCoreInChild(file, dest, updaterIgnore) {
        return new Promise((resolve, reject) => {
            const worker = child_process.fork(getWorkerPath(), [], {
                windowsHide: true,
                stdio: ["ignore", "pipe", "pipe", "ipc"]
            });

            let settled = false;

            const finish = (err) => {
                if (settled) return;
                settled = true;
                if (err) reject(err);
                else resolve();
            };

            if (worker.stdout) {
                worker.stdout.on("data", (chunk) => {
                    const output = chunk.toString().trim();
                    if (output.length > 0) console.log(output);
                });
            }

            if (worker.stderr) {
                worker.stderr.on("data", (chunk) => {
                    const output = chunk.toString().trim();
                    if (output.length > 0) console.error(output);
                });
            }

            worker.once("message", (message) => {
                if (message && message.ok) {
                    if (Array.isArray(message.ignored)) {
                        for (const ignored of message.ignored) {
                            emit("SonoranCAD::core:writeLog", "info", "IGNORED: " + ignored.path + " - " + ignored.reason);
                        }
                    }
                    finish();
                    return;
                }

                finish(createChildError(message && message.error));
            });

            worker.once("error", (err) => finish(err));
            worker.once("exit", (code, signal) => {
                if (settled) return;
                if (code === 0) {
                    finish();
                    return;
                }

                const details = signal ? ("signal " + signal) : ("code " + code);
                finish(createChildError("Unzip worker exited with " + details + "."));
            });

            worker.send({ file, dest, updaterIgnore });
        });
    }

    exports("UnzipFile", (file, dest, updaterIgnore) => {
        cachedUpdaterIgnore = updaterIgnore || { ignore: [] };

        unzipCoreInChild(file, dest, cachedUpdaterIgnore)
            .then(() => emit("unzipCoreCompleted", true))
            .catch((err) => emit("unzipCoreCompleted", false, err && err.message ? err.message : String(err)));
    });

    function deleteDirR(dir) {
        fs.rmdir(dir, { recursive: true }, (err) => {
            if (err) {
                console.log(err);
                return false, err;
            }
        });
        return true;
    }

    exports("UnzipFolder", (file, name, dest, updaterIgnore) => {
        const effectiveIgnore = updaterIgnore || cachedUpdaterIgnore || { ignore: [] };
        let firstDir = null;
        let hasStreamFolder = false;
        const rootPath = GetResourcePath(GetCurrentResourceName());
        const streamPath = rootPath + "/stream/" + name + "/";

        if (!fs.existsSync(file)) {
            console.error("File " + file + " doesn't exist.");
            return false;
        }

        fs.createReadStream(file).pipe(unzipper.Parse()).on("entry", function(entry) {
            var fileName = entry.path;
            const type = entry.type;
            if (type === "Directory") {
                if (fileName.includes("stream") && !hasStreamFolder) {
                    hasStreamFolder = true;
                    deleteDirR(streamPath);
                }
                if (firstDir == null) {
                    firstDir = fileName;
                } else {
                    fileName = fileName.replace(firstDir, "");
                    if (!fs.existsSync(dest + fileName)) {
                        fs.mkdirSync(dest + fileName);
                    }
                }
            }
            if (type === "File") {
                fileName = fileName.replace(firstDir, "");
                let finalPath = dest + fileName;
                if (fileName.includes("stream")) {
                    let streamFile = fileName.replace(/^.*[\\\/]/, "");
                    finalPath = rootPath + "/stream/" + name + "/" + streamFile;
                    if (!fs.existsSync(rootPath + "/stream/" + name + "/")) {
                        fs.mkdirSync(rootPath + "/stream/" + name + "/");
                    }
                }
                emit("SonoranCAD::core:writeLog", "debug", "write: " + finalPath);
                let ignoreEntry = findIgnoreEntryByPath(finalPath, effectiveIgnore);
                if (ignoreEntry) {
                    emit("SonoranCAD::core:writeLog", "info", "IGNORED: " + finalPath + " - " + (ignoreEntry.reason || "Ignored by updateIgnore"));
                    entry.autodrain();
                } else {
                    entry.pipe(fs.createWriteStream(finalPath));
                }
            } else {
                entry.autodrain();
            }
        }).on("close", () => {
            emit("unzipCompleted", true, name, file);
        }).on("error", (error) => {
            emit("unzipCompleted", false, name, file, error);
        });
    });

    exports("CreateFolderIfNotExisting", (folderPath) => {
        if (!fs.existsSync(folderPath)) {
            fs.mkdirSync(folderPath);
        }
    });

    exports("DeleteDirectoryRecursively", (dir) => {
        fs.rmdir(dir, { recursive: true }, (err) => {
            if (err) {
                console.log(err);
                return false, err;
            }
        });
        return true;
    });
})();
