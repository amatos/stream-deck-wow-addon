import { describe, expect, it, vi } from "vitest";

import { HelperClient } from "../src/helper-client";
import { DEFAULT_URL, parseHelperMessage, pressMessage } from "../src/protocol";
import { type KeyView, SlotController } from "../src/slot-controller";
import { buttonsFor, normaliseSettings, slotIndex } from "../src/slots";
import { Harness } from "./fakes";

describe("slotIndex", () => {
	it("maps bar and button to strip slots", () => {
		expect(slotIndex({ bar: 1, button: 1 })).toBe(0);
		expect(slotIndex({ bar: 1, button: 12 })).toBe(11);
		expect(slotIndex({ bar: 2, button: 1 })).toBe(12);
		expect(slotIndex({ bar: 3, button: 12 })).toBe(35);
		expect(slotIndex({ bar: 4, button: 1 })).toBe(36);
		expect(slotIndex({ bar: 4, button: 12 })).toBe(47);
		expect(slotIndex({ bar: 5, button: 1 })).toBe(48);
		expect(slotIndex({ bar: 5, button: 12 })).toBe(59);
	});

	it("knows how many buttons each bar has", () => {
		expect(buttonsFor(4)).toBe(12);
		expect(buttonsFor("2")).toBe(12);
		expect(buttonsFor(5)).toBe(12);
		expect(buttonsFor(6)).toBe(0);
		expect(buttonsFor(undefined)).toBe(0);
	});

	it("accepts the property inspector's string values", () => {
		expect(slotIndex({ bar: "2", button: "5" })).toBe(16);
	});

	it("is undefined when unset or out of range", () => {
		expect(slotIndex(undefined)).toBeUndefined();
		expect(slotIndex({})).toBeUndefined();
		expect(slotIndex({ bar: 1 })).toBeUndefined();
		expect(slotIndex({ bar: 6, button: 1 })).toBeUndefined();
		expect(slotIndex({ bar: 1, button: 13 })).toBeUndefined();
		expect(slotIndex({ bar: 0, button: 1 })).toBeUndefined();
		expect(slotIndex({ bar: "x", button: "1" })).toBeUndefined();
		expect(slotIndex({ bar: 1.5, button: 1 })).toBeUndefined();
	});
});

describe("protocol", () => {
	it("uses the helper's loopback port", () => {
		expect(DEFAULT_URL).toBe("ws://127.0.0.1:47811");
	});

	it("parses hello and slot messages", () => {
		expect(parseHelperMessage('{"type":"hello","version":1}')).toEqual({ type: "hello", version: 1 });
		expect(parseHelperMessage('{"type":"slot","slot":59,"image":"data:x"}')).toEqual({
			type: "slot",
			slot: 59,
			image: "data:x",
		});
	});

	it("rejects malformed messages", () => {
		for (const text of [
			"nope",
			"null",
			"5",
			'{"type":"hello"}',
			'{"type":"slot","slot":60,"image":"x"}',
			'{"type":"slot","slot":-1,"image":"x"}',
			'{"type":"slot","slot":1.5,"image":"x"}',
			'{"type":"slot","slot":1}',
			'{"type":"press","slot":1}',
		]) {
			expect(parseHelperMessage(text), text).toBeUndefined();
		}
	});

	it("formats press messages", () => {
		expect(JSON.parse(pressMessage(7))).toEqual({ type: "press", slot: 7 });
	});
});

function setup() {
	const h = new Harness();
	const client = new HelperClient({
		url: "ws://test",
		createSocket: h.createSocket,
		reconnectDelayMs: 500,
		setTimer: h.setTimer,
		clearTimer: h.clearTimer,
	});
	return { h, client };
}

