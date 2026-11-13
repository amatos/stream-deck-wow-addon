import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

const SCRIPT = join(__dirname, "../../tools/third-party-licenses.mjs");

let project: string;

function makeProject(packages: Record<string, { version: string; license: string; dev?: boolean; licenseFile?: string }>) {
	project = mkdtempSync(join(tmpdir(), "licenses-"));
	const lockPackages: Record<string, object> = { "": { name: "fixture" } };
	for (const [name, { licenseFile, ...pkg }] of Object.entries(packages)) {
		const path = `node_modules/${name}`;
		lockPackages[path] = pkg;
		mkdirSync(join(project, path), { recursive: true });
		if (licenseFile) writeFileSync(join(project, path, licenseFile), `${name} license text\n`);
	}
	writeFileSync(join(project, "package-lock.json"), JSON.stringify({ packages: lockPackages }));
}

function run() {
	return spawnSync(process.execPath, [SCRIPT, project], { encoding: "utf8" });
}

afterEach(() => rmSync(project, { recursive: true, force: true }));

describe("third-party-licenses", () => {
	it("prints runtime dependencies' licenses and skips dev dependencies", () => {
		makeProject({
			ws: { version: "8.0.0", license: "MIT", licenseFile: "LICENSE" },
			"@scope/lib": { version: "1.2.3", license: "ISC", licenseFile: "LICENSE.md" },
			vitest: { version: "5.0.0", license: "MIT", dev: true, licenseFile: "LICENSE" },
		});

		const result = run();

		expect(result.status).toBe(0);
		expect(result.stdout).toContain("@scope/lib 1.2.3 (ISC)");
		expect(result.stdout).toContain("@scope/lib license text");
		expect(result.stdout).toContain("ws 8.0.0 (MIT)");
		expect(result.stdout).toContain("ws license text");
		expect(result.stdout).not.toContain("vitest");
		expect(result.stdout.indexOf("@scope/lib")).toBeLessThan(result.stdout.indexOf("ws 8.0.0"));
	});

	it("fails when a runtime dependency has no license file", () => {
		makeProject({ ws: { version: "8.0.0", license: "MIT" } });

		const result = run();

		expect(result.status).toBe(1);
		expect(result.stderr).toContain("No license file");
	});
});
