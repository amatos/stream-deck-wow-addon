import streamDeck from "@elgato/streamdeck";
import WebSocket from "ws";

import { SlotAction } from "./actions/slot";
import { HelperClient, type Socket } from "./helper-client";
import { DEFAULT_URL } from "./protocol";
import { SlotController } from "./slot-controller";

streamDeck.logger.setLevel("info");

const client = new HelperClient({
	url: DEFAULT_URL,
	createSocket: (url) => new WebSocket(url) as unknown as Socket,
});
const controller = new SlotController(client);

streamDeck.actions.registerAction(new SlotAction(controller));
client.start();
streamDeck.connect();
