import { SLOT_COUNT } from "./slots";

/** Messages between the helper app and this plugin (docs/deck-protocol.md). */
export const DEFAULT_URL = "ws://127.0.0.1:47811";

export type HelperMessage =
	| { type: "hello"; version: number }
	| { type: "slot"; slot: number; image: string };

/** Parses a helper message; undefined for anything malformed or unknown. */
export function parseHelperMessage(text: string): HelperMessage | undefined {
	let value: unknown;
	try {
		value = JSON.parse(text);
	} catch {
		return undefined;
	}
	if (typeof value !== "object" || value === null) return undefined;
	const m = value as Record<string, unknown>;
	if (m.type === "hello" && typeof m.version === "number") {
		return { type: "hello", version: m.version };
	}
	if (
		m.type === "slot" &&
		typeof m.slot === "number" &&
		Number.isInteger(m.slot) &&
		m.slot >= 0 &&
		m.slot < SLOT_COUNT &&
		typeof m.image === "string"
	) {
		return { type: "slot", slot: m.slot, image: m.image };
	}
	return undefined;
}

export function pressMessage(slot: number): string {
	return JSON.stringify({ type: "press", slot });
}
