// Browser entry for the property inspector (bundled to ui/inspector.js).
import { connect } from "./inspector";

(globalThis as Record<string, unknown>).connectElgatoStreamDeckSocket = (
	port: string,
	uuid: string,
	registerEvent: string,
	info: string,
	actionInfo: string,
) => connect(globalThis as never, port, uuid, registerEvent, info, actionInfo);
