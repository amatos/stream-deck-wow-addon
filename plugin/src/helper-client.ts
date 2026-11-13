import { parseHelperMessage, pressMessage } from "./protocol";

/** The subset of a WebSocket the client uses (the `ws` package in the plugin, fakes in tests). */
export interface Socket {
	readonly readyState: number;
	send(data: string): void;
	close(): void;
	on(event: "open", listener: () => void): this;
	on(event: "message", listener: (data: unknown) => void): this;
	on(event: "close", listener: () => void): this;
	on(event: "error", listener: (error: Error) => void): this;
}

export type SocketFactory = (url: string) => Socket;

const OPEN = 1;

export type HelperClientOptions = {
	url: string;
	createSocket: SocketFactory;
	reconnectDelayMs?: number;
	setTimer?: (fn: () => void, ms: number) => unknown;
	clearTimer?: (handle: unknown) => void;
};

/**
 * Keeps a connection to the helper app, caches the latest image per slot and
 * reports changes. Reconnects after the helper goes away.
 */
export class HelperClient {
	readonly images = new Map<number, string>();
	private socket?: Socket;
	private timer?: unknown;
	private stopped = false;
	private readonly listeners = new Set<(slot: number, image: string | undefined) => void>();
	private readonly reconnectDelayMs: number;
	private readonly setTimer: (fn: () => void, ms: number) => unknown;
	private readonly clearTimer: (handle: unknown) => void;

	constructor(private readonly options: HelperClientOptions) {
		this.reconnectDelayMs = options.reconnectDelayMs ?? 2000;
		this.setTimer = options.setTimer ?? ((fn, ms) => setTimeout(fn, ms));
		this.clearTimer = options.clearTimer ?? ((h) => clearTimeout(h as ReturnType<typeof setTimeout>));
	}

	get connected(): boolean {
		return this.socket?.readyState === OPEN;
	}

	/** Listens for image changes. `image` is undefined when the helper disconnects. */
	onImage(listener: (slot: number, image: string | undefined) => void): () => void {
		this.listeners.add(listener);
		return () => this.listeners.delete(listener);
	}

	start(): void {
		this.stopped = false;
		this.connect();
	}

	stop(): void {
		this.stopped = true;
		if (this.timer !== undefined) this.clearTimer(this.timer);
		this.timer = undefined;
		this.socket?.close();
		this.socket = undefined;
	}

	/** Reports a key press. Returns false when not connected. */
	press(slot: number): boolean {
		if (!this.connected) return false;
		this.socket!.send(pressMessage(slot));
		return true;
	}

	private connect(): void {
		if (this.stopped) return;
		let socket: Socket;
		try {
			socket = this.options.createSocket(this.options.url);
		} catch {
			this.scheduleReconnect();
			return;
		}
		this.socket = socket;
		socket.on("message", (data) => this.handle(String(data)));
		socket.on("close", () => this.dropped(socket));
		socket.on("error", () => {
			/* A close event follows. */
		});
	}

	private handle(text: string): void {
		const message = parseHelperMessage(text);
		if (message?.type !== "slot") return;
		if (this.images.get(message.slot) === message.image) return;
		this.images.set(message.slot, message.image);
		for (const l of this.listeners) l(message.slot, message.image);
	}

	private dropped(socket: Socket): void {
		if (socket !== this.socket) return;
		this.socket = undefined;
		const slots = [...this.images.keys()];
		this.images.clear();
		for (const slot of slots) for (const l of this.listeners) l(slot, undefined);
		this.scheduleReconnect();
	}

	private scheduleReconnect(): void {
		if (this.stopped || this.timer !== undefined) return;
		this.timer = this.setTimer(() => {
			this.timer = undefined;
			this.connect();
		}, this.reconnectDelayMs);
	}
}
