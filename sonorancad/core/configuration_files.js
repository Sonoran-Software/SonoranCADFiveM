"use strict";

const fs = require("fs");
const path = require("path");

function configurationRoot() {
    return path.resolve(GetResourcePath(GetCurrentResourceName()), "configuration");
}

function isLegacyConfigurationFile(fileName, parentName) {
    if (parentName === "config-backup") {
        return true;
    }
    return fileName === "livemap_vehicle_models.json"
        || /_config(?:\.dist)?\.lua$/i.test(fileName);
}

function relativeResourcePath(fullPath) {
    return path.relative(GetResourcePath(GetCurrentResourceName()), fullPath).split(path.sep).join("/");
}

function scanDirectory(directory, root, result) {
    if (!fs.existsSync(directory)) {
        return;
    }
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
        const fullPath = path.resolve(directory, entry.name);
        if (fullPath !== root && !fullPath.startsWith(root + path.sep)) {
            throw new Error("configuration path escaped the resource directory");
        }
        if (entry.isSymbolicLink()) {
            if (isLegacyConfigurationFile(entry.name, path.basename(directory))) {
                result.push(fullPath);
            }
            continue;
        }
        if (entry.isDirectory()) {
            if (entry.name === "config-backup") {
                scanDirectory(fullPath, root, result);
            }
            continue;
        }
        if (entry.isFile() && isLegacyConfigurationFile(entry.name, path.basename(directory))) {
            result.push(fullPath);
        }
    }
}

function legacyFiles() {
    const root = configurationRoot();
    const files = [];
    scanDirectory(root, root, files);
    files.sort();
    return files;
}

function sanitizeBootstrapConfig(root, errors) {
    const configPath = path.resolve(root, "config.json");
    const temporaryPath = configPath + ".migration.tmp";
    if (!fs.existsSync(configPath)) {
        errors.push("configuration/config.json is missing");
        return false;
    }
    try {
        const parsed = JSON.parse(fs.readFileSync(configPath, "utf8"));
        const bootstrap = {
            communityID: parsed.communityID,
            apiKey: parsed.apiKey,
            mode: parsed.mode || "production",
            serverId: parsed.serverId || 1
        };
        fs.writeFileSync(temporaryPath, JSON.stringify(bootstrap, null, 4) + "\n", { encoding: "utf8", mode: 0o600 });
        fs.renameSync(temporaryPath, configPath);
        return true;
    } catch (err) {
        try {
            if (fs.existsSync(temporaryPath)) fs.unlinkSync(temporaryPath);
        } catch (_) {
        }
        errors.push("configuration/config.json: " + (err && err.message ? err.message : String(err)));
        return false;
    }
}

exports("GetLegacyConfigurationFiles", () => {
    try {
        return JSON.stringify({ files: legacyFiles().map(relativeResourcePath) });
    } catch (err) {
        return JSON.stringify({ files: [], error: err && err.message ? err.message : String(err) });
    }
});

exports("DeleteLegacyConfigurationFiles", () => {
    const root = configurationRoot();
    const errors = [];
    const deleted = [];
    let files;
    try {
        files = legacyFiles();
    } catch (err) {
        return JSON.stringify({ success: false, deleted, errors: [err && err.message ? err.message : String(err)] });
    }

    for (const filePath of files) {
        try {
            fs.unlinkSync(filePath);
            deleted.push(relativeResourcePath(filePath));
        } catch (err) {
            errors.push(relativeResourcePath(filePath) + ": " + (err && err.message ? err.message : String(err)));
        }
    }

    const backupDirectory = path.resolve(root, "config-backup");
    try {
        if (fs.existsSync(backupDirectory) && fs.readdirSync(backupDirectory).length === 0) {
            fs.rmdirSync(backupDirectory);
        }
    } catch (err) {
        errors.push("configuration/config-backup: " + (err && err.message ? err.message : String(err)));
    }

    if (errors.length === 0) {
        sanitizeBootstrapConfig(root, errors);
    }

    return JSON.stringify({ success: errors.length === 0, deleted, errors });
});
