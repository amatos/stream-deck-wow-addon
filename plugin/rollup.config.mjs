import commonjs from "@rollup/plugin-commonjs";
import nodeResolve from "@rollup/plugin-node-resolve";
import terser from "@rollup/plugin-terser";
import typescript from "@rollup/plugin-typescript";

const sdPlugin = "cc.matos.streamdeck.wowbars.sdPlugin";
// "/*!" comments survive minification. Keep in sync with LICENSE.
const banner = "/*! WoW Bars Stream Deck plugin. Copyright (c) 2026 Alberth Matos. BSD-2-Clause License. */";

/** @type {import('rollup').RollupOptions[]} */
export default [
	{
		input: "src/plugin.ts",
		output: {
			file: `${sdPlugin}/bin/plugin.js`,
			banner,
			sourcemap: false,
		},
		plugins: [
			typescript({ include: ["src/**/*.ts"] }),
			nodeResolve({ browser: false, exportConditions: ["node"], preferBuiltins: true }),
			commonjs(),
			terser(),
			{
				name: "emit-module-package-file",
				generateBundle() {
					this.emitFile({ fileName: "package.json", source: `{ "type": "module" }`, type: "asset" });
				},
			},
		],
	},
	{
		// Property inspector: a classic script, so it loads from file:// without module CORS rules.
		input: "src/inspector-entry.ts",
		output: { file: `${sdPlugin}/ui/inspector.js`, format: "iife", banner },
		plugins: [typescript({ include: ["src/**/*.ts"] }), terser()],
	},
];
