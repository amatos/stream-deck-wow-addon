import { describe, expect, it, vi } from "vitest";

import { barOptionsHTML, bindInspector, buttonOptionsHTML, connect, type SelectLike } from "../src/inspector";
import { normaliseSettings } from "../src/slots";

class FakeSelect implements SelectLike {
	value = "";
	innerHTML = "";
	private listener?: () => void;
	addEventListener(_type: "change", listener: () => void): void {
		this.listener = listener;
	}
	choose(value: string): void {
		this.value = value;
		this.listener?.();
	}
	get options(): string[] {
		return [...this.innerHTML.matchAll(/value="([^"]*)"/g)].map((m) => m[1]!);
	}
}

describe("normaliseSettings", () => {
	it("keeps valid settings as strings", () => {
		expect(normaliseSettings({ bar: 2, button: 12 })).toEqual({ bar: "2", button: "12" });
		expect(normaliseSettings({ bar: "4", button: "12" })).toEqual({ bar: "4", button: "12" });
	});

	it("drops a button the bar does not have", () => {
		expect(normaliseSettings({ bar: "4", button: "13" })).toEqual({ bar: "4" });
		expect(normaliseSettings({ bar: "1", button: "0" })).toEqual({ bar: "1" });
	});

	it("drops an unknown bar and its button", () => {
		expect(normaliseSettings({ bar: "7", button: "1" })).toEqual({});
		expect(normaliseSettings({ bar: "5", button: "12" })).toEqual({ bar: "5", button: "12" });
		expect(normaliseSettings({ button: "1" })).toEqual({});
	});
});

describe("inspector options", () => {
	it("lists five bars", () => {
		expect(barOptionsHTML()).toContain('value="5">Bar 5');
		expect(barOptionsHTML()).not.toContain('value="6"');
	});

	it("lists 12 buttons for every bar", () => {
		const count = (html: string) => (html.match(/value="\d+"/g) ?? []).length;
		expect(count(buttonOptionsHTML("1"))).toBe(12);
		expect(count(buttonOptionsHTML("4"))).toBe(12);
		expect(count(buttonOptionsHTML(undefined))).toBe(0);
		expect(buttonOptionsHTML(undefined)).toContain("Choose a bar first");
	});
});

describe("bindInspector", () => {
	function setup() {
		const bar = new FakeSelect();
		const button = new FakeSelect();
		const save = vi.fn();
		const apply = bindInspector(bar, button, save);
		return { bar, button, save, apply };
	}

	it("starts empty", () => {
		const { bar, button } = setup();
		expect(bar.value).toBe("");
		expect(button.options).toEqual([""]);
	});

	it("shows stored settings", () => {
		const { bar, button, apply } = setup();
		apply({ bar: "2", button: "11" });
		expect(bar.value).toBe("2");
		expect(button.value).toBe("11");
		expect(button.options).toHaveLength(13);
	});

	it("offers all 12 buttons on bar 4", () => {
		const { button, apply } = setup();
		apply({ bar: "4", button: "12" });
		expect(button.value).toBe("12");
		expect(button.options).toHaveLength(13);
	});

	it("drops a stored button that does not exist", () => {
		const { button, apply } = setup();
		apply({ bar: "4", button: "13" });
		expect(button.value).toBe("");
	});

	it("keeps the button when switching bars", () => {
		const { bar, save, apply } = setup();
		apply({ bar: "2", button: "12" });
		bar.choose("4");
		expect(save).toHaveBeenLastCalledWith({ bar: "4", button: "12" });
	});

	it("saves a chosen button", () => {
		const { bar, button, save } = setup();
		bar.choose("3");
		button.choose("9");
		expect(save).toHaveBeenLastCalledWith({ bar: "3", button: "9" });
	});

	it("rejects a button outside the bar if one is forced in", () => {
		const { bar, button, save } = setup();
		bar.choose("4");
		button.choose("13");
		expect(save).toHaveBeenLastCalledWith({ bar: "4" });
		expect(button.value).toBe("");
	});

	it("clears the button when no bar is chosen", () => {
		const { bar, button, save, apply } = setup();
		apply({ bar: "1", button: "3" });
		bar.choose("");
		expect(save).toHaveBeenLastCalledWith({});
		expect(button.options).toEqual([""]);
	});

	it("can clear the bar", () => {
		const { bar, save, apply } = setup();
		apply({ bar: "1", button: "1" });
		bar.choose("");
		expect(save).toHaveBeenLastCalledWith({});
	});
});

describe("connect", () => {
	class FakeWS {
		static last?: FakeWS;
		sent: unknown[] = [];
		onopen: (() => void) | null = null;
		onmessage: ((ev: { data: string }) => void) | null = null;
		constructor(readonly url: string) {
			FakeWS.last = this;
		}
		send(data: string): void {
			this.sent.push(JSON.parse(data));
		}
	}

	function globals() {
		const els: Record<string, FakeSelect> = { bar: new FakeSelect(), button: new FakeSelect() };
		return { els, g: { document: { getElementById: (id: string) => els[id] }, WebSocket: FakeWS } };
	}

	it("registers, shows settings and saves changes", () => {
		const { els, g } = globals();
		connect(g, "28196", "CTX", "registerPropertyInspector", "{}", JSON.stringify({ payload: { settings: { bar: "2", button: "3" } } }));
		const ws = FakeWS.last!;
		expect(ws.url).toBe("ws://127.0.0.1:28196");
		expect(els.bar!.value).toBe("2");
		ws.onopen!();
		expect(ws.sent[0]).toEqual({ event: "registerPropertyInspector", uuid: "CTX" });
		els.button!.choose("7");
		expect(ws.sent[1]).toEqual({ event: "setSettings", context: "CTX", payload: { bar: "2", button: "7" } });
	});

	it("follows settings pushed by Stream Deck and ignores junk", () => {
		const { els, g } = globals();
		connect(g, "1", "CTX", "reg", "{}", "not json");
		const ws = FakeWS.last!;
		ws.onmessage!({ data: JSON.stringify({ event: "didReceiveSettings", payload: { settings: { bar: "4", button: "11" } } }) });
		expect(els.bar!.value).toBe("4");
		expect(els.button!.value).toBe("11");
		ws.onmessage!({ data: "garbage" });
		ws.onmessage!({ data: JSON.stringify({ event: "other" }) });
		ws.onmessage!({ data: JSON.stringify({ event: "didReceiveSettings" }) });
		expect(els.bar!.value).toBe("");
	});
});
