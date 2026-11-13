import { defineConfig } from "vitest/config";

export default defineConfig({
	test: {
		include: ["test/**/*.test.ts"],
		coverage: {
			include: ["src/**/*.ts"],
			// plugin.ts, actions/slot.ts and inspector-entry.ts only wire the logic below to the Stream Deck SDK.
			exclude: ["src/plugin.ts", "src/actions/slot.ts", "src/inspector-entry.ts"],
			reporter: ["text"],
		},
	},
});
