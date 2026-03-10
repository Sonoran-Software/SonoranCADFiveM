(() => {
    var unzipper = require("unzipper");
    var fs = require("fs");
    var path = require("path");

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

    function unzipUpdate(file, dest, updaterIgnore) {
        const ignoredEntries = [];
        const resolvedDest = path.resolve(dest);

        return new Promise((resolve, reject) => {
            fs.createReadStream(file).pipe(unzipper.Parse()).on("entry", (entry) => {
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
                entry.pipe(fs.createWriteStream(fullPath));
            }).on("close", () => resolve(ignoredEntries))
            .on("error", reject);
        });
    }

    function sendResult(message, exitCode) {
        if (typeof process.send === "function") {
            process.send(message, () => process.exit(exitCode));
            return;
        }

        process.exit(exitCode);
    }

    process.once("message", ({ file, dest, updaterIgnore }) => {
        unzipUpdate(file, dest, updaterIgnore)
            .then((ignored) => sendResult({ ok: true, ignored: ignored }, 0))
            .catch((err) => sendResult({ ok: false, error: err && err.message ? err.message : String(err) }, 1));
    });
})();
