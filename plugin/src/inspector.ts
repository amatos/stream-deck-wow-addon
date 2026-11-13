/**
 * Property inspector for the WoW Slot action, built into ui/inspector.js.
 * Each bar lists only the buttons it has, and changing bars drops a button the new bar does not have.
 */
import { BAR_BUTTONS, buttonsFor, type NormalisedSettings, normaliseSettings, type SlotSettings } from "./slots";

/** The bits of a <select> the inspector uses. */
export interface SelectLike {
	value: string;
	innerHTML: string;
	addEventListener(type: "change", listener: () => void): void;
}

export function barOptionsHTML(): string {
	const labels = ["Bar 1 (main)", "Bar 2", "Bar 3", "Bar 4", "Bar 5"];
	return (
		`<option value="">Choose a bar</option>` +
		BAR_BUTTONS.map((_, i) => `<option value="${i + 1}">${labels[i]}</option>`).join("")
	);
}

export function buttonOptionsHTML(bar: string | undefined): string {
	const n = buttonsFor(bar);
	let html = `<option value="">${n ? "Choose a button" : "Choose a bar first"}</option>`;
	for (let b = 1; b <= n; b++) html += `<option value="${b}">${b}</option>`;
	return html;
}

/** Wires two selects to settings; `save` persists them. Returns a function to apply incoming settings. */
export function bindInspector(
	barSelect: SelectLike,
	buttonSelect: SelectLike,
	save: (settings: SlotSettings) => void,
): (settings: SlotSettings) => void {
	let current: NormalisedSettings = {};

	const show = (settings: SlotSettings) => {
		current = normaliseSettings(settings);
		barSelect.innerHTML = barOptionsHTML();
		barSelect.value = current.bar ?? "";
		buttonSelect.innerHTML = buttonOptionsHTML(current.bar);
		buttonSelect.value = current.button ?? "";
	};

	barSelect.addEventListener("change", () => {
		show({ bar: barSelect.value || undefined, button: current.button });
		save(current);
	});
	buttonSelect.addEventListener("change", () => {
		current = normaliseSettings({ bar: current.bar, button: buttonSelect.value || undefined });
		buttonSelect.value = current.button ?? "";
		save(current);
	});

	show({});
	return show;
}

type InspectorGlobals = {
	document: { getElementById(id: string): unknown };
	WebSocket: new (url: string) => {
		onopen: (() => void) | null;
		onmessage: ((ev: { data: string }) => void) | null;
		send(data: string): void;
	};
};

/**
 * Stream Deck calls window.connectElgatoStreamDeckSocket when the inspector opens.
 * Registers with Stream Deck, shows the key's settings and saves changes.
 */
export function connect(
	g: InspectorGlobals,
	port: string,
	uuid: string,
	registerEvent: string,
	_info: string,
	actionInfo: string,
): void {
	const ws = new g.WebSocket(`ws://127.0.0.1:${port}`);
	const save = (settings: SlotSettings) => ws.send(JSON.stringify({ event: "setSettings", context: uuid, payload: settings }));
	const apply = bindInspector(
		g.document.getElementById("bar") as SelectLike,
		g.document.getElementById("button") as SelectLike,
		save,
	);
	try {
		apply((JSON.parse(actionInfo) as { payload?: { settings?: SlotSettings } }).payload?.settings ?? {});
	} catch {
		apply({});
	}
	ws.onopen = () => ws.send(JSON.stringify({ event: registerEvent, uuid }));
	ws.onmessage = (ev) => {
		try {
			const m = JSON.parse(ev.data) as { event?: string; payload?: { settings?: SlotSettings } };
			if (m.event === "didReceiveSettings") apply(m.payload?.settings ?? {});
		} catch {
			/* ignore malformed messages */
		}
	};
}
