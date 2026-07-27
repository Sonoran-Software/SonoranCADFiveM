(() => {
    const fs = require("fs");
    const http = require("http");
    const https = require("https");
    const path = require("path");
    const ERROR_DOC_BASE_URL = "https://sonorancad.com/error/";

    function formatFileError(code, stage, filePath, err) {
        const fsCode = err && err.code ? err.code : "UNKNOWN";
        const message = err && err.message ? err.message : String(err);
        return `${code} stage=${stage} path=${filePath} fsCode=${fsCode} message=${message}`;
    }

    function reportFileError(code, stage, filePath, err) {
        const details = formatFileError(code, stage, filePath, err);
        console.error(`[recordPrinter] ${details}. More: ${ERROR_DOC_BASE_URL}${code.toLowerCase()}`);
        return new Error(details);
    }

    exports("SaveBase64ToFile", function (base64String, filename) {
        let base64Image = base64String.split(";base64,").pop();
        fs.writeFile(filename, base64Image, { encoding: "base64" }, function (err) {
            return true;
        });
    });

    exports("createPDFDirectory", async function (apiID) {
        const pdfRoot = path.join(
            GetResourcePath(GetCurrentResourceName()),
            "submodules",
            "recordPrinter",
            "pdfs"
        );
        const dir = path.join(pdfRoot, String(apiID));

        try {
            fs.mkdirSync(dir, { recursive: true });
            fs.accessSync(dir, fs.constants.W_OK);
            return dir;
        } catch (err) {
            throw reportFileError("ERR-RP-102", "create-directory", dir, err);
        }
    });

    exports("savePdfFromUrl", function (url, filename) {
        return new Promise((resolve, reject) => {
            const filePath = path.resolve(filename);
            const proto = url.startsWith("https") ? https : http;
            let settled = false;
            let file;
            let fileOpened = false;

            const removePartialFile = () => {
                if (fileOpened) {
                    fs.unlink(filePath, () => {});
                }
            };

            const fail = (stage, err) => {
                if (settled) {
                    return;
                }
                settled = true;
                if (file) {
                    if (fileOpened) {
                        if (file.closed) {
                            removePartialFile();
                        } else {
                            file.once("close", removePartialFile);
                        }
                    }
                    file.destroy();
                } else {
                    removePartialFile();
                }
                reject(reportFileError("ERR-RP-103", stage, filePath, err));
            };

            let request;
            try {
                request = proto.get(url, (response) => {
                    if (response.statusCode !== 200) {
                        response.resume();
                        fail("http-response", new Error(`Unexpected HTTP status ${response.statusCode}`));
                        return;
                    }

                    try {
                        file = fs.createWriteStream(filePath);
                    } catch (err) {
                        response.destroy();
                        fail("open-file", err);
                        return;
                    }

                    file.on("open", () => {
                        fileOpened = true;
                    });
                    file.on("error", (err) => {
                        response.destroy();
                        fail("write-file", err);
                    });

                    response.on("error", (err) => fail("download-stream", err));
                    response.pipe(file);

                    file.on("finish", () => {
                        file.close((err) => {
                            if (err) {
                                fail("close-file", err);
                                return;
                            }
                            if (!settled) {
                                settled = true;
                                resolve(filePath);
                            }
                        });
                    });
                });

                request.on("error", (err) => fail("http-request", err));
            } catch (err) {
                fail("http-request", err);
            }
        });
    });
})();