describe("HelperClient", () => {
	it("connects and caches slot images", () => {
		const { h, client } = setup();
		const seen = vi.fn();
		client.onImage(seen);
		client.start();
		expect(h.last.url).toBe("ws://test");
		h.last.open();
		expect(client.connected).toBe(true);
		h.last.receive({ type: "hello", version: 1 });
		h.last.receive({ type: "slot", slot: 3, image: "A" });
		expect(client.images.get(3)).toBe("A");
		expect(seen).toHaveBeenCalledWith(3, "A");
	});

	it("ignores repeated images and junk", () => {
		const { h, client } = setup();
		const seen = vi.fn();
		client.onImage(seen);
		client.start();
		h.last.open();
		h.last.receive({ type: "slot", slot: 3, image: "A" });
		h.last.receive({ type: "slot", slot: 3, image: "A" });
		h.last.receive("garbage");
		expect(seen).toHaveBeenCalledTimes(1);
	});

	it("sends presses only while connected", () => {
		const { h, client } = setup();
		client.start();
		expect(client.press(1)).toBe(false);
		h.last.open();
		expect(client.press(12)).toBe(true);
		expect(h.last.sent).toEqual([pressMessage(12)]);
	});

	it("clears images and reconnects when the helper goes away", () => {
		const { h, client } = setup();
		const seen = vi.fn();
		client.onImage(seen);
		client.start();
		h.last.open();
		h.last.receive({ type: "slot", slot: 5, image: "B" });
		h.last.fail();
		expect(client.connected).toBe(false);
		expect(client.images.size).toBe(0);
		expect(seen).toHaveBeenLastCalledWith(5, undefined);
		expect(h.timers).toHaveLength(1);
		expect(h.timers[0]!.ms).toBe(500);
		h.runTimers();
		expect(h.sockets).toHaveLength(2);
	});

	it("retries when the socket cannot be created", () => {
		const { h, client } = setup();
		h.failNextCreate = true;
		client.start();
		expect(h.sockets).toHaveLength(0);
		expect(h.timers).toHaveLength(1);
		h.runTimers();
		expect(h.sockets).toHaveLength(1);
	});

	it("schedules only one reconnect at a time", () => {
		const { h, client } = setup();
		h.failNextCreate = true;
		client.start();
		(client as unknown as { scheduleReconnect(): void }).scheduleReconnect();
		expect(h.timers).toHaveLength(1);
	});

	it("stops cleanly and does not reconnect", () => {
		const { h, client } = setup();
		client.start();
		h.last.open();
		h.last.fail();
		const pending = h.timers[0]!;
		client.stop();
		expect(pending.cleared).toBe(true);
		h.runTimers();
		expect(h.sockets).toHaveLength(1);
		client.start();
		expect(h.sockets).toHaveLength(2);
		client.stop();
		expect(h.last.closed).toBe(true);
		expect(h.timers).toHaveLength(0);
	});

	it("ignores close events from replaced sockets", () => {
		const { h, client } = setup();
		client.start();
		const first = h.last;
		first.open();
		first.fail();
		h.runTimers();
		h.last.open();
		h.last.receive({ type: "slot", slot: 1, image: "C" });
		first.close();
		expect(client.images.get(1)).toBe("C");
	});

	it("can remove listeners", () => {
		const { h, client } = setup();
		const seen = vi.fn();
		const off = client.onImage(seen);
		off();
		client.start();
		h.last.open();
		h.last.receive({ type: "slot", slot: 3, image: "A" });
		expect(seen).not.toHaveBeenCalled();
	});

	it("defaults to real timers", () => {
		vi.useFakeTimers();
		try {
			const h = new Harness();
			h.failNextCreate = true;
			const client = new HelperClient({ url: "ws://x", createSocket: h.createSocket });
			client.start();
			vi.advanceTimersByTime(1999);
			expect(h.sockets).toHaveLength(0);
			vi.advanceTimersByTime(1);
			expect(h.sockets).toHaveLength(1);
			h.last.fail();
			client.stop();
			vi.advanceTimersByTime(5000);
			expect(h.sockets).toHaveLength(1);
		} finally {
			vi.useRealTimers();
		}
	});
});

function key(id: string): KeyView & { images: (string | undefined)[]; alerts: number } {
	const k = {
		id,
		images: [] as (string | undefined)[],
		alerts: 0,
		setImage(image: string | undefined) {
			k.images.push(image);
		},
		showAlert() {
			k.alerts += 1;
		},
	};
	return k;
}

describe("SlotController", () => {
	function connected() {
		const { h, client } = setup();
		const controller = new SlotController(client);
		client.start();
		h.last.open();
		return { h, client, controller };
	}

	it("shows the cached image when a key appears", () => {
		const { h, controller } = connected();
		h.last.receive({ type: "slot", slot: 12, image: "IMG" });
		const k = key("a");
		controller.appear(k, { bar: 2, button: 1 });
		expect(k.images).toEqual(["IMG"]);
		expect(controller.visibleCount).toBe(1);
	});

	it("shows the default image for unconfigured or unknown slots", () => {
		const { controller } = connected();
		const k = key("a");
		controller.appear(k, {});
		controller.appear(key("b"), { bar: 1, button: 2 });
		expect(k.images).toEqual([undefined]);
	});

	it("updates visible keys showing a changed slot", () => {
		const { h, controller } = connected();
		const a = key("a");
		const b = key("b");
		controller.appear(a, { bar: 1, button: 1 });
		controller.appear(b, { bar: 1, button: 2 });
		h.last.receive({ type: "slot", slot: 0, image: "X" });
		expect(a.images).toEqual([undefined, "X"]);
		expect(b.images).toEqual([undefined]);
	});

	it("stops updating keys that disappear", () => {
		const { h, controller } = connected();
		const a = key("a");
		controller.appear(a, { bar: 1, button: 1 });
		controller.disappear("a");
		h.last.receive({ type: "slot", slot: 0, image: "X" });
		expect(a.images).toEqual([undefined]);
		expect(controller.visibleCount).toBe(0);
	});

	it("follows settings changes", () => {
		const { h, controller } = connected();
		h.last.receive({ type: "slot", slot: 24, image: "BAR3" });
		const a = key("a");
		controller.appear(a, { bar: 1, button: 1 });
		controller.settingsChanged(a, { bar: 3, button: 1 });
		expect(a.images).toEqual([undefined, "BAR3"]);
	});

	it("forwards presses for configured keys", () => {
		const { h, controller } = connected();
		const a = key("a");
		controller.press(a, { bar: 2, button: 12 });
		expect(h.last.sent).toEqual([pressMessage(23)]);
		expect(a.alerts).toBe(0);
	});

	it("alerts when a press cannot be delivered", () => {
		const { h, controller } = connected();
		const a = key("a");
		controller.press(a, {});
		h.last.fail();
		controller.press(a, { bar: 1, button: 1 });
		expect(a.alerts).toBe(2);
	});
});
