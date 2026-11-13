/** Per-key settings: which action-bar button the key mirrors. */
export type SlotSettings = {
	/** Bar 1-5 (stored as a string by the property inspector). */
	bar?: number | string;
	/** Button 1-12. */
	button?: number | string;
};

/** Settings as the property inspector stores them. */
export type NormalisedSettings = { bar?: string; button?: string };

/** Buttons mirrored per bar (docs/strip-format.md §5.1). */
export const BAR_BUTTONS = [12, 12, 12, 12, 12] as const;
export const SLOT_COUNT = 60;

function parse(value: number | string | undefined): number | undefined {
	const n = typeof value === "string" ? Number.parseInt(value, 10) : value;
	return n !== undefined && Number.isInteger(n) ? n : undefined;
}

/** Number of buttons on a bar, or 0 for an unknown bar. */
export function buttonsFor(bar: number | string | undefined): number {
	const b = parse(bar);
	return b !== undefined && b >= 1 && b <= BAR_BUTTONS.length ? BAR_BUTTONS[b - 1]! : 0;
}

/** Strip slot 0-59 for a key's settings, or undefined when not configured or out of range. */
export function slotIndex(settings: SlotSettings | undefined): number | undefined {
	const bar = parse(settings?.bar);
	const button = parse(settings?.button);
	if (bar === undefined || button === undefined) return undefined;
	if (button < 1 || button > buttonsFor(bar)) return undefined;
	return (bar - 1) * 12 + (button - 1);
}

/**
 * Settings after choosing a bar: keeps the button when the new bar has it,
 * otherwise clears it.
 */
export function normaliseSettings(settings: SlotSettings): NormalisedSettings {
	const out: NormalisedSettings = {};
	if (buttonsFor(settings.bar) > 0) out.bar = String(parse(settings.bar));
	const button = parse(settings.button);
	if (out.bar !== undefined && button !== undefined && button >= 1 && button <= buttonsFor(out.bar)) {
		out.button = String(button);
	}
	return out;
}
