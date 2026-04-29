(() => {
    var unzipper = require("unzipper");
    var fs = require("fs");
    var path = require("path");
    var sentResult = false;

    function normalizePathForMatch(value) {
        return String(value || "").replace(/\\/g, "/");
    }

    function getIgnoreList(updaterIgnore) {
        if (!updaterIgnore || !Array.isArray(updaterIgnore.ignore)) return [];
        return updaterIgnore.ignore;
    }

    function findIgnoreEntry(entryPath, fullPath, updaterIgnore) {
        const normalizedEntryPath = normalizePathForMatch(entryPath);
        const normalizedFullPath = normalizePathForMatch(fullPath);
        const ignoreList = getIgnoreList(updaterIgnore);

        for (const ignore of ignoreList) {
            if (!ignore || !ignore.path) continue;

            const candidate = normalizePathForMatch(ignore.path);
            const directCandidate = candidate.startsWith("/") ? candidate.slice(1) : candidate;

            if (
                normalizedEntryPath.includes(candidate) ||
                normalizedEntryPath.includes(directCandidate) ||
                normalizedFullPath.includes(candidate) ||
                normalizedFullPath.includes(directCandidate)
            ) {
                return ignore;
            }
        }

        return null;
    }

    function ensureDirectory(fullPath) {
        let shouldCreate = !fs.existsSync(fullPath);
        if (!shouldCreate && !fs.statSync(fullPath).isDirectory()) {
            fs.rmSync(fullPath, { recursive: true, force: true });
            shouldCreate = true;
        }

        if (shouldCreate) {
            fs.mkdirSync(fullPath, { recursive: true });
        }
    }

    function isWithinDirectory(root, candidate) {
        const relative = path.relative(root, candidate);
        return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
    }

    function formatUpdaterError(err, fullPath) {
        const code = err && err.code;
        const failedPath = fullPath || (err && err.path) || "unknown path";

        if (code === "EACCES" || code === "EPERM") {
            return new Error(
                "Automatic SonoranCAD update failed because the updater could not write to " +
                failedPath +
                ". Check resource folder permissions and try again: https://sonoran.link/cadupdateperms"
            );
        }

        return err instanceof Error ? err : new Error(String(err));
    }

    function writeEntryToFile(entry, fullPath) {
        return new Promise((resolve, reject) => {
            const output = fs.createWriteStream(fullPath);
            let settled = false;

            const finish = (err) => {
                if (settled) return;
                settled = true;
                if (err) {
                    reject(formatUpdaterError(err, fullPath));
                    return;
                }
                resolve();
            };

            const fail = (err) => {
                try {
                    entry.unpipe(output);
                } catch (_) {}

                if (!output.destroyed) {
                    output.destroy();
                }

                entry.autodrain();
                finish(err);
            };

            output.once("error", fail);
            entry.once("error", fail);
            output.once("finish", () => finish());
            entry.pipe(output);
        });
    }

    function trackWrite(entry, fullPath) {
        return writeEntryToFile(entry, fullPath)
            .then(() => ({ ok: true }))
            .catch((err) => ({ ok: false, error: formatUpdaterError(err, fullPath) }));
    }

    function unzipUpdate(file, dest, updaterIgnore) {
        const ignoredEntries = [];
        const resolvedDest = path.resolve(dest);

        return new Promise((resolve, reject) => {
            const pendingWrites = [];
            const parser = unzipper.Parse();
            const input = fs.createReadStream(file);

            const finish = () => {
                Promise.all(pendingWrites)
                    .then((results) => {
                        const failedWrite = results.find((result) => !result.ok);
                        if (failedWrite) {
                            reject(failedWrite.error);
                            return;
                        }
                        resolve(ignoredEntries);
                    })
                    .catch(reject);
            };

            input.on("error", reject);
            parser.on("entry", (entry) => {
                try {
                    const entryPath = entry.path;
                    const type = entry.type;
                    const fullPath = path.resolve(resolvedDest, entryPath);

                    // Guard against path traversal from malformed archives.
                    if (!isWithinDirectory(resolvedDest, fullPath)) {
                        entry.autodrain();
                        return;
                    }

                    const ignoreEntry = findIgnoreEntry(entryPath, fullPath, updaterIgnore);
                    if (ignoreEntry) {
                        ignoredEntries.push({
                            path: fullPath,
                            reason: ignoreEntry.reason || "Ignored by updateIgnore"
                        });
                        entry.autodrain();
                        return;
                    }

                    if (type === "Directory") {
                        ensureDirectory(fullPath);
                        entry.autodrain();
                        return;
                    }

                    ensureDirectory(path.dirname(fullPath));
                    pendingWrites.push(trackWrite(entry, fullPath));
                } catch (err) {
                    entry.autodrain();
                    reject(formatUpdaterError(err));
                }
            });
            parser.on("close", finish);
            parser.on("error", reject);
            input.pipe(parser);
        });
    }

    function sendResult(message, exitCode) {
        if (sentResult) return;
        sentResult = true;
        process.exitCode = exitCode;

        if (typeof process.send === "function") {
            process.send(message, () => {
                if (typeof process.disconnect === "function") {
                    process.disconnect();
                }
            });
            return;
        }
    }

    process.on("uncaughtException", (err) => {
        sendResult({ ok: false, error: formatUpdaterError(err).message }, 1);
    });

    process.on("unhandledRejection", (err) => {
        sendResult({ ok: false, error: formatUpdaterError(err).message }, 1);
    });

    process.once("message", ({ file, dest, updaterIgnore }) => {
        unzipUpdate(file, dest, updaterIgnore)
            .then((ignored) => sendResult({ ok: true, ignored: ignored }, 0))
            .catch((err) => sendResult({ ok: false, error: err && err.message ? err.message : String(err) }, 1));
    });
})();
