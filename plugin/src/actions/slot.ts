import {
	action,
	type DidReceiveSettingsEvent,
	type KeyDownEvent,
	SingletonAction,
	type WillAppearEvent,
	type WillDisappearEvent,
} from "@elgato/streamdeck";

import type { KeyView, SlotController } from "../slot-controller";
import type { SlotSettings } from "../slots";

type AnyActionEvent = { action: { id: string; isKey(): boolean } };

function view(ev: AnyActionEvent): KeyView | undefined {
	const a = ev.action as unknown as {
		id: string;
		isKey(): boolean;
		setImage(image?: string): Promise<void>;
		showAlert(): Promise<void>;
	};
	if (!a.isKey()) return undefined;
	return { id: a.id, setImage: (image) => a.setImage(image), showAlert: () => a.showAlert() };
}

/** A key that mirrors one action-bar button and presses it in WoW. */
@action({ UUID: "cc.matos.streamdeck.wowbars.slot" })
export class SlotAction extends SingletonAction<SlotSettings> {
	constructor(private readonly controller: SlotController) {
		super();
	}

	override onWillAppear(ev: WillAppearEvent<SlotSettings>): void {
		const v = view(ev);
		if (v) this.controller.appear(v, ev.payload.settings);
	}

	override onWillDisappear(ev: WillDisappearEvent<SlotSettings>): void {
		this.controller.disappear(ev.action.id);
	}

	override onDidReceiveSettings(ev: DidReceiveSettingsEvent<SlotSettings>): void {
		const v = view(ev);
		if (v) this.controller.settingsChanged(v, ev.payload.settings);
	}

	override onKeyDown(ev: KeyDownEvent<SlotSettings>): void {
		const v = view(ev);
		if (v) this.controller.press(v, ev.payload.settings);
	}
}
