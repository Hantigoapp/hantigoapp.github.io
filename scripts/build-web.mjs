// Copies the website files into www/ for the Android app.
import { mkdirSync, rmSync, copyFileSync } from "node:fs";
const files = ["index.html", "admin.html", "privacy.html", "manifest.json", "vendor/exceljs.min.js", "vendor/jspdf.umd.min.js", "icon.svg", "icon-192.png", "icon-512.png"];
rmSync("www", { recursive: true, force: true });
mkdirSync("www/vendor", { recursive: true });
for (const f of files) copyFileSync(f, "www/" + f);
console.log("www/ ready:", files.join(", "));
