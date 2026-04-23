(() => {
    const fs = require("fs");
    const http = require("http");
    const https = require("https");
    const path = require("path");

    exports("SaveBase64ToFile", function (base64String, filename) {
        let base64Image = base64String.split(";base64,").pop();
        fs.writeFile(filename, base64Image, { encoding: "base64" }, function (err) {
            return true;
        });
    });

    exports("createPDFDirectory", async function (apiID) {
        let screenshotFolder = `${GetResourcePath(GetCurrentResourceName())}/submodules/recordPrinter/pdfs`;
        if (!fs.existsSync(screenshotFolder)) {
            fs.mkdirSync(screenshotFolder);
        }
        let dir = `${GetResourcePath(GetCurrentResourceName())}/submodules/recordPrinter/pdfs/${apiID}`;
        if (!fs.existsSync(dir)) {
            fs.mkdirSync(dir);
        }
        return dir;
    });

    exports("savePdfFromUrl", function (url, filename) {
        return new Promise((resolve, reject) => {
            const proto = url.startsWith('https') ? https : http;
            const filePath = path.resolve(filename);
            const file = fs.createWriteStream(filePath);

            proto.get(url, (response) => {
                if (response.statusCode !== 200) {
                    return reject(new Error(`Failed to get PDF. Status: ${response.statusCode}`));
                }

                response.pipe(file);

                file.on('finish', () => {
                    file.close(() => resolve(filePath));
                });
            }).on('error', (err) => {
                fs.unlink(filePath, () => reject(err));
            });
        });
    });
})();
