// Prints the license texts of a Node project's runtime (non-dev) dependencies, read from
// its package-lock.json and node_modules. Rollup bundles these into the plugin, so their
// notices have to ship with it.
//
// Usage: node tools/third-party-licenses.mjs <project-dir> > THIRD_PARTY_LICENSES
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const projectDir = process.argv[2];
if (!projectDir) {
	console.error("Usage: node tools/third-party-licenses.mjs <project-dir>");
	process.exit(1);
}

const lock = JSON.parse(readFileSync(join(projectDir, "package-lock.json"), "utf8"));
const LICENSE_FILE = /^(licen[cs]e|copying)(\.(md|txt))?$/i;

const sections = [];
for (const [path, pkg] of Object.entries(lock.packages).sort(([a], [b]) => a.localeCompare(b))) {
	if (path === "" || pkg.dev) continue;

	const name = path.slice(path.lastIndexOf("node_modules/") + "node_modules/".length);
	const dir = join(projectDir, path);
	const file = readdirSync(dir).find((f) => LICENSE_FILE.test(f));
	if (!file) {
		console.error(`No license file in ${dir}; run npm install, or add its notice by hand.`);
		process.exit(1);
	}

	const text = readFileSync(join(dir, file), "utf8").trim();
	sections.push(`${name} ${pkg.version} (${pkg.license})\n${"-".repeat(60)}\n\n${text}\n`);
}

console.log("The WoW Bars Stream Deck plugin includes the following third-party software.\n");
console.log(sections.join(`\n${"=".repeat(60)}\n\n`));
