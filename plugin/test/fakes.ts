import type { Socket } from "../src/helper-client";

/** A controllable stand-in for a WebSocket. */
export class FakeSocket implements Socket {
	readyState = 0;
	sent: string[] = [];
	closed = false;
	private handlers: Record<string, ((arg?: unknown) => void)[]> = {};

	constructor(readonly url: string) {}

	on(event: string, listener: (...args: any[]) => void): this {
		(this.handlers[event] ??= []).push(listener as (arg?: unknown) => void);
		return this;
	}

	send(data: string): void {
		this.sent.push(data);
	}

	close(): void {
		this.closed = true;
		this.emitClose();
	}

	open(): void {
		this.readyState = 1;
		this.emit("open");
	}

	receive(message: unknown): void {
		this.emit("message", Buffer.from(typeof message === "string" ? message : JSON.stringify(message)));
	}

	fail(): void {
		this.emit("error", new Error("boom"));
		this.emitClose();
	}

	private emitClose(): void {
		if (this.readyState === 3) return;
		this.readyState = 3;
		this.emit("close");
	}

	private emit(event: string, arg?: unknown): void {
		for (const h of this.handlers[event] ?? []) h(arg);
	}
}

/** Collects sockets and timers so tests can drive reconnects by hand. */
export class Harness {
	sockets: FakeSocket[] = [];
	timers: { fn: () => void; ms: number; cleared: boolean }[] = [];
	failNextCreate = false;

	createSocket = (url: string): Socket => {
		if (this.failNextCreate) {
			this.failNextCreate = false;
			throw new Error("refused");
		}
		const s = new FakeSocket(url);
		this.sockets.push(s);
		return s;
	};

	setTimer = (fn: () => void, ms: number): unknown => {
		const t = { fn, ms, cleared: false };
		this.timers.push(t);
		return t;
	};

	clearTimer = (handle: unknown): void => {
		(handle as { cleared: boolean }).cleared = true;
	};

	get last(): FakeSocket {
		return this.sockets[this.sockets.length - 1]!;
	}

	runTimers(): void {
		const due = this.timers.filter((t) => !t.cleared);
		this.timers = [];
		for (const t of due) t.fn();
	}
}
